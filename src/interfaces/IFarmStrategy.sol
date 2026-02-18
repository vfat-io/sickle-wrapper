// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    Farm,
    DepositParams,
    HarvestParams,
    WithdrawParams,
    SimpleDepositParams,
    SimpleHarvestParams,
    SimpleWithdrawParams
} from "../structs/FarmStrategyStructs.sol";
import { PositionSettings } from "../structs/PositionSettingsStructs.sol";

/// @dev Interface for the deployed FarmStrategy contract (ERC20 positions).
/// Only includes functions called by SickleWrapper.
interface IFarmStrategy {
    function deposit(
        DepositParams calldata params,
        PositionSettings calldata positionSettings,
        address[] calldata sweepTokens,
        address approved,
        bytes32 referralCode
    ) external payable;

    function increase(
        DepositParams calldata params,
        address[] calldata sweepTokens
    ) external payable;

    function simpleDeposit(
        SimpleDepositParams calldata params,
        PositionSettings calldata positionSettings,
        address approved,
        bytes32 referralCode
    ) external payable;

    function simpleIncrease(
        SimpleDepositParams calldata params
    ) external;

    function harvest(
        Farm calldata farm,
        HarvestParams calldata params,
        address[] calldata sweepTokens
    ) external;

    function simpleHarvest(
        Farm calldata farm,
        SimpleHarvestParams calldata params
    ) external;

    function withdraw(
        Farm calldata farm,
        WithdrawParams calldata params,
        address[] calldata sweepTokens
    ) external;

    function simpleWithdraw(
        Farm calldata farm,
        SimpleWithdrawParams calldata params
    ) external;
}
