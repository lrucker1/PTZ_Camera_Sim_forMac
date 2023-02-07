/*
    Copyright 2021 Jacob Rau
    
    This file is part of libjr_visca.

    libjr_visca is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    libjr_visca is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with libjr_visca.  If not, see <https://www.gnu.org/licenses/>.
*/

/*
            Command Packet      Note
 Inquiry    8X QQ RR ... FF     QQ1) = Command/Inquiry,
                                RR2) = category code
 1) QQ = 01 (Command), 09 (Inquiry)
 2) RR = 00 (Interface), 04 (camera 1), 06 (Pan/Tilter)
 Sony also has a camera 2 0x07
 Macros: 04 COMMAND, 06 SYSCMD
 */

#include "jr_visca.h"

#include <string.h>
#include <stdio.h>
#include <stdbool.h>

typedef struct {
    uint8_t sender;
    uint8_t receiver;
    uint8_t data[JR_VISCA_MAX_ENCODED_MESSAGE_DATA_LENGTH - 2];
    uint8_t dataLength;
} jr_viscaFrame;

/**
 * Extract a frame from the given buffer.
 * 
 * `data` is a buffer containing VISCA data. It can be truncated or contain
 * multiple frames.
 * `dataLength` is the count of bytes in `data`.
 * 
 * If at least one full frame is present, it will be written to `frame`.
 * 
 * If less than one full frame is present in `buffer`, returns `0`.
 * 
 * If data corruption is detected (e.g. too many bytes occur before the end-of-frame marker),
 * returns `-1`.
 */
int jr_viscaDataToFrame(uint8_t *data, int dataLength, jr_viscaFrame *frame) {
    // We only decode a frame if the entire frame is present, i.e. 0xff terminator is present.
    int terminatorIndex;
    for (terminatorIndex = 0; terminatorIndex < dataLength; terminatorIndex++) {
        if (data[terminatorIndex] == 0xff) {
            break;
        }
    }

    // If we didn't find a terminator, the index will == dataLength.
    if (!(terminatorIndex < dataLength)) {
        // No bytes consumed, since we're waiting for more bytes to arrive.
        return 0;
    }

    if (terminatorIndex > JR_VISCA_MAX_ENCODED_MESSAGE_DATA_LENGTH - 2 - 1) {
        // All our internal buffers are fixed-length. If the frame exceeds that length, bail.
        return -1;
    }

    if (terminatorIndex == 0) {
        // If no header present, flag an error.
        return -1;
    }

    // First byte is header containing sender and receiver addresses.
    // Except for Address Set (aka Camera Number) and IFClear(Broadcast), which are 0x88, but they don't apply to visca over IP.
    frame->sender = (data[0] >> 4) & 0x7;
    frame->receiver = data[0] & 0xF;

    // N bytes of packet data between header byte and 0xff terminator.
    memcpy(frame->data, data + 1, terminatorIndex - 1);

    frame->dataLength = terminatorIndex - 1;

    return terminatorIndex + 1;
}

int jr_viscaFrameToData(uint8_t *data, int dataLength, jr_viscaFrame frame) {
    if (frame.dataLength + 2 > dataLength) {
        return -1;
    }

    if ((frame.sender > 7) || (frame.receiver > 0xF)) {
        return -1;
    }

    data[0] = 0x80 + (frame.sender << 4) + frame.receiver;
    memcpy(data + 1, frame.data, frame.dataLength);
    data[frame.dataLength + 1] = 0xff;
    return frame.dataLength + 2;
}

typedef struct {
    uint8_t signature[JR_VISCA_MAX_ENCODED_MESSAGE_DATA_LENGTH - 2];
    uint8_t signatureMask[JR_VISCA_MAX_ENCODED_MESSAGE_DATA_LENGTH - 2];
    int signatureLength;
    int commandType;
    void (*handleParameters)(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame);
} jr_viscaMessageDefinition;

/**
 * `buffer` looks like 0x01 0x02 0x03 0x04
 * Returned result will look like 0x1234
 * This is a common way for VISCA to bit pack things.
 */
