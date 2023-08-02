//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract NFTChaseto is Ownable, ERC721Holder, ERC1155Holder {
  uint256 private _fee;
  uint256 private _ethLocked;

  // global swaps storage, id => swap
  uint256 private _swapIdx;
  mapping (uint256 => Swap) private _swaps;

  // NFT info, the contract address and NFT id
  struct NFT {
    address contractAddr;
    uint256 id;
    uint256 amount; // used for ERC-1155
  }

  // Both users are allowed to use NTFs and ETHs in the swap
  // Here we assume that user A is the one who create the swap
  struct Swap {
    // User A's swap information
    address payable aAddress;
    NFT[] aNFTs;
    uint256 aEth;

    // User B's swap information
    address payable bAddress;
    NFT[] bNFTs;
    uint256 bEth;
  }

  event FeeChange(uint256 fee);
  // SwapCreate will be emitted when user A create a swap
  event SwapCreate(
    address indexed a,
    address indexed b,
    uint256 indexed id,
    NFT[] aNFTs,
    uint256 aEth
  );
  // SwapReady will be emitted when user B finish selecting his/her NFTs and ETHs to swap
  event SwapReady(
    address indexed a,
    address indexed b,
    uint256 indexed id,
    NFT[] aNFTs,
    uint256 aEth,
    NFT[] bNFTs,
    uint256 bEth
  );
  // SwapCancel will be emitted when either side cancel the swap
  event SwapCancel(
    address indexed a,
    address indexed b,
    uint256 indexed id
  );
  // SwapDone will be emitted when the swap is finished
  event SwapDone(
    address indexed a,
    address indexed b,
    uint256 indexed id
  );

  modifier onlyA(uint256 swapId) {
    require(_swaps[swapId].aAddress == msg.sender, "onlySwapCreatorCanCall");
    _;
  }

  modifier onlyAorB(uint256 swapId) {
    require(
      _swaps[swapId].aAddress == msg.sender ||
      _swaps[swapId].bAddress == msg.sender,
      "onlySwapCreatorCanCall"
    );
    _;
  }

  modifier chargeFee() {
    require(msg.value >= _fee, "feeNotGiven");
    _;
  }

  constructor(uint128 fee) {
    _fee = fee;
    super.transferOwnership(msg.sender);
  }

  function getFee() external view returns(uint256) {
    return _fee;
  }

  // Change the contract service fee
  function changeFee(uint128 fee) external onlyOwner {
    _fee = fee;
    emit FeeChange(_fee);
  }

  // Get swap by id, only by user A or B
  function getSwap(uint128 id) external view returns (Swap memory) {
    return _swaps[id];
  }

  // User A create a swap
  function createSwap(address bAddress, NFT[] memory aNFTs) external payable chargeFee {
    _swapIdx += 1;

    safeTransfer(msg.sender, address(this), aNFTs);

    Swap storage swap = _swaps[_swapIdx];

    swap.aAddress = payable(msg.sender);

    for (uint256 i = 0;i < aNFTs.length; i++) {
      swap.aNFTs.push(aNFTs[i]);
    }

    if (msg.value > _fee) {
      swap.aEth = msg.value - _fee;
      _ethLocked += swap.aEth;
    }

    swap.bAddress = payable(bAddress);

    emit SwapCreate(msg.sender, swap.bAddress, _swapIdx, aNFTs, swap.aEth);
  }

  // User B init the swap
  function initSwap(uint256 id, NFT[] memory bNFTs) external payable chargeFee {
    require(_swaps[id].bAddress == msg.sender, "notCorrectUserB");
    require(_swaps[id].bNFTs.length == 0 && _swaps[id].bEth == 0, "swapAlreadyInit");

    safeTransfer(msg.sender, address(this), bNFTs);

    _swaps[id].bAddress = payable(msg.sender);

    for (uint256 i = 0; i < bNFTs.length; i++) {
      _swaps[id].bNFTs.push(bNFTs[i]);
    }

    if (msg.value > _fee) {
      _swaps[id].bEth = msg.value - _fee;
      _ethLocked += _swaps[id].bEth;
    }

    emit SwapReady(
      _swaps[id].aAddress,
      _swaps[id].bAddress,
      id,
      _swaps[id].aNFTs,
      _swaps[id].aEth,
      _swaps[id].bNFTs,
      _swaps[id].bEth
    );
  }

  // User A agrees on what user B offers, and finish the swap
  function finishSwap(uint256 id) external onlyA(id) {
    Swap memory swap = _swaps[id];

    require(
      (swap.aNFTs.length != 0 || swap.aEth != 0) &&
      (swap.bNFTs.length != 0 || swap.bEth !=0),
      "uninitSwap"
    );

    _ethLocked -= (swap.aEth + swap.bEth);

    // b => a
    safeTransfer(address(this), swap.aAddress, swap.bNFTs);

    if (swap.bEth != 0) {
      swap.aAddress.transfer(swap.bEth);
    }

    // a => b
    safeTransfer(address(this), swap.bAddress, swap.aNFTs);

    if (swap.aEth != 0) {
      swap.bAddress.transfer(swap.aEth);
    }

    emit SwapDone(swap.aAddress, swap.bAddress, id);

    delete _swaps[id];
  }

  // Either user A or user B can cancel the swap
  function cancelSwap(uint256 id) external {
    Swap memory swap = _swaps[id];

    require(swap.aAddress == msg.sender || swap.bAddress == msg.sender, "notUserAorB");

    _ethLocked -= (swap.aEth + swap.bEth);

    if (swap.aNFTs.length != 0) {
      safeTransfer(address(this), swap.aAddress, swap.aNFTs);
    }

    if (swap.aEth != 0) {
      swap.aAddress.transfer(swap.aEth);
    }

    if (swap.bNFTs.length != 0) {
      safeTransfer(address(this), swap.bAddress, swap.bNFTs);
    }

    if (swap.bEth != 0) {
      swap.bAddress.transfer(swap.bEth);
    }

    emit SwapCancel(swap.aAddress, swap.bAddress, id);

    delete _swaps[id];
  }

  function safeTransfer(address from, address to, NFT[] memory nfts) internal {
    for (uint256 i = 0; i < nfts.length; i++) {
      // ERC-20 transfer
      if (nfts[i].amount == 0) {
        IERC721(nfts[i].contractAddr).safeTransferFrom(from, to, nfts[i].id, "");
      } else { // ERC-1155 transfer
        IERC1155(nfts[i].contractAddr).safeTransferFrom(from, to, nfts[i].id, nfts[i].amount, "");
      }
    }
  }

  function withdrawFee(address payable recipient) external onlyOwner {
    require(recipient != address(0), "canNotWithdrawToAddress0");

    recipient.transfer(address(this).balance - _ethLocked);
  }
}
