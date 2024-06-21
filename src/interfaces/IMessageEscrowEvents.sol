// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IMessageEscrowStructs } from "./IMessageEscrowStructs.sol";

interface IMessageEscrowEvents {
    // Important notice for relayers. The implementations (sourceImplementation and destinationImplementation),
    // when indexed in events, the hash is in the topic not the actual implementation.
    event BountyPlaced(
        bytes indexed destinationImplementation, 
        bytes32 chainIdentifier,
        bytes32 indexed messageIdentifier,
        IMessageEscrowStructs.IncentiveDescription incentive
    );
    event MessageDelivered(bytes indexed sourceImplementation, bytes32 chainIdentifier, bytes32 indexed messageIdentifier);
    event MessageAcked(bytes destinationImplementation, bytes32 chainIdentifier, bytes32 messageIdentifier); // Not indexed since relayers can sort by BountyClaimed.
    event TimeoutInitiated(bytes sourceImplementation, bytes32 chainIdentifier, bytes32 messageIdentifier);
    event MessageTimedOut(bytes destinationImplementation, bytes32 chainIdentifier, bytes32 messageIdentifier); // Not indexed since relayers can sort by BountyClaimed.
    event BountyClaimed(
        bytes indexed destinationImplementation,
        bytes32 chainIdentifier,
        bytes32 indexed messageIdentifier,
        uint64 gasSpentOnDestination,
        uint64 gasSpentOnSource,
        uint128 destinationRelayerReward,
        uint128 sourceRelayerReward
    );

    // To save gas, this event does not emit the full incentive scheme.
    // Instead, the new gas prices are emitted. As a result, the relayer can collect all bountyIncreased
    // and then use the maximum. (since the  maximum is enforced in the smart contract)
    event BountyIncreased(
        bytes32 indexed messageIdentifier,
        uint96 newDeliveryGasPrice,
        uint96 newAckGasPrice 
    );


    event RemoteImplementationSet(address application, bytes32 chainIdentifier, bytes32 implementationAddressHash, bytes implementationAddress);
}