// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { SmallStructs } from "./external/callworm/SmallStructs.sol";
import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";

// This is a mock contract which should only be used for testing.
contract IncentivizedWormholeEscrow is IncentivizedMessageEscrow, WormholeVerifier {
    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    IWormhole public immutable WORMHOLE;

    constructor(bytes32 uniqueChainIndex, address wormhole_) WormholeVerifier(wormhole_) {
        UNIQUE_SOURCE_IDENTIFIER = uniqueChainIndex;
        WORMHOLE = IWormhole(wormhole_);
    }

    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = WORMHOLE.messageFee();
    }

    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) internal override view returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes32(block.number),
                UNIQUE_SOURCE_IDENTIFIER, 
                destinationIdentifier,
                message
            )
        );
    }

    function _verifyMessage(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes calldata implementationIdentifier, bytes calldata message_) {

        (
            SmallStructs.SmallVM memory vm,
            bytes calldata payload,
            bool valid,
            string memory reason
        ) = parseAndVerifyVM(_message);

        require(valid, reason);

        // Load the identifier for the calling contract.
        implementationIdentifier = payload[0:32];

        // Local "supposedly" this chain identifier.
        bytes32 thisChainIdentifier = bytes32(payload[64:96]);

        // Check that the message is intended for this chain.
        require(thisChainIdentifier == UNIQUE_SOURCE_IDENTIFIER, "!Identifier");

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(payload[32:64]);

        // Get the application message.
        message_ = payload[96:];
    }

    function _sendMessage(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfSendMessageInNativeToken) {
        WORMHOLE.publishMessage(
            0,
            message,
            0   // Finality
        );
    }
}