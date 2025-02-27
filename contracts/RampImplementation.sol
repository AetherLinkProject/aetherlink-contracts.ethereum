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

    error InvalidSigner(address signer);
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

    event RequestSent(
        bytes32 indexed messageId,
        uint256 epoch,
        address indexed sender,
        string receiver,
        uint256 sourceChainId,
        uint256 targetChainId,
        bytes message,
        // for tokenAmount
        string targetContractAddress,
        string tokenAddress,
        uint256 amount
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

    function updateOracleNodes(
        address[] calldata newOracleNodes
    ) external onlyOwner {
        // console.log("Updating oracle nodes..."); // Log message
        _updateOracleNodes(newOracleNodes);
    }

    function sendRequest(
        uint256 targetChainId,
        string calldata receiver,
        bytes calldata message,
        IRamp.TokenAmount calldata tokenAmount
    ) external returns (bytes32 messageId) {
        require(tokenAmount.amount > 0, "Invalid token amount");

        messageId = keccak256(
            abi.encode(
                msg.sender,
                targetChainId,
                receiver,
                message,
                tokenAmount,
                block.timestamp
            )
        );

        emit RequestSent(
            messageId,
            epoch,
            msg.sender,
            receiver,
            block.chainid,
            targetChainId,
            message,
            tokenAmount.targetContractAddress,
            tokenAmount.tokenAddress,
            tokenAmount.amount
        );

        epoch += 1;
    }

    function transmit(
        bytes calldata reportContextDecoded,
        bytes calldata message,
        bytes calldata tokenAmountDecoded,
        bytes32[] memory rs,
        bytes32[] memory ss,
        bytes32 rawVs
    ) external onlyOracleNode {
        require(message.length > 0, "invalide message");
        require(rs.length > 0, "invalide rs");
        require(ss.length > 0, "invalide ss");
        require(rawVs.length > 0, "invalide rv");

        ReportContext memory reportContext = decodeReportContext(
            reportContextDecoded
        );
        IRamp.TokenAmount memory tokenAmount = decodeTokenAmount(
            tokenAmountDecoded
        );

        require(reportContext.targetChainId > 0, "Invalid targetChainId.");
        require(
            reportContext.receiver != address(0),
            "Invalid receiver address."
        );

        bytes32 reportHash = keccak256(
            abi.encode(reportContextDecoded, message, tokenAmountDecoded)
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
            tokenAmount
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

    function decodeTokenAmount(
        bytes calldata tokenAmountBytes
    ) internal returns (IRamp.TokenAmount memory) {
        // Decode the ABI-encoded data into the TokenAmount struct
        (
            string memory swapId,
            uint256 targetChainId,
            string memory targetContractAddress,
            string memory tokenAddress,
            string memory originToken,
            uint256 amount
        ) = abi.decode(
                tokenAmountBytes,
                (string, uint256, string, string, string, uint256)
            );

        return
            IRamp.TokenAmount({
                swapId: swapId,
                targetChainId: targetChainId,
                targetContractAddress: targetContractAddress,
                tokenAddress: tokenAddress,
                originToken: originToken,
                amount: amount
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

    // for debug
    // function debugReportHash(
    //     ReportContext memory reportContext,
    //     string memory message,
    //     TokenAmount memory tokenAmount
    // ) public pure returns (bytes32) {
    //     return keccak256(abi.encode(reportContext, message, tokenAmount));
    // }

    // function debugRequestId(bytes32 requestId) public pure returns (bytes32) {
    //     return requestId;
    // }
}
