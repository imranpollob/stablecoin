// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

/**
 * @title DecentralizedStablecoinTest
 * @notice Unit tests for the DecentralizedStableCoin contract
 * @dev Tests error conditions for minting and burning DSC tokens
 */
contract DecentralizedStablecoinTest is StdCheats, Test {
    DecentralizedStableCoin dsc;

    /// @notice Sets up the test environment by deploying a new DSC instance
    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    /// @notice Tests that minting zero amount reverts
    function testMustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(this), 0);
    }

    /// @notice Tests that burning zero amount reverts
    function testMustBurnMoreThanZero() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(0);
        vm.stopPrank();
    }

    /// @notice Tests that burning more than balance reverts
    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(101);
        vm.stopPrank();
    }

    /// @notice Tests that minting to zero address reverts
    function testCantMintToZeroAddress() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(0), 100);
        vm.stopPrank();
    }
}
