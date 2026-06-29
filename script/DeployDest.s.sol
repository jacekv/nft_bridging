// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script, console} from "forge-std/Script.sol";

import {CCIPConfig} from "./CCIPConfig.sol";
import {WrappedNFT} from "../src/WrappedNFT.sol";

/// Deploy WrappedNFT on Avalanche Fuji.
///
/// Run:
///   forge script script/DeployDest.s.sol --rpc-url $FUJI_RPC_URL \
///     --private-key $PRIVATE_KEY --broadcast
///
/// After deploying both chains, call SetupSource.s.sol and SetupDest.s.sol
/// to finish the allowlist configuration.
contract DeployDest is Script {
    function run() external {
        vm.startBroadcast();

        WrappedNFT wrappedNft = new WrappedNFT(
            "WrappedAwesomeNFT",
            "WANFT",
            CCIPConfig.OP_SEPOLIA_ROUTER
        );
        console.log("WrappedNFT:", address(wrappedNft));

        vm.stopBroadcast();
    }
}
