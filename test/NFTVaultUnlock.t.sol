// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {MockRouter} from "./mocks/MockRouter.sol";
import {ProviderNFT} from "../src/ProviderNFT.sol";
import {NFTVault} from "../src/NFTVault.sol";

contract NFTVaultUnlockTest is Test {
    ProviderNFT public providerNft;
    NFTVault public nftVault;
    MockRouter public mockRouter;

    uint64 sourceChainSelector = 12345;
    address wrappedNftContract = address(0xCAFE);
    address recipient = makeAddr("recipient");

    uint256 tokenId = 0;
    address user = makeAddr("user");

    function setUp() public {
        mockRouter = new MockRouter();

        vm.startPrank(user);
        providerNft = new ProviderNFT("AwesomeNFT", "ANFT");
        nftVault = new NFTVault(address(mockRouter), address(providerNft));
        vm.stopPrank();

        vm.deal(user, 10 ether);

        // allowlist destination so deposit works
        vm.startPrank(user);
        nftVault.allowlistDestinationChain(sourceChainSelector, true);
        nftVault.allowlistSourceChain(sourceChainSelector, true);
        nftVault.allowlistSender(wrappedNftContract, true);
        vm.stopPrank();

        // lock the NFT in the vault
        mockRouter.setFee(1000);
        vm.startPrank(user);
        providerNft.approve(address(nftVault), tokenId);
        nftVault.deposit{value: 1000}(tokenId, address(0xDEAD), sourceChainSelector);
        vm.stopPrank();
    }

    function _buildBurnMessage(uint256 _tokenId, address _recipient) private view returns (Client.Any2EVMMessage memory) {
        bytes memory payload = abi.encode(_tokenId, _recipient);

        return Client.Any2EVMMessage({
            messageId: keccak256("burn"),
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(wrappedNftContract),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    function test_unlock_transfersNftToRecipient() public {
        assertEq(providerNft.ownerOf(tokenId), address(nftVault));

        vm.prank(address(mockRouter));
        nftVault.ccipReceive(_buildBurnMessage(tokenId, recipient));

        assertEq(providerNft.ownerOf(tokenId), recipient);
    }

    function test_unlock_sourceChainNotAllowlistedReverts() public {
        uint64 badChain = 99999;

        Client.Any2EVMMessage memory msg_ = Client.Any2EVMMessage({
            messageId: keccak256("burn"),
            sourceChainSelector: badChain,
            sender: abi.encode(wrappedNftContract),
            data: abi.encode(tokenId, recipient),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(mockRouter));
        vm.expectRevert(
            abi.encodeWithSelector(NFTVault.SourceChainNotAllowlisted.selector, badChain)
        );
        nftVault.ccipReceive(msg_);
    }

    function test_unlock_senderNotAllowlistedReverts() public {
        address badSender = address(0xBAD);

        Client.Any2EVMMessage memory msg_ = Client.Any2EVMMessage({
            messageId: keccak256("burn"),
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(badSender),
            data: abi.encode(tokenId, recipient),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(mockRouter));
        vm.expectRevert(
            abi.encodeWithSelector(NFTVault.SenderNotAllowlisted.selector, badSender)
        );
        nftVault.ccipReceive(msg_);
    }
}
