// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract L03ConstructorValidationTest is ProtocolTestBase {
    function testDuplicateCollateralIsRejected() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(weth);
        feeds[0] = address(feed);
        feeds[1] = address(feed);

        vm.expectRevert();
        new DSCEngine(tokens, feeds, address(dsc));
    }
}
