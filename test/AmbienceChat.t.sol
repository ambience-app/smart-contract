// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AmbienceChat.sol";

contract AmbienceChatTest is Test {
    AmbienceChat public ambienceChat;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    function setUp() public {
        vm.prank(owner);
        ambienceChat = new AmbienceChat();
        
        // Set up test users
        vm.prank(user1);
        ambienceChat.setUsername("user1");
        
        vm.prank(user2);
        ambienceChat.setUsername("user2");
    }
    
    function testUserProfile() public {
        // Test user profile setting
        address testUser = address(4);
        string memory testUsername = "testuser";
        
        vm.prank(testUser);
        ambienceChat.setUsername(testUsername);
        
        (string memory username, bool isRegistered) = ambienceChat.userProfiles(testUser);
        assertEq(username, testUsername);
        assertTrue(isRegistered);
        
        // Test username uniqueness
        address anotherUser = address(5);
        vm.prank(anotherUser);
        vm.expectRevert("Username already taken");
        ambienceChat.setUsername(testUsername);
    }
    
    function testCreateRoom() public {
        string memory roomName = "Test Room";
        bool isPrivate = false;
        
        vm.prank(user1);
        uint256 roomId = ambienceChat.createRoom(roomName, isPrivate);
        
        (string memory name, address roomOwner, bool roomIsPrivate,,) = ambienceChat.rooms(roomId);
        assertEq(name, roomName);
        assertEq(roomOwner, user1);
        assertEq(roomIsPrivate, isPrivate);
        
        // Test that the default "General" room exists
        (name,, roomIsPrivate,,) = ambienceChat.rooms(0);
        assertEq(name, "General");
        assertFalse(roomIsPrivate);
    }
    
    function testSendMessage() public {
        // Create a room
        vm.prank(user1);
        uint256 roomId = ambienceChat.createRoom("Test Room", false);
        
        // Send a message
        string memory messageContent = "Hello, world!";
        vm.prank(user1);
        uint256 messageId = ambienceChat.sendMessage(roomId, messageContent);
        
        // Verify message
        (address sender, string memory content,,) = ambienceChat.messages(messageId);
        assertEq(sender, user1);
        assertEq(content, messageContent);
        
        // Check room message count
        (,,, uint256 messageCount) = ambienceChat.getRoomInfo(roomId);
        assertEq(messageCount, 1);
    }
    
    function testPrivateRoomAccess() public {
        // Create private room
        vm.prank(user1);
        uint256 roomId = ambienceChat.createRoom("Private Room", true);
        
        // User2 tries to send message (should fail)
        vm.prank(user2);
        vm.expectRevert("Access denied: not a member of this private room");
        ambienceChat.sendMessage(roomId, "Hello");
        
        // Add user2 to private room
        vm.prank(user1);
        ambienceChat.addRoomMember(roomId, user2);
        
        // Now user2 should be able to send message
        vm.prank(user2);
        ambienceChat.sendMessage(roomId, "Hello from user2");
    }
    
    function testMessageCooldown() public {
        // Use the default General room (roomId = 0)
        uint256 roomId = 0;
        
        // First message
        vm.prank(user1);
        ambienceChat.sendMessage(roomId, "First message");
        
        // Try to send another message immediately (should fail)
        vm.prank(user1);
        vm.expectRevert("Message cooldown period has not passed");
        ambienceChat.sendMessage(roomId, "Second message");
        
        // Fast forward time (1 minute + 1 second)
        vm.warp(block.timestamp + 61);
        
        // Now should work
        vm.prank(user1);
        ambienceChat.sendMessage(roomId, "Second message");
    }
}
