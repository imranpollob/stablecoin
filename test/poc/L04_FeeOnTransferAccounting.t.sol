// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, FeeOnTransferToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract L04FeeOnTransferAccountingTest is ProtocolTestBase {
    function testDepositCreditsOnlyTokensActuallyReceived() public {
        FeeOnTransferToken token = new FeeOnTransferToken();
        MockV3Aggregator feed = new MockV3Aggregator(8, 1e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(token);
        feeds[0] = address(feed);
        (, DSCEngine engine) = _deploy(tokens, feeds);

        token.mint(user, 100 ether);
        vm.startPrank(user);
        token.approve(address(engine), 100 ether);
        engine.depositCollateral(address(token), 100 ether);
        vm.stopPrank();

        assertEq(engine.getCollateralBalanceOfUser(user, address(token)), 90 ether);
        assertEq(token.balanceOf(address(engine)), 90 ether);
    }
}
