// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { SickleWrapper } from "../../src/SickleWrapper.sol";
import { INonfungiblePositionManager } from
    "../../src/interfaces/external/INonfungiblePositionManager.sol";
import {
    NftPosition,
    SimpleNftHarvest
} from "../../src/structs/NftFarmStrategyStructs.sol";
import { NftSettings } from "../../src/structs/NftSettingsStructs.sol";
import { Farm } from "../../src/structs/FarmStrategyStructs.sol";

import {
    ForkTestBase,
    Base,
    ICLPool,
    ICLGauge,
    ISlipstreamNFTManager
} from "./ForkTestBase.sol";

/// @title AerodromeNFT Fork Tests
/// @notice Full lifecycle tests for CL (NFT) positions through the wrapper.
///         Uses the deployed Sickle infrastructure on Base with Aerodrome Slipstream.
///
/// Flow: User mints CL NFT → simpleDepositNft → simpleHarvestNft → simpleWithdrawNft
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
        int24 tickLower = _closestLowerTick(currentTick - 10 * tickSpacing, tickSpacing);
        int24 tickUpper = _closestUpperTick(currentTick + 10 * tickSpacing, tickSpacing);

        // Deal tokens to this contract for minting
        uint256 amount0 = 1e18;  // WETH
        uint256 amount1 = 1000e18;  // AERO
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

    // =====================================================================
    // simpleDepositNft → simpleHarvestNft → simpleWithdrawNft
    // =====================================================================

    function test_nft_full_lifecycle() public {
        // Mint CL NFT to user
        uint256 tokenId = _mintCLPosition(user);
        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId), user);

        // --- Deposit NFT ---
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

        // NFT should have moved from user → wrapper → Sickle → gauge
        // User no longer owns it
        assertNotEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            user,
            "user should not own NFT after deposit"
        );
        assertNotEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            address(wrapper),
            "wrapper should not hold NFT after deposit"
        );

        // Verify gauge has the NFT staked for the wrapper's Sickle
        ICLGauge gauge = ICLGauge(GAUGE);
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        uint256 stakedLen = gauge.stakedLength(sickle);
        assertGt(stakedLen, 0, "sickle should have staked NFTs in gauge");

        // --- Warp time to accrue rewards ---
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // Check earned rewards
        uint256 earned = gauge.earned(sickle, tokenId);
        assertGt(earned, 0, "should have earned AERO rewards");

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
            feeRewards, totalRewards * FEE_BPS / 10_000, 0.01e18, "fee ~5%"
        );

        // --- Withdraw NFT ---
        vm.prank(user);
        wrapper.simpleWithdrawNft(
            _nftPosition(tokenId),
            ""
        );

        assertEq(
            IERC721(NFT_MANAGER).ownerOf(tokenId),
            user,
            "user should own NFT after withdraw"
        );
    }

    // =====================================================================
    // simpleExitNft (harvest + withdraw in one call)
    // =====================================================================

    function test_nft_simple_exit() public {
        uint256 tokenId = _mintCLPosition(user);

        // Deposit
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

        // Warp for rewards
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50_000);

        // Exit = harvest (routed) + withdraw (direct)
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
    // Multiple deposits (second NFT from same user)
    // =====================================================================

    function test_nft_two_positions() public {
        uint256 tokenId1 = _mintCLPosition(user);
        uint256 tokenId2 = _mintCLPosition(user);

        // Deposit both
        vm.startPrank(user);

        IERC721(NFT_MANAGER).approve(address(wrapper), tokenId1);
        wrapper.simpleDepositNft(
            _nftPosition(tokenId1),
            "",
            _emptyNftSettings(),
            address(0),
            bytes32(0)
        );

        IERC721(NFT_MANAGER).approve(address(wrapper), tokenId2);
        wrapper.simpleDepositNft(
            _nftPosition(tokenId2),
            "",
            _emptyNftSettings(),
            address(0),
            bytes32(0)
        );

        vm.stopPrank();

        // Both should be staked
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        ICLGauge gauge = ICLGauge(GAUGE);
        assertEq(gauge.stakedLength(sickle), 2, "sickle should have 2 staked NFTs");

        // Withdraw both
        vm.startPrank(user);
        wrapper.simpleWithdrawNft(_nftPosition(tokenId1), "");
        wrapper.simpleWithdrawNft(_nftPosition(tokenId2), "");
        vm.stopPrank();

        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId1), user, "user owns NFT 1");
        assertEq(IERC721(NFT_MANAGER).ownerOf(tokenId2), user, "user owns NFT 2");
    }
}
