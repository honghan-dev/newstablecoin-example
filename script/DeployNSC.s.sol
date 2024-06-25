// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NewStableCoin} from "../src/NewStableCoin.sol";
import {NSCEngine} from "../src/NSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployNSC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function run() external returns (NewStableCoin, NSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUSDPriceFeed, wbtcUSDPriceFeed];

        vm.startBroadcast(deployerKey);

        NewStableCoin newStableCoin = new NewStableCoin();
        NSCEngine nscEngine = new NSCEngine(tokenAddress, priceFeedAddress, address(newStableCoin));

        // Only the engine contract is in control of new stable coin
        newStableCoin.transferOwnership(address(nscEngine));

        vm.stopBroadcast();

        return (newStableCoin, nscEngine, helperConfig);
    }
}
