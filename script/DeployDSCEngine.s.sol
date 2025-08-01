// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSCEngine is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() public returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address weth, address wbtc, address usdc, address priceFeedWeth, address priceFeedWbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [priceFeedWeth, priceFeedWbtc];

        vm.startBroadcast();
        DecentralizedStablecoin dsc = new DecentralizedStablecoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}
