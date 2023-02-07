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

#ifndef JR_VISCA_H
#define JR_VISCA_H

#include <stdint.h>

#define JR_VISCA_MAX_ENCODED_MESSAGE_DATA_LENGTH 18

#define JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ 1
#define JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ_RESPONSE 2

#define JR_VISCA_MESSAGE_ACK 7
#define JR_VISCA_MESSAGE_COMPLETION 8

#define JR_VISCA_MESSAGE_ZOOM_STOP 9
#define JR_VISCA_MESSAGE_ZOOM_TELE_STANDARD 10
#define JR_VISCA_MESSAGE_ZOOM_WIDE_STANDARD 11
#define JR_VISCA_MESSAGE_ZOOM_TELE_VARIABLE 12
#define JR_VISCA_MESSAGE_ZOOM_WIDE_VARIABLE 13

// PTZOptics: JR_VISCA_MESSAGE_PAN_TILT_DRIVE navigates the menu when it's up.
#define JR_VISCA_MESSAGE_PAN_TILT_DRIVE 15

#define JR_VISCA_MESSAGE_CAMERA_NUMBER 16

#define JR_VISCA_MESSAGE_MEMORY 17

#define JR_VISCA_MESSAGE_CLEAR 18

#define JR_VISCA_MESSAGE_PRESET_RECALL_SPEED 19

#define JR_VISCA_MESSAGE_ABSOLUTE_PAN_TILT 20

#define JR_VISCA_MESSAGE_HOME 21

#define JR_VISCA_MESSAGE_RESET 22

#define JR_VISCA_MESSAGE_CANCEL 23


#define JR_VISCA_MESSAGE_FOCUS_STOP 26
#define JR_VISCA_MESSAGE_FOCUS_FAR_STANDARD 27
#define JR_VISCA_MESSAGE_FOCUS_NEAR_STANDARD 28
#define JR_VISCA_MESSAGE_FOCUS_FAR_VARIABLE 29
#define JR_VISCA_MESSAGE_FOCUS_NEAR_VARIABLE 30

#define JR_VISCA_MESSAGE_SONY_MENU_ENTER 31

#define JR_VISCA_MESSAGE_MOTION_SYNC 32

// Number convention for sys commands [81 01 06] and inqs [81 90 06]
// Set: 0x6yy, where yy is the cmd ID
// Set: 0x6yyz, z is the subcommand ID
// Inq: 0xAyy

// Number convention for camera commands [81 01 04] and inqs [81 90 04]
// Set: 0x8yy, where yy is the cmd ID
// Set: 0x8yyz, z is the subcommand ID
// Inq: 0x9yy
// Reply: 0x9pyy, where p is 5 for normal (0x50) replies, or 6 if 0x60
// The code does not care, it just makes debugging and rearranging code easier.
// 0x7 is reserved for Sony Camera2 [80 01 07]. Implemention is left as an excercise for the Sony fan.

// Response types:
//  OneByte: 90 50 xx FF
//  P:       90 50 0p FF
//  PQ:      90 50 0p 0q FF
//  ZZZP:    90 50 00 00 00 0p FF
//  ZZPQ:    90 50 00 00 0p 0q FF
//  PQRS:    90 50 0p 0q 0r 0s FF
// ZZPQ and ZZZP can be treated as PQRS
#define JR_VISCA_MESSAGE_ERROR_REPLY 0x9601
#define JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE 0x9501
#define JR_VISCA_MESSAGE_P_RESPONSE 0x9502
#define JR_VISCA_MESSAGE_PQ_INQ_RESPONSE 0x9503
#define JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE 0x9504
#define JR_VISCA_MESSAGE_ZZZP_INQ_RESPONSE JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE
#define JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE

