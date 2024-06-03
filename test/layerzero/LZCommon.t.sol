// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { EndpointV2 } from "LayerZero-v2/protocol/contracts/EndpointV2.sol";
import { SimpleMessageLib } from "LayerZero-v2/protocol/contracts/messagelib/SimpleMessageLib.sol";
import { UlnConfig, SetDefaultUlnConfigParam, UlnConfig } from "LayerZero-v2/messagelib/contracts/uln/UlnBase.sol";
import { ReceiveUln302 } from "LayerZero-v2/messagelib/contracts/uln/uln302/ReceiveUln302.sol";
import { SendUln302 } from "LayerZero-v2/messagelib/contracts/uln/uln302/SendUln302.sol";

import "forge-std/Test.sol";
import { MockLayerZeroEscrow } from "./mock/MockLayerZeroEscrow.sol";
import { MockDVN } from "./mock/MockDVN.sol";

contract LZCommon is Test {

    function test() public {}
    uint32 MAX_MESSAGE_SIZE = 65536;
    
    uint32 internal localEid;
    uint32 internal remoteEid;
    EndpointV2 internal endpoint;
    SimpleMessageLib internal simpleMsgLib;
    ReceiveUln302 receiveULN;
    SendUln302 sendULN;
    MockDVN mockDVN;

    address signer;
    uint256 privatekey;

    MockLayerZeroEscrow layerZeroEscrow;

    address SEND_LOST_GAS_TO = address(uint160(0xdead));

    uint32 dvnVID = 1;

    function setUp() virtual public {
        (signer, privatekey) = makeAddrAndKey("signer");

        localEid = 1;
        remoteEid = 2;

        endpoint = new EndpointV2(localEid, address(this));
        sendULN = new SendUln302(address(endpoint), 0, 0);
        receiveULN = new ReceiveUln302(address(endpoint));

        mockDVN = new MockDVN(); 

        address[] memory optionalDVNs = new address[](0);
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = address(mockDVN);

        // Set ULN Config
        UlnConfig memory baseConfig = UlnConfig({
            confirmations: 1,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: optionalDVNs
        });

        SetDefaultUlnConfigParam[] memory _params = new SetDefaultUlnConfigParam[](2);
        _params[0] = SetDefaultUlnConfigParam({
            eid: localEid,
            config: baseConfig
        });
        _params[1] = SetDefaultUlnConfigParam({
            eid: remoteEid,
            config: baseConfig
        });

        sendULN.setDefaultUlnConfigs(_params);
        receiveULN.setDefaultUlnConfigs(_params);

        SimpleMessageLib msgLib = new SimpleMessageLib(address(endpoint), address(0));

        // register msg lib
        endpoint.registerLibrary(address(msgLib));

        endpoint.registerLibrary(address(sendULN));
        endpoint.registerLibrary(address(receiveULN));

        // Set default libs
        endpoint.setDefaultSendLibrary(localEid, address(sendULN));
        endpoint.setDefaultReceiveLibrary(localEid, address(receiveULN), 0);
        endpoint.setDefaultSendLibrary(remoteEid, address(sendULN));
        endpoint.setDefaultReceiveLibrary(remoteEid, address(receiveULN), 0);


        // Setup our mock escrow
        layerZeroEscrow = new MockLayerZeroEscrow(SEND_LOST_GAS_TO, address(endpoint));
    }
}
