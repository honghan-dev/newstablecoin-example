// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Han
 * @notice This library is used to check the Chainlink Orcale for stale data.
 * NSCEngine to freeze if prices become stale
 */
library OracleLib {
    error Oracle__StalePrce();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondSince = block.timestamp - updatedAt;
        if (secondSince > TIMEOUT) revert Oracle__StalePrce();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
