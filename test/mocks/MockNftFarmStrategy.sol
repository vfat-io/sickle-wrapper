// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from
    "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { INftFarmStrategy } from "../../src/interfaces/INftFarmStrategy.sol";
import {
    NftPosition,
    NftDeposit,
    NftIncrease,
    NftWithdraw,
    NftHarvest,
    NftRebalance,
    NftMove,
    SimpleNftHarvest
} from "../../src/structs/NftFarmStrategyStructs.sol";
import { NftSettings } from "../../src/structs/NftSettingsStructs.sol";

import { MockERC20 } from "./MockERC20.sol";

/// @dev Mock NftFarmStrategy for testing.
///
/// Token pulls are not simulated (see MockFarmStrategy for rationale).
/// NFT transfers for simpleDeposit/simpleWithdraw ARE simulated because
/// those happen directly between wrapper and strategy (not via Sickle approval).
contract MockNftFarmStrategy is INftFarmStrategy, IERC721Receiver {
    // Reward tokens to mint on harvest
    address[] public harvestRewardTokens;
    uint256[] public harvestRewardAmounts;

    // Withdraw token to mint on withdraw
    address public withdrawToken;
    uint256 public withdrawAmount;

    // Track calls
    uint256 public depositCalls;
    uint256 public increaseCalls;
    uint256 public harvestCalls;
    uint256 public simpleHarvestCalls;
    uint256 public simpleDepositCalls;
    uint256 public simpleWithdrawCalls;
    uint256 public withdrawCalls;
    uint256 public decreaseCalls;
    uint256 public rebalanceCalls;
    uint256 public moveCalls;

    function setHarvestRewards(
        address[] memory tokens,
        uint256[] memory amounts
    ) external {
        harvestRewardTokens = tokens;
        harvestRewardAmounts = amounts;
    }

    function setWithdrawResult(address token, uint256 amount) external {
        withdrawToken = token;
        withdrawAmount = amount;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    // --- Strategy functions ---

    function deposit(
        NftDeposit calldata,
        NftSettings calldata,
        address[] calldata,
        address,
        bytes32
    ) external payable override {
        depositCalls++;
    }

    function increase(
        NftPosition calldata,
        NftHarvest calldata,
        NftIncrease calldata,
        bool inPlace,
        address[] calldata
    ) external payable override {
        increaseCalls++;
        // When !inPlace, the real strategy harvests first
        if (!inPlace) _mintRewards();
    }

    function harvest(
        NftPosition calldata,
        NftHarvest calldata
    ) external override {
        harvestCalls++;
        _mintRewards();
    }

    function simpleHarvest(
        NftPosition calldata,
        SimpleNftHarvest calldata
    ) external override {
        simpleHarvestCalls++;
        _mintRewards();
    }

    function simpleDeposit(
        NftPosition calldata position,
        bytes calldata,
        NftSettings calldata,
        address,
        bytes32
    ) external override {
        simpleDepositCalls++;
        // Pull NFT from wrapper (wrapper approved sickle, but for simpleDeposit
        // the wrapper calls approve directly to _sickleAddress(). In the real
        // system Sickle pulls the NFT. Here we simulate it being taken.)
        // Note: this needs the wrapper to have approved this contract for the NFT.
        // But the wrapper approves sickleFactory.predict() not this contract.
        // So we skip the NFT pull and just record the call.
        // The NFT transfer is tested at the wrapper level.
    }

    function simpleWithdraw(
        NftPosition calldata position,
        bytes calldata
    ) external override {
        simpleWithdrawCalls++;
        // Send NFT back to wrapper (simulates Sickle returning NFT to owner)
        IERC721(address(position.nft)).safeTransferFrom(
            address(this), msg.sender, position.tokenId
        );
    }

    function withdraw(
        NftPosition calldata,
        NftWithdraw calldata,
        address[] calldata
    ) external override {
        withdrawCalls++;
        if (withdrawAmount > 0) {
            MockERC20(withdrawToken).mint(msg.sender, withdrawAmount);
        }
    }

    function decrease(
        NftPosition calldata,
        NftHarvest calldata,
        NftWithdraw calldata,
        bool inPlace,
        address[] calldata
    ) external override {
        decreaseCalls++;
        if (!inPlace) _mintRewards();
        if (withdrawAmount > 0) {
            MockERC20(withdrawToken).mint(msg.sender, withdrawAmount);
        }
    }

    function rebalance(
        NftRebalance calldata,
        address[] calldata
    ) external override {
        rebalanceCalls++;
        _mintRewards();
    }

    function move(
        NftMove calldata,
        NftSettings calldata,
        address[] calldata
    ) external override {
        moveCalls++;
        _mintRewards();
    }

    function _mintRewards() private {
        for (uint256 i; i < harvestRewardTokens.length; i++) {
            MockERC20(harvestRewardTokens[i]).mint(
                msg.sender, harvestRewardAmounts[i]
            );
        }
    }
}
