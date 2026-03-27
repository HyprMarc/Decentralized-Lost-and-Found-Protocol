import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Seiji Protocol Escrow & Slashing", function () {
  let Seiji, seiji, owner, finder, treasury, daoArbitrator;
  const stakeAmount = ethers.parseEther("0.01");
  const rewardAmount = ethers.parseEther("0.1");

  beforeEach(async function () {
    [owner, finder, treasury, daoArbitrator] = await ethers.getSigners();
    Seiji = await ethers.getContractFactory("Seiji");
    seiji = await Seiji.deploy(treasury.address, daoArbitrator.address);
  });

  it("Should successfully execute the Happy Path (Item Returned)", async function () {
    await seiji
      .connect(owner)
      .registerItem("Wallet", ethers.encodeBytes32String("Desc"), "w21z7", {
        value: rewardAmount,
      });
    await seiji
      .connect(finder)
      .reportFound(
        0,
        ethers.encodeBytes32String("Loc"),
        ethers.toUtf8Bytes("ZK"),
        { value: stakeAmount },
      );
    await seiji.connect(owner).confirmReturn(0);
    const item = await seiji.items(0);
    expect(item.status).to.equal(2);
  });

  it("Should allow the DAO to slash a lying finder", async function () {
    await seiji
      .connect(owner)
      .registerItem("Wallet", ethers.encodeBytes32String("Desc"), "w21z7", {
        value: rewardAmount,
      });
    await seiji
      .connect(finder)
      .reportFound(
        0,
        ethers.encodeBytes32String("Loc"),
        ethers.toUtf8Bytes("ZK"),
        { value: stakeAmount },
      );
    await seiji.connect(owner).raiseDispute(0);
    await seiji.connect(daoArbitrator).resolveDispute(0, false);
    expect(await seiji.treasuryBalance()).to.equal(stakeAmount);
  });
});
