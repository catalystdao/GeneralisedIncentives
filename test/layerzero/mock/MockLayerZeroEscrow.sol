// SPDX-License-Identifier: IncentivizedLayerZeroEscrow
pragma solidity ^0.8.22;

import { IncentivizedLayerZeroEscrow } from "../../../src/apps/layerzero/IncentivizedLayerZeroEscrow.sol";

/**
 * @notice Mock Layer Zero Escrow
 */
contract MockLayerZeroEscrow is IncentivizedLayerZeroEscrow {
    
    function test() public {}

    constructor(address sendLostGasTo, address lzEndpointV2) IncentivizedLayerZeroEscrow(sendLostGasTo, lzEndpointV2) {}

    function verifyPacket(bytes calldata _packetHeader, bytes calldata _packet) view external returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        return _verifyPacket(_packetHeader, _packet);
    }

    function sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message, uint64 deadline) external returns(uint128 costOfsendPacketInNativeToken) {
        return _sendPacket(destinationChainIdentifier, destinationImplementation, message, deadline);
    }

    function setAllowExternalCall(bool state) external {
        allowExternalCall = state ? 2 : 1;
    }
}