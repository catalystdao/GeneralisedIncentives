// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title This contract does not implement a fallback, as a result it cannot collect gas payments.
 *  If gas is sent here, it will not arrive and instead be sent somewhere else.
 */
contract BadlyDesignedRefundTo {
}