int16_t _jr_viscaRead16FromBuffer(uint8_t *buffer) {
    int16_t result = 0;
    result += (buffer[0] & 0xf) * 0x1000;
    result += (buffer[1] & 0xf) * 0x100;
    result += (buffer[2] & 0xf) * 0x10;
    result += (buffer[3] & 0xf);
    return result;
}

/**
 * Given `value` looks like 0x1234
 * `buffer` will look like 0x01 0x02 0x03 0x04
 * We won't touch the upper nibble of each byte-- it may be significant per the specific comand.
 */
void _jr_viscaWrite16ToBuffer(int16_t value, uint8_t *buffer) {
    buffer[0] |= (value >> 12) & 0xf;
    buffer[1] |= (value >> 8) & 0xf;
    buffer[2] |= (value >> 4) & 0xf;
    buffer[3] |= value & 0xf;
}

/**
 * `buffer` looks like 0x01 0x02
 * Returned result will look like 0x12
 * This is a common way for VISCA to bit pack things.
 */
int16_t _jr_viscaRead8FromBuffer(uint8_t *buffer) {
    int16_t result = 0;
    result += (buffer[0] & 0xf) * 0x10;
    result += (buffer[1] & 0xf);
    return result;
}

void _jr_viscaWrite8ToBuffer(int16_t value, uint8_t *buffer) {
    buffer[0] |= (value >> 4) & 0xf;
    buffer[1] |= value & 0xf;
}

void jr_visca_handlePanTiltPositionInqResponseParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->panTiltPositionInqResponseParameters.panPosition = _jr_viscaRead16FromBuffer(frame->data + 1);
        messageParameters->panTiltPositionInqResponseParameters.tiltPosition = _jr_viscaRead16FromBuffer(frame->data + 5);
    } else {
        _jr_viscaWrite16ToBuffer(messageParameters->panTiltPositionInqResponseParameters.panPosition, frame->data + 1);
        _jr_viscaWrite16ToBuffer(messageParameters->panTiltPositionInqResponseParameters.tiltPosition, frame->data + 5);
    }
}

// AbsolutePosition [81] 01 06 02 [3]VV [4]WW [5]0Y 0Y 0Y 0Y [9]0Z 0Z 0Z 0Z FF
// VV: Pan speed 0x01 (low speed) to 0x18 (high speed)
// WW: Tilt speed 0x01 (low speed) to 0x14 (high speed)
// YYYY: Pan Position
// ZZZZ: Tilt Position
void jr_visca_handleAbsolutePanTiltPositionParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->absolutePanTiltPositionParameters.panSpeed = frame->data[3] & 0xf;
        messageParameters->absolutePanTiltPositionParameters.tiltSpeed = frame->data[4] & 0xf;
        messageParameters->absolutePanTiltPositionParameters.panPosition = _jr_viscaRead16FromBuffer(frame->data + 5);
        messageParameters->absolutePanTiltPositionParameters.tiltPosition = _jr_viscaRead16FromBuffer(frame->data + 9);
    } else {
        frame->data[3] = messageParameters->absolutePanTiltPositionParameters.panSpeed;
        frame->data[4] = messageParameters->absolutePanTiltPositionParameters.tiltSpeed;
        _jr_viscaWrite16ToBuffer(messageParameters->absolutePanTiltPositionParameters.panPosition, frame->data + 5);
        _jr_viscaWrite16ToBuffer(messageParameters->absolutePanTiltPositionParameters.tiltPosition, frame->data + 9);
    }
}

void jr_visca_handleAckCompletionParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->ackCompletionParameters.socketNumber = frame->data[0] & 0xf;
    } else {
        frame->data[0] += messageParameters->ackCompletionParameters.socketNumber;
    }
}


void jr_visca_handleErrorReplyParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->errorReplyParameters.socketNumber = frame->data[0] & 0xf;
        messageParameters->errorReplyParameters.errorType = frame->data[1];
    } else {
        frame->data[0] += messageParameters->errorReplyParameters.socketNumber;
        frame->data[1] += messageParameters->errorReplyParameters.errorType;
    }
}

