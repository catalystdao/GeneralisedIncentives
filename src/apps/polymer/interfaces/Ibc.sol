//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

/// IbcPacket represents the packet data structure received from a remote chain
/// over an IBC channel.
struct IbcPacket {
    /// identifies the channel and port on the sending chain.
    IbcEndpoint src;
    /// identifies the channel and port on the receiving chain.
    IbcEndpoint dest;
    /// The sequence number of the packet on the given channel
    uint64 sequence;
    bytes data;
    /// block height after which the packet times out
    Height timeoutHeight;
    /// block timestamp (in nanoseconds) after which the packet times out
    uint64 timeoutTimestamp;
}

/// Height is a monotonically increasing data type
/// that can be compared against another Height for the purposes of updating and
/// freezing clients
///
/// Normally the RevisionHeight is incremented at each height while keeping
/// RevisionNumber the same. However some consensus algorithms may choose to
/// reset the height in certain conditions e.g. hard forks, state-machine
/// breaking changes In these cases, the RevisionNumber is incremented so that
/// height continues to be monitonically increasing even as the RevisionHeight
/// gets reset
struct Height {
    uint64 revision_number;
    uint64 revision_height;
}

struct AckPacket {
    // success indicates the dApp-level logic. Even when a dApp fails to process a packet per its dApp logic, the
    // delivery of packet and ack packet are still considered successful.
    bool success;
    bytes data;
}

struct IncentivizedAckPacket {
    bool success;
    // Forward relayer's payee address, an EMV address registered on Polymer chain with `RegisterCounterpartyPayee` endpoint.
    // In case of missing payee, zero address is used on Polymer.
    // The relayer payee address is set when incentivized ack is created on Polymer.
    bytes relayer;
    bytes data;
}

enum ChannelOrder {
    NONE,
    UNORDERED,
    ORDERED
}
struct Channel {
    string version;
    ChannelOrder ordering;
    bool feeEnabled;
    string[] connectionHops;
    string counterpartyPortId;
    bytes32 counterpartyChannelId;
}

struct CounterParty {
    string portId;
    bytes32 channelId;
    string version;
}

struct IbcEndpoint {
    string portId;
    bytes32 channelId;
}

struct PacketFee {
    uint256 recvFee;
    uint256 ackFee;
    uint256 timeoutFee;
}

struct Proof {
    // block height at which the proof is valid for a membership or non-membership at the given keyPath
    Height proofHeight;
    // ics23 merkle proof
    bytes proof;
}

// define a library of Ibc utility functions
library Ibc {
    // calcEscrowFee returns the fee to be escrowed for sending a packet.
    function calcEscrowFee(PacketFee memory fee) internal pure returns (uint256) {
        uint256 ackFees = fee.recvFee + fee.ackFee;
        return fee.timeoutFee > ackFees ? fee.timeoutFee : ackFees;
    }

    /**
     * @dev Return the amount of fee to be refunded to the sender when a packet is timed out.
     * @param fee accumulative packet fees
     */
    function timeoutRefundAmount(PacketFee memory fee) internal pure returns (uint256) {
        if (fee.recvFee + fee.ackFee > fee.timeoutFee) {
            return fee.recvFee + fee.ackFee - fee.timeoutFee;
        } else {
            return 0;
        }
    }

    /**
     * @dev Return the amount of fee to be refunded to the sender when a packet is acknowledged.
     * @param fee accumulative packet fees
     */
    function ackRefundAmount(PacketFee memory fee) internal pure returns (uint256) {
        if (fee.timeoutFee > fee.ackFee + fee.recvFee) {
            return fee.timeoutFee - fee.ackFee - fee.recvFee;
        } else {
            return 0;
        }
    }
}
