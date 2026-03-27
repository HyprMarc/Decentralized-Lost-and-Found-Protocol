import pkg from "hardhat";
const { ethers } = pkg;

async function main() {
  // Grab the first three fake accounts from your local node
  const [deployer, treasury, dao] = await ethers.getSigners();

  console.log("Deploying Seiji Protocol...");

  const Seiji = await ethers.getContractFactory("Seiji");
  const seiji = await Seiji.deploy(treasury.address, dao.address);

  await seiji.waitForDeployment();

  console.log("✅ Seiji successfully deployed to:", await seiji.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