void jr_visca_handleCameraNumberParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    // Request: 88 30 01 FF, reply: 88 30 0w FF, w is 2-8 (camera+1)
    if (isDecodingFrame) {
        messageParameters->cameraNumberParameters.cameraNum = frame->data[1] & 0xf;
    } else {
        frame->data[1] += messageParameters->cameraNumberParameters.cameraNum;
    }
}

void jr_visca_handleMemoryParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->memoryParameters.memory = frame->data[4] & 0xff;
        messageParameters->memoryParameters.mode = frame->data[3] & 0xff;
    } else {
        frame->data[4] = messageParameters->memoryParameters.memory;
    }
}

void jr_visca_handlePQRSCommandParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->int16Parameters.int16Value = _jr_viscaRead16FromBuffer(frame->data + 3);
    } else {
        _jr_viscaWrite16ToBuffer(messageParameters->int16Parameters.int16Value, frame->data + 3);
    }
}

void jr_visca_handlePQCommandParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->int16Parameters.int16Value = _jr_viscaRead8FromBuffer(frame->data + 3);
    } else {
        _jr_viscaWrite8ToBuffer(messageParameters->int16Parameters.int16Value, frame->data + 3);
    }
}

void jr_visca_handlePanTiltDriveParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->panTiltDriveParameters.panDirection = frame->data[5];
        messageParameters->panTiltDriveParameters.tiltDirection = frame->data[6];
        messageParameters->panTiltDriveParameters.panSpeed = frame->data[3];
        messageParameters->panTiltDriveParameters.tiltSpeed = frame->data[4];
    } else {
        frame->data[3] = messageParameters->panTiltDriveParameters.panSpeed;
        frame->data[4] = messageParameters->panTiltDriveParameters.tiltSpeed;
        frame->data[5] = messageParameters->panTiltDriveParameters.panDirection;
        frame->data[6] = messageParameters->panTiltDriveParameters.tiltDirection;
    }
}

void jr_visca_handleOneByteInqResponseParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->oneByteParameters.byteValue = frame->data[1] & 0xff;
    } else {
        frame->data[1] = messageParameters->oneByteParameters.byteValue;
    }
}

void jr_visca_handlePInqResponseParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->oneByteParameters.byteValue = frame->data[1] & 0x0f;
    } else {
        frame->data[1] = messageParameters->oneByteParameters.byteValue;
    }
}

void jr_visca_handlePQRSInqResponseParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->int16Parameters.int16Value = _jr_viscaRead16FromBuffer(frame->data + 1);
    } else {
        _jr_viscaWrite16ToBuffer(messageParameters->int16Parameters.int16Value, frame->data + 1);
    }
}
void jr_visca_handlePQInqResponseParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->int16Parameters.int16Value = _jr_viscaRead8FromBuffer(frame->data + 1);
    } else {
        _jr_viscaWrite8ToBuffer(messageParameters->int16Parameters.int16Value, frame->data + 1);
    }
}

void jr_visca_handleOneByteCommandParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->oneByteParameters.byteValue = frame->data[3] & 0xff;
    } else {
        frame->data[3] = messageParameters->oneByteParameters.byteValue;
    }
}

void jr_visca_handlePCommandParameters(jr_viscaFrame* frame, union jr_viscaMessageParameters *messageParameters, bool isDecodingFrame) {
    if (isDecodingFrame) {
        messageParameters->oneByteParameters.byteValue = frame->data[3] & 0x0f;
    } else {
        frame->data[3] += messageParameters->oneByteParameters.byteValue;
    }
}

#define MESSAGE_INQ(_cmd, _enum)    \
{                                   \
    {0x09, 0x04, (_cmd)},           \
    {0xff, 0xff, 0xff},             \
    3,                              \
    (_enum),                        \
    NULL                            \
}

#define MESSAGE_ONE_BYTE_VALUE_SET(_cmd, _enum) \
{                                   \
    {0x01, 0x04, (_cmd), 0x00},     \
    {0xff, 0xff, 0xff, 0x00},       \
    4,                              \
    (_enum),                        \
    &jr_visca_handleOneByteCommandParameters \
}

