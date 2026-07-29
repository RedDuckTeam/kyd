// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/DoubleLinkedList.sol";
import "./libraries/DecimalsCorrectionLibrary.sol";
import "./libraries/UniswapV3Actions.sol";
import "./gelato/GelatoVRFConsumerBase.sol";
import "./interfaces/IAuction.sol";
import "./AuctionNFT.sol";
import "./AuctionFactory.sol";
import "hardhat/console.sol";

contract Auction is IAuction, OwnableUpgradeable {
    using DoubleLinkedList for DoubleLinkedList.List;
    using DecimalsCorrectionLibrary for uint256;
    using SafeERC20 for IERC20;
    DoubleLinkedList.List list;

    event Donate(address indexed user, address indexed stable, uint256 amount);
    event AuctionEnded();
    event RewardsDistributed();

    error InvalidEthDonate();
    error AuctionIsEnded();
    error AlreadyDistributed();
    error RandomnessIsNotSet();
    error AlreadyFinished();
    error NotDistributed();
    error MismatchLenghts();
    error StableNotSupported();
    error InvalidConfiguration();

    uint256 public constant MAX_RANDOM_WINNERS = 10;
    uint256 public constant MAX_TOP_WINNERS = 10;

    mapping(address => bool) public userDonated;
    mapping(address => bool) public supportedStables;

    uint256 public totalDonated;

    address[] stables;
    bytes ethToStablePath;
    address swapStable;
    address uniswapV3Router;
    uint256[] topWinnersNfts;
    uint256 public goal;
    address public nft;
    address public nftParticipate;
    uint256 public randomWinners;
    uint256 public randomWinnerLastNftId;
    uint256 public participationNftId;
    address public factory;

    uint256 public randomness;
    bool public nftsDistributed;
    bool public randomnessRequested;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IAuction.AuctionParams calldata _params
    ) external initializer {
        __Ownable_init(_params.owner);

        if (_params.randomWinners > MAX_RANDOM_WINNERS)
            revert InvalidConfiguration();

        if (_params.topWinners.length > MAX_TOP_WINNERS)
            revert InvalidConfiguration();

        goal = _params.goal;
        nft = _params.nft;
        randomWinners = _params.randomWinners;
        randomWinnerLastNftId = _params.randomWinnerNftId;
        participationNftId = _params.participationNftId;
        stables = _params.stables;
        ethToStablePath = _params.ethToStablePath;
        swapStable = _params.swapStable;
        uniswapV3Router = _params.uniswapV3Router;

        factory = msg.sender;

        for (uint i; i < _params.stables.length; i++) {
            supportedStables[_params.stables[i]] = true;
        }

        topWinnersNfts = _params.topWinners;
        nftParticipate = _params.nftParticipate;
    }

    function finish() external onlyOwner {
        if (randomnessRequested) revert AlreadyFinished();

        _finishAuction();

        emit AuctionEnded();
    }

    function distributeRewards() external {
        if (randomness == 0) revert RandomnessIsNotSet();
        if (nftsDistributed) revert AlreadyDistributed();

        _distibute();

        emit RewardsDistributed();
    }

    function withdrawMult(
        address[] calldata _stables,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (_stables.length != amounts.length) revert MismatchLenghts();
        if (!nftsDistributed) revert NotDistributed();

        for (uint i = 0; i < _stables.length; i++) {
            IERC20(_stables[i]).safeTransfer(owner(), amounts[i]);
        }
    }

    function donateEth(
        uint256 indexToInsert,
        uint256 indexOfExisting,
        bool before,
        uint256 minAmountOut
    ) external payable {
        if (msg.value == 0) {
            revert InvalidEthDonate();
        }

        uint256 stableAmount = UniswapV3Actions.swap(
            uniswapV3Router,
            ethToStablePath,
            address(this),
            msg.value,
            minAmountOut
        );

        stableAmount = stableAmount.convertToBase18(
            ERC20(swapStable).decimals()
        );

        _donate(
            stableAmount,
            indexToInsert,
            indexOfExisting,
            before,
            swapStable
        );
    }

    function donate(
        address stable,
        uint256 amount,
        uint256 indexToInsert,
        uint256 indexOfExisting,
        bool before
    ) external {
        if (!supportedStables[stable]) revert StableNotSupported();

        IERC20(stable).safeTransferFrom(msg.sender, address(this), amount);

        amount = amount.convertToBase18(ERC20(stable).decimals());

        _donate(amount, indexToInsert, indexOfExisting, before, stable);
    }

    function _donate(
        uint256 amount,
        uint256 indexToInsert,
        uint256 indexOfExisting,
        bool before,
        address stable
    ) internal {
        if (randomness != 0) {
            revert AuctionIsEnded();
        }

        totalDonated += amount;

        if (userDonated[msg.sender]) {
            if (indexToInsert == indexOfExisting) {
                list.increaseAmount(msg.sender, indexOfExisting, amount);
            } else {
                uint256 prevAmount = list.remove(msg.sender, indexOfExisting);

                if (before) {
                    list.insertBefore(
                        indexToInsert,
                        DoubleLinkedList.Data({
                            user: msg.sender,
                            amount: amount + prevAmount
                        })
                    );
                } else {
                    list.insertAfter(
                        indexToInsert,
                        DoubleLinkedList.Data({
                            user: msg.sender,
                            amount: amount + prevAmount
                        })
                    );
                }
            }
        } else {
            if (before) {
                list.insertBefore(
                    indexToInsert,
                    DoubleLinkedList.Data({user: msg.sender, amount: amount})
                );
            } else {
                list.insertAfter(
                    indexToInsert,
                    DoubleLinkedList.Data({user: msg.sender, amount: amount})
                );
            }

            _mint(nftParticipate, msg.sender, 0);

            userDonated[msg.sender] = true;
        }

        emit Donate(stable, msg.sender, amount);

        if (totalDonated >= goal) {
            _finishAuction();
        }
    }

    function getUser(
        uint256 id
    ) external view returns (DoubleLinkedList.Data memory) {
        return list.getNodeData(id);
    }

    function getNodes() external view returns (DoubleLinkedList.Node[] memory) {
        return list.getNodes();
    }

    function getListWithNodes()
        external
        view
        returns (DoubleLinkedList.Node[] memory, uint256, uint256, uint256)
    {
        return (list.getNodes(), list.head, list.tail, list.length);
    }

    function fulfillRandomness(uint256 _randomness) external {
        require(msg.sender == factory, "Not a factory");
        randomness = _randomness;
    }

    function getTopWinnerNFTS() external view returns (uint256[] memory) {
        return topWinnersNfts;
    }

    function getRandomWinners() external view returns (uint256) {
        return randomWinners;
    }

    function _finishAuction() internal virtual {
        AuctionFactory(factory).requestRandomness();
        randomnessRequested = true;
    }

    function _distibute() private {
        uint256 _randomWinners = randomWinners;

        for (uint i; i <= topWinnersNfts.length; i++) {
            if (list.length == 0) break;

            DoubleLinkedList.Node memory node = list.getNode(list.tail);

            _mint(nft, node.data.user, i);
            console.log(list.tail, node.data.user, i);
            list.remove(node.data.user, list.tail);
        }

        for (uint256 i; _randomWinners != 0; i++) {
            if (list.length == 0) break;

            uint256 randomValue = uint256(
                keccak256(abi.encodePacked(randomness, i))
            ) % list.length;

            DoubleLinkedList.Data memory data = list.getNodeData(randomValue);

            // if random value repeated
            if (data.user == address(0)) continue;

            console.log("randomWinnerLastNftId", randomWinnerLastNftId);
            _mint(nft, data.user, randomWinnerLastNftId++);

            list.remove(data.user, randomValue);

            _randomWinners--;
        }

        nftsDistributed = true;
    }

    function _mint(address _nft, address to, uint256 id) private {
        AuctionNFT(_nft).mint(to, id);
    }
}
