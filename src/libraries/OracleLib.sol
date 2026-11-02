// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title OracleLib
/// @notice Validation helpers for Chainlink-style price feeds.
library OracleLib {
    error OracleLib__InvalidHeartbeat();
    error OracleLib__InvalidPrice(int256 answer);
    error OracleLib__StalePrice(uint256 updatedAt, uint256 heartbeat);

    uint256 internal constant DEFAULT_HEARTBEAT = 3 hours;

    /// @notice Reads a round and rejects incomplete, non-positive, future, or stale observations.
    function staleCheckLatestRoundData(
        AggregatorV3Interface chainlinkFeed,
        uint256 heartbeat
    )
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (heartbeat == 0) revert OracleLib__InvalidHeartbeat();

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            chainlinkFeed.latestRoundData();

        if (answer <= 0) revert OracleLib__InvalidPrice(answer);
        if (updatedAt == 0 || updatedAt > block.timestamp || answeredInRound < roundId) {
            revert OracleLib__StalePrice(updatedAt, heartbeat);
        }
        if (block.timestamp - updatedAt > heartbeat) {
            revert OracleLib__StalePrice(updatedAt, heartbeat);
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @dev Backwards-compatible overload used by legacy tests and simple integrations.
    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return staleCheckLatestRoundData(chainlinkFeed, DEFAULT_HEARTBEAT);
    }

    function getTimeout() public pure returns (uint256) {
        return DEFAULT_HEARTBEAT;
    }
}
