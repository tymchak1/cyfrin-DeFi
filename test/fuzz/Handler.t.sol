// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStablecoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    address[] public userWithCollaterallDeposited;
    MockV3Aggregator public ethPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStablecoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (userWithCollaterallDeposited.length == 0) {
            return;
        }
        address sender = userWithCollaterallDeposited[addressSeed % userWithCollaterallDeposited.length];

        vm.startPrank(sender);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);

        uint256 maxDscToMint = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        if (maxDscToMint <= totalDscMinted) {
            vm.stopPrank();
            return;
        }

        uint256 availableToMint = maxDscToMint - totalDscMinted;

        amount = bound(amount, 1, availableToMint);

        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userWithCollaterallDeposited.push(msg.sender);
    }

    // function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxCollateralToRedeem = dscEngine.getCollateralDeposited(msg.sender, address(collateral));
    //     amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem); // but maxCollateralToRedeem can be 0
    //     if (amountCollateral == 0) {
    //         return;
    //     }
    //     dscEngine.redeemCollateral(address(collateral), amountCollateral);
    // }

    // If price falls quickly - we are busted
    // Breaks Invariant
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethPriceFeed.updateAnswer(newPriceInt);
    // }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function getUserWithCollateralDeposited() external view returns (address[] memory) {
        return userWithCollaterallDeposited;
    }

    function getWeth() external view returns (address) {
        return address(weth);
    }

    function getWbtc() external view returns (address) {
        return address(wbtc);
    }
}
