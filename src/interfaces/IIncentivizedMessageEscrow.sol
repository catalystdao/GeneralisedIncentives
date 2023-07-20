// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import { IMessageEscrowStructs } from "./IMessageEscrowStructs.sol";
import { IMessageEscrowErrors } from "./IMessageEscrowErrors.sol";
import { IMessageEscrowEvents } from "./IMessageEscrowEvents.sol";


interface IIncentivizedMessageEscrow is IMessageEscrowStructs, IMessageEscrowErrors, IMessageEscrowEvents {
   function bounty(bytes32 messageIdentifier) external view returns(IncentiveDescription memory incentive);

   function spentMessageIdentifier(bytes32 messageIdentifier) external view returns(bool hasMessageBeenExecuted);

    function increaseBounty(
        bytes32 messageIdentifier,
        uint96 priceOfDeliveryGas,
        uint96 priceOfAckGas
    ) external payable;

    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier);

    /// @notice Describes the implementation
    function implementationVersion() view external returns(string memory versionDescriptor);
}