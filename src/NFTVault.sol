// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/OwnerIsCreator.sol";

import {ERC721} from "@openzeppelin/contracts/token/erc721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NFTVault is CCIPReceiver, OwnerIsCreator, IERC721Receiver {
    error NotApproved(uint256 tokenId, address operator, address nft_contract);
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NotOwner(address _address, uint256 tokenId);
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SenderNotAllowlisted(address sender);
    error InvalidReceiverAddress();
    error RefundFailed(address receiver, uint256 amount);

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        bytes payload,
        uint256 fees
    );

    event NFTUnlocked(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 tokenId,
        address recipient
    );

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;

    ERC721 public nft_contract;

    constructor(address _router, address _nftContract) CCIPReceiver(_router) {
        nft_contract = ERC721(_nftContract);
    }

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

    function deposit(uint256 tokenId, address receiver, uint64 destinationChainSelector)
        public
        payable
        onlyAllowlistedDestinationChain(destinationChainSelector)
        validateReceiver(receiver)
        returns (bytes32 messageId)
    {
        if (msg.sender != nft_contract.ownerOf(tokenId)) {
            revert NotOwner(msg.sender, tokenId);
        }
        if (nft_contract.getApproved(tokenId) != address(this)) {
            revert NotApproved(tokenId, address(this), address(nft_contract));
        }

        string memory tokenUri = nft_contract.tokenURI(tokenId);

        bytes memory payload = abi.encode(tokenUri, tokenId, msg.sender, address(nft_contract));

        Client.EVM2AnyMessage memory evm2AnyMessage = buildCCIPMessage(receiver, payload, address(0));
        uint256 fees = getCCIPMessageFee(destinationChainSelector, evm2AnyMessage);
        if (fees == 0 || msg.value < fees) {
            revert NotEnoughBalance(msg.value, fees);
        }

        nft_contract.safeTransferFrom(msg.sender, address(this), tokenId);

        IRouterClient router = IRouterClient(this.getRouter());
        messageId = router.ccipSend{value: fees}(destinationChainSelector, evm2AnyMessage);

        emit MessageSent(messageId, destinationChainSelector, receiver, payload, fees);

        uint256 refundAmount = msg.value - fees;
        if (refundAmount > 0) {
            (bool success,) = msg.sender.call{value: refundAmount}("");
            if (!success) revert RefundFailed(msg.sender, refundAmount);
        }

        return messageId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (uint256 tokenId, address recipient) = abi.decode(any2EvmMessage.data, (uint256, address));

        emit NFTUnlocked(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            tokenId,
            recipient
        );

        nft_contract.safeTransferFrom(address(this), recipient, tokenId);
    }

    function buildCCIPMessage(address _receiver, bytes memory _payload, address _feeTokenAddress)
        public
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: _payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    // _mint + two SSTOREs (tokenUriMapping + tokenSourceVault) + a long URI string
                    // can easily exceed 200k; 500k gives comfortable headroom
                    gasLimit: 500_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: _feeTokenAddress
        });
    }

    function getCCIPMessageFee(uint64 _destinationChainSelector, Client.EVM2AnyMessage memory evm2AnyMessage)
        public
        view
        returns (uint256 fees)
    {
        IRouterClient router = IRouterClient(this.getRouter());
        fees = router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
