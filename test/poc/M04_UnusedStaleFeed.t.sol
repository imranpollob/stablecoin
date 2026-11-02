// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract M04UnusedStaleFeedTest is ProtocolTestBase {
    function testUnusedStaleFeedDoesNotFreezeEthOnlyUser() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        DecimalToken wbtc = new DecimalToken("Wrapped Bitcoin", "WBTC", 8);
        MockV3Aggregator ethFeed = new MockV3Aggregator(8, 2000e8);
        MockV3Aggregator btcFeed = new MockV3Aggregator(8, 30_000e8);
        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);
        feeds[0] = address(ethFeed);
        feeds[1] = address(btcFeed);
        (, DSCEngine engine) = _deploy(tokens, feeds);

        weth.mint(user, 1 ether);
        vm.startPrank(user);
        weth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(weth), 1 ether);
        vm.stopPrank();
        vm.warp(block.timestamp + 4 hours);
        ethFeed.updateAnswer(2000e8);

        assertEq(engine.getAccountCollateralValue(user), 2000 ether);
    }
}
