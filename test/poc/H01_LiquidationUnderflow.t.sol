// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

/// @notice Regression for a position whose collateral cannot fund debt plus the liquidation bonus.
contract H01LiquidationUnderflowTest is ProtocolTestBase {
    function testDeepUnderwaterPositionCanBeSettledAndResidualDebtRecorded() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (DecentralizedStableCoin dsc, DSCEngine engine) = _deploy(tokens, feeds);

        _depositAndMint(engine, weth, dsc, user, 10 ether, 10_000 ether);
        vm.prank(user);
        dsc.transfer(liquidator, 10_000 ether);
        feed.updateAnswer(1050e8);

        vm.startPrank(liquidator);
        dsc.approve(address(engine), type(uint256).max);
        engine.liquidate(address(weth), user, 10_000 ether);
        vm.stopPrank();

        assertEq(engine.getCollateralBalanceOfUser(user, address(weth)), 0);
        (uint256 activeDebt,) = engine.getAccountInformation(user);
        assertEq(activeDebt, 0);
        assertGt(engine.getBadDebt(), 0);
        assertEq(engine.getTotalAccountedDebt(), dsc.totalSupply());
    }
}
