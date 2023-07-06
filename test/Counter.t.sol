// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/hyperlane/IncentivizedHyperlaneEscrow.sol";

contract HyperlaneTest is Test {
    IncentivizedHyperlaneEscrow public counter;

    function setUp() public {
        counter = new IncentivizedHyperlaneEscrow();
    }
}
