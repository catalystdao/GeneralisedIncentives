// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";


/**
 * @notice To add support for a new chain search this document for "ADD".
 * @dev This contract is intended to be used by defining the deployment functions, say "deploy"
 * function deploy() iter_chains(chain_list) broadcast {}
 * then it will iter over all the chains in chain_list. It may be relevant to create a second function
 * for legacy chains:
 * function deploy() iter_chains(chain_list_legacy) broadcast {}
 */
contract BaseMultiChainDeployer is Script {

    // ADD: Add the chain to the enum here. Please use a descriptive name, including if the chain is
    // a testnet name in the name. This list contains both mainnets and testnets.
    enum Chains {
        // Mainnets
        Base,
        Blast,
        Optimism,
        // Testnets
        Sepolia,
        BaseSepolia,
        ArbitrumSepolia,
        OptimismSepolia,
        BlastTestnet
    }

    mapping(Chains => string) public chainKey;


    Chains[] chain_list;
    Chains[] chain_list_legacy;
    Chains[] chain_list_testnet;
    Chains[] chain_list_testnet_legacy;

    string currentChainKey;

    constructor() {
        chainKey[Chains.Base] = "base";
        chain_list.push(Chains.Base);

        chainKey[Chains.Blast] = "blast";
        chain_list.push(Chains.Blast);

        chainKey[Chains.Optimism] = "optimism";
        chain_list.push(Chains.Optimism);

        chainKey[Chains.Sepolia] = "sepolia";
        chain_list_testnet.push(Chains.Sepolia);
        
        chainKey[Chains.BaseSepolia] = "basesepolia";
        chain_list_testnet.push(Chains.BaseSepolia);

        chainKey[Chains.ArbitrumSepolia] = "arbitrumsepolia";
        chain_list_testnet.push(Chains.ArbitrumSepolia);

        chainKey[Chains.OptimismSepolia] = "optimismsepolia";
        chain_list_testnet.push(Chains.OptimismSepolia);

        chainKey[Chains.BlastTestnet] = "blasttestnet";
        chain_list_testnet.push(Chains.BlastTestnet);

        // ADD: To deploy Generalised Incentives to a new chain, add 2 lines above this comment:
        // chainKey[Chains.OptimismSepolia] = "optimismsepolia"; // What is the external key used to identify this chain? Please add it to .env.example for an RPC key.
        // chain_list.push(Chains.OptimismSepolia); // Is the chain legacy, please specify by pushing to the correct list?
    }

    uint256 pk;

    function selectFork(string memory chain_) internal {
        console.log(vm.envString(chain_));
        vm.createSelectFork(vm.envString(chain_));
    }


    modifier iter_chains(Chains[] memory chains) {
        for (uint256 chainIndex = 0; chainIndex < chains.length; ++chainIndex) {

            currentChainKey = chainKey[chains[chainIndex]];

            selectFork(currentChainKey);

            _;
        }
    }

    modifier iter_chains_string(string[] memory chains) {
        for (uint256 chainIndex = 0; chainIndex < chains.length; ++chainIndex) {

            currentChainKey = chains[chainIndex];

            selectFork(currentChainKey);

            _;
        }
    }

    modifier broadcast() {
        pk = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(pk);

        _;

        vm.stopBroadcast();
    }

    function fund(address toFund, uint256 amount) internal {
        if (toFund.balance >= amount) return;

        payable(toFund).transfer(amount);
    }
}

