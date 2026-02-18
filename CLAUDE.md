# Sickle Wrapper — Project Context

## What This Is

A standalone Foundry project that implements a **wrapper ownership model** on top of [Sickle](https://github.com/vfat-io/sickle-contracts) (a DeFi position management protocol). This project is designed to be deployed and maintained by a **partner** (e.g. Mohamed / Aerodrome gamified layer) independently of the Sickle team.

## Problem Statement

Mohamed wants to build a gamified layer for Aerodrome on top of Sickle:
1. Users deposit via Mohamed's UI
2. Sickle manages the LP positions
3. Reward claims route through Mohamed's contract (RewardRouter) before reaching the user
4. Positions created through Mohamed's flow can **only** claim via his contract

Sickle's access control is global (whitelisted strategies/callers), not per-position. There's no way to restrict claims for specific positions without modifying existing Sickle contracts. The user (vf.at / Sickle team) doesn't want to modify anything existing.

## Solution: Wrapper Ownership Model

A `SickleWrapper` contract becomes the Sickle's `owner`. Since `FarmStrategy.harvest()` resolves the Sickle via `getSickle(msg.sender)`, only the wrapper can trigger strategy calls — preventing the end user from bypassing reward routing.

### Token Flows

```
Harvest:   Gauge → Sickle → Wrapper (as owner) → RewardRouter → User
Compound:  Gauge → Sickle → Wrapper → RewardRouter → Wrapper → Sickle → Gauge
Withdraw:  Gauge → Sickle → Wrapper (as owner) → User (direct)
Deposit:   User → Wrapper → Sickle → Gauge
```

### Custody Model

Not pure self-custody (wrapper owns Sickle), but the user can always withdraw LP directly. Only reward claims are restricted to go through the RewardRouter.

## Architecture

### Contracts

- **`SickleWrapper.sol`** — Per-user contract that owns a Sickle. Immutable `user` address. Supports both ERC20 (FarmStrategy) and NFT/CL (NftFarmStrategy) positions. Routes rewards through the `IRewardRouter`.
- **`WrapperFactory.sol`** — CREATE2 factory, deploys one `SickleWrapper` per user. Holds immutable references to the strategy contracts, SickleFactory, and RewardRouter.
- **`IRewardRouter.sol`** — Interface that Mohamed implements. Two methods:
  - `onRewardsClaimed(user, tokens, amounts)` — harvest flow, send processed rewards to user
  - `onRewardsCompounded(user, tokens, amounts)` — compound flow, return processed tokens to `msg.sender` (wrapper) for re-deposit

### Interfaces (extracted from sickle-contracts)

The `src/interfaces/` directory contains minimal interfaces for the deployed Sickle contracts:
- `IFarmStrategy` — ERC20 farm strategy (deposit, increase, harvest, withdraw, etc.)
- `INftFarmStrategy` — NFT/CL farm strategy (same operations + rebalance, move, decrease)
- `ISickleFactory` — Only `predict(address) → address` (deterministic Sickle address)
- `external/IUniswapV3Pool` — Stub, used only as a type in structs
- `external/INonfungiblePositionManager` — Extends IERC721, used as type in structs

### Structs (extracted from sickle-contracts)

The `src/structs/` directory mirrors the struct definitions from sickle-contracts exactly (ABI compatibility is critical). Structs that reference the `Sickle` type directly (e.g. `PositionKey`, `NftKey`) are omitted — the wrapper doesn't need them.

## Deployment

Mohamed deploys:
1. His `RewardRouter` contract (implements `IRewardRouter`)
2. `WrapperFactory` pointing to:
   - Existing deployed `FarmStrategy` address
   - Existing deployed `NftFarmStrategy` address
   - Existing deployed `SickleFactory` address
   - His `RewardRouter` address

**No changes needed on the Sickle side.** The wrapper calls existing strategies as `msg.sender`. The strategies look up `getSickle(msg.sender)` which resolves to the wrapper's Sickle. The strategies are already whitelisted callers in SickleRegistry.

## Deployed Sickle Addresses (Base / Aerodrome)

These need to be filled in at deployment time:
- `FarmStrategy`: TBD
- `NftFarmStrategy`: TBD
- `SickleFactory`: TBD

## Build & Test

```bash
forge build    # Compile
forge test     # Run tests (none yet)
```

## Dependencies

- OpenZeppelin Contracts v4.9.3 (SafeERC20, IERC20, IERC721, IERC721Receiver)
- Solidity 0.8.17

## Key Design Decisions

1. **Interfaces instead of concrete imports** — This project doesn't depend on the private sickle-contracts repo. All Sickle types are extracted as interfaces and structs.
2. **Exit is two separate calls** — `exit()` does `harvest()` then `withdraw()` as separate strategy calls to avoid mixing reward tokens with LP tokens.
3. **OZ v4.x approve pattern** — Uses `safeApprove(spender, 0)` then `safeApprove(spender, amount)` because OZ v4.x doesn't have `forceApprove`.
4. **No admin functions** — The wrapper is fully immutable once deployed. No owner, no upgradeability.
5. **Rescue functions** — `rescueToken`, `rescueETH`, `rescueNft` allow the user to recover tokens accidentally sent to the wrapper (not the Sickle).

## TODO

- [ ] Write tests (unit + fork tests against deployed Sickle on Base)
- [ ] Implement the `RewardRouter` contract (Mohamed's side)
- [ ] Deployment scripts
- [ ] Verify deployed strategy addresses for Base / Aerodrome
- [ ] Consider whether `compound` functions need more flexibility in how tokens are passed back from the router
