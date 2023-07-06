// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IApplication {
    function ackMessage() external;

    function receiveMessage() external;
}