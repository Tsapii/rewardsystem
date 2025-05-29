# Notification System

## Overview
This smart contract implements a notification validation and reward system on the Ethereum blockchain. Users send notifications with a deposit, which others validate or reject. Based on community feedback, rewards or sanctions are applied to the sender.

---

## Main Features 
---
### 1. Community-driven notification validation  
Users submit notifications which other community members validate or reject. This decentralized process ensures quality and relevance by leveraging collective judgment rather than relying on a central authority.

### 2. User tiers: Bronze, Silver, Gold, Platinum  
Users are ranked into tiers based on their accumulated points. Each tier unlocks higher rewards and recognition:  
- **Bronze**: Default starting level  
- **Silver**: Achieved after earning enough points (e.g., 100+)  
- **Gold**: Higher tier for experienced users (e.g., 500+ points)  
- **Platinum**: Elite users with the highest reputation (e.g., 2000+ points)  

### 3. Points and reputation system  
Users earn points by sending notifications and validating others’ notifications. Points increase reputation, unlocking higher tiers and greater rewards. Points reflect a user’s trustworthiness and contribution to the community.

### 4. Deposit refund or forfeiture based on validation  
To send a notification, users must pay a deposit (e.g., 1 ether). If the notification is validated by enough community members, the deposit is refunded plus rewards. If rejected, the deposit is forfeited, discouraging spam and low-quality content.

### 5. Cooldown between sends and ban system  
Users must wait a cooldown period (e.g., 1 hour) between sending notifications to prevent flooding. Repeated invalid notifications lead to bans for a defined duration (e.g., 3 days), limiting misuse.

### 6. Ticket purchases using accrued balance  
Users earn rewards that accumulate as a balance in the contract. This balance can be spent to purchase different types of tickets (standard, student, monthly), enabling access to premium features or events.

### 7. Leaderboard showing top users  
A leaderboard ranks users by their points or reputation, promoting competition and motivation. The top contributors gain visibility and status within the community.

### 8. Notification categories (event, warning, error)  
Notifications are categorized to better organize and filter content:  
- **Event**: Informational messages about occurrences  
- **Warning**: Alerts about potential issues or risks  
- **Error**: Reports of actual problems or failures  

This classification improves user experience and helps validators understand the context.


---

## Constants

| Name                  | Value                      | Description                              |
|-----------------------|----------------------------|------------------------------------------|
| `REQUIRED_VALIDATIONS` | 5                          | Number of validations needed              |
| `REQUIRED_REJECTIONS`  | 3                          | Number of rejections for invalidation    |
| `COOLDOWN_PERIOD`      | 1 hour                     | Required wait time between sends          |
| `NOTIFICATION_LIFETIME`| 7 days                     | Notification validity duration            |
| `BAN_DURATION`         | 3 days                     | Duration of user ban                      |
| `notificationDeposit`  | 1 ether (adjustable)       | Deposit required to send a notification   |

---

## Tier Rewards

| Tier       | Reward Points              |
|------------|----------------------------|
| Bronze     | 5                          |
| Silver     | 8                          |
| Gold       | 12                         |
| Platinum   | 20                         |

---

## Tier Thresholds (by points)

| Tier       | Threshold                  |
|------------|----------------------------|
| Silver     | 100                        |
| Gold       | 500                        |
| Platinum   | 2000                       |

---

## Notification Structure

- `id`: Unique identifier  
- `message`: Text message  
- `sender`: Sender's address  
- `validationCount`: Number of validations  
- `rejectionCount`: Number of rejections  
- `status`: Status (PENDING, VALIDATED, REJECTED)  
- `creationTime`: Timestamp of creation  
- `validators`: Addresses of validators  
- `rejectors`: Addresses of rejectors  
- `category`: Notification type (event, warning, error)  

---

## User Structure

- `points`: User points  
- `level`: Tier (UserLevel)  
- `notificationsSent`: Number of notifications sent  
- `notificationsValidated`: Number of notifications validated  
- `rejectionCount`: Number of rejected notifications  
- `lastNotificationTime`: Last notification timestamp (cooldown)  
- `isBanned`: Ban status  
- `depositBalance`: Deposit balance  

---

## Events

| Name                  | Parameters                  | Description                              |
|-----------------------|-----------------------------|------------------------------------------|
| `NotificationSent`     | id, sender, message          | A new notification was sent               |
| `NotificationValidated`| id, validator                | A notification was validated              |
| `NotificationRejected` | id, rejector                 | A notification was rejected               |
| `RewardSent`           | id, sender, amount, tier     | Reward paid for a validated notification |
| `UserLevelUpgraded`    | user, newLevel               | User upgraded to a new tier               |
| `TicketPurchased`      | buyer, price, ticketType     | Ticket purchase occurred                   |
| `ThresholdsUpdated`    | silver, gold, platinum       | Tier thresholds updated                    |
| `UserBanned`           | user, until                  | User was banned                            |
| `UserUnbanned`         | user                        | User ban was lifted                        |
| `DepositCollected`     | user, amount                 | Deposit collected after invalid notification |
| `DepositRefunded`      | user, amount                 | Deposit refunded after successful notification |
| `DepositAmountChanged` | newAmount                   | Deposit amount changed                      |
| `LeaderboardUpdated`   | topUsers (address[])         | Leaderboard updated                        |

---

## Public Functions

- `sendNotification(string _message, string _category)` — Send a notification with a category  
- `validateNotification(uint256 _id)` — Validate a notification  
- `rejectNotification(uint256 _id)` — Reject a notification  
- `checkAndUnban()` — Remove ban if expired  
- `purchaseTicket(string _ticketType)` — Purchase tickets with points  
- `getUserBasicStats(address _user)` — Get basic user stats  
- `getUserBanStatus(address _user)` — Get user ban status  
- `getUserBalance(address _user)` — Get user balance  
- `getNotificationDetails(uint256 _id)` — Get notification details  
- `getLeaderboard()` — Get top users list  

---

## Admin Functions (onlyOwner)

- `setNotificationDeposit(uint256 _newDeposit)` — Set deposit amount  
- `setTierThresholds(uint256 silver, uint256 gold, uint256 platinum)` — Set tier thresholds  
- `fundContract()` — Fund the contract  
- `withdrawFunds(uint256 amount)` — Withdraw funds from contract  

---
