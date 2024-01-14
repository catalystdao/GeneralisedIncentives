// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "./IncentivizedMessageEscrow.sol";
import "./MessagePayload.sol";

/**
 * @title Generalised Incentive Escrow Extended with a timeout
 * @author Alexander @ Catalyst
 * @notice Adds another message handler specialised for timeouts.
 * These messages have no execution on the destination chain and as such
 * they arrive without any of the execution context from the destination chain.
 * This is an issue, since the timeout message cannot be directly given to
 * _handleAck. Instead a seperate handler is created to handle these "anomalies".
 */
abstract contract IMETimeoutExtension is IncentivizedMessageEscrow {

    constructor(address sendLostGasTo) IncentivizedMessageEscrow(sendLostGasTo) {}

    /**
     * @notice Handles timeout messages.
     * @dev Is very similar to _handleAck
     */
    function _handleTimeout(bytes32 destinationIdentifier, bytes calldata message, bytes32 feeRecipitent, uint256 gasLimit) internal {
        // Ensure the bounty can only be claimed once.
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);

        // The 3 (9, loading the variables out of storage fills a bit.) next lines act as a reentry guard,
        // so this call doesn't have to be protected by reentry.
        IncentiveDescription storage incentive = _bounty[messageIdentifier];
        // Load all variables from storage onto the stack.
        uint48 maxGasDelivery = incentive.maxGasDelivery;
        uint48 maxGasAck = incentive.maxGasAck;
        address refundGasTo = incentive.refundGasTo;
        uint96 priceOfDeliveryGas = incentive.priceOfDeliveryGas;
        uint96 priceOfAckGas = incentive.priceOfAckGas;
        if (refundGasTo == address(0)) revert MessageAlreadyAcked();
        delete _bounty[messageIdentifier];  // The bounty cannot be accessed anymore.

        address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));

        // We don't have to check if the destination implementation is as expected, since timeouts can only come from this contract.

        // Deliver the ack to the application.
        // Ensure that if the call reverts it doesn't boil up.
        // We don't need any return values and don't care if the call reverts.
        // This call implies we need reentry protection.
        bytes memory payload = abi.encodeWithSignature("receiveAck(bytes32,bytes32,bytes)", destinationIdentifier, messageIdentifier, abi.encodePacked(bytes1(0xfd), message[CTX0_MESSAGE_START: ]));
        bool success;
        assembly ("memory-safe") {
            // Because Solidity always create RETURNDATACOPY for external calls, even low-level calls where no variables are assigned,
            // the contract can be attacked by a so called return bomb. This incur additional cost to the relayer they aren't paid for.
            // To protect the relayer, the call is made in inline assembly.
            success := call(maxGasAck, fromApplication, 0, add(payload, 0x20), mload(payload), 0, 0)
            // This is what the call would look like non-assembly.
            // fromApplication.call{gas: maxGasAck}(
            //     abi.encodeWithSignature("receiveAck(bytes32,bytes32,bytes)", destinationIdentifier, messageIdentifier, abi.encodePacked(bytes1(0xfd), message[CTX0_MESSAGE_START: ]))
            // );
        }
        // Check that enough gas was provided to the application. For further documentation of this statement, check
        // the long description on ack. TLDR: The relayer can cheat the application by providing less gas
        // but this statement ensures that if they try to do that, then it will fail (assuming the application reverts).
        unchecked {
            if (!success) if(gasleft() < maxGasAck * 1 / 63) revert NotEnoughGasExeuction();
        }

        // Set the gas used on the destination to 15%
        uint256 gasSpentOnDestination = maxGasDelivery * 15 / 100;

        // Find the respective rewards for delivery and ack.
        uint256 deliveryFee; uint256 ackFee; uint256 sumFee; uint256 refund; uint256 gasSpentOnSource;
        unchecked {
            deliveryFee = gasSpentOnDestination * priceOfDeliveryGas;  
            // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
            // gasLimit = gasleft() when less gas was spent, thus it is always larger than gasleft().
            gasSpentOnSource = gasLimit - gasleft();
            if (maxGasAck <= gasSpentOnSource) gasSpentOnSource = maxGasAck;  // If more gas was spent then allocated, then only use the allocation.
            // gasSpentOnSource * priceOfAckGas < 2**48 * 2**96 = 2**144
            ackFee = gasSpentOnSource * priceOfAckGas;  
            // deliveryFee + ackFee < 2**144 + 2**144 = 2**145
            sumFee = deliveryFee + ackFee;
            // (priceOfDeliveryGas * maxGasDelivery + priceOfDeliveryGas * maxGasAck) has been caculated before (escrowBounty) < (2**48 * 2**96) + (2**48 * 2**96) = 2**144 + 2**144 = 2**145
            uint256 maxDeliveryGas = maxGasDelivery * priceOfDeliveryGas;
            uint256 maxAckGas = maxGasAck * priceOfAckGas;
            uint256 maxSum = maxDeliveryGas + maxAckGas;
            refund = maxSum - sumFee;
        }
        address sourceFeeRecipitent = address(uint160(uint256(feeRecipitent)));

        // ".send" is used to ensure this doesn't revert. ".transfer" could revert and block the ack from ever being delivered.
        if(!payable(refundGasTo).send(refund)) {  // If this returns false, it implies that the transfer failed.
            // The result is that this contract still has deliveryFee. As a result, send it somewhere else.
            payable(SEND_LOST_GAS_TO).transfer(refund);  // If we don't send the gas somewhere, the gas is lost forever.
        }
        payable(sourceFeeRecipitent).transfer(ackFee + deliveryFee);  // If this reverts, then the relayer that is executing this tx provided a bad input.
        emit MessageTimedout(messageIdentifier);
        emit BountyClaimed(
            messageIdentifier,
            uint64(gasSpentOnDestination),
            uint64(gasSpentOnSource),
            uint128(0),
            uint128(ackFee + deliveryFee)
        );
    }
}
