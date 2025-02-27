pragma solidity ^0.8.9;

import "../interfaces/RampInterface.sol";
import "../interfaces/RouterInterface.sol";

contract MockRouter is IRouter {
    event MockRouterDeployed(address indexed routerAddress);

    constructor() {
        emit MockRouterDeployed(address(this));
    }

    function forwardMessage(
        uint256 sourceChainId,
        uint256 targetChainId,
        string calldata sender,
        address receiver,
        bytes calldata message,
        IRamp.TokenAmount calldata tokenAmount
    ) external override {}
}
