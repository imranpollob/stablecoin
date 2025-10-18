// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**
 * @title StopOnRevertInvariants
 * @notice Invariant tests with stop-on-revert behavior
 * @dev Tests protocol invariants that must hold during fuzz testing
 */

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../../script/DeployDSC.s.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { StopOnRevertHandler } from "./StopOnRevertHandler.t.sol";
import { console } from "forge-std/console.sol";

/**
 * @notice Invariants tested:
 * - protocol must never be insolvent / undercollateralized
 * - TODO: users can't create stablecoins with a bad health factor
 * - TODO: a user should only be able to be liquidated if they have a bad health factor
 */
contract StopOnRevertInvariants is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    /// @notice Liquidator address for testing liquidations
    address public liquidator = makeAddr("liquidator");
    /// @notice Amount of collateral to cover during liquidation tests
    uint256 public collateralToCover = 20 ether;

    StopOnRevertHandler public handler;

    /// @notice Sets up the test environment by deploying contracts and initializing the handler
    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new StopOnRevertHandler(dsce, dsc);
        targetContract(address(handler));
        // targetContract(address(ethUsdPriceFeed)); Why can't we just do this?
    }

    /// @notice Invariant: Protocol must always have collateral value greater than or equal to total DSC supply (solvency)
    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    /// @notice Invariant: Getter functions should not revert under any circumstances
    function invariant_gettersCantRevert() public view {
        dsce.getAdditionalFeedPrecision();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getDsc();
        // dsce.getTokenAmountFromUsd();
        // dsce.getCollateralTokenPriceFeed();
        // dsce.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}
