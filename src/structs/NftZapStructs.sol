// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SwapParams } from "./SwapStructs.sol";
import {
    NftAddLiquidity,
    NftRemoveLiquidity
} from "./NftLiquidityStructs.sol";

struct NftZapIn {
    SwapParams[] swaps;
    NftAddLiquidity addLiquidityParams;
}

struct NftZapOut {
    NftRemoveLiquidity removeLiquidityParams;
    SwapParams[] swaps;
}
