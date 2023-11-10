// test/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../../src/apps/wormhole/external/wormhole/Messages.sol";
import "../../src/apps/wormhole/external/wormhole/Setters.sol";
import "../../src/apps/wormhole/external/wormhole/Structs.sol";
import { IMessageEscrowStructs } from "../../src/interfaces/IMessageEscrowStructs.sol";
import { WormholeVerifier } from "../../src/apps/wormhole/external/callworm/WormholeVerifier.sol";
import { SmallStructs } from "../../src/apps/wormhole/external/callworm/SmallStructs.sol";
import { IncentivizedWormholeEscrow } from "../../src/apps/wormhole/IncentivizedWormholeEscrow.sol";
import { Bytes65 } from "../../src/utils/Bytes65.sol";
import "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import "forge-std/Test.sol";

contract ExportedMessages is Messages, Setters {

    function storeGuardianSetPub(Structs.GuardianSet memory set, uint32 index) public {
        return super.storeGuardianSet(set, index);
    }

    event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel);
    
    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence) {
      sequence = nextSequence(msg.sender);
      emit LogMessagePublished(
        msg.sender,
        sequence,
        nonce,
        payload,
        consistencyLevel
      );
    }
}

contract TestRoundtrip is Test, IMessageEscrowStructs, Bytes65 {
  event Debug(bytes);
  event Debug(bytes32);
  IncentiveDescription _INCENTIVE = IncentiveDescription({
    maxGasDelivery: 1199199,
    maxGasAck: 1188188,
    refundGasTo: address(uint160(1)),
    priceOfDeliveryGas: 123321,
    priceOfAckGas: 321123,
    targetDelta: 30 minutes
  });

  function _getTotalIncentive(IncentiveDescription memory incentive) internal pure returns(uint256) {
      return incentive.maxGasDelivery * incentive.priceOfDeliveryGas + incentive.maxGasAck * incentive.priceOfAckGas;
  }
  
  event WormholeMessage(bytes32 destinationIdentifier, bytes32 recipitent);

  bytes32 _DESTINATION_IDENTIFIER;

  address testGuardianPub;
  uint256 testGuardian;

  address sendLostGasTo;

  ExportedMessages messages;

  IIncentivizedMessageEscrow public escrow;

  Structs.GuardianSet guardianSet;

  function setUp() public {
    (testGuardianPub, testGuardian) = makeAddrAndKey("signer");
    sendLostGasTo = makeAddr("sendLostGasTo");

    messages = new ExportedMessages();

    escrow = new IncentivizedWormholeEscrow(sendLostGasTo, address(messages));

    _DESTINATION_IDENTIFIER = bytes32(uint256(messages.chainId()));

    escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

    // initialize guardian set with one guardian
    address[] memory keys = new address[](1);
    keys[0] = vm.addr(testGuardian);
    guardianSet = Structs.GuardianSet(keys, 0);
    require(messages.quorum(guardianSet.keys.length) == 1, "Quorum should be 1");

    // Set the initial guardian set
    address[] memory initialGuardians = new address[](1);
    initialGuardians[0] = testGuardianPub;

    // Create a guardian set
    Structs.GuardianSet memory initialGuardianSet = Structs.GuardianSet({
      keys: initialGuardians,
      expirationTime: 0
    });

    messages.storeGuardianSetPub(initialGuardianSet, uint32(0));
  }

  function makeValidVM(bytes memory payload, uint16 emitterChainid, bytes32 emitterAddress) internal returns(bytes memory validVM) {
    bytes memory presigsVM = abi.encodePacked(
      uint8(1), // version
      uint32(0), // guardianSetIndex
      uint8(1) // signersLen
    );
    bytes memory postsigsVM = abi.encodePacked(
      uint32(block.timestamp),
      uint32(0), // nonce
      emitterChainid,
      emitterAddress,
      uint64(0),  // sequence
      uint8(0),  // consistencyLevel
      payload
    );

    (uint8 v, bytes32 r,  bytes32 s) = vm.sign(testGuardian, keccak256(abi.encodePacked(keccak256(postsigsVM))));

    validVM = abi.encodePacked(
      presigsVM,
      uint8(0),
      r, s, v - 27,
      postsigsVM
    );
  }

  function test_escrow_wormhole_message(bytes calldata message) public {
    vm.assume(message.length != 0);

    IncentiveDescription storage incentive = _INCENTIVE;

    vm.recordLogs();
    (uint256 gasRefund, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
        _DESTINATION_IDENTIFIER,
        convertEVMTo65(address(this)),
        message,
        incentive
    );
    Vm.Log[] memory entries = vm.getRecordedLogs();

    (uint64 sequence, uint32 nonce, bytes memory payload, uint8 consistencyLevel) = abi.decode(
      entries[2].data,
      (uint64, uint32, bytes, uint8)
    );

    bytes memory validVM = makeValidVM(payload, uint16(uint256(_DESTINATION_IDENTIFIER)), bytes32(uint256(uint160(address(escrow)))));

    vm.recordLogs();
    escrow.processPacket(hex"", validVM, bytes32(uint256(0xdead)));
    entries = vm.getRecordedLogs();

    (sequence, nonce, payload, consistencyLevel) = abi.decode(
      entries[2].data,
      (uint64, uint32, bytes, uint8)
    );

    validVM = makeValidVM(payload, uint16(uint256(_DESTINATION_IDENTIFIER)), bytes32(uint256(uint160(address(escrow)))));

    escrow.processPacket(hex"", validVM, bytes32(uint256(0xdead)));
  }
}
