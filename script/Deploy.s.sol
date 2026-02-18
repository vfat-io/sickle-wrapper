// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { WrapperFactory } from "../src/WrapperFactory.sol";
import { RewardRouter } from "../src/RewardRouter.sol";
import { IFarmStrategy } from "../src/interfaces/IFarmStrategy.sol";
import { INftFarmStrategy } from "../src/interfaces/INftFarmStrategy.sol";
import { ISickleFactory } from "../src/interfaces/ISickleFactory.sol";
import { IRewardRouter } from "../src/interfaces/IRewardRouter.sol";

/// @notice Deployment script for the sickle-wrapper system.
///
/// Required environment variables:
///   FARM_STRATEGY       — Deployed FarmStrategy address
///   NFT_FARM_STRATEGY   — Deployed NftFarmStrategy address
///   SICKLE_FACTORY      — Deployed SickleFactory address
///   FEE_BPS             — Fee in basis points (e.g. 500 = 5%)
///   FEE_RECIPIENT       — Address to receive fees
///
/// Usage:
///   forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
contract DeployScript is Script {
    function run() external {
        address farmStrategy = vm.envAddress("FARM_STRATEGY");
        address nftFarmStrategy = vm.envAddress("NFT_FARM_STRATEGY");
        address sickleFactory = vm.envAddress("SICKLE_FACTORY");
        uint256 feeBps = vm.envUint("FEE_BPS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        vm.startBroadcast();

        RewardRouter router =
            new RewardRouter(msg.sender, feeBps, feeRecipient);

        WrapperFactory factory = new WrapperFactory(
            IFarmStrategy(farmStrategy),
            INftFarmStrategy(nftFarmStrategy),
            ISickleFactory(sickleFactory),
            IRewardRouter(address(router))
        );

        vm.stopBroadcast();

        console.log("RewardRouter:", address(router));
        console.log("WrapperFactory:", address(factory));
    }
}
