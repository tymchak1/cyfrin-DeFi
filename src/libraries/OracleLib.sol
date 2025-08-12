// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Anastasia Tymchak
 * @notice Library to check for stale prices from Chainlink oracles
 * It prevents the DSCEngine from operating with outdated price data by reverting
 * if the price data is stale, effectively freezing the DSCEngine
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 public constant TIMEOUT = 3 hours;

    /**
     * @notice Fetches the latest round data from a Chainlink oracle and checks if the data is stale
     * Reverts if the data is stale to prevent using outdated price information
     * @param chainlinkFeed The Chainlink AggregatorV3Interface oracle to query
     * @return roundId The round ID from the oracle
     * @return answer The price answer from the oracle
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was last updated
     * @return answeredInRound The round ID in which the answer was computed
     */
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

    /**
     * @notice Returns the timeout threshold in seconds used to determine if price data is stale
     * @return The timeout duration in seconds
     */
    function getTimeout(AggregatorV3Interface /* chainlinkFeed */ ) public pure returns (uint256) {
        return TIMEOUT;
    }
}
