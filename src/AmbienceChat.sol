// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title AmbienceChat
 * @dev Onchain messaging system with room-based chat functionality
 * @notice This contract enables decentralized chat with message storage on Base blockchain
 */
contract AmbienceChat {
    // ============ Structs ============

    /**
     * @dev Message struct with packed data for gas optimization
     * @param sender Address of the message sender
     * @param content Message content (stored as string)
     * @param timestamp Unix timestamp when message was sent
     * @param roomId ID of the room this message belongs to
     */
    struct Message {
        address sender;
        string content;
        uint256 timestamp;
        uint256 roomId;
    }

    /**
     * @dev Room struct containing room metadata and settings
     * @param name Room display name
     * @param owner Address of room creator/owner
     * @param isPrivate Whether the room requires permission to access
     * @param createdAt Unix timestamp of room creation
     * @param messageCount Number of messages in this room
     */
    struct Room {
        string name;
        address owner;
        bool isPrivate;
        uint256 createdAt;
        uint256 messageCount;
    }

    /**
     * @dev User profile information
     * @param username Display name chosen by user
     * @param isRegistered Whether user has set up profile
     */
    struct UserProfile {
        string username;
        bool isRegistered;
    }

    // ============ State Variables ============

    /// @dev Counter for generating unique message IDs
    uint256 private messageIdCounter;

    /// @dev Counter for generating unique room IDs
    uint256 private roomIdCounter;

    /// @dev Time (in seconds) a user must wait between sending messages
    uint256 public constant MESSAGE_COOLDOWN = 1 minutes;

    /// @dev Mapping to track the last message timestamp for each address
    mapping(address => uint256) public lastMessageTime;

    /// @dev Mapping from message ID to Message struct
    mapping(uint256 => Message) public messages;

    /// @dev Mapping from room ID to Room struct
    mapping(uint256 => Room) public rooms;

    /// @dev Mapping from address to UserProfile
    mapping(address => UserProfile) public userProfiles;

    /// @dev Mapping from room ID to member addresses (for private rooms)
    mapping(uint256 => mapping(address => bool)) public roomMembers;

    /// @dev Mapping from room ID to array of message IDs (for indexing)
    mapping(uint256 => uint256[]) public roomMessages;

    /// @dev Mapping to check if username is taken
    mapping(string => bool) public usernameTaken;

    // ============ Events ============

    /**
     * @dev Emitted when a new message is sent
     * @param messageId Unique identifier for the message
     * @param roomId ID of the room where message was sent
     * @param sender Address of the sender
     * @param content Message content
     * @param timestamp When the message was sent
     */
    event MessageSent(
        uint256 indexed messageId, uint256 indexed roomId, address indexed sender, string content, uint256 timestamp
    );

    /**
     * @dev Emitted when a new room is created
     * @param roomId Unique identifier for the room
     * @param name Room name
     * @param owner Address of room creator
     * @param isPrivate Whether room is private
     * @param createdAt When the room was created
     */
    event RoomCreated(uint256 indexed roomId, string name, address indexed owner, bool isPrivate, uint256 createdAt);

    /**
     * @dev Emitted when a user is added to a private room
     * @param roomId ID of the room
     * @param member Address of the new member
     * @param addedBy Address who added the member
     */
    event MemberAdded(uint256 indexed roomId, address indexed member, address indexed addedBy);

    /**
     * @dev Emitted when a user is removed from a private room
     * @param roomId ID of the room
     * @param member Address of the removed member
     * @param removedBy Address who removed the member
     */
    event MemberRemoved(uint256 indexed roomId, address indexed member, address indexed removedBy);

    /**
     * @dev Emitted when a user registers or updates their profile
     * @param user Address of the user
     * @param username Username chosen
     */
    event UserProfileUpdated(address indexed user, string username);

    // ============ Modifiers ============

    /**
     * @dev Ensures the caller has access to the specified room
     * @param roomId ID of the room to check access for
     */
    modifier canAccessRoom(uint256 roomId) {
        require(roomId < roomIdCounter, "Room does not exist");
        Room storage room = rooms[roomId];

        if (room.isPrivate) {
            require(
                roomMembers[roomId][msg.sender] || room.owner == msg.sender,
                "Access denied: not a member of this private room"
            );
        }
        _;
    }

    /**
     * @dev Ensures the caller is the owner of the specified room
     * @param roomId ID of the room to check ownership for
     */
    modifier onlyRoomOwner(uint256 roomId) {
        require(roomId < roomIdCounter, "Room does not exist");
        require(rooms[roomId].owner == msg.sender, "Only room owner can perform this action");
        _;
    }

    // ============ Constructor ============

    constructor() {
        // Initialize counters
        messageIdCounter = 0;
        roomIdCounter = 0;

        // Create a default public "General" room
        _createRoom("General", false);
    }

    // ============ User Profile Functions ============

    /**
     * @dev Register or update user profile with a username
     * @param username Desired username (must be unique)
     */
    function setUsername(string calldata username) external {
        require(bytes(username).length > 0, "Username cannot be empty");
        require(bytes(username).length <= 32, "Username too long");

        // If user already has a username, free it up
        if (userProfiles[msg.sender].isRegistered) {
            string memory oldUsername = userProfiles[msg.sender].username;
            usernameTaken[oldUsername] = false;
        }

        require(!usernameTaken[username], "Username already taken");

        userProfiles[msg.sender] = UserProfile({username: username, isRegistered: true});

        usernameTaken[username] = true;

        emit UserProfileUpdated(msg.sender, username);
    }

    /**
     * @dev Get username for an address
     * @param user Address to look up
     * @return username The user's username (empty string if not registered)
     */
    function getUsername(address user) external view returns (string memory) {
        return userProfiles[user].username;
    }

    // ============ Room Management Functions ============

    /**
     * @dev Create a new chat room
     * @param name Name of the room
     * @param isPrivate Whether the room should be private
     * @return roomId The ID of the newly created room
     */
    function createRoom(string calldata name, bool isPrivate) external returns (uint256) {
        return _createRoom(name, isPrivate);
    }

    /**
     * @dev Internal function to create a room
     * @param name Name of the room
     * @param isPrivate Whether the room should be private
     * @return roomId The ID of the newly created room
     */
    function _createRoom(string memory name, bool isPrivate) private returns (uint256) {
        require(bytes(name).length > 0, "Room name cannot be empty");
        require(bytes(name).length <= 64, "Room name too long");

        uint256 roomId = roomIdCounter++;

        rooms[roomId] =
            Room({name: name, owner: msg.sender, isPrivate: isPrivate, createdAt: block.timestamp, messageCount: 0});

        // Owner is automatically a member of private rooms
        if (isPrivate) {
            roomMembers[roomId][msg.sender] = true;
        }

        emit RoomCreated(roomId, name, msg.sender, isPrivate, block.timestamp);

        return roomId;
    }

    /**
     * @dev Add a member to a private room (only owner can do this)
     * @param roomId ID of the room
     * @param member Address to add as member
     */
    function addRoomMember(uint256 roomId, address member) external onlyRoomOwner(roomId) {
        require(rooms[roomId].isPrivate, "Can only add members to private rooms");
        require(!roomMembers[roomId][member], "Already a member");
        require(member != address(0), "Invalid address");

        roomMembers[roomId][member] = true;

        emit MemberAdded(roomId, member, msg.sender);
    }

    /**
     * @dev Remove a member from a private room (only owner can do this)
     * @param roomId ID of the room
     * @param member Address to remove from members
     */
    function removeRoomMember(uint256 roomId, address member) external onlyRoomOwner(roomId) {
        require(rooms[roomId].isPrivate, "Can only remove members from private rooms");
        require(roomMembers[roomId][member], "Not a member");
        require(member != rooms[roomId].owner, "Cannot remove room owner");

        roomMembers[roomId][member] = false;

        emit MemberRemoved(roomId, member, msg.sender);
    }

    /**
     * @dev Check if an address is a member of a room
     * @param roomId ID of the room
     * @param user Address to check
     * @return bool True if user has access to the room
     */
    function isMember(uint256 roomId, address user) external view returns (bool) {
        require(roomId < roomIdCounter, "Room does not exist");

        Room storage room = rooms[roomId];

        // Public rooms: everyone has access
        if (!room.isPrivate) {
            return true;
        }

        // Private rooms: check membership or ownership
        return roomMembers[roomId][user] || room.owner == user;
    }

    // ============ Messaging Functions ============

    /**
     * @dev Send a message to a room
     * @param roomId ID of the room to send message to
     * @param content Message content
     * @return messageId The ID of the newly created message
     */
    function sendMessage(uint256 roomId, string calldata content) external canAccessRoom(roomId) returns (uint256) {
        require(bytes(content).length > 0, "Message cannot be empty");
        require(bytes(content).length <= 1000, "Message too long");
        require(
            block.timestamp >= lastMessageTime[msg.sender] + MESSAGE_COOLDOWN,
            "Cooldown period not met. Please wait before sending another message."
        );

        // Update the last message time for this sender
        lastMessageTime[msg.sender] = block.timestamp;

        uint256 messageId = messageIdCounter++;

        messages[messageId] =
            Message({sender: msg.sender, content: content, timestamp: block.timestamp, roomId: roomId});

        // Add message to room's message array for indexing
        roomMessages[roomId].push(messageId);

        // Increment room message count
        rooms[roomId].messageCount++;

        emit MessageSent(messageId, roomId, msg.sender, content, block.timestamp);

        return messageId;
    }

    /**
     * @dev Get a specific message by ID
     * @param messageId ID of the message to retrieve
     * @return Message struct containing message data
     */
    function getMessage(uint256 messageId)
        external
        view
        canAccessRoom(messages[messageId].roomId)
        returns (Message memory)
    {
        require(messageId < messageIdCounter, "Message does not exist");
        return messages[messageId];
    }

    /**
     * @dev Get all message IDs for a specific room
     * @param roomId ID of the room
     * @return Array of message IDs in the room
     */
    function getRoomMessageIds(uint256 roomId) external view canAccessRoom(roomId) returns (uint256[] memory) {
        return roomMessages[roomId];
    }

    /**
     * @dev Get paginated messages from a room
     * @param roomId ID of the room
     * @param offset Starting index
     * @param limit Number of messages to retrieve
     * @return Array of Message structs
     */
    function getRoomMessages(uint256 roomId, uint256 offset, uint256 limit)
        external
        view
        canAccessRoom(roomId)
        returns (Message[] memory)
    {
        uint256[] storage messageIds = roomMessages[roomId];
        uint256 totalMessages = messageIds.length;

        require(offset < totalMessages, "Offset out of bounds");

        // Calculate actual number of messages to return
        uint256 remaining = totalMessages - offset;
        uint256 count = remaining < limit ? remaining : limit;

        Message[] memory result = new Message[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = messages[messageIds[offset + i]];
        }

        return result;
    }

    // ============ View Functions ============

    /**
     * @dev Get room information
     * @param roomId ID of the room
     * @return Room struct containing room data
     */
    function getRoom(uint256 roomId) external view returns (Room memory) {
        require(roomId < roomIdCounter, "Room does not exist");
        return rooms[roomId];
    }

    /**
     * @dev Get total number of rooms
     * @return Total room count
     */
    function getTotalRooms() external view returns (uint256) {
        return roomIdCounter;
    }

    /**
     * @dev Get total number of messages
     * @return Total message count
     */
    function getTotalMessages() external view returns (uint256) {
        return messageIdCounter;
    }

    /**
     * @dev Get message count for a specific room
     * @param roomId ID of the room
     * @return Number of messages in the room
     */
    function getRoomMessageCount(uint256 roomId) external view canAccessRoom(roomId) returns (uint256) {
        require(roomId < roomIdCounter, "Room does not exist");
        return rooms[roomId].messageCount;
    }
}
