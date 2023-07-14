// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Bytes65} from "./Bytes65.sol";

contract EscrowAddress is Bytes65 {

    mapping(bytes32 => bytes) public destinationToAddress;

    bytes constant ALT_DEPLOYMENT = bytes("0x12341234");


    /// @notice Gets this address on the destination chain
    /// @dev Can be overwritten if a messaging router uses some other assumption
    function _getEscrowAddress(bytes32 destinationIdentifier) internal virtual returns(bytes memory) {
        // Try to save gas by not accessing storage. If the most significant bit is set to 1, then return itself
        if ((uint256(destinationIdentifier) & 2**255) != 0) return convertEVMTo65(address(this));
        if ((uint256(destinationIdentifier) & 2**254) != 0) return ALT_DEPLOYMENT;
        return destinationToAddress[destinationIdentifier];
    }
}