// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IFarmStrategy } from "./interfaces/IFarmStrategy.sol";
import { INftFarmStrategy } from "./interfaces/INftFarmStrategy.sol";
import { ISickleFactory } from "./interfaces/ISickleFactory.sol";
import { IRewardRouter } from "./interfaces/IRewardRouter.sol";
import { SickleWrapper } from "./SickleWrapper.sol";

/// @title WrapperFactory
/// @notice Deploys one SickleWrapper per user using CREATE2.
///         Deployed by the partner with their RewardRouter.
///         Users interact with their wrapper, which owns the Sickle.
contract WrapperFactory {
    // =========================================================================
    // Events
    // =========================================================================

    event WrapperCreated(address indexed user, address wrapper);

    // =========================================================================
    // Immutables
    // =========================================================================

    IFarmStrategy public immutable farmStrategy;
    INftFarmStrategy public immutable nftFarmStrategy;
    ISickleFactory public immutable sickleFactory;
    IRewardRouter public immutable rewardRouter;

    // =========================================================================
    // Storage
    // =========================================================================

    mapping(address => SickleWrapper) public wrappers;

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        IFarmStrategy _farmStrategy,
        INftFarmStrategy _nftFarmStrategy,
        ISickleFactory _sickleFactory,
        IRewardRouter _rewardRouter
    ) {
        farmStrategy = _farmStrategy;
        nftFarmStrategy = _nftFarmStrategy;
        sickleFactory = _sickleFactory;
        rewardRouter = _rewardRouter;
    }

    // =========================================================================
    // External
    // =========================================================================

    /// @notice Get or create a wrapper for the given user.
    /// Anyone can call this to deploy a wrapper for a user, but only the
    /// user can interact with their wrapper.
    /// @param user The end user address
    /// @return wrapper The user's SickleWrapper
    function getOrCreateWrapper(
        address user
    ) external returns (SickleWrapper wrapper) {
        wrapper = wrappers[user];
        if (address(wrapper) == address(0)) {
            wrapper = new SickleWrapper{
                salt: bytes32(uint256(uint160(user)))
            }(user, farmStrategy, nftFarmStrategy, sickleFactory, rewardRouter);
            wrappers[user] = wrapper;
            emit WrapperCreated(user, address(wrapper));
        }
    }

    /// @notice Predict the wrapper address for a user (before deployment).
    /// @param user The end user address
    /// @return The predicted wrapper address
    function predict(address user) external view returns (address) {
        bytes32 salt = bytes32(uint256(uint160(user)));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                    abi.encodePacked(
                        type(SickleWrapper).creationCode,
                        abi.encode(
                            user,
                            farmStrategy,
                            nftFarmStrategy,
                            sickleFactory,
                            rewardRouter
                        )
                    )
                )
            )
        );
        return address(uint160(uint256(hash)));
    }
}
