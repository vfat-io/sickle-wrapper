// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SwapParams} from "../../src/structs/SwapStructs.sol";

/// @dev Struct encoded in SwapParams.extraData when using MockSwapConnector.
struct MockExtraData {
    address tokenOut;
}

/// @notice Mock swap connector for fork tests.
///
/// Mirrors the pattern from sickle-contracts' MockLiquidityConnector:
///   - Inherits from `Test` so it can call `deal()` inside delegatecall context.
///   - Registered in ConnectorRegistry as the connector for a mock router address.
///   - When the Sickle delegatecalls this connector, `address(this)` == Sickle.
///   - Burns tokenIn (sends to router / zero-value sink) and mints tokenOut via deal().
///
/// SwapParams.extraData = abi.encode(MockExtraData({ tokenOut: <addr> }))
contract MockSwapConnector is Test {
    function swapExactTokensForTokens(SwapParams memory swap) external {
        MockExtraData memory extraData = abi.decode(swap.extraData, (MockExtraData));

        // Transfer tokenIn away (to the "router" address as a burn sink)
        IERC20(swap.tokenIn).transfer(swap.router, swap.amountIn);

        // Mint tokenOut to this address (the Sickle, via delegatecall context)
        uint256 balanceBefore = IERC20(extraData.tokenOut).balanceOf(address(this));
        deal(extraData.tokenOut, address(this), swap.minAmountOut + balanceBefore);
    }
}
