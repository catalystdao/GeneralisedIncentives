// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Address } from "openzeppelin/utils/Address.sol";

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "./interfaces/ICrossChainReceiver.sol";
import { Bytes65 } from "./utils/Bytes65.sol";
import { CTX_SOURCE_TO_DESTINATION, CTX_DESTINATION_TO_SOURCE, CTX_TIMEDOUT_ON_DESTINATION } from "./MessagePayload.sol";
import "./MessagePayload.sol";


/**
 * @title Generalised Incentive Escrow
 * @author Cata labs Inc.
 * @notice Main logic for placing transparent incentives on message relaying.
 * This contract is intended to sit between an application and a cross-chain message protocol.
 * The goal is to overload the existing incentive scheme with one that is open to anyone.
 *
 * Each messaging protocol will have a respective implementation that understands how to send
 * and verify messages. There are 4 functions that an integration has to implement.
 * Any implementation of this contract, allows applications to deliver a message to ::submitMessage
 * along with the respective incentives. 
 * The integration (this contract) will handle transferring the message to the destination and
 * returning an ack from the destination to the integrating application.
 *
 * The incentive is released when an ack from the destination chain is delivered to this contract.
 *
 * Beyond making relayer incentives stronger, this contract also implements several quality of life features:
 * - Refund unused gas.
 * - Separate gas payments for call and ack.
 * - Simple implementation of new messaging protocols.
 *
 * Applications integration with Generalised Incentives have to be aware that Acks are replayable.
 */
abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow, Bytes65 {
    
    //--- Constants ---//

    /**
     * @notice If the message reverts on the destination chain,
     * 1 byte is prepended to the original message on ack. This is the byte.
     */
    bytes1 constant MESSAGE_REVERTED = 0xff;

    /** 
     * @notice If the original sender is not authorised on the application on the destination chain,
     * 1 byte is prepended to the original message on ack. This is the byte.
     */
    bytes1 constant NO_AUTHENTICATION = 0xfe;

    /** 
     * @notice If the message timed out on destination chain,
     * 1 byte is prepended to the original message on ack. This is the byte.
     */
    bytes1 constant MESSAGE_TIMED_OUT = 0xfd;

    /**
     * @notice If setRemoteImplementation is called with this as the destination implementation
     * (abi.encodePacked(DISABLE_ROUTE_IMPLEMENTATION)), then the route is permanently disabled
     * This is treated as a magic value so that incase an implementations treats abi.encodePacked(0x00)
     * as a valid destination (say address(0)).
     */
    bytes1 constant DISABLE_ROUTE_IMPLEMENTATION = 0x00;

    /**
     * @notice If a relayer or application provides an address that cannot accept gas and
     * the transfer fails the gas is sent here instead.
     * @dev This may not invoke any logic on receive() or be a proxy.
     */
    address immutable public SEND_LOST_GAS_TO;

    //--- Storage ---//
    
    /** 
     * @notice Get incentive description based on message context: messageIdentifier, fromApplication, and destChain
     * @dev fromApplication and destChain are required to fetch the bounty. Together they
     * match exactly 1 remote escrow implementation. As a result, this restricts the storage
     * slot's security to the security of the specified remote escrow implementation.
     */
    mapping(address fromApplication => mapping(bytes32 destChain => mapping(bytes32 messageIdentifier => IncentiveDescription))) _bounty;

    /** @notice A hash of the emitted message on receive such that we can emit a similar one. */
    mapping(bytes32 => mapping(bytes => mapping(bytes32 => bytes32))) _messageDelivered;

    // Maps applications to their escrow implementations.
    mapping(address => mapping(bytes32 => bytes)) public implementationAddress;
    mapping(address => mapping(bytes32 => bytes32)) public implementationAddressHash;

    //--- Virtual Functions ---//
    // To integrate a messaging protocol, a contract has to inherit this contract and implement 4 functions below.

    /** 
     * @notice Verifies the authenticity of a message.
     * @dev Should be overwritten by the specific messaging protocol verification structure.
     * onRecv. implementations should collect acks so _verifyPacket returns true after acks have been executed once.
     * @param messagingProtocolContext Some context that is useful for verifying the message.
     * It should not contain the message but instead verification context like signatures, header, etc.
     * Context may not be needed for verifying the message and can be prepended to rawMessage.
     * @param rawMessage Some kind of package, initially untrusted. Should contain the message as a slice
     * It may contain more than just the message, like signatures, headers, etc.
     *
     * @return sourceIdentifier The source chain identifier. A chainID, a channel ID, or similarly.
     * @return implementationIdentifier An identifier for the address that emitted the message.
     * @return message The emitted message as a calldata slice. Should not contain anything AMB specific
     * and should be the exact message as delivered to _sendPacket
     */
    function _verifyPacket(
        bytes calldata messagingProtocolContext,
        bytes calldata rawMessage
    ) virtual internal returns(
        bytes32 sourceIdentifier,
        bytes memory implementationIdentifier,
        bytes calldata message
    );

    /** 
     * @notice Deliver the message to the messaging protocol to generate a proof.
     * @dev Should be overwritten to send a message using the specific messaging protocol.
     * The function is allowed to claim native tokens (set costOfsendPacketInNativeToken). 
     * The function is allowed to take ERC20 tokens (transferFrom(msg.sender,...)) 
     * in which case set costOfsendPacketInNativeToken to 0.
     * @param destinationIdentifier The destination chain for the message.
     * @param destinationImplementation The destination escrow contract.
     * @param message The message. Contains relevant escrow context.
     * @param deadline A timestamp that the message should be delivered before. If the AMB does not natively
     * support a timeout on their messages this parameter should be ignored. If 0 is provided, parse it as MAX.
     * @return costOfsendPacketInNativeToken An additional cost to emitting messages in NATIVE tokens.
     */
    function _sendPacket(
        bytes32 destinationIdentifier,
        bytes memory destinationImplementation,
        bytes memory message, uint64 deadline
    ) virtual internal returns(uint128 costOfsendPacketInNativeToken);

    /**
     *  @notice A unique source identifier used to generate the message identifier.
     *  @dev Should generally be the same as the one set by the AMB such that we can verify messages with this identifier
     */
    function _uniqueSourceIdentifier() virtual internal view returns(bytes32 sourceIdentifier);

    /**
     * @notice The duration for which a proof is valid for. It may vary by destination.
     * @dev On checks, block.timestamp is added to the return of this function such that
     * block.timestamp + _proofValidPeriod > deadline.
     * If any deadline is valid, set to **0** instead of ~~type(uint64).max~~.
     * @param destinationIdentifier The destination chain identifier.
     * @return duration The maximum proof duration. Includes the time from message emitted (proof gen)
     * to message finalised.
     */
    function _proofValidPeriod(bytes32 destinationIdentifier) virtual internal view returns(uint64 duration);

    /**
     * @notice The duration for which a proof is valid for.
     * @dev On checks, block.timestamp is added to the return of this function such that
     * block.timestamp + _proofValidPeriod > deadline.
     * If 0, implies that any deadline is valid.
     * @param destinationIdentifier The destination chain identifier.
     * @return duration The maximum proof duration. Includes the time from message emitted (proof gen)
     * to message finalised.
     */
    function proofValidPeriod(bytes32 destinationIdentifier) external view returns(uint64 duration) {
        return duration = _proofValidPeriod(destinationIdentifier);
    }

    /**
     * @param sendLostGasTo It should only be set to an EOA or a contract that has no logic on receive nor be a proxy.
     * If no-one wants to take responsibility of the lost Ether, use a burn address (0xdead) instead of address(0). 
     */
    constructor(address sendLostGasTo) {
        if (sendLostGasTo == address(0)) revert SendLostGasToIsZero();
        SEND_LOST_GAS_TO = sendLostGasTo;
    }

    /**
     * @notice Generates a unique message identifier for a message
     * @dev The identifier should:
     *  - Be unique within a trusted ecosystem.
     *  - Be unique based on the sender such that applications can't be DoS'ed.
     *  - Contain the deadline for timeout validation.
     *  - Be unique over time: Use blocknumber or blockhash.
     *  - Be unique on the source chain: Use a unique destinationIdentifier.
     *  - Be unique on destination chain: Use a unique source identifier.
     *  - Depend on the message, for uniqueness & for timeouts.
     * Point 2 implies that applications are allowed to DoS themselves. To protect against this, applications
     * should include some user unique information, say include a user address.
     */
    function _getMessageIdentifier(
        address messageSender,
        uint64 deadline,
        uint256 blockNumber,
        bytes32 sourceIdentifier,
        bytes32 destinationIdentifier,
        bytes memory message
    ) view internal virtual returns(bytes32) {
        return keccak256(
            bytes.concat(
                bytes20(address(this)),
                bytes20(messageSender),
                bytes8(deadline),
                bytes32(blockNumber),
                sourceIdentifier, 
                destinationIdentifier,
                message
            )
        );
    }

    /**
     * @notice Generates a unique message identifier for a message
     * @dev Simplifies using _getMessageIdentifier raw by assuming what the inputs
     * to the other parameters should be.
     */
    function _getMessageIdentifier(
        uint64 deadline,
        bytes32 destinationIdentifier,
        bytes calldata message
    ) view internal virtual returns(bytes32) {
        return _getMessageIdentifier(
            msg.sender,
            deadline,
            block.number,
            _uniqueSourceIdentifier(),
            destinationIdentifier,
            message
        );
    }

    //--- Getter Functions ---//
    /**
     * @notice Returns the bounty associated with a specific messageIdentifier.
     * @param fromApplication The application that submitted the message.
     * @param destinationIdentifier The destination chain for the message.
     * @param messageIdentifier The message identifier for a specific bounty.
     * @return incentive The message incentive / bounty as read from memory. If refundGasTo is address(0), it has been claimed.
     */
    function bounty(address fromApplication, bytes32 destinationIdentifier, bytes32 messageIdentifier) external view returns(IncentiveDescription memory incentive) {
        return _bounty[fromApplication][destinationIdentifier][messageIdentifier];
    }

    /**
     * @notice Get the message statue through the an ack hash.
     * If the message hasn't been delivered yet it returns bytes32(0)
     * @param sourceIdentifier The source chain the message was emitted from.
     * @param sourceImplementationIdentifier The source escrow implementation that emitted the message.
     * @param messageIdentifier The message identifier of the message.
     * @return hasMessageBeenExecuted Hash of the ack message. If not ack, then bytes32(uint256(1)). If not
     * executed then bytes32(0).
     */
   function messageDelivered(
        bytes32 sourceIdentifier,
        bytes calldata sourceImplementationIdentifier,
        bytes32 messageIdentifier
    ) external view returns(bytes32 hasMessageBeenExecuted) {
        return _messageDelivered[sourceIdentifier][sourceImplementationIdentifier][messageIdentifier];
   }

    /**
     * @notice Sets the escrow implementation for a specific chain
     * @dev This can only be set once. When set, it cannot be changed.
     * This is to protect relayers as this could be used to fail acks.
     * @param destinationIdentifier An identifier for the destination chain. Varies from AMB.
     * @param implementation Implementation address. Encoding varies between AMBs.
     * You are not allowed to set a 0 length implementation address. Beaware that while some implementations
     * are valid for sending (say hex"0x01" which may be read as address(uint160(1))), they break acks / delivery.
     * If you want to disable a specific route, set implementation to hex"00" (DISABLE_ROUTE_IMPLEMENTATION).
     */
    function setRemoteImplementation(bytes32 destinationIdentifier, bytes calldata implementation) external virtual {
        if (implementationAddressHash[msg.sender][destinationIdentifier] != bytes32(0)) revert ImplementationAddressAlreadySet(
            implementationAddress[msg.sender][destinationIdentifier]
        );
        if (implementation.length == 0) revert NoImplementationAddressSet();

        implementationAddress[msg.sender][destinationIdentifier] = implementation;
        bytes32 _implementationHash = keccak256(implementation);
        implementationAddressHash[msg.sender][destinationIdentifier] = _implementationHash;

        emit RemoteImplementationSet(msg.sender, destinationIdentifier, _implementationHash, implementation);
    }

    //--- Public Endpoints ---//

    /**
     * @notice Increases the bounty for relaying messages
     * @dev It is not possible to increase the gas budget for a message. 
     * The increase should be paid and is generally:
     *      incentive.maxGasDelivery * deliveryGasPriceIncrease + incentive.maxGasAck * ackGasPriceIncrease
     * Value has to be provided exact.
     * 
     * @param messageIdentifier The message identifier of the message to increase the bounty price for.
     * @param deliveryGasPriceIncrease The INCREASE in the gas price of the delivery gas
     * @param ackGasPriceIncrease The INCREASE in the gas price of ack gas.
     */
    function increaseBounty(
        address fromApplication,
        bytes32 destinationIdentifier,
        bytes32 messageIdentifier,
        uint96 deliveryGasPriceIncrease,
        uint96 ackGasPriceIncrease
    ) external payable {
        // Find incentive scheme.
        IncentiveDescription storage incentive = _bounty[fromApplication][destinationIdentifier][messageIdentifier];
        if (incentive.refundGasTo == address(0)) revert MessageDoesNotExist();

        // Compute incentive metrics.
        uint128 maxDeliveryFee = incentive.maxGasDelivery * deliveryGasPriceIncrease;
        uint128 maxAckFee = incentive.maxGasAck * ackGasPriceIncrease;
        uint128 sum = maxDeliveryFee + maxAckFee;
        // Check that the provided gas is exact
        if (msg.value != sum) revert IncorrectValueProvided(sum, uint128(msg.value));

        uint96 newPriceOfDeliveryGas = incentive.priceOfDeliveryGas + deliveryGasPriceIncrease;
        uint96 newPriceOfAckGas = incentive.priceOfAckGas + ackGasPriceIncrease;
        // Update storage.
        incentive.priceOfDeliveryGas = newPriceOfDeliveryGas;
        incentive.priceOfAckGas = newPriceOfAckGas;

        // Emit the event with the increased values.
        emit BountyIncreased(
            messageIdentifier,
            newPriceOfDeliveryGas,
            newPriceOfAckGas
        );
    }

    /** 
     * @notice Set a bounty on a message and transfer the message to the messaging protocol.
     * @dev Called by applications. These application should ensure:
     *     1. incentive.maxGasAck is sufficient! Otherwise, an off-chain agent needs to re-submit the ack.
     *     2. incentive.maxGasDelivery is sufficient. Otherwise, the call will fail within the try - catch.
     *     3. The relay incentive is enough to get the message relayed within the expected time. If that is never, this check is not needed.
     * Furthermore, if the package times out there is no gas refund.
     * Sending too much value results in the excess being refunded to refundGasTo via a call. This may allow refundGasTo to throw the call.
     * @param destinationIdentifier 32 bytes that identifies the destination chain.
     * @param destinationAddress The destination application encoded in 65 bytes: First byte is the length and last 64 is the destination application.
     * @param message The message to be sent to the destination. Please ensure the message is block-unique.
     *     This means that you don't send the same message twice in a single block. If you need to do that, add a nonce or noise.
     * @param incentive The incentive to attach to the bounty. The price of this incentive has to be paid,
     * any excess is refunded to refundGasTo. (not msg.sender)
     * @param deadline After this date, do not allow relayers to execute the message on the destination chain. If set to 0, disable timeouts.
     * Not all AMBs may support disabling the deadline. If acks are required it is recommended to set the deadline sometime in the future.
     * Note, it may still take a significant amount of time to bring back the timeout.
     * @return gasRefund The amount of excess gas that was paid to this call. The app should handle the excess.
     * @return messageIdentifier An unique identifier for a message.
     */
    function submitMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) checkBytes65Address(destinationAddress) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        // Valid refund to.
        if (incentive.refundGasTo == address(0)) revert RefundGasToIsZero();

        // Check that the application has set a destination implementation by checking if the length of the destinationImplementation entry is not 0.
        bytes memory destinationImplementation = implementationAddress[msg.sender][destinationIdentifier];
        if (destinationImplementation.length == 0) revert NoImplementationAddressSet();
        if (destinationImplementation.length == 1 && destinationImplementation[0] == DISABLE_ROUTE_IMPLEMENTATION) revert RouteDisabled();

        // Check that the deadline is lower than the AMB specification.
        unchecked {
            // Timestamps do not overflow in uint64 within reason.
            uint64 ambMaxDeadline = _proofValidPeriod(destinationIdentifier);
            if (ambMaxDeadline != 0 && deadline == 0) revert DeadlineTooLong(ambMaxDeadline, 0);
            if (ambMaxDeadline != 0 && deadline > uint64(block.timestamp) + ambMaxDeadline) revert DeadlineTooLong(uint64(block.timestamp) + ambMaxDeadline, deadline);
            // Check that the deadline is in the future = not (block.timestamp < deadline) = block.timestamp >= deadline.
            if (deadline != 0 && block.timestamp >= deadline) revert DeadlineInPast(uint64(block.timestamp), deadline);
        }

        // Prepare to store incentive
        messageIdentifier = _getMessageIdentifier(
            deadline,
            destinationIdentifier,
            message
        );
        // Store the bounty, get the sum to refunding excess later.
        uint128 sum = _setBounty(msg.sender, destinationIdentifier, messageIdentifier, incentive);

        // Add escrow context to the message.
        bytes memory messageWithContext = bytes.concat(
            bytes1(CTX_SOURCE_TO_DESTINATION),      // This is a sendPacket intended for the _destination_
            bytes32(messageIdentifier),             // A unique message identifier.
            convertEVMTo65(msg.sender),             // Original sender / application.
            destinationAddress,                     // The address to deliver the provided message to.
            bytes8(uint64(deadline)),
            bytes6(incentive.maxGasDelivery),       // The delivery gas limit, to enforce on the destination.
            message                                 // The message to deliver to the destination.
        );

        // Emit the event for off-chain relayers.
        emit BountyPlaced(
            destinationImplementation,
            destinationIdentifier,
            messageIdentifier,
            incentive
        );

        // Bounty is emitted before event to standardized with the other event before sending message scheme.

        // Send message to messaging protocol
        // This call will collect payments for sending the message. It can be in any token but if it is in 
        // native gas, it should return the amount it took.
        uint128 costOfsendPacketInNativeToken = _sendPacket(
            destinationIdentifier,
            destinationImplementation,
            messageWithContext,
            deadline
        );
        // Add the cost of the send message.
        sum += costOfsendPacketInNativeToken;

        // Check that the provided gas is sufficient. The refund will be sent later.
        if (msg.value < sum) revert NotEnoughGasProvided(sum, uint128(msg.value));


        // Return excess incentives to the user (found from incentive.refundGasTo).
        unchecked {
            if (msg.value > sum) {
                // We know: msg.value > sum, thus msg.value - sum > 0.
                gasRefund = msg.value - sum;
                // Send the refund to the refund address.
                Address.sendValue(payable(incentive.refundGasTo), uint256(gasRefund));
                return (gasRefund, messageIdentifier);
            }
        }
        return (0, messageIdentifier);
    }

    /**
     * @notice Deliver a message & proof of validity.
     * @dev This function is intended to be called by off-chain agents.
     *  Please ensure that feeRecipient can receive gas token: EOA or implements fallback() / receive() with no logic.
     *  Likewise for any non-evm chains. Otherwise the message fails (ack) or the relay payment is lost (deliver).
     *  You need to pass in incentive.maxGas(Delivery|Ack) + messaging protocol dependent buffer, otherwise this call might fail.
     *
     * OnReceive implementations should make _verifyPacket revert. The result is that this function is disabled.
     * Though this function is _virtual_ so feel free to override.
     * @param messagingProtocolContext Additional context required to verify the message by the messaging protocol.
     * @param rawMessage A messaging protocol message, including the message as it was sent as a slice.
     * @param feeRecipient An identifier for the the fee recipient. The identifier should identify the relayer on the source chain.
     *  For EVM (and this contract as a source), use the bytes32 encoded address. For other VMs you might have to register your address.
     */
    function processPacket(
        bytes calldata messagingProtocolContext,
        bytes calldata rawMessage,
        bytes32 feeRecipient
    ) external virtual payable {
        uint256 gasLimit = gasleft();  // uint256 is used here instead of uint48, since there is no advantage to uint48 until after we calculate the difference.
        if (feeRecipient == bytes32(0)) revert FeeRecipientIsZero();

        // Verify that the message is authentic and remove potential context that the messaging protocol added to the message.
        (bytes32 chainIdentifier, bytes memory implementationIdentifier, bytes calldata message) = _verifyPacket(messagingProtocolContext, rawMessage);

        // Figure out if this is deliver or ack.
        uint128 cost = 0;
        bytes1 context = bytes1(message[0]);
        if (context == CTX_SOURCE_TO_DESTINATION) {
            bytes memory receiveAckWithContext = _handleMessage(chainIdentifier, implementationIdentifier, message, feeRecipient, gasLimit);

            // The cost management is made by _sendPacket so we don't have to check if enough gas has been provided.
            cost = _sendPacket(chainIdentifier, implementationIdentifier, receiveAckWithContext, 0);
        } else if (context == CTX_DESTINATION_TO_SOURCE) {
            // Notice that sometimes ack actually handles deadlines which have been passed.
            // However, these are much different from "timeouts".
            _handleAck(chainIdentifier, implementationIdentifier, message, feeRecipient, gasLimit);
        } else if (context == CTX_TIMEDOUT_ON_DESTINATION) {
            // Verify that the timeout is valid.
            // Anyone is able to not only get here but also control the inputs to this code section
            // This logic is not protected by us controlling the logic for the roundtrip.
            // Instead, we need to authenticate the whole message:
            (bytes32 messageIdentifier, address fromApplication, bytes calldata applicationMessage) = _verifyTimeout(chainIdentifier, implementationIdentifier, message);

            // Now that we have the verified the inputs, we can actually use them. Execute the timeout:
            _handleTimeout(chainIdentifier, implementationIdentifier, messageIdentifier, fromApplication, applicationMessage, feeRecipient, gasLimit);
        } else {
            revert NotImplementedError();
        }

        // Check if there is a mismatch between the cost and the value of the message.
        if (uint128(msg.value) != cost) {
            if (uint128(msg.value) > cost) {
                // Send the unused gas back to the the user.
                Address.sendValue(payable(msg.sender), msg.value - uint256(cost));
                return;
            }
            // => uint128(msg.value) < cost, so revert.
            revert NotEnoughGasProvided(uint128(msg.value), cost);
        }
    }

    //--- Internal Functions ---//

    /**
     * @notice Handles messages deliveries (SOURCE_TO_DESTINATION)
     */
    function _handleMessage(
        bytes32 sourceIdentifier,
        bytes memory sourceImplementationIdentifier,
        bytes calldata message,
        bytes32 feeRecipient,
        uint256 gasLimit
    ) internal returns(bytes memory receiveAckWithContext) {
        // Ensure message is unique and can only be execyted once
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);

        // The 3 next lines act as a reentry guard, so this call doesn't have to be protected by reentry.
        // We will re-set _messageDelivered[messageIdentifier] again later as the hash of the ack, however, we need re-entry protection
        // so applications don't try to claim incentives multiple times.
        bytes32 messageState = _messageDelivered[sourceIdentifier][sourceImplementationIdentifier][messageIdentifier];
        if (messageState != bytes32(0)) revert MessageAlreadySpent();
        // This is where the "magic-byte" of bytes32(uint256(1)) comes from. Generally, it should always be overwritten by
        // an ack hash.
        _messageDelivered[sourceIdentifier][sourceImplementationIdentifier][messageIdentifier] = bytes32(uint256(1));

        // Prepare to deliver the message to application.
        // We need toApplication to check if the source implementation is valid
        // and we opportunistic decode fromApplication since it is needed in all cases.
        address toApplication = address(bytes20(message[CTX0_TO_APPLICATION_START_EVM:CTX0_TO_APPLICATION_END])); 
        bytes calldata fromApplication = message[FROM_APPLICATION_LENGTH_POS:FROM_APPLICATION_END];

        // Check if the message is valid. This includes:
        // - Checking if the sender is valid.
        // - Checking if the message has expired.

        bytes memory acknowledgement;

        bytes32 expectedSourceImplementationHash = implementationAddressHash[toApplication][sourceIdentifier];
        // Check that the application allows the source implementation.
        // This is not the case when another implementation calls this contract from the source chain.
        // This could be a mistake, send back an ack with the relevant information.
        if (expectedSourceImplementationHash != keccak256(sourceImplementationIdentifier)) {
            // If they are different, return send a failed message back with NO_AUTHENTICATION.
            acknowledgement = bytes.concat(
                NO_AUTHENTICATION,
                message[CTX0_MESSAGE_START: ]
            );

            // Encode a new message to send back. This lets the relayer claim their payment.
            receiveAckWithContext = bytes.concat(
                bytes1(CTX_DESTINATION_TO_SOURCE),  // Context
                messageIdentifier,  // message identifier
                fromApplication,
                feeRecipient,
                bytes6(uint48(gasLimit - gasleft())),  // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
                bytes8(uint64(block.timestamp)),  // If this overflows, it is fine. It is used in conjunction with a delta.
                acknowledgement
            );

            // Store a hash of the acknowledgement so we can later retry the ack if the ack proofs expires / becomes invalid.
            _messageDelivered[sourceIdentifier][sourceImplementationIdentifier][messageIdentifier] = keccak256(receiveAckWithContext);

            // Message has been delivered and shouldn't be executed again.
            emit MessageDelivered(sourceImplementationIdentifier, sourceIdentifier, messageIdentifier);
            return receiveAckWithContext;
        }

        // Check that if the deadline has been set (deadline != 0). If the deadline has been set,
        // check if the current timestamp is beyond the deadline and return MESSAGE_TIMED_OUT if it is.
        uint64 deadline = uint64(bytes8(message[CTX0_DEADLINE_START:CTX0_DEADLINE_END]));
        if (deadline != 0 && deadline < block.timestamp) {
            acknowledgement = bytes.concat(
                MESSAGE_TIMED_OUT,
                message[CTX0_MESSAGE_START: ]
            );

            // Encode a new message to send back. This lets the relayer claim their payment.
            // Incase of timeouts, we give all of the gas.
            receiveAckWithContext = bytes.concat(
                bytes1(CTX_DESTINATION_TO_SOURCE),  // Context
                messageIdentifier,  // message identifier
                fromApplication,
                feeRecipient,
                bytes6(uint48(2**47)),  // We set the gas spent as max. Why 2**47 instead of maxGasDelivery? 2**47 is only 1 high bit and it saves gas. Furthermore, min(2**47, maxGasDelivery) is checked on the source.
                bytes8(uint64(block.timestamp)),  // If this overflows, it is fine. It is used in conjunction with a delta.
                acknowledgement
            );

            // Store a hash of the acknowledgement so we can later retry a potentially invalid ack proof.
            _messageDelivered[sourceIdentifier][sourceImplementationIdentifier][messageIdentifier] = keccak256(receiveAckWithContext);

            // Message has been delivered and shouldn't be executed again.
            emit MessageDelivered(sourceImplementationIdentifier, sourceIdentifier, messageIdentifier);
            return receiveAckWithContext;
        }

        // Load the max gas.
        uint48 maxGas = uint48(bytes6(message[CTX0_MAX_GAS_LIMIT_START:CTX0_MAX_GAS_LIMIT_END]));

        // Execute call to application. Gas limit is set explicitly to ensure enough gas has been sent.

        // This call might fail because the abi.decode of the return value can fail. It is too gas costly to check co full correctness 
        // of the returned value and then error if decoding is not possible.
        // As a result, relayers needs to simulate the tx. If the call fails, then they should blacklist the message.
        // The call will only fall if the application doesn't expose receiveMessage or captures the message via a fallback. 
        // As a result, if message delivery once executed, then it will always execute.
        try ICrossChainReceiver(toApplication).receiveMessage{gas: maxGas}(sourceIdentifier, messageIdentifier, fromApplication, message[CTX0_MESSAGE_START: ])
        returns (bytes memory ack) {
            acknowledgement = ack;
        } catch (bytes memory /* err */) {
            // Check that enough gas was provided to the application. For further documentation of this statement, check
            // the long description on ack. TLDR: The relayer can cheat the application by providing less gas
            // but this statement ensures that if they try to do that, then it will fail (assuming the application reverts).
            if(gasleft() < maxGas * 1 / 63) revert NotEnoughGasExecution();

            // Send the message back if the execution failed.
            // This lets you store information in the message that you can trust gets returned.
            // (You just have to understand that the status is appended as the first byte.)
            acknowledgement = bytes.concat(
                MESSAGE_REVERTED,
                message[CTX0_MESSAGE_START: ]
            );
        }
        
        // Encode a new message to send back. This lets the relayer claim their payment.
        receiveAckWithContext = bytes.concat(
            bytes1(CTX_DESTINATION_TO_SOURCE), // Context
            messageIdentifier,  // message identifier
            fromApplication,
            feeRecipient,
            bytes6(uint48(gasLimit - gasleft())),  // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
            bytes8(uint64(block.timestamp)),  // If this overflows, it is fine. It is used in conjunction with a delta.
            acknowledgement
        );

        // Store a hash of the acknowledgement so we can later retry a potentially invalid ack proof.
        _messageDelivered[sourceIdentifier][sourceImplementationIdentifier][messageIdentifier] = keccak256(receiveAckWithContext);

        // Why is the messageDelivered event emitted before _sendPacket?
        // Because it lets us pop messageIdentifier from the stack. This avoid a stack limit reached error. 
        // Not optimal but okay-ish.

        // Emit event to inform relayers that the message has been delivered.
        emit MessageDelivered(sourceImplementationIdentifier, sourceIdentifier, messageIdentifier);
        // Send message to messaging protocol in processMessage.
        return receiveAckWithContext;
    }

    /**
     * @notice Handles ack messages (DESTINATION_TO_SOURCE).
     */
    function _handleAck(
        bytes32 destinationIdentifier,
        bytes memory destinationImplementationIdentifier,
        bytes calldata message,
        bytes32 feeRecipient,
        uint256 gasLimit
    ) internal {
        // Ensure the bounty can only be claimed once.
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));

        // The 3 (9, loading the variables out of storage fills a bit.) next lines act as a reentry guard,
        // so this call doesn't have to be protected by reentry.
        IncentiveDescription storage incentive = _bounty[fromApplication][destinationIdentifier][messageIdentifier];
        // Load all variables from storage onto the stack.
        uint48 maxGasDelivery = incentive.maxGasDelivery;
        uint48 maxGasAck = incentive.maxGasAck;
        address refundGasTo = incentive.refundGasTo;
        uint96 priceOfDeliveryGas = incentive.priceOfDeliveryGas;
        uint96 priceOfAckGas = incentive.priceOfAckGas;
        uint64 targetDelta = incentive.targetDelta;

        // Ensure the bounty can only be claimed once. This call is matched on the timeout side,
        // so it also ensures that an ack cannot be delivered if a timeout has been seen.
        if (refundGasTo == address(0)) revert MessageAlreadyAcked();
        delete _bounty[fromApplication][destinationIdentifier][messageIdentifier];  // The bounty cannot be accessed anymore.


        // First check if the application trusts the implementation on the destination chain.
        bytes32 expectedDestinationImplementationHash = implementationAddressHash[fromApplication][destinationIdentifier];
        // Check that the application approves the source implementation
        // For acks, this should always be the case except when a fraudulent applications sends a message to this contract.
        if (expectedDestinationImplementationHash != keccak256(destinationImplementationIdentifier)) revert InvalidImplementationAddress();

        // Deliver the ack to the application.
        // Ensure that if the call reverts it doesn't boil up.
        // We don't need any return values and don't care if the call reverts.
        // This call implies we need reentry protection.
        bytes memory payload = abi.encodeWithSignature("receiveAck(bytes32,bytes32,bytes)", destinationIdentifier, messageIdentifier, message[CTX1_MESSAGE_START: ]);
        bool success;
        assembly ("memory-safe") {
            // Because Solidity always create RETURNDATACOPY for external calls, even low-level calls where no variables are assigned,
            // the contract can be attacked by a so called return bomb. This incur additional cost to the relayer they aren't paid for.
            // To protect the relayer, the call is made in inline assembly.
            success := call(maxGasAck, fromApplication, 0, add(payload, 0x20), mload(payload), 0, 0)
            // This is what the call would look like non-assembly.
            // fromApplication.call{gas: maxGasAck}(
            //     abi.encodeWithSignature("receiveAck(bytes32,bytes32,bytes)", destinationIdentifier, messageIdentifier, message[CTX1_MESSAGE_START: ])
            // );
        }

        // External calls are allocated gas according roughly the following: min( gasleft * 63/64, gasArg ).
        // If there is no check against gasleft, then a relayer could potentially cheat by providing less gas.
        // Without a check, they only have to provide enough gas such that any further logic executees on 1/64 of gasleft
        // To ensure maximum compatibility with external tx simulation and gas estimation tools we will check a more complex
        // but more forgiving expression.
        // Before the call, there needs to be at least maxGasAck * 64/63 gas available. With that available, then
        // the call is allocated exactly min(+(maxGasAck * 64/63 * 63/64), maxGasAck) = maxGasAck.
        // If the call uses up all of the gas, then there must be maxGasAck * 64/63 - maxGasAck = maxGasAck * 1/63
        // gas left. It is sufficient to check that smaller limit rather than the larger limit.
        // Furthermore, if we only check when the call failed we don't have to read gasleft if it is not needed.
        unchecked {
            if (!success) if(gasleft() < maxGasAck * 1 / 63) revert NotEnoughGasExecution();
        }
        // Why is this better (than checking before)?
        // 1. We only have to check when the call failed. The vast majority of acks should not revert so it won't be checked.
        // 2. For the majority of applications it is going to be hold that: gasleft > rest of logic > maxGasAck * 1 / 63
        // and as such won't impact and execution/gas simuatlion/estimation libs.
        
        // Why is this worse?
        // 1. What if the application expected us to check that it got maxGasAck? It might assume that it gets
        // maxGasAck, when it turns out it got less it silently reverts (say by a low level call ala ours).

        // Get the gas used by the destination call.
        uint48 gasSpentOnDestination = uint48(bytes6(message[CTX1_GAS_SPENT_START:CTX1_GAS_SPENT_END]));

        (uint256 gasSpentOnSource, uint256 deliveryFee, uint256 ackFee) = _payoutIncentive(
            gasLimit,
            gasSpentOnDestination,
            maxGasDelivery,
            priceOfDeliveryGas,
            maxGasAck,
            priceOfAckGas,
            refundGasTo,
            address(uint160(uint256(bytes32(message[CTX1_RELAYER_RECIPIENT_START:CTX1_RELAYER_RECIPIENT_END])))),
            address(uint160(uint256(feeRecipient))),
            targetDelta,
            uint64(bytes8(message[CTX1_EXECUTION_TIME_START:CTX1_EXECUTION_TIME_END]))
        );

        emit MessageAcked(destinationImplementationIdentifier, destinationIdentifier, messageIdentifier);
        emit BountyClaimed(
            destinationImplementationIdentifier,
            destinationIdentifier,
            messageIdentifier,
            uint64(gasSpentOnDestination),
            uint64(gasSpentOnSource),
            uint128(deliveryFee),
            uint128(ackFee)
        );
    }

    /**
     * @notice Handles timeout messages.
     * @dev This function is very light. That is because it is intended to be used for both:
     * 1. Handling authentic timeouts from some AMBs.
     * 2. Handling returning timedout functions.
     * Before calling, check if the destination implementation is correct.
     */
    function _handleTimeout(
        bytes32 destinationIdentifier,
        bytes memory destinationImplementationIdentifier,
        bytes32 messageIdentifier,
        address fromApplication,
        bytes calldata applicationMessage,
        bytes32 feeRecipient,
        uint256 gasLimit
    ) internal {
        // The 3 (9, loading the variables out of storage fills a bit.) next lines act as a reentry guard,
        // so this call doesn't have to be protected by reentry.
        IncentiveDescription storage incentive = _bounty[fromApplication][destinationIdentifier][messageIdentifier];
        // Load all variables from storage onto the stack.
        uint48 maxGasDelivery = incentive.maxGasDelivery;
        uint48 maxGasAck = incentive.maxGasAck;
        address refundGasTo = incentive.refundGasTo;
        uint96 priceOfDeliveryGas = incentive.priceOfDeliveryGas;
        uint96 priceOfAckGas = incentive.priceOfAckGas;

        // Ensure the bounty can only be claimed once. This call is matched on the ack side,
        // so it also ensures that an ack cannot be delivered if a timeout has been seen.
        if (refundGasTo == address(0)) revert MessageAlreadyAcked();
        delete _bounty[fromApplication][destinationIdentifier][messageIdentifier];  // The bounty cannot be accessed anymore.

        // We delegate checking the if the destination implementation is correct to outside this contract.
        // This is done such that this function can be as light as possible.

        // Deliver the ack to the application.
        // Ensure that if the call reverts it doesn't boil up.
        // We don't need any return values and don't care if the call reverts.
        // This call implies we need reentry protection.
        bytes memory payload = abi.encodeWithSignature("receiveAck(bytes32,bytes32,bytes)", destinationIdentifier, messageIdentifier, bytes.concat(MESSAGE_TIMED_OUT, applicationMessage));
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
            if (!success) if(gasleft() < maxGasAck * 1 / 63) revert NotEnoughGasExecution();
        }

        (uint256 gasSpentOnSource, uint256 deliveryFee, uint256 ackFee) = _payoutIncentive(
            gasLimit,
            maxGasDelivery, // We set gas spent on destination as the entire allowance.
            maxGasDelivery,
            priceOfDeliveryGas,
            maxGasAck,
            priceOfAckGas,
            refundGasTo,
            address(uint160(uint256(feeRecipient))),
            address(uint160(uint256(feeRecipient))),
            0, // Disable target delta, since there is only 1 relayer.
            0
        );

        emit MessageTimedOut(destinationImplementationIdentifier, destinationIdentifier, messageIdentifier);
        emit BountyClaimed(
            destinationImplementationIdentifier,
            destinationIdentifier,
            messageIdentifier,
            uint64(maxGasDelivery),
            uint64(gasSpentOnSource),
            uint128(deliveryFee),
            uint128(ackFee)
        );
    }

    /**
     * @notice Verifies the input parameters are contained messageIdentifier and that the other arguments are valid.
     * The usage of this function is intended when no parameters of a message can be trusted and we have to verify them.
     * This is the case when we receive a timeout, as the timeout had to be emitted without any verification
     * on the remote chain, for us to then verify since we know when a message identifier is good AND how to compute it.
     *
     * @dev This function uses the fact that hash(a) == hash(b) IFF a == b. So if someone proposes b, we have hash(a)
     * then we can check if b == a by hashing b and comparing to a.
     * a is the initial state when the message was initiated and b is the proposed state from the timeout.
     *
     * When hash(a) is the message identifier, this allows us to verify authenticity by:
     *  1. The package is correctly formatted. The data within matches the message identifier.
     *  2. The remote implementation can verify that no package has previously been executed with that message identifier.
     *  3. If we check if the message identifier has a bounty, we must have emitted that message. (in _handleTimeout)
     */
    function _verifyTimeout(
        bytes32 destinationIdentifier,
        bytes memory implementationIdentifier,
        bytes calldata message
    ) internal view returns(bytes32 messageIdentifier, address fromApplication, bytes calldata applicationMessage) {
        // First check if the application trusts the implementation on the destination chain. This is very important
        // since the remote implementation NEEDS to check that the message hasn't been executed before the deadline
        // and if the message get relayed post deadline, then it should never arrive at the application.
        // Without those checks the whole concept of timeouts doesn't matter
        fromApplication = address(uint160(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END])));
        bytes32 expectedDestinationImplementationHash = implementationAddressHash[fromApplication][destinationIdentifier];
        // Check that the application approves of the remote implementation.
        // For timeouts, this could fail because of fraudulent sender or bad data.
        if (expectedDestinationImplementationHash != keccak256(implementationIdentifier)) revert InvalidImplementationAddress();

        // Do we need to check deadline again?
        // Considering the cost: cheap, we will do it. In most instances it is not needed.
        // This is because we must expect the remote implementation to also do the check to save gas
        // since it is an obvious and valid check on the remote.
        uint64 deadline = uint64(bytes8(message[CTX2_DEADLINE_START:CTX2_DEADLINE_END]));
        if (deadline >= block.timestamp || deadline == 0) revert DeadlineNotPassed(deadline, uint64(block.timestamp));

        // The entirety of the incoming message is untrusted. So far we havn't done any verification of
        // the message but rather of the origin of the message.
        // As a result, we need to verify the rest of the message, specifically:
        // - MESSAGE_IDENTIFIER
        // - FROM_APPLICATION      \
        // - DEADLINE               \
        // - ORIGIN_BLOCK_NUMBER     > Message Identifier
        // - SOURCE_IDENTIFIER      /
        // - MESSAGE               /

        // We need to verify that the message identifier sent is correct because the messageIdentifier
        // should have been used to check if the message would have been executed before.
        // We can check if the message identifier is correct by checking the bounty. (See _handleTimeout)
        // However, we still need to check the rest of the information. The message identifier has been crafted
        // so it is dependent on the rest of the information we use.
        
        applicationMessage = message[CTX2_MESSAGE_START: ];

        // Lets compute the messageIdentifier based on the message.
        bytes32 computedMessageIdentifier = _getMessageIdentifier(
            fromApplication,
            deadline,
            uint256(bytes32(message[CTX2_ORIGIN_BLOCK_NUMBER_START:CTX2_ORIGIN_BLOCK_NUMBER_END])),
            _uniqueSourceIdentifier(),
            destinationIdentifier,
            applicationMessage
        );

        // Get the reference message identifier from the package. We need to verify this since it was used on the sending chain.
        messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        if (computedMessageIdentifier != messageIdentifier) revert InvalidTimeoutPackage(messageIdentifier, computedMessageIdentifier);
    }

    /** 
     * @notice Payout incentives to the relayers.
     * @dev Timeouts needs to set targetDelta == 0 to cut off logic.
     */
    function _payoutIncentive(
        uint256 gasLimit,
        uint48 gasSpentOnDestination,
        uint48 maxGasDelivery,
        uint96 priceOfDeliveryGas,
        uint48 maxGasAck,
        uint96 priceOfAckGas,
        address refundGasTo,
        address destinationFeeRecipient,
        address sourceFeeRecipient,
        uint64 targetDelta,
        uint64 messageExecutionTimestamp
    ) internal returns(uint256 gasSpentOnSource, uint256 deliveryFee, uint256 ackFee) {

        // Find the respective rewards for delivery and ack.
        uint256 actualFee; uint256 refund;
        unchecked {
            // gasSpentOnDestination * priceOfDeliveryGas < 2**48 * 2**96 = 2**144
            if (maxGasDelivery <= gasSpentOnDestination) gasSpentOnDestination = maxGasDelivery;  // If more gas was spent then allocated, then only use the allocation.
            deliveryFee = gasSpentOnDestination * priceOfDeliveryGas;  
            // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
            // gasLimit = gasleft() when less gas was spent, thus it is always larger than gasleft().
            gasSpentOnSource = gasLimit - gasleft();
            if (maxGasAck <= gasSpentOnSource) gasSpentOnSource = maxGasAck;  // If more gas was spent then allocated, then only use the allocation.
            // gasSpentOnSource * priceOfAckGas < 2**48 * 2**96 = 2**144
            ackFee = gasSpentOnSource * priceOfAckGas;  
            // deliveryFee + ackFee < 2**144 + 2**144 = 2**145
            actualFee = deliveryFee + ackFee;
            // (priceOfDeliveryGas * maxGasDelivery + priceOfDeliveryGas * maxGasAck) has been calculated before (escrowBounty) < (2**48 * 2**96) + (2**48 * 2**96) = 2**144 + 2**144 = 2**145
            uint256 maxDeliveryFee = maxGasDelivery * priceOfDeliveryGas;
            uint256 maxAckFee = maxGasAck * priceOfAckGas;
            uint256 maxFee = maxDeliveryFee + maxAckFee;
            refund = maxFee - actualFee;
        }

        // send is used to ensure this doesn't revert. ".transfer" could revert and block the ack from ever being delivered.
        if(!payable(refundGasTo).send(refund)) {
            payable(SEND_LOST_GAS_TO).transfer(refund);  // If we don't send the gas somewhere, the gas is lost forever.
        }

        // If both the destination relayer and source relayer are the same then we don't have to figure out which fraction goes to who. For timeouts, logic should end here.
        if (destinationFeeRecipient == sourceFeeRecipient) {
            payable(sourceFeeRecipient).transfer(actualFee);  // If this reverts, then the relayer that is executing this tx provided a bad input.
            return (gasSpentOnSource, deliveryFee, ackFee);
        }

        // If targetDelta is 0, then distribute exactly the rewards.
        if (targetDelta == 0) {
            // ".send" is used to ensure this doesn't revert. ".transfer" could revert and block the ack from ever being delivered.
            if(!payable(destinationFeeRecipient).send(deliveryFee)) {  // If this returns false, it implies that the transfer failed.
                // The result is that this contract still has deliveryFee. As a result, send it somewhere else.
                payable(SEND_LOST_GAS_TO).transfer(deliveryFee);  // If we don't send the gas somewhere, the gas is lost forever.
            }
            Address.sendValue(payable(sourceFeeRecipient), ackFee); // If this reverts, then the relayer that is executing this tx provided a bad input.
            return (gasSpentOnSource, deliveryFee, ackFee);
        }

        // Compute the reward distribution. We need the time it took to deliver the ack back.
        uint64 executionTime;
        unchecked {
            // Overflow is desired in this code chuck. It ensures that the code piece continues working
            // past the time when uint64 stops working. *As long as any timedelta is less than uint64.
            executionTime = uint64(block.timestamp) - messageExecutionTimestamp;
            // Check if the overflow (/underflow) was because block.timestamp < messageExecutionTimestamp rather
            // than because block.timestamp has overflowed and messageExecutionTimestamp has now.
            // We do this by checking if executionTime is greater than an unrealistic period of time.
            // 32768 days is chosen since that is the neatest value close to the uint32 limit: 49710 days.
            // If this is the cause, we must assume that block.timestamp was slightly less than messageExecutionTimestamp
            // and an overflow happened and the execution time was set significantly too large as a result.
            // If this is true, then the delivery was quick (based on all available information) and the source to destination
            // should get everything.
            if (executionTime > 32768 days) executionTime = 0;
        }
        // The incentive scheme is as follows: When executionTime = targetDelta then
        // the rewards are distributed as per the incentive spec. If the time is less, then
        // more incentives are given to the destination relayer while if the time is more, 
        // then more incentives are given to the sourceRelayer.
        uint256 forDestinationRelayer = deliveryFee;
        unchecked {
            // |executionTime - targetDelta| < |2**64 + 2**64| = 2**65
            int256 timeBetweenTargetAndExecution = int256(uint256(executionTime)) - int256(uint256(targetDelta));
            if (timeBetweenTargetAndExecution <= 0) {
                // Less time than target passed and the destination relayer should get a larger chunk.
                // targetDelta != 0, we checked for that.
                // max abs timeBetweenTargetAndExecution = | - targetDelta| = targetDelta
                //                    => ackFee * targetDelta < actualFee * targetDelta < 2**127 * 2**64 = 2**191
                forDestinationRelayer += ackFee * uint256(- timeBetweenTargetAndExecution) / targetDelta;
            } else { // timeBetweenTargetAndExecution > 0
                // More time than target passed and the ack relayer should get a larger chunk.
                // If more time than double the target passed, the ack relayer should get everything
                if (uint256(timeBetweenTargetAndExecution) < targetDelta) {
                    // targetDelta != 0, we checked for that. 
                    // max abs timeBetweenTargetAndExecution = targetDelta from previous
                    //                    => deliveryFee * targetDelta < actualFee * targetDelta < 2**127 * 2**64 = 2**191
                    forDestinationRelayer -= deliveryFee * uint256(timeBetweenTargetAndExecution) / targetDelta;
                } else { 
                    // timeBetweenTargetAndExecution > targetDelta === executionTime - targetDelta > targetDelta === executionTime > 2 * targetDelta
                    // This doesn't discourage relaying, since executionTime first begins counting once the destination call has been executed.
                    // As a result, this only encourages delivery of the ack.
                    forDestinationRelayer = 0;
                }
            }
        }
        // send is used to ensure this doesn't revert. ".transfer" could revert and block the ack from ever being delivered.
        if(!payable(destinationFeeRecipient).send(forDestinationRelayer)) {
            payable(SEND_LOST_GAS_TO).transfer(forDestinationRelayer);  // If we don't send the gas somewhere, the gas is lost forever.
        }
        uint256 forSourceRelayer;
        unchecked {
            // max forDestinationRelayer is deliveryFee + ackFee = actualFee => actualFee - forDestinationRelayer == 0
            // min forDestinationRelayer = 0 => actualFee - 0 = actualFee
            forSourceRelayer = actualFee - forDestinationRelayer;
        }
        Address.sendValue(payable(sourceFeeRecipient), forSourceRelayer); // If this reverts, then the relayer that is executing this tx provided a bad input.

        return (gasSpentOnSource, forDestinationRelayer, forSourceRelayer);
    }

    /** 
     * @notice Sets a bounty for a message
     * @dev Does not check if enough incentives have been provided, this is delegated as responsibility 
     * of the caller of this function.
     * @param fromApplication The application that called the contract. Should generally be msg.sender. Is used to separate storage between applications.
     * @param destinationIdentifier The destination chain. Combined with fromApplication, this specifics a unique remote escrow implementation.
     * @param messageIdentifier A unique identifier for the message. Is used to check if bounties have been paid, on ack and timeout.
     * @param incentive The incentive structure. ".refundGasTo" is not allowed to be address(0).
     *
     * @return sum The total cost of the bounty. It not checked against msg.value in this contract.
     */
    function _setBounty(
        address fromApplication,
        bytes32 destinationIdentifier,
        bytes32 messageIdentifier, 
        IncentiveDescription calldata incentive
    ) internal returns(uint128 sum) {
        if (_bounty[fromApplication][destinationIdentifier][messageIdentifier].refundGasTo != address(0)) revert MessageAlreadyBountied();
        // Compute incentive metrics.
        uint128 maxDeliveryFee = incentive.maxGasDelivery * incentive.priceOfDeliveryGas;
        uint128 maxAckFee = incentive.maxGasAck * incentive.priceOfAckGas;
        sum = maxDeliveryFee + maxAckFee;
        
        _bounty[fromApplication][destinationIdentifier][messageIdentifier] = incentive;
    }

    /**
     * @notice Allows anyone to re-execute an ack which didn't properly execute.
     * @dev No application should rely on this function. It should only be used incase an application has faulty logic. 
     * Example: Faulty logic results in wrong enforcement on gas limit => out of gas?
     *
     * This function allows replaying acks.
     *
     * For further parameter documentation, read processPacket.
     * @param messagingProtocolContext Argument that once made _verifyPacket pass on processPacket
     * @param rawMessage Argument that once made _verifyPacket pass on processPacket.
     */
    function recoverAck(
        bytes calldata messagingProtocolContext,
        bytes calldata rawMessage
    ) external {
        // onRecv. implementations should collect acks so _verifyPacket returns true after first execution of the ack.
        (bytes32 chainIdentifier,  bytes memory implementationIdentifier, bytes calldata message) = _verifyPacket(messagingProtocolContext, rawMessage);

        bytes1 context = bytes1(message[0]);
        
        // Only allow acks to do this. Normal messages are invalid after first execution.
        if (context == CTX_DESTINATION_TO_SOURCE) {
            bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
            address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
            if(_bounty[fromApplication][chainIdentifier][messageIdentifier].refundGasTo != address(0)) revert AckHasNotBeenExecuted();
            
            // check if the application trusts the implementation on the destination chain.
            bytes32 expectedDestinationImplementationHash = implementationAddressHash[fromApplication][chainIdentifier];
            if (expectedDestinationImplementationHash != keccak256(implementationIdentifier)) revert InvalidImplementationAddress();
            ICrossChainReceiver(fromApplication).receiveAck(chainIdentifier, messageIdentifier, message[CTX1_MESSAGE_START: ]);
            emit MessageAcked(implementationIdentifier, chainIdentifier, messageIdentifier);
        } else {
            revert NotImplementedError();
        }
    }

    /** 
     * @notice Emit a new ack message incase the proof for the old got lost.
     * This function is intended for manual usage in case the ack was critical to the application
     * and the ack proof expired.
     * @dev If an AMB controls the entire flow of the message, disable this function.
     * @param sourceIdentifier Which chain to send the ack to? Is checked against stored ack hash to ensure
     * the message can only be sent to the correct source chain.
     * @param implementationIdentifier Which escrow contract to send the ack to? Is checked against stored ack hash
     * to ensure the message can only be sent to the original implementation.
     * @param receiveAckWithContext The message as this contract delivered to _sendMessage via processMessage.
     */
    function reemitAckMessage(
        bytes32 sourceIdentifier,
        bytes calldata implementationIdentifier,
        bytes calldata receiveAckWithContext
    ) external payable virtual {
        // Has the package previously been executed? (otherwise timeout might be more appropriate)

        // Load the messageIdentifier from receiveAckWithContext.
        // This makes it slightly easier to retry messages.
        bytes32 messageIdentifier = bytes32(receiveAckWithContext[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);

        bytes32 storedAckHash = _messageDelivered[sourceIdentifier][implementationIdentifier][messageIdentifier];
        // First, check if there is actually an appropriate hash at the message identifier.
        // Then, check if the storedAckHash & the source target (sourceIdentifier & implementationIdentifier) matches the executed one.
        if (storedAckHash == bytes32(0) || storedAckHash != keccak256(receiveAckWithContext)) revert CannotRetryWrongMessage(storedAckHash, keccak256(receiveAckWithContext));

        // Send the package again.
        uint128 cost = _sendPacket(sourceIdentifier, implementationIdentifier, receiveAckWithContext, 0);

        // Check if there is a mismatch between the cost and the value of the message.
        if (uint128(msg.value) != cost) {
            if (uint128(msg.value) > cost) {
                // Send the unused gas back to the the user.
                Address.sendValue(payable(msg.sender), msg.value - uint256(cost));
                return;
            }
            revert NotEnoughGasProvided(uint128(msg.value), cost);
        }
    }

    /**
     * @notice This function will timeout a message.
     * If a message has been executed but the proof for the ack might have been lost
     * then the message can be retried.
     * If a message has not been executed and the message is beyond timeout, then it can be
     * timed out. The intended usecase for this function is the latter case AND when the proof is lost.
     * If the proof is intact, delivering the proof normally is safer.
     * @dev If an AMB has a native way to timeout messages, disable this function.
     * The reason why we don't verify that the message is contained within the message identifier
     * is because we don't know where the messageIdentifier was computed and don't know what hashing function was used
     * As a result, it is expected that the sender of this function checks for inclusion manually, otherwise they could
     * waste a lot of gas.
     * There is no reliable way to block this function such that it can't be called twice after a message has been timed out
     * since the content could we wrong or the proof may still exist.
     * @param sourceIdentifier The identifier for the source chain (where to send the message)
     * @param implementationIdentifier The address of the source generalisedIncentives that emitted the original message
     * @param originBlockNumber The block number when the message was originally emitted. 
     * Note that for some L2 this could be the block number of the underlying chain. 
     * Regardless: It is the same block number that originally generated themessage identifier.
     * @param message Original Generalised Incentives message
     */
    function timeoutMessage(
        bytes32 sourceIdentifier,
        bytes calldata implementationIdentifier,
        uint256 originBlockNumber,
        bytes calldata message
    ) external payable virtual {
        //! When reading this function, it is important to remember that 'message' is
        // entirely untrusted. We do no verification on it. As a result, we shouldn't
        // trust any data within it. It is first when this message hits the source chain we can begin to verify data.

        // Check that at least the context is set correctly.
        if (message[CONTEXT_POS] != CTX_SOURCE_TO_DESTINATION) revert MessageHasInvalidContext();

        // Get the message identifier from the message.
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        // Read the status of the package at MessageIdentifier.
        bytes32 storedAckHash = _messageDelivered[sourceIdentifier][implementationIdentifier][messageIdentifier];
        // If has already been processed, then don't allow timeouting the message. Instead, it should be retried.
        if (storedAckHash != bytes32(0)) revert MessageAlreadyProcessed();
        // This also protects a relayer that delivered a timedout message.
        // ! It could still be that someone delivers the "true" message along with the proof after this has been emitted!
        // As a result, the above check only ensures that if the message properly arrives, then this cannot be called afterwards.
        // ensuring that the original relayer isn't cheated.
        // When the message arrives, the usual incentive check ensures only 1 message can arrive. Since the incentive check is based on
        // messageIdentifier, we need to verify it.
        // Remember, the messageIdentifier is actually untrusted. So it is trivial to pass the above check. However, any way to pass
        // the above check fraudulently would result in messageIdentifier being wrong and unable to be reproduced on the source chain.

        // Load the deadline from the message.
        uint64 deadline = uint64(bytes8(message[CTX0_DEADLINE_START:CTX0_DEADLINE_END]));

        // Check that the deadline has passed AND that there is no opt out.
        // This isn't a strong check but if a relayer is honest, then it can be used as a sanity check.
        // This protects against emitting rouge messages of timeout before the message has had a time to execute IF deadline belong to messageIdentifier.
        if (deadline == 0 || deadline >= block.timestamp) revert DeadlineNotPassed(deadline, uint64(block.timestamp));

        // Reconstruct message
        bytes memory receiveAckWithContext = bytes.concat(
            CTX_TIMEDOUT_ON_DESTINATION,
            messageIdentifier,
            message[FROM_APPLICATION_LENGTH_POS:FROM_APPLICATION_END],
            bytes8(deadline),
            bytes32(originBlockNumber),
            message[CTX0_MESSAGE_START: ]
        );

        // To maintain a common implementation language, emit our event before message.
        emit TimeoutInitiated(implementationIdentifier, sourceIdentifier, messageIdentifier);

        // Send the message
        uint128 cost = _sendPacket(
            sourceIdentifier,
            implementationIdentifier,
            receiveAckWithContext,
            0
        );

        // Check if there is a mismatch between the cost and the value of the message.
        if (uint128(msg.value) != cost) {
            if (uint128(msg.value) > cost) {
                // Send the unused gas back to the the user.
                Address.sendValue(payable(msg.sender), msg.value - uint256(cost));
                return;
            }
            revert NotEnoughGasProvided(uint128(msg.value), cost);
        }
    }
}