#define MESSAGE_P_VALUE_SET(_cmd, _enum) \
{                                   \
    {0x01, 0x04, (_cmd), 0x00},     \
    {0xff, 0xff, 0xff, 0xf0},       \
    4,                              \
    (_enum),                        \
    &jr_visca_handlePCommandParameters \
}

#define MESSAGE_PQ_VALUE_SET(_cmd, _enum)   \
{                                           \
    {0x01, 0x04, (_cmd), 0x00, 0x00},       \
    {0xff, 0xff, 0xff, 0xf0, 0xf0},         \
    5,                                      \
    (_enum),                                \
    &jr_visca_handlePQCommandParameters     \
}

#define MESSAGE_PQRS_VALUE_SET(_cmd, _enum)   \
{                                               \
    {0x01, 0x04, (_cmd), 0x00, 0x00, 0x00, 0x00},\
    {0xff, 0xff, 0xff, 0xf0, 0xf0, 0xf0, 0xf0}, \
    7,                                          \
    (_enum),                                    \
    &jr_visca_handlePQRSCommandParameters       \
}

#define MESSAGE_SUBCOMMAND_SET(_cmd, _sub, _enum)   \
{                                   \
    {0x01, 0x04, (_cmd), (_sub)},   \
    {0xff, 0xff, 0xff, 0xff},       \
    4,                              \
    (_enum),                        \
    NULL                            \
}

// Subcommands in the form Sp, where S is the command
// See also MESSAGE_P_VALUE_SET
#define MESSAGE_SUBCOMMAND_P_VALUE_SET(_cmd, _sub, _enum)   \
{                                   \
    {0x01, 0x04, (_cmd), (_sub)},   \
    {0xff, 0xff, 0xff, 0xf0},       \
    4,                              \
    (_enum),                        \
    jr_visca_handlePCommandParameters   \
}

#define SYSCMD_INQ(_cmd, _enum)     \
{                                   \
    {0x09, 0x06, (_cmd)},           \
    {0xff, 0xff, 0xff},             \
    3,                              \
    (_enum),                        \
    NULL                            \
}

#define SYSCMD_SET(_cmd, _enum)     \
{                                   \
    {0x01, 0x06, (_cmd)},           \
    {0xff, 0xff, 0xff},             \
    3,                              \
    (_enum),                        \
    NULL                            \
}

#define SYSCMD_SUBCOMMAND_SET(_cmd, _sub, _enum)   \
{                                   \
    {0x01, 0x06, (_cmd), (_sub)},   \
    {0xff, 0xff, 0xff, 0xff},       \
    4,                              \
    (_enum),                        \
    NULL                            \
}

#define SYSCMD_ONE_BYTE_VALUE_SET(_cmd, _enum) \
{                                   \
    {0x01, 0x06, (_cmd), 0x00},     \
    {0xff, 0xff, 0xff, 0x00},       \
    4,                              \
    (_enum),                        \
    &jr_visca_handleOneByteCommandParameters \
}

