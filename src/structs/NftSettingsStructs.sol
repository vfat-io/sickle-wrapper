// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IUniswapV3Pool } from
    "../interfaces/external/IUniswapV3Pool.sol";
import { RewardConfig } from "./PositionSettingsStructs.sol";

struct ExitConfig {
    int24 triggerTickLow;
    int24 triggerTickHigh;
    address exitTokenOutLow;
    address exitTokenOutHigh;
    uint256 priceImpactBP;
    uint256 slippageBP;
}

struct RebalanceConfig {
    uint24 tickSpacesBelow;
    uint24 tickSpacesAbove;
    int24 bufferTicksBelow;
    int24 bufferTicksAbove;
    uint256 dustBP;
    uint256 priceImpactBP;
    uint256 slippageBP;
    int24 cutoffTickLow;
    int24 cutoffTickHigh;
    uint8 delayMin;
    RewardConfig rewardConfig;
}

struct NftSettings {
    IUniswapV3Pool pool;
    bytes32 poolId;
    bool autoRebalance;
    RebalanceConfig rebalanceConfig;
    bool automateRewards;
    RewardConfig rewardConfig;
    bool autoExit;
    ExitConfig exitConfig;
    bytes extraData;
}
