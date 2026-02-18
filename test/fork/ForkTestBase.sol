// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { SickleWrapper } from "../../src/SickleWrapper.sol";
import { WrapperFactory } from "../../src/WrapperFactory.sol";
import { RewardRouter } from "../../src/RewardRouter.sol";
import { IFarmStrategy } from "../../src/interfaces/IFarmStrategy.sol";
import { INftFarmStrategy } from "../../src/interfaces/INftFarmStrategy.sol";
import { ISickleFactory } from "../../src/interfaces/ISickleFactory.sol";
import { IRewardRouter } from "../../src/interfaces/IRewardRouter.sol";
import { INonfungiblePositionManager } from
    "../../src/interfaces/external/INonfungiblePositionManager.sol";
import { MockSwapConnector } from "./MockSwapConnector.sol";

// =========================================================================
// Base Mainnet Addresses
// =========================================================================

library Base {
    // Tokens
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // Aerodrome VAMM (ERC20 farms)
    address constant VAMM_WETH_USDC =
        0xcDAC0d6c6C59727a65F871236188350531885C43;
    address constant VAMM_WETH_USDC_GAUGE =
        0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025;

    // Aerodrome Slipstream / CL (NFT farms)
    address constant CL200_WETH_AERO =
        0x82321f3BEB69f503380D6B233857d5C43562e2D0;
    address constant CL200_WETH_AERO_GAUGE =
        0xdE8FF0D3e8ab225110B088a250b546015C567E27;
    address constant SLIPSTREAM_NFT_MANAGER =
        0x827922686190790b37229fd06084350E74485b72;

    // Aerodrome routers
    address constant AERODROME_ROUTER =
        0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    // Deployed Sickle contracts on Base
    address constant SICKLE_FACTORY =
        0x71D234A3e1dfC161cc1d081E6496e76627baAc31;
    address constant FARM_STRATEGY =
        0xbF325BC7921256f842B3BC99C8eF4E2f72999556;
    address constant NFT_FARM_STRATEGY =
        0x9699bE38E6D54E51a4b36645726FEE9CC736EB45;
    address constant SICKLE_REGISTRY =
        0x2Ef5EAFA8711E2441Bd519EED5d09F8DFEf2Ecf3;
    address constant CONNECTOR_REGISTRY =
        0x53E205dcEb0a2e95c88C6a0e80280d6003221FAF;
}

// =========================================================================
// Minimal Aerodrome interfaces
// =========================================================================

interface ICLGauge {
    function stakedByIndex(
        address depositor,
        uint256 index
    ) external view returns (uint256);

    function stakedLength(
        address depositor
    ) external view returns (uint256);

    function earned(
        address account,
        uint256 tokenId
    ) external view returns (uint256);
}

interface ICLPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );
}

interface ISlipstreamNFTManager {
    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

interface IVAMMPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves()
        external
        view
        returns (
            uint256 reserve0,
            uint256 reserve1,
            uint256 blockTimestampLast
        );
    function totalSupply() external view returns (uint256);
}

interface IVAMMGauge {
    function balanceOf(address account) external view returns (uint256);
}

interface IPositionManager {
    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            int24 tickSpacing,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        );
}

interface ISickleRegistry {
    function admin() external view returns (address);
    function setWhitelistedCallers(
        address[] calldata callers,
        bool whitelisted
    ) external;
    function setWhitelistedTargets(
        address[] calldata targets,
        bool whitelisted
    ) external;
}

interface IConnectorRegistry {
    function admin() external view returns (address);
    function setConnectors(
        address[] calldata targets,
        address[] calldata connectors
    ) external;
    function connectorOf(
        address target
    ) external view returns (address);
}

// =========================================================================
// Fork Test Base Contract
// =========================================================================

