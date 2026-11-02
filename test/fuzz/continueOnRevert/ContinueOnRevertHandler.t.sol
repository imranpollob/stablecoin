// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StopOnRevertHandler } from "../failOnRevert/StopOnRevertHandler.t.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../../mocks/MockV3Aggregator.sol";

/// @notice Adversarial requests and price shocks. Expected protocol reverts are allowed.
contract ContinueOnRevertHandler is StopOnRevertHandler {
    constructor(DSCEngine engine_, DecentralizedStableCoin dsc_) StopOnRevertHandler(engine_, dsc_) {
        // Exercise collateral exhaustion and realized bad debt before randomized calls.
        address feed = engine.getCollateralTokenPriceFeed(tokens[0]);
        MockV3Aggregator(feed).updateAnswer(100e8);
        vm.prank(LIQUIDATOR);
        engine.liquidate(tokens[0], actors[0], 1000 ether);
        MockV3Aggregator(feed).updateAnswer(2000e8);
    }

    function mint(uint256 actorSeed, uint256 amount) public override {
        vm.prank(actors[actorSeed % actors.length]);
        engine.mintDsc(bound(amount, 0, 100_000 ether));
    }

    function repay(uint256 actorSeed, uint256 amount) public override {
        vm.prank(actors[actorSeed % actors.length]);
        engine.burnDsc(bound(amount, 0, 100_000 ether));
    }

    function redeem(uint256 actorSeed, uint256 tokenSeed, uint256 amount) public override {
        vm.prank(actors[actorSeed % actors.length]);
        engine.redeemCollateral(tokens[tokenSeed % tokens.length], bound(amount, 0, 100 ether));
    }

    function updatePrice(uint256 tokenSeed, uint256 price) public {
        address feed = engine.getCollateralTokenPriceFeed(tokens[tokenSeed % tokens.length]);
        // Positive, fresh observations; invalid/stale data has separate regressions.
        MockV3Aggregator(feed).updateAnswer(int256(bound(price, 1e8, 4000e8)));
    }

    function liquidate(uint256 userSeed, uint256 tokenSeed, uint256 amount) public {
        address user = actors[userSeed % actors.length];
        (uint256 debt,) = engine.getAccountInformation(user);
        uint256 available = Math.min(debt, dsc.balanceOf(LIQUIDATOR));
        if (available == 0) return;
        vm.prank(LIQUIDATOR);
        engine.liquidate(tokens[tokenSeed % tokens.length], user, bound(amount, 1, available));
    }

    function coverBadDebt(uint256 amount) public {
        uint256 available = Math.min(engine.getBadDebt(), dsc.balanceOf(LIQUIDATOR));
        if (available == 0) return;
        vm.prank(LIQUIDATOR);
        engine.coverBadDebt(bound(amount, 1, available));
    }
}
