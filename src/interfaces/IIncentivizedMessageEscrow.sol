// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IMessageEscrowStructs } from "./IMessageEscrowStructs.sol";
import { IMessageEscrowErrors } from "./IMessageEscrowErrors.sol";
import { IMessageEscrowEvents } from "./IMessageEscrowEvents.sol";

interface IIncentivizedMessageEscrow is IMessageEscrowStructs, IMessageEscrowErrors, IMessageEscrowEvents {
   function bounty(bytes32 messageIdentifier) external view returns(IncentiveDescription memory incentive);

   function messageDelivered(bytes32 sourceIdentifier, bytes calldata sourceImplementationIdentifier, bytes32 messageIdentifier) external view returns(bytes32 hasMessageBeenExecuted);

    function increaseBounty(
        bytes32 messageIdentifier,
        uint96 priceOfDeliveryGas,
        uint96 priceOfAckGas
    ) external payable;

    function submitMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier);

    function processPacket(bytes calldata messagingProtocolContext, bytes calldata message, bytes32 feeRecipient) payable external;

    function setRemoteImplementation(bytes32 chainIdentifier, bytes calldata implementation) external;

    /**
     * @notice Estimates the additional cost to the messaging router to validate the message
     * @return asset The asset the token is in. If native token, returns address(0);
     * @return amount The number of assets to pay.
     */
    function estimateAdditionalCost() external view returns(address asset, uint256 amount);

    function timeoutMessage(
        bytes32 sourceIdentifier,
        bytes calldata implementationIdentifier,
        uint256 originBlockNumber,
        bytes calldata message
    ) external payable;

    function reemitAckMessage(
        bytes32 sourceIdentifier,
        bytes calldata implementationIdentifier,
        bytes calldata receiveAckWithContext
    ) external payable;
}