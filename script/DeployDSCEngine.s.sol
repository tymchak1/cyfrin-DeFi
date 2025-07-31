// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDSCEngine is Script {
    function run() public returns (DSCEngine) {
        vm.startBroadcast();
        DSCEngine dscEngine = new DSCEngine();
        vm.stopBroadcast();
        return dscEngine;
    }
}
