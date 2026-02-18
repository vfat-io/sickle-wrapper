// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SickleWrapper } from "../../src/SickleWrapper.sol";
import {
    Farm,
    SimpleDepositParams,
    SimpleHarvestParams,
    SimpleWithdrawParams
} from "../../src/structs/FarmStrategyStructs.sol";
import { PositionSettings } from "../../src/structs/PositionSettingsStructs.sol";

import { ForkTestBase, Base } from "./ForkTestBase.sol";

/// @title AerodromeERC20 Fork Tests
/// @notice Full lifecycle tests for ERC20 (VAMM) positions through the wrapper.
///         Uses the deployed Sickle infrastructure on Base with Aerodrome.
///
/// Flow: User → SickleWrapper → FarmStrategy → Sickle → Aerodrome Gauge
///
/// Run: forge test --match-contract AerodromeERC20ForkTest -vvv
contract AerodromeERC20ForkTest is ForkTestBase {
    SickleWrapper wrapper;

    address constant LP_TOKEN = Base.VAMM_WETH_USDC;
    address constant GAUGE = Base.VAMM_WETH_USDC_GAUGE;
    address constant REWARD_TOKEN = Base.AERO;

    function setUp() public {
        _setUpFork();
        wrapper = _createWrapper();
    }

    function _farm() internal pure returns (Farm memory) {
        return Farm({ stakingContract: GAUGE, poolIndex: 0 });
    }

    // =====================================================================
    // simpleDeposit → simpleHarvest → simpleWithdraw
    // =====================================================================

    function test_erc20_full_lifecycle() public {
        uint256 depositAmount = 1e18;

        // --- Deal LP tokens to user ---
        deal(LP_TOKEN, user, depositAmount);
        assertEq(IERC20(LP_TOKEN).balanceOf(user), depositAmount);

        // --- Deposit ---
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), depositAmount);

        wrapper.simpleDeposit(
            SimpleDepositParams({
                farm: _farm(),
                lpToken: LP_TOKEN,
                amountIn: depositAmount,
                extraData: ""
            }),
            _emptyPositionSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        // LP tokens should have been deposited into the gauge via Sickle
        assertEq(IERC20(LP_TOKEN).balanceOf(user), 0, "user LP after deposit");
        assertEq(
            IERC20(LP_TOKEN).balanceOf(address(wrapper)),
            0,
            "wrapper LP after deposit"
        );

        // --- Warp time to accrue rewards ---
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // --- Harvest ---
        uint256 userAeroBefore = IERC20(REWARD_TOKEN).balanceOf(user);
        uint256 feeRecipientAeroBefore =
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        vm.prank(user);
        wrapper.simpleHarvest(
            _farm(),
            SimpleHarvestParams({ rewardTokens: rewardTokens, extraData: "" })
        );

        uint256 userAeroAfter = IERC20(REWARD_TOKEN).balanceOf(user);
        uint256 feeRecipientAeroAfter =
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient);
        uint256 userRewards = userAeroAfter - userAeroBefore;
        uint256 feeRewards = feeRecipientAeroAfter - feeRecipientAeroBefore;

        assertGt(userRewards, 0, "user should have received AERO rewards");
        assertGt(feeRewards, 0, "fee recipient should have received fee");

        // Fee should be ~5% of total
        uint256 totalRewards = userRewards + feeRewards;
        assertApproxEqRel(
            feeRewards, totalRewards * FEE_BPS / 10_000, 0.01e18, "fee ~5%"
        );

        // --- Withdraw ---
        uint256 userLpBefore = IERC20(LP_TOKEN).balanceOf(user);

        vm.prank(user);
        wrapper.simpleWithdraw(
            _farm(),
            SimpleWithdrawParams({
                lpToken: LP_TOKEN,
                amountOut: depositAmount,
                extraData: ""
            })
        );

        uint256 userLpAfter = IERC20(LP_TOKEN).balanceOf(user);
        assertGt(
            userLpAfter,
            userLpBefore,
            "user should have LP tokens back after withdraw"
        );
    }

    // =====================================================================
    // simpleExit (harvest + withdraw in one call)
    // =====================================================================

    function test_erc20_simple_exit() public {
        uint256 depositAmount = 1e18;

        // Deposit
        deal(LP_TOKEN, user, depositAmount);
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), depositAmount);
        wrapper.simpleDeposit(
            SimpleDepositParams({
                farm: _farm(),
                lpToken: LP_TOKEN,
                amountIn: depositAmount,
                extraData: ""
            }),
            _emptyPositionSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        // Warp for rewards
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // Exit = harvest (routed) + withdraw (direct)
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        vm.prank(user);
        wrapper.simpleExit(
            _farm(),
            SimpleHarvestParams({ rewardTokens: rewardTokens, extraData: "" }),
            SimpleWithdrawParams({
                lpToken: LP_TOKEN,
                amountOut: depositAmount,
                extraData: ""
            })
        );

        // User should have both LP and rewards
        assertGt(
            IERC20(LP_TOKEN).balanceOf(user), 0, "user should have LP back"
        );
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(user),
            0,
            "user should have AERO rewards"
        );
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient),
            0,
            "fee recipient should have fee"
        );
    }

    // =====================================================================
    // Access control: attacker cannot operate on user's wrapper
    // =====================================================================

    function test_erc20_attacker_cannot_harvest() public {
        uint256 depositAmount = 1e18;

        deal(LP_TOKEN, user, depositAmount);
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), depositAmount);
        wrapper.simpleDeposit(
            SimpleDepositParams({
                farm: _farm(),
                lpToken: LP_TOKEN,
                amountIn: depositAmount,
                extraData: ""
            }),
            _emptyPositionSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.simpleHarvest(
            _farm(),
            SimpleHarvestParams({ rewardTokens: rewardTokens, extraData: "" })
        );
    }

    // =====================================================================
    // Multiple deposits (increase)
    // =====================================================================

    function test_erc20_increase() public {
        uint256 firstDeposit = 0.5e18;
        uint256 secondDeposit = 0.5e18;

        // First deposit
        deal(LP_TOKEN, user, firstDeposit);
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), firstDeposit);
        wrapper.simpleDeposit(
            SimpleDepositParams({
                farm: _farm(),
                lpToken: LP_TOKEN,
                amountIn: firstDeposit,
                extraData: ""
            }),
            _emptyPositionSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        // Second deposit (increase)
        deal(LP_TOKEN, user, secondDeposit);
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), secondDeposit);
        wrapper.simpleIncrease(
            SimpleDepositParams({
                farm: _farm(),
                lpToken: LP_TOKEN,
                amountIn: secondDeposit,
                extraData: ""
            })
        );
        vm.stopPrank();

        // Withdraw full amount
        vm.prank(user);
        wrapper.simpleWithdraw(
            _farm(),
            SimpleWithdrawParams({
                lpToken: LP_TOKEN,
                amountOut: firstDeposit + secondDeposit,
                extraData: ""
            })
        );

        assertApproxEqAbs(
            IERC20(LP_TOKEN).balanceOf(user),
            firstDeposit + secondDeposit,
            1, // rounding
            "user should get all LP back"
        );
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _emptyPositionSettings()
        internal
        pure
        returns (PositionSettings memory)
    {
        PositionSettings memory ps;
        return ps;
    }
}
