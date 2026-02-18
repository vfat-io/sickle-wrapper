// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    NftPosition,
    NftDeposit,
    NftIncrease,
    NftWithdraw,
    NftHarvest,
    NftRebalance,
    NftMove,
    SimpleNftHarvest
} from "../structs/NftFarmStrategyStructs.sol";
import {NftSettings} from "../structs/NftSettingsStructs.sol";

/// @dev Interface for the deployed NftFarmStrategy contract (CL / NFT positions).
/// Only includes functions called by SickleWrapper.
interface INftFarmStrategy {
    function deposit(
        NftDeposit calldata params,
        NftSettings calldata settings,
        address[] calldata sweepTokens,
        address approved,
        bytes32 referralCode
    ) external payable;

    function increase(
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftIncrease calldata increaseParams,
        bool inPlace,
        address[] calldata sweepTokens
    ) external payable;

    function harvest(NftPosition calldata position, NftHarvest calldata params) external;

    function simpleHarvest(NftPosition calldata position, SimpleNftHarvest calldata params) external;

    function simpleDeposit(
        NftPosition calldata position,
        bytes calldata extraData,
        NftSettings calldata settings,
        address approved,
        bytes32 referralCode
    ) external;

    function simpleWithdraw(NftPosition calldata position, bytes calldata extraData) external;

    function withdraw(NftPosition calldata position, NftWithdraw calldata params, address[] calldata sweepTokens)
        external;

    function decrease(
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftWithdraw calldata withdrawParams,
        bool inPlace,
        address[] calldata sweepTokens
    ) external;

    function rebalance(NftRebalance calldata params, address[] calldata sweepTokens) external;

    function move(NftMove calldata params, NftSettings calldata settings, address[] calldata sweepTokens) external;
}
