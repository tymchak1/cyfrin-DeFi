// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Errors} from "../../src/Errors.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test, Errors {
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

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

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                               Constructor TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(address(weth), usdAmount);
        assertEq(expectedWeth, actualWeth);
    }
    /*//////////////////////////////////////////////////////////////
                        depositCollateral TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositedAndMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 mintAmount = 5_000e18;
        dscEngine.mintDsc(mintAmount);

        _;
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        _;
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine_MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine_TokenIsNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralAndEmitEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, false);
        emit CollaterallDeposited(USER, weth, AMOUNT_COLLATERAL);

        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralDepositCollateralAndGetAccountInfo() public depositedCollateral {
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValue);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositSucceedsEvenIfHealthFactorIsLow() public depositedCollateral {
        uint256 safeMintAmount = 5_000e18;
        dscEngine.mintDsc(safeMintAmount);

        uint256 newPrice = 100 * 1e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(int256(newPrice));

        ERC20Mock(weth).mint(USER, 1 ether);
        ERC20Mock(weth).approve(address(dscEngine), 1 ether);
        dscEngine.depositCollateral(weth, 1 ether);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        redeemCollateral TESTS
    //////////////////////////////////////////////////////////////*/

    function testRedeemCollateralRevertsIfAmountIsZero() public {
        vm.expectRevert(DSCEngine_MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralWorksCorrectly() public depositedCollateral {
        uint256 redeemAmount = 5 ether;

        uint256 userBalanceBefore = ERC20Mock(weth).balanceOf(USER);
        (uint256 dscMintedBefore, uint256 collateralValueBefore) = dscEngine.getAccountInformation(USER);

        dscEngine.redeemCollateral(weth, redeemAmount);

        uint256 userBalanceAfter = ERC20Mock(weth).balanceOf(USER);
        (uint256 dscMintedAfter, uint256 collateralValueAfter) = dscEngine.getAccountInformation(USER);

        assertEq(userBalanceAfter, userBalanceBefore + redeemAmount);
        assertEq(dscMintedAfter, dscMintedBefore);

        uint256 expectedCollateralValueAfter = collateralValueBefore - dscEngine.getUsdValue(weth, redeemAmount);
        assertEq(collateralValueAfter, expectedCollateralValueAfter);

        vm.stopPrank();
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateral {
        uint256 redeemAmount = 3 ether;

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, redeemAmount, weth);

        dscEngine.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 maxDscToMint = 10_000e18;
        dscEngine.mintDsc(maxDscToMint);
        // HF = 1 -> can not redeem anything
        vm.expectRevert(DSCEngine_BreaksHealthFactor.selector);
        dscEngine.redeemCollateral(weth, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            mintDsc TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertWhenMintingBreaksHealthFactor() public depositedCollateral {
        uint256 excessiveMintAmount = 10_001e18; // trying to mint 10 001 DSC, but can only 10 000
        vm.expectRevert(DSCEngine_BreaksHealthFactor.selector);

        dscEngine.mintDsc(excessiveMintAmount);
    }

    function testMintDscEmitsEvent() public depositedCollateral {
        uint256 mintAmount = 5_000e18;
        vm.expectEmit(true, true, false, false);
        emit DscMinted(USER, mintAmount);
        dscEngine.mintDsc(mintAmount);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount);
    }

    function testMintDscUpdatesUserState() public depositedAndMinted {
        uint256 mintAmount = 5_000e18;

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount);

        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(userDscBalance, mintAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            burnDsc TESTS
    //////////////////////////////////////////////////////////////*/

    function testBurnRevertsIfAmountIsZero() public {
        vm.expectRevert(DSCEngine_MustBeMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }

    function testBurnEmitsEvent() public depositedAndMinted {
        uint256 burnAmount = 5_000e18;

        dsc.approve(address(dscEngine), burnAmount);

        vm.expectEmit(true, true, false, false);
        emit DscBurned(USER, burnAmount);

        dscEngine.burnDsc(burnAmount);
    }

    function testBurnReducesDscBalanceAndUpdatesState() public depositedAndMinted {
        uint256 burnAmount = 2_000e18;

        dsc.approve(address(dscEngine), burnAmount);
        dscEngine.burnDsc(burnAmount);

        (uint256 totalMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalMinted, 3_000e18);

        assertEq(dsc.balanceOf(USER), 3_000e18);
    }

    function testBurnImprovesHealthFactor() public depositedAndMinted {
        uint256 initialHealthFactor = dscEngine.getUserHealthFactor(USER);

        uint256 burnAmount = 2_000e18;
        dsc.approve(address(dscEngine), burnAmount);
        dscEngine.burnDsc(burnAmount);

        uint256 newHealthFactor = dscEngine.getUserHealthFactor(USER);

        assertGt(newHealthFactor, initialHealthFactor); // new > old
    }

    /*//////////////////////////////////////////////////////////////
                        Multistep Functions TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositCollateralAndMintWorksCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        uint256 mintAmount = 5_000e18;

        dscEngine.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, mintAmount);
        (uint256 totalMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        assertEq(totalMinted, mintAmount);

        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);

        vm.stopPrank();
    }

    function testRedeemCollateralForDscWorksCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        // starting balance = 20_000$
        // mint 1000 (5 ether of collateral)
        // redeem = get back my 5 ether to my wallet
        // so only 5 ether left, because half is redeemed
        dscEngine.mintDsc(5_000e18);

        dsc.approve(address(dscEngine), 5_000e18);

        uint256 userBalanceBefore = ERC20Mock(weth).balanceOf(USER);
        uint256 collateralAdjustedForThreshold = (AMOUNT_COLLATERAL * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        dscEngine.redeemCollateralForDsc(weth, collateralAdjustedForThreshold, 5_000e18);

        uint256 userBalanceAfter = ERC20Mock(weth).balanceOf(USER);
        assertGt(userBalanceAfter, userBalanceBefore);
        uint256 expectedCollateralValueAfter = AMOUNT_COLLATERAL - collateralAdjustedForThreshold;
        (uint256 dscMintedAfter, uint256 collateralValueAfter) = dscEngine.getAccountInformation(USER);
        assertEq(dscMintedAfter, 0);
        assertEq(collateralValueAfter, dscEngine.getUsdValue(weth, expectedCollateralValueAfter));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            liquidate TESTS
    //////////////////////////////////////////////////////////////*/

    function testLiquidateRevertsIfDebtToCoverIsZero() public {
        vm.expectRevert(DSCEngine_MustBeMoreThanZero.selector);
        dscEngine.liquidate(weth, USER, 0);
    }

    function testLiquidateRevertsIfUserHealthFactorIsNotBroken() public depositedAndMinted {
        address LIQUIDATOR = makeAddr("liquidator");

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine_UserHealthFactorIsNotBroken.selector);
        dscEngine.liquidate(weth, USER, 1000e18);
        vm.stopPrank();
    }

    function testLiquidateWorksCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 mintAmount = 9_000e18;
        dscEngine.mintDsc(mintAmount);
        vm.stopPrank();

        address LIQUIDATOR = makeAddr("liquidator");

        vm.startPrank(address(dscEngine));
        dsc.mint(LIQUIDATOR, 10_000e18);
        vm.stopPrank();

        uint256 newEthPrice = 1000e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(int256(newEthPrice));

        uint256 startingHealthFactor = dscEngine.getUserHealthFactor(USER);

        uint256 debtToCover = 4000e18;

        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dscEngine), debtToCover);
        dscEngine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();

        uint256 endingHealthFactor = dscEngine.getUserHealthFactor(USER);
        assertGt(endingHealthFactor, startingHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                           INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUserCanDepositMintBurnWithdrawFully() public {
        vm.startPrank(USER);

        // Deposit collateral
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Mint DSC
        uint256 mintAmount = 5_000e18;
        dscEngine.mintDsc(mintAmount);

        // Burn DSC
        dsc.approve(address(dscEngine), mintAmount);
        dscEngine.burnDsc(mintAmount);

        // Withdraw collateral
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        // Check final state
        (uint256 dscMinted, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        assertEq(dscMinted, 0);
        assertEq(collateralValue, 0);

        vm.stopPrank();
    }

    function testWithdrawFailsIfHealthFactorIsBroken() public depositedAndMinted {
        uint256 newPrice = 100 * 1e8; // drop ETH price from 2000 to 100
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(int256(newPrice));

        vm.expectRevert(DSCEngine_BreaksHealthFactor.selector);
        dscEngine.redeemCollateral(weth, 1 ether);
    }

    function testCanDepositMintThenAddMoreCollateralAndMintMore() public depositedCollateral {
        uint256 firstMintAmount = 2_000e18;
        dscEngine.mintDsc(firstMintAmount);

        // Add more collateral
        ERC20Mock(weth).mint(USER, 5 ether);
        ERC20Mock(weth).approve(address(dscEngine), 5 ether);
        dscEngine.depositCollateral(weth, 5 ether);

        // Mint more DSC
        uint256 secondMintAmount = 3_000e18;
        dscEngine.mintDsc(secondMintAmount);

        // Check total minted DSC
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, firstMintAmount + secondMintAmount);

        vm.stopPrank();
    }

    function testMultipleUsersIndependentState() public {
        address user2 = makeAddr("user2");

        // User1 deposit and mint
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDsc(4_000e18);
        vm.stopPrank();

        // User2 mint and deposit
        ERC20Mock(weth).mint(user2, 10 ether);
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateral(weth, 10 ether);
        dscEngine.mintDsc(3_000e18);
        vm.stopPrank();

        // Check user1 state
        (uint256 dscMinted1, uint256 collateralValue1) = dscEngine.getAccountInformation(USER);
        assertEq(dscMinted1, 4_000e18);
        assertGt(collateralValue1, 0);

        // Check user2 state
        (uint256 dscMinted2, uint256 collateralValue2) = dscEngine.getAccountInformation(user2);
        assertEq(dscMinted2, 3_000e18);
        assertGt(collateralValue2, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             Getters TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetAccountCollateralValueInUsd() public depositedCollateral {
        uint256 expectedValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 actualValue = dscEngine.getAccountCollateralValueInUsd(USER);
        assertEq(expectedValue, actualValue);
    }

    function testGetAccountInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
    }

    function testGetUserHealthFactor_NoDebt() public depositedCollateral {
        uint256 hf = dscEngine.getUserHealthFactor(USER);
        assertEq(hf, type(uint256).max);
    }

    function testGetCollateralDeposited() public depositedCollateral {
        uint256 depositedAmount = dscEngine.getCollateralDeposited(USER, weth);
        assertEq(depositedAmount, AMOUNT_COLLATERAL);
    }

    function testCalculateHealthFactor() public view {
        uint256 collateralValueInUsd = 2000 ether;
        uint256 debt = 1000 ether;
        uint256 expectedHF = (collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION) * 1e18 / debt;
        uint256 actualHF = dscEngine.calculateHealthFactor(debt, collateralValueInUsd);
        assertEq(expectedHF, actualHF);
    }
}
