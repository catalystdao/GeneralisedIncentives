// SPDX-License-Identifier: IncentivizedLayerZeroEscrow
pragma solidity ^0.8.22;

import { ILayerZeroDVN } from "LayerZero-v2/messagelib/contracts/uln/interfaces/ILayerZeroDVN.sol";

/**
 * @notice Mock DVN
 */
contract MockDVN is ILayerZeroDVN {

    function test() public {}
    
    function assignJob(AssignJobParam calldata /* _param */, bytes calldata /* _options */) external payable returns (uint256 fee) {
        return 0;
    }

    function getFee(
        uint32 /* _dstEid */,
        uint64 /* _confirmations */,
        address /* _sender */,
        bytes calldata /* _options */
    ) external pure returns (uint256 fee) {
        return 0;
    } 
}