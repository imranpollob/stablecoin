// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { InvariantTestBase } from "../helpers/InvariantTestBase.sol";
import { StopOnRevertHandler } from "./StopOnRevertHandler.t.sol";

/// @notice Fixed-price campaign: valid actions preserve accounting and borrower health.
contract StopOnRevertInvariants is InvariantTestBase {
    function setUp() public {
        _deploy();
        handler = new StopOnRevertHandler(engine, dsc);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = StopOnRevertHandler.deposit.selector;
        selectors[1] = StopOnRevertHandler.mint.selector;
        selectors[2] = StopOnRevertHandler.repay.selector;
        selectors[3] = StopOnRevertHandler.redeem.selector;
        selectors[4] = StopOnRevertHandler.transfer.selector;
        _target(selectors);
    }

    function invariant_debtAccounting() public {
        _assertDebtAccounting();
    }

    function invariant_collateralCustody() public {
        _assertCollateralCustody();
    }

    function invariant_positionsRemainHealthyAtFixedPrices() public {
        address[] memory actors = handler.getActors();
        for (uint256 i; i < actors.length; ++i) {
            assertGe(engine.getHealthFactor(actors[i]), engine.getMinHealthFactor());
        }
    }
}
