// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { SickleWrapper } from "../../src/SickleWrapper.sol";
import { INonfungiblePositionManager } from
    "../../src/interfaces/external/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from
    "../../src/interfaces/external/IUniswapV3Pool.sol";
import {
    NftPosition,
    NftDeposit,
    NftIncrease,
    NftWithdraw,
    NftHarvest,
    NftRebalance,
    SimpleNftHarvest
} from "../../src/structs/NftFarmStrategyStructs.sol";
import { NftZapIn, NftZapOut } from "../../src/structs/NftZapStructs.sol";
import {
    NftAddLiquidity,
    NftRemoveLiquidity,
    Pool
} from "../../src/structs/NftLiquidityStructs.sol";
import { SwapParams } from "../../src/structs/SwapStructs.sol";
import { NftSettings } from "../../src/structs/NftSettingsStructs.sol";
import { Farm } from "../../src/structs/FarmStrategyStructs.sol";

import {
    ForkTestBase,
    Base,
    ICLPool,
    ICLGauge,
    ISlipstreamNFTManager,
    IPositionManager
} from "./ForkTestBase.sol";

/// @title AerodromeNFT Fork Tests
/// @notice Full lifecycle tests for CL (NFT) positions through the wrapper.
///         Uses the deployed Sickle infrastructure on Base with Aerodrome Slipstream.
///
/// Run: forge test --match-contract AerodromeNFTForkTest -vvv
contract AerodromeNFTForkTest is ForkTestBase {
    SickleWrapper wrapper;

    address constant POOL = Base.CL200_WETH_AERO;
    address constant GAUGE = Base.CL200_WETH_AERO_GAUGE;
    address constant NFT_MANAGER = Base.SLIPSTREAM_NFT_MANAGER;
    address constant REWARD_TOKEN = Base.AERO;

    function setUp() public {
        _setUpFork();
        wrapper = _createWrapper();
    }

    function _farm() internal pure returns (Farm memory) {
        return Farm({ stakingContract: GAUGE, poolIndex: 0 });
    }

    function _nftPosition(
        uint256 tokenId
    ) internal pure returns (NftPosition memory) {
        return NftPosition({
            farm: Farm({ stakingContract: GAUGE, poolIndex: 0 }),
            nft: INonfungiblePositionManager(NFT_MANAGER),
            tokenId: tokenId
        });
    }

    function _emptyNftSettings()
        internal
        pure
        returns (NftSettings memory)
    {
        NftSettings memory ns;
        return ns;
    }

    /// @dev Mint a CL NFT position to the given recipient by providing liquidity
    ///      around the current tick.
    function _mintCLPosition(
        address recipient
    ) internal returns (uint256 tokenId) {
        ICLPool pool = ICLPool(POOL);
        address token0 = pool.token0();
        address token1 = pool.token1();
        int24 tickSpacing = pool.tickSpacing();
        (, int24 currentTick,,,,) = pool.slot0();

        // Set a wide range around current tick
        int24 tickLower =
            _closestLowerTick(currentTick - 10 * tickSpacing, tickSpacing);
        int24 tickUpper =
            _closestUpperTick(currentTick + 10 * tickSpacing, tickSpacing);

        // Deal tokens to this contract for minting
        uint256 amount0 = 1e18; // WETH
        uint256 amount1 = 1000e18; // AERO
        deal(token0, address(this), amount0);
        deal(token1, address(this), amount1);

        IERC20(token0).approve(NFT_MANAGER, amount0);
        IERC20(token1).approve(NFT_MANAGER, amount1);

        (tokenId,,,) = ISlipstreamNFTManager(NFT_MANAGER).mint(
            ISlipstreamNFTManager.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: tickSpacing,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: block.timestamp + 1 hours,
                sqrtPriceX96: 0
            })
        );
    }

    /// @dev Deposit an NFT via simpleDepositNft for use as setup in other tests
    function _depositNFT(uint256 tokenId) internal {
        vm.startPrank(user);
        IERC721(NFT_MANAGER).approve(address(wrapper), tokenId);
        wrapper.simpleDepositNft(
            _nftPosition(tokenId),
            "",
            _emptyNftSettings(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    /// @dev Helper to get the liquidity of a position
    function _getLiquidity(
        uint256 tokenId
    ) internal view returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) =
            IPositionManager(NFT_MANAGER).positions(tokenId);
    }

    /// @dev Build a simple NftHarvest with no swaps — just claim raw rewards
    function _buildSimpleNftHarvest()
        internal
        pure
        returns (NftHarvest memory)
    {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        address[] memory outputTokens = new address[](1);
        outputTokens[0] = REWARD_TOKEN;

        address[] memory sweepTokens = new address[](1);
        sweepTokens[0] = REWARD_TOKEN;

        return NftHarvest({
            harvest: SimpleNftHarvest({
                rewardTokens: rewardTokens,
                amount0Max: 0,
                amount1Max: 0,
                extraData: ""
            }),
            swaps: new SwapParams[](0),
            outputTokens: outputTokens,
            sweepTokens: sweepTokens
        });
    }

    /// @dev Build NftWithdraw params to remove liquidity to underlying tokens
    function _buildNftWithdraw(
        uint256 tokenId,
        uint128 liquidity
    ) internal view returns (NftWithdraw memory) {
        ICLPool pool = ICLPool(POOL);
        address token0 = pool.token0();
        address token1 = pool.token1();

        address[] memory tokensOut = new address[](2);
        tokensOut[0] = token0;
        tokensOut[1] = token1;

        return NftWithdraw({
            zap: NftZapOut({
                removeLiquidityParams: NftRemoveLiquidity({
                    nft: INonfungiblePositionManager(NFT_MANAGER),
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max,
                    extraData: ""
                }),
                swaps: new SwapParams[](0)
            }),
            tokensOut: tokensOut,
            extraData: ""
        });
    }

    // =====================================================================
    // Simple: simpleDepositNft → simpleHarvestNft → simpleWithdrawNft
    // =====================================================================

    function test_nft_full_lifecycle() public {
        // Mint CL NFT to user
        uint256 tokenId = _mintCLPosition(user);
        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId), user);

        // --- Deposit NFT ---
        _depositNFT(tokenId);

        // NFT should have moved from user → wrapper → Sickle → gauge
        assertNotEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            user,
            "user should not own NFT after deposit"
        );

        // Verify gauge has the NFT staked for the wrapper's Sickle
        ICLGauge gauge = ICLGauge(GAUGE);
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        uint256 stakedLen = gauge.stakedLength(sickle);
        assertGt(stakedLen, 0, "sickle should have staked NFTs in gauge");

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
        wrapper.simpleHarvestNft(
            _nftPosition(tokenId),
            SimpleNftHarvest({
                rewardTokens: rewardTokens,
                amount0Max: 0,
                amount1Max: 0,
                extraData: ""
            })
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
            feeRewards,
            totalRewards * FEE_BPS / 10_000,
            0.01e18,
            "fee ~5%"
        );

        // --- Withdraw NFT ---
        vm.prank(user);
        wrapper.simpleWithdrawNft(_nftPosition(tokenId), "");

        assertEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            user,
            "user should own NFT after withdraw"
        );
    }

    // =====================================================================
    // Simple: simpleExitNft (harvest + withdraw in one call)
    // =====================================================================

    function test_nft_simple_exit() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        // Warp for rewards
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        vm.prank(user);
        wrapper.simpleExitNft(
            _nftPosition(tokenId),
            SimpleNftHarvest({
                rewardTokens: rewardTokens,
                amount0Max: 0,
                amount1Max: 0,
                extraData: ""
            }),
            ""
        );

        // User should have NFT back and rewards
        assertEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            user,
            "user should have NFT back"
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

    function test_nft_attacker_cannot_harvest() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = REWARD_TOKEN;

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.simpleHarvestNft(
            _nftPosition(tokenId),
            SimpleNftHarvest({
                rewardTokens: rewardTokens,
                amount0Max: 0,
                amount1Max: 0,
                extraData: ""
            })
        );
    }

    // =====================================================================
    // Multiple deposits (two positions from same user)
    // =====================================================================

    function test_nft_two_positions() public {
        uint256 tokenId1 = _mintCLPosition(user);
        uint256 tokenId2 = _mintCLPosition(user);

        _depositNFT(tokenId1);
        _depositNFT(tokenId2);

        // Both should be staked
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        ICLGauge gauge = ICLGauge(GAUGE);
        assertEq(
            gauge.stakedLength(sickle), 2, "sickle should have 2 staked NFTs"
        );

        // Withdraw both
        vm.startPrank(user);
        wrapper.simpleWithdrawNft(_nftPosition(tokenId1), "");
        wrapper.simpleWithdrawNft(_nftPosition(tokenId2), "");
        vm.stopPrank();

        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId1), user, "user owns 1");
        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId2), user, "user owns 2");
    }

    // =====================================================================
    // harvestNft() — non-simple harvest with NftHarvest (no swap)
    // =====================================================================

    function test_nft_harvestNft_withParams() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        NftHarvest memory harvestParams = _buildSimpleNftHarvest();

        uint256 userAeroBefore = IERC20(REWARD_TOKEN).balanceOf(user);

        vm.prank(user);
        wrapper.harvestNft(_nftPosition(tokenId), harvestParams);

        uint256 userAeroAfter = IERC20(REWARD_TOKEN).balanceOf(user);
        assertGt(
            userAeroAfter,
            userAeroBefore,
            "user should have AERO rewards after harvestNft()"
        );
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient),
            0,
            "fee recipient should have fee"
        );
    }

    // =====================================================================
    // withdrawNft() — remove liquidity, receive underlying tokens
    // =====================================================================

    function test_nft_withdrawNft_to_underlying() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        ICLPool pool = ICLPool(POOL);
        address token0 = pool.token0();
        address token1 = pool.token1();

        uint128 liquidity = _getLiquidity(tokenId);
        NftWithdraw memory withdrawParams =
            _buildNftWithdraw(tokenId, liquidity);

        address[] memory sweepTokens = new address[](2);
        sweepTokens[0] = token0;
        sweepTokens[1] = token1;

        vm.prank(user);
        wrapper.withdrawNft(
            _nftPosition(tokenId), withdrawParams, sweepTokens
        );

        // User should have received underlying tokens
        assertGt(
            IERC20(token0).balanceOf(user), 0, "user should have WETH"
        );
        assertGt(
            IERC20(token1).balanceOf(user), 0, "user should have AERO"
        );
    }

    // =====================================================================
    // exitNft() — harvest (routed) + withdraw (direct) in one call
    // =====================================================================

    function test_nft_exitNft_full() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        ICLPool pool = ICLPool(POOL);
        address token0 = pool.token0();
        address token1 = pool.token1();

        NftHarvest memory harvestParams = _buildSimpleNftHarvest();

        uint128 liquidity = _getLiquidity(tokenId);
        NftWithdraw memory withdrawParams =
            _buildNftWithdraw(tokenId, liquidity);

        address[] memory sweepTokens = new address[](2);
        sweepTokens[0] = token0;
        sweepTokens[1] = token1;

        vm.prank(user);
        wrapper.exitNft(
            _nftPosition(tokenId), harvestParams, withdrawParams, sweepTokens
        );

        // User should have underlying tokens + AERO rewards
        assertGt(IERC20(token0).balanceOf(user), 0, "user should have WETH");
        assertGt(IERC20(token1).balanceOf(user), 0, "user should have AERO");
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient),
            0,
            "fee recipient should have fee from harvest"
        );
    }

    // =====================================================================
    // depositNft() — mint new NFT from tokens via zap
    // =====================================================================

    function test_nft_depositNft_from_tokens() public {
        uint256 amount0 = 1e18; // WETH
        uint256 amount1 = 1000e18; // AERO

        _dealPoolTokens(user, amount0, amount1);

        NftDeposit memory params =
            _buildNftDeposit(amount0, amount1);

        vm.startPrank(user);
        IERC20(ICLPool(POOL).token0()).approve(address(wrapper), amount0);
        IERC20(ICLPool(POOL).token1()).approve(address(wrapper), amount1);
        wrapper.depositNft(
            params,
            _emptyNftSettings(),
            _poolTokenArray(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        // NFT should be staked in gauge
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        assertGt(
            ICLGauge(GAUGE).stakedLength(sickle),
            0,
            "sickle should have staked NFT"
        );
    }

    // =====================================================================
    // increaseNft() with inPlace=false — harvest then increase
    // NOTE: inPlace=true is not supported for Slipstream gauge-staked NFTs
    //       because the strategy doesn't unstake before modifying liquidity.
    // =====================================================================

    function test_nft_increaseNft_withHarvest() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        uint128 liquidityBefore = _getLiquidity(tokenId);
        uint256 userAeroBefore = IERC20(REWARD_TOKEN).balanceOf(user);

        NftIncrease memory increaseParams =
            _buildNftIncrease(tokenId, 0.5e18, 500e18);

        _dealPoolTokens(user, 0.5e18, 500e18);

        vm.startPrank(user);
        IERC20(ICLPool(POOL).token0()).approve(address(wrapper), 0.5e18);
        IERC20(ICLPool(POOL).token1()).approve(address(wrapper), 500e18);
        wrapper.increaseNft(
            _nftPosition(tokenId),
            _buildSimpleNftHarvest(),
            increaseParams,
            false, // inPlace=false → harvest first
            _poolTokenArray()
        );
        vm.stopPrank();

        assertGt(
            _getLiquidity(tokenId),
            liquidityBefore,
            "liquidity should increase"
        );
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(user),
            userAeroBefore,
            "user should have AERO from harvest"
        );
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient),
            0,
            "fee recipient should have fee"
        );
    }

    // =====================================================================
    // decreaseNft() with inPlace=false — harvest then decrease
    // NOTE: inPlace=true is not supported for Slipstream gauge-staked NFTs
    //       because the strategy doesn't unstake before modifying liquidity.
    // =====================================================================

    function test_nft_decreaseNft_withHarvest() public {
        uint256 tokenId = _mintCLPosition(user);
        _depositNFT(tokenId);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        ICLPool pool = ICLPool(POOL);
        address token0 = pool.token0();
        address token1 = pool.token1();

        uint128 totalLiquidity = _getLiquidity(tokenId);
        uint128 halfLiquidity = totalLiquidity / 2;

        NftWithdraw memory withdrawParams =
            _buildNftWithdraw(tokenId, halfLiquidity);
        NftHarvest memory harvestParams = _buildSimpleNftHarvest();

        address[] memory sweepTokens = new address[](2);
        sweepTokens[0] = token0;
        sweepTokens[1] = token1;

        uint256 userAeroBefore = IERC20(REWARD_TOKEN).balanceOf(user);

        vm.prank(user);
        wrapper.decreaseNft(
            _nftPosition(tokenId),
            harvestParams,
            withdrawParams,
            false, // inPlace=false → harvest first
            sweepTokens
        );

        // Position should have less liquidity
        uint128 remainingLiquidity = _getLiquidity(tokenId);
        assertLt(
            remainingLiquidity,
            totalLiquidity,
            "liquidity should decrease"
        );

        // User should have underlying tokens
        assertGt(IERC20(token0).balanceOf(user), 0, "user should have WETH");
        assertGt(IERC20(token1).balanceOf(user), 0, "user should have AERO");

        // Rewards should have been routed
        uint256 userAeroAfter = IERC20(REWARD_TOKEN).balanceOf(user);
        assertGt(
            userAeroAfter,
            userAeroBefore,
            "user should have AERO from harvest"
        );
        assertGt(
            IERC20(REWARD_TOKEN).balanceOf(feeRecipient),
            0,
            "fee recipient should have fee"
        );
    }

    // =====================================================================
    // Rescue NFT
    // =====================================================================

    function test_rescueNft() public {
        // Mint NFT directly to wrapper (simulate accidental transfer)
        uint256 tokenId = _mintCLPosition(address(wrapper));
        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId), address(wrapper));

        vm.prank(user);
        wrapper.rescueNft(NFT_MANAGER, tokenId);

        assertEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            user,
            "user should have rescued NFT"
        );
    }

    function test_rescueNft_onlyUser() public {
        uint256 tokenId = _mintCLPosition(address(wrapper));

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SickleWrapper.NotUser.selector);
        wrapper.rescueNft(NFT_MANAGER, tokenId);
    }

    // =====================================================================
    // Additional helpers
    // =====================================================================

    function _poolTokenArray() internal view returns (address[] memory arr) {
        ICLPool pool = ICLPool(POOL);
        arr = new address[](2);
        arr[0] = pool.token0();
        arr[1] = pool.token1();
    }

    function _dealPoolTokens(
        address to,
        uint256 amount0,
        uint256 amount1
    ) internal {
        ICLPool pool = ICLPool(POOL);
        deal(pool.token0(), to, amount0);
        deal(pool.token1(), to, amount1);
    }

    /// @dev Build NftDeposit params for a new mint from two tokens
    function _buildNftDeposit(
        uint256 amount0,
        uint256 amount1
    ) internal view returns (NftDeposit memory) {
        address[] memory tokensIn = _poolTokenArray();

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;

        return NftDeposit({
            farm: _farm(),
            nft: INonfungiblePositionManager(NFT_MANAGER),
            increase: NftIncrease({
                tokensIn: tokensIn,
                amountsIn: amountsIn,
                zap: NftZapIn({
                    swaps: new SwapParams[](0),
                    addLiquidityParams: _buildAddLiquidity(0, amount0, amount1)
                }),
                extraData: ""
            })
        });
    }

    /// @dev Build NftIncrease params for an existing position
    function _buildNftIncrease(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (NftIncrease memory) {
        address[] memory tokensIn = _poolTokenArray();

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;

        return NftIncrease({
            tokensIn: tokensIn,
            amountsIn: amountsIn,
            zap: NftZapIn({
                swaps: new SwapParams[](0),
                addLiquidityParams: _buildAddLiquidity(
                    tokenId, amount0, amount1
                )
            }),
            extraData: ""
        });
    }

    /// @dev Build NftAddLiquidity params (shared by deposit and increase)
    function _buildAddLiquidity(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (NftAddLiquidity memory) {
        ICLPool pool = ICLPool(POOL);
        int24 tickSpacing = pool.tickSpacing();
        int24 tickLower;
        int24 tickUpper;

        if (tokenId == 0) {
            (, int24 currentTick,,,,) = pool.slot0();
            tickLower = _closestLowerTick(
                currentTick - 10 * tickSpacing, tickSpacing
            );
            tickUpper = _closestUpperTick(
                currentTick + 10 * tickSpacing, tickSpacing
            );
        } else {
            (,,,,, tickLower, tickUpper,,,,,) =
                IPositionManager(NFT_MANAGER).positions(tokenId);
        }

        return NftAddLiquidity({
            nft: INonfungiblePositionManager(NFT_MANAGER),
            tokenId: tokenId,
            pool: Pool({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: uint24(tickSpacing)
            }),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            extraData: abi.encode(tickSpacing)
        });
    }
}
