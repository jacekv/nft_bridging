// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script, console} from "forge-std/Script.sol";

import {CCIPConfig} from "./CCIPConfig.sol";
import {NFTVault} from "../src/NFTVault.sol";

/// Configure NFTVault on Ethereum Sepolia after both chains are deployed.
/// Allowlists Fuji as destination + source, and the WrappedNFT contract as
/// the only trusted sender.
///
/// Run:
///   forge script script/SetupSource.s.sol --rpc-url $SEPOLIA_RPC_URL \
///     --private-key $PRIVATE_KEY --broadcast \
///     --sig "run(address,address)" <NFT_VAULT_ADDRESS> <WRAPPED_NFT_ADDRESS>
contract SetupSource is Script {
    function run(address vaultAddress, address wrappedNftAddress) external {
        NFTVault vault = NFTVault(vaultAddress);

        vm.startBroadcast();

        vault.allowlistDestinationChain(CCIPConfig.OP_SEPOLIA_CHAIN_SELECTOR, true);
        console.log("Allowlisted destination chain: Fuji");

        vault.allowlistSourceChain(CCIPConfig.OP_SEPOLIA_CHAIN_SELECTOR, true);
        console.log("Allowlisted source chain: Fuji");

        vault.allowlistSender(wrappedNftAddress, true);
        console.log("Allowlisted sender (WrappedNFT):", wrappedNftAddress);

        vm.stopBroadcast();
    }
}
