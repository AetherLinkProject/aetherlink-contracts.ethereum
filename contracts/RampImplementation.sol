// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./Proxy.sol";
import "./interfaces/RampInterface.sol";
import "./interfaces/RouterInterface.sol";
import "hardhat/console.sol";

pragma solidity 0.8.9;

contract RampImplementation is ProxyStorage, IRamp {
    bool private initialized;
    address[] private oracleNodes;
    mapping(address => bool) private isOracleNode;
    uint256 public signatureThreshold;
    uint256 public epoch;
    mapping(address => bool) private authorizedSenders;
    uint256[] private authorizedSourceChainIdListArray;
    mapping(uint256 => bool) public authorizedSourceChainIdList;
    uint256[] private authorizedTargetChainIdListArray;
    mapping(uint256 => bool) public authorizedTargetChainIdList;

    mapping(bytes32 => bool) private processedReports;
    bytes32 public TRANSMIT_TYPEHASH;
    bytes32 public DOMAIN_SEPARATOR;

    error InvalidSigner(address signer);

    event ContractInitialized(address[] initialNodes);
    event RampSenderAdded(address sender);
    event RampSenderRemoved(address sender);
    event OracleNodesUpdated(address[] newOracleNodes);
    event ChainIdWhitelistUpdated(
        uint256[] newSourceChainIds,
        uint256[] newTargetChainIds
    );

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
        DOMAIN_SEPARATOR = _buildDomainSeparator();
        TRANSMIT_TYPEHASH = _buildTransmitTypeHash();

        _updateOracleNodes(initialNodes);

        emit ContractInitialized(initialNodes);
    }

    function getOracleNodes() external view returns (address[] memory) {
        return oracleNodes;
    }

    function getInitialized() external view returns (bool) {
        return initialized;
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _buildDomainSeparator();
    }

    function getTransmitTypeHash() external view returns (bytes32) {
        return _buildTransmitTypeHash();
    }

    function isAuthorizedSender(address sender) external view returns (bool) {
        return authorizedSenders[sender];
    }

    function addRampSender(address sender) external onlyOwner {
        require(sender != address(0), "Invalid sender address");
        require(!authorizedSenders[sender], "Sender already whitelisted");

        authorizedSenders[sender] = true;

        emit RampSenderAdded(sender);
    }

    function removeRampSenderFrom(address sender) external onlyOwner {
        require(sender != address(0), "Invalid sender address");
        require(authorizedSenders[sender], "Sender not in whitelist");

        delete authorizedSenders[sender];

        emit RampSenderRemoved(sender);
    }

    function updateOracleNodes(
        address[] calldata newOracleNodes
    ) external onlyOwner {
        _updateOracleNodes(newOracleNodes);

        emit OracleNodesUpdated(newOracleNodes);
    }

    function updateChainIdWhitelist(
        uint256[] calldata newSourceChainIds,
        uint256[] calldata newTargetChainIds
    ) external onlyOwner {
        _updateChainIdWhitelist(newSourceChainIds, newTargetChainIds);

        emit ChainIdWhitelistUpdated(newSourceChainIds, newTargetChainIds);
    }

    function sendRequest(
        uint256 targetChainId,
        string calldata receiver,
        bytes calldata message,
        IRamp.TokenTransferMetadata calldata tokenTransferMetadata
    ) external onlyAuthorizedSender returns (bytes32 messageId) {
        require(
            authorizedTargetChainIdList[targetChainId],
            "targetChainId not supportted"
        );
        messageId = keccak256(
            abi.encode(
                msg.sender,
                targetChainId,
                receiver,
                message,
                tokenTransferMetadata,
                epoch,
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
        bytes[] calldata signatures
    ) external onlyOracleNode {
        require(message.length > 0, "Invalid message");

        bytes32 reportHash = _buildEIP712ReportHash(
            reportContextBytes,
            message,
            tokenTransferMetadataBytes
        );

        require(
            !processedReports[reportHash],
            "Duplicate report: already processed"
        );
        processedReports[reportHash] = true;

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

        _validateSignatures(reportHash, signatures);

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

    function _validateSignatures(
        bytes32 reportHash,
        bytes[] memory signatures
    ) internal view {
        require(
            signatures.length >= signatureThreshold,
            "Not enough signatures"
        );

        address[] memory signers = new address[](signatures.length);
        for (uint256 i = 0; i < signatures.length; i++) {
            address recoveredSigner = ECDSA.recover(reportHash, signatures[i]);
            require(
                !_contains(signers, recoveredSigner),
                "Non-unique signature"
            );

            if (!isOracleNode[recoveredSigner]) {
                revert("invalid signer");
            }

            signers[i] = recoveredSigner;
        }
    }

    function _updateOracleNodes(address[] memory newOracleNodes) internal {
        for (uint256 i = 0; i < oracleNodes.length; i++) {
            isOracleNode[oracleNodes[i]] = false;
        }
        delete oracleNodes;

        for (uint256 j = 0; j < newOracleNodes.length; j++) {
            require(newOracleNodes[j] != address(0), "Invalid node address");
            require(!isOracleNode[newOracleNodes[j]], "Duplicate node address");

            oracleNodes.push(newOracleNodes[j]);
            isOracleNode[newOracleNodes[j]] = true;
        }

        signatureThreshold = (oracleNodes.length + 1) / 2 + 1;
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
                !authorizedTargetChainIdList[newTargetChainIds[i]],
                "Duplicate chainId"
            );
            authorizedTargetChainIdList[newTargetChainIds[i]] = true;
            authorizedTargetChainIdListArray.push(newTargetChainIds[i]);
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("RampImplementation"),
                    keccak256("1.0.0"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _buildTransmitTypeHash() private view returns (bytes32) {
        return
            keccak256(
                "Transmit(bytes reportContextBytes, bytes message, bytes tokenTransferMetadataBytes)"
            );
    }

    function _buildEIP712ReportHash(
        bytes calldata reportContextBytes,
        bytes calldata message,
        bytes calldata tokenTransferMetadataBytes
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-712
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            TRANSMIT_TYPEHASH,
                            keccak256(reportContextBytes),
                            keccak256(message),
                            keccak256(tokenTransferMetadataBytes)
                        )
                    )
                )
            );
    }
}
