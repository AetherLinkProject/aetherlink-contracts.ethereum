// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRamp {
    struct TokenTransferMetadata {
        // TODO change struct name
        string swapId;
        uint256 targetChainId;
        string targetContractAddress;
        string tokenAddress;
        string originToken; // symbol
        uint256 amount;
        // TODO add extra data
    }

    struct Request {
        bytes32 id;
        address sender;
        address receiver;
        uint256 targetChainId;
        bytes data;
        TokenTransferMetadata tokenTransferMetadata;
        uint256 timestamp;
        bool fulfilled;
    }

    event ForwardMessageCalled(
        TokenTransferMetadata tokenTransferMetadata,
        string message,
        uint256 sourceChainId,
        string sender,
        address receiver
    );

    function sendRequest(
        uint256 targetChainId,
        string calldata receiver,
        bytes calldata data,
        TokenTransferMetadata calldata tokenTransferMetadata
    ) external returns (bytes32 messageId);
}