// PanTilter and System commands
#define JR_VISCA_MESSAGE_MENU_RETURN 0x604
#define JR_VISCA_MESSAGE_MENU_ENTER 0x605
// PTZOptics toggle is JR_VISCA_MESSAGE_MEMORY preset #95. No really.
#define JR_VISCA_MESSAGE_SONY_MENU_MODE 0x606
#define JR_VISCA_MESSAGE_MENU_MODE_INQ 0xA06
#define JR_VISCA_MESSAGE_MENU_MODE_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

// Camera commands
#define JR_VISCA_MESSAGE_BRIGHT_DIRECT 0x80D
#define JR_VISCA_MESSAGE_BRIGHT_POS_INQ 0x94D
#define JR_VISCA_MESSAGE_BRIGHT_POS_RESPONSE JR_VISCA_MESSAGE_PQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_COLOR_TEMP_DIRECT 0x820
#define JR_VISCA_MESSAGE_COLOR_TEMP_INQ 0x920
#define JR_VISCA_MESSAGE_COLOR_TEMP_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_FLICKER_MODE 0x823
#define JR_VISCA_MESSAGE_FLICKER_MODE_INQ 0x955
#define JR_VISCA_MESSAGE_FLICKER_MODE_RESPONSE JR_VISCA_MESSAGE_P_RESPONSE

#define JR_VISCA_MESSAGE_GAIN_LIMIT 0x82C
#define JR_VISCA_MESSAGE_GAIN_LIMIT_INQ 0x92C
#define JR_VISCA_MESSAGE_GAIN_LIMIT_RESPONSE JR_VISCA_MESSAGE_P_RESPONSE

#define JR_VISCA_MESSAGE_WB_MODE 0x835
#define JR_VISCA_MESSAGE_WB_MODE_INQ 0x935
#define JR_VISCA_MESSAGE_WB_MODE_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_FOCUS_AUTOMATIC 0x8382
#define JR_VISCA_MESSAGE_FOCUS_MANUAL 0x8383
#define JR_VISCA_MESSAGE_FOCUS_AF_MODE_INQ 0x938
#define JR_VISCA_MESSAGE_FOCUS_AF_MODE_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_AE_MODE 0x839
#define JR_VISCA_MESSAGE_AE_MODE_INQ 0x939
#define JR_VISCA_MESSAGE_AE_MODE_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_APERTURE_VALUE 0x842
#define JR_VISCA_MESSAGE_APERTURE_VALUE_INQ 0x942
#define JR_VISCA_MESSAGE_APERTURE_VALUE_RESPONSE JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_RGAIN_VALUE 0x843
#define JR_VISCA_MESSAGE_RGAIN_VALUE_INQ 0x943
#define JR_VISCA_MESSAGE_RGAIN_VALUE_RESPONSE JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_BGAIN_VALUE 0x844
#define JR_VISCA_MESSAGE_BGAIN_VALUE_INQ 0x944
#define JR_VISCA_MESSAGE_BGAIN_VALUE_RESPONSE JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_ZOOM_DIRECT 0x847
#define JR_VISCA_MESSAGE_ZOOM_POSITION_INQ 0x947
#define JR_VISCA_MESSAGE_ZOOM_POSITION_RESPONSE JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE

#define JR_VISCA_MESSAGE_FOCUS_VALUE 0x848
#define JR_VISCA_MESSAGE_FOCUS_VALUE_INQ 0x948
#define JR_VISCA_MESSAGE_FOCUS_VALUE_RESPONSE JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE

#define JR_VISCA_MESSAGE_COLOR_GAIN_DIRECT 0x849
#define JR_VISCA_MESSAGE_COLOR_GAIN_INQ 0x949
#define JR_VISCA_MESSAGE_COLOR_GAIN_RESPONSE JR_VISCA_MESSAGE_ZZZP_INQ_RESPONSE

