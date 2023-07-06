// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { IApplication } from "./interfaces/IApplication.sol";


abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow {
    error NotEnoughGasProvided(uint256 expected, uint256 actual);
    error InvalidTotalIncentive(uint256 expected, uint256 actual);
    error ZeroIncentiveNotAllowed();
    error MessageAlreadyBountied();
    error NotImplementedError();

    bytes1 constant MESSAGEv1 = 0x00;
    bytes1 constant ACKv1 = 0x01;

    mapping(bytes32 => incentiveDescription) public bounty;

    /// @notice Verify a message's authenticity.
    /// @dev Should be overwritten by the specific messaging protocol verification structure.
    function _verifyMessage() virtual internal;

    /// @notice Send the message to the messaging protocol.
    /// @dev Should be overwritten to send a message using the specific messaging protocol.
    function _sendMessage(bytes32 destinationIdentifier, bytes32 target, bytes memory message) virtual internal;

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by other contracts
    function escrowMessage(bytes32 destinationIdentifier, bytes32 target, bytes calldata message, incentiveDescription calldata incentive) external payable returns(uint256) {
        
        // Compute incentive metrics.
        uint256 deliveryGas = incentive.minGasDelivery * incentive.priceOfDeliveryGas;
        uint256 ackGas = incentive.minGasAck * incentive.priceOfDeliveryGas;
        uint256 sum = deliveryGas + ackGas;
        // Check that the provided gas is sufficient and refund the rest
        if (msg.value < sum) revert NotEnoughGasProvided(sum, msg.value);
        // Verify that the incentive structure is correct.
        if (incentive.totalIncentive != sum) revert NotEnoughGasProvided(incentive.totalIncentive, sum);
        if (sum == 0) revert ZeroIncentiveNotAllowed();

        // Prepare to store incentive
        bytes32 messageIdentifier = keccak256(message);
        if (bounty[messageIdentifier].totalIncentive != 0) revert MessageAlreadyBountied();
        bounty[messageIdentifier] = incentive;

        bytes memory paddedMessage = abi.encodePacked(
            bytes1(0x00),
            msg.sender,
            message
        );

        // Send message to messaging protocol
        _sendMessage(destinationIdentifier, target, paddedMessage);

        // Return excess incentives
        if (msg.value > sum) {
            payable(msg.sender).transfer(msg.value - sum);
            return msg.value - sum;
        }
        return 0;
    }

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by off-chain agents.
    function deliverMessage(bytes calldata message) external payable {
        // Verify message is valid
        _verifyMessage();

        bytes1 context = bytes1(message[0]);

        if (context == MESSAGEv1) {

        } else if (context == ACKv1) {

        } else {
            revert NotImplementedError();
        }
    }
}
