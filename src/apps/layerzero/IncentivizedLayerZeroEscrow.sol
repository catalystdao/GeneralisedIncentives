// SPDX-License-Identifier: DO-NOT-USE
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { ILayerZeroEndpointV2, MessagingParams } from "./interfaces/ILayerZeroEndpointV2.sol";

/**
 * @notice LayerZero escrow.
 * Do not use because of license issues.
 */
abstract contract BareIncentivizedLayerZeroEscrow is IncentivizedMessageEscrow {
    error LayerZeroCannotBeAddress0();

    ILayerZeroEndpointV2 immutable LAYER_ZERO;

    // chainid is immutable on LayerZero endpoint, so we read it and store it likewise.
    uint32 public immutable chainId;

    constructor(address sendLostGasTo, address layer_zero) IncentivizedMessageEscrow(sendLostGasTo) {
        if (layer_zero == address(0)) revert LayerZeroCannotBeAddress0();
        LAYER_ZERO = ILayerZeroEndpointV2(layer_zero);
        chainId  = LAYER_ZERO.eid();
    }

    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = 0; // TODO: Verify.
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

        costOfsendPacketInNativeToken = 0; // TODO

        // Handoff package to LZ.
        LAYER_ZERO.send{value: costOfsendPacketInNativeToken}(
            MessagingParams({
                dstEid: uint32(uint256(destinationChainIdentifier)),
                receiver: bytes32(destinationImplementation),
                message: message,
                options: hex"",
                payInLzToken: false
            }),
            msg.sender // TODO:
        );

        return costOfsendPacketInNativeToken;
    }
}