const hre = require("hardhat");

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

  console.log("Deploying Treasury...");
  const Treasury = await hre.ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(USDC_ADDRESS);
  await treasury.waitForDeployment();
  console.log("Treasury deployed to:", await treasury.getAddress());
  await sleep(5000);

  console.log("Deploying MarketFactory...");
  const MarketFactory = await hre.ethers.getContractFactory("MarketFactory");
  const marketFactory = await MarketFactory.deploy(USDC_ADDRESS, await treasury.getAddress());
  await marketFactory.waitForDeployment();
  console.log("MarketFactory deployed to:", await marketFactory.getAddress());
  await sleep(5000);

  console.log("Deploying PredictionMarket...");
  const PredictionMarket = await hre.ethers.getContractFactory("PredictionMarket");
  const predictionMarket = await PredictionMarket.deploy(
    USDC_ADDRESS,
    await treasury.getAddress(),
    await marketFactory.getAddress()
  );
  await predictionMarket.waitForDeployment();
  console.log("PredictionMarket deployed to:", await predictionMarket.getAddress());
  await sleep(5000);

  console.log("Deploying CourtRegistry...");
  const CourtRegistry = await hre.ethers.getContractFactory("CourtRegistry");
  const courtRegistry = await CourtRegistry.deploy();
  await courtRegistry.waitForDeployment();
  console.log("CourtRegistry deployed to:", await courtRegistry.getAddress());
  await sleep(5000);

  console.log("Deploying DisputeManager...");
  const DisputeManager = await hre.ethers.getContractFactory("DisputeManager");
  const disputeManager = await DisputeManager.deploy(
    USDC_ADDRESS,
    await courtRegistry.getAddress(),
    await predictionMarket.getAddress(),
    await treasury.getAddress()
  );
  await disputeManager.waitForDeployment();
  console.log("DisputeManager deployed to:", await disputeManager.getAddress());

  console.log("\n--- PredictAfri Deployment Complete ---");
  console.log("USDC:             ", USDC_ADDRESS);
  console.log("Treasury:         ", await treasury.getAddress());
  console.log("MarketFactory:    ", await marketFactory.getAddress());
  console.log("PredictionMarket: ", await predictionMarket.getAddress());
  console.log("CourtRegistry:    ", await courtRegistry.getAddress());
  console.log("DisputeManager:   ", await disputeManager.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
