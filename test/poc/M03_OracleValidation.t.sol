// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract M03OracleValidationTest is ProtocolTestBase {
    function testZeroPriceIsRejected() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (, DSCEngine engine) = _deploy(tokens, feeds);
        feed.updateAnswer(0);

        vm.expectRevert();
        engine.getUsdValue(address(weth), 1 ether);
    }

    function testNegativePriceIsRejectedInsteadOfWrapping() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (, DSCEngine engine) = _deploy(tokens, feeds);
        // A negative answer cast straight to uint256 would wrap into a huge
        // price and make every position look infinitely collateralized.
        feed.updateAnswer(-100e8);

        vm.expectRevert();
        engine.getUsdValue(address(weth), 1 ether);
    }
}
