//SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

// IncentivizedMessageEscrow Payload***********************************************************************************************
//
// Common Payload (beginning)
//    CONTEXT                           0   (1 byte)
//    + MESSAGE_IDENTIFIER              1   (32 bytes)
//    + FROM_APPLICATION_LENGTH         33  (1 byte)
//    + FROM_APPLICATION                34  (64 bytes)
// 
// Context-depending Payload
//    CTX0 - 0x00 - Source to Destination
//      + TO_APPLICATION_LENGTH         98  (1 byte)
//      + TO_APPLICATION                99  (64 bytes)
//      + DEADLINE                      163 (8 bytes)
//      + MAX_GAS                       171 (6 bytes)
//     => MESSAGE_START                 177 (remainder)
//
//    CTX1 - 0x01 - Destination to Source
//      + RELAYER_RECIPIENT             98  (32 bytes)
//      + GAS_SPENT                     130 (6 bytes)
//      + EXECUTION_TIME                136 (8 bytes)
//     => MESSAGE_START                 144 (remainder)
//
//    CTX2 - 0x02 - Timed Out on Destination
//      + DEADLINE                      98 (8 bytes)
//      + ORIGIN_BLOCKNUMER             106 (32 bytes)
//     => MESSAGE_START                 138 (remainder)


// Contexts *********************************************************************************************************************

bytes1 constant CTX_SOURCE_TO_DESTINATION       = 0x00;
bytes1 constant CTX_DESTINATION_TO_SOURCE       = 0x01;
bytes1 constant CTX_TIMEDOUT_ON_DESTINATION     = 0x02;


// Common Payload ***************************************************************************************************************

uint constant CONTEXT_POS                       = 0;

uint constant MESSAGE_IDENTIFIER_START          = 1;
uint constant MESSAGE_IDENTIFIER_END            = 33;

uint constant FROM_APPLICATION_LENGTH_POS       = 33;
uint constant FROM_APPLICATION_START            = 34;
uint constant FROM_APPLICATION_START_EVM        = 78;  // If the address is an EVM address, this is the start
uint constant FROM_APPLICATION_END              = 98;


// CTX0 Source to Destination ******************************************************************************************************

uint constant CTX0_TO_APPLICATION_LENGTH_POS        = 98;
uint constant CTX0_TO_APPLICATION_START             = 99;
uint constant CTX0_TO_APPLICATION_START_EVM         = 143;  // If the address is an EVM address, this is the start
uint constant CTX0_TO_APPLICATION_END               = 163;

uint constant CTX0_DEADLINE_START                   = 163;
uint constant CTX0_DEADLINE_END                     = 171;

uint constant CTX0_MAX_GAS_LIMIT_START              = 171;
uint constant CTX0_MAX_GAS_LIMIT_END                = 177;

uint constant CTX0_MESSAGE_START                    = 177;

// CTX1 Destination to Source **************************************************************************************************

uint constant CTX1_RELAYER_RECIPIENT_START          = 98;
uint constant CTX1_RELAYER_RECIPIENT_END            = 130;

uint constant CTX1_GAS_SPENT_START                  = 130;
uint constant CTX1_GAS_SPENT_END                    = 136;

uint constant CTX1_EXECUTION_TIME_START             = 136;
uint constant CTX1_EXECUTION_TIME_END               = 144;

uint constant CTX1_MESSAGE_START                    = 144;

// CTX2 Message Timed out **************************************************************************************************

uint constant CTX2_DEADLINE_START                   = 98;
uint constant CTX2_DEADLINE_END                     = 106;

uint constant CTX2_ORIGIN_BLOCK_NUMBER_START        = 106;
uint constant CTX2_ORIGIN_BLOCK_NUMBER_END          = 138;

uint constant CTX2_MESSAGE_START                    = 138;