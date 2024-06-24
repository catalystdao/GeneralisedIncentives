// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { BaseMultiChainDeployer} from "../BaseMultiChainDeployer.s.sol";

import { IncentivizedLayerZeroEscrow } from "../../src/apps/layerzero/IncentivizedLayerZeroEscrow.sol";

contract LZProcessMessage is BaseMultiChainDeployer {
    function processMessage(
        address escrow,
        bytes calldata rawMessage,
        bytes32 feeRecipient
    ) external broadcast {
        IncentivizedLayerZeroEscrow(payable(escrow)).processPacket{value: 2806592784579}(hex"", rawMessage, feeRecipient);
    }
}

