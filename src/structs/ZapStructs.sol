// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SwapParams} from "./SwapStructs.sol";
import {AddLiquidityParams, RemoveLiquidityParams} from "./LiquidityStructs.sol";

struct ZapIn {
    SwapParams[] swaps;
    AddLiquidityParams addLiquidityParams;
}

struct ZapOut {
    RemoveLiquidityParams removeLiquidityParams;
    SwapParams[] swaps;
}
