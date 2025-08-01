// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";

contract DSCEngineTest {
    DeployDSCEngine deployer;
    DecentralizedStablecoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethPriceInUsd;
    address weth;

    function setUp() public {
        deployer = new DeployDSCEngine();
        return (dsc, engine, config) = deployer.run();
        (ethPriceInUsd,, weth,,) = config.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assert(expectUsd == actualUsd);
    }
}
