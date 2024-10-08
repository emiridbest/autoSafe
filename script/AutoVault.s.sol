// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AutoVault} from "../src/AutoVault.sol";

contract CounterScript is Script {
    AutoVault public autoVault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        autoVault = new AutoVault();

        vm.stopBroadcast();
    }
}
