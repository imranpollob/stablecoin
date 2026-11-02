// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

/// @notice Regression for the inherited burnFrom path bypassing engine debt accounting.
contract L06DirectBurnTest is ProtocolTestBase {
    DecentralizedStableCoin internal dsc;
    DSCEngine internal engine;

    function setUp() public {
        DecimalToken token = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(token);
        feeds[0] = address(feed);
        (dsc, engine) = _deploy(tokens, feeds);
        _depositAndMint(engine, token, dsc, user, 10 ether, 1000 ether);
    }

    function testHolderCannotBurnOutsideEngineAccounting() public {
        vm.startPrank(user);
        dsc.approve(user, 1 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.burnFrom(user, 1 ether);
        vm.stopPrank();
        assertEq(engine.getTotalAccountedDebt(), dsc.totalSupply());
    }

    function testApprovedSpenderCannotBurnOutsideEngineAccounting() public {
        vm.prank(user);
        dsc.approve(liquidator, 1 ether);
        vm.prank(liquidator);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.burnFrom(user, 1 ether);
        assertEq(dsc.balanceOf(user), 1000 ether);
    }

    function testRepaymentStillBurnsSupplyAndReducesDebt() public {
        vm.startPrank(user);
        dsc.approve(address(engine), 1 ether);
        engine.burnDsc(1 ether);
        vm.stopPrank();
        assertEq(dsc.totalSupply(), 999 ether);
        assertEq(engine.getTotalActiveDebt(), 999 ether);
    }
}
