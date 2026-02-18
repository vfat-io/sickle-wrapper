// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IFarmStrategy} from "./interfaces/IFarmStrategy.sol";
import {INftFarmStrategy} from "./interfaces/INftFarmStrategy.sol";
import {ISickleFactory} from "./interfaces/ISickleFactory.sol";
import {IRewardRouter} from "./interfaces/IRewardRouter.sol";
import {
    Farm,
    DepositParams,
    HarvestParams,
    WithdrawParams,
    SimpleDepositParams,
    SimpleHarvestParams,
    SimpleWithdrawParams
} from "./structs/FarmStrategyStructs.sol";
import {
    NftPosition,
    NftDeposit,
    NftIncrease,
    NftWithdraw,
    NftHarvest,
    NftRebalance,
    NftMove,
    SimpleNftHarvest
} from "./structs/NftFarmStrategyStructs.sol";
import {PositionSettings} from "./structs/PositionSettingsStructs.sol";
import {NftSettings} from "./structs/NftSettingsStructs.sol";

/// @title SickleWrapper
/// @notice Per-user wrapper that owns a Sickle on behalf of a user.
///         - Deposits and withdrawals pass through directly to the user.
///         - Reward claims are routed through an external RewardRouter.
///         - The user can always withdraw their principal (LP tokens / NFTs).
///         - No admin functions, no upgradability, immutable user address.
///
/// @dev Architecture:
///      The wrapper is the Sickle's `owner`. Since FarmStrategy and
///      NftFarmStrategy resolve the Sickle via `getSickle(msg.sender)`,
///      only the wrapper can trigger strategy calls. This prevents the
///      end user from bypassing the reward routing.
///
///      Token flow for harvest:
///        Gauge → Sickle → Wrapper (as owner) → RewardRouter → User
///
///      Token flow for compound:
///        Gauge → Sickle → Wrapper → RewardRouter → Wrapper → Sickle → Gauge
///
///      Token flow for withdraw:
///        Gauge → Sickle → Wrapper (as owner) → User (direct)
contract SickleWrapper is IERC721Receiver {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Errors
    // =========================================================================

    error NotUser();
    error ETHTransferFailed();

    // =========================================================================
    // Immutables
    // =========================================================================

    /// @notice The end user (set at deployment, never changes)
    address public immutable user;

    /// @notice Existing FarmStrategy contract (ERC20 positions)
    IFarmStrategy public immutable farmStrategy;

    /// @notice Existing NftFarmStrategy contract (NFT / CL positions)
    INftFarmStrategy public immutable nftFarmStrategy;

    /// @notice SickleFactory for predicting the Sickle address
    ISickleFactory public immutable sickleFactory;

    /// @notice External contract that processes rewards before forwarding
    IRewardRouter public immutable rewardRouter;

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyUser() {
        if (msg.sender != user) revert NotUser();
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        address _user,
        IFarmStrategy _farmStrategy,
        INftFarmStrategy _nftFarmStrategy,
        ISickleFactory _sickleFactory,
        IRewardRouter _rewardRouter
    ) {
        user = _user;
        farmStrategy = _farmStrategy;
        nftFarmStrategy = _nftFarmStrategy;
        sickleFactory = _sickleFactory;
        rewardRouter = _rewardRouter;
    }

    /// @notice Accept ETH (Sickle unwraps WETH before sending to owner)
    receive() external payable {}

    /// @notice Accept ERC721 NFTs
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // =========================================================================
    // ERC20 Farm Strategy — Deposits (tokens → user via sweep)
    // =========================================================================

    /// @notice First deposit into an ERC20 farm. Creates the Sickle if needed.
    function deposit(
        DepositParams calldata params,
        PositionSettings calldata positionSettings,
        address[] calldata sweepTokens,
        address approved,
        bytes32 referralCode
    ) external payable onlyUser {
        _pullTokens(params.tokensIn, params.amountsIn);
        _approveSickle(params.tokensIn, params.amountsIn);

        farmStrategy.deposit{value: msg.value}(params, positionSettings, sweepTokens, approved, referralCode);

        _sweepToUser(sweepTokens);
    }

    /// @notice Add to an existing ERC20 farm position.
    function increase(DepositParams calldata params, address[] calldata sweepTokens) external payable onlyUser {
        _pullTokens(params.tokensIn, params.amountsIn);
        _approveSickle(params.tokensIn, params.amountsIn);

        farmStrategy.increase{value: msg.value}(params, sweepTokens);

        _sweepToUser(sweepTokens);
    }

    /// @notice Simple first deposit (single LP token, no zap).
    function simpleDeposit(
        SimpleDepositParams calldata params,
        PositionSettings calldata positionSettings,
        address approved,
        bytes32 referralCode
    ) external payable onlyUser {
        _pullToken(params.lpToken, params.amountIn);
        _approveTokenForSickle(params.lpToken, params.amountIn);

        farmStrategy.simpleDeposit{value: msg.value}(params, positionSettings, approved, referralCode);
    }

    /// @notice Simple increase (single LP token, no zap).
    function simpleIncrease(SimpleDepositParams calldata params) external onlyUser {
        _pullToken(params.lpToken, params.amountIn);
        _approveTokenForSickle(params.lpToken, params.amountIn);

        farmStrategy.simpleIncrease(params);
    }

    // =========================================================================
    // ERC20 Farm Strategy — Harvest (rewards → RewardRouter → user)
    // =========================================================================

    /// @notice Claim rewards with optional swap. Routed through RewardRouter.
    function harvest(Farm calldata farm, HarvestParams calldata params, address[] calldata sweepTokens)
        external
        onlyUser
    {
        farmStrategy.harvest(farm, params, sweepTokens);

        _routeRewards(sweepTokens, false);
    }

    /// @notice Simple claim (no swap). Routed through RewardRouter.
    function simpleHarvest(Farm calldata farm, SimpleHarvestParams calldata params) external onlyUser {
        farmStrategy.simpleHarvest(farm, params);

        _routeRewards(params.rewardTokens, false);
    }

    // =========================================================================
    // ERC20 Farm Strategy — Compound (harvest routed + re-deposit)
    // =========================================================================

    /// @notice Compound = harvest (routed via RewardRouter) + increase.
    /// The RewardRouter.onRewardsCompounded must send processed tokens back
    /// to the wrapper (msg.sender) so they can be re-deposited.
    /// @param farm The farm to harvest from
    /// @param harvestParams Harvest parameters (claim + optional swap)
    /// @param harvestSweepTokens Tokens to sweep after harvest
    /// @param depositParams Deposit parameters for the re-invest
    /// @param depositSweepTokens Tokens to sweep after deposit (dust → user)
    function compound(
        Farm calldata farm,
        HarvestParams calldata harvestParams,
        address[] calldata harvestSweepTokens,
        DepositParams calldata depositParams,
        address[] calldata depositSweepTokens
    ) external onlyUser {
        // 1. Harvest — rewards come to wrapper
        farmStrategy.harvest(farm, harvestParams, harvestSweepTokens);

        // 2. Route through RewardRouter (compound mode — tokens come back)
        _routeRewards(harvestSweepTokens, true);

        // 3. Approve Sickle for the tokens the router returned
        _approveSickle(depositParams.tokensIn, depositParams.amountsIn);

        // 4. Re-deposit into the position
        farmStrategy.increase(depositParams, depositSweepTokens);
        _sweepToUser(depositSweepTokens);
    }

    // =========================================================================
    // ERC20 Farm Strategy — Withdraw (LP → user directly)
    // =========================================================================

    /// @notice Withdraw with zap. LP/tokens sent directly to user.
    function withdraw(Farm calldata farm, WithdrawParams calldata params, address[] calldata sweepTokens)
        external
        onlyUser
    {
        farmStrategy.withdraw(farm, params, sweepTokens);

        _sweepToUser(sweepTokens);
    }

    /// @notice Simple withdraw (single LP token). Sent directly to user.
    function simpleWithdraw(Farm calldata farm, SimpleWithdrawParams calldata params) external onlyUser {
        farmStrategy.simpleWithdraw(farm, params);

        _sweepTokenToUser(params.lpToken);
    }

    // =========================================================================
    // ERC20 Farm Strategy — Exit (harvest routed + withdraw direct)
    // =========================================================================

    /// @notice Exit = harvest (routed) + withdraw (direct).
    /// Executed as two separate strategy calls to avoid token mixing.
    function exit(
        Farm calldata farm,
        HarvestParams calldata harvestParams,
        address[] calldata harvestSweepTokens,
        WithdrawParams calldata withdrawParams,
        address[] calldata withdrawSweepTokens
    ) external onlyUser {
        // 1. Harvest — rewards routed through RewardRouter
        farmStrategy.harvest(farm, harvestParams, harvestSweepTokens);
        _routeRewards(harvestSweepTokens, false);

        // 2. Withdraw — LP sent directly to user
        farmStrategy.withdraw(farm, withdrawParams, withdrawSweepTokens);
        _sweepToUser(withdrawSweepTokens);
    }

    /// @notice Simple exit = simpleHarvest (routed) + simpleWithdraw (direct).
    function simpleExit(
        Farm calldata farm,
        SimpleHarvestParams calldata harvestParams,
        SimpleWithdrawParams calldata withdrawParams
    ) external onlyUser {
        farmStrategy.simpleHarvest(farm, harvestParams);
        _routeRewards(harvestParams.rewardTokens, false);

        farmStrategy.simpleWithdraw(farm, withdrawParams);
        _sweepTokenToUser(withdrawParams.lpToken);
    }

    // =========================================================================
    // NFT Farm Strategy — Deposits (tokens/NFT → Sickle → gauge)
    // =========================================================================

    /// @notice Deposit into an NFT farm via zap (mints new NFT position).
    function depositNft(
        NftDeposit calldata params,
        NftSettings calldata settings,
        address[] calldata sweepTokens,
        address approved,
        bytes32 referralCode
    ) external payable onlyUser {
        _pullTokens(params.increase.tokensIn, params.increase.amountsIn);
        _approveSickle(params.increase.tokensIn, params.increase.amountsIn);

        nftFarmStrategy.deposit{value: msg.value}(params, settings, sweepTokens, approved, referralCode);

        _sweepToUser(sweepTokens);
    }

    /// @notice Deposit an existing NFT into a farm (user already has the NFT).
    function simpleDepositNft(
        NftPosition calldata position,
        bytes calldata extraData,
        NftSettings calldata settings,
        address approved,
        bytes32 referralCode
    ) external onlyUser {
        // Pull NFT from user → wrapper
        IERC721(address(position.nft)).safeTransferFrom(user, address(this), position.tokenId);

        // Approve Sickle to pull NFT from wrapper
        IERC721(address(position.nft)).approve(_sickleAddress(), position.tokenId);

        nftFarmStrategy.simpleDeposit(position, extraData, settings, approved, referralCode);
    }

    // =========================================================================
    // NFT Farm Strategy — Harvest (rewards → RewardRouter → user)
    // =========================================================================

    /// @notice Claim NFT position rewards with optional swap. Routed.
    function harvestNft(NftPosition calldata position, NftHarvest calldata params) external onlyUser {
        nftFarmStrategy.harvest(position, params);

        _routeRewards(params.sweepTokens, false);
    }

    /// @notice Simple NFT claim (no swap). Routed through RewardRouter.
    function simpleHarvestNft(NftPosition calldata position, SimpleNftHarvest calldata params) external onlyUser {
        nftFarmStrategy.simpleHarvest(position, params);

        _routeRewards(params.rewardTokens, false);
    }

    // =========================================================================
    // NFT Farm Strategy — Compound (harvest routed + re-deposit in place)
    // =========================================================================

    /// @notice NFT compound = harvest (routed) + increase in-place.
    /// RewardRouter.onRewardsCompounded must return tokens to the wrapper.
    /// @param position The NFT position to compound
    /// @param harvestParams Harvest parameters (claim + optional swap)
    /// @param increaseParams Increase parameters (zap config for re-invest).
    ///        increaseParams.zap.addLiquidityParams.tokenId must be set.
    /// @param sweepTokens Tokens to sweep after the increase (dust → user)
    function compoundNft(
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftIncrease calldata increaseParams,
        address[] calldata sweepTokens
    ) external payable onlyUser {
        // 1. Harvest — rewards come to wrapper
        nftFarmStrategy.harvest(position, harvestParams);
        _routeRewards(harvestParams.sweepTokens, true);

        // 2. Approve Sickle for the tokens the router returned
        _approveSickle(increaseParams.tokensIn, increaseParams.amountsIn);

        // 3. Increase position in-place
        nftFarmStrategy.increase{value: msg.value}(position, harvestParams, increaseParams, true, sweepTokens);

        _sweepToUser(sweepTokens);
    }

    // =========================================================================
    // NFT Farm Strategy — Increase / Decrease
    // =========================================================================

    /// @notice Increase an NFT position. If !inPlace, harvests first (routed).
    function increaseNft(
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftIncrease calldata increaseParams,
        bool inPlace,
        address[] calldata sweepTokens
    ) external payable onlyUser {
        _pullTokens(increaseParams.tokensIn, increaseParams.amountsIn);
        _approveSickle(increaseParams.tokensIn, increaseParams.amountsIn);

        nftFarmStrategy.increase{value: msg.value}(position, harvestParams, increaseParams, inPlace, sweepTokens);

        // Route harvest rewards if harvest happened
        if (!inPlace && harvestParams.sweepTokens.length > 0) {
            _routeRewards(harvestParams.sweepTokens, false);
        }

        _sweepToUser(sweepTokens);
    }

    /// @notice Decrease an NFT position. If !inPlace, harvests first (routed).
    function decreaseNft(
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftWithdraw calldata withdrawParams,
        bool inPlace,
        address[] calldata sweepTokens
    ) external onlyUser {
        nftFarmStrategy.decrease(position, harvestParams, withdrawParams, inPlace, sweepTokens);

        // Route harvest rewards if harvest happened
        if (!inPlace && harvestParams.sweepTokens.length > 0) {
            _routeRewards(harvestParams.sweepTokens, false);
        }

        _sweepToUser(sweepTokens);
    }

    // =========================================================================
    // NFT Farm Strategy — Withdraw (NFT/tokens → user directly)
    // =========================================================================

    /// @notice Withdraw from NFT farm with zap. Tokens sent to user.
    function withdrawNft(NftPosition calldata position, NftWithdraw calldata params, address[] calldata sweepTokens)
        external
        onlyUser
    {
        nftFarmStrategy.withdraw(position, params, sweepTokens);

        _sweepToUser(sweepTokens);
    }

    /// @notice Simple withdraw (unstake NFT and send to user).
    function simpleWithdrawNft(NftPosition calldata position, bytes calldata extraData) external onlyUser {
        nftFarmStrategy.simpleWithdraw(position, extraData);

        // NFT is now in wrapper (transferred from Sickle to owner)
        IERC721(address(position.nft)).safeTransferFrom(address(this), user, position.tokenId);
    }

    // =========================================================================
    // NFT Farm Strategy — Exit (harvest routed + withdraw direct)
    // =========================================================================

    /// @notice NFT exit = harvest (routed) + withdraw (direct).
    function exitNft(
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftWithdraw calldata withdrawParams,
        address[] calldata sweepTokens
    ) external onlyUser {
        // 1. Harvest — rewards routed
        nftFarmStrategy.harvest(position, harvestParams);
        _routeRewards(harvestParams.sweepTokens, false);

        // 2. Withdraw — tokens sent to user
        nftFarmStrategy.withdraw(position, withdrawParams, sweepTokens);
        _sweepToUser(sweepTokens);
    }

    /// @notice Simple NFT exit = simpleHarvest (routed) + simpleWithdraw (direct).
    function simpleExitNft(
        NftPosition calldata position,
        SimpleNftHarvest calldata harvestParams,
        bytes calldata withdrawExtraData
    ) external onlyUser {
        nftFarmStrategy.simpleHarvest(position, harvestParams);
        _routeRewards(harvestParams.rewardTokens, false);

        nftFarmStrategy.simpleWithdraw(position, withdrawExtraData);
        IERC721(address(position.nft)).safeTransferFrom(address(this), user, position.tokenId);
    }

    // =========================================================================
    // NFT Farm Strategy — Rebalance / Move
    // =========================================================================

    /// @notice Rebalance an NFT position (harvest + withdraw + re-zap + deposit).
    /// Harvest rewards are routed through the RewardRouter.
    function rebalanceNft(NftRebalance calldata params, address[] calldata sweepTokens) external onlyUser {
        nftFarmStrategy.rebalance(params, sweepTokens);

        // Route the harvest rewards that landed in the wrapper
        _routeRewards(params.harvest.sweepTokens, false);

        _sweepToUser(sweepTokens);
    }

    /// @notice Move an NFT from one farm to another (harvest + withdraw + deposit).
    /// Harvest rewards are routed through the RewardRouter.
    function moveNft(NftMove calldata params, NftSettings calldata settings, address[] calldata sweepTokens)
        external
        onlyUser
    {
        nftFarmStrategy.move(params, settings, sweepTokens);

        // Route the harvest rewards that landed in the wrapper
        _routeRewards(params.harvest.sweepTokens, false);

        _sweepToUser(sweepTokens);
    }

    // =========================================================================
    // Rescue — recover tokens accidentally sent to the wrapper
    // =========================================================================

    /// @notice Recover ERC20 tokens stuck in the wrapper.
    function rescueToken(address token) external onlyUser {
        _sweepTokenToUser(token);
    }

    /// @notice Recover ETH stuck in the wrapper.
    function rescueETH() external onlyUser {
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool ok,) = user.call{value: bal}("");
            if (!ok) revert ETHTransferFailed();
        }
    }

    /// @notice Recover an ERC721 NFT stuck in the wrapper.
    function rescueNft(address nft, uint256 tokenId) external onlyUser {
        IERC721(nft).safeTransferFrom(address(this), user, tokenId);
    }

    // =========================================================================
    // Internal — Token Transfers
    // =========================================================================

    /// @dev Pull ERC20 tokens from user into wrapper.
    function _pullTokens(address[] calldata tokens, uint256[] calldata amounts) private {
        for (uint256 i; i < tokens.length;) {
            _pullToken(tokens[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _pullToken(address token, uint256 amount) private {
        if (_isETH(token) || amount == 0) return;
        IERC20(token).safeTransferFrom(user, address(this), amount);
    }

    // =========================================================================
    // Internal — Sickle Approvals
    // =========================================================================

    /// @dev Approve the Sickle to pull tokens from wrapper.
    /// TransferLib.transferTokenFromUser does safeTransferFrom(owner, sickle, amount)
    /// where owner = this wrapper. The Sickle address is deterministic.
    function _approveSickle(address[] calldata tokens, uint256[] calldata amounts) private {
        address sickle = _sickleAddress();
        for (uint256 i; i < tokens.length;) {
            _approveFor(tokens[i], sickle, amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _approveTokenForSickle(address token, uint256 amount) private {
        _approveFor(token, _sickleAddress(), amount);
    }

    function _approveFor(address token, address spender, uint256 amount) private {
        if (_isETH(token) || amount == 0) return;
        IERC20 t = IERC20(token);
        uint256 allowance = t.allowance(address(this), spender);
        if (allowance > 0) t.safeApprove(spender, 0);
        t.safeApprove(spender, amount);
    }

    // =========================================================================
    // Internal — Sweep to User (for deposits / withdrawals)
    // =========================================================================

    /// @dev Forward ERC20 tokens / ETH from wrapper to user.
    function _sweepToUser(address[] calldata tokens) private {
        for (uint256 i; i < tokens.length;) {
            _sweepTokenToUser(tokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _sweepTokenToUser(address token) private {
        if (_isETH(token)) {
            uint256 bal = address(this).balance;
            if (bal > 0) {
                (bool ok,) = user.call{value: bal}("");
                if (!ok) revert ETHTransferFailed();
            }
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal > 0) IERC20(token).safeTransfer(user, bal);
        }
    }

    // =========================================================================
    // Internal — Route Rewards
    // =========================================================================

    /// @dev Forward reward tokens to the RewardRouter.
    /// Approves the router for each token, then calls the appropriate method.
    /// @param tokens The reward tokens to route
    /// @param compound If true, calls onRewardsCompounded (tokens return to
    ///        wrapper for re-deposit). If false, calls onRewardsClaimed
    ///        (tokens go to user).
    function _routeRewards(address[] calldata tokens, bool compound) private {
        uint256[] memory amounts = new uint256[](tokens.length);
        bool hasRewards = false;

        for (uint256 i; i < tokens.length;) {
            if (!_isETH(tokens[i])) {
                amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
                if (amounts[i] > 0) {
                    _approveFor(tokens[i], address(rewardRouter), amounts[i]);
                    hasRewards = true;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (hasRewards) {
            if (compound) {
                rewardRouter.onRewardsCompounded(user, tokens, amounts);
            } else {
                rewardRouter.onRewardsClaimed(user, tokens, amounts);
            }
        }
    }

    // =========================================================================
    // Internal — Helpers
    // =========================================================================

    /// @dev Predict or retrieve the Sickle address for this wrapper.
    /// The Sickle is created with owner = wrapper address.
    function _sickleAddress() private view returns (address) {
        return sickleFactory.predict(address(this));
    }

    function _isETH(address token) private pure returns (bool) {
        return token == address(0) || token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }
}
