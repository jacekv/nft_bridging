// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script, console} from "forge-std/Script.sol";

import {CCIPConfig} from "./CCIPConfig.sol";
import {ProviderNFT} from "../src/ProviderNFT.sol";
import {NFTVault} from "../src/NFTVault.sol";

/// Deploy ProviderNFT + NFTVault on Ethereum Sepolia.
///
/// Run:
///   forge script script/DeploySource.s.sol --rpc-url $SEPOLIA_RPC_URL \
///     --private-key $PRIVATE_KEY --broadcast
///
/// After deploying the destination chain, call SetupSource.s.sol to finish
/// the allowlist configuration.
contract DeploySource is Script {
    function run() external {
        vm.startBroadcast();

        ProviderNFT providerNft = new ProviderNFT("AwesomeNFT", "ANFT");
        console.log("ProviderNFT:", address(providerNft));

        NFTVault vault = new NFTVault(CCIPConfig.SEPOLIA_ROUTER, address(providerNft));
        console.log("NFTVault:   ", address(vault));

        vm.stopBroadcast();
    }
}
