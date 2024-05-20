// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { BaseMultiChainDeployer} from "./BaseMultiChainDeployer.s.sol";

// Import all the Apps for deployment here.
import { IncentivizedMockEscrow } from "../src/apps/mock/IncentivizedMockEscrow.sol";
import { IncentivizedWormholeEscrow } from "../src/apps/wormhole/IncentivizedWormholeEscrow.sol";
import { IncentivizedPolymerEscrow } from "../src/apps/polymer/vIBCEscrow.sol";
import { IncentivizedLayerZeroEscrow } from "../src/apps/layerzero/IncentivizedLayerZeroEscrow.sol";

contract DeployGeneralisedIncentives is BaseMultiChainDeployer {
    using stdJson for string;

    error IncentivesVersionNotFound();
    
    string incentiveVersion;

    string pathToAmbConfig;

    bool write = true;

    mapping(address => bytes32) deploySalts;

    bytes32 constant KECCACK_OF_NOTHING = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    // define a list of AMB mappings so we can get their addresses.
    mapping(string => mapping(string => address)) bridgeContract;
    // mapping to store ULN addresses
    mapping(string => mapping(string => address)) ulnContract;


    constructor() {
        // Here we can define input salts. These are always assumed to be dependent on the secondary argument
        // to an AMB. (as the first should be send lost gas to which is fixed.)
        // For some AMBs this is a futile efford since they have different deployment adresses.

        deploySalts[0x00000001a9818a7807998dbc243b05F2B3CfF6f4] = bytes32(uint256(1));
    }

    function deployGeneralisedIncentives(string memory version) internal returns(address incentive) {

        bytes32 versionHash = keccak256(abi.encodePacked(version));
        if (versionHash == keccak256(abi.encodePacked("MOCK"))) {
            bytes32 chainIdentifier = bytes32(block.chainid);

            address signer = vm.envAddress("MOCK_SIGNER");

            // Don't use a salt such that the deployer defines the address.
            incentive = address(new IncentivizedMockEscrow(vm.envAddress("SEND_LOST_GAS_TO"), chainIdentifier, signer, 0, 0));

        } else if (versionHash == keccak256(abi.encodePacked("Wormhole"))) {

            address wormholeBridgeContract = bridgeContract[version][currentChainKey];

            bytes32 salt = deploySalts[wormholeBridgeContract];

            require(wormholeBridgeContract != address(0), "bridge cannot be address(0)");

            address expectedAddress = _getAddress(
                abi.encodePacked(
                    type(IncentivizedWormholeEscrow).creationCode,
                    abi.encode(vm.envAddress("SEND_LOST_GAS_TO"), wormholeBridgeContract)
                ),
                salt
            );

            // Check if it is already deployed. If it is, we skip.
            if (expectedAddress.codehash != bytes32(0)) return expectedAddress;

            IncentivizedWormholeEscrow wormholeEscrow = new IncentivizedWormholeEscrow{salt: salt}(vm.envAddress("SEND_LOST_GAS_TO"), wormholeBridgeContract);

            incentive = address(wormholeEscrow);

        } else if (versionHash == keccak256(abi.encodePacked("Polymer"))) {

            address polymerBridgeContract = bridgeContract[version][currentChainKey];

            bytes32 salt = deploySalts[polymerBridgeContract];

            require(polymerBridgeContract != address(0), "bridge cannot be address(0)");

            address expectedAddress = _getAddress(
                abi.encodePacked(
                    type(IncentivizedPolymerEscrow).creationCode,
                    abi.encode(vm.envAddress("SEND_LOST_GAS_TO"), polymerBridgeContract)
                ),
                salt
            );

            // Check if it is already deployed. If it is, we skip.
            if (expectedAddress.codehash != bytes32(0)) return expectedAddress;

            IncentivizedPolymerEscrow polymerEscrow = new IncentivizedPolymerEscrow{salt: salt}(vm.envAddress("SEND_LOST_GAS_TO"), polymerBridgeContract);

            incentive = address(polymerEscrow);

        } else if (versionHash == keccak256(abi.encodePacked("LayerZero"))) {
            address layerZeroBridgeContract = bridgeContract[version][currentChainKey];
            address ulnAddress = ulnContract[version][currentChainKey];
            bytes32 salt = deploySalts[layerZeroBridgeContract];
            require(layerZeroBridgeContract != address(0), "bridge cannot be address(0)");
            require(ulnAddress != address(0), "ULN cannot be address(0)");

            address expectedAddress = _getAddress(
                abi.encodePacked(
                    type(IncentivizedLayerZeroEscrow).creationCode,
                    abi.encode(vm.envAddress("SEND_LOST_GAS_TO"), layerZeroBridgeContract, ulnAddress)
                ),
                salt
            );

            if (expectedAddress.codehash != bytes32(0)) return expectedAddress;

            IncentivizedLayerZeroEscrow layerZeroEscrow = new IncentivizedLayerZeroEscrow{salt: salt}(vm.envAddress("SEND_LOST_GAS_TO"), layerZeroBridgeContract, ulnAddress);
            incentive = address(layerZeroEscrow);
        } else {
            revert IncentivesVersionNotFound();
        }


        console.log(string.concat("Deployed", version ,"Escrow at"));
        console.logAddress(incentive);

        if (write) write_config(incentive, version, currentChainKey);

        return incentive;
    }

    modifier load_config() {
        
        string memory pathRoot = vm.projectRoot();
        pathToAmbConfig = string.concat(pathRoot, "/script/bridge_contracts.json");

        string memory bridge_config = vm.readFile(pathToAmbConfig);

        // Get the bridges available
        string[] memory availableBridges = vm.parseJsonKeys(bridge_config, "$");

        // For each bridge, decode their contracts for each chain.
        for (uint256 i = 0; i < availableBridges.length; ++i) {
            string memory bridge = availableBridges[i];
            // Get the chains this bridge supports.
            string[] memory availableBridgesChains = vm.parseJsonKeys(bridge_config, string.concat(".", bridge));
            for (uint256 j = 0; j < availableBridgesChains.length; ++j) {
                string memory chain = availableBridgesChains[j];
                // Decode the address
                address _bridgeContract = vm.parseJsonAddress(bridge_config, string.concat(".", bridge, ".", chain, ".bridge"));
                bridgeContract[bridge][chain] = _bridgeContract;

                // Check if the bridge is LayerZero
                if (keccak256(abi.encodePacked(bridge)) == keccak256(abi.encodePacked("LayerZero"))) {
                    // Read the ULN address
                    address ulnAddress = vm.parseJsonAddress(bridge_config, string.concat(".", bridge, ".", chain, ".ULN"));
                    ulnContract[bridge][chain] = ulnAddress;
                }
            }
        }

        _;
    }

    // get the computed address before the contract DeployWithCreate2 deployed using Bytecode of contract
    function _getAddress(bytes memory bytecode, bytes32 _salt) internal pure returns (address) {
        bytes32 create2Hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(0x4e59b44847b379578588920cA78FbF26c0B4956C), _salt, keccak256(bytecode)
            )
        );
        return address(uint160(uint(create2Hash)));
    }

    function write_config(address escrow, string memory bridge, string memory chain) internal {
        vm.writeJson(
            vm.toString(escrow),
            pathToAmbConfig,
            string.concat(".", bridge, ".", chain, ".escrow")
        );
    }

    modifier forEachBridge(string[] memory bridges) {
        for (uint256 i = 0; i < bridges.length; ++i) {
            string memory bridge = bridges[i];
            incentiveVersion = bridge;
            _;
        }
    }

    function deployEscrow(string[] memory bridges) forEachBridge(bridges) internal {
        deployGeneralisedIncentives(incentiveVersion);
    }
    
    function _deploy(string[] memory bridges) internal {
        deployEscrow(bridges);
    }

    function deploy(string[] memory bridges, string[] memory chains) load_config iter_chains_string(chains) broadcast external {
        _deploy(bridges);
    }

    function deploy(string[] memory bridges, string[] memory chains, bool _write) load_config iter_chains_string(chains) broadcast external {
        write = _write;
        _deploy(bridges);
    }

    function deployAll(string[] memory bridges) load_config iter_chains(chain_list) broadcast external {
        _deploy(bridges);
    }

    function deployAllLegacy(string[] memory bridges) load_config iter_chains(chain_list_legacy) broadcast external {
        _deploy(bridges);
    }
}

