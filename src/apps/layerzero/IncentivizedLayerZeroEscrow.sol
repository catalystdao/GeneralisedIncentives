// SPDX-License-Identifier: DO-NOT-USE
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { ILayerZeroEndpointV2, MessagingParams, MessagingFee } from "./interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "./libs/PacketV1Codec.sol";
import { UlnConfig } from "./interfaces/IUlnBase.sol";
import { IReceiveUlnBase, UlnConfig, Verification } from "./interfaces/IUlnBase.sol";

/**
 * @notice LayerZero escrow.
 * TODO: Set config such that we are the executor.
 */
abstract contract BareIncentivizedLayerZeroEscrow is IncentivizedMessageEscrow {
    using PacketV1Codec for bytes;

    error LayerZeroCannotBeAddress0();
    error LZ_ULN_Verifying();
    error LZ_ULN_InvalidPacketHeader();
    error LZ_ULN_InvalidPacketVersion();
    error LZ_ULN_InvalidEid();

    ILayerZeroEndpointV2 immutable ENDPOINT;
    IReceiveUlnBase immutable ULTRA_LIGHT_NODE;

    // TODO: Are these values packed?
    uint128 excessPaid = 1; // Set to 1 so we never have to pay zero to non-zero cost.
    bool allowExternalCall = false;

    // chainid is immutable on LayerZero endpoint, so we read it and store it likewise.
    uint32 public immutable chainId;
    address private constant DEFAULT_CONFIG = address(0);

    constructor(address sendLostGasTo, address lzEndpointV2, address ULN) IncentivizedMessageEscrow(sendLostGasTo) {
        if (lzEndpointV2 == address(0)) revert LayerZeroCannotBeAddress0();
        ENDPOINT = ILayerZeroEndpointV2(lzEndpointV2);
        chainId  = ENDPOINT.eid();
        ULTRA_LIGHT_NODE = IReceiveUlnBase(ULN);
        // TODO: Set executor as this contract.
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
        MessagingFee memory fee = ENDPOINT.quote(params, address(this));
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

    function _verifyPacket(bytes calldata _packetHeader, bytes calldata _packet) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        _assertHeader(_packetHeader);

        // Check that we are the receiver
        address receiver = _packetHeader.receiverB20();
        require(receiver == address(this)); // TODO: update

        // Get the source chain.
        uint32 srcEid = _packetHeader.srcEid();


        bytes32 _headerHash = keccak256(_packetHeader);
        bytes32 _payloadHash = _packet.payloadHash();
        UlnConfig memory _config = ULTRA_LIGHT_NODE.getUlnConfig(address(this), srcEid);
        if (ULTRA_LIGHT_NODE.verifiable(_config, _headerHash, _payloadHash)) revert LZ_ULN_Verifying();

        // Get the sourec chain
        sourceIdentifier = bytes32(uint256(srcEid));
        // Get the sender
        implementationIdentifier = abi.encode(_packetHeader.sender());
        // Get the message
        message_ = _packet.message();
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

        // MessagingFee memory fee = ENDPOINT.quote(params, address(this));
        // costOfsendPacketInNativeToken = uint128(fee.nativeFee); // Layer zero doesn't need that much.

        // Handoff package to LZ.
        // We are getting a refund on any excess value we sent. Since that refund is 
        // coming before the end of this call, we can record it.
        allowExternalCall = true;
        ENDPOINT.send{value: msg.value}(
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


    function _assertHeader(bytes calldata _packetHeader) internal view {
        // assert packet header is of right size 81
        if (_packetHeader.length != 81) revert LZ_ULN_InvalidPacketHeader();
        // assert packet header version is the same as ULN
        if (_packetHeader.version() != PacketV1Codec.PACKET_VERSION) revert LZ_ULN_InvalidPacketVersion();
        // assert the packet is for this endpoint
        if (_packetHeader.dstEid() != chainId) revert LZ_ULN_InvalidEid();
    }
}