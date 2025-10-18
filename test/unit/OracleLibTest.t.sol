// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { OracleLib, AggregatorV3Interface } from "../../src/libraries/OracleLib.sol";

/**
 * @title OracleLibTest
 * @notice Unit tests for the OracleLib library
 * @dev Tests oracle staleness checks and timeout functionality
 */
contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITAL_PRICE = 2000 ether;

    /// @notice Sets up the test environment by deploying a mock aggregator
    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITAL_PRICE);
    }

    /// @notice Tests that the timeout value is returned correctly
    function testGetTimeout() public {
        uint256 expectedTimeout = 3 hours;
        assertEq(OracleLib.getTimeout(AggregatorV3Interface(address(aggregator))), expectedTimeout);
    }

    /// @notice Tests that staleCheckLatestRoundData reverts when price data is stale
    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    /// @notice Tests that staleCheckLatestRoundData reverts when answeredInRound is invalid
    function testPriceRevertsOnBadAnsweredInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }
}
