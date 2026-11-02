// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

/// @notice Regression for I-01: health-factor math must never round *up*.
/// @dev Rounding up would overstate collateralization and let an under-backed
///      position slip past the mint/redeem check. `Math.mulDiv` floors, so the
///      reported factor is always conservative (it favors the protocol).
contract I01HealthFactorPrecisionTest is ProtocolTestBase {
    function testHealthFactorRoundsDownInFavorOfProtocol() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (, DSCEngine engine) = _deploy(tokens, feeds);

        // 2 wei of collateral at 50% threshold against 3 wei of debt: the exact
        // risk-adjusted ratio is 1/3, so the engine must report the floor
        // 333333333333333333 and never round up to a healthier-looking value.
        uint256 hf = engine.calculateHealthFactor(3, 2);
        assertEq(hf, 333_333_333_333_333_333);
        assertTrue(hf * 3 <= 1 ether);

        // Zero-debt sentinel is untouched by the rounding logic.
        assertEq(engine.calculateHealthFactor(0, 0), type(uint256).max);
    }
}
