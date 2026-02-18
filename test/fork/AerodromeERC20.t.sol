// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SickleWrapper} from "../../src/SickleWrapper.sol";
import {
    Farm,
    DepositParams,
    HarvestParams,
    WithdrawParams,
    SimpleDepositParams,
    SimpleHarvestParams,
    SimpleWithdrawParams
} from "../../src/structs/FarmStrategyStructs.sol";
import {ZapIn, ZapOut} from "../../src/structs/ZapStructs.sol";
import {AddLiquidityParams, RemoveLiquidityParams} from "../../src/structs/LiquidityStructs.sol";
import {SwapParams} from "../../src/structs/SwapStructs.sol";
import {PositionSettings} from "../../src/structs/PositionSettingsStructs.sol";

import {ForkTestBase, Base, IVAMMPool, IVAMMGauge} from "./ForkTestBase.sol";
import {MockExtraData} from "./MockSwapConnector.sol";

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
        return Farm({stakingContract: GAUGE, poolIndex: 0});
    }

    /// @dev Deposit LP tokens via simpleDeposit for use as setup in other tests.
    /// Uses deal() on the LP token. NOTE: this creates phantom LP (totalSupply
    /// not updated), so tests that call removeLiquidity should use
    /// _depositTwoToken() instead.
    function _depositLP(uint256 amount) internal {
        deal(LP_TOKEN, user, amount);
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), amount);
        wrapper.simpleDeposit(
            SimpleDepositParams({farm: _farm(), lpToken: LP_TOKEN, amountIn: amount, extraData: ""}),
            _emptyPositionSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    /// @dev Deposit via deposit() with real tokens (WETH + USDC) which mints
    /// real LP tokens through the pool, keeping totalSupply in sync.
    /// Required for tests that later call removeLiquidity.
    function _depositTwoToken(uint256 amount0, uint256 amount1) internal {
        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        address token0 = pool.token0();
        address token1 = pool.token1();

        deal(token0, user, amount0);
        deal(token1, user, amount1);

        address[] memory tokensIn = new address[](2);
        tokensIn[0] = token0;
        tokensIn[1] = token1;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;

        address[] memory liqTokens = new address[](2);
        liqTokens[0] = token0;
        liqTokens[1] = token1;

        DepositParams memory params = DepositParams({
            farm: _farm(),
            tokensIn: tokensIn,
            amountsIn: amountsIn,
            zap: ZapIn({
                swaps: new SwapParams[](0),
                addLiquidityParams: AddLiquidityParams({
                    router: Base.AERODROME_ROUTER,
                    lpToken: LP_TOKEN,
                    tokens: liqTokens,
                    desiredAmounts: new uint256[](2),
                    minAmounts: new uint256[](2),
                    extraData: abi.encode(false)
                })
            }),
            extraData: ""
        });

        address[] memory sweepTokens = new address[](2);
        sweepTokens[0] = token0;
        sweepTokens[1] = token1;

        vm.startPrank(user);
        IERC20(token0).approve(address(wrapper), amount0);
        IERC20(token1).approve(address(wrapper), amount1);
        wrapper.deposit(params, _emptyPositionSettings(), sweepTokens, address(0), bytes32(0));
        vm.stopPrank();
    }

    /// @dev Get the Sickle's staked LP balance in the gauge
    function _stakedBalance() internal view returns (uint256) {
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        return IVAMMGauge(GAUGE).balanceOf(sickle);
    }

    // =====================================================================
    // Simple: simpleDeposit → simpleHarvest → simpleWithdraw
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
            SimpleDepositParams({farm: _farm(), lpToken: LP_TOKEN, amountIn: depositAmount, extraData: ""}),
            _emptyPositionSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        // LP tokens should have been deposited into the gauge via Sickle
        assertEq(IERC20(LP_TOKEN).balanceOf(user), 0, "user LP after deposit");
        assertEq(IERC20(LP_TOKEN).balanceOf(address(wrapper)), 0, "wrapper LP after deposit");

        // --- Warp time to accrue rewards ---
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // --- Harvest ---
        uint256 userAeroBefore = IERC20(REWARD_TOKEN).balanceOf(user);
        uint256 feeRecipientAeroBefore = IERC20(REWARD_TOKEN).balanceOf(feeRecipient);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        vm.prank(user);
        wrapper.simpleHarvest(_farm(), SimpleHarvestParams({rewardTokens: rewardTokens, extraData: ""}));

        uint256 userAeroAfter = IERC20(REWARD_TOKEN).balanceOf(user);
        uint256 feeRecipientAeroAfter = IERC20(REWARD_TOKEN).balanceOf(feeRecipient);
        uint256 userRewards = userAeroAfter - userAeroBefore;
        uint256 feeRewards = feeRecipientAeroAfter - feeRecipientAeroBefore;

        assertGt(userRewards, 0, "user should have received AERO rewards");
        assertGt(feeRewards, 0, "fee recipient should have received fee");

        // Fee should be ~5% of total
        uint256 totalRewards = userRewards + feeRewards;
        assertApproxEqRel(feeRewards, totalRewards * FEE_BPS / 10_000, 0.01e18, "fee ~5%");

        // --- Withdraw ---
        uint256 userLpBefore = IERC20(LP_TOKEN).balanceOf(user);

        vm.prank(user);
        wrapper.simpleWithdraw(
            _farm(), SimpleWithdrawParams({lpToken: LP_TOKEN, amountOut: depositAmount, extraData: ""})
        );

        uint256 userLpAfter = IERC20(LP_TOKEN).balanceOf(user);
        assertGt(userLpAfter, userLpBefore, "user should have LP tokens back after withdraw");
    }

    // =====================================================================
    // Simple: simpleExit (harvest + withdraw in one call)
    // =====================================================================

    function test_erc20_simple_exit() public {
        uint256 depositAmount = 1e18;

        _depositLP(depositAmount);

        // Warp for rewards
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // Exit = harvest (routed) + withdraw (direct)
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        vm.prank(user);
        wrapper.simpleExit(
            _farm(),
            SimpleHarvestParams({rewardTokens: rewardTokens, extraData: ""}),
            SimpleWithdrawParams({lpToken: LP_TOKEN, amountOut: depositAmount, extraData: ""})
        );

        // User should have both LP and rewards
        assertGt(IERC20(LP_TOKEN).balanceOf(user), 0, "user should have LP back");
        assertGt(IERC20(REWARD_TOKEN).balanceOf(user), 0, "user should have AERO rewards");
        assertGt(IERC20(REWARD_TOKEN).balanceOf(feeRecipient), 0, "fee recipient should have fee");
    }

    // =====================================================================
    // Access control: attacker cannot operate on user's wrapper
    // =====================================================================

    function test_erc20_attacker_cannot_harvest() public {
        uint256 depositAmount = 1e18;

        _depositLP(depositAmount);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.simpleHarvest(_farm(), SimpleHarvestParams({rewardTokens: rewardTokens, extraData: ""}));
    }

    // =====================================================================
    // Simple: simpleIncrease (multiple deposits)
    // =====================================================================

    function test_erc20_increase() public {
        uint256 firstDeposit = 0.5e18;
        uint256 secondDeposit = 0.5e18;

        // First deposit
        _depositLP(firstDeposit);

        // Second deposit (increase)
        deal(LP_TOKEN, user, secondDeposit);
        vm.startPrank(user);
        IERC20(LP_TOKEN).approve(address(wrapper), secondDeposit);
        wrapper.simpleIncrease(
            SimpleDepositParams({farm: _farm(), lpToken: LP_TOKEN, amountIn: secondDeposit, extraData: ""})
        );
        vm.stopPrank();

        // Withdraw full amount
        vm.prank(user);
        wrapper.simpleWithdraw(
            _farm(), SimpleWithdrawParams({lpToken: LP_TOKEN, amountOut: firstDeposit + secondDeposit, extraData: ""})
        );

        assertApproxEqAbs(
            IERC20(LP_TOKEN).balanceOf(user),
            firstDeposit + secondDeposit,
            1, // rounding
            "user should get all LP back"
        );
    }

    // =====================================================================
    // deposit() — two-token deposit via addLiquidity zap
    // =====================================================================

    function test_erc20_deposit_twoToken() public {
        // Get pool token order
        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        address token0 = pool.token0();
        address token1 = pool.token1();

        // Provide both tokens — router handles proportional amounts
        uint256 amount0 = 1e18; // WETH (token0)
        uint256 amount1 = 3000e6; // USDC (token1, 6 decimals)

        deal(token0, user, amount0);
        deal(token1, user, amount1);

        address[] memory tokensIn = new address[](2);
        tokensIn[0] = token0;
        tokensIn[1] = token1;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;

        // AddLiquidity: Aerodrome router, VAMM pool, no swaps
        address[] memory liqTokens = new address[](2);
        liqTokens[0] = token0;
        liqTokens[1] = token1;

        uint256[] memory desiredAmounts = new uint256[](2);
        // 0,0 = auto-fill from Sickle balance
        uint256[] memory minAmounts = new uint256[](2);

        DepositParams memory params = DepositParams({
            farm: _farm(),
            tokensIn: tokensIn,
            amountsIn: amountsIn,
            zap: ZapIn({
                swaps: new SwapParams[](0),
                addLiquidityParams: AddLiquidityParams({
                    router: Base.AERODROME_ROUTER,
                    lpToken: LP_TOKEN,
                    tokens: liqTokens,
                    desiredAmounts: desiredAmounts,
                    minAmounts: minAmounts,
                    extraData: abi.encode(false) // isStablePool = false (volatile)
                })
            }),
            extraData: ""
        });

        address[] memory sweepTokens = new address[](2);
        sweepTokens[0] = token0;
        sweepTokens[1] = token1;

        vm.startPrank(user);
        IERC20(token0).approve(address(wrapper), amount0);
        IERC20(token1).approve(address(wrapper), amount1);
        wrapper.deposit(params, _emptyPositionSettings(), sweepTokens, address(0), bytes32(0));
        vm.stopPrank();

        // LP should be staked in gauge
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        uint256 staked = IVAMMGauge(GAUGE).balanceOf(sickle);
        assertGt(staked, 0, "sickle should have LP staked in gauge");

        // Wrapper should not hold any tokens
        assertEq(IERC20(LP_TOKEN).balanceOf(address(wrapper)), 0, "wrapper LP should be 0");
    }

    // =====================================================================
    // increase() — add more tokens via addLiquidity zap
    // =====================================================================

    function test_erc20_increase_twoToken() public {
        // First do a simple deposit
        _depositLP(1e18);

        // Now do an increase with two tokens via zap
        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        address token0 = pool.token0();
        address token1 = pool.token1();

        uint256 amount0 = 0.5e18;
        uint256 amount1 = 1500e6;

        deal(token0, user, amount0);
        deal(token1, user, amount1);

        address[] memory tokensIn = new address[](2);
        tokensIn[0] = token0;
        tokensIn[1] = token1;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;

        address[] memory liqTokens = new address[](2);
        liqTokens[0] = token0;
        liqTokens[1] = token1;

        uint256[] memory desiredAmounts = new uint256[](2);
        uint256[] memory minAmounts = new uint256[](2);

        DepositParams memory params = DepositParams({
            farm: _farm(),
            tokensIn: tokensIn,
            amountsIn: amountsIn,
            zap: ZapIn({
                swaps: new SwapParams[](0),
                addLiquidityParams: AddLiquidityParams({
                    router: Base.AERODROME_ROUTER,
                    lpToken: LP_TOKEN,
                    tokens: liqTokens,
                    desiredAmounts: desiredAmounts,
                    minAmounts: minAmounts,
                    extraData: abi.encode(false)
                })
            }),
            extraData: ""
        });

        address[] memory sweepTokens = new address[](2);
        sweepTokens[0] = token0;
        sweepTokens[1] = token1;

        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        uint256 stakedBefore = IVAMMGauge(GAUGE).balanceOf(sickle);

        vm.startPrank(user);
        IERC20(token0).approve(address(wrapper), amount0);
        IERC20(token1).approve(address(wrapper), amount1);
        wrapper.increase(params, sweepTokens);
        vm.stopPrank();

        uint256 stakedAfter = IVAMMGauge(GAUGE).balanceOf(sickle);
        assertGt(stakedAfter, stakedBefore, "staked LP should increase");
    }

    // =====================================================================
    // harvest() — non-simple harvest with HarvestParams (no swap)
    // =====================================================================

    function test_erc20_harvest_withParams() public {
        _depositLP(1e18);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // Non-simple harvest: claim rewards, no swap, fee on tokensOut
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = REWARD_TOKEN;

        address[] memory sweepTokens = new address[](1);
        sweepTokens[0] = REWARD_TOKEN;

        HarvestParams memory params = HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: tokensOut});

        uint256 userAeroBefore = IERC20(REWARD_TOKEN).balanceOf(user);

        vm.prank(user);
        wrapper.harvest(_farm(), params, sweepTokens);

        uint256 userAeroAfter = IERC20(REWARD_TOKEN).balanceOf(user);
        assertGt(userAeroAfter, userAeroBefore, "user should have AERO rewards after harvest()");
        assertGt(IERC20(REWARD_TOKEN).balanceOf(feeRecipient), 0, "fee recipient should have fee");
    }

    // =====================================================================
    // withdraw() — non-simple withdraw with removeLiquidity zap
    // =====================================================================

    function test_erc20_withdraw_to_underlying() public {
        // Use real two-token deposit so removeLiquidity works correctly
        _depositTwoToken(1e18, 3000e6);

        uint256 staked = _stakedBalance();
        assertGt(staked, 0, "should have staked LP");

        WithdrawParams memory params = _buildWithdrawParams(staked);
        address[] memory sweepTokens = _tokenPairArray();

        vm.prank(user);
        wrapper.withdraw(_farm(), params, sweepTokens);

        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        // User should have received underlying tokens (WETH + USDC)
        assertGt(IERC20(pool.token0()).balanceOf(user), 0, "user should have WETH after withdraw");
        assertGt(IERC20(pool.token1()).balanceOf(user), 0, "user should have USDC after withdraw");
    }

    // =====================================================================
    // exit() — non-simple exit: harvest (routed) + withdraw (direct)
    // =====================================================================

    function test_erc20_exit_full() public {
        // Use real two-token deposit so removeLiquidity works correctly
        _depositTwoToken(1e18, 3000e6);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        HarvestParams memory harvestParams = _buildHarvestParams();
        address[] memory harvestSweepTokens = _aeroArray();

        uint256 staked = _stakedBalance();
        WithdrawParams memory withdrawParams = _buildWithdrawParams(staked);
        address[] memory withdrawSweepTokens = _tokenPairArray();

        vm.prank(user);
        wrapper.exit(_farm(), harvestParams, harvestSweepTokens, withdrawParams, withdrawSweepTokens);

        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        // User should have underlying tokens + AERO rewards
        assertGt(IERC20(pool.token0()).balanceOf(user), 0, "user should have WETH");
        assertGt(IERC20(pool.token1()).balanceOf(user), 0, "user should have USDC");
        assertGt(IERC20(REWARD_TOKEN).balanceOf(user), 0, "user should have AERO rewards");
        assertGt(IERC20(REWARD_TOKEN).balanceOf(feeRecipient), 0, "fee recipient should have fee");
    }

    // =====================================================================
    // compound() — harvest rewards, route (compound mode), swap, re-deposit
    // =====================================================================

    function test_erc20_compound() public {
        // Deposit real tokens so the position is valid for re-deposit
        _depositTwoToken(1e18, 3000e6);

        uint256 stakedBefore = _stakedBalance();
        assertGt(stakedBefore, 0, "should have staked LP");

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // Build harvest params: claim AERO, then swap AERO→WETH via mock
        HarvestParams memory harvestParams = _buildHarvestParamsWithSwap();

        // Sweep WETH (the OUTPUT of the swap, not input AERO)
        address[] memory harvestSweepTokens = new address[](1);
        harvestSweepTokens[0] = Base.WETH;

        // Build deposit params: re-deposit WETH into the pool.
        // The wrapper's WETH balance after harvest+route is reduced by both
        // the Sickle protocol fee (~0.9%) and our RewardRouter fee (5%).
        // Use a conservative amount that's safely below the actual balance.
        DepositParams memory depositParams = _buildCompoundDepositParams(0.45e18);
        address[] memory depositSweepTokens = _tokenPairArray();

        vm.prank(user);
        wrapper.compound(_farm(), harvestParams, harvestSweepTokens, depositParams, depositSweepTokens);

        // Staked LP should have increased from the compounded rewards
        uint256 stakedAfter = _stakedBalance();
        assertGt(stakedAfter, stakedBefore, "staked LP should increase after compound");

        // Fee recipient should have received a WETH fee (harvest swaps AERO→WETH)
        assertGt(IERC20(Base.WETH).balanceOf(feeRecipient), 0, "fee recipient should have WETH fee");
    }

    // =====================================================================
    // Rescue functions
    // =====================================================================

    function test_rescueToken() public {
        // Accidentally send tokens to the wrapper
        uint256 amount = 1e18;
        deal(Base.WETH, address(wrapper), amount);

        assertEq(IERC20(Base.WETH).balanceOf(address(wrapper)), amount);

        vm.prank(user);
        wrapper.rescueToken(Base.WETH);

        assertEq(IERC20(Base.WETH).balanceOf(address(wrapper)), 0, "wrapper should have 0 after rescue");
        assertEq(IERC20(Base.WETH).balanceOf(user), amount, "user should have rescued tokens");
    }

    function test_rescueETH() public {
        // Send ETH to the wrapper
        uint256 amount = 1 ether;
        deal(address(wrapper), amount);

        assertEq(address(wrapper).balance, amount);

        vm.prank(user);
        wrapper.rescueETH();

        assertEq(address(wrapper).balance, 0, "wrapper should have 0 ETH");
        assertEq(user.balance, amount, "user should have rescued ETH");
    }

    function test_rescueToken_onlyUser() public {
        deal(Base.WETH, address(wrapper), 1e18);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.rescueToken(Base.WETH);
    }

    function test_rescueETH_onlyUser() public {
        deal(address(wrapper), 1 ether);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.rescueETH();
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _emptyPositionSettings() internal pure returns (PositionSettings memory) {
        PositionSettings memory ps;
        return ps;
    }

    function _aeroArray() internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = REWARD_TOKEN;
    }

    function _tokenPairArray() internal view returns (address[] memory arr) {
        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        arr = new address[](2);
        arr[0] = pool.token0();
        arr[1] = pool.token1();
    }

    function _buildHarvestParams() internal pure returns (HarvestParams memory) {
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = REWARD_TOKEN;

        return HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: tokensOut});
    }

    /// @dev Build HarvestParams that swap AERO → WETH via the mock router.
    /// The mock router just deal()s the output tokens.
    function _buildHarvestParamsWithSwap() internal view returns (HarvestParams memory) {
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = Base.WETH;

        SwapParams[] memory swaps = new SwapParams[](1);
        swaps[0] = SwapParams({
            tokenApproval: mockRouter,
            router: mockRouter,
            amountIn: 1, // mock connector ignores actual amount, uses deal()
            desiredAmountOut: 0,
            minAmountOut: 0.5e18, // mock will deal this much WETH
            tokenIn: REWARD_TOKEN,
            tokenOut: Base.WETH,
            extraData: abi.encode(MockExtraData({tokenOut: Base.WETH}))
        });

        return HarvestParams({swaps: swaps, extraData: "", tokensOut: tokensOut});
    }

    /// @dev Build DepositParams for re-depositing WETH into the VAMM pool.
    /// Used in compound: the router returns WETH, which must be split into
    /// both pool tokens (volatile AMMs require both). Includes a mock swap
    /// WETH → USDC for half the amount.
    function _buildCompoundDepositParams(uint256 wethAmount) internal view returns (DepositParams memory) {
        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        address token0 = pool.token0();
        address token1 = pool.token1();

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = Base.WETH;

        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = wethAmount;

        address[] memory liqTokens = new address[](2);
        liqTokens[0] = token0;
        liqTokens[1] = token1;

        // Swap half WETH → USDC via mock so we have both pool tokens
        uint256 halfWeth = wethAmount / 2;
        // Approximate USDC amount for half WETH at ~$3000
        uint256 usdcOut = 1400e6;

        SwapParams[] memory swaps = new SwapParams[](1);
        swaps[0] = SwapParams({
            tokenApproval: mockRouter,
            router: mockRouter,
            amountIn: halfWeth,
            desiredAmountOut: 0,
            minAmountOut: usdcOut,
            tokenIn: Base.WETH,
            tokenOut: Base.USDC,
            extraData: abi.encode(MockExtraData({tokenOut: Base.USDC}))
        });

        return DepositParams({
            farm: _farm(),
            tokensIn: tokensIn,
            amountsIn: amountsIn,
            zap: ZapIn({
                swaps: swaps,
                addLiquidityParams: AddLiquidityParams({
                    router: Base.AERODROME_ROUTER,
                    lpToken: LP_TOKEN,
                    tokens: liqTokens,
                    desiredAmounts: new uint256[](2),
                    minAmounts: new uint256[](2),
                    extraData: abi.encode(false) // volatile pool
                })
            }),
            extraData: ""
        });
    }

    function _buildWithdrawParams(uint256 lpAmount) internal view returns (WithdrawParams memory) {
        IVAMMPool pool = IVAMMPool(LP_TOKEN);
        address token0 = pool.token0();
        address token1 = pool.token1();

        address[] memory liqTokens = new address[](2);
        liqTokens[0] = token0;
        liqTokens[1] = token1;

        address[] memory tokensOut = new address[](2);
        tokensOut[0] = token0;
        tokensOut[1] = token1;

        return WithdrawParams({
            extraData: "",
            zap: ZapOut({
                removeLiquidityParams: RemoveLiquidityParams({
                    router: Base.AERODROME_ROUTER,
                    lpToken: LP_TOKEN,
                    tokens: liqTokens,
                    lpAmountIn: lpAmount,
                    minAmountsOut: new uint256[](2),
                    extraData: abi.encode(false)
                }),
                swaps: new SwapParams[](0)
            }),
            tokensOut: tokensOut
        });
    }
}
