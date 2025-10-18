// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**
 * @title ContinueOnRevertHandler
 * @notice Handler contract for fuzz testing with continue-on-revert behavior
 * @dev Provides functions to interact with the protocol during invariant testing with continue-on-revert
 */

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../../mocks/MockV3Aggregator.sol";
import { DSCEngine, AggregatorV3Interface } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { console } from "forge-std/console.sol";

/**
 * @title ContinueOnRevertHandler
 * @notice Handler contract for fuzz testing with continue-on-revert behavior
 * @dev Provides functions to interact with the protocol during invariant testing
 */
contract ContinueOnRevertHandler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    /// @notice Maximum deposit size for fuzz testing
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    /// @notice Constructor to initialize the handler with protocol contracts
    /// @param _dscEngine The DSCEngine contract instance
    /// @param _dsc The DecentralizedStableCoin contract instance
    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    /// @notice Mint and deposit collateral to the protocol
    /// @param collateralSeed Seed value to determine which collateral type to use
    /// @param amountCollateral Amount of collateral to deposit
    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        collateral.mint(msg.sender, amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
    }

    /// @notice Redeem collateral from the protocol
    /// @param collateralSeed Seed value to determine which collateral type to use
    /// @param amountCollateral Amount of collateral to redeem
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    /// @notice Burn DSC tokens
    /// @param amountDsc Amount of DSC to burn
    function burnDsc(uint256 amountDsc) public {
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        dsc.burn(amountDsc);
    }

    /// @notice Mint DSC tokens (direct minting - only for testing purposes)
    /// @param amountDsc Amount of DSC to mint
    function mintDsc(uint256 amountDsc) public {
        amountDsc = bound(amountDsc, 0, MAX_DEPOSIT_SIZE);
        dsc.mint(msg.sender, amountDsc);
    }

    /// @notice Liquidate an undercollateralized user
    /// @param collateralSeed Seed value to determine which collateral type to liquidate
    /// @param userToBeLiquidated Address of the user to be liquidated
    /// @param debtToCover Amount of debt to cover during liquidation
    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        dscEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /// @notice Transfer DSC tokens
    /// @param amountDsc Amount of DSC to transfer
    /// @param to Transfer recipient address
    function transferDsc(uint256 amountDsc, address to) public {
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        vm.prank(msg.sender);
        dsc.transfer(to, amountDsc);
    }

    /// @notice Update the price of collateral tokens (sets price to 0 for testing)
    /// @param newPrice New price value for the collateral (unused in this implementation)
    /// @param collateralSeed Seed value to determine which collateral type to update
    function updateCollateralPrice(uint128 newPrice, uint256 collateralSeed) public {
        int256 intNewPrice = 0;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(collateral)));

        priceFeed.updateAnswer(intNewPrice);
    }

    /// @notice Helper function to select collateral based on seed
    /// @param collateralSeed Seed value to determine which collateral type to return
    /// @return The selected collateral token
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    /// @notice Provides a summary of protocol state for debugging
    function callSummary() external view {
        console.log("Weth total deposited", weth.balanceOf(address(dscEngine)));
        console.log("Wbtc total deposited", wbtc.balanceOf(address(dscEngine)));
        console.log("Total supply of DSC", dsc.totalSupply());
    }
}
