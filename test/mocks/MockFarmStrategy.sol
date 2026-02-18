// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IFarmStrategy} from "../../src/interfaces/IFarmStrategy.sol";
import {
    Farm,
    DepositParams,
    HarvestParams,
    WithdrawParams,
    SimpleDepositParams,
    SimpleHarvestParams,
    SimpleWithdrawParams
} from "../../src/structs/FarmStrategyStructs.sol";
import {PositionSettings} from "../../src/structs/PositionSettingsStructs.sol";

import {MockERC20} from "./MockERC20.sol";

/// @dev Mock FarmStrategy for testing.
///
/// In the real system, strategies orchestrate the Sickle to pull tokens from
/// the wrapper (owner). We can't replicate that here because the approval
/// targets the Sickle address, not the strategy. Instead:
///   - Deposits just record calls (token pull from user is tested separately).
///   - Harvests mint reward tokens to msg.sender (wrapper).
///   - Withdraws mint LP tokens to msg.sender (wrapper).
contract MockFarmStrategy is IFarmStrategy {
    // Tokens to mint to wrapper on harvest
    address[] public harvestRewardTokens;
    uint256[] public harvestRewardAmounts;

    // Token to mint to wrapper on withdraw
    address public withdrawToken;
    uint256 public withdrawAmount;

    // Track calls
    uint256 public depositCalls;
    uint256 public increaseCalls;
    uint256 public simpleDepositCalls;
    uint256 public simpleIncreaseCalls;
    uint256 public harvestCalls;
    uint256 public simpleHarvestCalls;
    uint256 public withdrawCalls;
    uint256 public simpleWithdrawCalls;

    function setHarvestRewards(address[] memory tokens, uint256[] memory amounts) external {
        harvestRewardTokens = tokens;
        harvestRewardAmounts = amounts;
    }

    function setWithdrawResult(address token, uint256 amount) external {
        withdrawToken = token;
        withdrawAmount = amount;
    }

    // --- Strategy functions ---

    function deposit(DepositParams calldata, PositionSettings calldata, address[] calldata, address, bytes32)
        external
        payable
        override
    {
        depositCalls++;
    }

    function increase(DepositParams calldata, address[] calldata) external payable override {
        increaseCalls++;
    }

    function simpleDeposit(SimpleDepositParams calldata, PositionSettings calldata, address, bytes32)
        external
        payable
        override
    {
        simpleDepositCalls++;
    }

    function simpleIncrease(SimpleDepositParams calldata) external override {
        simpleIncreaseCalls++;
    }

    function harvest(Farm calldata, HarvestParams calldata, address[] calldata) external override {
        harvestCalls++;
        _mintRewards();
    }

    function simpleHarvest(Farm calldata, SimpleHarvestParams calldata) external override {
        simpleHarvestCalls++;
        _mintRewards();
    }

    function withdraw(Farm calldata, WithdrawParams calldata, address[] calldata) external override {
        withdrawCalls++;
        if (withdrawAmount > 0) {
            MockERC20(withdrawToken).mint(msg.sender, withdrawAmount);
        }
    }

    function simpleWithdraw(Farm calldata, SimpleWithdrawParams calldata) external override {
        simpleWithdrawCalls++;
        if (withdrawAmount > 0) {
            MockERC20(withdrawToken).mint(msg.sender, withdrawAmount);
        }
    }

    function _mintRewards() private {
        for (uint256 i; i < harvestRewardTokens.length; i++) {
            MockERC20(harvestRewardTokens[i]).mint(msg.sender, harvestRewardAmounts[i]);
        }
    }
}
