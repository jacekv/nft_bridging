// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script, console} from "forge-std/Script.sol";

import {CCIPConfig} from "./CCIPConfig.sol";
import {WrappedNFT} from "../src/WrappedNFT.sol";

/// Configure WrappedNFT on Avalanche Fuji after both chains are deployed.
/// Allowlists Sepolia as source + destination, and the NFTVault contract as
/// the only trusted sender.
///
/// Run:
///   forge script script/SetupDest.s.sol --rpc-url $FUJI_RPC_URL \
///     --private-key $PRIVATE_KEY --broadcast \
///     --sig "run(address,address)" <WRAPPED_NFT_ADDRESS> <NFT_VAULT_ADDRESS>
contract SetupDest is Script {
    function run(address wrappedNftAddress, address vaultAddress) external {
        WrappedNFT wrappedNft = WrappedNFT(wrappedNftAddress);

        vm.startBroadcast();

        wrappedNft.allowlistSourceChain(CCIPConfig.SEPOLIA_CHAIN_SELECTOR, true);
        console.log("Allowlisted source chain: Sepolia");

        wrappedNft.allowlistSender(vaultAddress, true);
        console.log("Allowlisted sender (NFTVault):", vaultAddress);

        wrappedNft.allowlistDestinationChain(CCIPConfig.SEPOLIA_CHAIN_SELECTOR, true);
        console.log("Allowlisted destination chain: Sepolia");

        vm.stopBroadcast();
    }
}
