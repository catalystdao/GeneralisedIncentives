// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { SmallStructs } from "./external/callworm/SmallStructs.sol";
import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";

/**
 * @title Incentivized Wormhole Message Escrow
 * @notice Incentivizes Wormhole messages through Generalised Incentives.
 * Wormhole does not have any native way of relaying messages, this implementation adds one.
 *
 * When using Wormhole with Generalised Incentives and you don't want to lose message, be very careful regarding
 * emitting messages to destinationChainIdentifiers that does not exist. Wormhole has no way to verify if a
 * chain identifier exists or not. If the chain identifier does not exist, it is not possible to get a timeout or ack back.
 *
 * @dev This implementation only uses the Wormhole contracts to emit messages, it does not use the Wormhole contracts
 * to verify if messages are authentic. A custom verification library is used that is more gas efficient and skips
 * parts of the VAA that is not relevant to us. This provides significant gas savings compared to verifying packages
 * against the Wormhole implementation.
 */
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

    function estimateAdditionalCost(bytes32 /* destinationChainIdentifier */) external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = WORMHOLE.messageFee();
    }

    /** @notice Wormhole proofs are valid until the guardian set is changed. The new guardian set may sign a new VAA */
    function _proofValidPeriod(bytes32 /* destinationIdentifier */) override internal pure returns(uint64) {
        return 0;
    }

    function _uniqueSourceIdentifier() override internal view returns(bytes32 sourceIdentifier) {
        return sourceIdentifier = UNIQUE_SOURCE_IDENTIFIER;
    }

    /** @dev _message is the entire Wormhole VAA. It contains both the proof & the message as a slice. */
    function _verifyPacket(bytes calldata /* _metadata */, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {

        // Decode & verify the VAA.
        // This uses the custom verification logic found in ./external/callworm/WormholeVerifier.sol.
        (
            SmallStructs.SmallVM memory vm,
            bytes calldata payload,
            bool valid,
            string memory reason
        ) = parseAndVerifyVM(_message);

        // This is the preferred flow used by Wormhole.
        require(valid, reason);

        // We added the destination chain to the payload since Wormhole messages are broadcast.
        // Get the chain identifier for the destination chain according to the payload.
        bytes32 destinationChainIdentifier = bytes32(payload[0:32]);

        // Check that the message is intended for this chain.
        if (destinationChainIdentifier != UNIQUE_SOURCE_IDENTIFIER) revert BadChainIdentifier();

        // Get the identifier for the source chain.
        sourceIdentifier = bytes32(uint256(vm.emitterChainId));

        // Load the identifier for the calling contract.
        implementationIdentifier = bytes.concat(vm.emitterAddress);

        // Get the application message.
        message_ = payload[32:];
    }

    /**
     * @dev Wormhole messages are broadcast, as a result we set destinationChainIdentifier in the message.
     */
    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory /* destinationImplementation */, bytes memory message, uint64 /* deadline */) internal override returns(uint128 costOfsendPacketInNativeToken) {
        // Get the cost of sending wormhole messages.
        costOfsendPacketInNativeToken = uint128(WORMHOLE.messageFee());

        // Relayers can collect the destination chain from the payload and destinationImplementation from storage / their whitelist.

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