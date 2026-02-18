# @vfat-io/sickle-wrapper-sdk

TypeScript SDK for interacting with [SickleWrapper](../README.md) contracts. Wraps `@vfat-io/sickle-sdk`, translating strategy-targeted calldata into wrapper-targeted calldata.

## How It Works

```
User's frontend
  → wrapper.lp.depositToken({ userAddress, ... })
    → predict(userAddress) → wrapperAddress
    → sickle-sdk.lp.depositToken({ walletAddress: wrapperAddress, ... })
    → quoting API returns ContractCallData targeting FarmStrategy
    → SDK swaps address/abi → ContractCallData targeting SickleWrapper
  → walletClient.writeContract(result)
```

Every method:
1. Calls `WrapperFactory.predict(userAddress)` to resolve the deterministic wrapper address
2. Calls `@vfat-io/sickle-sdk` with `walletAddress = wrapperAddress`
3. Replaces `address` and `abi` in the returned `ContractCallData` to target the wrapper

For NFT operations, the SDK also appends `Nft` to the `functionName` (e.g. `deposit` → `depositNft`).

## Install

```bash
npm install @vfat-io/sickle-wrapper-sdk
```

## Setup

```typescript
import { createPublicClient, http } from 'viem';
import { base } from 'viem/chains';
import { createWrapperSickle } from '@vfat-io/sickle-wrapper-sdk';

const publicClient = createPublicClient({
  chain: base,
  transport: http(),
});

const wrapper = createWrapperSickle({
  wrapperFactoryAddress: '0x...', // deployed WrapperFactory
  publicClient,
});
```

## API

All async methods return `Promise<ContractCallData>` — pass the result to `walletClient.writeContract()`.

### Factory

```typescript
// Get or deploy the user's wrapper (returns calldata, not a promise)
const createTx = wrapper.factory.getOrCreateWrapper(userAddress);

// Predict the wrapper address (view call)
const wrapperAddr = await wrapper.factory.predict(userAddress);
```

### LP Operations

```typescript
// Deposit LP tokens (new position)
await wrapper.lp.deposit({ chainId, userAddress, farmAddress, amount, positionSettings });

// Zap single token → LP
await wrapper.lp.depositToken({ chainId, userAddress, farmAddress, tokenAddress, amount, positionSettings, slippage? });

// Deposit underlying tokens → LP
await wrapper.lp.depositUnderlying({ chainId, userAddress, farmAddress, amount0, amount1, positionSettings });

// Increase existing position
await wrapper.lp.increase.withToken({ chainId, userAddress, farmAddress, tokenAddress, amount });
await wrapper.lp.increase.withUnderlying({ chainId, userAddress, farmAddress, amount0, amount1, token0Address, token1Address });

// Harvest rewards (routed through RewardRouter)
await wrapper.lp.harvest({ chainId, userAddress, farmAddress, tokenAddress? });

// Withdraw
await wrapper.lp.withdraw.toLp({ chainId, userAddress, farmAddress, amount });
await wrapper.lp.withdraw.toToken({ chainId, userAddress, farmAddress, tokenAddress, amount });
await wrapper.lp.withdraw.toUnderlying({ chainId, userAddress, farmAddress, amount });

// Exit = harvest + withdraw (composed from two parallel API calls)
await wrapper.lp.exit.toToken({ chainId, userAddress, farmAddress, tokenAddress, amount });
```

### NFT Operations

```typescript
// Deposit
await wrapper.nft.deposit({ chainId, userAddress, farmAddress, nftId, nftSettings });
await wrapper.nft.depositToken({ chainId, userAddress, farmAddress, tokenAddress, amount, nftSettings });
await wrapper.nft.depositUnderlying({ chainId, userAddress, farmAddress, amount0, amount1, nftSettings });

// Increase
await wrapper.nft.increase.withToken({ chainId, userAddress, farmAddress, tokenAddress, amount, nftId });
await wrapper.nft.increase.withUnderlying({ chainId, userAddress, farmAddress, amount0, amount1, nftId });

// Harvest rewards (routed through RewardRouter)
await wrapper.nft.harvest({ chainId, userAddress, farmAddress, nftId });

// Decrease
await wrapper.nft.decrease.toToken({ chainId, userAddress, farmAddress, positionPercentage, nftId });
await wrapper.nft.decrease.toUnderlying({ chainId, userAddress, farmAddress, positionPercentage, nftId });

// Withdraw NFT position
await wrapper.nft.withdraw({ chainId, userAddress, farmAddress, nftId });

// Rebalance to new price range
await wrapper.nft.rebalance({ chainId, userAddress, nftId, sourceFarmAddress });
```

### Rescue

Recover tokens accidentally sent to the wrapper contract (not the Sickle).

```typescript
await wrapper.rescue.token(chainId, userAddress, tokenAddress);
await wrapper.rescue.eth(chainId, userAddress);
await wrapper.rescue.nft(chainId, userAddress, nftAddress, tokenId);
```

## Usage with viem

```typescript
import { createWalletClient, custom } from 'viem';
import { base } from 'viem/chains';

const walletClient = createWalletClient({
  chain: base,
  transport: custom(window.ethereum),
});

// 1. Ensure wrapper exists
const createTx = wrapper.factory.getOrCreateWrapper(userAddress);
await walletClient.writeContract(createTx);

// 2. Deposit
const depositTx = await wrapper.lp.depositToken({
  chainId: 8453,
  userAddress: '0x...',
  farmAddress: '0x...',
  tokenAddress: '0x...',
  amount: 1000000000000000000n,
  positionSettings: { /* ... */ },
});
await walletClient.writeContract(depositTx);

// 3. Harvest
const harvestTx = await wrapper.lp.harvest({
  chainId: 8453,
  userAddress: '0x...',
  farmAddress: '0x...',
  tokenAddress: '0x...', // desired reward token
});
await walletClient.writeContract(harvestTx);
```

## Param Types

All parameter types mirror `@vfat-io/sickle-sdk` but replace `walletAddress` with `userAddress`. The SDK resolves the wrapper address internally via `WrapperFactory.predict()`.

## Not in v1

- `compound` / `compoundNft` — requires knowing RewardRouter fee to estimate re-deposit amounts
- `nft.exit` — wrapper's `exitNft` takes NftHarvest + NftWithdraw structs; decomposition needs investigation
- `moveNft` — no sickle-sdk endpoint

## Development

```bash
npm install
npm run typecheck   # Type-check
npm test            # Run tests
npm run build       # Build CJS + ESM
```
