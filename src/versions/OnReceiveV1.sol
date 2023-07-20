// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "../interfaces/IIncentivizedMessageEscrow.sol";

// TODO: Name
/**
 * @title On Receive implementation
 * @author Alexander @ Catalyst
 * @notice // TODO:
 */
abstract contract OnReceiveV1 is IIncentivizedMessageEscrow {
    function implementationVersion() pure override external returns(string memory versionDescriptor) {
        return "OnReceiveV1";
    }
    
}