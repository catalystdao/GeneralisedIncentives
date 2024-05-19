// SPDX-License-Identifier: LZBL-1.2
// TODO: License

pragma solidity ^0.8.13;

import { IReceiveUlnBase, UlnConfig, Verification } from "./interfaces/IUlnBase.sol";

contract SimpleLZULN {

    IReceiveUlnBase immutable ULTRA_LIGHT_NODE;

    constructor(address ULN) {
        ULTRA_LIGHT_NODE = IReceiveUlnBase(ULN);
    }

}