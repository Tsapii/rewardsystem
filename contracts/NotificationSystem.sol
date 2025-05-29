// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NotificationSystem {
    address public owner;

    enum UserLevel { BRONZE, SILVER, GOLD, PLATINUM }
    enum NotificationStatus { PENDING, VALIDATED, REJECTED }
    enum NotificationCategory { EVENT, WARNING, ERROR, ANNOUNCEMENT, ALERT }

    struct User {
        uint256 points;
        UserLevel level;
        uint256 notificationsSent;
        uint256 notificationsValidated;
        uint256 lastNotificationTime;
        uint256 rejectionCount;
        bool isBanned;
        uint256 depositBalance;
    }

    struct Notification {
        uint256 id;
        string message;
        address sender;
        uint256 validationCount;
        uint256 rejectionCount;
        uint256 creationTime;
        NotificationStatus status;
        NotificationCategory category;
        mapping(address => bool) validators;
        mapping(address => bool) rejectors;
    }

    uint256 public constant REQUIRED_VALIDATIONS = 5;
    uint256 public constant REQUIRED_REJECTIONS = 3;
    uint256 public constant COOLDOWN_PERIOD = 1 hours;
    uint256 public constant NOTIFICATION_LIFETIME = 7 days;
    uint256 public constant BAN_DURATION = 3 days;

    uint256 public notificationDeposit = 1 ether;

    uint256 public constant BRONZE_REWARD = 5;
    uint256 public constant SILVER_REWARD = 8;
    uint256 public constant GOLD_REWARD = 12;
    uint256 public constant PLATINUM_REWARD = 20;

    uint256 public silverThreshold = 100;
    uint256 public goldThreshold = 500;
    uint256 public platinumThreshold = 2000;

    Notification[] public notifications;
    mapping(address => User) public users;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public banExpiry;
    address[] public leaderboard;

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

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setNotificationDeposit(uint256 _newDeposit) external onlyOwner {
        require(_newDeposit > 0, "Deposit amount must be positive");
        notificationDeposit = _newDeposit;
        emit DepositAmountChanged(_newDeposit);
    }

    function getCurrentDepositRequirement() external view returns (uint256) {
        return notificationDeposit;
    }

    function sendNotification(string memory _message, NotificationCategory _category) external payable {
        User storage user = users[msg.sender];
        require(!user.isBanned, "You are currently banned");
        require(block.timestamp >= user.lastNotificationTime + COOLDOWN_PERIOD, "Cooldown period not passed");
        require(msg.value >= notificationDeposit, "Insufficient deposit");

        if (msg.value > notificationDeposit) {
            payable(msg.sender).transfer(msg.value - notificationDeposit);
        }

        uint256 id = notifications.length;
        Notification storage newNotification = notifications.push();
        newNotification.id = id;
        newNotification.message = _message;
        newNotification.sender = msg.sender;
        newNotification.creationTime = block.timestamp;
        newNotification.status = NotificationStatus.PENDING;
        newNotification.category = _category;

        user.lastNotificationTime = block.timestamp;
        user.notificationsSent++;
        user.depositBalance += notificationDeposit;

        emit NotificationSent(id, msg.sender, _message, _category);
    }

    function validateNotification(uint256 _id) external {
        require(_id < notifications.length, "Invalid ID");
        Notification storage notification = notifications[_id];

        require(block.timestamp <= notification.creationTime + NOTIFICATION_LIFETIME, "Expired");
        require(!notification.validators[msg.sender], "Already validated");
        require(!notification.rejectors[msg.sender], "Already rejected");
        require(msg.sender != notification.sender, "Can't validate own");

        notification.validators[msg.sender] = true;
        notification.validationCount++;

        User storage validator = users[msg.sender];
        validator.notificationsValidated++;
        validator.points += 1;
        _updateUserLevel(msg.sender);

        emit NotificationValidated(_id, msg.sender);

        if (notification.validationCount >= REQUIRED_VALIDATIONS) {
            _processSuccessfulValidation(_id);
        }
    }

    function _processSuccessfulValidation(uint256 _id) private {
        Notification storage notification = notifications[_id];
        notification.status = NotificationStatus.VALIDATED;

        User storage sender = users[notification.sender];
        uint256 reward = _getRewardForLevel(sender.level);

        balances[notification.sender] += reward;
        sender.points += reward * 2;

        sender.depositBalance -= notificationDeposit;
        payable(notification.sender).transfer(notificationDeposit);
        emit DepositRefunded(notification.sender, notificationDeposit);

        _updateUserLevel(notification.sender);
        emit RewardSent(_id, notification.sender, reward, sender.level);
    }

    function rejectNotification(uint256 _id) external {
        require(_id < notifications.length, "Invalid ID");
        Notification storage notification = notifications[_id];

        require(block.timestamp <= notification.creationTime + NOTIFICATION_LIFETIME, "Expired");
        require(!notification.validators[msg.sender], "Already validated");
        require(!notification.rejectors[msg.sender], "Already rejected");
        require(msg.sender != notification.sender, "Can't reject own");

        notification.rejectors[msg.sender] = true;
        notification.rejectionCount++;

        emit NotificationRejected(_id, msg.sender);

        if (notification.rejectionCount >= REQUIRED_REJECTIONS) {
            _processFailedNotification(_id);
        }
    }

    function _processFailedNotification(uint256 _id) private {
        Notification storage notification = notifications[_id];
        notification.status = NotificationStatus.REJECTED;

        User storage sender = users[notification.sender];
        sender.rejectionCount++;

        if (sender.rejectionCount >= 3) {
            sender.isBanned = true;
            banExpiry[notification.sender] = block.timestamp + BAN_DURATION;
            emit UserBanned(notification.sender, banExpiry[notification.sender]);
        }

        sender.depositBalance -= notificationDeposit;
        emit DepositCollected(notification.sender, notificationDeposit);
    }

    function checkAndUnban() external {
        require(users[msg.sender].isBanned, "Not banned");
        require(block.timestamp >= banExpiry[msg.sender], "Ban not expired");

        users[msg.sender].isBanned = false;
        users[msg.sender].rejectionCount = 0;
        emit UserUnbanned(msg.sender);
    }

    function purchaseTicket(string memory _ticketType) external {
        uint256 price = _getTicketPrice(_ticketType);
        require(balances[msg.sender] >= price, "Insufficient balance");
        balances[msg.sender] -= price;

        emit TicketPurchased(msg.sender, price, _ticketType);
    }

    function _getTicketPrice(string memory _ticketType) private pure returns (uint256) {
        if (keccak256(bytes(_ticketType)) == keccak256(bytes("standard"))) return 10;
        if (keccak256(bytes(_ticketType)) == keccak256(bytes("student"))) return 7;
        if (keccak256(bytes(_ticketType)) == keccak256(bytes("monthly"))) return 50;
        revert("Invalid ticket type");
    }

    function _getRewardForLevel(UserLevel _level) private pure returns (uint256) {
        if (_level == UserLevel.PLATINUM) return PLATINUM_REWARD;
        if (_level == UserLevel.GOLD) return GOLD_REWARD;
        if (_level == UserLevel.SILVER) return SILVER_REWARD;
        return BRONZE_REWARD;
    }

    function _updateUserLevel(address _user) private {
        User storage user = users[_user];
        UserLevel newLevel = _calculateLevel(user.points);

        if (newLevel != user.level) {
            user.level = newLevel;
            emit UserLevelUpgraded(_user, newLevel);
        }

        bool found = false;
        for (uint i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i] == _user) {
                found = true;
                break;
            }
        }
        if (!found) leaderboard.push(_user);
    }

    function _calculateLevel(uint256 _points) private view returns (UserLevel) {
        if (_points >= platinumThreshold) return UserLevel.PLATINUM;
        if (_points >= goldThreshold) return UserLevel.GOLD;
        if (_points >= silverThreshold) return UserLevel.SILVER;
        return UserLevel.BRONZE;
    }

    function getUserBasicStats(address _user) public view returns (
        uint256 points,
        UserLevel level,
        uint256 sent,
        uint256 validated
    ) {
        User memory user = users[_user];
        return (user.points, user.level, user.notificationsSent, user.notificationsValidated);
    }

    function getUserBanStatus(address _user) public view returns (
        bool isBanned,
        uint256 expiryTime
    ) {
        return (users[_user].isBanned, banExpiry[_user]);
    }

    function getUserBalance(address _user) public view returns (uint256) {
        return balances[_user];
    }

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

    function getLeaderboard() public view returns (address[] memory) {
        return leaderboard;
    }

    function setTierThresholds(uint256 _silver, uint256 _gold, uint256 _platinum) external onlyOwner {
        require(_silver < _gold && _gold < _platinum, "Invalid thresholds");
        silverThreshold = _silver;
        goldThreshold = _gold;
        platinumThreshold = _platinum;
        emit ThresholdsUpdated(_silver, _gold, _platinum);
    }

    function fundContract() external payable onlyOwner {}

    function withdrawFunds(uint256 _amount) external onlyOwner {
        payable(owner).transfer(_amount);
    }
}
