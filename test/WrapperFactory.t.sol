// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import { WrapperFactory } from "../src/WrapperFactory.sol";
import { SickleWrapper } from "../src/SickleWrapper.sol";
import { IFarmStrategy } from "../src/interfaces/IFarmStrategy.sol";
import { INftFarmStrategy } from "../src/interfaces/INftFarmStrategy.sol";
import { IRewardRouter } from "../src/interfaces/IRewardRouter.sol";

import { MockFarmStrategy } from "./mocks/MockFarmStrategy.sol";
import { MockNftFarmStrategy } from "./mocks/MockNftFarmStrategy.sol";
import { MockSickleFactory } from "./mocks/MockSickleFactory.sol";
import { MockRewardRouter } from "./mocks/MockRewardRouter.sol";

contract WrapperFactoryTest is Test {
    event WrapperCreated(address indexed user, address wrapper);

    WrapperFactory factory;

    MockFarmStrategy farmStrategy;
    MockNftFarmStrategy nftFarmStrategy;
    MockSickleFactory sickleFactory;
    MockRewardRouter rewardRouter;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        farmStrategy = new MockFarmStrategy();
        nftFarmStrategy = new MockNftFarmStrategy();
        sickleFactory = new MockSickleFactory();
        rewardRouter = new MockRewardRouter();

        factory = new WrapperFactory(
            IFarmStrategy(address(farmStrategy)),
            INftFarmStrategy(address(nftFarmStrategy)),
            sickleFactory,
            IRewardRouter(address(rewardRouter))
        );
    }

    function test_getOrCreateWrapper() public {
        vm.expectEmit(true, false, false, true);
        emit WrapperCreated(alice, factory.predict(alice));

        SickleWrapper wrapper = factory.getOrCreateWrapper(alice);

        assertNotEq(address(wrapper), address(0));
        assertEq(wrapper.user(), alice);
        assertEq(address(wrapper.farmStrategy()), address(farmStrategy));
        assertEq(address(wrapper.nftFarmStrategy()), address(nftFarmStrategy));
        assertEq(address(wrapper.sickleFactory()), address(sickleFactory));
        assertEq(address(wrapper.rewardRouter()), address(rewardRouter));
        assertEq(address(factory.wrappers(alice)), address(wrapper));
    }

    function test_getOrCreateWrapper_returnExisting() public {
        SickleWrapper first = factory.getOrCreateWrapper(alice);
        SickleWrapper second = factory.getOrCreateWrapper(alice);

        assertEq(address(first), address(second));
    }

    function test_predict_matchesDeployment() public {
        address predicted = factory.predict(alice);
        SickleWrapper wrapper = factory.getOrCreateWrapper(alice);

        assertEq(predicted, address(wrapper));
    }

    function test_differentUsers_differentWrappers() public {
        SickleWrapper wrapperAlice = factory.getOrCreateWrapper(alice);
        SickleWrapper wrapperBob = factory.getOrCreateWrapper(bob);

        assertNotEq(address(wrapperAlice), address(wrapperBob));
        assertEq(wrapperAlice.user(), alice);
        assertEq(wrapperBob.user(), bob);
    }

    function test_predict_differentUsers() public {
        address predictAlice = factory.predict(alice);
        address predictBob = factory.predict(bob);

        assertNotEq(predictAlice, predictBob);
    }

    function test_immutables() public {
        assertEq(address(factory.farmStrategy()), address(farmStrategy));
        assertEq(
            address(factory.nftFarmStrategy()), address(nftFarmStrategy)
        );
        assertEq(address(factory.sickleFactory()), address(sickleFactory));
        assertEq(address(factory.rewardRouter()), address(rewardRouter));
    }
}
