// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import "../../mocks/MockApplication.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";

contract NoImplementationAddressSetTest is TestCommon {

    function test_error_no_implementation_address_set() public {
        MockApplication applicationWithNoImplementationAddress = new MockApplication(address(escrow));

        vm.expectRevert(
            abi.encodeWithSignature("NoImplementationAddressSet()")
        ); 
        applicationWithNoImplementationAddress.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            _INCENTIVE
        );
    }
}
