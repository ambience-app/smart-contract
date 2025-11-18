// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/AmbienceChat.sol";

contract DeployAmbienceChat is Script {
    function run() external {
        // Get the private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the contract
        AmbienceChat ambienceChat = new AmbienceChat();
        
        // Log the deployed contract address
        console.log("AmbienceChat deployed to:", address(ambienceChat));
        
        vm.stopBroadcast();
    }
}
