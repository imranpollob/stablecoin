// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";

/// @notice Valid user actions at fixed prices. Every targeted call must succeed.
contract StopOnRevertHandler is Test {
    DSCEngine public immutable engine;
    DecentralizedStableCoin public immutable dsc;
    address public constant LIQUIDATOR = address(0x2000);
    address[] internal actors;
    address[] internal tokens;

    constructor(DSCEngine engine_, DecentralizedStableCoin dsc_) {
        engine = engine_;
        dsc = dsc_;
        tokens = engine_.getCollateralTokens();
        for (uint256 i; i < 4; ++i) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            // Start with live debt so assertions cannot pass on an empty system.
            ERC20Mock(tokens[0]).mint(actor, 10 ether);
            vm.startPrank(actor);
            ERC20Mock(tokens[0]).approve(address(engine), type(uint256).max);
            ERC20Mock(tokens[1]).approve(address(engine), type(uint256).max);
            dsc.approve(address(engine), type(uint256).max);
            engine.depositCollateralAndMintDsc(tokens[0], 10 ether, 1000 ether);
            dsc.transfer(LIQUIDATOR, 250 ether);
            vm.stopPrank();
        }
        vm.prank(LIQUIDATOR);
        dsc.approve(address(engine), type(uint256).max);
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function deposit(uint256 actorSeed, uint256 tokenSeed, uint256 amount) public {
        address actor = actors[actorSeed % actors.length];
        ERC20Mock token = ERC20Mock(tokens[tokenSeed % tokens.length]);
        amount = bound(amount, 1, 100 ether);
        token.mint(actor, amount);
        vm.prank(actor);
        engine.depositCollateral(address(token), amount);
    }

    function mint(uint256 actorSeed, uint256 amount) public virtual {
        address actor = actors[actorSeed % actors.length];
        (uint256 debt, uint256 value) = engine.getAccountInformation(actor);
        uint256 limit = value / 2; // Default threshold (50%) and minHF (1e18).
        if (limit <= debt) return;
        amount = bound(amount, 1, limit - debt);
        vm.prank(actor);
        engine.mintDsc(amount);
    }

    function repay(uint256 actorSeed, uint256 amount) public virtual {
        address actor = actors[actorSeed % actors.length];
        (uint256 debt,) = engine.getAccountInformation(actor);
        uint256 available = Math.min(debt, dsc.balanceOf(actor));
        if (available == 0) return;
        amount = bound(amount, 1, available);
        vm.prank(actor);
        engine.burnDsc(amount);
    }

    function redeem(uint256 actorSeed, uint256 tokenSeed, uint256 amount) public virtual {
        address actor = actors[actorSeed % actors.length];
        address token = tokens[tokenSeed % tokens.length];
        (uint256 debt, uint256 value) = engine.getAccountInformation(actor);
        uint256 balance = engine.getCollateralBalanceOfUser(actor, token);
        if (balance == 0 || value <= debt * 2) return;
        // Leave a $1 rounding buffer when debt is outstanding.
        uint256 spare = value - debt * 2;
        if (debt != 0) {
            if (spare <= 1 ether) return;
            spare -= 1 ether;
        }
        uint256 available = Math.min(balance, engine.getTokenAmountFromUsd(token, spare));
        if (available == 0) return;
        amount = bound(amount, 1, available);
        vm.prank(actor);
        engine.redeemCollateral(token, amount);
    }

    function transfer(uint256 actorSeed, uint256 recipientSeed, uint256 amount) public {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0, dsc.balanceOf(actor));
        vm.prank(actor);
        assertTrue(dsc.transfer(actors[recipientSeed % actors.length], amount));
    }
}
