// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {MockRouter} from "./mocks/MockRouter.sol";
import {ProviderNFT} from "../src/ProviderNFT.sol";
import {NFTVault} from "../src/NFTVault.sol";
import {WrappedNFT} from "../src/WrappedNFT.sol";

/// Tests the full lock → mint → burn → unlock round trip.
/// Two MockRouters simulate the two chains; message delivery is manual.
contract RoundTripTest is Test {
    ProviderNFT public providerNft;
    NFTVault public vault;
    WrappedNFT public wrappedNft;

    MockRouter public sourceRouter;
    MockRouter public destRouter;

    uint64 constant SOURCE_CHAIN = 1;
    uint64 constant DEST_CHAIN = 2;

    uint256 tokenId = 0;
    address user = makeAddr("user");

    function setUp() public {
        sourceRouter = new MockRouter();
        destRouter = new MockRouter();

        vm.startPrank(user);
        providerNft = new ProviderNFT("AwesomeNFT", "ANFT");
        vault = new NFTVault(address(sourceRouter), address(providerNft));
        wrappedNft = new WrappedNFT("WrappedAwesomeNFT", "WANFT", address(destRouter));
        vm.stopPrank();

        // source chain: vault accepts messages from wrappedNft on DEST_CHAIN
        vm.startPrank(user);
        vault.allowlistDestinationChain(DEST_CHAIN, true);
        vault.allowlistSourceChain(DEST_CHAIN, true);
        vault.allowlistSender(address(wrappedNft), true);
        vm.stopPrank();

        // dest chain: wrappedNft accepts messages from vault on SOURCE_CHAIN, sends back to SOURCE_CHAIN
        vm.startPrank(user);
        wrappedNft.allowlistSourceChain(SOURCE_CHAIN, true);
        wrappedNft.allowlistSender(address(vault), true);
        wrappedNft.allowlistDestinationChain(SOURCE_CHAIN, true);
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    function test_roundTrip() public {
        // ── Step 1: user locks NFT and sends CCIP message to dest chain ──────
        uint256 depositFee = 1000;
        sourceRouter.setFee(depositFee);

        vm.startPrank(user);
        providerNft.approve(address(vault), tokenId);
        vault.deposit{value: depositFee}(tokenId, user, DEST_CHAIN);
        vm.stopPrank();

        assertEq(providerNft.ownerOf(tokenId), address(vault), "NFT not locked");

        // ── Step 2: relay deposit message to dest chain (manual delivery) ────
        string memory tokenUri = providerNft.tokenURI(tokenId);
        bytes memory depositPayload = abi.encode(tokenUri, tokenId, user, address(providerNft));

        Client.Any2EVMMessage memory depositMsg = Client.Any2EVMMessage({
            messageId: keccak256("deposit"),
            sourceChainSelector: SOURCE_CHAIN,
            sender: abi.encode(address(vault)),
            data: depositPayload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(destRouter));
        wrappedNft.ccipReceive(depositMsg);

        assertEq(wrappedNft.ownerOf(tokenId), user, "wrapped NFT not minted to user");
        assertEq(wrappedNft.tokenURI(tokenId), tokenUri, "wrong tokenURI on wrapped NFT");
        assertEq(wrappedNft.tokenSourceVault(tokenId), address(vault), "wrong source vault tracked");

        // ── Step 3: user burns wrapped NFT, sends unlock message to source chain
        uint256 burnFee = 2000;
        destRouter.setFee(burnFee);
        vm.deal(user, burnFee);

        vm.prank(user);
        wrappedNft.burn{value: burnFee}(tokenId, user, SOURCE_CHAIN);

        vm.expectRevert();
        wrappedNft.ownerOf(tokenId); // token no longer exists

        // ── Step 4: relay burn message to source chain (manual delivery) ─────
        bytes memory burnPayload = abi.encode(tokenId, user);

        Client.Any2EVMMessage memory burnMsg = Client.Any2EVMMessage({
            messageId: keccak256("burn"),
            sourceChainSelector: DEST_CHAIN,
            sender: abi.encode(address(wrappedNft)),
            data: burnPayload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(sourceRouter));
        vault.ccipReceive(burnMsg);

        assertEq(providerNft.ownerOf(tokenId), user, "NFT not returned to user");
    }
}
