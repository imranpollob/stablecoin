// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

/// @notice Regression for M-02: risk parameters cannot change instantly or beyond safe bounds.
/// @dev Previously `setLiquidationThreshold`/`setLiquidationBonus` took effect immediately
///      with no bounds, enabling a single-transaction mass-liquidation rug.
contract M02RiskTimelockTest is ProtocolTestBase {
    function _deploySingle() internal returns (DecentralizedStableCoin dsc, DSCEngine engine, DecimalToken weth) {
        weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (dsc, engine) = _deploy(tokens, feeds);
    }

    function testRiskChangeRequiresFortyEightHourDelay() public {
        (, DSCEngine engine,) = _deploySingle();
        engine.scheduleRiskParameters(60, 10, 1 ether);

        vm.expectRevert();
        engine.executeRiskParameters(60, 10, 1 ether);

        vm.warp(block.timestamp + 48 hours);
        engine.executeRiskParameters(60, 10, 1 ether);
        assertEq(engine.getLiquidationThreshold(), 60);
    }

    function testUnsafeRiskParametersAreRejected() public {
        (, DSCEngine engine,) = _deploySingle();

        // Threshold 0 bricks every health factor; 100 makes everything liquidatable.
        vm.expectRevert();
        engine.scheduleRiskParameters(0, 10, 1 ether);
        vm.expectRevert();
        engine.scheduleRiskParameters(100, 10, 1 ether);

        // Bonus that makes liquidation unprofitable at the margin.
        vm.expectRevert();
        engine.scheduleRiskParameters(50, 100, 1 ether);

        // Coupled threshold/bonus that reverts at the liquidation margin.
        vm.expectRevert();
        engine.scheduleRiskParameters(80, 25, 1 ether);
    }

    function testCancelledRiskChangeCannotExecute() public {
        (, DSCEngine engine,) = _deploySingle();
        engine.scheduleRiskParameters(60, 10, 1 ether);
        engine.cancelRiskParameters();

        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert();
        engine.executeRiskParameters(60, 10, 1 ether);
    }
}
