// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// CCIP testnet configuration for Ethereum Sepolia (source) and Avalanche Fuji (destination).
/// Chain selectors and router addresses from:
///   https://docs.chain.link/ccip/directory/testnet
library CCIPConfig {
    // ── Ethereum Sepolia ─────────────────────────────────────────────────────
    uint64 constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    address constant SEPOLIA_ROUTER = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    // ── Avalanche Fuji ───────────────────────────────────────────────────────
    uint64 constant OP_SEPOLIA_CHAIN_SELECTOR = 5224473277236331295;
    address constant OP_SEPOLIA_ROUTER = 0x114A20A10b43D4115e5aeef7345a1A71d2a60C57;
}
