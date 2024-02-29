// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { SmallStructs } from "./external/callworm/SmallStructs.sol";
import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";

// This is a mock contract which should only be used for testing.
contract IncentivizedWormholeEscrow is IncentivizedMessageEscrow, WormholeVerifier {
    error BadChainIdentifier();

    IWormhole public immutable WORMHOLE;

    // Wormhole's chain identifier can be changed. However, we generally expect to redeploy
    // in cases where they would change it.
    bytes32 public immutable UNIQUE_SOURCE_IDENTIFIER;

    // For EVM it is generally set that 15 => Finality
    uint8 constant WORMHOLE_CONSISTENCY = 15;

    constructor(address sendLostGasTo, address wormhole_) payable IncentivizedMessageEscrow(sendLostGasTo) WormholeVerifier(wormhole_) {
        WORMHOLE = IWormhole(wormhole_);

        // Collect chainId from Wormhole.
        UNIQUE_SOURCE_IDENTIFIER = bytes32(uint256(WORMHOLE.chainId()));
    }

    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = WORMHOLE.messageFee();
    }

    function _proofValidPeriod(bytes32 /* destinationIdentifier */) override internal pure returns(uint64) {
        return 0;
    }

    function _uniqueSourceIdentifier() override internal view returns(bytes32 sourceIdentifier) {
        return sourceIdentifier = UNIQUE_SOURCE_IDENTIFIER;
    }

    function _verifyPacket(bytes calldata /* _metadata */, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {

        (
            SmallStructs.SmallVM memory vm,
            bytes calldata payload,
            bool valid,
            string memory reason
        ) = parseAndVerifyVM(_message);

        require(valid, reason);


        // Local "supposedly" this chain identifier.
        bytes32 thisChainIdentifier = bytes32(payload[0:32]);

        // Check that the message is intended for this chain.
        if (thisChainIdentifier != UNIQUE_SOURCE_IDENTIFIER) revert BadChainIdentifier();

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(uint256(vm.emitterChainId));

        // Load the identifier for the calling contract.
        implementationIdentifier = bytes.concat(vm.emitterAddress);

        // Get the application message.
        message_ = payload[32:];
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory /* destinationImplementation */, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        // Get the cost of sending wormhole messages.
        costOfsendPacketInNativeToken = uint128(WORMHOLE.messageFee());

        // Relayers can collect the destination chain from the payload and destination address from storage.

        // Handoff the message to wormhole.
        WORMHOLE.publishMessage{value: costOfsendPacketInNativeToken}(
            0,
            bytes.concat(
                destinationChainIdentifier,
                message
            ),
            WORMHOLE_CONSISTENCY
        );
    }
}