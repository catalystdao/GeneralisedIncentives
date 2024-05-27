// SPDX-License-Identifier: LZBL-1.2
// TODO: License
pragma solidity ^0.8.13;


// the formal properties are documented in the setter functions
struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}

struct Verification {
    bool submitted;
    uint64 confirmations;
}

interface IReceiveUlnBase {
    // mapping(bytes32 headerHash => mapping(bytes32 payloadHash => mapping(address dvn => Verification))) public hashLookup;
    function hashLookup(bytes32 headerHash, bytes32 payloadHash, address dvn) external view returns (Verification memory);
    
    function getUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory rtnConfig);
}