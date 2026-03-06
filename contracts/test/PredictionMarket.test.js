const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PredictionMarket", function () {
  let predictionMarket;
  let mockUSDC;
  let treasury;
  let marketFactory;
  let owner;
  let user1;
  let user2;
  let eventStartTime;
  let resolutionDeadline;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();

    const Treasury = await ethers.getContractFactory("Treasury");
    treasury = await Treasury.deploy(await mockUSDC.getAddress());
    await treasury.waitForDeployment();

    const MarketFactory = await ethers.getContractFactory("MarketFactory");
    marketFactory = await MarketFactory.deploy(
      await mockUSDC.getAddress(),
      await treasury.getAddress()
    );
    await marketFactory.waitForDeployment();

    const PredictionMarket = await ethers.getContractFactory("PredictionMarket");
    predictionMarket = await PredictionMarket.deploy(
      await mockUSDC.getAddress(),
      await treasury.getAddress(),
      await marketFactory.getAddress()
    );
    await predictionMarket.waitForDeployment();

    await mockUSDC.mint(owner.address, ethers.parseUnits("100000", 6));
    await mockUSDC.mint(user1.address, ethers.parseUnits("10000", 6));
    await mockUSDC.mint(user2.address, ethers.parseUnits("10000", 6));

    const block = await ethers.provider.getBlock("latest");
    eventStartTime = block.timestamp + 3600;
    resolutionDeadline = block.timestamp + 7200;
  });

  async function createMarket() {
    const liquidity = ethers.parseUnits("1000", 6);
    await mockUSDC.approve(await predictionMarket.getAddress(), liquidity);
    await predictionMarket.createMarket(
      "Will Man Utd beat Chelsea?",
      "Sports",
      "EPL",
      eventStartTime,
      resolutionDeadline,
      liquidity
    );
  }

  it("Should create a market correctly", async function () {
    await createMarket();
    const market = await predictionMarket.getMarket(0);
    expect(market.question).to.equal("Will Man Utd beat Chelsea?");
    expect(market.state).to.equal(0);
  });

  it("Should set initial liquidity correctly", async function () {
    await createMarket();
    const market = await predictionMarket.getMarket(0);
    expect(market.yesPool).to.equal(ethers.parseUnits("500", 6));
    expect(market.noPool).to.equal(ethers.parseUnits("500", 6));
  });

  it("Should allow user to buy YES shares", async function () {
    await createMarket();
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user1).buyShares(0, true, amount);
    const position = await predictionMarket.getPosition(0, user1.address);
    expect(position.yesShares).to.be.gt(0);
  });

  it("Should allow user to buy NO shares", async function () {
    await createMarket();
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user1).buyShares(0, false, amount);
    const position = await predictionMarket.getPosition(0, user1.address);
    expect(position.noShares).to.be.gt(0);
  });

  it("Should calculate payout correctly", async function () {
    await createMarket();
    const amount = ethers.parseUnits("100", 6);
    const [shares, payout] = await predictionMarket.calculatePayout(0, true, amount);
    expect(shares).to.be.gt(0);
    expect(payout).to.be.gt(0);
  });

  it("Should show YES + NO price above 100", async function () {
    await createMarket();
    const yesPrice = await predictionMarket.getYesPrice(0);
    const noPrice = await predictionMarket.getNoPrice(0);
    expect(yesPrice + noPrice).to.be.gte(102n);
  });

  it("Should reject buying shares after event starts", async function () {
    await createMarket();
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine");
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await expect(
      predictionMarket.connect(user1).buyShares(0, true, amount)
    ).to.be.revertedWith("Event already started");
  });

  it("Should allow cashout before deadline", async function () {
    await createMarket();
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user1).buyShares(0, true, amount);
    const balanceBefore = await mockUSDC.balanceOf(user1.address);
    await predictionMarket.connect(user1).cashout(0, true);
    const balanceAfter = await mockUSDC.balanceOf(user1.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
  });

  it("Should apply 10% cashout fee", async function () {
    await createMarket();
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user1).buyShares(0, true, amount);
    const balanceBefore = await mockUSDC.balanceOf(user1.address);
    await predictionMarket.connect(user1).cashout(0, true);
    const balanceAfter = await mockUSDC.balanceOf(user1.address);
    const received = balanceAfter - balanceBefore;
    expect(received).to.equal(ethers.parseUnits("90", 6));
  });

 it("Should resolve market and allow winner to claim", async function () {
    await createMarket();
    const amount = ethers.parseUnits("500", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user1).buyShares(0, true, amount);
    await mockUSDC.connect(user2).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user2).buyShares(0, false, amount);

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine");

    await predictionMarket.lockMarket(0);
    await predictionMarket.proposeResult(0, true);
    await predictionMarket.resolveMarket(0);

    const balanceBefore = await mockUSDC.balanceOf(user1.address);
    await predictionMarket.connect(user1).claimWinnings(0);
    const balanceAfter = await mockUSDC.balanceOf(user1.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
});

  it("Should allow refund when market is cancelled", async function () {
    await createMarket();
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user1).approve(await predictionMarket.getAddress(), amount);
    await predictionMarket.connect(user1).buyShares(0, true, amount);
    await predictionMarket.cancelMarket(0);
    const balanceBefore = await mockUSDC.balanceOf(user1.address);
    await predictionMarket.connect(user1).claimRefund(0);
    const balanceAfter = await mockUSDC.balanceOf(user1.address);
    expect(balanceAfter - balanceBefore).to.equal(amount);
  });

  it("Should pause and unpause market", async function () {
    await createMarket();
    await predictionMarket.pauseMarket(0);
    expect((await predictionMarket.getMarket(0)).state).to.equal(1);
    await predictionMarket.unpauseMarket(0);
    expect((await predictionMarket.getMarket(0)).state).to.equal(0);
  });
});
