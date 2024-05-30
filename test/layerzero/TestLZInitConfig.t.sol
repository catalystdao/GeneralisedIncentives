// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { LZCommon } from "./LZCommon.t.sol";

import { Origin } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract TestLZInitConfig is LZCommon {
    function test_init_config(uint32[] calldata remoteEids) external {
        vm.assume(remoteEids.length > 0);
        address sendLibrary = endpoint.getSendLibrary(address(layerZeroEscrow), remoteEid);
        layerZeroEscrow.initConfig(sendLibrary, remoteEids);
    }
}