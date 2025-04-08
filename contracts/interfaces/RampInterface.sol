// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRamp {
    struct TokenTransferMetadata {
        uint256 targetChainId;
        string tokenAddress;
        string symbol;
        uint256 amount;
        bytes extraData;
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
