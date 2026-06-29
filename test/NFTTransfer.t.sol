// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {MockRouter} from "./mocks/MockRouter.sol";

import {ProviderNFT} from "../src/ProviderNFT.sol";
import {NFTVault} from "../src/NFTVault.sol";

contract NFTTransferTest is Test {
    ProviderNFT public providerNft;
    NFTVault public nftVault;
    MockRouter public mockRouter;

    string nftName = "AwesomeNFT";
    string nftSymbol = "ANFT";
    uint256 firstTokenId = 0;

    address user = makeAddr("user");

    function setUp() public {
        mockRouter = new MockRouter();

        vm.startPrank(user);
        providerNft = new ProviderNFT(nftName, nftSymbol);
        nftVault = new NFTVault(address(mockRouter), address(providerNft));
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    function setAllowlist(uint64 destinationChainId) private {
        vm.prank(user);
        nftVault.allowlistSourceChain(destinationChainId, true);

        vm.prank(user);
        nftVault.allowlistDestinationChain(destinationChainId, true);
    }

    function test_correctOwner() public {
        vm.prank(user);
        assert(providerNft.ownerOf(firstTokenId) == user);
    }

    function test_destinationChainNotSupported() public {
        uint64 destinationChainId = 0;
        vm.expectRevert(abi.encodeWithSelector(NFTVault.DestinationChainNotAllowlisted.selector, destinationChainId));
        nftVault.deposit(firstTokenId, address(0), destinationChainId);
    }

    function test_notOwner() public {
        uint64 destinationChainId = 0;
        setAllowlist(destinationChainId);
        vm.expectRevert(abi.encodeWithSelector(NFTVault.NotOwner.selector, address(this), firstTokenId));
        nftVault.deposit(firstTokenId, address(0xdead), 0);
    }

    function test_notApproved() public {
        uint64 destinationChainId = 0;
        setAllowlist(destinationChainId);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NFTVault.NotApproved.selector, firstTokenId, address(nftVault), address(providerNft))
        );
        nftVault.deposit(firstTokenId, address(0xdead), 0);
    }

    function test_notEnoughBalance() public {
        uint64 destinationChainId = 0;
        setAllowlist(destinationChainId);

        vm.prank(user);
        providerNft.approve(address(nftVault), firstTokenId);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NFTVault.NotEnoughBalance.selector, 0, 0));
        nftVault.deposit(firstTokenId, address(0xdead), 0);
    }

    function test_successfullyDeposited() public {
        uint64 destinationChainId = 0;
        setAllowlist(destinationChainId);

        address receiver = address(0xdeadbeef);
        uint64 destinationChainSelector = 0;

        vm.prank(user);
        providerNft.approve(address(nftVault), firstTokenId);

        string memory tokenUri = providerNft.tokenURI(firstTokenId);

        bytes memory payload = abi.encode(tokenUri, firstTokenId, address(user), address(providerNft));

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = nftVault.buildCCIPMessage(receiver, payload, address(0));
        mockRouter.setFee(1337);
        uint256 fees = nftVault.getCCIPMessageFee(destinationChainSelector, evm2AnyMessage);

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);
        nftVault.deposit{value: fees + 1 ether}(firstTokenId, receiver, destinationChainSelector);

        assertEq(user.balance, userBalanceBefore - fees);
        assertEq(providerNft.ownerOf(firstTokenId), address(nftVault));

        assert(providerNft.ownerOf(firstTokenId) == address(nftVault));
    }
}
