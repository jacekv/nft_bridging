#!/usr/bin/env bash
#
# Read-only verification helpers for the NFT bridge.
#
# Setup — export these before using the commands below:
#   export SEPOLIA_RPC_URL=...        # source chain RPC
#   export OP_SEPOLIA_RPC_URL=...     # destination chain RPC
#   export PROVIDER_NFT=0x...         # ProviderNFT on Sepolia
#   export NFT_VAULT=0x...            # NFTVault on Sepolia
#   export WRAPPED_NFT=0x...          # WrappedNFT on OP Sepolia
#   export TOKEN_ID=0
#
# Then run individual functions, e.g.:
#   ./script/verify.sh
#   owner_source
#   owner_dest
#   state

set -euo pipefail

# ── Source chain (Sepolia): the original ProviderNFT ──────────────────────────

# Who owns the original NFT (the user before bridging, the vault while locked).
owner_source() {
    cast call "$PROVIDER_NFT" "ownerOf(uint256)(address)" "$TOKEN_ID" \
        --rpc-url "$SEPOLIA_RPC_URL"
}

# Who is approved to move the original NFT (should be the vault before deposit).
approved_source() {
    cast call "$PROVIDER_NFT" "getApproved(uint256)(address)" "$TOKEN_ID" \
        --rpc-url "$SEPOLIA_RPC_URL"
}

# tokenURI of the original NFT.
uri_source() {
    cast call "$PROVIDER_NFT" "tokenURI(uint256)(string)" "$TOKEN_ID" \
        --rpc-url "$SEPOLIA_RPC_URL"
}

# ── Destination chain (OP Sepolia): the WrappedNFT ────────────────────────────

# Who owns the wrapped NFT (reverts if it has not been minted / was burned).
owner_dest() {
    cast call "$WRAPPED_NFT" "ownerOf(uint256)(address)" "$TOKEN_ID" \
        --rpc-url "$OP_SEPOLIA_RPC_URL"
}

# tokenURI of the wrapped NFT.
uri_dest() {
    cast call "$WRAPPED_NFT" "tokenURI(uint256)(string)" "$TOKEN_ID" \
        --rpc-url "$OP_SEPOLIA_RPC_URL"
}

# Which source vault locked this token (set on mint, cleared on burn).
source_vault() {
    cast call "$WRAPPED_NFT" "tokenSourceVault(uint256)(address)" "$TOKEN_ID" \
        --rpc-url "$OP_SEPOLIA_RPC_URL"
}

# ── Allowlist sanity checks ───────────────────────────────────────────────────

# Vault's view of OP Sepolia (selector 5224473277236331295) as source chain.
vault_allows_source() {
    cast call "$NFT_VAULT" "allowlistedSourceChains(uint64)(bool)" \
        5224473277236331295 --rpc-url "$SEPOLIA_RPC_URL"
}

# Vault's allowlist for the WrappedNFT sender.
vault_allows_sender() {
    cast call "$NFT_VAULT" "allowlistedSenders(address)(bool)" \
        "$WRAPPED_NFT" --rpc-url "$SEPOLIA_RPC_URL"
}

# WrappedNFT's view of Sepolia (selector 16015286601757825753) as source chain.
wrapped_allows_source() {
    cast call "$WRAPPED_NFT" "allowlistedSourceChains(uint64)(bool)" \
        16015286601757825753 --rpc-url "$OP_SEPOLIA_RPC_URL"
}

# WrappedNFT's allowlist for the NFTVault sender.
wrapped_allows_sender() {
    cast call "$WRAPPED_NFT" "allowlistedSenders(address)(bool)" \
        "$NFT_VAULT" --rpc-url "$OP_SEPOLIA_RPC_URL"
}

# ── Combined snapshot ─────────────────────────────────────────────────────────

state() {
    echo "── Source chain (Sepolia) ──"
    echo "ProviderNFT owner:   $(owner_source)"
    echo "ProviderNFT approved: $(approved_source)"
    echo
    echo "── Destination chain (OP Sepolia) ──"
    echo "WrappedNFT owner:    $(owner_dest 2>/dev/null || echo '(not minted / burned)')"
    echo "Source vault:        $(source_vault)"
}

# ── Write actions (require PRIVATE_KEY) ───────────────────────────────────────

# CCIP chain selector of the destination chain (OP Sepolia).
OP_SEPOLIA_SELECTOR=5224473277236331295

# Native value sent to cover the CCIP fee. deposit() reverts if it is below the
# actual fee and refunds any excess, so a generous overpayment is safe.
BRIDGE_FEE_VALUE="${BRIDGE_FEE_VALUE:-0.05ether}"

# Approve the vault to move the original NFT (run once before depositing).
approve() {
    cast send "$PROVIDER_NFT" "approve(address,uint256)" "$NFT_VAULT" "$TOKEN_ID" \
        --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
}

# Lock the NFT in the vault and send the CCIP message to mint on OP Sepolia.
# The CCIP receiver is the WrappedNFT contract; excess fee is refunded.
deposit() {
    cast send "$NFT_VAULT" "deposit(uint256,address,uint64)" \
        "$TOKEN_ID" "$WRAPPED_NFT" "$OP_SEPOLIA_SELECTOR" \
        --value "$BRIDGE_FEE_VALUE" \
        --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
}

# Convenience: approve then deposit in one go.
lock_and_bridge() {
    approve
    deposit
}

# CCIP chain selector of the source chain (Sepolia) — where the burn message
# is sent so the vault can release the original NFT.
SEPOLIA_SELECTOR=16015286601757825753

# Burn the wrapped NFT on OP Sepolia and send the CCIP message back to Sepolia
# to release the locked original to the recipient. Recipient defaults to the
# broadcasting wallet; override with RECIPIENT. Excess fee is refunded.
burn() {
    local recipient="${RECIPIENT:-$(cast wallet address --private-key "$PRIVATE_KEY")}"
    cast send "$WRAPPED_NFT" "burn(uint256,address,uint64)" \
        "$TOKEN_ID" "$recipient" "$SEPOLIA_SELECTOR" \
        --value "$BRIDGE_FEE_VALUE" \
        --rpc-url "$OP_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" -vvvv
}

main() {
  case "${1:-}" in
    state)          state ;;
    approve)        approve ;;
    deposit)        deposit ;;
    lock_and_bridge) lock_and_bridge ;;
    burn)           burn ;;
    *)
      echo "Usage: $0 {state|approve|deposit|lock_and_bridge|burn}"
      exit 1
      ;;
  esac
}

main "$@"
