// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @notice This library is used to check Chainlink oracles for stale data.
 * @dev If a price is stale, functions will revert, which renders the DSCEngine unusable - this is by design.
 *      We want the DSCEngine to freeze if prices become stale.
 */
library OracleLib {
    /// @notice Thrown when attempting to use stale price data
    error OracleLib__StalePrice();

    /// @notice The maximum time allowed between oracle updates before data is considered stale
    uint256 private constant TIMEOUT = 3 hours;

    /// @notice Checks the Chainlink oracle for stale data and returns the latest round data
    /// @param chainlinkFeed The Chainlink price feed to check
    /// @return roundId The round ID from the oracle
    /// @return answer The price from the oracle
    /// @return startedAt The timestamp when the round started
    /// @return updatedAt The timestamp when the round was updated
    /// @return answeredInRound The round ID in which the answer was computed
    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            chainlinkFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @notice Gets the timeout duration for oracle data staleness
    /// @param chainlinkFeed The Chainlink price feed (unused, present for interface consistency)
    /// @return The timeout value in seconds
    function getTimeout(AggregatorV3Interface chainlinkFeed) public pure returns (uint256) {
        return TIMEOUT;
    }
}
