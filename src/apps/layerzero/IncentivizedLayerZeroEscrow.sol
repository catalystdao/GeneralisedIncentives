// SPDX-License-Identifier: DO-NOT-USE
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { ILayerZeroEndpointV2, MessagingParams, MessagingFee } from "./interfaces/ILayerZeroEndpointV2.sol";

/**
 * @notice LayerZero escrow.
 * TODO: Set config such that we are the executor.
 * TODO: Figure out if we can verify
 *      If not, then figure out how to decode the payload and then do both the composer and the executor step in 1.
 */
abstract contract BareIncentivizedLayerZeroEscrow is IncentivizedMessageEscrow {
    error LayerZeroCannotBeAddress0();

    ILayerZeroEndpointV2 immutable LAYER_ZERO;

    // TODO: Are these values packed?
    uint128 excessPaid = 1; // Set to 1 so we never have to pay zero to non-zero cost.
    bool allowExternalCall = false;

    // chainid is immutable on LayerZero endpoint, so we read it and store it likewise.
    uint32 public immutable chainId;

    constructor(address sendLostGasTo, address layer_zero) IncentivizedMessageEscrow(sendLostGasTo) {
        if (layer_zero == address(0)) revert LayerZeroCannotBeAddress0();
        LAYER_ZERO = ILayerZeroEndpointV2(layer_zero);
        chainId  = LAYER_ZERO.eid();
    }

    // TODO: Fix
    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        MessagingParams memory params = MessagingParams({
            dstEid: uint32(uint256(0)), // TODO: Fix
            receiver: bytes32(0), // TODO: FIX
            message: hex"",
            options: hex"",
            payInLzToken: false
        });
        MessagingFee memory fee = LAYER_ZERO.quote(params, address(this));
        amount = fee.nativeFee;
        asset =  address(0);
    }

    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) internal override view returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                msg.sender,
                bytes32(block.number),
                chainId, 
                destinationIdentifier,
                message
            )
        );
    }

    function _verifyPacket(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        // TODO: Set verification logic.
        // require(messageSigner == owner(), "!signer");

        // Load the identifier for the calling contract.
        implementationIdentifier = _message[0:32];

        // Local "supposedly" this chain identifier.
        uint16 thisChainIdentifier = uint16(uint256(bytes32(_message[64:96])));

        // Check that the message is intended for this chain.
        require(thisChainIdentifier == chainId, "!Identifier");

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(_message[32:64]);

        // Get the application message.
        message_ = _message[96:];
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {

        // TODO: Optimise this.
        MessagingParams memory params = MessagingParams({
            dstEid: uint32(uint256(destinationChainIdentifier)),
            receiver: bytes32(destinationImplementation),
            message: message,
            options: hex"",
            payInLzToken: false
        });

        // MessagingFee memory fee = LAYER_ZERO.quote(params, address(this));
        // costOfsendPacketInNativeToken = uint128(fee.nativeFee); // Layer zero doesn't need that much.

        // Handoff package to LZ.
        // We are getting a refund on any excess value we sent. Since that refund is 
        // coming before the end of this call, we can record it.
        allowExternalCall = true;
        LAYER_ZERO.send{value: msg.value}(
            params,
            address(this)
        );
        // Set the cost of the sendPacket to msg.value 
        costOfsendPacketInNativeToken = uint128(msg.value - (excessPaid - 1));
        excessPaid = 1;

        return costOfsendPacketInNativeToken;
    }

    // Record refunds coming in.
    // Ideally, disallow randoms from sending to this contract but that wou
    receive() external payable {
        require(allowExternalCall, "Do not send ether to this address");
        excessPaid = uint128(1 + msg.value);
        allowExternalCall = false;
    }
}