// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ISickleFactory} from "../../src/interfaces/ISickleFactory.sol";

/// @dev Returns a deterministic address for any admin input.
/// In tests we don't need a real Sickle — we just need the address
/// to exist so token approvals point somewhere stable.
contract MockSickleFactory is ISickleFactory {
    mapping(address => address) public sickles;

    function predict(address admin) external view override returns (address) {
        address s = sickles[admin];
        if (s != address(0)) return s;
        // Deterministic fallback so predict is stable before setSickle
        return address(uint160(uint256(keccak256(abi.encode(admin)))));
    }

    function setSickle(address admin, address sickle) external {
        sickles[admin] = sickle;
    }
}
