//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

// IncentivizedMessageEscrow Payload***********************************************************************************************
//
// Common Payload (beginning)
//    CONTEXT                       0   (1 byte)
//    + FROM_APPLICATION_LENGTH     1   (1 byte)
//    + FROM_APPLICATION            2   (64 bytes)
// 
// Context-depending Payload
//    CTX0 - 0x00 - Source to Destination
//      + TO_VAULT_LENGTH             66  (1 byte)
//      + TO_VAULT                    67  (64 bytes)
//
//    CTX1 - 0x01 - Destination to Source
//      +


// Contexts *********************************************************************************************************************

bytes1 constant SourcetoDestination     = 0x00;
bytes1 constant DestinationtoSource = 0x01;


// Common Payload ***************************************************************************************************************

uint constant CONTEXT_POS                       = 0;

uint constant FROM_APPLICATION_LENGTH_POS      = 1; 
uint constant FROM_APPLICATION_START            = 2; 
uint constant FROM_APPLICATION_START_EVM        = 46;  // If the address is an EVM address, this is the start
uint constant FROM_APPLICATION_END              = 66;


// CTX0 Source to Destination ******************************************************************************************************

uint constant TO_APPLICATION_LENGTH__POS        = 66; 
uint constant TO_APPLICATION_START              = 67; 
uint constant TO_APPLICATION_START_EVM          = 111;  // If the address is an EVM address, this is the start
uint constant TO_APPLICATION_END                = 131;


// CTX1 Destination to Source **************************************************************************************************

