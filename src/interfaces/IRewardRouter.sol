// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title IRewardRouter
/// @notice Interface for the external reward routing contract.
/// When a SickleWrapper claims rewards on behalf of a user, it approves
/// the RewardRouter to pull the reward tokens and calls the appropriate method.
///
/// Two modes:
///   - `onRewardsClaimed`: Rewards are sent to the end user after processing.
///   - `onRewardsCompounded`: Rewards are sent back to the wrapper (msg.sender)
///     so that they can be re-deposited into the position.
interface IRewardRouter {
    /// @notice Called by SickleWrapper after claiming rewards (harvest flow).
    /// Reward tokens are approved for transfer by the wrapper before this call.
    /// The router should pull tokens via transferFrom, process them, and send
    /// the result to the user.
    /// @param user The end user who owns the position
    /// @param tokens The reward token addresses
    /// @param amounts The reward token amounts available in the wrapper
    function onRewardsClaimed(
        address user,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;

    /// @notice Called by SickleWrapper when compounding rewards.
    /// Same as `onRewardsClaimed` but the processed tokens must be sent back
    /// to msg.sender (the wrapper) so they can be re-deposited into the
    /// position.
    /// @param user The end user who owns the position
    /// @param tokens The reward token addresses
    /// @param amounts The reward token amounts available in the wrapper
    function onRewardsCompounded(
        address user,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;
}
