// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/OwnerIsCreator.sol";

import {ERC721} from "@openzeppelin/contracts/token/erc721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/erc721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/erc721/extensions/IERC721Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiver.sol";

contract WrappedNFT is ERC721, OwnerIsCreator, CCIPReceiver {
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SenderNotAllowlisted(address sender);
    error InvalidReceiverAddress();
    error NotOwner(address caller, uint256 tokenId);
    error NotEnoughBalance(uint256 sent, uint256 required);
    error RefundFailed(address receiver, uint256 amount);

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;

    mapping(uint256 => string) public tokenUriMapping;
    // tracks which vault on the source chain locked each token
    mapping(uint256 => address) public tokenSourceVault;

    event MintMessageReceived(
        bytes32 messageId, uint64 sourceChainSelector, address sourceVault, uint256 tokenId, address owner
    );
    event BurnMessageSent(
        bytes32 messageId, uint64 destinationChainSelector, address vault, uint256 tokenId, address recipient
    );

    constructor(string memory _name, string memory _symbol, address _router)
        ERC721(_name, _symbol)
        CCIPReceiver(_router)
    {}

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        }
        _;
    }

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector]) {
            revert SourceChainNotAllowlisted(_sourceChainSelector);
        }
        if (!allowlistedSenders[_sender]) revert SenderNotAllowlisted(_sender);
        _;
    }

    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        address sourceVault = abi.decode(any2EvmMessage.sender, (address));

        (string memory tokenUri, uint256 tokenId, address originalOwner,) =
            abi.decode(any2EvmMessage.data, (string, uint256, address, address));

        emit MintMessageReceived(
            any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, sourceVault, tokenId, originalOwner
        );

        _mint(originalOwner, tokenId);
        tokenUriMapping[tokenId] = tokenUri;
        tokenSourceVault[tokenId] = sourceVault;
    }

    function burn(uint256 tokenId, address recipient, uint64 destinationChainSelector)
        external
        payable
        onlyAllowlistedDestinationChain(destinationChainSelector)
        validateReceiver(recipient)
    {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner(msg.sender, tokenId);

        address vault = tokenSourceVault[tokenId];

        _burn(tokenId);
        delete tokenUriMapping[tokenId];
        delete tokenSourceVault[tokenId];

        bytes memory payload = abi.encode(tokenId, recipient);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(vault),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    // 300k: safeTransferFrom is cheap but CCIP enforces a minimum
                    // and adds overhead on top of execution gas
                    gasLimit: 300_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(0)
        });

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 fees = router.getFee(destinationChainSelector, message);
        if (msg.value < fees) revert NotEnoughBalance(msg.value, fees);

        bytes32 messageId = router.ccipSend{value: fees}(destinationChainSelector, message);

        emit BurnMessageSent(messageId, destinationChainSelector, vault, tokenId, recipient);

        uint256 refund = msg.value - fees;
        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundFailed(msg.sender, refund);
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return tokenUriMapping[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override(CCIPReceiver, ERC721) returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId
            || interfaceId == type(IAny2EVMMessageReceiver).interfaceId;
    }
}
