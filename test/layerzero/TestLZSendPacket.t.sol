// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LZCommon } from "./LZCommon.t.sol";

import { Packet } from "LayerZero-v2/protocol/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "LayerZero-v2/protocol/contracts/messagelib/libs/PacketV1Codec.sol";
import { GUID } from "LayerZero-v2/protocol/contracts/libs/GUID.sol";

contract TestLZSendPacket is LZCommon {

    event ExecutorFeePaid(address executor, uint256 fee);
    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);

    function _set_init_config() internal {
        uint32[] memory remoteEids = new uint32[](2);
        remoteEids[0] = remoteEid;
        remoteEids[1] = localEid;

        address sendLibrary = endpoint.getSendLibrary(address(layerZeroEscrow), remoteEid);
        layerZeroEscrow.initConfig(sendLibrary, remoteEids);
    }

    function setUp() public override {
        super.setUp();
    }

    function test_send_packet(address target, bytes calldata message, uint64 deadline) external {
        _set_init_config();

        uint64 nonce = 1;
        uint32 dstEid = remoteEid;
        bytes32 receiver = bytes32(uint256(uint160(target)));
        address sender = address(layerZeroEscrow);
        
        bytes32 guid = GUID.generate(nonce, localEid, sender, dstEid, receiver);

        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: localEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });

        vm.expectEmit();
        emit ExecutorFeePaid(address(layerZeroEscrow), 0);

        vm.expectEmit();
        emit PacketSent(
            PacketV1Codec.encode(packet),
            hex"0003",
            address(sendULN)
        );
        layerZeroEscrow.sendPacket(bytes32(uint256(remoteEid)), abi.encodePacked(bytes32(uint256(uint160(target)))), message, deadline);
    }

    function test_revert_no_init_config_send_packet(address target, bytes calldata message, uint64 deadline) external {
        vm.expectRevert();
        layerZeroEscrow.sendPacket(bytes32(uint256(remoteEid)), abi.encodePacked(bytes32(uint256(uint160(target)))), message, deadline);
    }
}