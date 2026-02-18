// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

enum RewardBehavior {
    None,
    Harvest,
    Compound
}

struct RewardConfig {
    RewardBehavior rewardBehavior;
    address harvestTokenOut;
}

struct ExitConfig {
    uint256 baseTokenIndex;
    uint256 quoteTokenIndex;
    uint256 triggerPriceLow;
    address exitTokenOutLow;
    uint256 triggerPriceHigh;
    address exitTokenOutHigh;
    uint256[] triggerReservesLow;
    address[] triggerReservesTokensOut;
    uint256 priceImpactBP;
    uint256 slippageBP;
}

struct PositionSettings {
    address pool;
    address router;
    bool automateRewards;
    RewardConfig rewardConfig;
    bool autoExit;
    ExitConfig exitConfig;
    bytes extraData;
}
