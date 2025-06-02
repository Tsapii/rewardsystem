// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title NotificationSystem
 * @dev A decentralized notification system with validation mechanics, user levels, and rewards
 * Features:
 * - Users can send notifications with deposit
 * - Community validation/rejection system
 * - Tiered user levels with rewards
 * - Ban system for spammers
 * - Leaderboard tracking
 */
contract NotificationSystem {
    // Contract owner address
    address public owner;

    // Enum defining user levels based on points
    enum UserLevel { BRONZE, SILVER, GOLD, PLATINUM }
    
    // Enum defining notification statuses
    enum NotificationStatus { PENDING, VALIDATED, REJECTED }
    
    // Enum defining notification categories
    enum NotificationCategory { EVENT, WARNING, ERROR, ANNOUNCEMENT, ALERT }

    // User structure storing all user-related data
    struct User {
        uint256 points;                 // Accumulated points
        UserLevel level;                // Current user level
        uint256 notificationsSent;      // Total notifications sent
        uint256 notificationsValidated; // Total notifications validated
        uint256 lastNotificationTime;   // Timestamp of last sent notification
        uint256 rejectionCount;         // Count of rejected notifications
        bool isBanned;                 // Ban status
        uint256 depositBalance;         // Total deposited ETH
    }

    // Notification structure storing all notification data
    struct Notification {
        uint256 id;                     // Unique notification ID
        string message;                 // Notification content
        address sender;                 // Creator address
        uint256 validationCount;       // Number of validations
        uint256 rejectionCount;        // Number of rejections
        uint256 creationTime;          // Block timestamp when created
        NotificationStatus status;     // Current status
        NotificationCategory category; // Notification type
        mapping(address => bool) validators; // Addresses that validated
        mapping(address => bool) rejectors;  // Addresses that rejected
    }

    // System constants
    uint256 public constant REQUIRED_VALIDATIONS = 5; // Validations needed for approval
    uint256 public constant REQUIRED_REJECTIONS = 3;  // Rejections needed for rejection
    uint256 public constant COOLDOWN_PERIOD = 1 hours; // Delay between user notifications
    uint256 public constant NOTIFICATION_LIFETIME = 7 days; // Active validation period
    uint256 public constant BAN_DURATION = 3 days;    // Ban duration after 3 rejections

    // Notification deposit amount (in ETH)
    uint256 public notificationDeposit = 1 ether;

    // Reward amounts per level
    uint256 public constant BRONZE_REWARD = 5;
    uint256 public constant SILVER_REWARD = 8;
    uint256 public constant GOLD_REWARD = 12;
    uint256 public constant PLATINUM_REWARD = 20;

    // Point thresholds for each level
    uint256 public silverThreshold = 100;
    uint256 public goldThreshold = 500;
    uint256 public platinumThreshold = 2000;

    // Storage variables
    Notification[] public notifications;              // All notifications
    mapping(address => User) public users;           // User address => User data
    mapping(address => uint256) public balances;    // User token balances
    mapping(address => uint256) public banExpiry;  // Ban expiration timestamps
    address[] public leaderboard;                 // Top users addresses

    // Events
    event NotificationSent(uint256 indexed id, address indexed sender, string message, NotificationCategory category);
    event NotificationValidated(uint256 indexed id, address indexed validator);
    event NotificationRejected(uint256 indexed id, address indexed rejector);
    event RewardSent(uint256 indexed id, address indexed sender, uint256 amount, UserLevel tier);
    event UserLevelUpgraded(address indexed user, UserLevel newLevel);
    event TicketPurchased(address indexed buyer, uint256 price, string ticketType);
    event ThresholdsUpdated(uint256 silver, uint256 gold, uint256 platinum);
    event UserBanned(address indexed user, uint256 until);
    event UserUnbanned(address indexed user);
    event DepositCollected(address indexed user, uint256 amount);
    event DepositRefunded(address indexed user, uint256 amount);
    event DepositAmountChanged(uint256 newAmount);

    // Modifier for owner-only functions
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    /**
     * @dev Contract constructor sets the deployer as owner
     */
    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Sets the required deposit amount for notifications
     * @param _newDeposit New deposit amount in wei
     * Requirements:
     * - Only callable by owner
     * - Deposit must be positive
     */
    function setNotificationDeposit(uint256 _newDeposit) external onlyOwner {
        require(_newDeposit > 0, "Deposit amount must be positive");
        notificationDeposit = _newDeposit;
        emit DepositAmountChanged(_newDeposit);
    }

    /**
     * @dev Returns current deposit requirement
     * @return Current deposit amount in wei
     */
    function getCurrentDepositRequirement() external view returns (uint256) {
        return notificationDeposit;
    }

    /**
     * @dev Sends a new notification
     * @param _message Notification content
     * @param _category Notification category from enum
     * Requirements:
     * - User not banned
     * - Cooldown period passed
     * - Sufficient deposit sent
     * Emits NotificationSent event
     */
    function sendNotification(string memory _message, NotificationCategory _category) external payable {
        User storage user = users[msg.sender];
        require(!user.isBanned, "You are currently banned");
        require(block.timestamp >= user.lastNotificationTime + COOLDOWN_PERIOD, "Cooldown period not passed");
        require(msg.value >= notificationDeposit, "Insufficient deposit");

        // Refund excess ETH
        if (msg.value > notificationDeposit) {
            payable(msg.sender).transfer(msg.value - notificationDeposit);
        }

        // Create new notification
        uint256 id = notifications.length;
        Notification storage newNotification = notifications.push();
        newNotification.id = id;
        newNotification.message = _message;
        newNotification.sender = msg.sender;
        newNotification.creationTime = block.timestamp;
        newNotification.status = NotificationStatus.PENDING;
        newNotification.category = _category;

        // Update user stats
        user.lastNotificationTime = block.timestamp;
        user.notificationsSent++;
        user.depositBalance += notificationDeposit;

        emit NotificationSent(id, msg.sender, _message, _category);
    }

    /**
     * @dev Validates a notification
     * @param _id Notification ID to validate
     * Requirements:
     * - Notification exists and is active
     * - Caller hasn't voted before
     * - Caller isn't the sender
     * Emits NotificationValidated event
     */
    function validateNotification(uint256 _id) external {
        require(_id < notifications.length, "Invalid ID");
        Notification storage notification = notifications[_id];

        require(block.timestamp <= notification.creationTime + NOTIFICATION_LIFETIME, "Expired");
        require(!notification.validators[msg.sender], "Already validated");
        require(!notification.rejectors[msg.sender], "Already rejected");
        require(msg.sender != notification.sender, "Can't validate own");

        // Record validation
        notification.validators[msg.sender] = true;
        notification.validationCount++;

        // Update validator stats
        User storage validator = users[msg.sender];
        validator.notificationsValidated++;
        validator.points += 1;
        _updateUserLevel(msg.sender);

        emit NotificationValidated(_id, msg.sender);

        // Check if validation threshold reached
        if (notification.validationCount >= REQUIRED_VALIDATIONS) {
            _processSuccessfulValidation(_id);
        }
    }

    /**
     * @dev Internal function to process successful validation
     * @param _id Notification ID that reached validation threshold
     * - Updates notification status
     * - Awards sender with tokens
     * - Refunds deposit
     * Emits RewardSent and DepositRefunded events
     */
    function _processSuccessfulValidation(uint256 _id) private {
        Notification storage notification = notifications[_id];
        notification.status = NotificationStatus.VALIDATED;

        User storage sender = users[notification.sender];
        uint256 reward = _getRewardForLevel(sender.level);

        // Award sender
        balances[notification.sender] += reward;
        sender.points += reward * 2;

        // Refund deposit
        sender.depositBalance -= notificationDeposit;
        payable(notification.sender).transfer(notificationDeposit);
        emit DepositRefunded(notification.sender, notificationDeposit);

        _updateUserLevel(notification.sender);
        emit RewardSent(_id, notification.sender, reward, sender.level);
    }

    /**
     * @dev Rejects a notification
     * @param _id Notification ID to reject
     * Requirements:
     * - Notification exists and is active
     * - Caller hasn't voted before
     * - Caller isn't the sender
     * Emits NotificationRejected event
     */
    function rejectNotification(uint256 _id) external {
        require(_id < notifications.length, "Invalid ID");
        Notification storage notification = notifications[_id];

        require(block.timestamp <= notification.creationTime + NOTIFICATION_LIFETIME, "Expired");
        require(!notification.validators[msg.sender], "Already validated");
        require(!notification.rejectors[msg.sender], "Already rejected");
        require(msg.sender != notification.sender, "Can't reject own");

        // Record rejection
        notification.rejectors[msg.sender] = true;
        notification.rejectionCount++;

        emit NotificationRejected(_id, msg.sender);

        // Check if rejection threshold reached
        if (notification.rejectionCount >= REQUIRED_REJECTIONS) {
            _processFailedNotification(_id);
        }
    }

    /**
     * @dev Internal function to process failed notification
     * @param _id Notification ID that reached rejection threshold
     * - Updates notification status
     * - Potentially bans sender if too many rejections
     * Emits UserBanned if applicable
     */
    function _processFailedNotification(uint256 _id) private {
        Notification storage notification = notifications[_id];
        notification.status = NotificationStatus.REJECTED;

        User storage sender = users[notification.sender];
        sender.rejectionCount++;

        // Ban user if 3rd rejection
        if (sender.rejectionCount >= 3) {
            sender.isBanned = true;
            banExpiry[notification.sender] = block.timestamp + BAN_DURATION;
            emit UserBanned(notification.sender, banExpiry[notification.sender]);
        }

        // Confiscate deposit
        sender.depositBalance -= notificationDeposit;
        emit DepositCollected(notification.sender, notificationDeposit);
    }

    /**
     * @dev Allows banned users to unban themselves after ban expires
     * Requirements:
     * - User must be banned
     * - Ban period must have expired
     * Emits UserUnbanned event
     */
    function checkAndUnban() external {
        require(users[msg.sender].isBanned, "Not banned");
        require(block.timestamp >= banExpiry[msg.sender], "Ban not expired");

        users[msg.sender].isBanned = false;
        users[msg.sender].rejectionCount = 0;
        emit UserUnbanned(msg.sender);
    }

    /**
     * @dev Purchases a ticket using token balance
     * @param _ticketType Type of ticket to purchase
     * Requirements:
     * - Sufficient token balance
     * Emits TicketPurchased event
     */
    function purchaseTicket(string memory _ticketType) external {
        uint256 price = _getTicketPrice(_ticketType);
        require(balances[msg.sender] >= price, "Insufficient balance");
        balances[msg.sender] -= price;

        emit TicketPurchased(msg.sender, price, _ticketType);
    }

    /**
     * @dev Internal function to get ticket price by type
     * @param _ticketType Type of ticket
     * @return Price in tokens
     */
    function _getTicketPrice(string memory _ticketType) private pure returns (uint256) {
        if (keccak256(bytes(_ticketType)) == keccak256(bytes("standard"))) return 10;
        if (keccak256(bytes(_ticketType)) == keccak256(bytes("student"))) return 7;
        if (keccak256(bytes(_ticketType)) == keccak256(bytes("monthly"))) return 50;
        revert("Invalid ticket type");
    }

    /**
     * @dev Internal function to get reward amount by user level
     * @param _level UserLevel enum value
     * @return Reward amount in tokens
     */
    function _getRewardForLevel(UserLevel _level) private pure returns (uint256) {
        if (_level == UserLevel.PLATINUM) return PLATINUM_REWARD;
        if (_level == UserLevel.GOLD) return GOLD_REWARD;
        if (_level == UserLevel.SILVER) return SILVER_REWARD;
        return BRONZE_REWARD;
    }

    /**
     * @dev Updates user level based on points and maintains leaderboard
     * @param _user Address of user to update
     * Emits UserLevelUpgraded if level changed
     */
    function _updateUserLevel(address _user) private {
        User storage user = users[_user];
        UserLevel newLevel = _calculateLevel(user.points);

        if (newLevel != user.level) {
            user.level = newLevel;
            emit UserLevelUpgraded(_user, newLevel);
        }

        // Add to leaderboard if not already present
        bool found = false;
        for (uint i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i] == _user) {
                found = true;
                break;
            }
        }
        if (!found) leaderboard.push(_user);
    }

    /**
     * @dev Calculates user level based on points
     * @param _points User's total points
     * @return UserLevel enum value
     */
    function _calculateLevel(uint256 _points) private view returns (UserLevel) {
        if (_points >= platinumThreshold) return UserLevel.PLATINUM;
        if (_points >= goldThreshold) return UserLevel.GOLD;
        if (_points >= silverThreshold) return UserLevel.SILVER;
        return UserLevel.BRONZE;
    }

    // ========== VIEW FUNCTIONS ========== //

    /**
     * @dev Returns basic user statistics
     * @param _user Address to query
     * @return points User's total points
     * @return level Current UserLevel
     * @return sent Total notifications sent
     * @return validated Total notifications validated
     */
    function getUserBasicStats(address _user) public view returns (
        uint256 points,
        UserLevel level,
        uint256 sent,
        uint256 validated
    ) {
        User memory user = users[_user];
        return (user.points, user.level, user.notificationsSent, user.notificationsValidated);
    }

    /**
     * @dev Returns user's ban status
     * @param _user Address to query
     * @return isBanned Whether user is banned
     * @return expiryTime Timestamp when ban expires
     */
    function getUserBanStatus(address _user) public view returns (
        bool isBanned,
        uint256 expiryTime
    ) {
        return (users[_user].isBanned, banExpiry[_user]);
    }

    /**
     * @dev Returns user's token balance
     * @param _user Address to query
     * @return Token balance
     */
    function getUserBalance(address _user) public view returns (uint256) {
        return balances[_user];
    }

    /**
     * @dev Returns notification details
     * @param _id Notification ID to query
     * @return id Notification ID
     * @return message Notification content
     * @return sender Creator address
     * @return validationCount Number of validations
     * @return rejectionCount Number of rejections
     * @return isActive Whether notification is still active
     * @return status Current NotificationStatus
     * @return category NotificationCategory
     */
    function getNotificationDetails(uint256 _id) public view returns (
        uint256 id,
        string memory message,
        address sender,
        uint256 validationCount,
        uint256 rejectionCount,
        bool isActive,
        NotificationStatus status,
        NotificationCategory category
    ) {
        require(_id < notifications.length, "Invalid ID");
        Notification storage n = notifications[_id];
        return (
            n.id,
            n.message,
            n.sender,
            n.validationCount,
            n.rejectionCount,
            block.timestamp <= n.creationTime + NOTIFICATION_LIFETIME,
            n.status,
            n.category
        );
    }

    /**
     * @dev Returns current leaderboard addresses
     * @return Array of user addresses
     */
    function getLeaderboard() public view returns (address[] memory) {
        return leaderboard;
    }

    // ========== OWNER FUNCTIONS ========== //

    /**
     * @dev Sets point thresholds for each user level
     * @param _silver Points needed for SILVER
     * @param _gold Points needed for GOLD
     * @param _platinum Points needed for PLATINUM
     * Requirements:
     * - Only callable by owner
     * - Thresholds must be in ascending order
     * Emits ThresholdsUpdated event
     */
    function setTierThresholds(uint256 _silver, uint256 _gold, uint256 _platinum) external onlyOwner {
        require(_silver < _gold && _gold < _platinum, "Invalid thresholds");
        silverThreshold = _silver;
        goldThreshold = _gold;
        platinumThreshold = _platinum;
        emit ThresholdsUpdated(_silver, _gold, _platinum);
    }

    /**
     * @dev Allows owner to withdraw contract funds
     * @param _amount Amount to withdraw in wei
     * Requirements:
     * - Only callable by owner
     */
    function withdrawFunds(uint256 _amount) external onlyOwner {
        payable(owner).transfer(_amount);
    }
}