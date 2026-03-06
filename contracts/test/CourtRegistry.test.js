const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CourtRegistry", function () {
  let courtRegistry;
  let owner;
  let juror1;
  let juror2;
  let randomUser;

  beforeEach(async function () {
    [owner, juror1, juror2, randomUser] = await ethers.getSigners();

    const CourtRegistry = await ethers.getContractFactory("CourtRegistry");
    courtRegistry = await CourtRegistry.deploy();
    await courtRegistry.waitForDeployment();
  });

  it("Should deploy correctly", async function () {
    expect(await courtRegistry.totalJurors()).to.equal(0);
    expect(await courtRegistry.MAX_JURORS()).to.equal(100);
  });

  it("Should approve a juror", async function () {
    await courtRegistry.approveJuror(juror1.address);
    expect(await courtRegistry.isRegistered(juror1.address)).to.equal(true);
    expect(await courtRegistry.totalJurors()).to.equal(1);
  });

  it("Should reject approving same juror twice", async function () {
    await courtRegistry.approveJuror(juror1.address);
    await expect(
      courtRegistry.approveJuror(juror1.address)
    ).to.be.revertedWith("Already registered");
  });

  it("Should warn a juror", async function () {
    await courtRegistry.approveJuror(juror1.address);
    await courtRegistry.warnJuror(juror1.address);
    const juror = await courtRegistry.getJuror(juror1.address);
    expect(juror.status).to.equal(1);
  });

  it("Should remove a juror", async function () {
    await courtRegistry.approveJuror(juror1.address);
    await courtRegistry.removeJuror(juror1.address);
    const juror = await courtRegistry.getJuror(juror1.address);
    expect(juror.status).to.equal(2);
    expect(await courtRegistry.totalJurors()).to.equal(0);
  });

  it("Should return active jurors only", async function () {
    await courtRegistry.approveJuror(juror1.address);
    await courtRegistry.approveJuror(juror2.address);
    await courtRegistry.removeJuror(juror2.address);
    const activeJurors = await courtRegistry.getActiveJurors();
    expect(activeJurors.length).to.equal(1);
    expect(activeJurors[0]).to.equal(juror1.address);
  });

  it("Should update juror stats correctly", async function () {
    await courtRegistry.approveJuror(juror1.address);
    await courtRegistry.updateJurorStats(juror1.address, true, 100);
    const juror = await courtRegistry.getJuror(juror1.address);
    expect(juror.totalVotes).to.equal(1);
    expect(juror.majorityVotes).to.equal(1);
    expect(juror.totalEarnings).to.equal(100);
  });

  it("Should reject non owner from approving juror", async function () {
    await expect(
      courtRegistry.connect(randomUser).approveJuror(juror1.address)
    ).to.be.revertedWithCustomError(courtRegistry, "OwnableUnauthorizedAccount");
  });

  it("Should correctly identify active juror", async function () {
    await courtRegistry.approveJuror(juror1.address);
    expect(await courtRegistry.isActiveJuror(juror1.address)).to.equal(true);
    await courtRegistry.removeJuror(juror1.address);
    expect(await courtRegistry.isActiveJuror(juror1.address)).to.equal(false);
  });
});
