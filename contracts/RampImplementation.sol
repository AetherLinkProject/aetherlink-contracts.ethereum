// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./Proxy.sol";
import "./interfaces/RampInterface.sol";
import "./interfaces/RouterInterface.sol";
import "hardhat/console.sol";

pragma solidity 0.8.9;

contract RampImplementation is ProxyStorage {
    bool private initialized;
    uint256 public threshold; // Min signatures required for consensus
    address[] private oracleNodes;
    mapping(address => bool) private isOracleNode;
    uint256 public signatureThreshold;
    uint256 public epoch;
    mapping(address => bool) private authorizedSenders;
    uint256[] private authorizedSourceChainIdListArray;
    mapping(uint256 => bool) public authorizedSourceChainIdList;
    uint256[] private authorizedTargetChainIdListArray;
    mapping(uint256 => bool) public authorizedTargetChainIdList;

    error InvalidSigner(address signer);
    error InvalidSender(address sender);

    struct ReportContext {
        bytes32 messageId;
        uint256 sourceChainId;
        uint256 targetChainId;
        string sender;
        address receiver;
    }

    modifier onlyOracleNode() {
        require(
            isOracleNode[msg.sender],
            "Caller is not an authorized oracle node"
        );
        // console.log("Oracle check passed for:", msg.sender); // Debug oracle check
        _;
    }

    modifier onlyAuthorizedSender() {
        require(
            authorizedSenders[msg.sender],
            "Caller is not an authorized sender"
        );

        _;
    }

    event RequestSent(
        bytes32 indexed messageId,
        uint256 epoch,
        address indexed sender,
        string receiver,
        uint256 sourceChainId,
        uint256 targetChainId,
        bytes message,
        bytes tokenTransferMetadataBytes
    );

    event ForwardMessageCalled(
        bytes32 indexed messageId,
        uint256 sourceChainId,
        uint256 targetChainId,
        string sender,
        address receiver,
        bytes message
    );

    function initialize(address[] memory initialNodes) external onlyOwner {
        require(!initialized, "Already initialized");
        initialized = true;

        _updateOracleNodes(initialNodes);
    }

    function getOracleNodes() external view returns (address[] memory) {
        return oracleNodes;
    }

    function getInitialized() external view returns (bool) {
        return initialized;
    }

    function isAuthorizedSender(address sender) external view returns (bool) {
        return authorizedSenders[sender];
    }

    function addRampSender(address sender) external onlyOwner {
        require(sender != address(0), "Invalid sender address");
        require(!authorizedSenders[sender], "Sender already whitelisted");

        authorizedSenders[sender] = true;
    }

    function removeRampSenderFrom(address sender) external onlyOwner {
        require(sender != address(0), "Invalid sender address");
        require(authorizedSenders[sender], "Sender not in whitelist");

        delete authorizedSenders[sender];
    }

    function updateOracleNodes(
        address[] calldata newOracleNodes
    ) external onlyOwner {
        // console.log("Updating oracle nodes..."); // Log message
        _updateOracleNodes(newOracleNodes);
    }

    function updateChainIdWhitelist(
        uint256[] calldata newSourceChainIds,
        uint256[] calldata newTargetChainIds
    ) external onlyOwner {
        _updateChainIdWhitelist(newSourceChainIds, newTargetChainIds);
    }

    function sendRequest(
        uint256 targetChainId,
        string calldata receiver,
        bytes calldata message,
        IRamp.TokenTransferMetadata calldata tokenTransferMetadata
    ) external onlyAuthorizedSender returns (bytes32 messageId) {
        messageId = keccak256(
            abi.encode(
                msg.sender,
                targetChainId,
                receiver,
                message,
                tokenTransferMetadata,
                block.timestamp
            )
        );
        bytes memory tokenTransferMetadataBytes = abi.encode(
            tokenTransferMetadata
        );

        emit RequestSent(
            messageId,
            epoch,
            msg.sender,
            receiver,
            block.chainid,
            targetChainId,
            message,
            tokenTransferMetadataBytes
        );

        epoch += 1;
    }

    function transmit(
        bytes calldata reportContextBytes,
        bytes calldata message,
        bytes calldata tokenTransferMetadataBytes,
        bytes32[] memory rs,
        bytes32[] memory ss,
        bytes32 rawVs
    ) external onlyOracleNode {
        require(message.length > 0, "invalide message");
        require(rs.length > 0, "invalide rs");
        require(ss.length > 0, "invalide ss");
        require(rawVs.length > 0, "invalide rv");

        ReportContext memory reportContext = decodeReportContext(
            reportContextBytes
        );

        require(
            authorizedSourceChainIdList[reportContext.sourceChainId],
            "sourceChainId not supportted"
        );

        IRamp.TokenTransferMetadata memory tokenTransferMetadata;
        if (tokenTransferMetadataBytes.length > 0) {
            tokenTransferMetadata = decodeTokenTransferMetadata(
                tokenTransferMetadataBytes
            );
        }

        require(reportContext.targetChainId > 0, "Invalid targetChainId.");
        require(
            reportContext.receiver != address(0),
            "Invalid receiver address."
        );

        bytes32 reportHash = keccak256(
            abi.encode(reportContextBytes, message, tokenTransferMetadataBytes)
        );
        require(
            _validateSignatures(reportHash, rs, ss, rawVs),
            "Insufficient or invalid signatures"
        );

        IRouter(reportContext.receiver).forwardMessage(
            reportContext.sourceChainId,
            reportContext.targetChainId,
            reportContext.sender,
            reportContext.receiver,
            message,
            tokenTransferMetadata
        );

        emit ForwardMessageCalled(
            reportContext.messageId,
            reportContext.sourceChainId,
            reportContext.targetChainId,
            reportContext.sender,
            reportContext.receiver,
            message
        );
    }

    function decodeTokenTransferMetadata(
        bytes calldata tokenTransferMetadataBytes
    ) internal returns (IRamp.TokenTransferMetadata memory) {
        (
            uint256 targetChainId,
            string memory tokenAddress,
            string memory symbol,
            uint256 amount,
            bytes memory extraData
        ) = abi.decode(
                tokenTransferMetadataBytes,
                (uint256, string, string, uint256, bytes)
            );

        return
            IRamp.TokenTransferMetadata({
                targetChainId: targetChainId,
                tokenAddress: tokenAddress,
                symbol: symbol,
                amount: amount,
                extraData: extraData
            });
    }

    function decodeReportContext(
        bytes calldata reportContextBytes
    ) internal returns (ReportContext memory) {
        // Decode the ABI-encoded data into the ReportContext struct
        (
            bytes32 messageId,
            uint256 sourceChainId,
            uint256 targetChainId,
            string memory sender,
            address receiver
        ) = abi.decode(
                reportContextBytes,
                (bytes32, uint256, uint256, string, address)
            );

        return
            ReportContext({
                messageId: messageId,
                sourceChainId: sourceChainId,
                targetChainId: targetChainId,
                sender: sender,
                receiver: receiver
            });
    }

    function _contains(
        address[] memory array,
        address target
    ) internal pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (target == array[i]) {
                return true;
            }
        }
        return false;
    }

    // --- Internal Helpers ---
    function _validateSignatures(
        bytes32 reportHash,
        bytes32[] memory rs,
        bytes32[] memory ss,
        bytes32 rawVs
    ) internal view returns (bool) {
        require(rs.length == ss.length, "Mismatched signature arrays");
        require(rs.length <= oracleNodes.length, "Too many signatures");

        // Track valid signatures
        uint256 validSignatures = 0;

        address[] memory signers = new address[](rs.length);
        for (uint256 i = 0; i < rs.length; i++) {
            uint8 v = uint8(rawVs[i]); // Extract normalized `v` value

            // Ensure `v` is valid (27 or 28)
            if (v < 27) v += 27;

            // Recover signer address
            address recovered = ecrecover(reportHash, v, rs[i], ss[i]);
            require(recovered != address(0), "Invalid signature: zero address");
            require(!_contains(signers, recovered), "non-unique signature");
            signers[i] = recovered;

            // Ensure recovered signer is an authorized oracle node
            if (isOracleNode[recovered]) {
                validSignatures++;
            } else {
                revert InvalidSigner(recovered);
            }
        }

        // Check signature threshold
        // console.log("Valid Signatures:", validSignatures);
        return validSignatures >= signatureThreshold;
    }

    function _updateOracleNodes(address[] memory newOracleNodes) internal {
        // console.log("Clearing current oracle nodes...");
        for (uint256 i = 0; i < oracleNodes.length; i++) {
            isOracleNode[oracleNodes[i]] = false;
        }
        delete oracleNodes;

        for (uint256 j = 0; j < newOracleNodes.length; j++) {
            require(newOracleNodes[j] != address(0), "Invalid node address");
            require(!isOracleNode[newOracleNodes[j]], "Duplicate node address");

            // console.log("Adding new node:", newOracleNodes[j]); // Log new node addition
            oracleNodes.push(newOracleNodes[j]);
            isOracleNode[newOracleNodes[j]] = true;
        }

        signatureThreshold = (oracleNodes.length + 1) / 2 + 1;
        // console.log("Updated signature threshold:", signatureThreshold); // Debug threshold update
    }

    function _updateChainIdWhitelist(
        uint256[] calldata newSourceChainIds,
        uint256[] calldata newTargetChainIds
    ) internal {
        // source chain ids
        for (uint256 i = 0; i < authorizedSourceChainIdListArray.length; i++) {
            authorizedSourceChainIdList[
                authorizedSourceChainIdListArray[i]
            ] = false;
        }
        delete authorizedSourceChainIdListArray;

        for (uint256 i = 0; i < newSourceChainIds.length; i++) {
            require(newSourceChainIds[i] > 0, "Invalid chainId");
            require(
                !authorizedSourceChainIdList[newSourceChainIds[i]],
                "Duplicate chainId"
            );
            authorizedSourceChainIdList[newSourceChainIds[i]] = true;
            authorizedSourceChainIdListArray.push(newSourceChainIds[i]);
        }

        // target chain ids
        for (uint256 i = 0; i < authorizedTargetChainIdListArray.length; i++) {
            authorizedTargetChainIdList[
                authorizedTargetChainIdListArray[i]
            ] = false;
        }
        delete authorizedTargetChainIdListArray;

        for (uint256 i = 0; i < newTargetChainIds.length; i++) {
            require(newTargetChainIds[i] > 0, "Invalid chainId");
            require(
                !authorizedSourceChainIdList[newTargetChainIds[i]],
                "Duplicate chainId"
            );
            authorizedSourceChainIdList[newTargetChainIds[i]] = true;
            authorizedSourceChainIdListArray.push(newTargetChainIds[i]);
        }
    }

    // for debug
    // function debugReportHash(
    //     ReportContext memory reportContext,
    //     string memory message,
    //     TokenTransferMetadata memory tokenTransferMetadata
    // ) public pure returns (bytes32) {
    //     return keccak256(abi.encode(reportContext, message, tokenTransferMetadata));
    // }

    // function debugRequestId(bytes32 requestId) public pure returns (bytes32) {
    //     return requestId;
    // }
}
