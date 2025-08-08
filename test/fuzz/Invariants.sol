// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    // test/fuzz/Invariants.sol

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        require(wethValue + wbtcValue >= wethValue, "Invariant: Total collateral value overflow");

        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNeverGetRevert() public view {
        dscEngine.i_dsc();
        dscEngine.getCollateralTokens();

        address[] memory users = handler.getUserWithCollateralDeposited();
        if (users.length > 0) {
            address user = users[0];
            address wethAddress = handler.getWeth();
            address wbtcAddress = handler.getWbtc();

            dscEngine.getTokenAmountFromUsd(wethAddress, 1e18);
            dscEngine.getAccountCollateralValueInUsd(user);
            dscEngine.getUsdValue(wethAddress, 1e18);
            dscEngine.getAccountInformation(user);
            dscEngine.getUserHealthFactor(user);
            dscEngine.getCollateralDeposited(user, wethAddress);
            dscEngine.calculateHealthFactor(10 ether, 100 ether);

            dscEngine.getTokenAmountFromUsd(wbtcAddress, 1e18);
            dscEngine.getUsdValue(wbtcAddress, 1e18);
            dscEngine.getCollateralDeposited(user, wbtcAddress);
        }
    }
}
