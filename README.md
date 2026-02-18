# Sickle Wrapper

A wrapper ownership model on top of [Sickle](https://github.com/vfat-io/sickle-contracts) that enables partners to route reward claims through a custom `RewardRouter` contract. Positions created through the wrapper can **only** claim rewards via the partner's router, while users always retain the ability to withdraw their principal (LP tokens / NFTs) directly.

## How It Works

A `SickleWrapper` contract becomes the Sickle's `owner`. Since `FarmStrategy.harvest()` resolves the Sickle via `getSickle(msg.sender)`, only the wrapper can trigger strategy calls — preventing the end user from bypassing reward routing.

### Token Flows

```
Deposit:   User → Wrapper → Sickle → Gauge
Harvest:   Gauge → Sickle → Wrapper → RewardRouter → User
Compound:  Gauge → Sickle → Wrapper → RewardRouter → Wrapper → Sickle → Gauge
Withdraw:  Gauge → Sickle → Wrapper → User (direct, no router)
```

### Architecture

```
┌──────────┐     ┌────────────────┐     ┌─────────────────┐
│   User   │────▶│ SickleWrapper  │────▶│  FarmStrategy /  │
│          │◀────│  (owns Sickle) │◀────│ NftFarmStrategy  │
└──────────┘     └───────┬────────┘     └─────────────────┘
                         │
                         ▼
                 ┌───────────────┐
                 │ RewardRouter  │  (partner-controlled)
                 └───────────────┘
```

**Contracts:**

| Contract | Description |
|----------|-------------|
| `SickleWrapper` | Per-user contract that owns a Sickle. Immutable `user` address. Routes rewards through `IRewardRouter`. |
| `WrapperFactory` | CREATE2 factory. Deploys one `SickleWrapper` per user with deterministic addresses. |
| `RewardRouter` | Reference `IRewardRouter` implementation. Takes a configurable fee (basis points) on rewards. |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Access to deployed Sickle contracts on your target chain:
  - `FarmStrategy` address
  - `NftFarmStrategy` address
  - `SickleFactory` address

## Build & Test

```bash
# Install dependencies
forge install

# Compile
forge build

# Run tests
forge test

# Run tests with verbose output
forge test -vvv

# Gas report
forge test --gas-report
```

## Deployment

### 1. Set up environment

Create a `.env` file (it is gitignored):

```bash
# RPC
RPC_URL=https://mainnet.base.org

# Deployer private key
PRIVATE_KEY=0x...

# Existing deployed Sickle contract addresses
FARM_STRATEGY=0x...
NFT_FARM_STRATEGY=0x...
SICKLE_FACTORY=0x...

# RewardRouter config
FEE_BPS=500            # 5% fee (in basis points, max 5000 = 50%)
FEE_RECIPIENT=0x...    # Address that receives the fee portion of rewards
```

### 2. Deploy

```bash
source .env

forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

This deploys two contracts:
1. **RewardRouter** — with the deployer as `owner`, the configured fee, and fee recipient
2. **WrapperFactory** — pointing to the existing Sickle strategy contracts and the new RewardRouter

The script logs both deployed addresses.

### 3. Verify (if `--verify` wasn't used)

```bash
forge verify-contract <REWARD_ROUTER_ADDRESS> src/RewardRouter.sol:RewardRouter \
  --constructor-args $(cast abi-encode "constructor(address,uint256,address)" $DEPLOYER $FEE_BPS $FEE_RECIPIENT) \
  --chain base

forge verify-contract <WRAPPER_FACTORY_ADDRESS> src/WrapperFactory.sol:WrapperFactory \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" $FARM_STRATEGY $NFT_FARM_STRATEGY $SICKLE_FACTORY <REWARD_ROUTER_ADDRESS>) \
  --chain base
```

## Usage

### For the Frontend / Integration

#### Creating a wrapper for a user

```solidity
// Anyone can call this — but only the user can interact with their wrapper
SickleWrapper wrapper = factory.getOrCreateWrapper(userAddress);
```

The wrapper address is deterministic and can be predicted before deployment:

```solidity
address predicted = factory.predict(userAddress);
```

#### Depositing into an ERC20 farm

```solidity
// User must first approve the wrapper for their tokens
IERC20(token).approve(address(wrapper), amount);

// Then call deposit (only the user can call this)
wrapper.deposit(depositParams, positionSettings, sweepTokens, approved, referralCode);

// Or for simple single-token deposits:
wrapper.simpleDeposit(simpleDepositParams, positionSettings, approved, referralCode);
```

#### Harvesting rewards

```solidity
// Rewards are automatically routed through the RewardRouter
wrapper.harvest(farm, harvestParams, sweepTokens);

// Or simple harvest:
wrapper.simpleHarvest(farm, simpleHarvestParams);
```

#### Compounding rewards

```solidity
// Harvest + route through RewardRouter (compound mode) + re-deposit
wrapper.compound(farm, harvestParams, harvestSweepTokens, depositParams, depositSweepTokens);
```

#### Withdrawing

```solidity
// LP tokens go directly to the user (no router involvement)
wrapper.withdraw(farm, withdrawParams, sweepTokens);

// Or exit (harvest routed + withdraw direct):
wrapper.exit(farm, harvestParams, harvestSweepTokens, withdrawParams, withdrawSweepTokens);
```

#### NFT positions

All ERC20 operations have NFT equivalents: `depositNft`, `harvestNft`, `compoundNft`, `withdrawNft`, `exitNft`, `increaseNft`, `decreaseNft`, `rebalanceNft`, `moveNft`, and their `simple*` variants.

### Managing the RewardRouter

The RewardRouter `owner` can update fee parameters:

```solidity
RewardRouter router = RewardRouter(routerAddress);

// Update fee (max 5000 = 50%)
router.setFeeBps(300); // 3%

// Update fee recipient
router.setFeeRecipient(newRecipient);

// Transfer ownership
router.transferOwnership(newOwner);
```

### Rescue functions

If tokens or NFTs are accidentally sent directly to the wrapper contract:

```solidity
wrapper.rescueToken(tokenAddress);  // ERC20
wrapper.rescueETH();                // Native ETH
wrapper.rescueNft(nftAddress, tokenId);  // ERC721
```

## Implementing a Custom RewardRouter

The included `RewardRouter.sol` is a reference implementation. To build a custom one, implement the `IRewardRouter` interface:

```solidity
interface IRewardRouter {
    /// @notice Called on harvest. Pull tokens from msg.sender, process, send to user.
    function onRewardsClaimed(
        address user,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;

    /// @notice Called on compound. Pull tokens from msg.sender, process,
    ///         send back to msg.sender (the wrapper) for re-deposit.
    function onRewardsCompounded(
        address user,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;
}
```

Key points:
- The wrapper approves the router for the reward token amounts before calling
- `onRewardsClaimed`: pull tokens via `transferFrom(msg.sender, ...)`, then send processed result to `user`
- `onRewardsCompounded`: pull tokens via `transferFrom(msg.sender, ...)`, then send processed result back to `msg.sender` (the wrapper)

## Security Considerations

- **Not pure self-custody**: The wrapper owns the Sickle, not the user directly. However, the user can always withdraw LP tokens and NFTs — only reward claims are routed.
- **Immutable**: Once deployed, a wrapper has no admin functions, no upgradeability. The `user` address is set at construction and cannot be changed.
- **RewardRouter trust**: Users trust the RewardRouter to forward rewards correctly. The router is controlled by the partner and can be audited independently.
- **No changes to Sickle**: This system works with existing deployed Sickle contracts. No modifications are needed on the Sickle side.

## Dependencies

- [OpenZeppelin Contracts v4.9.3](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v4.9.3) (SafeERC20, IERC20, IERC721, IERC721Receiver)
- [forge-std](https://github.com/foundry-rs/forge-std) (testing)
- Solidity 0.8.17
