pragma solidity ^0.8.9;
import "./RampInterface.sol";

interface IRouter {
    function forwardMessage(
        uint256 sourceChainId,
        uint256 targetChainId,
        string memory sender,
        address receiver,
        bytes memory message,
        IRamp.TokenAmount memory tokenAmount
    ) external;
}
