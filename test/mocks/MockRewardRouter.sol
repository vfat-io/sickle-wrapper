// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardRouter} from "../../src/interfaces/IRewardRouter.sol";

/// @dev Mock RewardRouter for testing.
/// - onRewardsClaimed: pulls tokens from msg.sender, sends to user
/// - onRewardsCompounded: pulls tokens from msg.sender, sends back to msg.sender
contract MockRewardRouter is IRewardRouter {
    using SafeERC20 for IERC20;

    // Track calls for assertions
    address public lastUser;
    address[] public lastTokens;
    uint256[] public lastAmounts;
    bool public lastWasCompound;

    function onRewardsClaimed(address user, address[] calldata tokens, uint256[] calldata amounts) external override {
        lastUser = user;
        lastTokens = tokens;
        lastAmounts = amounts;
        lastWasCompound = false;

        for (uint256 i; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, user, amounts[i]);
            }
        }
    }

    function onRewardsCompounded(address user, address[] calldata tokens, uint256[] calldata amounts)
        external
        override
    {
        lastUser = user;
        lastTokens = tokens;
        lastAmounts = amounts;
        lastWasCompound = true;

        // Pull tokens from wrapper, then send them back (simulates processing)
        for (uint256 i; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
                IERC20(tokens[i]).safeTransfer(msg.sender, amounts[i]);
            }
        }
    }
}
