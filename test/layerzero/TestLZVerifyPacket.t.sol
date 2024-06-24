// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LZCommon } from "./LZCommon.t.sol";

import { Packet } from "LayerZero-v2/protocol/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "LayerZero-v2/protocol/contracts/messagelib/libs/PacketV1Codec.sol";
import { GUID } from "LayerZero-v2/protocol/contracts/libs/GUID.sol";

contract TestLZVerifyPacket is LZCommon {
    using PacketV1Codec for bytes;
    using PacketV1Codec for Packet;

    event ExecutorFeePaid(address executor, uint256 fee);
    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);

    function setUp() public override {
        super.setUp();
        _set_init_config();
    }

    function test_revert_verify_packet_no_proof(bytes calldata message) external {
        vm.assume(message.length > 0);
        address target = address(layerZeroEscrow);

        uint64 nonce = 1;
        uint32 dstEid = localEid;
        bytes32 receiver = bytes32(uint256(uint160(target)));
        address sender = address(layerZeroEscrow);
        
        bytes32 guid = GUID.generate(nonce, localEid, sender, dstEid, receiver);

        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: remoteEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });

        bytes memory _packet = PacketV1Codec.encode(packet);

        vm.expectRevert(abi.encodeWithSignature("LZ_ULN_Verifying()"));
        layerZeroEscrow.verifyPacket(hex"", _packet);
    }

    function test_verify_packet(bytes calldata message) external {
        vm.assume(message.length > 0);
        address target = address(layerZeroEscrow);

        uint64 nonce = 1;
        uint32 dstEid = localEid;
        bytes32 receiver = bytes32(uint256(uint160(target)));
        address sender = address(layerZeroEscrow);
        
        bytes32 guid = GUID.generate(nonce, localEid, sender, dstEid, receiver);

        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: remoteEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });

        bytes memory _packet = packet.encode();

        bytes32 ph = this.payloadHash(packet.encode());
    
        vm.prank(address(mockDVN));
        receiveULN.verify(
            packet.encodePacketHeader(),
            ph,
            10
        );

        layerZeroEscrow.verifyPacket(hex"", _packet);
    }

    function test_revert_verify_wrong_chain(bytes calldata message) external {
        vm.assume(message.length > 0);
        address target = address(layerZeroEscrow);

        uint64 nonce = 1;
        uint32 dstEid = remoteEid;
        bytes32 receiver = bytes32(uint256(uint160(target)));
        address sender = address(layerZeroEscrow);
        
        bytes32 guid = GUID.generate(nonce, dstEid, sender, dstEid, receiver);

        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: dstEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });

        bytes memory _packet = packet.encode();

        bytes32 ph = this.payloadHash(packet.encode());
    
        vm.prank(address(mockDVN));
        receiveULN.verify(
            packet.encodePacketHeader(),
            ph,
            10
        );

        vm.expectRevert(abi.encodeWithSignature("LZ_ULN_InvalidEid()"));
        layerZeroEscrow.verifyPacket(hex"", _packet);
    }

    function test_revert_verify_invalid_receiver(bytes calldata message, address target) external {
        vm.assume(target != address(layerZeroEscrow));
        vm.assume(message.length > 0);

        uint64 nonce = 1;
        uint32 dstEid = localEid;
        bytes32 receiver = bytes32(uint256(uint160(target)));
        address sender = address(layerZeroEscrow);
        
        bytes32 guid = GUID.generate(nonce, dstEid, sender, dstEid, receiver);

        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: remoteEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });

        bytes memory _packet = packet.encode();

        bytes32 ph = this.payloadHash(packet.encode());
    
        vm.prank(address(mockDVN));
        receiveULN.verify(
            packet.encodePacketHeader(),
            ph,
            10
        );

        vm.expectRevert(abi.encodeWithSignature("IncorrectDestination()"));
        layerZeroEscrow.verifyPacket(hex"", _packet);
    }

    function test_revert_verify_invalid_packet_version(bytes calldata message) external {
        vm.assume(message.length > 0);
        address target = address(layerZeroEscrow);

        uint64 nonce = 1;
        uint32 dstEid = remoteEid;
        bytes32 receiver = bytes32(uint256(uint160(target)));
        address sender = address(layerZeroEscrow);
        
        bytes32 guid = GUID.generate(nonce, dstEid, sender, dstEid, receiver);

        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: dstEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });

        bytes memory _packet = packet.encode();
        _packet = this.replaceVersion(0x02, _packet);

        bytes32 ph = this.payloadHash(packet.encode());
    
        vm.prank(address(mockDVN));
        receiveULN.verify(
            packet.encodePacketHeader(),
            ph,
            10
        );

        vm.expectRevert(abi.encodeWithSignature("LZ_ULN_InvalidPacketVersion()"));
        layerZeroEscrow.verifyPacket(hex"", _packet);
    }

    function payloadHash(bytes calldata pl) pure public returns(bytes32) {
        return pl.payloadHash();
    }

    function replaceVersion(bytes1 newVersion, bytes calldata pl) pure public returns(bytes memory) {
        return abi.encodePacked(newVersion, pl[1:]);
    }
}