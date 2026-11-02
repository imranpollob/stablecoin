// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../../mocks/MockV3Aggregator.sol";

contract DecimalToken is ERC20 {
    uint8 private immutable i_decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        i_decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeOnTransferToken is DecimalToken {
    uint256 internal constant FEE_BPS = 1000;

    constructor() DecimalToken("Fee Token", "FEE", 18) { }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = amount * FEE_BPS / 10_000;
        _burn(from, fee);
        super._transfer(from, to, amount - fee);
    }
}

abstract contract ProtocolTestBase is Test {
    address internal user = makeAddr("user");
    address internal liquidator = makeAddr("liquidator");

    function _deploy(address[] memory tokens, address[] memory feeds)
        internal
        returns (DecentralizedStableCoin dsc, DSCEngine engine)
    {
        dsc = new DecentralizedStableCoin();
        engine = new DSCEngine(tokens, feeds, address(dsc));
        dsc.transferOwnership(address(engine));

        // Current code uses Ownable2Step. The vulnerable snapshot used one-step Ownable and does
        // not expose this selector, so a low-level call keeps the same PoC source compatible.
        (bool accepted,) = address(engine).call(abi.encodeWithSignature("acceptDscOwnership()"));
        accepted;
    }

    function _depositAndMint(
        DSCEngine engine,
        DecimalToken collateral,
        DecentralizedStableCoin dsc,
        address actor,
        uint256 collateralAmount,
        uint256 debtAmount
    )
        internal
    {
        collateral.mint(actor, collateralAmount);
        vm.startPrank(actor);
        collateral.approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDsc(address(collateral), collateralAmount, debtAmount);
        vm.stopPrank();
        assertEq(dsc.balanceOf(actor), debtAmount);
    }
}
