// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { SmallStructs } from "./external/callworm/SmallStructs.sol";
import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";

// This is a mock contract which should only be used for testing.
contract IncentivizedWormholeEscrow is IncentivizedMessageEscrow, WormholeVerifier {
    error BadChainIdentifier();

    event WormholeMessage(
        bytes32 destinationIdentifier,
        bytes recipient
    );

    IWormhole public immutable WORMHOLE;

    constructor(address sendLostGasTo, address wormhole_) IncentivizedMessageEscrow(sendLostGasTo) WormholeVerifier(wormhole_) {
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
                chainId(), 
                destinationIdentifier,
                message
            )
        );
    }

    function _verifyPacket(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {

        (
            SmallStructs.SmallVM memory vm,
            bytes calldata payload,
            bool valid,
            string memory reason
        ) = parseAndVerifyVM(_message);

        require(valid, reason);

        // Load the identifier for the calling contract.
        implementationIdentifier = abi.encodePacked(vm.emitterAddress);

        // Local "supposedly" this chain identifier.
        bytes32 thisChainIdentifier = bytes32(payload[0:32]);

        // Check that the message is intended for this chain.
        if (thisChainIdentifier != bytes32(uint256(chainId()))) revert BadChainIdentifier();

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(bytes2(vm.emitterChainId));

        // Get the application message.
        message_ = payload[32:];
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        // Get the cost of sending wormhole messages.
        costOfsendPacketInNativeToken = uint128(WORMHOLE.messageFee());

        // Emit context for relayers so they know where to send the message
        emit WormholeMessage(destinationChainIdentifier, destinationImplementation);

        // Handoff the message to wormhole.
        WORMHOLE.publishMessage{value: costOfsendPacketInNativeToken}(
            0,
            abi.encodePacked(
                destinationChainIdentifier,
                message
            ),
            0   // Finality = complete.
        );
    }
}