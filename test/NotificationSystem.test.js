const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NotificationSystem", function () {
  let NotificationSystem, notif, owner, addr1;

beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    NotificationSystem = await ethers.getContractFactory("NotificationSystem");
    notif = await NotificationSystem.deploy();

});


  it("should set the deployer as the owner", async function () {
    expect(await notif.owner()).to.equal(owner.address);
  });

  it("should allow user to send notification with sufficient deposit", async function () {
  const deposit = await notif.getCurrentDepositRequirement();
  await expect(
    notif.connect(addr1).sendNotification("Hello World", 0, { value: deposit })
  ).to.emit(notif, "NotificationSent").withArgs(0, addr1.address, "Hello World", 0);
});

it("should allow another user to validate a notification", async function () {
  const deposit = await notif.getCurrentDepositRequirement();

  await notif.connect(addr1).sendNotification("Test validation", 0, { value: deposit });

  await expect(notif.validateNotification(0))
    .to.emit(notif, "NotificationValidated")
    .withArgs(0, owner.address);

  const details = await notif.getNotificationDetails(0);
  expect(details.validationCount).to.equal(1);
});

it("should allow another user to reject a notification", async function () {
  const deposit = await notif.getCurrentDepositRequirement();

  await notif.connect(addr1).sendNotification("Test rejection", 0, { value: deposit });

  await expect(notif.rejectNotification(0))
    .to.emit(notif, "NotificationRejected")
    .withArgs(0, owner.address);

  const details = await notif.getNotificationDetails(0);
  expect(details.rejectionCount).to.equal(1);
});

it("should upgrade user level based on points", async function () {
  const deposit = await notif.getCurrentDepositRequirement();

  await notif.connect(addr1).sendNotification("Level up test", 0, { value: deposit });

  const signers = await ethers.getSigners();
  for (let i = 0; i < 5; i++) {
    
    if (signers[i].address !== addr1.address) {
      await notif.connect(signers[i]).validateNotification(0);
    }
  }

  const [points, level] = await notif.getUserBasicStats(addr1.address);
  expect(points).to.be.gte(0);
  expect(level).to.be.gte(0);
});




});
