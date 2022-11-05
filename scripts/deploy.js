const { getAddress } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

const main = async() => {
  const BullBearFactory = await ethers.getContractFactory("BullBear");
  const bullBear = await BullBearFactory.deploy(
    900, // 15min
    getAddress("0xA39434A63A52E749F02807ae27335515BA4b07F7"), // Goerli BTC/USD
    getAddress("0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D")  // Goerli VRF Coordinator
  );

  await bullBear.deployed();
  //console.log("Bull&Bear owner address:", owner.address);
  console.log("Bull&Bear address:", bullBear.address);
}

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
  }
};

runMain();
