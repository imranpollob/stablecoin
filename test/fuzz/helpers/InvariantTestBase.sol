// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { DeployDSC } from "../../../script/DeployDSC.s.sol";
import { StopOnRevertHandler } from "../failOnRevert/StopOnRevertHandler.t.sol";

abstract contract InvariantTestBase is StdInvariant, Test {
    DSCEngine internal engine;
    DecentralizedStableCoin internal dsc;
    StopOnRevertHandler internal handler;

    function _deploy() internal {
        (dsc, engine,) = new DeployDSC().run();
    }

    /// @dev Keep getters and inherited test utilities out of the campaign.
    function _target(bytes4[] memory selectors) internal {
        targetContract(address(handler));
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        assertGt(dsc.totalSupply(), 0, "campaign must start with live debt");
    }

    function _assertDebtAccounting() internal {
        address[] memory actors = handler.getActors();
        uint256 activeDebt;
        for (uint256 i; i < actors.length; ++i) {
            (uint256 debt,) = engine.getAccountInformation(actors[i]);
            activeDebt += debt;
        }
        assertEq(activeDebt, engine.getTotalActiveDebt(), "actor debt != active debt");
        assertEq(activeDebt + engine.getBadDebt(), dsc.totalSupply(), "accounted debt != supply");
    }

    function _assertCollateralCustody() internal {
        address[] memory tokens = engine.getCollateralTokens();
        address[] memory actors = handler.getActors();
        for (uint256 t; t < tokens.length; ++t) {
            uint256 deposits;
            for (uint256 a; a < actors.length; ++a) {
                deposits += engine.getCollateralBalanceOfUser(actors[a], tokens[t]);
            }
            assertEq(deposits, ERC20Mock(tokens[t]).balanceOf(address(engine)), "deposit ledger != custody");
        }
    }
}
