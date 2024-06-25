// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";
import {NSCEngine} from "../../src/NSCEngine.sol";
import {NewStableCoin} from "../../src/NewStableCoin.sol";
import {MockV3Aggregator} from "../mocks/MockAggregatorV3.sol";

contract Handler is Test {
    NSCEngine nscEngine;
    NewStableCoin newStableCoin;

    ERC20Mock weth;
    ERC20Mock wbtc;

    MockV3Aggregator public ethUSDPriceFeed;

    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;

    // Keep track of how many time MintNSC function is called
    uint256 public timesMintNSCCalled;
    // Keep track of senders that have deposited, because foundry use multiple sender address to run this function
    address[] public usersWithCollateral;

    constructor(NSCEngine _nscEngine, NewStableCoin _newStableCoin) {
        nscEngine = _nscEngine;
        newStableCoin = _newStableCoin;

        // Get the list of acceptable tokens from nscEngine
        address[] memory collateralTokens = nscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUSDPriceFeed = MockV3Aggregator(nscEngine.getCollateralPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Getting valid collateral token to deposit
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        // Bound the amount collateral
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(msg.sender);

        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(nscEngine), amountCollateral);

        nscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
        // Double push
        usersWithCollateral.push(msg.sender);
        // usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Get a random collateral from the collateral list
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Get the collateral that a user has
        uint256 maxCollateralToRedeem = nscEngine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        // If the amountCollateral is 0
        if (amountCollateral == 0) return;

        nscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintNSC(uint256 amountNSCToMint, uint256 addressSeed) public {
        // If no user deposited then return
        if (usersWithCollateral.length == 0) return;
        address sender = usersWithCollateral[addressSeed % usersWithCollateral.length];
        (uint256 totalNSCMinted, uint256 collateralValueInUSD) = nscEngine.getAccountInformation(sender);
        // Max NSC able to mint is 50%(overcollaterized) - whatever that user already has minted
        // using int because it could be negative
        console.log("Collateral value in USD", collateralValueInUSD);
        int256 availableNSCToMint = (int256(collateralValueInUSD / 2) - int256(totalNSCMinted));
        if (availableNSCToMint < 0) return;
        console.log("Available NSC To Mint", uint256(availableNSCToMint));
        amountNSCToMint = bound(amountNSCToMint, 0, uint256(availableNSCToMint));
        // console.log("Amount of NSC to mint", amountNSCToMint);
        if (amountNSCToMint == 0) return;

        vm.startPrank(sender);
        nscEngine.mintNSC(amountNSCToMint);
        vm.stopPrank();
        timesMintNSCCalled++;
    }

    // This break invariant test suite
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUSDPriceFeed.updateAnswer(newPriceInt);
    //     // (, int256 answer,,,) = ethUSDPriceFeed.latestRoundData();
    //     // console.log("Lastest ETH price", uint256(answer));
    // }

    function liquidate() public {}

    // Helper function
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
