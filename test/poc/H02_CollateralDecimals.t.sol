// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract H02CollateralDecimalsTest is ProtocolTestBase {
    function testEightDecimalCollateralIsValuedInEighteenDecimalUsd() public {
        DecimalToken wbtc = new DecimalToken("Wrapped Bitcoin", "WBTC", 8);
        MockV3Aggregator feed = new MockV3Aggregator(8, 30_000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(wbtc);
        feeds[0] = address(feed);
        (, DSCEngine engine) = _deploy(tokens, feeds);

        assertEq(engine.getUsdValue(address(wbtc), 1e8), 30_000 ether);
        assertEq(engine.getTokenAmountFromUsd(address(wbtc), 30_000 ether), 1e8);
    }
}
