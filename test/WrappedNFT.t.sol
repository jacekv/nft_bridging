// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {MockRouter} from "./mocks/MockRouter.sol";
import {WrappedNFT} from "../src/WrappedNFT.sol";

contract WrappedNFTTest is Test {
    WrappedNFT public wrappedNft;
    MockRouter public mockRouter;

    uint64 sourceChainSelector = 12345;
    address sourceVault = address(0xCAFE);
    address originalOwner = makeAddr("originalOwner");
    address sourceNftContract = address(0xBEEF);

    uint256 tokenId = 0;
    string tokenUri = "https://example.com/nft/0";

    address owner = makeAddr("owner");

    function setUp() public {
        mockRouter = new MockRouter();

        vm.prank(owner);
        wrappedNft = new WrappedNFT("WrappedAwesomeNFT", "WANFT", address(mockRouter));
    }

    function _allowlist() private {
        vm.startPrank(owner);
        wrappedNft.allowlistSourceChain(sourceChainSelector, true);
        wrappedNft.allowlistSender(sourceVault, true);
        vm.stopPrank();
    }

    function _buildMessage() private view returns (Client.Any2EVMMessage memory) {
        bytes memory payload = abi.encode(tokenUri, tokenId, originalOwner, sourceNftContract);

        return Client.Any2EVMMessage({
            messageId: keccak256("test"),
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(sourceVault),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    function test_mintToOriginalOwner() public {
        _allowlist();

        vm.prank(address(mockRouter));
        wrappedNft.ccipReceive(_buildMessage());

        assertEq(wrappedNft.ownerOf(tokenId), originalOwner);
    }

    function test_tokenUriSetCorrectly() public {
        _allowlist();

        vm.prank(address(mockRouter));
        wrappedNft.ccipReceive(_buildMessage());

        assertEq(wrappedNft.tokenURI(tokenId), tokenUri);
    }

    function test_sourceChainNotAllowlisted() public {
        vm.prank(address(mockRouter));
        vm.expectRevert(abi.encodeWithSelector(WrappedNFT.SourceChainNotAllowlisted.selector, sourceChainSelector));
        wrappedNft.ccipReceive(_buildMessage());
    }

    function test_senderNotAllowlisted() public {
        vm.prank(owner);
        wrappedNft.allowlistSourceChain(sourceChainSelector, true);

        vm.prank(address(mockRouter));
        vm.expectRevert(abi.encodeWithSelector(WrappedNFT.SenderNotAllowlisted.selector, sourceVault));
        wrappedNft.ccipReceive(_buildMessage());
    }

    function test_mintEventEmitted() public {
        _allowlist();

        vm.expectEmit(false, false, false, true, address(wrappedNft));
        emit WrappedNFT.MintMessageReceived(keccak256("test"), sourceChainSelector, sourceVault, tokenId, originalOwner);

        vm.prank(address(mockRouter));
        wrappedNft.ccipReceive(_buildMessage());
    }

    function test_sourceVaultTracked() public {
        _allowlist();

        vm.prank(address(mockRouter));
        wrappedNft.ccipReceive(_buildMessage());

        assertEq(wrappedNft.tokenSourceVault(tokenId), sourceVault);
    }

    // ── burn tests ──────────────────────────────────────────────────────────

    function _mintToken() private {
        _allowlist();
        vm.prank(address(mockRouter));
        wrappedNft.ccipReceive(_buildMessage());
    }

    function _allowlistBurnDestination(uint64 chainSel) private {
        vm.prank(owner);
        wrappedNft.allowlistDestinationChain(chainSel, true);
    }

    function test_burn_removesToken() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        uint256 burnFee = 1337;
        mockRouter.setFee(burnFee);
        vm.deal(originalOwner, burnFee);

        vm.prank(originalOwner);
        wrappedNft.burn{value: burnFee}(tokenId, originalOwner, destChain);

        vm.expectRevert();
        wrappedNft.ownerOf(tokenId);
    }

    function test_burn_clearsTokenUri() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        uint256 burnFee = 1337;
        mockRouter.setFee(burnFee);
        vm.deal(originalOwner, burnFee);

        vm.prank(originalOwner);
        wrappedNft.burn{value: burnFee}(tokenId, originalOwner, destChain);

        assertEq(wrappedNft.tokenUriMapping(tokenId), "");
    }

    function test_burn_sendsCCIPMessage() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        uint256 burnFee = 1337;
        mockRouter.setFee(burnFee);
        vm.deal(originalOwner, burnFee);

        vm.prank(originalOwner);
        wrappedNft.burn{value: burnFee}(tokenId, originalOwner, destChain);

        assertEq(mockRouter.lastDestinationChainSelector(), destChain);
        (uint256 decodedTokenId, address decodedRecipient) = abi.decode(mockRouter.lastData(), (uint256, address));
        assertEq(decodedTokenId, tokenId);
        assertEq(decodedRecipient, originalOwner);
    }

    function test_burn_refundsExcess() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        uint256 burnFee = 1337;
        uint256 excess = 1 ether;
        mockRouter.setFee(burnFee);
        vm.deal(originalOwner, burnFee + excess);

        uint256 balanceBefore = originalOwner.balance;
        vm.prank(originalOwner);
        wrappedNft.burn{value: burnFee + excess}(tokenId, originalOwner, destChain);

        assertEq(originalOwner.balance, balanceBefore - burnFee);
    }

    function test_burn_notOwnerReverts() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        address notOwner = makeAddr("notOwner");
        vm.deal(notOwner, 1 ether);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(WrappedNFT.NotOwner.selector, notOwner, tokenId));
        wrappedNft.burn{value: 1 ether}(tokenId, notOwner, destChain);
    }

    function test_burn_destinationChainNotAllowlistedReverts() public {
        _mintToken();

        uint64 destChain = sourceChainSelector;
        vm.deal(originalOwner, 1 ether);

        vm.prank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(WrappedNFT.DestinationChainNotAllowlisted.selector, destChain));
        wrappedNft.burn{value: 1 ether}(tokenId, originalOwner, destChain);
    }

    function test_burn_notEnoughFeeReverts() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        uint256 burnFee = 1337;
        mockRouter.setFee(burnFee);
        vm.deal(originalOwner, burnFee - 1);

        vm.prank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(WrappedNFT.NotEnoughBalance.selector, burnFee - 1, burnFee));
        wrappedNft.burn{value: burnFee - 1}(tokenId, originalOwner, destChain);
    }

    function test_burn_eventEmitted() public {
        _mintToken();
        uint64 destChain = sourceChainSelector;
        _allowlistBurnDestination(destChain);

        uint256 burnFee = 1337;
        mockRouter.setFee(burnFee);
        vm.deal(originalOwner, burnFee);

        vm.expectEmit(true, true, true, true, address(wrappedNft));
        emit WrappedNFT.BurnMessageSent(
            MockRouter(address(mockRouter)).MOCK_MESSAGE_ID(), destChain, sourceVault, tokenId, originalOwner
        );

        vm.prank(originalOwner);
        wrappedNft.burn{value: burnFee}(tokenId, originalOwner, destChain);
    }
}
