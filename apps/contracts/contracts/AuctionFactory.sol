// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IAuction.sol";
import "./Auction.sol";
import "./AuctionNFT.sol";
import "./AuctionNFT1155.sol";
import "./gelato/GelatoVRFConsumerBase.sol";

struct AuctionCreateParams {
    address[] stables;
    bytes ethToStablePath;
    address swapStable;
    address uniswapV3Router;
    uint256[] topWinners;
    uint256 goal;
    address owner;
    uint256 randomWinners;
    uint256 randomWinnerNftId;
    string baseUri;
}

struct AuctionNftCreateParams {
    string name;
    string symb;
    string uri;
}

contract AuctionFactory is GelatoVRFConsumerBase {
    address[] public auctions;
    mapping(address => bool) public auctionsMap;

    event AuctionDeployed(
        address indexed auction,
        address indexed owner,
        string baseUri
    );
    event NFTDeployed(
        address indexed nft,
        string baseUri,
        address auctionAddress
    );
    event NFT1155Deployed(
        address indexed nft1155,
        string baseUri,
        address auctionAddress
    );

    address immutable gelatoOperator;
    address immutable implementation;
    address immutable nftImplementation;
    address immutable nftParticipantsImplementation;

    constructor(
        address _gelatoOperator,
        address _implementation,
        address _nftImplementation,
        address _nftParticipantsImplementation
    ) {
        gelatoOperator = _gelatoOperator;
        implementation = _implementation;

        nftImplementation = _nftImplementation;
        nftParticipantsImplementation = _nftParticipantsImplementation;
    }

    function create(
        AuctionCreateParams calldata params,
        AuctionNftCreateParams calldata paramsNft,
        AuctionNftCreateParams calldata paramsNftParticipants
    ) external returns (address) {
        AuctionNFT auctionNFT = AuctionNFT(
            payable(Clones.clone(nftImplementation))
        );
        AuctionNFT1155 auctionNFTParticipants = AuctionNFT1155(
            payable(Clones.clone(nftParticipantsImplementation))
        );
        Auction auction = Auction(payable(Clones.clone(implementation)));

        auctionNFT.initialize(
            paramsNft.name,
            paramsNft.symb,
            paramsNft.uri,
            address(auction)
        );
        auctionNFTParticipants.initialize(
            paramsNftParticipants.uri,
            address(auction)
        );

        auction.initialize(
            IAuction.AuctionParams({
                stables: params.stables,
                ethToStablePath: params.ethToStablePath,
                swapStable: params.swapStable,
                uniswapV3Router: params.uniswapV3Router,
                topWinners: params.topWinners,
                goal: params.goal,
                owner: params.owner,
                nft: address(auctionNFT),
                nftParticipate: address(auctionNFTParticipants),
                randomWinners: params.randomWinners,
                randomWinnerNftId: params.randomWinnerNftId,
                participationNftId: 0
            })
        );

        auctions.push(address(auction));
        auctionsMap[address(auction)] = true;
        emit AuctionDeployed(address(auction), params.owner, params.baseUri);
        emit NFTDeployed(address(auctionNFT), paramsNft.uri, address(auction));
        emit NFT1155Deployed(
            address(auctionNFTParticipants),
            paramsNftParticipants.uri,
            address(auction)
        );

        return address(auction);
    }

    function _fulfillRandomness(
        uint256 randomness,
        uint256,
        bytes memory extraData
    ) internal override {
        address auction = abi.decode(extraData, (address));
        require(auctionsMap[auction], "Not an auction");
        Auction(auction).fulfillRandomness(randomness);
    }

    function requestRandomness() external {
        require(auctionsMap[msg.sender], "Not an auction");
        _requestRandomness(abi.encode(msg.sender));
    }

    function _operator() internal view override returns (address) {
        return gelatoOperator;
    }
}
