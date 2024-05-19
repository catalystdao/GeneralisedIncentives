// SPDX-License-Identifier: LZBL-1.2
// TODO: License

pragma solidity ^0.8.13;

import { IReceiveUlnBase, UlnConfig, Verification } from "./interfaces/IUlnBase.sol";

contract SimpleLZULN {

    IReceiveUlnBase immutable ULTRA_LIGHT_NODE;

    constructor(address ULN) {
        ULTRA_LIGHT_NODE = IReceiveUlnBase(ULN);
    }

    /// @dev for verifiable view function
    /// @dev checks if this verification is ready to be committed to the endpoint
    function _checkVerifiable(
        uint32 _srcEid,
        bytes32 _headerHash,
        bytes32 _payloadHash
    ) internal view returns (bool) {
        UlnConfig memory _config = ULTRA_LIGHT_NODE.getUlnConfig(address(this), _srcEid);
        // iterate the required DVNs
        if (_config.requiredDVNCount > 0) {
            for (uint8 i = 0; i < _config.requiredDVNCount; ++i) {
                if (!_verified(_config.requiredDVNs[i], _headerHash, _payloadHash, _config.confirmations)) {
                    // return if any of the required DVNs haven't signed
                    return false;
                }
            }
            if (_config.optionalDVNCount == 0) {
                // returns early if all required DVNs have signed and there are no optional DVNs
                return true;
            }
        }

        // then it must require optional validations
        uint8 threshold = _config.optionalDVNThreshold;
        for (uint8 i = 0; i < _config.optionalDVNCount; ++i) {
            if (_verified(_config.optionalDVNs[i], _headerHash, _payloadHash, _config.confirmations)) {
                // increment the optional count if the optional DVN has signed
                threshold--;
                if (threshold == 0) {
                    // early return if the optional threshold has hit
                    return true;
                }
            }
        }

        // return false as a catch-all
        return false;
    }

    function _verified(
        address _dvn,
        bytes32 _headerHash,
        bytes32 _payloadHash,
        uint64 _requiredConfirmation
    ) internal view returns (bool verified) {
        Verification memory verification = ULTRA_LIGHT_NODE.hashLookup(_headerHash, _payloadHash, _dvn);
        // return true if the dvn has signed enough confirmations
        verified = verification.submitted && verification.confirmations >= _requiredConfirmation;
    }
}