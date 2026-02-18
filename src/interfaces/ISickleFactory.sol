// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Minimal interface for the Sickle factory.
/// Only the `predict` function is needed by the wrapper.
interface ISickleFactory {
    function predict(address admin) external view returns (address);
}
