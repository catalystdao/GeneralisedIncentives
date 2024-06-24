// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LZCommon } from "./LZCommon.t.sol";

import { Origin } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ExecutorConfig } from "LayerZero-v2/messagelib/contracts/SendLibBase.sol";

contract TestLZInitConfig is LZCommon {
    function test_init_config_remote() external {
        uint32[] memory remoteEids = new uint32[](1);
        remoteEids[0] = remoteEid;

        address sendLibrary = endpoint.getSendLibrary(address(layerZeroEscrow), remoteEid);
        layerZeroEscrow.initConfig(sendLibrary, remoteEids);

        bytes memory config = endpoint.getConfig(address(layerZeroEscrow), sendLibrary, remoteEid, 1);
        ExecutorConfig memory executorConfig = abi.decode(config, (ExecutorConfig));
        assertEq(executorConfig.executor, address(layerZeroEscrow));
        assertEq(executorConfig.maxMessageSize, MAX_MESSAGE_SIZE);
    }

    function test_init_config_local() external {
        uint32[] memory remoteEids = new uint32[](1);
        remoteEids[0] = localEid;

        address sendLibrary = endpoint.getSendLibrary(address(layerZeroEscrow), remoteEid);
        layerZeroEscrow.initConfig(sendLibrary, remoteEids);

        bytes memory config = endpoint.getConfig(address(layerZeroEscrow), sendLibrary, localEid, 1);
        ExecutorConfig memory executorConfig = abi.decode(config, (ExecutorConfig));
        assertEq(executorConfig.executor, address(layerZeroEscrow));
        assertEq(executorConfig.maxMessageSize, MAX_MESSAGE_SIZE);
    }

    function test_init_config_remote_local() external {
        uint32[] memory remoteEids = new uint32[](2);
        remoteEids[0] = remoteEid;
        remoteEids[1] = localEid;

        address sendLibrary = endpoint.getSendLibrary(address(layerZeroEscrow), remoteEid);
        layerZeroEscrow.initConfig(sendLibrary, remoteEids);

        bytes memory config = endpoint.getConfig(address(layerZeroEscrow), sendLibrary, localEid, 1);
        ExecutorConfig memory executorConfig = abi.decode(config, (ExecutorConfig));
        assertEq(executorConfig.executor, address(layerZeroEscrow));
        assertEq(executorConfig.maxMessageSize, MAX_MESSAGE_SIZE);

        config = endpoint.getConfig(address(layerZeroEscrow), sendLibrary, remoteEid, 1);
        executorConfig = abi.decode(config, (ExecutorConfig));
        assertEq(executorConfig.executor, address(layerZeroEscrow));
        assertEq(executorConfig.maxMessageSize, MAX_MESSAGE_SIZE);
    }
}