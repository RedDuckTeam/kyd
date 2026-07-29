// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAuction {
    struct AuctionParams {
        address[] stables;
        bytes ethToStablePath;
        address swapStable;
        address uniswapV3Router;
        uint256[] topWinners;
        uint256 goal;
        address owner;
        address nft;
        address nftParticipate;
        uint256 randomWinners;
        uint256 randomWinnerNftId;
        uint256 participationNftId;
    }
}
