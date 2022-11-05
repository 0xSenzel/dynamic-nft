const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Bull&Bear Test", function () {
let owner, BullBearFactory, bullBear, MockPriceFactory, mockPrice, MockCoordinatorFactory, mockCoordinator;

    beforeEach(async () => {
        [owner, user1] = await ethers.getSigners();
        MockPriceFactory = await ethers.getContractFactory("MockV3Aggregator", owner.address);
        mockPrice = await MockPriceFactory.deploy(8, 3034715771688);
        await mockPrice.deployed();
        //console.log("MockV3Aggregator address:", mockPrice.address)

        MockCoordinatorFactory = await ethers.getContractFactory("VRFCoordinatorV2Mock", owner.address);
        mockCoordinator = await MockCoordinatorFactory.deploy(
            BigNumber.from(10), // 0.1 LINK 100000000000000000
            BigNumber.from(1) // 0.000000001 LINK per gas 1000000000
        );
        await mockCoordinator.deployed();
        //console.log("VRFCoordinatorV2Mock address:", mockCoordinator.address)

        BullBearFactory = await ethers.getContractFactory("BullBear", owner.address);
        bullBear = await BullBearFactory.deploy(
            10, // 10 second 
            mockPrice.address,
            mockCoordinator.address
            );
        await bullBear.deployed();
        //console.log("NFT contract address:", bullBear.address);
    });

    describe("Mint NFT:", function () {
        it("Should add balance of NFT for owner", async function () {
            await bullBear.safeMint(owner.address);
            expect(await bullBear.ownerOf(0)).to.equal(owner.address);
        });

        it("Should add balance of NFT to total supply", async function () {
            await bullBear.safeMint(owner.address);
            expect(await bullBear.totalSupply()).to.equal(1);
      });
    });
    
    describe("Checking TokenURI:", function (){
        it("Should mint token correctly", async () => {
            await bullBear.safeMint(owner.address);
    
            expect(await bullBear.tokenURI(0)).to.include(
                "filename=gamer_bull.json"
            );
    
            await expect(bullBear.tokenURI(1)).to.be.revertedWith(
                "ERC721: invalid token ID"
            );
        });
    });
});