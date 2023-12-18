// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IInterchainSecurityModule} from "../../../src/apps/hyperlane/interfaces/IInterchainSecurityModule.sol";

contract MockIsm is IInterchainSecurityModule {
    uint8 public moduleType = uint8(Types.UNUSED);

    function verify(bytes calldata metadata, bytes calldata /* _message */) external pure returns (bool) {
        return bytes1(metadata) == bytes1(0x01);
    }
}