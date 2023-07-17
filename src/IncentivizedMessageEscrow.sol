// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "./interfaces/ICrossChainReceiver.sol";
import { SourcetoDestination, DestinationtoSource } from "./MessagePayload.sol";
import { Bytes65 } from "./utils/Bytes65.sol";
import "./MessagePayload.sol";

/**
 * @title Generalised Incentive Escrow
 * @author Alexander @ Catalyst
 * @notice Places transparent incentives on relaying messages.
 * This contract is intended to sit between an application and a cross-chain message protocol.
 * The goal is to overload the existing incentive scheme with one which is open for anyone.
 *
 * Each messaging protocol will have a respective implementation which understands
 * how to send and verify messages. An integrating application shall deliver a message to escrowMessage
 * along with the respective incentives. This contract will then handle transfering the message to the
 * destination and carry an ack back from the destination to return to the integrating application.
 *
 * The incentive is released when an ack from the destination chain is delivered to this contract.
 *
 * Beyond making relayer incentives strong, this contract also implements several quality of life features:
 * - Refund unused gas.
 * - Seperate gas payments for call and ack.
 * - Simple implementation of new messaging protocols.
 */
abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow, Bytes65 {
    
    //--- Constants ---//

    /// @notice  If a swap reverts on the destination chain, 1 bytes is sent back instead. This is the byte.
    bytes1 constant public SWAP_REVERTED = 0xff;

    /// @notice If a relayer or application provides an address which cannot accept gas and the transfer fails
    /// the gas is sent here instead.
    address constant public SEND_LOST_GAS_TO = address(0);

    //--- Storage ---//
    mapping(bytes32 => IncentiveDescription) _bounty;

    mapping(bytes32 => bool) _spentMessageIdentifier;

    //--- Virtual Functions ---//
    // To integrate a messaging protocol, a contract has to inherit this contract and implement the below 3 functions.

    /// @notice Verify a message's authenticity.
    /// @dev Should be overwritten by the specific messaging protocol verification structure.
    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata rawMessage) virtual internal returns(bytes calldata message);

    /// @notice Send the message to the messaging protocol.
    /// @dev Should be overwritten to send a message using the specific messaging protocol.
    function _sendMessage(bytes32 destinationIdentifier, bytes memory message) virtual internal;

    /// @notice Generates a unique message identifier for a message
    /// @dev Should be overwritten. The identifier should:
    ///  - Be unique over time: Use blocknumber or blockhash
    ///  - Be unique on destination chain: Use a unique source identifier 
    ///  - Be unique on the source chain: Use a unique destinationIdentifier
    ///  - Depend on the message
    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) view internal virtual returns(bytes32);

    //--- Getter Functions ---//
    function bounty(bytes32 messageIdentifier) external view returns(IncentiveDescription memory incentive) {
        return _bounty[messageIdentifier];
    }

   function spentMessageIdentifier(bytes32 messageIdentifier) external view returns(bool hasMessageBeenExecuted) {
        return _spentMessageIdentifier[messageIdentifier];
   }

    //--- Public Endpoints ---//

    /**
     * @notice Increases the bounty for relaying messages
     * @dev It is not possible to increase the gas budget for a message. 
     */
    function increaseBounty(
        bytes32 messageIdentifier,
        uint96 deliveryGasPriceIncrease,
        uint96 ackGasPriceIncrease
    ) external payable {
        if (_bounty[messageIdentifier].refundGasTo == address(0)) revert MessageDoesNotExist();
        // Find incentive scheme.
        IncentiveDescription storage incentive = _bounty[messageIdentifier];

        // Compute incentive metrics.
        uint128 deliveryGas = incentive.maxGasDelivery * deliveryGasPriceIncrease;
        uint128 ackGas = incentive.maxGasAck * ackGasPriceIncrease;
        uint128 sum = deliveryGas + ackGas;
        // Check that the provided gas is exact
        if (msg.value != sum) revert NotEnoughGasProvided(sum, uint128(msg.value));

        // Update storage.
        incentive.priceOfDeliveryGas += deliveryGasPriceIncrease;
        incentive.priceOfAckGas += ackGasPriceIncrease;

        // Emit the event with the increased values.
        emit BountyIncreased(
            messageIdentifier,
            deliveryGasPriceIncrease,
            ackGasPriceIncrease
        );
    }

    /** 
     * @notice Set a bounty on a message and transfer the message to the messaging protocol.
     * @dev Called by other contracts.
     * Any integrating application should check:
     *     1. That incentive.maxGasAck is sufficient! Otherwise, an off-chain agent needs to re-submit the ack.
     *     2. That incentive.maxGasDelivery is sufficient. Otherwise, the call will fail within the try - catch.
     *     3. The relay incentive is enough to get the message relayed within the expected time. If that is never, this check is not needed.
     * @param destinationIdentifier 32 bytes which identifies the destination chain. The first 2 bytes are used for gas-saving context. 
     * @param destinationAddress The destination address encoded in 65 bytes: First byte is the length and last 64 is the destination address.
     * @param message The message to be sent to the destination. Please ensure the message is block-unique.
     *     This means that you don't send the same message twice in a single block.
     * @return gasRefund The amount of excess gas which was paid to this call. The app should handle the excess.
     * @return messageIdentifier An unique identifier for a message.
     */
    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive
    ) checkBytes65Address(destinationAddress) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        // Prepare to store incentive
        messageIdentifier = _getMessageIdentifier(
            destinationIdentifier,
            message
        );
        // Store the bounty, get the sum for later refunding excess.
        uint128 sum = _setBounty(messageIdentifier, incentive);

        // Add escrow context to the message.
        bytes memory messageWithContext = abi.encodePacked(
            bytes1(SourcetoDestination),    // This is a sendMessage,
            messageIdentifier,              // An unique identifier to recover identifier to recover 
            convertEVMTo65(msg.sender),     // Original sender
            destinationAddress,             // The address to deliver the (original) message to.
            incentive.maxGasDelivery,       // Send the gas limit to the other chain so we can enforce it
            message                         // The message to deliver to the destination.
        );

        // Send message to messaging protocol
        _sendMessage(
            destinationIdentifier,
            messageWithContext
        );

        // Emit the event for off-chain relayers.
        emit BountyPlaced(
            messageIdentifier,
            incentive
        );

        // Return excess incentives to the sender. 
        // TODO: DO we want to return the excess to incentive.refundGasTo instead? 
        // TODO: What if an application what to take the excess? Should they be allowed to do that?
        unchecked {
            if (msg.value > sum) {
                // We know: msg.value >= sum, thus msg.value - sum >= 0.
                gasRefund = msg.value - sum;
                payable(msg.sender).transfer(gasRefund);
                return (gasRefund, messageIdentifier);
            }
        }
        return (0, messageIdentifier);
    }

    /**
     * @notice Deliver a message which has been *signed* by a messaging protocol.
     * @dev This function is intended to be called by off-chain agents.
     *  Please ensure that feeRecipitent can receive gas token: Either it is an EOA or a implement fallback() / receive().
     *  Likewise for any non-evm chains. Otherwise the message fails (ack) or the relay payment is lost (call).
     *  You need to pass in incentive.maxGas(Delivery|Ack) + messaging protocol dependent buffer, otherwise this call fails. // TODO: Check
     * @param messagingProtocolContext Additional context required to verify the message by the messaging protocol.
     * @param rawMessage The raw message as it was emitted.
     * @param feeRecipitent The fee recipitent encoded in 65 bytes: First byte is the length and last 64 is the destination address.
     */
    function processMessage(
        bytes32 chainIdentifier,
        bytes calldata messagingProtocolContext,
        bytes calldata rawMessage,
        bytes calldata feeRecipitent
    ) checkBytes65Address(feeRecipitent) external {
        uint256 gasLimit = gasleft();  // uint256 is used here instead of uint48, since there is no advantage to uint48 until after we calculate the difference.

        // Verify that the message is authentic and remove potential context that the messaging protocol added to the message.
        bytes calldata message = _verifyMessage(chainIdentifier, messagingProtocolContext, rawMessage);

        // Figure out if this is a call or an ack.
        bytes1 context = bytes1(message[0]);
        if (context == SourcetoDestination) {
            _handleCall(chainIdentifier, message, feeRecipitent, gasLimit);
        } else if (context == DestinationtoSource) {
            _handleAck(chainIdentifier, message, feeRecipitent, gasLimit);
        } else {
            revert NotImplementedError();
        }
    }

    //--- Internal Functions ---//

    /**
     * @notice Handles call messages.
     */
    function _handleCall(bytes32 sourceIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint256 gasLimit) internal {
        // Ensure message is unique and can only be execyted once
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        bool messageState = _spentMessageIdentifier[messageIdentifier];
        if (messageState) revert MessageAlreadySpent();
        _spentMessageIdentifier[messageIdentifier] = true;


        // Deliver message to application.
        // Decode gas limit, application address and sending application.
        uint48 maxGas = uint48(bytes6(message[CTX0_MIN_GAS_LIMIT_START:CTX0_MIN_GAS_LIMIT_END]));
        address toApplication = address(bytes20(message[CTX0_TO_APPLICATION_START_EVM:CTX0_TO_APPLICATION_END])); 
        bytes calldata fromApplication = message[FROM_APPLICATION_LENGTH_POS:FROM_APPLICATION_END];
        // Execute call to application. Gas limit is set explicitly to ensure enough gas has been sent.

        // TODO: Optimise gas?
        (bool success, bytes memory acknowledgement) = toApplication.call{gas: maxGas}(
            abi.encodeWithSignature("receiveMessage(bytes32,bytes,bytes)", sourceIdentifier, fromApplication, message[CTX0_MESSAGE_START: ])
        );
        if (success) {
            // TODO: Optimise gas?
            acknowledgement = abi.decode(acknowledgement, (bytes));
        } else {
            acknowledgement = abi.encodePacked(SWAP_REVERTED);
        }


        // Encode a new message to send back. This lets the relayer claim their payment.
        bytes memory ackMessageWithContext = abi.encodePacked(
            bytes1(DestinationtoSource),    // This is a sendMessage
            messageIdentifier,              // message identifier
            fromApplication,
            feeRecipitent,
            uint48(gasLimit - gasleft()),   // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
            uint64(block.timestamp),        // If this overflows, it is fine. It is used in conjunction with a delta.
            acknowledgement
        );

        // Send message to messaging protocol
        _sendMessage(sourceIdentifier, ackMessageWithContext);

        // Message has been delivered and shouldn't be executed again.
        emit MessageDelivered(messageIdentifier);
    }

    /**
     * @notice Handles ack messages.
     */
    function _handleAck(bytes32 destinationIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint256 gasLimit) internal {
        // Ensure the bounty can only be claimed once.
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        IncentiveDescription memory incentive = _bounty[messageIdentifier];
        delete _bounty[messageIdentifier];  // The bounty cannot be accessed anymore.

        // Deliver the ack to the application.
        address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
        // Ensure that if the call reverts it doesn't boil up.  // TODO: Optimise gas?
        fromApplication.call{gas: incentive.maxGasAck}(
            abi.encodeWithSignature("ackMessage(bytes32,bytes)", destinationIdentifier, message[CTX1_MESSAGE_START: ])
        );

        // Get the gas used by the destination call.
        uint256 gasSpentOnDestination = uint48(bytes6(message[CTX1_GAS_SPENT_START:CTX1_GAS_SPENT_END]));

        // Find the respective rewards for delivery and ack.
        uint256 deliveryFee; uint256 ackFee; uint256 sumFee; uint256 refund; uint256 gasSpentOnSource;
        unchecked {
            // gasSpentOnDestination * incentive.priceOfDeliveryGas < 2**48 * 2**96 = 2**144
            if (incentive.maxGasDelivery <= gasSpentOnDestination) gasSpentOnDestination = incentive.maxGasDelivery;  // If more gas was spent then allocated, then only use the allocation.
            deliveryFee = gasSpentOnDestination * incentive.priceOfDeliveryGas;  
            // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
            // gasLimit = gasleft() when less gas was spent, thus it is always larger than gasleft().
            gasSpentOnSource = gasLimit - gasleft();
            if (incentive.maxGasAck <= gasSpentOnSource) gasSpentOnSource = incentive.maxGasAck;  // If more gas was spent then allocated, then only use the allocation.
            // gasSpentOnSource * incentive.priceOfAckGas < 2**48 * 2**96 = 2**144
            ackFee = gasSpentOnSource * incentive.priceOfAckGas;  
            // deliveryFee + ackFee < 2**144 + 2**144 = 2**145
            sumFee = deliveryFee + ackFee;
            // (incentive.priceOfDeliveryGas * incentive.maxGasDelivery + incentive.priceOfDeliveryGas * incentive.maxGasAck) has been caculated before (escrowBounty) < (2**48 * 2**96) + (2**48 * 2**96) = 2**144 + 2**144 = 2**145
            uint256 maxDeliveryGas = incentive.maxGasDelivery * incentive.priceOfDeliveryGas;
            uint256 maxAckGas = incentive.maxGasAck * incentive.priceOfAckGas;
            uint256 maxSum = maxDeliveryGas + maxAckGas;
            refund = maxSum - sumFee;
        }
        // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
        if(!payable(incentive.refundGasTo).send(refund)) {
            payable(SEND_LOST_GAS_TO).transfer(refund);  // If we don't send the gas somewhere, the gas is lost forever.
        }
        address destinationFeeRecipitent = address(bytes20(message[CTX1_RELAYER_RECIPITENT_START_EVM:CTX1_RELAYER_RECIPITENT_END]));
        // feeRecipitent is bytes65, an EVM address is the last 20 bytes.
        address sourceFeeRecipitent = address(bytes20(feeRecipitent[45:]));
        // If both the destination relayer and source relayer are the same then we don't have to figure out which fraction goes to who.
        if (destinationFeeRecipitent == sourceFeeRecipitent) {
            payable(sourceFeeRecipitent).transfer(sumFee);  // If this reverts, then the relayer that is executing this tx provided a bad input.
            emit MessageAcked(messageIdentifier);
            emit BountyClaimed(
                messageIdentifier,
                uint64(gasSpentOnDestination),
                uint64(gasSpentOnSource),
                uint128(sumFee),
                0
            );
            return;
        }

        uint64 targetDelta = incentive.targetDelta;
        // If targetDelta is 0, then distribute exactly the rewards.
        if (targetDelta == 0) {
            // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
            if(!payable(destinationFeeRecipitent).send(deliveryFee)) { // TODO: test
                payable(SEND_LOST_GAS_TO).transfer(refund);  // If we don't send the gas somewhere, the gas is lost forever.
            }
            payable(sourceFeeRecipitent).transfer(ackFee);  // If this reverts, then the relayer that is executing this tx provided a bad input.
            return;
        }
        // Compute the reward distribution. We need the time it took to deliver the ack back.
        uint64 executionTime;
        unchecked {
            // Underflow is desired in this code chuck. It ensures that the code piece continues working
            // past the time when uint64 stops working. *As long as any timedelta is less than uint64.
            executionTime = uint64(block.timestamp) - uint64(bytes8(message[CTX1_EXECUTION_TIME_START:CTX1_EXECUTION_TIME_END]));
        }
        // The incentive scheme is as follows: When executionTime = incentive.targetDelta then 
        // The rewards are distributed as per the incentive spec. If the time is less, then
        // more incentives are given to the destination relayer while if the time is more, 
        // then more incentives are given to the sourceRelayer.
        uint256 forDestinationRelayer = deliveryFee;
        unchecked {
            // |targetDelta - executionTime| < |2**64 + 2**64| = 2**65
            int256 timeBetweenTargetAndExecution = int256(uint256(executionTime))-int256(uint256(targetDelta));
            if (timeBetweenTargetAndExecution <= 0) {
                // Less time than target passed and the destination relayer should get a larger chunk.
                // targetDelta != 0, we checked for that. 
                // max abs timeBetweenTargetAndExecution = | - targetDelta| = targetDelta => ackFee * targetDelta < sumFee * targetDelta
                //  2**127 * 2**64 = 2**191
                forDestinationRelayer += ackFee * uint256(- timeBetweenTargetAndExecution) / targetDelta;
            } else {
                // More time than target passed and the ack relayer should get a larger chunk.
                // If more time than the target passed, the ack relayer should get everything.
                if (uint256(timeBetweenTargetAndExecution) < targetDelta) {
                    // targetDelta != 0, we checked for that. 
                    // max abs timeBetweenTargetAndExecution = targetDelta since we have the above check
                    // => deliveryFee * targetDelta < sumFee * targetDelta < 2**127 * 2**64 = 2**191
                    forDestinationRelayer -= deliveryFee * uint256(timeBetweenTargetAndExecution) / targetDelta;
                } else {
                    // This doesn't discourage relaying, since executionTime first begins counting once the destinaion call has been executed.
                    // As a result, this only encorages delivery of the ack.
                    forDestinationRelayer = 0;
                }
            }
        }
        // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
        if(!payable(destinationFeeRecipitent).send(forDestinationRelayer)) {
            payable(SEND_LOST_GAS_TO).transfer(refund);  // If we don't send the gas somewhere, the gas is lost forever.
        }
        uint256 forSourceRelayer;
        unchecked {
            // max forDestinationRelayer is deliveryFee + ackFee = sumFee => sumFee - forDestinationRelayer == 0
            // min forDestinationRelayer = 0 => sumFee - 0 = sumFee
            forSourceRelayer = sumFee - forDestinationRelayer;
        }
            payable(sourceFeeRecipitent).transfer(forSourceRelayer);  // If this reverts, then the relayer that is executing this tx provided a bad input.

        emit MessageAcked(messageIdentifier);
        emit BountyClaimed(
            messageIdentifier,
            uint64(gasSpentOnDestination),
            uint64(gasSpentOnSource),
            uint128(forDestinationRelayer),
            uint128(forSourceRelayer)
        );
    }


    /// @notice Sets a bounty for a message
   function _setBounty(
        bytes32 messageIdentifier, 
        IncentiveDescription calldata incentive
    ) internal returns(uint128 sum){
        if (_bounty[messageIdentifier].refundGasTo != address(0)) revert MessageAlreadyBountied();
        // Compute incentive metrics.
        uint128 deliveryGas = incentive.maxGasDelivery * incentive.priceOfDeliveryGas;
        uint128 ackGas = incentive.maxGasAck * incentive.priceOfAckGas;
        sum = deliveryGas + ackGas;
        // Check that the provided gas is sufficient. The refund will be sent later. (reentry? concern).
        if (sum == 0) revert ZeroIncentiveNotAllowed();
        if (msg.value < sum) revert NotEnoughGasProvided(sum, uint128(msg.value));
        
        _bounty[messageIdentifier] = incentive;
    }


    /// @notice Allows anyone to re-execute an ack which didn't properly execute.
    /// @dev No applciation should rely on this function. It should only be used in-case an
    /// application has faulty logic. 
    /// Example: Faulty logic results in wrong enforcement on gas limit => out of gas?
    function recoverAck(
        bytes32 chainIdentifier,
        bytes calldata messagingProtocolContext,
        bytes calldata message
    ) external {
        _verifyMessage(chainIdentifier, messagingProtocolContext, message);

        bytes1 context = bytes1(message[0]);
        
        // Only allow acks to do this. Normal messages are invalid after first execution.
        if (context == DestinationtoSource) {
            bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
            if(_bounty[messageIdentifier].refundGasTo != address(0)) revert AckHasNotBeenExecuted(); 

            address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
            ICrossChainReceiver(fromApplication).ackMessage(chainIdentifier, message[CTX1_MESSAGE_START: ]);

            emit MessageAcked(messageIdentifier);
        } else {
            revert NotImplementedError();
        }
    }
}
