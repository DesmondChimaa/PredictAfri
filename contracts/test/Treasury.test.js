const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Treasury", function () {
  let treasury;
  let mockUSDC;
  let owner;
  let user;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();

    const Treasury = await ethers.getContractFactory("Treasury");
    treasury = await Treasury.deploy(await mockUSDC.getAddress());
    await treasury.waitForDeployment();

    await mockUSDC.mint(user.address, ethers.parseUnits("10000", 6));
  });

  it("Should deploy with correct USDC address", async function () {
    expect(await treasury.usdc()).to.equal(await mockUSDC.getAddress());
  });

  it("Should receive funds correctly", async function () {
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user).approve(await treasury.getAddress(), amount);
    await treasury.connect(user).receiveFunds(amount);
    expect(await treasury.getBalance()).to.equal(amount);
  });

  it("Should track total revenue", async function () {
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user).approve(await treasury.getAddress(), amount);
    await treasury.connect(user).receiveFunds(amount);
    expect(await treasury.totalRevenue()).to.equal(amount);
  });

  it("Should allow owner to withdraw", async function () {
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user).approve(await treasury.getAddress(), amount);
    await treasury.connect(user).receiveFunds(amount);
    await treasury.withdraw(owner.address, amount);
    expect(await treasury.getBalance()).to.equal(0);
  });

  it("Should reject withdrawal from non owner", async function () {
    const amount = ethers.parseUnits("100", 6);
    await mockUSDC.connect(user).approve(await treasury.getAddress(), amount);
    await treasury.connect(user).receiveFunds(amount);
    await expect(
      treasury.connect(user).withdraw(user.address, amount)
    ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
  });

  it("Should reject zero amount deposit", async function () {
    await expect(
      treasury.connect(user).receiveFunds(0)
    ).to.be.revertedWith("Amount must be greater than zero");
  });
});