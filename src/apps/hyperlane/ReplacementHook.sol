// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { IPostDispatchHook } from "./interfaces/hooks/IPostDispatchHook.sol";

/// @notice Hyperlane implementation of Generalised incentives.
contract ReplacementHook is IPostDispatchHook {
    /**
     * @notice Returns an enum that represents the type of hook
     */
    function hookType() external pure returns (uint8) {
        return uint8(Types.INTERCHAIN_GAS_PAYMASTER);
    }

    /**
     * @notice Returns whether the hook supports metadata
     * @dev The following params aren't used:
     * param metadata metadata
     * @return Whether the hook supports metadata
     */
    function supportsMetadata(
        bytes calldata /* metadata */
    ) external pure returns (bool) {
        return false;
    }

    /**
     * @notice Post action after a message is dispatched via the Mailbox
     * @dev The following params aren't used:
     * param metadata The metadata required for the hook
     * param message The message passed from the Mailbox.dispatch() call
     */
    function postDispatch(
        bytes calldata /* metadata */,
        bytes calldata /* message */
    ) external payable {
        return;
    }

    /**
     * @notice Compute the payment required by the postDispatch call
     * @dev The following params aren't used:
     * param metadata The metadata required for the hook
     * param message The message passed from the Mailbox.dispatch() call
     * @return Quoted payment for the postDispatch call
     */
    function quoteDispatch(
        bytes calldata /* metadata */,
        bytes calldata /* message */
    ) external pure returns (uint256) {
        return 0;
    }
}