// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { Test } from "forge-std/Test.sol";
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
        assertEq(OracleLib.getTimeout(), expectedTimeout);
    }

    /// @notice Tests that staleCheckLatestRoundData reverts when price data is stale
    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleLib.OracleLib__StalePrice.selector, block.timestamp - 4 hours - 1 seconds, 3 hours
            )
        );
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    /// @notice Tests that a feed cannot report an observation from the future.
    function testPriceRevertsOnFutureTimestamp() public {
        uint80 _roundId = 2;
        int256 _answer = INITAL_PRICE;
        uint256 _timestamp = block.timestamp + 1;
        uint256 _startedAt = block.timestamp;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(abi.encodeWithSelector(OracleLib.OracleLib__StalePrice.selector, block.timestamp + 1, 3 hours));
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    function testPriceRevertsWhenAnswerIsNegative() public {
        aggregator.updateAnswer(-1);
        vm.expectRevert(abi.encodeWithSelector(OracleLib.OracleLib__InvalidPrice.selector, int256(-1)));
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }
}
