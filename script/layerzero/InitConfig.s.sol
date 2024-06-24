// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { BaseMultiChainDeployer} from "../BaseMultiChainDeployer.s.sol";

import { IncentivizedLayerZeroEscrow } from "../../src/apps/layerzero/IncentivizedLayerZeroEscrow.sol";

import { ILayerZeroEndpointV2 } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract InitConfigLayerZero is BaseMultiChainDeployer {
    using stdJson for string;

    error IncentivesNotFound();

    string bridge_config;

    bytes32 constant KECCACK_OF_NOTHING = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    // define a list of AMB mappings so we can get their addresses.
    mapping(string => address) escrow;
    mapping(string => uint32 eid) chainEid;

    function _setInitConfig(string[] memory counterPartyChains) internal {
        IncentivizedLayerZeroEscrow lzescrow = IncentivizedLayerZeroEscrow(payable(escrow[currentChainKey]));
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(lzescrow.ENDPOINT());
        endpoint.eid();

        // Get all eids.
        uint32[] memory remoteEids = getEids(counterPartyChains);

        // Get 1 example of the send library.
        address sendLibrary = endpoint.getSendLibrary(address(lzescrow), remoteEids[0]);
        
        lzescrow.initConfig(sendLibrary, remoteEids);
    }
    
    function _initConfig(string[] memory chains, string[] memory counterPartyChains) iter_chains_string(chains) broadcast internal {
        _setInitConfig(counterPartyChains);
    }

    function _loadEids(string[] memory chains) iter_chains_string(chains) internal {
            IncentivizedLayerZeroEscrow lzescrow = IncentivizedLayerZeroEscrow(payable(escrow[currentChainKey]));
            ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(lzescrow.ENDPOINT());
            chainEid[currentChainKey] = endpoint.eid();
    }

    function _loadAllEids(string[] memory chains, string[] memory counterPartyChains) internal {
        _loadEids(combineString(chains, counterPartyChains));
    }

    function initConfig(string[] memory chains, string[] memory counterPartyChains) load_config external {
        _loadAllEids(chains, counterPartyChains);
        _initConfig(chains, counterPartyChains);
    }

    //-- Helpers --//
    function getEids(string[] memory chains) public view returns(uint32[] memory eids) {
        eids = new uint32[](chains.length);
        for (uint256 i = 0; i < chains.length; ++i) {
            eids[i] = chainEid[chains[i]];
        }
    }

    function combineString(string[] memory a, string[] memory b) public pure returns (string[] memory all_chains) {
        all_chains = new string[](a.length + b.length);
        uint256 i = 0;
        for (i = 0; i < a.length; ++i) {
            all_chains[i] = a[i];
        }
        uint256 j = 0;
        for (uint256 p = 0; p < b.length; ++p) {
            string memory selected = b[p];
            bool found = false;
            for (uint256 q = 0; q < a.length; ++q) {
                if (keccak256(abi.encode(a[q])) == keccak256(abi.encode(selected))) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                all_chains[i+j] = selected;
                ++j;
            }
        }
        string[] memory all_chains_copy = all_chains;
        all_chains = new string[](i+j);
        for (i = 0; i < all_chains.length; ++i) {
            all_chains[i] = all_chains_copy[i];
        }
    }

    function filter(string[] memory a, string memory val) public pure returns(string[] memory filtered) {
        filtered = new string[](a.length - 1);
        uint256 j = 0;
        for (uint256 i = 0; i < a.length; ++i) {
            string memory currentElement = a[i];
            if (keccak256(abi.encodePacked(val)) == keccak256(abi.encodePacked(currentElement))) continue;
            filtered[j] = currentElement;
            ++j;
        }
        require(j == a.length - 1, "Invalid Index");  // May be because val is replicated in a.
    }

    modifier load_config() {
        string memory pathRoot = vm.projectRoot();
        string memory pathToAmbConfig = string.concat(pathRoot, "/script/bridge_contracts.json");

        bridge_config = vm.readFile(pathToAmbConfig);

        string memory bridge = "LayerZero";
        // Get the chains this bridge supports.
        string[] memory availableBridgesChains = vm.parseJsonKeys(bridge_config, string.concat(".", bridge));
        for (uint256 j = 0; j < availableBridgesChains.length; ++j) {
            string memory chain = availableBridgesChains[j];
            // Decode the address
            address escrowContract = vm.parseJsonAddress(bridge_config, string.concat(".", bridge, ".", chain, ".escrow"));
            escrow[chain] = escrowContract;
        }

    _;
    }
}

