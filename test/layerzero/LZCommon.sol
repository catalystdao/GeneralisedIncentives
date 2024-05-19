// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { EndpointV2 } from "LayerZero-v2/protocol/contracts/EndpointV2.sol";
import { SimpleMessageLib } from "LayerZero-v2/protocol/contracts/messagelib/SimpleMessageLib.sol";
import { ReceiveUln302 } from "LayerZero-v2/messagelib/contracts/uln/uln302/ReceiveUln302.sol";

import "forge-std/Test.sol";
import { MockLayerZeroEscrow } from "./mock/MockLayerZeroEscrow.sol";

contract TestLzCommon is Test {
    uint32 internal localEid;
    uint32 internal remoteEid;
    EndpointV2 internal endpoint;
    SimpleMessageLib internal simpleMsgLib;
    ReceiveUln302 ULN;

    MockLayerZeroEscrow mockLayerZeroEscrow;

    address SEND_LOST_GAS_TO = address(uint160(0xdead));

    function setUp() virtual public {
        localEid = 1;
        remoteEid = 2;

        endpoint = new EndpointV2(localEid, address(this));
        ULN = new ReceiveUln302(address(endpoint));

        SimpleMessageLib msgLib = new SimpleMessageLib(address(endpoint), address(0));

        // register msg lib
        endpoint.registerLibrary(address(msgLib));

        // Set default libs
        endpoint.setDefaultSendLibrary(remoteEid, address(msgLib));
        endpoint.setDefaultReceiveLibrary(remoteEid, address(msgLib), 0);


        // Setup our mock escrow
        mockLayerZeroEscrow = new MockLayerZeroEscrow(SEND_LOST_GAS_TO, address(endpoint), address(ULN));

    }
}
