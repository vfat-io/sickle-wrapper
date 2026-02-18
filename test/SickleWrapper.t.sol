// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SickleWrapper} from "../src/SickleWrapper.sol";
import {WrapperFactory} from "../src/WrapperFactory.sol";
import {IFarmStrategy} from "../src/interfaces/IFarmStrategy.sol";
import {INftFarmStrategy} from "../src/interfaces/INftFarmStrategy.sol";
import {ISickleFactory} from "../src/interfaces/ISickleFactory.sol";
import {IRewardRouter} from "../src/interfaces/IRewardRouter.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "../src/interfaces/external/IUniswapV3Pool.sol";

import {
    Farm,
    DepositParams,
    HarvestParams,
    WithdrawParams,
    SimpleDepositParams,
    SimpleHarvestParams,
    SimpleWithdrawParams
} from "../src/structs/FarmStrategyStructs.sol";
import {
    NftPosition,
    NftDeposit,
    NftIncrease,
    NftWithdraw,
    NftHarvest,
    NftRebalance,
    NftMove,
    SimpleNftHarvest
} from "../src/structs/NftFarmStrategyStructs.sol";
import {PositionSettings} from "../src/structs/PositionSettingsStructs.sol";
import {NftSettings} from "../src/structs/NftSettingsStructs.sol";
import {SwapParams} from "../src/structs/SwapStructs.sol";
import {ZapIn, ZapOut} from "../src/structs/ZapStructs.sol";
import {AddLiquidityParams, RemoveLiquidityParams} from "../src/structs/LiquidityStructs.sol";
import {NftZapIn, NftZapOut} from "../src/structs/NftZapStructs.sol";
import {NftAddLiquidity, NftRemoveLiquidity, Pool} from "../src/structs/NftLiquidityStructs.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockFarmStrategy} from "./mocks/MockFarmStrategy.sol";
import {MockNftFarmStrategy} from "./mocks/MockNftFarmStrategy.sol";
import {MockSickleFactory} from "./mocks/MockSickleFactory.sol";
import {MockRewardRouter} from "./mocks/MockRewardRouter.sol";

