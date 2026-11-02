// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";

contract DSCEnginePausableTest is Test {
    DSCEngine internal engine;
    DecentralizedStableCoin internal dsc;
    ERC20Mock internal weth;

    address internal user = makeAddr("user");
    address internal guardian = makeAddr("guardian");
    uint256 internal constant COLLATERAL = 10 ether;
    uint256 internal constant DEBT = 100 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        HelperConfig config;
        (dsc, engine, config) = deployer.run();
        (,, address wethAddress,,) = config.activeNetworkConfig();
        weth = ERC20Mock(wethAddress);
        weth.mint(user, COLLATERAL);

        vm.prank(engine.owner());
        engine.setGuardian(guardian);
    }

    function testOwnerAndGuardianCanPauseButOnlyOwnerCanUnpause() public {
        vm.prank(guardian);
        engine.pause();
        assertTrue(engine.paused());

        vm.prank(guardian);
        vm.expectRevert("Ownable: caller is not the owner");
        engine.unpause();

        vm.prank(engine.owner());
        engine.unpause();
        assertFalse(engine.paused());
    }

    function testUnauthorizedAccountCannotPause() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotGuardianOrOwner.selector);
        engine.pause();
    }

    function testPauseBlocksMintAndWithdrawalButAllowsDepositAndRepayment() public {
        vm.startPrank(user);
        weth.approve(address(engine), COLLATERAL);
        engine.depositCollateralAndMintDsc(address(weth), COLLATERAL, DEBT);
        dsc.approve(address(engine), DEBT);
        vm.stopPrank();

        vm.prank(guardian);
        engine.pause();

        weth.mint(user, 1 ether);
        vm.startPrank(user);
        weth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(weth), 1 ether);

        vm.expectRevert("Pausable: paused");
        engine.mintDsc(1 ether);
        vm.expectRevert("Pausable: paused");
        engine.redeemCollateral(address(weth), 1 ether);

        engine.burnDsc(DEBT);
        vm.stopPrank();

        (uint256 debt,) = engine.getAccountInformation(user);
        assertEq(debt, 0);
    }

    function testRiskChangeRequiresDelayAndExactCalldata() public {
        address owner = engine.owner();
        vm.prank(owner);
        engine.scheduleRiskParameters(40, 8, 1.1 ether);

        (, uint256 readyAt) = engine.getPendingRiskChange();
        assertEq(readyAt, block.timestamp + engine.RISK_CHANGE_DELAY());

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__RiskChangeNotReady.selector, readyAt));
        engine.executeRiskParameters(40, 8, 1.1 ether);

        vm.warp(readyAt);
        vm.prank(owner);
        vm.expectRevert(DSCEngine.DSCEngine__RiskChangeMismatch.selector);
        engine.executeRiskParameters(41, 8, 1.1 ether);

        vm.prank(owner);
        engine.executeRiskParameters(40, 8, 1.1 ether);
        assertEq(engine.getLiquidationThreshold(), 40);
        assertEq(engine.getLiquidationBonus(), 8);
        assertEq(engine.getMinHealthFactor(), 1.1 ether);
    }

    function testRiskBoundsRejectMassLiquidationConfiguration() public {
        vm.prank(engine.owner());
        vm.expectRevert(DSCEngine.DSCEngine__InvalidParameter.selector);
        engine.scheduleRiskParameters(1, 50, type(uint256).max);
    }

    function testNonOwnerCannotScheduleRiskChange() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        engine.scheduleRiskParameters(40, 8, 1 ether);
    }
}
