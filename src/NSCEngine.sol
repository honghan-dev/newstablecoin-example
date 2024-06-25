// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20Burnable, ERC20} from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {INewStableCoin} from "./interfaces/INewStableCoin.sol";
import {AggregatorV3Interface} from "chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title NSCEngie
 * @author Han
 *
 * Token will peg to 1 dollar. 1 token == $1
 * Similar to DAI without governance, fees, and only backed by WETH and WBTC
 *
 * Nsc system should always be "overcollateralized" - invariant
 *
 * @notice This contract is the core of the NSC system. It handles all the logic for mining and redeeming NSC.
 */
contract NSCEngine is ReentrancyGuard {
    /*///////////////////////////////////
                    Error
    ///////////////////////////////////*/
    error NSCEngine__MustBeMoreThanZero();
    error NSCEngine__TokenAddressAndPriceFeedAddressNotSame();
    error NSCEngie__NotAllowedToken();
    error NSCEngine__TransferFailed();
    error NSCEngine__Undercollaterized(uint256 userHealthFactor);
    error NSCEngine__MintFailed();
    error NSCEngine__AboveHealthFactor();
    error NSCEngine__BelowHealthFactor();

    //////////////////////////
    ///// Types ///
    //////////////////////////
    using OracleLib for AggregatorV3Interface;

    //////////////////////////
    ///// States Variables ///
    //////////////////////////
    // For chainlink price feed adjustment
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    // For synchronise decimal
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    // 10% bonus for liquidator
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposit;
    mapping(address user => uint256 amountNSCMinted) private s_NSCMinted;
    address[] private s_collateralTokens;

    INewStableCoin private immutable i_nsc;

    ////////////////////
    ///// Events   /////
    ////////////////////
    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    ////////////////////
    ///// Modifier /////
    ////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert NSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert NSCEngie__NotAllowedToken();
        }
        _;
    }

    ////////////////////
    ///// Functions ////
    ////////////////////
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address nscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert NSCEngine__TokenAddressAndPriceFeedAddressNotSame();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_nsc = INewStableCoin(nscAddress);
    }

    //////////////////////////////
    ///// External Functions /////
    //////////////////////////////

    /**
     *
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountNSCToMint The amount of NSC to mint
     * @notice this function will deposit collateral and mint NSC in one transaction
     */
    function depositCollateralAndMintToken(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountNSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintNSC(amountNSCToMint);
    }

    /**
     * @notice follows CEI
     * This function allows users to deposit collateral
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral amount to collateralize
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // Update collateral added
        s_collateralDeposit[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert NSCEngine__TransferFailed();
        }
    }

    /**
     * This function burn NSC and redeems underlying collateral
     * @param tokenCollateralAddress Allowed token address
     * @param amountCollateral Amount to collaterize
     * @param amountNSCToBurn Amount of NSC token to burn
     */
    function redeemCollateralForNSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountNSCToBurn)
        external
    {
        burnNSC(amountNSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already check healthfactor
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        // Check health factor
        _revertIfUnderCollaterized(msg.sender);
    }

    /**
     * @param amount amount to burn
     */
    function burnNSC(uint256 amount) public moreThanZero(amount) {
        // User reducing their NSC themselves
        _burnNSC(msg.sender, msg.sender, amount);
        _revertIfUnderCollaterized(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountNSCToMint The amount of new stable coin to mint
     * @notice Must have more collateral value than the moinimum threshold
     */
    function mintNSC(uint256 amountNSCToMint) public moreThanZero(amountNSCToMint) {
        s_NSCMinted[msg.sender] += amountNSCToMint;
        // If user mint too many and it becomes undercollaterized
        _revertIfUnderCollaterized(msg.sender);
        bool minted = i_nsc.mint(msg.sender, amountNSCToMint);
        if (!minted) {
            revert NSCEngine__MintFailed();
        }
    }

    /**
     * Allow other user to liquidate position
     * @param collateral ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor
     * @param debtToCover The amount of NSC to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You get liquidation incentive
     * @notice Invariant - protocol must always be overcollaterized
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // Check health factor
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert NSCEngine__AboveHealthFactor();
        }
        // Amount of token that the liquidator able to collect
        uint256 tokenAmountFromDebtCovered = getCollateralAmountFromUSD(collateral, debtToCover);
        // And give them a 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Total collateral liquidator able to receive = token amount received from liquidation + 10% incentive bonus
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        // Liquidator redeem collateral from user
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnNSC(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _getHealthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert NSCEngine__BelowHealthFactor();
        }
        _revertIfUnderCollaterized(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////////////////////////////////
    ///// Private and Internal View Functions /////
    ///////////////////////////////////////////////
    /**
     * @dev low-level internal function, it doesn't check for health factor
     * @param onBehalfOf User who will get their NSC reduced
     * @param NSCFrom NSC token from the user
     * @param amountToBurn Amount of token to burn
     */
    function _burnNSC(address onBehalfOf, address NSCFrom, uint256 amountToBurn) private {
        // Update NSC minted amount
        s_NSCMinted[onBehalfOf] -= amountToBurn;
        // transfer from before burning the token
        bool success = i_nsc.transferFrom(NSCFrom, address(this), amountToBurn);
        if (!success) {
            revert NSCEngine__TransferFailed();
        }
        i_nsc.burn(amountToBurn);
    }

    /**
     * @notice Redeems the specified amount of collateral from the given address and transfers it to another address.
     * @param from The address from which the collateral is redeemed.
     * @param to The address to which the collateral is transferred.
     * @param tokenCollateralAddress The address of the ERC20 token contract representing the collateral.
     * @param amountCollateral The amount of collateral to redeem and transfer.
     */
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposit[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert NSCEngine__TransferFailed();
        }
    }

    /**
     * Returns the health factor of user's position
     * @param user user
     * @return healthFactor Health factor
     */
    function _getHealthFactor(address user) private view returns (uint256 healthFactor) {
        // Total NSC minted
        // Total collateral value
        (uint256 totalNSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        // If user did not mint any NSC, return max value
        if (totalNSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalNSCMinted;
    }

    /**
     * @param user User address
     * @return totalNSCMinted Total NSC minted by User
     * @return collateralValueInUSD Total collateral in USD
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalNSCMinted, uint256 collateralValueInUSD)
    {
        totalNSCMinted = s_NSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return (totalNSCMinted, collateralValueInUSD);
    }

    /**
     * 1. Check health factor
     * 2. Revert if they are undercollaterized / below health factor
     * @param user user
     */
    function _revertIfUnderCollaterized(address user) internal view {
        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert NSCEngine__Undercollaterized(userHealthFactor);
        }
    }

    ///////////////////////////////////////////////
    ///// Public and External View Functions //////
    ///////////////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // Loops through each collateral token
        uint256 collateralTokens = s_collateralTokens.length;
        for (uint256 i = 0; i < collateralTokens; ++i) {
            // Get token address
            address token = s_collateralTokens[i];
            // Get the amount of the token user deposited
            uint256 amount = s_collateralDeposit[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // return value - eg 1000USD eth
        return (uint256((price)) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    /**
     * @notice Converts a specified amount of USD (in wei) to the equivalent amount of a specified token.
     * @param token The address of the token to convert to.
     * @param USDAmountInWei The amount of USD (in wei) to convert.
     * @return The equivalent amount of the specified token.
     */
    function getCollateralAmountFromUSD(address token, uint256 USDAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (USDAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalNSCMinted, uint256 collateralValueInUSD)
    {
        (totalNSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    /**
     * Get the list of acceptable tokens as collaterals
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     *
     */
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposit[user][token];
    }

    function getCollateralPriceFeed(address collateralToken) external view returns (address) {
        return s_priceFeeds[collateralToken];
    }
}