contract SickleWrapperTest is Test {
    SickleWrapper wrapper;
    WrapperFactory factory;

    MockFarmStrategy farmStrategy;
    MockNftFarmStrategy nftFarmStrategy;
    MockSickleFactory sickleFactory;
    MockRewardRouter rewardRouter;

    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 rewardToken;
    MockERC20 lpToken;
    MockERC721 nft;

    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        rewardToken = new MockERC20("Reward", "RWD");
        lpToken = new MockERC20("LP Token", "LP");
        nft = new MockERC721("NFT Position", "NFT");

        farmStrategy = new MockFarmStrategy();
        nftFarmStrategy = new MockNftFarmStrategy();
        sickleFactory = new MockSickleFactory();
        rewardRouter = new MockRewardRouter();

        factory = new WrapperFactory(
            IFarmStrategy(address(farmStrategy)),
            INftFarmStrategy(address(nftFarmStrategy)),
            sickleFactory,
            IRewardRouter(address(rewardRouter))
        );

        wrapper = factory.getOrCreateWrapper(user);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _farm() internal pure returns (Farm memory) {
        return Farm({stakingContract: address(1), poolIndex: 0});
    }

    function _emptyZapIn() internal pure returns (ZapIn memory) {
        return ZapIn({
            swaps: new SwapParams[](0),
            addLiquidityParams: AddLiquidityParams({
                router: address(0),
                lpToken: address(0),
                tokens: new address[](0),
                desiredAmounts: new uint256[](0),
                minAmounts: new uint256[](0),
                extraData: ""
            })
        });
    }

    function _emptyZapOut() internal pure returns (ZapOut memory) {
        return ZapOut({
            removeLiquidityParams: RemoveLiquidityParams({
                router: address(0),
                lpToken: address(0),
                tokens: new address[](0),
                lpAmountIn: 0,
                minAmountsOut: new uint256[](0),
                extraData: ""
            }),
            swaps: new SwapParams[](0)
        });
    }

    function _emptyNftZapIn() internal pure returns (NftZapIn memory) {
        return NftZapIn({
            swaps: new SwapParams[](0),
            addLiquidityParams: NftAddLiquidity({
                nft: INonfungiblePositionManager(address(0)),
                tokenId: 0,
                pool: Pool({token0: address(0), token1: address(0), fee: 0}),
                tickLower: 0,
                tickUpper: 0,
                amount0Desired: 0,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                extraData: ""
            })
        });
    }

    function _emptyNftZapOut() internal pure returns (NftZapOut memory) {
        return NftZapOut({
            removeLiquidityParams: NftRemoveLiquidity({
                nft: INonfungiblePositionManager(address(0)),
                tokenId: 0,
                liquidity: 0,
                amount0Min: 0,
                amount1Min: 0,
                amount0Max: 0,
                amount1Max: 0,
                extraData: ""
            }),
            swaps: new SwapParams[](0)
        });
    }

    function _emptyPositionSettings() internal pure returns (PositionSettings memory) {
        PositionSettings memory ps;
        return ps;
    }

    function _emptyNftSettings() internal pure returns (NftSettings memory) {
        NftSettings memory ns;
        return ns;
    }

    function _nftPosition() internal view returns (NftPosition memory) {
        return NftPosition({farm: _farm(), nft: INonfungiblePositionManager(address(nft)), tokenId: 1});
    }

    function _setupHarvestRewards(uint256 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        farmStrategy.setHarvestRewards(tokens, amounts);
    }

    function _setupNftHarvestRewards(uint256 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        nftFarmStrategy.setHarvestRewards(tokens, amounts);
    }

    function _singleAddress(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _singleUint(uint256 v) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = v;
    }

    // =========================================================================
    // Access Control
    // =========================================================================

    function test_onlyUser_deposit_reverts() public {
        DepositParams memory params = DepositParams({
            farm: _farm(), tokensIn: new address[](0), amountsIn: new uint256[](0), zap: _emptyZapIn(), extraData: ""
        });

        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.deposit(params, _emptyPositionSettings(), new address[](0), address(0), bytes32(0));
    }

    function test_onlyUser_harvest_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.harvest(
            _farm(),
            HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: new address[](0)}),
            new address[](0)
        );
    }

    function test_onlyUser_withdraw_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.withdraw(
            _farm(), WithdrawParams({extraData: "", zap: _emptyZapOut(), tokensOut: new address[](0)}), new address[](0)
        );
    }

    function test_onlyUser_rescueToken_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.rescueToken(address(tokenA));
    }

    function test_onlyUser_rescueETH_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.rescueETH();
    }

    function test_onlyUser_rescueNft_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.rescueNft(address(nft), 1);
    }

    // =========================================================================
    // ERC20 Deposits
    // =========================================================================

    function test_deposit() public {
        uint256 amount = 100e18;
        tokenA.mint(user, amount);

        vm.startPrank(user);
        tokenA.approve(address(wrapper), amount);

        address[] memory tokensIn = _singleAddress(address(tokenA));
        uint256[] memory amountsIn = _singleUint(amount);

        DepositParams memory params =
            DepositParams({farm: _farm(), tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyZapIn(), extraData: ""});

        wrapper.deposit(params, _emptyPositionSettings(), tokensIn, address(0), bytes32(0));
        vm.stopPrank();

        assertEq(farmStrategy.depositCalls(), 1);
        // Tokens pulled from user into wrapper; mock strategy doesn't consume,
        // so sweep returns them to user. In real system Sickle would pull them.
        assertEq(tokenA.balanceOf(user), amount);
    }

    function test_increase() public {
        uint256 amount = 50e18;
        tokenA.mint(user, amount);

        vm.startPrank(user);
        tokenA.approve(address(wrapper), amount);

        address[] memory tokensIn = _singleAddress(address(tokenA));
        uint256[] memory amountsIn = _singleUint(amount);

        DepositParams memory params =
            DepositParams({farm: _farm(), tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyZapIn(), extraData: ""});

        wrapper.increase(params, tokensIn);
        vm.stopPrank();

        assertEq(farmStrategy.increaseCalls(), 1);
        // Tokens pulled from user (mock strategy doesn't consume them)
    }

    function test_simpleDeposit() public {
        uint256 amount = 100e18;
        lpToken.mint(user, amount);

        vm.startPrank(user);
        lpToken.approve(address(wrapper), amount);

        SimpleDepositParams memory params =
            SimpleDepositParams({farm: _farm(), lpToken: address(lpToken), amountIn: amount, extraData: ""});

        wrapper.simpleDeposit(params, _emptyPositionSettings(), address(0), bytes32(0));
        vm.stopPrank();

        assertEq(farmStrategy.simpleDepositCalls(), 1);
        // Token pulled from user to wrapper (no sweep for simpleDeposit)
        assertEq(lpToken.balanceOf(user), 0);
    }

    function test_simpleIncrease() public {
        uint256 amount = 50e18;
        lpToken.mint(user, amount);

        vm.startPrank(user);
        lpToken.approve(address(wrapper), amount);

        SimpleDepositParams memory params =
            SimpleDepositParams({farm: _farm(), lpToken: address(lpToken), amountIn: amount, extraData: ""});

        wrapper.simpleIncrease(params);
        vm.stopPrank();

        assertEq(farmStrategy.simpleIncreaseCalls(), 1);
        assertEq(lpToken.balanceOf(user), 0);
    }

    // =========================================================================
    // ERC20 Harvest
    // =========================================================================

    function test_harvest() public {
        uint256 rewardAmount = 10e18;
        _setupHarvestRewards(rewardAmount);

        address[] memory sweepTokens = _singleAddress(address(rewardToken));

        vm.prank(user);
        wrapper.harvest(
            _farm(), HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: sweepTokens}), sweepTokens
        );

        assertEq(farmStrategy.harvestCalls(), 1);
        // Rewards routed through router to user
        assertEq(rewardToken.balanceOf(user), rewardAmount);
        assertEq(rewardToken.balanceOf(address(wrapper)), 0);
        assertEq(rewardRouter.lastUser(), user);
        assertEq(rewardRouter.lastWasCompound(), false);
    }

    function test_simpleHarvest() public {
        uint256 rewardAmount = 10e18;
        _setupHarvestRewards(rewardAmount);

        address[] memory rewardTokens = _singleAddress(address(rewardToken));

        vm.prank(user);
        wrapper.simpleHarvest(_farm(), SimpleHarvestParams({rewardTokens: rewardTokens, extraData: ""}));

        assertEq(farmStrategy.simpleHarvestCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
    }

    function test_harvest_noRewards_skipsRouter() public {
        // No rewards configured — strategy mints nothing
        address[] memory sweepTokens = _singleAddress(address(rewardToken));

        vm.prank(user);
        wrapper.harvest(
            _farm(), HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: sweepTokens}), sweepTokens
        );

        assertEq(farmStrategy.harvestCalls(), 1);
        // Router should not have been called
        assertEq(rewardRouter.lastUser(), address(0));
    }

    // =========================================================================
    // ERC20 Compound
    // =========================================================================

    function test_compound() public {
        uint256 rewardAmount = 10e18;
        _setupHarvestRewards(rewardAmount);

        address[] memory harvestSweepTokens = _singleAddress(address(rewardToken));
        address[] memory depositTokensIn = _singleAddress(address(rewardToken));
        uint256[] memory depositAmountsIn = _singleUint(rewardAmount);

        DepositParams memory depositParams = DepositParams({
            farm: _farm(), tokensIn: depositTokensIn, amountsIn: depositAmountsIn, zap: _emptyZapIn(), extraData: ""
        });

        vm.prank(user);
        wrapper.compound(
            _farm(),
            HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: harvestSweepTokens}),
            harvestSweepTokens,
            depositParams,
            harvestSweepTokens
        );

        assertEq(farmStrategy.harvestCalls(), 1);
        assertEq(farmStrategy.increaseCalls(), 1);
        assertEq(rewardRouter.lastWasCompound(), true);
        // Rewards went through router and back to wrapper
        // Mock increase doesn't pull, so tokens remain in wrapper
        // (in real system, Sickle would consume them)
    }

    // =========================================================================
    // ERC20 Withdraw / Exit
    // =========================================================================

    function test_withdraw() public {
        uint256 withdrawAmt = 100e18;
        farmStrategy.setWithdrawResult(address(lpToken), withdrawAmt);

        address[] memory sweepTokens = _singleAddress(address(lpToken));

        vm.prank(user);
        wrapper.withdraw(
            _farm(), WithdrawParams({extraData: "", zap: _emptyZapOut(), tokensOut: sweepTokens}), sweepTokens
        );

        assertEq(farmStrategy.withdrawCalls(), 1);
        assertEq(lpToken.balanceOf(user), withdrawAmt);
        assertEq(lpToken.balanceOf(address(wrapper)), 0);
    }

    function test_simpleWithdraw() public {
        uint256 withdrawAmt = 100e18;
        farmStrategy.setWithdrawResult(address(lpToken), withdrawAmt);

        vm.prank(user);
        wrapper.simpleWithdraw(
            _farm(), SimpleWithdrawParams({lpToken: address(lpToken), amountOut: withdrawAmt, extraData: ""})
        );

        assertEq(farmStrategy.simpleWithdrawCalls(), 1);
        assertEq(lpToken.balanceOf(user), withdrawAmt);
    }

    function test_exit() public {
        uint256 rewardAmount = 10e18;
        uint256 withdrawAmt = 100e18;
        _setupHarvestRewards(rewardAmount);
        farmStrategy.setWithdrawResult(address(lpToken), withdrawAmt);

        address[] memory harvestSweepTokens = _singleAddress(address(rewardToken));
        address[] memory withdrawSweepTokens = _singleAddress(address(lpToken));

        vm.prank(user);
        wrapper.exit(
            _farm(),
            HarvestParams({swaps: new SwapParams[](0), extraData: "", tokensOut: harvestSweepTokens}),
            harvestSweepTokens,
            WithdrawParams({extraData: "", zap: _emptyZapOut(), tokensOut: withdrawSweepTokens}),
            withdrawSweepTokens
        );

        assertEq(farmStrategy.harvestCalls(), 1);
        assertEq(farmStrategy.withdrawCalls(), 1);
        // Rewards routed to user, LP direct to user
        assertEq(rewardToken.balanceOf(user), rewardAmount);
        assertEq(lpToken.balanceOf(user), withdrawAmt);
    }

    function test_simpleExit() public {
        uint256 rewardAmount = 10e18;
        uint256 withdrawAmt = 100e18;
        _setupHarvestRewards(rewardAmount);
        farmStrategy.setWithdrawResult(address(lpToken), withdrawAmt);

        address[] memory rewardTokens = _singleAddress(address(rewardToken));

        vm.prank(user);
        wrapper.simpleExit(
            _farm(),
            SimpleHarvestParams({rewardTokens: rewardTokens, extraData: ""}),
            SimpleWithdrawParams({lpToken: address(lpToken), amountOut: withdrawAmt, extraData: ""})
        );

        assertEq(farmStrategy.simpleHarvestCalls(), 1);
        assertEq(farmStrategy.simpleWithdrawCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
        assertEq(lpToken.balanceOf(user), withdrawAmt);
    }

    // =========================================================================
    // NFT Deposits
    // =========================================================================

    function test_depositNft() public {
        uint256 amount = 100e18;
        tokenA.mint(user, amount);

        address[] memory tokensIn = _singleAddress(address(tokenA));
        uint256[] memory amountsIn = _singleUint(amount);

        NftDeposit memory params = NftDeposit({
            farm: _farm(),
            nft: INonfungiblePositionManager(address(nft)),
            increase: NftIncrease({tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyNftZapIn(), extraData: ""})
        });

        vm.startPrank(user);
        tokenA.approve(address(wrapper), amount);
        wrapper.depositNft(params, _emptyNftSettings(), tokensIn, address(0), bytes32(0));
        vm.stopPrank();

        assertEq(nftFarmStrategy.depositCalls(), 1);
        // Tokens pulled from user to wrapper; mock doesn't consume,
        // sweep sends them back to user
        assertEq(tokenA.balanceOf(user), amount);
    }

    function test_simpleDepositNft() public {
        nft.mint(user, 1);

        vm.startPrank(user);
        nft.approve(address(wrapper), 1);
        wrapper.simpleDepositNft(_nftPosition(), "", _emptyNftSettings(), address(0), bytes32(0));
        vm.stopPrank();

        assertEq(nftFarmStrategy.simpleDepositCalls(), 1);
        // NFT pulled from user to wrapper; mock strategy doesn't pull it
        // (in real system, Sickle would pull the NFT from wrapper)
        assertEq(nft.ownerOf(1), address(wrapper));
    }

    // =========================================================================
    // NFT Harvest
    // =========================================================================

    function test_harvestNft() public {
        uint256 rewardAmount = 10e18;
        _setupNftHarvestRewards(rewardAmount);

        address[] memory sweepTokens = _singleAddress(address(rewardToken));

        NftHarvest memory params = NftHarvest({
            harvest: SimpleNftHarvest({rewardTokens: sweepTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
            swaps: new SwapParams[](0),
            outputTokens: new address[](0),
            sweepTokens: sweepTokens
        });

        vm.prank(user);
        wrapper.harvestNft(_nftPosition(), params);

        assertEq(nftFarmStrategy.harvestCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
    }

    function test_simpleHarvestNft() public {
        uint256 rewardAmount = 10e18;
        _setupNftHarvestRewards(rewardAmount);

        address[] memory rewardTokens = _singleAddress(address(rewardToken));

        vm.prank(user);
        wrapper.simpleHarvestNft(
            _nftPosition(), SimpleNftHarvest({rewardTokens: rewardTokens, amount0Max: 0, amount1Max: 0, extraData: ""})
        );

        assertEq(nftFarmStrategy.simpleHarvestCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
    }

    // =========================================================================
    // NFT Compound
    // =========================================================================

    function test_compoundNft() public {
        uint256 rewardAmount = 10e18;
        _setupNftHarvestRewards(rewardAmount);

        address[] memory sweepTokens = _singleAddress(address(rewardToken));
        address[] memory tokensIn = _singleAddress(address(rewardToken));
        uint256[] memory amountsIn = _singleUint(rewardAmount);

        NftHarvest memory harvestParams = NftHarvest({
            harvest: SimpleNftHarvest({rewardTokens: sweepTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
            swaps: new SwapParams[](0),
            outputTokens: new address[](0),
            sweepTokens: sweepTokens
        });

        NftIncrease memory increaseParams =
            NftIncrease({tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyNftZapIn(), extraData: ""});

        vm.prank(user);
        wrapper.compoundNft(_nftPosition(), harvestParams, increaseParams, sweepTokens);

        assertEq(nftFarmStrategy.harvestCalls(), 1);
        assertEq(nftFarmStrategy.increaseCalls(), 1);
        assertEq(rewardRouter.lastWasCompound(), true);
    }

    // =========================================================================
    // NFT Increase / Decrease
    // =========================================================================

    function test_increaseNft() public {
        uint256 amount = 50e18;
        tokenA.mint(user, amount);

        address[] memory tokensIn = _singleAddress(address(tokenA));
        uint256[] memory amountsIn = _singleUint(amount);

        NftIncrease memory increaseParams =
            NftIncrease({tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyNftZapIn(), extraData: ""});

        NftHarvest memory harvestParams = NftHarvest({
            harvest: SimpleNftHarvest({rewardTokens: new address[](0), amount0Max: 0, amount1Max: 0, extraData: ""}),
            swaps: new SwapParams[](0),
            outputTokens: new address[](0),
            sweepTokens: new address[](0)
        });

        vm.startPrank(user);
        tokenA.approve(address(wrapper), amount);
        wrapper.increaseNft(_nftPosition(), harvestParams, increaseParams, true, tokensIn);
        vm.stopPrank();

        assertEq(nftFarmStrategy.increaseCalls(), 1);
        // Tokens pulled from user to wrapper; mock doesn't consume,
        // sweep sends them back to user
        assertEq(tokenA.balanceOf(user), amount);
    }

    function test_decreaseNft() public {
        uint256 withdrawAmt = 50e18;
        nftFarmStrategy.setWithdrawResult(address(tokenA), withdrawAmt);

        address[] memory sweepTokens = _singleAddress(address(tokenA));

        NftHarvest memory harvestParams = NftHarvest({
            harvest: SimpleNftHarvest({rewardTokens: new address[](0), amount0Max: 0, amount1Max: 0, extraData: ""}),
            swaps: new SwapParams[](0),
            outputTokens: new address[](0),
            sweepTokens: new address[](0)
        });

        NftWithdraw memory withdrawParams = NftWithdraw({zap: _emptyNftZapOut(), tokensOut: sweepTokens, extraData: ""});

        vm.prank(user);
        wrapper.decreaseNft(_nftPosition(), harvestParams, withdrawParams, true, sweepTokens);

        assertEq(nftFarmStrategy.decreaseCalls(), 1);
        assertEq(tokenA.balanceOf(user), withdrawAmt);
    }

    function test_increaseNft_withHarvest() public {
        uint256 amount = 50e18;
        uint256 rewardAmount = 10e18;
        tokenA.mint(user, amount);
        _setupNftHarvestRewards(rewardAmount);

        address[] memory tokensIn = _singleAddress(address(tokenA));
        uint256[] memory amountsIn = _singleUint(amount);
        address[] memory rewardSweepTokens = _singleAddress(address(rewardToken));

        NftIncrease memory increaseParams =
            NftIncrease({tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyNftZapIn(), extraData: ""});

        NftHarvest memory harvestParams = NftHarvest({
            harvest: SimpleNftHarvest({rewardTokens: rewardSweepTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
            swaps: new SwapParams[](0),
            outputTokens: new address[](0),
            sweepTokens: rewardSweepTokens
        });

        vm.startPrank(user);
        tokenA.approve(address(wrapper), amount);
        wrapper.increaseNft(_nftPosition(), harvestParams, increaseParams, false, tokensIn);
        vm.stopPrank();

        assertEq(nftFarmStrategy.increaseCalls(), 1);
        // Rewards routed to user
        assertEq(rewardToken.balanceOf(user), rewardAmount);
    }

    // =========================================================================
    // NFT Withdraw / Exit
    // =========================================================================

    function test_withdrawNft() public {
        uint256 withdrawAmt = 100e18;
        nftFarmStrategy.setWithdrawResult(address(tokenA), withdrawAmt);

        address[] memory sweepTokens = _singleAddress(address(tokenA));

        NftWithdraw memory params = NftWithdraw({zap: _emptyNftZapOut(), tokensOut: sweepTokens, extraData: ""});

        vm.prank(user);
        wrapper.withdrawNft(_nftPosition(), params, sweepTokens);

        assertEq(nftFarmStrategy.withdrawCalls(), 1);
        assertEq(tokenA.balanceOf(user), withdrawAmt);
    }

    function test_simpleWithdrawNft() public {
        // Give NFT to strategy first (simulates it being staked)
        nft.mint(address(nftFarmStrategy), 1);

        vm.prank(user);
        wrapper.simpleWithdrawNft(_nftPosition(), "");

        assertEq(nftFarmStrategy.simpleWithdrawCalls(), 1);
        assertEq(nft.ownerOf(1), user);
    }

    function test_exitNft() public {
        uint256 rewardAmount = 10e18;
        uint256 withdrawAmt = 100e18;
        _setupNftHarvestRewards(rewardAmount);
        nftFarmStrategy.setWithdrawResult(address(tokenA), withdrawAmt);

        address[] memory rewardSweepTokens = _singleAddress(address(rewardToken));
        address[] memory withdrawSweepTokens = _singleAddress(address(tokenA));

        NftHarvest memory harvestParams = NftHarvest({
            harvest: SimpleNftHarvest({rewardTokens: rewardSweepTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
            swaps: new SwapParams[](0),
            outputTokens: new address[](0),
            sweepTokens: rewardSweepTokens
        });

        NftWithdraw memory withdrawParams =
            NftWithdraw({zap: _emptyNftZapOut(), tokensOut: withdrawSweepTokens, extraData: ""});

        vm.prank(user);
        wrapper.exitNft(_nftPosition(), harvestParams, withdrawParams, withdrawSweepTokens);

        assertEq(nftFarmStrategy.harvestCalls(), 1);
        assertEq(nftFarmStrategy.withdrawCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
        assertEq(tokenA.balanceOf(user), withdrawAmt);
    }

    function test_simpleExitNft() public {
        uint256 rewardAmount = 10e18;
        _setupNftHarvestRewards(rewardAmount);
        nft.mint(address(nftFarmStrategy), 1);

        address[] memory rewardTokens = _singleAddress(address(rewardToken));

        vm.prank(user);
        wrapper.simpleExitNft(
            _nftPosition(),
            SimpleNftHarvest({rewardTokens: rewardTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
            ""
        );

        assertEq(nftFarmStrategy.simpleHarvestCalls(), 1);
        assertEq(nftFarmStrategy.simpleWithdrawCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
        assertEq(nft.ownerOf(1), user);
    }

    // =========================================================================
    // NFT Rebalance / Move
    // =========================================================================

    function test_rebalanceNft() public {
        uint256 rewardAmount = 10e18;
        _setupNftHarvestRewards(rewardAmount);

        address[] memory sweepTokens = _singleAddress(address(rewardToken));

        NftRebalance memory params = NftRebalance({
            pool: IUniswapV3Pool(address(0)),
            position: _nftPosition(),
            harvest: NftHarvest({
                harvest: SimpleNftHarvest({rewardTokens: sweepTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
                swaps: new SwapParams[](0),
                outputTokens: new address[](0),
                sweepTokens: sweepTokens
            }),
            withdraw: NftWithdraw({zap: _emptyNftZapOut(), tokensOut: new address[](0), extraData: ""}),
            increase: NftIncrease({
                tokensIn: new address[](0), amountsIn: new uint256[](0), zap: _emptyNftZapIn(), extraData: ""
            })
        });

        vm.prank(user);
        wrapper.rebalanceNft(params, sweepTokens);

        assertEq(nftFarmStrategy.rebalanceCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
    }

    function test_moveNft() public {
        uint256 rewardAmount = 10e18;
        _setupNftHarvestRewards(rewardAmount);

        address[] memory sweepTokens = _singleAddress(address(rewardToken));

        NftMove memory params = NftMove({
            pool: IUniswapV3Pool(address(0)),
            position: _nftPosition(),
            harvest: NftHarvest({
                harvest: SimpleNftHarvest({rewardTokens: sweepTokens, amount0Max: 0, amount1Max: 0, extraData: ""}),
                swaps: new SwapParams[](0),
                outputTokens: new address[](0),
                sweepTokens: sweepTokens
            }),
            withdraw: NftWithdraw({zap: _emptyNftZapOut(), tokensOut: new address[](0), extraData: ""}),
            deposit: NftDeposit({
                farm: _farm(),
                nft: INonfungiblePositionManager(address(nft)),
                increase: NftIncrease({
                    tokensIn: new address[](0), amountsIn: new uint256[](0), zap: _emptyNftZapIn(), extraData: ""
                })
            })
        });

        vm.prank(user);
        wrapper.moveNft(params, _emptyNftSettings(), sweepTokens);

        assertEq(nftFarmStrategy.moveCalls(), 1);
        assertEq(rewardToken.balanceOf(user), rewardAmount);
    }

    // =========================================================================
    // Rescue
    // =========================================================================

    function test_rescueToken() public {
        uint256 amount = 42e18;
        tokenA.mint(address(wrapper), amount);

        vm.prank(user);
        wrapper.rescueToken(address(tokenA));

        assertEq(tokenA.balanceOf(user), amount);
        assertEq(tokenA.balanceOf(address(wrapper)), 0);
    }

    function test_rescueETH() public {
        uint256 amount = 1 ether;
        vm.deal(address(wrapper), amount);

        vm.prank(user);
        wrapper.rescueETH();

        assertEq(user.balance, amount);
        assertEq(address(wrapper).balance, 0);
    }

    function test_rescueNft() public {
        nft.mint(address(wrapper), 42);

        vm.prank(user);
        wrapper.rescueNft(address(nft), 42);

        assertEq(nft.ownerOf(42), user);
    }

    // =========================================================================
    // Edge Cases
    // =========================================================================

    function test_isETH_zeroAddress() public {
        // Wrapper should not try to pull ETH (address(0))
        // This is tested implicitly — deposit with ETH address skips pull
        address[] memory tokensIn = _singleAddress(address(0));
        uint256[] memory amountsIn = _singleUint(1 ether);

        DepositParams memory params =
            DepositParams({farm: _farm(), tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyZapIn(), extraData: ""});

        vm.deal(user, 1 ether);
        vm.prank(user);
        wrapper.deposit{value: 1 ether}(params, _emptyPositionSettings(), new address[](0), address(0), bytes32(0));

        assertEq(farmStrategy.depositCalls(), 1);
    }

    function test_isETH_sentinel() public {
        address[] memory tokensIn = _singleAddress(ETH_ADDRESS);
        uint256[] memory amountsIn = _singleUint(1 ether);

        DepositParams memory params =
            DepositParams({farm: _farm(), tokensIn: tokensIn, amountsIn: amountsIn, zap: _emptyZapIn(), extraData: ""});

        vm.deal(user, 1 ether);
        vm.prank(user);
        wrapper.deposit{value: 1 ether}(params, _emptyPositionSettings(), new address[](0), address(0), bytes32(0));

        assertEq(farmStrategy.depositCalls(), 1);
    }

    function test_receiveETH() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool ok,) = address(wrapper).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(wrapper).balance, 1 ether);
    }

    function test_onERC721Received() public {
        nft.mint(user, 99);

        vm.prank(user);
        nft.safeTransferFrom(user, address(wrapper), 99);

        assertEq(nft.ownerOf(99), address(wrapper));
    }

    function test_approvePattern_resetsFirst() public {
        // Verify the OZ v4.x approve pattern works with repeated deposits
        uint256 amount = 100e18;
        lpToken.mint(user, amount * 2);

        vm.startPrank(user);
        lpToken.approve(address(wrapper), amount * 2);

        SimpleDepositParams memory params =
            SimpleDepositParams({farm: _farm(), lpToken: address(lpToken), amountIn: amount, extraData: ""});

        wrapper.simpleDeposit(params, _emptyPositionSettings(), address(0), bytes32(0));
        // Second deposit — allowance to sickle should reset properly
        wrapper.simpleDeposit(params, _emptyPositionSettings(), address(0), bytes32(0));
        vm.stopPrank();

        assertEq(farmStrategy.simpleDepositCalls(), 2);
        // Both deposits succeeded — approve pattern handled correctly
    }
}
