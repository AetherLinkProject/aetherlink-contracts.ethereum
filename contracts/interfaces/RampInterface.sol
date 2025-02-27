// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRamp {
    struct TokenAmount {
        string swapId;
        uint256 targetChainId;
        string targetContractAddress;
        string tokenAddress;
        string originToken;
        uint256 amount;
    }

    struct Request {
        bytes32 id;
        address sender;
        address receiver;
        uint256 targetChainId;
        bytes data;
        TokenAmount tokenAmount;
        uint256 timestamp;
        bool fulfilled;
    }

    event ForwardMessageCalled(
        TokenAmount tokenAmount,
        string message,
        uint256 sourceChainId,
        string sender,
        address receiver
    );

    function sendRequest(
        uint256 targetChainId,
        string calldata receiver,
        bytes calldata data,
        TokenAmount calldata tokenAmount
    ) external returns (bytes32 messageId);
}
