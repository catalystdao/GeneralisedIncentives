// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { BaseMultiChainDeployer} from "./BaseMultiChainDeployer.s.sol";

// Import all the Apps for deployment here.
import { IMessageEscrowStructs } from "../src/interfaces/IMessageEscrowStructs.sol";
import { IIncentivizedMessageEscrow } from "../src/interfaces/IIncentivizedMessageEscrow.sol";

import { SimpleApplication } from "./SimpleApplication.sol";

contract SubmitMessage is BaseMultiChainDeployer {
    function submitMessage(address app, bytes32 destinationIdentifier, bytes memory destinationAddress, string memory message, address refundGasTo) external broadcast {
        IMessageEscrowStructs.IncentiveDescription memory incentive = IMessageEscrowStructs.IncentiveDescription({
            maxGasDelivery: 200000,
            maxGasAck: 200000,
            refundGasTo: refundGasTo,
            priceOfDeliveryGas: 1 gwei,
            priceOfAckGas: 1 gwei,
            targetDelta: 0
        });

        uint256 incentiveValue = 200000 * 1 gwei * 2;

        SimpleApplication(payable(app)).submitMessage{value: 2807712706467 + incentiveValue}(
            destinationIdentifier,
            destinationAddress,
            abi.encodePacked(message),
            incentive,
            0
        );
    }

    function setRemoteImplementation(address app, bytes32 destinationIdentifier, bytes calldata implementation) broadcast external {
        SimpleApplication(payable(app)).setRemoteImplementation(destinationIdentifier, implementation);
    }

    function deploySimpleApplication(string[] memory chains, address escrow) iter_chains_string(chains) broadcast external returns(address app) {
        app = address(new SimpleApplication{salt: bytes32(0)}(escrow));
    }
}

