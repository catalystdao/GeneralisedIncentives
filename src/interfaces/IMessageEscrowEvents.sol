// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IMessageEscrowStructs } from "./IMessageEscrowStructs.sol";

interface IMessageEscrowEvents {
    event BountyPlaced(
        bytes32 indexed messageIdentifier,
        IMessageEscrowStructs.IncentiveDescription incentive
    );
    event MessageDelivered(bytes32 messageIdentifier);
    event MessageAcked(bytes32 messageIdentifier);
    event BountyClaimed(
        bytes32 indexed uniqueIdentifier,
        uint64 gasSpentOnDestination,
        uint64 gasSpentOnSource,
        uint128 destinationRelayerReward,
        uint128 sourceRelayerReward
    );
}