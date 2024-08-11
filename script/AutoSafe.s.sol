// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AutoSafe} from "../src/AutoSafe.sol";

contract CounterScript is Script {
    AutoSafe public autosafe;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        autosafe = new AutoSafe();

        vm.stopBroadcast();
    }
}
