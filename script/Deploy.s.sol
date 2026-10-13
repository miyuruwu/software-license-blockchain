// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SoftwareLicenseManager} from "../src/SoftwareLicenseManager.sol";

interface VmDeploy {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract Deploy {
    VmDeploy private constant vm = VmDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (SoftwareLicenseManager manager) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address publisher = vm.envAddress("PUBLISHER_ADDRESS");
        vm.startBroadcast();
        manager = new SoftwareLicenseManager(admin, publisher);
        vm.stopBroadcast();
    }
}
