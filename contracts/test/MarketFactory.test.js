const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MarketFactory", function () {
  let marketFactory;
  let mockUSDC;
  let treasury;
  let owner;
  let approvedCreator;
  let randomUser;

  beforeEach(async function () {
    [owner, approvedCreator, randomUser] = await ethers.getSigners();

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
  });

  it("Should deploy with correct addresses", async function () {
    expect(await marketFactory.usdc()).to.equal(await mockUSDC.getAddress());
    expect(await marketFactory.treasury()).to.equal(await treasury.getAddress());
  });

  it("Should approve a creator", async function () {
    await marketFactory.approveCreator(approvedCreator.address);
    expect(await marketFactory.approvedCreators(approvedCreator.address)).to.equal(true);
  });

  it("Should remove a creator", async function () {
    await marketFactory.approveCreator(approvedCreator.address);
    await marketFactory.removeCreator(approvedCreator.address);
    expect(await marketFactory.approvedCreators(approvedCreator.address)).to.equal(false);
  });

  it("Should reject approving same creator twice", async function () {
    await marketFactory.approveCreator(approvedCreator.address);
    await expect(
      marketFactory.approveCreator(approvedCreator.address)
    ).to.be.revertedWith("Already approved");
  });

  it("Should allow approved creator to register market", async function () {
    await marketFactory.approveCreator(approvedCreator.address);
    await marketFactory.connect(approvedCreator).registerMarket(
      ethers.Wallet.createRandom().address,
      "Will Man Utd beat Chelsea?"
    );
    expect(await marketFactory.getTotalMarkets()).to.equal(1);
  });

  it("Should reject unapproved creator from registering market", async function () {
    await expect(
      marketFactory.connect(randomUser).registerMarket(
        ethers.Wallet.createRandom().address,
        "Will Man Utd beat Chelsea?"
      )
    ).to.be.revertedWith("Not an approved creator");
  });

  it("Should allow owner to register market without approval", async function () {
    await marketFactory.connect(owner).registerMarket(
      ethers.Wallet.createRandom().address,
      "Will Man Utd beat Chelsea?"
    );
    expect(await marketFactory.getTotalMarkets()).to.equal(1);
  });

  it("Should return all markets", async function () {
    await marketFactory.approveCreator(approvedCreator.address);
    await marketFactory.connect(approvedCreator).registerMarket(
      ethers.Wallet.createRandom().address,
      "Will Man Utd beat Chelsea?"
    );
    await marketFactory.connect(approvedCreator).registerMarket(
      ethers.Wallet.createRandom().address,
      "Will BTC hit $120k?"
    );
    expect((await marketFactory.getAllMarkets()).length).to.equal(2);
  });
});