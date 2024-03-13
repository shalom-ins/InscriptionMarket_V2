const {
	loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Market", function () {
	let market, invt;

    let owner, user1, user2, user3, feeReceiver;

    const zeroAddress = "0x0000000000000000000000000000000000000000"
    
	/* --------- constructor args --------- */
    const marketName = "ins.evm market";
    const marketVersion = "v1.0.0";

    const ItemType = {
        NATIVE: 0,
        ERC20: 1,
        ERC721: 2,
        ERC1155: 3
    }

    beforeEach(async function () {
        [owner, user1, user2, user3, feeReceiver] = await hre.ethers.getSigners();

        // deploy
        const maxSupply = 3000;
        const mintLimit = 1000;
        const INVT = await ethers.getContractFactory("INS20Innovator");
        invt = await INVT.deploy(maxSupply, mintLimit, owner.address);

        const Market = await ethers.getContractFactory("InscriptionMarket_v2");
        market = await hre.upgrades.deployProxy(
			Market, [marketName, marketVersion],
			{ initializer: 'initialize' });
		await market.deployed();
    });

    describe("fulfillOrder test", async function () {
		/* 
		- The consideration must be fulfilled
		*/
	})

})