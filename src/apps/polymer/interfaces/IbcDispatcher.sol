//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './Ibc.sol';
import './IbcReceiver.sol';

/**
 * @title IbcDispatcher
 * @author Polymer Labs
 * @notice IBC dispatcher interface is the Polymer Core Smart Contract that implements the core IBC protocol.
 */
interface IbcDispatcher {
    function closeIbcChannel(bytes32 channelId) external;

    function sendPacket(
        bytes32 channelId,
        bytes calldata payload,
        uint64 timeoutTimestamp,
        PacketFee calldata fee
    ) external payable;
}
