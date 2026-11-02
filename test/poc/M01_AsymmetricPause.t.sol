// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract M01AsymmetricPauseTest is ProtocolTestBase {
    function testPauseStillAllowsRiskReducingDepositAndRepayment() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (DecentralizedStableCoin dsc, DSCEngine engine) = _deploy(tokens, feeds);
        _depositAndMint(engine, weth, dsc, user, 1 ether, 100 ether);

        engine.pause();
        weth.mint(user, 1 ether);
        vm.startPrank(user);
        weth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(weth), 1 ether);
        dsc.approve(address(engine), 100 ether);
        engine.burnDsc(100 ether);
        vm.stopPrank();

        (uint256 debt,) = engine.getAccountInformation(user);
        assertEq(debt, 0);
    }
}
