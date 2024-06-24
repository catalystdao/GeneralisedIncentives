// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LZCommon } from "./LZCommon.t.sol";

import { Origin } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract TestLZMisc is LZCommon {
    function setUp() public override {
        super.setUp();
    }
    
    function test_allowInitializePath(Origin calldata origin) external {
        bool result = layerZeroEscrow.allowInitializePath(origin);

        assertEq(result, false, "allowInitializePath returns true");
    }

    function test_estimate_additional_cost() external {
        _set_init_config();
        vm.expectCall(
            address(layerZeroEscrow),
            abi.encodeCall(layerZeroEscrow.getFee, (localEid, address(layerZeroEscrow), 0, hex""))
        );
        layerZeroEscrow.estimateAdditionalCost();
    }

    function test_revert_estimate_additional_cost_no_config() external {
        vm.expectCall(
            address(0),
            abi.encodeCall(layerZeroEscrow.getFee, (localEid, address(layerZeroEscrow), 0, hex""))
        );
        vm.expectRevert();
        layerZeroEscrow.estimateAdditionalCost();
    }

    function test_estimate_additional_cost_remote() external {
        _set_init_config();
        vm.expectCall(
            address(layerZeroEscrow),
            abi.encodeCall(layerZeroEscrow.getFee, (remoteEid, address(layerZeroEscrow), 0, hex""))
        );
        layerZeroEscrow.estimateAdditionalCost(bytes32(uint256(remoteEid)));
    }
}