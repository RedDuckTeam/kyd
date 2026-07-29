// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./AuctionFactory.sol";

contract AuctionFactoryScroll is AuctionFactory {
    error NotImplemented();

    constructor(
        address _gelatoOperator,
        address _implementation,
        address _nftImplementation,
        address _nftParticipantsImplementation
    )
        AuctionFactory(
            _gelatoOperator,
            _implementation,
            _nftImplementation,
            _nftParticipantsImplementation
        )
    {}

    function fulfillRandomness(uint256, bytes calldata) external override {
        revert NotImplemented();
    }

    function _requestRandomness(
        bytes memory extraData
    ) internal override returns (uint256) {
        // as we do not have a vrf provider on scroll, we a generating pseudo-random value here
        uint256 randomness = uint256(
            keccak256(
                abi.encodePacked(
                    requestPending.length,
                    address(this),
                    block.number,
                    block.timestamp,
                    block.chainid,
                    _round()
                )
            )
        );

        requestPending.push();

        _fulfillRandomness(randomness, 0, extraData);
    }
}
