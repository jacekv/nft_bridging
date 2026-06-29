# NFT Bridge — Lock+Mint with Chainlink CCIP

A cross-chain NFT bridge using the **lock-and-mint** pattern on top of Chainlink CCIP.
Locking an NFT on Ethereum Sepolia mints a wrapped copy on OP Sepolia. Burning the
wrapped copy releases the original.

## Contracts

| Contract | Chain | Role |
|---|---|---|
| `ProviderNFT` | Sepolia | Stand-in ERC-721 (any collection works) |
| `NFTVault` | Sepolia | Locks originals, releases on burn confirmation |
| `WrappedNFT` | OP Sepolia | Mints wrapped copies, burns them on return |

CCIP chain selectors and router addresses are in `script/CCIPConfig.sol`.

## Build & Test

```shell
forge build
forge test
```

## Deploy

### 1. Source chain (Sepolia)

```shell
forge script script/DeploySource.s.sol --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast
# note: NFTVault and ProviderNFT addresses printed to stdout
```

### 2. Destination chain (OP Sepolia)

```shell
forge script script/DeployDest.s.sol --rpc-url $OP_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast
# note: WrappedNFT address printed to stdout
```

### 3. Wire up the allowlists

Both contracts need to know each other's address — run these after both chains are deployed:

```shell
forge script script/SetupSource.s.sol --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast \
  --sig "run(address,address)" $NFT_VAULT $WRAPPED_NFT

forge script script/SetupDest.s.sol --rpc-url $OP_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast \
  --sig "run(address,address)" $WRAPPED_NFT $NFT_VAULT
```

## End-to-End Round Trip

Set env vars once, then use `script/verify.sh` for all interactions:

```shell
export SEPOLIA_RPC_URL=...
export OP_SEPOLIA_RPC_URL=...
export PROVIDER_NFT=<ProviderNFT address>
export NFT_VAULT=<NFTVault address>
export WRAPPED_NFT=<WrappedNFT address>
export TOKEN_ID=0
export PRIVATE_KEY=...

./script/verify.sh approve         # approve vault to move the NFT
./script/verify.sh deposit         # lock + CCIP message to OP Sepolia
# wait for CCIP delivery at ccip.chain.link
./script/verify.sh state           # confirm vault owns original, you own wrapped
./script/verify.sh burn            # burn wrapped + CCIP message back to Sepolia
# wait for CCIP delivery
./script/verify.sh state           # confirm original returned to your wallet
```

Read-only helpers (no `PRIVATE_KEY` needed):

```shell
./script/verify.sh state           # ownership snapshot on both chains
cast call $WRAPPED_NFT "tokenURI(uint256)(string)" $TOKEN_ID --rpc-url $OP_SEPOLIA_RPC_URL
```

Expected state at each stage:

| Stage | `owner_source` | `owner_dest` |
|---|---|---|
| Before deposit | your wallet | (reverts) |
| After deposit + CCIP delivery | vault | your wallet |
| After burn + CCIP delivery | your wallet | (reverts) |

## Testnet Deployments

| Contract | Chain | Address |
|---|---|---|
| ProviderNFT | Sepolia | [0xE4BF4837573b7AFeeDA149661A7D4bc6e30A4618](https://sepolia.etherscan.io/address/0xE4BF4837573b7AFeeDA149661A7D4bc6e30A4618) |
| NFTVault | Sepolia | [0x6A34b2410f6325944f05cEAA087700E0C6aE7C46](https://sepolia.etherscan.io/address/0x6A34b2410f6325944f05cEAA087700E0C6aE7C46) |
| WrappedNFT | OP Sepolia | [0x04bD0c9C8aa8fC9a9887024C1F3bE2911909D2A4](https://optimism-sepolia.etherscan.io/address/0x04bD0c9C8aa8fC9a9887024C1F3bE2911909D2A4) |
