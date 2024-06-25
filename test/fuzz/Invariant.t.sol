// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StdInvariant, Test, console} from "forge-std/Test.sol";
import {DeployNSC} from "../../script/DeployNSC.s.sol";
import {NSCEngine} from "../../src/NSCEngine.sol";
import {NewStableCoin} from "../../src/NewStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant, Test {
    NewStableCoin newStableCoin;
    NSCEngine nscEngine;
    HelperConfig helperConfig;
    Handler handler;

    address wethUSDPriceFeed;
    address wbtcUSDPriceFeed;
    address weth;
    address wbtc;

    function setUp() public {
        DeployNSC deployer = new DeployNSC();
        (newStableCoin, nscEngine, helperConfig) = deployer.run();
        (wethUSDPriceFeed, wbtcUSDPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(nscEngine, newStableCoin);
        // Calling functions through handler contract
        targetContract(address(handler));
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = newStableCoin.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(nscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(nscEngine));

        uint256 wethValue = nscEngine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = nscEngine.getUSDValue(wbtc, totalWbtcDeposited);

        console.log("=======================");
        console.log("Weth Value", wethValue);
        console.log("Wbtc value", wbtcValue);
        console.log("Total NSC supply", totalSupply);
        console.log("Times MintNSC called", handler.timesMintNSCCalled());
        console.log("=======================");

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {}
}