#define JR_VISCA_MESSAGE_SHUTTER_VALUE 0x84A
#define JR_VISCA_MESSAGE_SHUTTER_POS_INQ 0x94A
#define JR_VISCA_MESSAGE_SHUTTER_POS_RESPONSE JR_VISCA_MESSAGE_PQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_IRIS_VALUE 0x84B
#define JR_VISCA_MESSAGE_IRIS_POS_INQ 0x94B
#define JR_VISCA_MESSAGE_IRIS_POS_RESPONSE JR_VISCA_MESSAGE_PQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_EXP_COMP_DIRECT 0x4E
#define JR_VISCA_MESSAGE_EXP_COMP_POS_INQ 0x4E
#define JR_VISCA_MESSAGE_EXP_COMP_POS_RESPONSE JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_COLOR_HUE_DIRECT 0x84F
#define JR_VISCA_MESSAGE_COLOR_HUE_INQ 0x94F
#define JR_VISCA_MESSAGE_COLOR_HUE_RESPONSE JR_VISCA_MESSAGE_ZZZP_INQ_RESPONSE

#define JR_VISCA_MESSAGE_LR_REVERSE 0x861
#define JR_VISCA_MESSAGE_LR_REVERSE_INQ 0x961
#define JR_VISCA_MESSAGE_LR_REVERSE_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_PICTURE_EFFECT 0x863
#define JR_VISCA_MESSAGE_PICTURE_EFFECT_INQ 0x963
#define JR_VISCA_MESSAGE_PICTURE_EFFECT_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_PICTURE_FLIP 0x866
#define JR_VISCA_MESSAGE_PICTURE_FLIP_INQ 0x966
#define JR_VISCA_MESSAGE_PICTURE_FLIP_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

#define JR_VISCA_MESSAGE_BRIGHTNESS 0x8A1
#define JR_VISCA_MESSAGE_BRIGHTNESS_INQ 0x9A1
#define JR_VISCA_MESSAGE_BRIGHTNESS_RESPONSE JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_CONTRAST 0x8A2
#define JR_VISCA_MESSAGE_CONTRAST_INQ 0x9A2
#define JR_VISCA_MESSAGE_CONTRAST_RESPONSE JR_VISCA_MESSAGE_ZZPQ_INQ_RESPONSE

#define JR_VISCA_MESSAGE_AWB_SENS 0x8A9
#define JR_VISCA_MESSAGE_AWB_SENS_INQ 0x9A9
#define JR_VISCA_MESSAGE_AWB_SENS_RESPONSE JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE

struct jr_viscaPanTiltPositionInqResponseParameters {
    int16_t panPosition;
    int16_t tiltPosition;
};

// AbsolutePosition 81 01 06 02 VV WW 0Y 0Y 0Y 0Y 0Z 0Z 0Z 0Z FF
// VV: Pan speed 0x01 (low speed) to 0x18 (high speed)
// WW: Tilt speed 0x01 (low speed) to 0x14 (high speed)
// YYYY: Pan Position
// ZZZZ: Tilt Position
struct jr_viscaAbsolutePanTiltPositionParameters {
    int16_t panPosition;
    int16_t tiltPosition;
    uint8_t panSpeed;
    uint8_t tiltSpeed;
};

struct jr_viscaAckCompletionParameters {
    uint8_t socketNumber;
};

#define JR_VISCA_ERROR_SYNTAX 0x02
#define JR_VISCA_ERROR_BUFFER_FULL 0x03
#define JR_VISCA_ERROR_CANCELLED 0x04
#define JR_VISCA_ERROR_NO_SOCKET 0x05
#define JR_VISCA_ERROR_NOT_EXECUTABLE 0x41

struct jr_viscaErrorReplyParameters {
    uint8_t socketNumber;
    uint8_t errorType;
};

struct jr_viscaCameraNumberParameters {
    // 1-7
    uint8_t cameraNum;
};


struct jr_viscaMemoryParameters {
    // 1-127
    uint8_t memory;
    // 0=reset, 1=set, 2=recall
    uint8_t mode;
};

