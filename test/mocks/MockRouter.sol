// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract MockRouter is IRouterClient {
    bytes32 public constant MOCK_MESSAGE_ID = keccak256("MOCK_MESSAGE_ID");

    uint256 public fee;

    bytes public lastData;
    bytes public lastReceiver;
    address public lastFeeToken;
    uint64 public lastDestinationChainSelector;

    function setFee(uint256 _fee) external {
        fee = _fee;
    }

    function getFee(uint64, Client.EVM2AnyMessage calldata) external view override returns (uint256) {
        return fee;
    }

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        override
        returns (bytes32)
    {
        lastDestinationChainSelector = destinationChainSelector;
        lastData = message.data;
        lastReceiver = message.receiver;
        lastFeeToken = message.feeToken;

        return MOCK_MESSAGE_ID;
    }

    function isChainSupported(uint64) external pure override returns (bool) {
        return true;
    }

    function getSupportedTokens(uint64) external pure returns (address[] memory tokens) {
        return new address[](0);
    }
}
