// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @dev Minimal interface — used as a type in structs.
/// Extends IERC721 so the wrapper can call safeTransferFrom / approve.
interface INonfungiblePositionManager is IERC721 {}