abstract contract ForkTestBase is Test {
    uint256 constant FORK_BLOCK = 36_354_297;

    WrapperFactory factory;
    RewardRouter rewardRouter;

    IFarmStrategy farmStrategy;
    INftFarmStrategy nftFarmStrategy;
    ISickleFactory sickleFactory;

    /// @dev Mock router address used as the "swap router" in SwapParams.
    ///      The MockSwapConnector is registered as the connector for this address.
    address mockRouter = makeAddr("mockRouter");

    address user = makeAddr("user");
    address feeRecipient = makeAddr("feeRecipient");

    uint256 constant FEE_BPS = 500; // 5%

    function _setUpFork() internal {
        vm.createSelectFork(vm.envString("BASE_RPC"), FORK_BLOCK);

        farmStrategy = IFarmStrategy(Base.FARM_STRATEGY);
        nftFarmStrategy = INftFarmStrategy(Base.NFT_FARM_STRATEGY);
        sickleFactory = ISickleFactory(Base.SICKLE_FACTORY);

        // Deploy our contracts on the fork
        rewardRouter = new RewardRouter(address(this), FEE_BPS, feeRecipient);

        factory = new WrapperFactory(
            farmStrategy,
            nftFarmStrategy,
            sickleFactory,
            IRewardRouter(address(rewardRouter))
        );

        // Deploy MockSwapConnector and register it in the deployed Sickle
        // infrastructure so we can test compound/rebalance/move with mock swaps.
        _deployMockSwapConnector();

        vm.label(Base.WETH, "WETH");
        vm.label(Base.USDC, "USDC");
        vm.label(Base.AERO, "AERO");
        vm.label(Base.FARM_STRATEGY, "FarmStrategy");
        vm.label(Base.NFT_FARM_STRATEGY, "NftFarmStrategy");
        vm.label(Base.SICKLE_FACTORY, "SickleFactory");
    }

    /// @dev Deploy a MockSwapConnector and register it in the deployed
    ///      ConnectorRegistry + SickleRegistry so the Sickle can delegatecall it.
    function _deployMockSwapConnector() internal {
        MockSwapConnector connector = new MockSwapConnector();
        vm.label(address(connector), "MockSwapConnector");

        // 1. Whitelist the connector as a delegatecall target in SickleRegistry
        ISickleRegistry registry = ISickleRegistry(Base.SICKLE_REGISTRY);
        address registryAdmin = registry.admin();

        vm.startPrank(registryAdmin);
        address[] memory targets = new address[](1);
        targets[0] = address(connector);
        registry.setWhitelistedTargets(targets, true);
        vm.stopPrank();

        // 2. Register the connector for mockRouter in ConnectorRegistry
        IConnectorRegistry connectorRegistry =
            IConnectorRegistry(Base.CONNECTOR_REGISTRY);
        address connectorAdmin = connectorRegistry.admin();

        vm.startPrank(connectorAdmin);
        address[] memory routers = new address[](1);
        routers[0] = mockRouter;
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        connectorRegistry.setConnectors(routers, connectors);
        vm.stopPrank();
    }

    function _createWrapper() internal returns (SickleWrapper wrapper) {
        wrapper = factory.getOrCreateWrapper(user);
        vm.label(address(wrapper), "SickleWrapper");

        // Allow cheatcodes (deal) on the Sickle address so MockSwapConnector
        // can mint tokens when delegatecalled by the Sickle.
        address sickle = wrapper.sickleFactory().predict(address(wrapper));
        vm.allowCheatcodes(sickle);
    }

    /// @dev Round tick down to nearest tickSpacing
    function _closestLowerTick(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        if (tick < 0 && tick % tickSpacing != 0) {
            return (tick / tickSpacing - 1) * tickSpacing;
        }
        return (tick / tickSpacing) * tickSpacing;
    }

    /// @dev Round tick up to nearest tickSpacing
    function _closestUpperTick(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        if (tick > 0 && tick % tickSpacing != 0) {
            return (tick / tickSpacing + 1) * tickSpacing;
        }
        return (tick / tickSpacing) * tickSpacing;
    }
}
