// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LZCommon } from "./LZCommon.t.sol";

import { Origin } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract TestLZMisc is LZCommon {
    function test_allowInitializePath(Origin calldata origin) external {
        bool result = layerZeroEscrow.allowInitializePath(origin);

        assertEq(result, false, "allowInitializePath returns true");
    }
}