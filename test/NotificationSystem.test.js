const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NotificationSystem", function () {
  let NotificationSystem, notif, owner, addr1, addr2, addr3, addr4, addr5;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();
    NotificationSystem = await ethers.getContractFactory("NotificationSystem");
    notif = await NotificationSystem.deploy();
  });

  describe("Deployment", function () {
    it("should set the deployer as the owner", async function () {
      console.log("Checking contract owner...");
      expect(await notif.owner()).to.equal(owner.address);
      console.log("✓ Owner correctly set to deployer");
    });

    it("should initialize with default deposit amount", async function () {
      console.log("Checking default deposit amount...");
      const deposit = await notif.getCurrentDepositRequirement();
      expect(deposit).to.equal(ethers.parseEther("1"));
      console.log("✓ Default deposit amount set to 1 ETH");
    });
  });

  describe("Notification Functionality", function () {
    it("should allow user to send notification with sufficient deposit", async function () {
      console.log("Testing notification sending...");
      const deposit = await notif.getCurrentDepositRequirement();
      
      await expect(
        notif.connect(addr1).sendNotification("Hello World", 0, { value: deposit })
      ).to.emit(notif, "NotificationSent").withArgs(0, addr1.address, "Hello World", 0);
      
      console.log("✓ Notification sent successfully");
      
      const details = await notif.getNotificationDetails(0);
      expect(details.message).to.equal("Hello World");
      expect(details.sender).to.equal(addr1.address);
      console.log("✓ Notification details stored correctly");
    });

    it("should reject notification with insufficient deposit", async function () {
      console.log("Testing insufficient deposit...");
      const insufficientDeposit = ethers.parseEther("0.5");
      
      await expect(
        notif.connect(addr1).sendNotification("Test", 0, { value: insufficientDeposit })
      ).to.be.revertedWith("Insufficient deposit");
      
      console.log("✓ Reverted correctly with insufficient deposit");
    });

    it("should enforce cooldown period between notifications", async function () {
      console.log("Testing cooldown enforcement...");
      const deposit = await notif.getCurrentDepositRequirement();
      
      await notif.connect(addr1).sendNotification("First", 0, { value: deposit });
      
      await expect(
        notif.connect(addr1).sendNotification("Second", 0, { value: deposit })
      ).to.be.revertedWith("Cooldown period not passed");
      
      console.log("✓ Cooldown period enforced correctly");
    });
  });

  describe("Validation System", function () {
    beforeEach(async function () {
      const deposit = await notif.getCurrentDepositRequirement();
      await notif.connect(addr1).sendNotification("Test validation", 0, { value: deposit });
    });

    it("should allow users to validate notifications", async function () {
      console.log("Testing notification validation...");
      
      await expect(notif.connect(addr2).validateNotification(0))
        .to.emit(notif, "NotificationValidated")
        .withArgs(0, addr2.address);
      
      const details = await notif.getNotificationDetails(0);
      expect(details.validationCount).to.equal(1);
      console.log("✓ Validation recorded correctly");
      
      const [points] = await notif.getUserBasicStats(addr2.address);
      expect(points).to.equal(1);
      console.log("✓ Validator received points");
    });

    it("should prevent self-validation", async function () {
      console.log("Testing self-validation prevention...");
      
      await expect(
        notif.connect(addr1).validateNotification(0)
      ).to.be.revertedWith("Can't validate own");
      
      console.log("✓ Self-validation prevented");
    });

    it("should prevent duplicate validation", async function () {
      console.log("Testing duplicate validation...");
      
      await notif.connect(addr2).validateNotification(0);
      
      await expect(
        notif.connect(addr2).validateNotification(0)
      ).to.be.revertedWith("Already validated");
      
      console.log("✓ Duplicate validation prevented");
    });

    it("should process successful validation when threshold reached", async function () {
      console.log("Testing validation threshold...");
      
      await notif.connect(addr2).validateNotification(0);
      await notif.connect(addr3).validateNotification(0);
      await notif.connect(addr4).validateNotification(0);
      await notif.connect(addr5).validateNotification(0);
      
      await expect(notif.connect(owner).validateNotification(0))
        .to.emit(notif, "RewardSent");
      
      const details = await notif.getNotificationDetails(0);
      expect(details.status).to.equal(1); // VALIDATED
      console.log("✓ Notification marked as validated");
      
      const [points] = await notif.getUserBasicStats(addr1.address);
      expect(points).to.be.gt(0);
      console.log("✓ Sender received reward points");
    });
  });

  describe("Rejection System", function () {
    beforeEach(async function () {
      const deposit = await notif.getCurrentDepositRequirement();
      await notif.connect(addr1).sendNotification("Test rejection", 0, { value: deposit });
    });

    it("should allow users to reject notifications", async function () {
      console.log("Testing notification rejection...");
      
      await expect(notif.connect(addr2).rejectNotification(0))
        .to.emit(notif, "NotificationRejected")
        .withArgs(0, addr2.address);
      
      const details = await notif.getNotificationDetails(0);
      expect(details.rejectionCount).to.equal(1);
      console.log("✓ Rejection recorded correctly");
    });

    it("should process failed notification when threshold reached", async function () {
      console.log("Testing rejection threshold...");
      
      await notif.connect(addr2).rejectNotification(0);
      await notif.connect(addr3).rejectNotification(0);
      
      await expect(notif.connect(addr4).rejectNotification(0))
        .to.emit(notif, "DepositCollected");
      
      const details = await notif.getNotificationDetails(0);
      expect(details.status).to.equal(2); // REJECTED
      console.log("✓ Notification marked as rejected");
      
      const user = await notif.users(addr1.address);
      expect(user.rejectionCount).to.equal(1);
      console.log("✓ Sender rejection count incremented");
    });

    it("should ban user after 3 rejected notifications", async function () {
      console.log("Testing user banning...");
      
      const deposit = await notif.getCurrentDepositRequirement();
      
      for (let i = 0; i < 3; i++) {
        await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
        await ethers.provider.send("evm_mine");
        
        await notif.connect(addr1).sendNotification(`Spam ${i}`, 0, { value: deposit });
        await notif.connect(addr2).rejectNotification(i);
        await notif.connect(addr3).rejectNotification(i);
        await notif.connect(addr4).rejectNotification(i);
      }
      
      const [isBanned] = await notif.getUserBanStatus(addr1.address);
      expect(isBanned).to.be.true;
      console.log("✓ User correctly banned after 3 rejections");
      
      await expect(
        notif.connect(addr1).sendNotification("Banned attempt", 0, { value: deposit })
      ).to.be.revertedWith("You are currently banned");
      console.log("✓ Banned user prevented from sending notifications");
    });
  });

  describe("User Level System", function () {
    it("should upgrade user level based on points", async function () {
      console.log("Testing user level upgrades...");
      
      const silver = await notif.silverThreshold();
      const gold = await notif.goldThreshold();
      const platinum = await notif.platinumThreshold();
      
      const deposit = await notif.getCurrentDepositRequirement();
      const notificationsNeeded = Math.ceil(Number(platinum) / 10); // Approximate
      
      for (let i = 0; i < notificationsNeeded; i++) {
        await ethers.provider.send("evm_increaseTime", [3600]);
        await ethers.provider.send("evm_mine");
        
        await notif.connect(addr1).sendNotification(`Level up ${i}`, 0, { value: deposit });
        
        await notif.connect(addr2).validateNotification(i);
        await notif.connect(addr3).validateNotification(i);
        await notif.connect(addr4).validateNotification(i);
        await notif.connect(addr5).validateNotification(i);
        await notif.connect(owner).validateNotification(i);
      }
      
      const [, level] = await notif.getUserBasicStats(addr1.address);
      expect(level).to.equal(3); // PLATINUM
      console.log("✓ User reached PLATINUM level");
    });
  });

  describe("Owner Functions", function () {
    it("should allow owner to change deposit amount", async function () {
      console.log("Testing deposit amount change...");
      
      const newDeposit = ethers.parseEther("0.5");
      await notif.setNotificationDeposit(newDeposit);
      
      expect(await notif.getCurrentDepositRequirement()).to.equal(newDeposit);
      console.log("✓ Deposit amount changed successfully");
    });

    it("should prevent non-owners from changing deposit", async function () {
      console.log("Testing deposit change permission...");
      
      await expect(
        notif.connect(addr1).setNotificationDeposit(ethers.parseEther("0.5"))
      ).to.be.revertedWith("Only owner can call this");
      
      console.log("✓ Non-owner prevented from changing deposit");
    });

    it("should allow owner to change tier thresholds", async function () {
      console.log("Testing tier threshold changes...");
      
      await notif.setTierThresholds(50, 250, 1000);
      
      expect(await notif.silverThreshold()).to.equal(50);
      expect(await notif.goldThreshold()).to.equal(250);
      expect(await notif.platinumThreshold()).to.equal(1000);
      console.log("✓ Tier thresholds updated successfully");
    });
  });
});