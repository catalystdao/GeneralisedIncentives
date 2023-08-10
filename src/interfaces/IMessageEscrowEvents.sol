// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IMessageEscrowStructs } from "./IMessageEscrowStructs.sol";

interface IMessageEscrowEvents {
    event BountyPlaced(
        bytes32 indexed messageIdentifier,
        IMessageEscrowStructs.IncentiveDescription incentive
    );
    event MessageDelivered(bytes32 indexed messageIdentifier);
    event MessageAcked(bytes32 messageIdentifier); // Not indexed since relayers can sort by BountyClaimed.
    event BountyClaimed(
        bytes32 indexed uniqueIdentifier,
        uint64 gasSpentOnDestination,
        uint64 gasSpentOnSource,
        uint128 destinationRelayerReward,
        uint128 sourceRelayerReward
    );

    // To save gas, this event does not emit the full incentive scheme.
    // Instead, the off-chain relayer should collect all BountyIncreased for a specific event
    // then add all deliveryGasPriceIncrease and ackGasPriceIncrease to their respective payments.
    event BountyIncreased(
        bytes32 indexed messageIdentifier,
        uint96 deliveryGasPriceIncrease,
        uint96 ackGasPriceIncrease 
    );


    event RemoteEscrowSet(address application, bytes32 chainIdentifier, bytes32 implementationAddressHash, bytes implementationAddress);
}