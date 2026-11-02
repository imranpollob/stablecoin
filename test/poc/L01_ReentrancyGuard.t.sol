// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ProtocolTestBase, DecimalToken } from "./helpers/ProtocolTestBase.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

/// @notice A hook-style token that attempts to re-enter the engine during settlement.
contract CallbackToken is DecimalToken {
    DSCEngine internal s_target;
    bytes internal s_callback;

    constructor() DecimalToken("Callback Token", "CALL", 18) { }

    function arm(DSCEngine target, bytes memory callback) external {
        s_target = target;
        s_callback = callback;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (s_callback.length != 0) {
            bytes memory cb = s_callback;
            s_callback = "";
            (bool ok, bytes memory ret) = address(s_target).call(cb);
            if (!ok) {
                // Bubble up the inner revert reason so the test can pin *which*
                // defense stopped the re-entry: the guard message post-fix,
                // an arithmetic panic on the unguarded code.
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
        return super.transfer(to, amount);
    }
}

/// @notice Regression for L-01: settlement paths carry `nonReentrant`, so a token
///         callback cannot re-enter redeem/burn flows mid-settlement.
/// @dev The expected revert string pins the guard itself: without `nonReentrant`
///      the inner call would fail later with an arithmetic panic instead.
contract L01ReentrancyGuardTest is ProtocolTestBase {
    function _deployWithCallback()
        internal
        returns (DecentralizedStableCoin dsc, DSCEngine engine, CallbackToken token)
    {
        token = new CallbackToken();
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = address(token);
        feeds[0] = address(feed);
        (dsc, engine) = _deploy(tokens, feeds);
        token.mint(user, 10 ether);
        vm.startPrank(user);
        token.approve(address(engine), type(uint256).max);
        engine.depositCollateral(address(token), 10 ether);
        vm.stopPrank();
    }

    function testReentrantRedeemDuringSettlementIsBlockedByGuard() public {
        (, DSCEngine engine, CallbackToken token) = _deployWithCallback();
        token.arm(engine, abi.encodeWithSelector(engine.redeemCollateral.selector, address(token), 1));

        vm.prank(user);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        engine.redeemCollateral(address(token), 1 ether);
    }

    function testReentrantBurnDuringSettlementIsBlockedByGuard() public {
        (, DSCEngine engine, CallbackToken token) = _deployWithCallback();
        token.arm(engine, abi.encodeWithSelector(engine.burnDsc.selector, 1));

        vm.prank(user);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        engine.redeemCollateral(address(token), 1 ether);
    }

    function testReentrantFullExitDuringSettlementIsBlockedByGuard() public {
        (, DSCEngine engine, CallbackToken token) = _deployWithCallback();
        token.arm(engine, abi.encodeWithSelector(engine.redeemCollateralForDsc.selector, address(token), 1 ether, 1));

        vm.prank(user);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        engine.redeemCollateral(address(token), 1 ether);
    }
}
