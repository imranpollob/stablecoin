// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { InvariantTestBase } from "../helpers/InvariantTestBase.sol";
import { StopOnRevertHandler } from "../failOnRevert/StopOnRevertHandler.t.sol";
import { ContinueOnRevertHandler } from "./ContinueOnRevertHandler.t.sol";

/// @notice Price shocks may cause insolvency; accounting must still reconcile.
/// @dev forge-config: default.invariant.fail-on-revert = false
contract ContinueOnRevertInvariants is InvariantTestBase {
    function setUp() public {
        _deploy();
        handler = new ContinueOnRevertHandler(engine, dsc);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = StopOnRevertHandler.deposit.selector;
        selectors[1] = ContinueOnRevertHandler.mint.selector;
        selectors[2] = ContinueOnRevertHandler.repay.selector;
        selectors[3] = ContinueOnRevertHandler.redeem.selector;
        selectors[4] = StopOnRevertHandler.transfer.selector;
        selectors[5] = ContinueOnRevertHandler.updatePrice.selector;
        selectors[6] = ContinueOnRevertHandler.liquidate.selector;
        selectors[7] = ContinueOnRevertHandler.coverBadDebt.selector;
        _target(selectors);
    }

    function invariant_debtAccounting() public {
        _assertDebtAccounting();
    }

    function invariant_collateralCustody() public {
        _assertCollateralCustody();
    }
}
