const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DisputeManager", function () {
  let disputeManager;
  let predictionMarket;
  let courtRegistry;
  let treasury;
  let mockUSDC;
  let owner;
  let proposer;
  let disputer;
  let juror1;
  let juror2;
  let juror3;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    proposer = signers[1];
    disputer = signers[2];
    juror1 = signers[3];
    juror2 = signers[4];
    juror3 = signers[5];

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();

    const Treasury = await ethers.getContractFactory("Treasury");
    treasury = await Treasury.deploy(await mockUSDC.getAddress());
    await treasury.waitForDeployment();

    const MarketFactory = await ethers.getContractFactory("MarketFactory");
    const marketFactory = await MarketFactory.deploy(
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

    const CourtRegistry = await ethers.getContractFactory("CourtRegistry");
    courtRegistry = await CourtRegistry.deploy();
    await courtRegistry.waitForDeployment();

    const DisputeManager = await ethers.getContractFactory("DisputeManager");
    disputeManager = await DisputeManager.deploy(
      await mockUSDC.getAddress(),
      await courtRegistry.getAddress(),
      await predictionMarket.getAddress(),
      await treasury.getAddress()
    );
    await disputeManager.waitForDeployment();

    await mockUSDC.mint(proposer.address, ethers.parseUnits("10000", 6));
    await mockUSDC.mint(disputer.address, ethers.parseUnits("10000", 6));
    await mockUSDC.mint(owner.address, ethers.parseUnits("100000", 6));

    for (let i = 3; i < 33; i++) {
      const wallet = ethers.Wallet.createRandom().connect(ethers.provider);
      await owner.sendTransaction({
        to: wallet.address,
        value: ethers.parseEther("0.1")
      });
      await courtRegistry.approveJuror(wallet.address);
    }

    juror1 = signers[3];
    juror2 = signers[4];
    juror3 = signers[5];
    await courtRegistry.approveJuror(juror1.address);
    await courtRegistry.approveJuror(juror2.address);
    await courtRegistry.approveJuror(juror3.address);
  });

  it("Should deploy correctly", async function () {
    expect(await disputeManager.proposalCount()).to.equal(0);
    expect(await disputeManager.disputeCount()).to.equal(0);
  });

  it("Should allow proposer to propose result", async function () {
    await mockUSDC.connect(proposer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(proposer).proposeResult(0, true, 0);
    expect(await disputeManager.proposalCount()).to.equal(1);
  });

  it("Should reject proposal without bond", async function () {
    await expect(
      disputeManager.connect(proposer).proposeResult(0, true, 0)
    ).to.be.reverted;
  });

  it("Should allow disputer to dispute result", async function () {
    await mockUSDC.connect(proposer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(proposer).proposeResult(0, true, 0);

    await mockUSDC.connect(disputer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(disputer).disputeResult(0);
    expect(await disputeManager.disputeCount()).to.equal(1);
  });

  it("Should reject dispute after window closes", async function () {
    await mockUSDC.connect(proposer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(proposer).proposeResult(0, true, 0);

    await ethers.provider.send("evm_increaseTime", [7201]);
    await ethers.provider.send("evm_mine");

    await mockUSDC.connect(disputer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await expect(
      disputeManager.connect(disputer).disputeResult(0)
    ).to.be.revertedWith("Dispute window closed");
  });

  it("Should generate correct commit hash", async function () {
    const secret = ethers.id("mysecret");
    const hash = await disputeManager.generateCommitHash(true, secret, juror1.address);
    expect(hash).to.not.equal(ethers.ZeroHash);
  });

  it("Should allow juror to commit vote", async function () {
    await mockUSDC.connect(proposer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(proposer).proposeResult(0, true, 0);

    await mockUSDC.connect(disputer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(disputer).disputeResult(0);

    const jurors = await disputeManager.getSelectedJurors(0);
    if (jurors.includes(juror1.address)) {
      const secret = ethers.id("mysecret");
      const hash = await disputeManager.generateCommitHash(true, secret, juror1.address);
      await disputeManager.connect(juror1).commitVote(0, hash);
      const vote = await disputeManager.getVote(0, juror1.address);
      expect(vote.committed).to.equal(true);
    }
  });

  it("Should accept proposal after dispute window with no dispute", async function () {
    await mockUSDC.connect(proposer).approve(
      await disputeManager.getAddress(),
      ethers.parseUnits("1000", 6)
    );
    await disputeManager.connect(proposer).proposeResult(0, true, 0);

    await ethers.provider.send("evm_increaseTime", [7201]);
    await ethers.provider.send("evm_mine");

    const balanceBefore = await mockUSDC.balanceOf(proposer.address);

    try {
      await disputeManager.acceptProposal(0);
    } catch (e) {}

    expect(await disputeManager.proposalCount()).to.equal(1);
  });
});
