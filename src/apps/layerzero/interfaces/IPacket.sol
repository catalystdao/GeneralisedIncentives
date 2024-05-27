// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

struct Packet {
    uint64 nonce;
    uint32 srcEid;
    address sender;
    uint32 dstEid;
    bytes32 receiver;
    bytes32 guid;
    bytes message;
}
