// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEnginePausableTest is StdCheats, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (
            ethUsdPriceFeed,
            btcUsdPriceFeed,
            weth,
            wbtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(user, 10 ether);
        }
        ERC20Mock(weth).mint(user, 10 ether);
        ERC20Mock(wbtc).mint(user, 10 ether);
    }

    ///////////////////
    // Pausable Tests
    ///////////////////

    function testOwnerCanPause() public {
        vm.prank(dsce.owner());
        dsce.pause();
        assertTrue(dsce.paused());
    }

    function testOwnerCanUnpause() public {
        vm.startPrank(dsce.owner());
        dsce.pause();
        dsce.unpause();
        vm.stopPrank();
        assertFalse(dsce.paused());
    }

    function testNonOwnerCannotPause() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dsce.pause();
    }

    function testCannotDepositWhenPaused() public {
        vm.prank(dsce.owner());
        dsce.pause();

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert("Pausable: paused");
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testCannotMintWhenPaused() public {
        // 1. Unpause (default is unpaused), deposit collateral
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();

        // 2. Pause
        vm.prank(dsce.owner());
        dsce.pause();

        // 3. Try to mint
        vm.startPrank(user);
        vm.expectRevert("Pausable: paused");
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    ///////////////////
    // Dynamic Parameter Tests
    ///////////////////

    function testOwnerCanUpdateLiquidationThreshold() public {
        uint256 newThreshold = 60;
        vm.prank(dsce.owner());
        dsce.setLiquidationThreshold(newThreshold);
        assertEq(dsce.getLiquidationThreshold(), newThreshold);
    }

    function testOwnerCanUpdateLiquidationBonus() public {
        uint256 newBonus = 20;
        vm.prank(dsce.owner());
        dsce.setLiquidationBonus(newBonus);
        assertEq(dsce.getLiquidationBonus(), newBonus);
    }

    function testOwnerCanUpdateMinHealthFactor() public {
        uint256 newHealthFactor = 0.5 ether;
        vm.prank(dsce.owner());
        dsce.setMinHealthFactor(newHealthFactor);
        assertEq(dsce.getMinHealthFactor(), newHealthFactor);
    }

    function testNonOwnerCannotUpdateParameters() public {
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dsce.setLiquidationThreshold(60);
        vm.stopPrank();
    }

    function testInvalidLiquidationThresholdReverts() public {
        vm.startPrank(dsce.owner());
        vm.expectRevert(DSCEngine.DSCEngine__InvalidParameter.selector);
        dsce.setLiquidationThreshold(100);
        vm.stopPrank();
    }

    function testUpdateUseNewParametersForHealthFactor() public {
        // 1. User deposits collateral and mints DSC near the limit
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // Mint max possible roughly
        // Collateral = $20,000 (10 ETH * 2000)
        // Threshold = 50% => $10,000 capacity
        // Mint $10,000
        uint256 maxMint = 10000 ether;
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, maxMint);

        uint256 hfBefore = dsce.getHealthFactor(user);
        // Should be exactly 1e18
        assertEq(hfBefore, 1e18);
        vm.stopPrank();

        // 2. Owner lowers threshold to 40% (meaning you need 2.5x collateral, or only 40% of collateral counts)
        // Previous: $20,000 * 0.50 = $10,000 adjusted value. Debt $10,000. HF = 1.0.
        // New: $20,000 * 0.40 = $8,000 adjusted value. Debt $10,000. HF = 0.8. (Debt > Adjusted Collateral)
        // HF Formula: (AdjCollateral * 1e18) / Debt
        // (8,000 * 1e18) / 10,000 = 0.8e18
        vm.prank(dsce.owner());
        dsce.setLiquidationThreshold(40);

        // 3. User should now be liquidatable (broken health factor)
        uint256 hfAfter = dsce.getHealthFactor(user);
        assertEq(hfAfter, 0.8 ether);
    }
}
