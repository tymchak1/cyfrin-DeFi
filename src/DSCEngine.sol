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
            revert DSCEngine_MustBeMoreThatZero();
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
    uint256 private constant MIN_HEALTH_FACTOR = 1;

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

    function depositCollateralAndMint() external {}

    /**
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the collateral token (e.g., WETH, WBTC)
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @notice Follows CEI
     * @param amountDcsToMint The amount of DSC to mint
     * @notice User must more collateral value than the threhold
     */
    function mintDsc(uint256 amountDcsToMint) external {
        s_amountDscMinted[msg.sender] += amountDcsToMint;
        _revertIfHealthFactorBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountDcsToMint);
        if (!success) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    /*//////////////////////////////////////////////////////////////
                        Private & Internal View FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _revertIfHealthFactorBroken(address user) internal {
        uint256 userHealthFactor = _calculateHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // healthFactor = collateralValueInUsd / totalDscMinted;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; // true health factor
    }

    /*//////////////////////////////////////////////////////////////
                        Public & External FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_amountDscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
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
}
