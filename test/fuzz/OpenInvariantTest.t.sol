// // SPDX-License-Identifier: MIT

// // Our invariants / properties

// // 1. TotalSupply of DSC > collateralDeposited
// // 2. Getter view functions never revert <- evergreen invariant

// pragma solidity ^0.8.27;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DecentralizedStablecoin dsc;
//     DSCEngine dscEngine;
//     HelperConfig helperConfig;
//     address weth;
//     address wbtc;

//     function setUp() public {
//         deployer = new DeployDSC();
//         (dsc, dscEngine, helperConfig) = deployer.run();
//         (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant__protocolMustHaveMoreValueThanTotalSupply() public view {
//         // get totalSupply
//         // get (weth+btc)
//         // compare
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

//         uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

//         console.log("wethValue: ", wethValue);
//         console.log("wbtcValue: ", wbtcValue);
//         console.log("totalSupply: ", totalSupply);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