#pragma mark definitions
jr_viscaMessageDefinition definitions[] = {
    // Generic 1-byte response: [90 50 xx FF] and ok for [90 50 0p FF]
    {
        {0x50, 0x00},
        {0xff, 0x00},
        2,
        JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE,
        &jr_visca_handleOneByteInqResponseParameters
    },
    // Generic 1-byte response: [90 50 Xp FF] when you need the mask because X may be non-zero
    {
        {0x50, 0x00},
        {0xff, 0xf0},
        2,
        JR_VISCA_MESSAGE_P_RESPONSE,
        &jr_visca_handlePInqResponseParameters
    },
    // Generic response: 90 50 0p 0q 0r 0s FF
    {
        {0x50, 0x00, 0x00, 0x00, 0x00},
        {0xff, 0xf0, 0xf0, 0xf0, 0xf0},
        5,
        JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE,
        &jr_visca_handlePQRSInqResponseParameters
    },
    // Generic response: 90 50 0p 0q FF
    {
        {0x50, 0x00, 0x00},
        {0xff, 0xf0, 0xf0},
        3,
        JR_VISCA_MESSAGE_PQ_INQ_RESPONSE,
        &jr_visca_handlePQInqResponseParameters
    },
    {
        {0x09, 0x06, 0x12}, //signature
        {0xff, 0xff, 0xff}, //signatureMask
        3, //signatureLength
        JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ, //commandType
        NULL //handleParameters
    },
    {
        // pan (signed) = 0xstuv
        // tilt (signed) = 0xwxyz
        //        s     t     u     v     w     y     x     z
        {0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
        {0xff, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0},
        9,
        JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ_RESPONSE,
        &jr_visca_handlePanTiltPositionInqResponseParameters
    },
    {
        {0x40},
        {0xf0},
        1,
        JR_VISCA_MESSAGE_ACK,
        &jr_visca_handleAckCompletionParameters
    },
    {
        {0x50},
        {0xf0},
        1,
        JR_VISCA_MESSAGE_COMPLETION,
        &jr_visca_handleAckCompletionParameters
    },
    MESSAGE_SUBCOMMAND_SET(0x07, 0x00, JR_VISCA_MESSAGE_ZOOM_STOP),
    MESSAGE_SUBCOMMAND_SET(0x07, 0x02, JR_VISCA_MESSAGE_ZOOM_TELE_STANDARD),
    MESSAGE_SUBCOMMAND_SET(0x07, 0x03, JR_VISCA_MESSAGE_ZOOM_WIDE_STANDARD),
    MESSAGE_SUBCOMMAND_P_VALUE_SET(0x07, 0x20, JR_VISCA_MESSAGE_ZOOM_TELE_VARIABLE),
    MESSAGE_SUBCOMMAND_P_VALUE_SET(0x07, 0x30, JR_VISCA_MESSAGE_ZOOM_WIDE_VARIABLE),
    MESSAGE_SUBCOMMAND_SET(0x08, 0x00, JR_VISCA_MESSAGE_FOCUS_STOP),
    MESSAGE_SUBCOMMAND_SET(0x08, 0x02, JR_VISCA_MESSAGE_FOCUS_FAR_STANDARD),
    MESSAGE_SUBCOMMAND_SET(0x08, 0x03, JR_VISCA_MESSAGE_FOCUS_NEAR_STANDARD),
    MESSAGE_SUBCOMMAND_P_VALUE_SET(0x08, 0x20, JR_VISCA_MESSAGE_FOCUS_FAR_VARIABLE),
    MESSAGE_SUBCOMMAND_P_VALUE_SET(0x08, 0x30, JR_VISCA_MESSAGE_FOCUS_NEAR_VARIABLE),
    // Pan_TiltDrive
    {
        {0x01, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00},
        {0xff, 0xff, 0xff, 0xe0, 0xe0, 0xf0, 0xf0},
        7,
        JR_VISCA_MESSAGE_PAN_TILT_DRIVE,
        &jr_visca_handlePanTiltDriveParameters
    },
    {
        {0x30, 0x01},
        {0xff, 0xff},
        2,
        JR_VISCA_MESSAGE_CAMERA_NUMBER,
        &jr_visca_handleCameraNumberParameters
    },
    {
        {0x01, 0x04, 0x3f, 0x00, 0x00},
        {0xff, 0xff, 0xff, 0x00, 0x00},
        5,
        JR_VISCA_MESSAGE_MEMORY,
        &jr_visca_handleMemoryParameters
    },
    {
        {0x01, 0x00, 0x01},
        {0xff, 0xff, 0xff},
        3,
        JR_VISCA_MESSAGE_CLEAR,
        NULL
    },
    // CAM_PTZMotionSync 81 0A 11 13 xx FF
    // xx is off/on [02 03]
    // No Inq
    {
        {0x0A, 0x11, 0x13, 0x00},
        {0xff, 0xff, 0xff, 0x00},
        4,
        JR_VISCA_MESSAGE_MOTION_SYNC,
        NULL
    },
    SYSCMD_ONE_BYTE_VALUE_SET(0x01, JR_VISCA_MESSAGE_PRESET_RECALL_SPEED),
    {   // 01 06 02        VV    WW     0Y 0Y 0Y 0Y              0Z 0Z 0Z 0Z
        {0x01, 0x06, 0x02, 0x00, 0x00,  0x00, 0x00, 0x00, 0x00,  0x00, 0x00, 0x00, 0x00},
        {0xff, 0xff, 0xff, 0x00, 0x00,  0xf0, 0xf0, 0xf0, 0xf0,  0xf0, 0xf0, 0xf0, 0xf0},
        13,
        JR_VISCA_MESSAGE_ABSOLUTE_PAN_TILT,
        &jr_visca_handleAbsolutePanTiltPositionParameters
    },
    SYSCMD_SET(0x04, JR_VISCA_MESSAGE_HOME),
    SYSCMD_SET(0x05, JR_VISCA_MESSAGE_RESET),
    {   // Cancel 81 2z FF - supported by some cameras but apparently not PTZOptics, which returns syntax error instead of cancel reply. But it does interrupt the current operation.
        {0x20},
        {0xf0},
        1,
        JR_VISCA_MESSAGE_CANCEL,
        NULL
    },
    SYSCMD_SUBCOMMAND_SET(0x06, 0x05, JR_VISCA_MESSAGE_MENU_ENTER),
    SYSCMD_SUBCOMMAND_SET(0x06, 0x04, JR_VISCA_MESSAGE_MENU_RETURN),
    SYSCMD_ONE_BYTE_VALUE_SET(0x06, JR_VISCA_MESSAGE_SONY_MENU_MODE),
    // Sony Menu Enter : 8x 01 7E 01 02 00 01 FF
    {
        {0x01, 0x7E, 0x01, 0x02, 0x00, 0x01},
        {0xff, 0xff, 0xff, 0xff, 0xff, 0xff},
        6,
        JR_VISCA_MESSAGE_SONY_MENU_ENTER,
        NULL
    },
    SYSCMD_INQ(0x06, JR_VISCA_MESSAGE_MENU_MODE_INQ),
    // CAM_Bright 81 01 04 0D 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0x0D, JR_VISCA_MESSAGE_BRIGHT_DIRECT),
    MESSAGE_INQ(0x4D, JR_VISCA_MESSAGE_BRIGHT_POS_INQ),
    // CAM_ColorTemp Direct 81 01 04 20 0p 0q FF
    MESSAGE_PQ_VALUE_SET(0x20, JR_VISCA_MESSAGE_COLOR_TEMP_DIRECT),
    MESSAGE_INQ(0x20, JR_VISCA_MESSAGE_COLOR_TEMP_INQ),
    // CAM_Flicker CAM_Flicker 81 01 04 23 xx FF
    // p: Flicker Settings - (0: Off, 1: 50Hz, 2: 60Hz)
    MESSAGE_ONE_BYTE_VALUE_SET(0x23, JR_VISCA_MESSAGE_FLICKER_MODE),
    MESSAGE_INQ(0x55, JR_VISCA_MESSAGE_FLICKER_MODE_INQ),
    // CAM_Gain Gain Limit 81 01 04 2C 0p FF
    MESSAGE_P_VALUE_SET(0x2C, JR_VISCA_MESSAGE_GAIN_LIMIT),
    MESSAGE_INQ(0x2C, JR_VISCA_MESSAGE_GAIN_LIMIT_INQ),
    // CAM_WB  81 01 04 35 xx FF
    // xx is one of [01 02 03 05 20]
    MESSAGE_ONE_BYTE_VALUE_SET(0x35, JR_VISCA_MESSAGE_WB_MODE),
    MESSAGE_INQ(0x35, JR_VISCA_MESSAGE_WB_MODE_INQ),
    // CAM_Focus
    // Reply:AF 90 50 02 FF
    // Reply:M  90 50 03 FF
    MESSAGE_SUBCOMMAND_SET(0x38, 0x02, JR_VISCA_MESSAGE_FOCUS_AUTOMATIC),
    MESSAGE_SUBCOMMAND_SET(0x38, 0x03, JR_VISCA_MESSAGE_FOCUS_MANUAL),
    MESSAGE_INQ(0x38, JR_VISCA_MESSAGE_FOCUS_AF_MODE_INQ),
    // CAM_AE 81 01 04 39 xx FF
    // xx is [00 03 0A 0B 0D]
    MESSAGE_ONE_BYTE_VALUE_SET(0x39, JR_VISCA_MESSAGE_AE_MODE),
    MESSAGE_INQ(0x39, JR_VISCA_MESSAGE_AE_MODE_INQ),
    // CAM_Aperture(sharpness) 81 01 04 42 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0x42, JR_VISCA_MESSAGE_APERTURE_VALUE),
    MESSAGE_INQ(0x42, JR_VISCA_MESSAGE_APERTURE_VALUE_INQ),
    // CAM_RGain 81 01 04 43 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0x43, JR_VISCA_MESSAGE_RGAIN_VALUE),
    MESSAGE_INQ(0x43, JR_VISCA_MESSAGE_RGAIN_VALUE_INQ),
    // CAM_BGain 81 01 04 44 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0x44, JR_VISCA_MESSAGE_BGAIN_VALUE),
    MESSAGE_INQ(0x44, JR_VISCA_MESSAGE_BGAIN_VALUE_INQ),
    // CAM_Zoom Direct 81 01 04 47 p q r s FF
    MESSAGE_PQRS_VALUE_SET(0x47, JR_VISCA_MESSAGE_ZOOM_DIRECT),
    MESSAGE_INQ(0x47, JR_VISCA_MESSAGE_ZOOM_POSITION_INQ),
    // CAM_Focus Direct 81 01 04 48 0p 0q 0r 0s FF
    MESSAGE_PQRS_VALUE_SET(0x48, JR_VISCA_MESSAGE_FOCUS_VALUE),
    MESSAGE_INQ(0x48, JR_VISCA_MESSAGE_FOCUS_VALUE_INQ),
    // CAM_ColorGain Direct 81 01 04 49 00 00 00 0p FF
    // p: Color Gain setting 0h (60%) to Eh (200%)
    MESSAGE_PQRS_VALUE_SET(0x49, JR_VISCA_MESSAGE_COLOR_GAIN_DIRECT),
    MESSAGE_INQ(0x49, JR_VISCA_MESSAGE_COLOR_GAIN_INQ),
    // CAM_Shutter Direct 81 01 04 4A 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0x4A, JR_VISCA_MESSAGE_SHUTTER_VALUE),
    MESSAGE_INQ(0x4A, JR_VISCA_MESSAGE_SHUTTER_POS_INQ),
    // Iris Direct 81 01 04 4B 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0x4B, JR_VISCA_MESSAGE_IRIS_VALUE),
    MESSAGE_INQ(0x4B, JR_VISCA_MESSAGE_IRIS_POS_INQ),
    // CAM_ColorHue Direct 81 01 04 4F 00 00 00 0p FF
    // p: Color Hue setting 0h (− 14 dgrees) to Eh ( +14 degrees)
    MESSAGE_PQRS_VALUE_SET(0x4F, JR_VISCA_MESSAGE_COLOR_HUE_DIRECT),
    MESSAGE_INQ(0x4F, JR_VISCA_MESSAGE_COLOR_HUE_INQ),
    // CAM_LR_Reverse (flipH)  81 01 04 61 xx FF
    // xx is off/on [02 03]
    MESSAGE_ONE_BYTE_VALUE_SET(0x61, JR_VISCA_MESSAGE_LR_REVERSE),
    MESSAGE_INQ(0x61, JR_VISCA_MESSAGE_LR_REVERSE_INQ),
    // CAM_PictureEffect  81 01 04 63 xx FF
    // xx is (00:Off, 04:B&W), or others depending on camera
    MESSAGE_ONE_BYTE_VALUE_SET(0x63, JR_VISCA_MESSAGE_PICTURE_EFFECT),
    MESSAGE_INQ(0x63, JR_VISCA_MESSAGE_PICTURE_EFFECT_INQ),
    // CAM_PictureFlip (flipV) 81 01 04 66 02 FF
    // xx is off/on [02 03]
    MESSAGE_ONE_BYTE_VALUE_SET(0x66, JR_VISCA_MESSAGE_PICTURE_FLIP),
    MESSAGE_INQ(0x66, JR_VISCA_MESSAGE_PICTURE_FLIP_INQ),
    // CAM_Brightness Direct 81 01 04 A1 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0xA1, JR_VISCA_MESSAGE_BRIGHTNESS),
    MESSAGE_INQ(0xA1, JR_VISCA_MESSAGE_BRIGHTNESS_INQ),
    // CAM_Contrast Direct 81 01 04 A2 00 00 0p 0q FF
    MESSAGE_PQRS_VALUE_SET(0xA2, JR_VISCA_MESSAGE_CONTRAST),
    MESSAGE_INQ(0xA2, JR_VISCA_MESSAGE_CONTRAST_INQ),
    // CAM_AWBSensitivity 81 01 04 A9 xx FF
    // xx is 00=high 01=normal 02=low
    MESSAGE_ONE_BYTE_VALUE_SET(0xA9, JR_VISCA_MESSAGE_AWB_SENS),
    MESSAGE_INQ(0xA9, JR_VISCA_MESSAGE_AWB_SENS_INQ),
    { {}, {}, 0, 0, NULL} // Final definition must have `signatureLength` == 0.
};

void _jr_viscahex_print(char *buf, int buf_size) {
    for (int i = 0; i < buf_size; i++) {
        printf("%02hhx ", buf[i]);
    }
}

void _jr_viscaMemAnd(uint8_t *a, uint8_t *b, uint8_t *output, int length) {
    for (int i = 0; i < length; i++) {
        output[i] = a[i] & b[i];
    }
}

int jr_viscaDecodeFrame(jr_viscaFrame frame, union jr_viscaMessageParameters *messageParameters) {
    int i = 0;
    while (definitions[i].signatureLength) {
        uint8_t maskedFrame[JR_VISCA_MAX_ENCODED_MESSAGE_DATA_LENGTH - 2];
        _jr_viscaMemAnd(frame.data, definitions[i].signatureMask, maskedFrame, frame.dataLength);
        if (   (frame.dataLength == definitions[i].signatureLength)
            && (memcmp(maskedFrame, definitions[i].signature, definitions[i].signatureLength) == 0)) {
            if (definitions[i].handleParameters != NULL) {
                definitions[i].handleParameters(&frame, messageParameters, true);
            }
            return definitions[i].commandType;
        }
#ifdef VERBOSE_DEF
         printf("definition %d: sig: ", i);
         _jr_viscahex_print(definitions[i].signature, definitions[i].signatureLength);
         printf(" sigmask: ");
         _jr_viscahex_print(definitions[i].signatureMask, definitions[i].signatureLength);
         printf("\n");
#endif
        i++;
    }

    return -1;
}

int jr_viscaEncodeFrame(int messageType, union jr_viscaMessageParameters messageParameters, jr_viscaFrame *frame) {
    int i = 0;
    while (definitions[i].signatureLength) {
        if (messageType == definitions[i].commandType) {
            memcpy(frame->data, definitions[i].signature, definitions[i].signatureLength);
            frame->dataLength = definitions[i].signatureLength;
            if (definitions[i].handleParameters != NULL) {
                definitions[i].handleParameters(frame, &messageParameters, false);
            }
            return 0;
        }
        i++;
    }

    return -1;
}

int jr_viscaDecodeMessage(uint8_t *data, int dataLength, int *message, union jr_viscaMessageParameters *messageParameters, uint8_t *sender, uint8_t *receiver) {
    jr_viscaFrame frame;
    int consumedBytes = jr_viscaDataToFrame(data, dataLength, &frame);
    if (consumedBytes <= 0) {
        return consumedBytes;
    }

    *message = jr_viscaDecodeFrame(frame, messageParameters);
    *sender = frame.sender;
    *receiver = frame.receiver;

    return consumedBytes;
}

int jr_viscaEncodeMessage(uint8_t *data, int dataLength, int message, union jr_viscaMessageParameters messageParameters, uint8_t sender, uint8_t receiver) {
    jr_viscaFrame frame;
    frame.sender = sender;
    frame.receiver = receiver;
    if (jr_viscaEncodeFrame(message, messageParameters, &frame) < 0) {
        return -1;
    }

    return jr_viscaFrameToData(data, dataLength, frame);
}
