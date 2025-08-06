// version
// Layout of Contract:
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title DSCEngine
 * @author Anastasia Tymchak
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain 1 toke == $1 peg.
 * This sstablecoin has the properties:
 * - Exogenous collateral
 * - Dollar Pegged
 * - Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only pegged by WETH
 * and WBTC.
 *
 * Our system should always be "overcollateralized". At no point the value of all
 * collateral <= the $ backed value of all DSC.
 *
 * @notice This contract is the core of DSC system. It handles all the logic for minting
 * and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on MakerDAO DSS (DAI) system.
 */
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {Errors} from "./Errors.sol";

contract DSCEngine is ReentrancyGuard, Errors {
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine_TokenIsNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 collateralAmount)) private s_collateralDeposited;
    mapping(address user => uint256 dscAmount) private s_amountDscMinted;
    address[] private s_collateralTokens;

    DecentralizedStablecoin public immutable i_dsc;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollaterallDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        uint256 indexed amountCollateral,
        address tokenCollateralAddress
    );

    event DscMinted(address indexed user, uint256 indexed amountDscMinted);

    event DscBurned(address indexed user, uint256 indexed amountDscBurned);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStablecoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            External FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @param tokenCollateralAddress The address of the collateral token (e.g., WETH, WBTC)
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function allows a user to deposit collateral and mint DSC in one transaction
     */
    function depositCollateralAndMint(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the collateral token (e.g., WETH, WBTC)
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        // checks
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollaterallDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }
    /**
     * @param tokenCollateralAddress The address of the collateral token (e.g., WETH, WBTC)
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn Amount of DSC to burn
     * @notice This function burns DSC and redeems underlying collateral in one transaction
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // already checks health factor before redeeming collateral
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _revertIfHealthFactorBrokenToRedeem(msg.sender, amountCollateral);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    /**
     * @notice Follows CEI
     * @param amountDcsToMint The amount of DSC to mint
     * @notice User must more collateral value than the threhold
     */
    function mintDsc(uint256 amountDcsToMint) public {
        s_amountDscMinted[msg.sender] += amountDcsToMint;
        _revertIfHealthFactorBrokenToMint(msg.sender, amountDcsToMint);
        bool success = i_dsc.mint(msg.sender, amountDcsToMint);
        if (!success) {
            revert DSCEngine_MintFailed();
        }
        emit DscMinted(msg.sender, amountDcsToMint);
    }

    /**
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC and updates the user's minted DSC amount
     */
    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        i_dsc.burn(amountDscToBurn);
        emit DscBurned(msg.sender, amountDscToBurn);
    }

    /**
     * @notice This function allows a user to liquidate a position by covering the debt of another user
     *
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _calculateHealthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine_UserHealthFactorIsNotBroken();
        }

        // burn dsc debt and take their collateral
        uint256 tokenAmountFromDebt = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebt * LIQUIDATION_BONUS) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebt + bonusCollateral;

        // redeem
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);
        // burn
        _burnDsc(debtToCover, user, msg.sender);
        // check health factor after liquidation
        uint256 endingHealthFactor = _calculateHealthFactor(user);
        if (endingHealthFactor >= startingHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        _revertIfHealthFactorBroken(user);
    }

    /*//////////////////////////////////////////////////////////////
                        Private & Internal View FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_amountDscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_amountDscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral, tokenCollateralAddress);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function _revertIfHealthFactorBrokenToMint(address user, uint256 amountDcsToMint) internal view {
        uint256 userHealthFactor = _calculateHealthFactorWithNewMint(user, amountDcsToMint);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor();
        }
    }

    function _revertIfHealthFactorBrokenToRedeem(address user, uint256 amountCollateralToRedeem) internal view {
        uint256 userHealthFactor = _calculateHealthFactorToRedeemCollateral(user, amountCollateralToRedeem);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor();
        }
    }

    function _revertIfHealthFactorBroken(address user) internal view {
        uint256 userHealthFactor = _calculateHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor();
        }
    }

    function _calculateHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // healthFactor = collateralValueInUsd / totalDscMinted;

        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; // true health factor
    }

    function _calculateHealthFactorWithNewMint(address user, uint256 amountDcsToMint) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 newTotalDcs = amountDcsToMint + totalDscMinted;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / newTotalDcs; // true health factor
    }

    function _calculateHealthFactorToRedeemCollateral(address user, uint256 amountCollateralToRedeem)
        internal
        view
        returns (uint256)
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold =
            ((collateralValueInUsd - amountCollateralToRedeem) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /*//////////////////////////////////////////////////////////////
                        Public & VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // маю пройтись по масиву із всіх collateralTokens, перевести їх у usdValue і тоді сумую всіх
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            // сумуються всі значення в usd для кожного токена
            totalCollateralValueInUsd += getUsdValue(token, amount);
            // totalCollateralValueInUsd = totalCollateralValueInUsd + getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getUserHealthFactor(address user) external view returns (uint256) {
        return _calculateHealthFactor(user);
    }
}
