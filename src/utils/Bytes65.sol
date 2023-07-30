// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract Bytes65 {
    error InvalidBytes65Address();

    function _checkBytes65(bytes calldata supposedlyBytes65) internal pure returns(bool) {
        return supposedlyBytes65.length == 65;
    }

    modifier checkBytes65Address(bytes calldata supposedlyBytes65) {
        if (!_checkBytes65(supposedlyBytes65)) revert InvalidBytes65Address();
        _;
    }

    function convertEVMTo65(address evmAddress) public pure returns(bytes memory) {
        return abi.encodePacked(
            uint8(20),                              // Size of address. Is always 20 for EVM
            bytes32(0),                             // First 32 bytes on EVM are 0
            bytes32(uint256(uint160((evmAddress)))) // Encode the address in bytes32.
        );
    }

    function thisBytes65() public view returns(bytes memory) {
        return abi.encodePacked(
            uint8(20),                              // Size of address. Is always 20 for EVM
            bytes32(0),                             // First 32 bytes on EVM are 0
            bytes32(uint256(uint160(address(this)))) // Encode the address in bytes32.
        );
    }
}
