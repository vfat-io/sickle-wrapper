// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardRouter} from "./interfaces/IRewardRouter.sol";

/// @title RewardRouter
/// @notice Reference implementation of IRewardRouter.
///         Takes a configurable fee (basis points) on rewards before
///         forwarding the remainder to the user (harvest) or back to
///         the wrapper (compound).
///
///         Intended as a starting point for partners — extend or replace
///         with custom logic (gamified rewards, vesting, etc.).
contract RewardRouter is IRewardRouter {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Errors
    // =========================================================================

    error NotOwner();
    error InvalidFeeBps();

    // =========================================================================
    // Events
    // =========================================================================

    event FeeUpdated(uint256 feeBps);
    event FeeRecipientUpdated(address feeRecipient);
    event RewardsClaimed(
        address indexed user, address indexed wrapper, address[] tokens, uint256[] userAmounts, uint256[] feeAmounts
    );
    event RewardsCompounded(
        address indexed user, address indexed wrapper, address[] tokens, uint256[] wrapperAmounts, uint256[] feeAmounts
    );

    // =========================================================================
    // Constants
    // =========================================================================

    uint256 public constant MAX_FEE_BPS = 5000; // 50% cap
    uint256 private constant BPS = 10_000;

    // =========================================================================
    // State
    // =========================================================================

    address public owner;
    uint256 public feeBps;
    address public feeRecipient;

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @param _owner Admin address (can update fee params)
    /// @param _feeBps Fee in basis points (0–5000)
    /// @param _feeRecipient Address that receives fee portion
    constructor(address _owner, uint256 _feeBps, address _feeRecipient) {
        if (_feeBps > MAX_FEE_BPS) revert InvalidFeeBps();
        owner = _owner;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
    }

    // =========================================================================
    // IRewardRouter
    // =========================================================================

    /// @inheritdoc IRewardRouter
    function onRewardsClaimed(address user, address[] calldata tokens, uint256[] calldata amounts) external override {
        uint256[] memory userAmounts = new uint256[](tokens.length);
        uint256[] memory feeAmounts = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length;) {
            if (amounts[i] > 0) {
                uint256 fee = (amounts[i] * feeBps) / BPS;
                uint256 userAmount = amounts[i] - fee;

                IERC20(tokens[i]).safeTransferFrom(msg.sender, user, userAmount);
                if (fee > 0) {
                    IERC20(tokens[i]).safeTransferFrom(msg.sender, feeRecipient, fee);
                }

                userAmounts[i] = userAmount;
                feeAmounts[i] = fee;
            }
            unchecked {
                ++i;
            }
        }

        emit RewardsClaimed(user, msg.sender, tokens, userAmounts, feeAmounts);
    }

    /// @inheritdoc IRewardRouter
    function onRewardsCompounded(address user, address[] calldata tokens, uint256[] calldata amounts)
        external
        override
    {
        uint256[] memory wrapperAmounts = new uint256[](tokens.length);
        uint256[] memory feeAmounts = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length;) {
            if (amounts[i] > 0) {
                uint256 fee = (amounts[i] * feeBps) / BPS;
                uint256 wrapperAmount = amounts[i] - fee;

                // Send remainder back to wrapper (msg.sender) for re-deposit
                IERC20(tokens[i]).safeTransferFrom(msg.sender, msg.sender, wrapperAmount);
                if (fee > 0) {
                    IERC20(tokens[i]).safeTransferFrom(msg.sender, feeRecipient, fee);
                }

                wrapperAmounts[i] = wrapperAmount;
                feeAmounts[i] = fee;
            }
            unchecked {
                ++i;
            }
        }

        emit RewardsCompounded(user, msg.sender, tokens, wrapperAmounts, feeAmounts);
    }

    // =========================================================================
    // Admin
    // =========================================================================

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert InvalidFeeBps();
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
