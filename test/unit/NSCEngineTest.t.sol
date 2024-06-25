// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployNSC} from "../../script/DeployNSC.s.sol";
import {NewStableCoin} from "../../src/NewStableCoin.sol";
import {NSCEngine} from "../../src/NSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";

contract NSCEngineTest is Test {
    DeployNSC deployer;
    NewStableCoin newStableCoin;
    NSCEngine nscEngine;
    HelperConfig helper;
    address ethUSDPriceFeed;
    address btcUSDPriceFeed;
    address weth;
    address wbtc;

    address public user = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployNSC();
        (newStableCoin, nscEngine, helper) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, weth, wbtc,) = helper.activeNetworkConfig();
        ERC20Mock(weth).mint(user, AMOUNT_COLLATERAL);
    }

    //////////////////////////////
    /////// Constructor test /////
    //////////////////////////////
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertsIfTokenLengthNotTheSameAsPriceFeed() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(ethUSDPriceFeed);
        priceFeedAddress.push(btcUSDPriceFeed);

        vm.expectRevert(NSCEngine.NSCEngine__TokenAddressAndPriceFeedAddressNotSame.selector);
        new NSCEngine(tokenAddress, priceFeedAddress, address(newStableCoin));
    }

    //////////////////////////////
    ////// Price Feed test ///////
    //////////////////////////////

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = nscEngine.getUSDValue(address(weth), ethAmount);
        console.log("actualUSD", actualUSD);
        assertEq(expectedUSD, actualUSD);
    }

    function testGetCollateralAmountFromUSD() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWETH = 0.05 ether;
        uint256 actualWETH = nscEngine.getCollateralAmountFromUSD(weth, usdAmount);
        assertEq(expectedWETH, actualWETH);
    }

    ////////////////////////////////////
    ///// Deposit collateral test //////
    ////////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(newStableCoin), AMOUNT_COLLATERAL);

        vm.expectRevert(NSCEngine.NSCEngine__MustBeMoreThanZero.selector);
        nscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock tokenA = new ERC20Mock();
        tokenA.mint(user, 2 ether);
        vm.startPrank(user);
        vm.expectRevert(NSCEngine.NSCEngie__NotAllowedToken.selector);
        nscEngine.depositCollateral(address(tokenA), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(nscEngine), AMOUNT_COLLATERAL);
        nscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateral() public depositedCollateral {
        (uint256 totalNSCMinted, uint256 collateralValueInUSD) = nscEngine.getAccountInformation(user);

        uint256 expectedTotalNSCMinted = 0;
        // Amount of token deposited
        uint256 expectedCollateralAmount = nscEngine.getCollateralAmountFromUSD(weth, collateralValueInUSD);
        // Check total NSC minted
        assertEq(totalNSCMinted, expectedTotalNSCMinted);
        // Check total collateral amount deposited
        assertEq(AMOUNT_COLLATERAL, expectedCollateralAmount);
    }
}
