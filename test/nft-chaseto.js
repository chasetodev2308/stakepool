const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFTChaseto", function () {
  it("Should init with give fee", async function () {
    const swap = await createSwap();

    expect(await swap.getFee()).to.equal(100);
  });

  it("Should change the fee", async function () {
    const swap = await createSwap();

    expect(await swap.getFee()).to.equal(100);

    await swap.changeFee(200);

    expect(await swap.getFee()).to.equal(200);
  });

  it("Should create the swap", async function () {
    const swap = await createSwap();
    const token = await getERC721();

    const [owner, addr1] = await ethers.getSigners();

    await token.mint(owner.address, 1);
    await token.approve(swap.address, 1);

    await swap.createSwap(
      addr1.address,
      [{ contractAddr: token.address, id: 1, amount: 0 }],
      { value: ethers.utils.parseEther("1.0") }
    );

    const createdSwap = await swap.getSwap(1);

    expect(createdSwap.id, 1);
    expect(createdSwap.aAddress, owner.address);
    expect(createdSwap.bAddress, addr1.address);
    expect(createdSwap.aNFTs.length, 1);
    expect(createdSwap.aNFTs[0].amount, 1);
    expect(createdSwap.aNFTs[0].contractAddr, token.address);
    expect(createdSwap.aNFTs[0].id, 1);
  });

  it("Should init and finish the swap", async function () {
    const swap = await createSwap();
    const token = await getERC721();

    const [owner, addr1] = await ethers.getSigners();

    await token.mint(owner.address, 1);
    await token.approve(swap.address, 1);

    await token.mint(addr1.address, 2);
    await token.connect(addr1).approve(swap.address, 2);

    await swap.createSwap(
      addr1.address,
      [{ contractAddr: token.address, id: 1, amount: 0 }],
      { value: ethers.utils.parseEther("1.0") }
    );

    let createdSwap = await swap.getSwap(1);

    expect(createdSwap.id, 1);

    await swap
      .connect(addr1)
      .initSwap(1, [{ contractAddr: token.address, id: 2, amount: 0 }], {
        value: ethers.utils.parseEther("2.0"),
      });

    createdSwap = await swap.getSwap(1);

    expect(createdSwap.id, 1);
    expect(createdSwap.aAddress, owner.address);
    expect(createdSwap.bAddress, addr1.address);
    expect(createdSwap.aNFTs.length, 1);
    expect(createdSwap.aNFTs[0].amount, 1);
    expect(createdSwap.aNFTs[0].contractAddr, token.address);
    expect(createdSwap.aNFTs[0].id, 1);
    expect(createdSwap.bNFTs.length, 1);
    expect(createdSwap.bNFTs[0].amount, 1);
    expect(createdSwap.bNFTs[0].contractAddr, token.address);
    expect(createdSwap.bNFTs[0].id, 2);

    await swap.finishSwap(1);

    createdSwap = await swap.getSwap(1);

    expect(createdSwap.id, 0);
    expect(createdSwap.aAddress, "0x0000000000000000000000000000000000000000");
    expect(createdSwap.bAddress, "0x0000000000000000000000000000000000000000");
  });

  it("Should finish the swap", async function () {
    const swap = await createSwap();
    const token = await getERC721();

    const [owner, addr1] = await ethers.getSigners();

    await token.mint(owner.address, 1);
    await token.approve(swap.address, 1);

    await swap.createSwap(
      addr1.address,
      [{ contractAddr: token.address, id: 1, amount: 0 }],
      { value: ethers.utils.parseEther("1.0") }
    );

    let createdSwap = await swap.getSwap(1);

    await swap.cancelSwap(1);

    createdSwap = await swap.getSwap(1);

    expect(createdSwap.id, 0);
    expect(createdSwap.aAddress, "0x0000000000000000000000000000000000000000");
    expect(createdSwap.bAddress, "0x0000000000000000000000000000000000000000");
  });
});

async function createSwap() {
  const Swap = await ethers.getContractFactory("NFTChaseto");
  const swap = await Swap.deploy(100);
  await swap.deployed();

  return swap;
}

async function getERC721() {
  const ERC721 = await ethers.getContractFactory("TestERC721");
  const token = await ERC721.deploy();
  await token.deployed();

  return token;
}