#define JR_VISCA_TILT_DIRECTION_UP 1
#define JR_VISCA_TILT_DIRECTION_DOWN 2
#define JR_VISCA_TILT_DIRECTION_STOP 3

#define JR_VISCA_PAN_DIRECTION_LEFT 1
#define JR_VISCA_PAN_DIRECTION_RIGHT 2
#define JR_VISCA_PAN_DIRECTION_STOP 3

#define JR_VISCA_MEMORY_MODE_RESET 0
#define JR_VISCA_MEMORY_MODE_SET 1
#define JR_VISCA_MEMORY_MODE_RECALL 2

struct jr_viscaPanTiltDriveParameters {
    uint8_t panSpeed; // 1-0x18
    uint8_t tiltSpeed; // 1-0x14
    uint8_t panDirection; // JR_VISCA_PAN_DIRECTION_*
    uint8_t tiltDirection; // JR_VISCA_TILT_DIRECTION_*
};

#define JR_VISCA_AF_MODE_AUTO 0x02
#define JR_VISCA_AF_MODE_MANUAL 0x03

/*
 * You really won't believe this (PTZOptics. Sony supports all the modes)
 * CAM_PictureEffect Off    81 01 04 63 00 FF
                     B&W    81 01 04 63 04 FF

 * CAM_PictureEffectModeInq
 *   Reply          Off 90 50 02 FF
                    BW  90 50 04 FF
 * Yes. It's asymmetric.
 * 02 is "Negative" mode. I think someone got confused.
 */
#define JR_VISCA_PICTURE_FX_MODE_OFF 0x00
#define JR_VISCA_PICTURE_FX_MODE_OFF_REPLY 0x02
#define JR_VISCA_PICTURE_FX_MODE_BW 0x04

#define JR_VISCA_ON 0x02
#define JR_VISCA_OFF 0x03
#define BOOL_TO_ONOFF(b) ((b) ? JR_VISCA_ON : JR_VISCA_OFF)
#define ONOFF_TO_BOOL(b) ((b) == JR_VISCA_ON)

struct jr_viscaOneByteParameters {
    uint8_t byteValue;
};

struct jr_viscaInt16Parameters {
    int16_t int16Value;
};


union jr_viscaMessageParameters
{
    struct jr_viscaPanTiltPositionInqResponseParameters panTiltPositionInqResponseParameters;
    struct jr_viscaAckCompletionParameters ackCompletionParameters;
    struct jr_viscaPanTiltDriveParameters panTiltDriveParameters;
    struct jr_viscaCameraNumberParameters cameraNumberParameters;
    struct jr_viscaMemoryParameters memoryParameters;
    struct jr_viscaAbsolutePanTiltPositionParameters absolutePanTiltPositionParameters;
    struct jr_viscaOneByteParameters oneByteParameters;
    struct jr_viscaInt16Parameters int16Parameters;
    struct jr_viscaErrorReplyParameters errorReplyParameters;
};

/**
 * Decodes the first message from `data` into `message` and `messageParameters`.
 * 
 * Returns the byte count of the decoded message, or 0 if the buffer does not contain a complete message.
 * 
 * If the buffer contains at least one complete message (i.e. the return value is greater than 0):
 *  - `message` will either be set to -1 (unrecognized message) or one of the `JR_VISCA_MESSAGE_*` constants.
 *  - `messageParameters` will have the corresponding parameters set as appropriate for the detected message type.
 */
int jr_viscaDecodeMessage(uint8_t *data, int dataLength, int *message, union jr_viscaMessageParameters *messageParameters, uint8_t *sender, uint8_t *receiver);

/**
 * Encodes `message` and `messageParameters` and write it to `data`.
 * 
 * Returns the byte count of the encoded message, or -1 if the given `data` buffer is too short to hold the full message.
 */
int jr_viscaEncodeMessage(uint8_t *data, int dataLength, int message, union jr_viscaMessageParameters messageParameters, uint8_t sender, uint8_t receiver);

#endif
