// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { MockLayerZeroEscrow } from "./mock/MockLayerZeroEscrow.sol";

contract TestLzCommon is Test {

    MockLayerZeroEscrow mockLayerZeroEscrow;

    address SEND_LOST_GAS_TO = address(uint160(0xdead));
    address lzEndpointV2;
    address ULN;

    function setUp() virtual public {

        lzEndpointV2 = address(0);
        ULN = address(0);
        mockLayerZeroEscrow = new MockLayerZeroEscrow(SEND_LOST_GAS_TO, lzEndpointV2, ULN);
    }
}
