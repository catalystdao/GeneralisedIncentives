// SPDX-License-Identifier: IncentivizedLayerZeroEscrow
pragma solidity ^0.8.13;

import { IncentivizedLayerZeroEscrow } from "../../../src/apps/layerzero/IncentivizedLayerZeroEscrow.sol";

/**
 * @notice Mock Layer Zero Escrow
 */
contract MockLayerZeroEscrow is IncentivizedLayerZeroEscrow {

    constructor(address sendLostGasTo, address lzEndpointV2, address ULN) IncentivizedLayerZeroEscrow(sendLostGasTo, lzEndpointV2, ULN) {}

    function verifyPacket(bytes calldata _packetHeader, bytes calldata _packet) external view returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        return _verifyPacket(_packetHeader, _packet);
    }

    function sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) external returns(uint128 costOfsendPacketInNativeToken) {
        return _sendPacket(destinationChainIdentifier, destinationImplementation, message);
    }

    function setAllowExternalCall(bool state) external {
        allowExternalCall = state;
    }
}