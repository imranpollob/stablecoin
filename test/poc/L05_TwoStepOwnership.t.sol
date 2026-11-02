// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

/// @notice Regression for L-05: ownership moves in two steps, so a typo'd new
///         owner cannot brick or steal the protocol in a single transaction.
contract L05TwoStepOwnershipTest is ProtocolTestBase {
    function testOwnershipTransferRequiresAcceptance() public {
        DecimalToken weth = new DecimalToken("Wrapped Ether", "WETH", 18);
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(weth);
        feeds[0] = address(feed);
        (DecentralizedStableCoin dsc, DSCEngine engine) = _deploy(tokens, feeds);

        address newOwner = makeAddr("newOwner");
        engine.transferOwnership(newOwner);

        // A single-step transfer would already have moved power; here it is pending.
        assertEq(engine.owner(), address(this));
        assertEq(engine.pendingOwner(), newOwner);

        // The pending owner cannot act until acceptance, and acceptance by anyone
        // else changes nothing.
        vm.prank(user);
        vm.expectRevert();
        engine.acceptOwnership();

        vm.prank(newOwner);
        engine.acceptOwnership();
        assertEq(engine.owner(), newOwner);

        // The DSC token behind the engine follows the same two-step discipline.
        assertEq(dsc.owner(), address(engine));
    }
}
