#include <stdio.h>
#include "jr_socket.h"

#include "jr_hex_print.h"
#include "jr_visca.h"
#include <string.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>
#include <time.h>
#include "PTZCamera.h"

#define IP_CAMERA_NUMBER 1

void sendMessage(int messageType, union jr_viscaMessageParameters parameters, jr_socket socket) {
    uint8_t resultData[18];
    /* First byte of Address Set (Camera Num) and IPClear(Broadcast) is 0x88
     X = 1 to 7: Address of the unit (Locked to “X = 1” for VISCA over IP)
     Y = 9 to F: Address of the unit +8 (Locked to “Y = 9” for VISCA over IP)
     */
    uint8_t sender = (messageType == JR_VISCA_MESSAGE_CAMERA_NUMBER) ? 0 : IP_CAMERA_NUMBER;
    uint8_t receiver = (messageType == JR_VISCA_MESSAGE_CAMERA_NUMBER) ? 8 : 0;
    int dataLength = jr_viscaEncodeMessage(resultData, sizeof(resultData), messageType, parameters, sender, receiver);
    if (dataLength < 0) {
        fprintf(stderr, "error converting frame to data\n");
        return;
    }
#if 1 // TODO: a pref for logging sends
     printf("send: ");
     hex_print((char*)resultData, dataLength);
     printf("\n");
#endif

    if (jr_socket_send(socket, (char*)resultData, dataLength) == -1) {
        fprintf(stderr, "error sending response\n");
        return;
    }
}

void sendAckCompletion(uint8_t socketNumber, jr_socket socket) {
    union jr_viscaMessageParameters parameters;
    parameters.ackCompletionParameters.socketNumber = socketNumber;
    sendMessage(JR_VISCA_MESSAGE_ACK, parameters, socket);
    sendMessage(JR_VISCA_MESSAGE_COMPLETION, parameters, socket);
}

void sendAck(uint8_t socketNumber, jr_socket socket) {
    union jr_viscaMessageParameters parameters;
    parameters.ackCompletionParameters.socketNumber = socketNumber;
    sendMessage(JR_VISCA_MESSAGE_ACK, parameters, socket);
}

void sendCompletion(uint8_t socketNumber, jr_socket socket) {
    union jr_viscaMessageParameters parameters;
    parameters.ackCompletionParameters.socketNumber = socketNumber;
    sendMessage(JR_VISCA_MESSAGE_COMPLETION, parameters, socket);
}

void sendErrorReply(uint8_t socketNumber, jr_socket socket, uint8_t errorType) {
    union jr_viscaMessageParameters parameters;
    parameters.errorReplyParameters.socketNumber = socketNumber;
    parameters.errorReplyParameters.errorType = errorType;
    sendMessage(JR_VISCA_MESSAGE_ERROR_REPLY, parameters, socket);
}

#define SET_CAM_VALUE(_key, _value) [camera safeSetNumber:(_value) forKey:(_key)]

int handle_camera(PTZCamera *camera) {
    jr_server_socket serverSocket;

    if (jr_socket_setupServerSocket(5678, &serverSocket) == -1) {
        fprintf(stderr, "Setup failed\n");
        return -1;
    }
    
    jr_socket clientSocket;
    if (jr_socket_accept(serverSocket, &clientSocket) == -1) {
        fprintf(stderr, "Accept failed");
        return -2;
    }
    
    [camera pingCamera:clientSocket];

    [camera setSocketFD:serverSocket._serverSocket];
    
    fprintf(stdout, "ready\n");
    
    int count = 0;
    char buffer[1024];
    
    ssize_t latestCount;
    while ((latestCount = jr_socket_receive(clientSocket, buffer + count, 1024 - count)) > 0) {
        [camera pingCamera:clientSocket];
        count += latestCount;
        // printf("recv: ");
        // hex_print(buffer, count);
        // printf("\n");
        int consumed;
        do {
            int messageType;
            union jr_viscaMessageParameters messageParameters;
            uint8_t sender;
            uint8_t receiver;
            consumed = jr_viscaDecodeMessage((uint8_t*)buffer, count, &messageType, &messageParameters, &sender, &receiver);
            if (consumed < 0) {
                fprintf(stderr, "error, bailing\n");
                goto bailTCPLoop;
            }
            
            if (consumed) {
                // printf("found %d-byte frame: ", consumed);
                
                union jr_viscaMessageParameters response;
                switch (messageType)
                {
                    case JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ: {
                        fprintf(stdout, "CAM_PanTiltPosInq\n");
                        response.panTiltPositionInqResponseParameters.panPosition = camera.pan;
                        response.panTiltPositionInqResponseParameters.tiltPosition = camera.tilt;
                        sendMessage(JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ_RESPONSE, response, clientSocket);
                        break;
                    }
                    case JR_VISCA_MESSAGE_ZOOM_POSITION_INQ:
                        fprintf(stdout, "CAM_ZoomPosInq\n");
                        response.int16Parameters.int16Value = camera.zoom;
                        sendMessage(JR_VISCA_MESSAGE_ZOOM_POSITION_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_AUTOMATIC:
                        fprintf(stdout, "CAM_Focus Automatic\n");
                        [camera focusAutomatic];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_MANUAL:
                        fprintf(stdout, "CAM_Focus Manual\n");
                        [camera focusManual];
                        response.ackCompletionParameters.socketNumber = 1;
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_AF_MODE_INQ:
                        fprintf(stdout, "CAM_FocusAFModeInq\n");
                        response.oneByteParameters.byteValue = camera.autofocus ? JR_VISCA_AF_MODE_AUTO : JR_VISCA_AF_MODE_MANUAL;
                        sendMessage(JR_VISCA_MESSAGE_FOCUS_AF_MODE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_VALUE_INQ:
                        fprintf(stdout, "CAM_FocusPosInq\n");
                        response.int16Parameters.int16Value = camera.focus;
                        sendMessage(JR_VISCA_MESSAGE_FOCUS_VALUE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_BRIGHTNESS:
                        SET_CAM_VALUE(@"brightness", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_Brightness 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                   case JR_VISCA_MESSAGE_BRIGHTNESS_INQ:
                        fprintf(stdout, "CAM_BrightnessInq\n");
                        response.int16Parameters.int16Value = camera.brightness;
                        sendMessage(JR_VISCA_MESSAGE_BRIGHTNESS_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_CONTRAST:
                        SET_CAM_VALUE(@"contrast", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_Contrast 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_CONTRAST_INQ:
                        fprintf(stdout, "CAM_ContrastInq\n");
                        response.int16Parameters.int16Value = camera.contrast;
                        sendMessage(JR_VISCA_MESSAGE_CONTRAST_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_DIRECT:
                        fprintf(stdout, "CAM_Zoom Direct 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        [camera absoluteZoom:messageParameters.int16Parameters.int16Value];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_STOP:
                        fprintf(stdout, "CAM_Zoom Stop\n");
                        [camera zoomStop];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_TELE_STANDARD:
                        fprintf(stdout, "CAM_Zoom Tele(in) Standard\n");
                        [camera startZoomIn:1];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_WIDE_STANDARD:
                        fprintf(stdout, "CAM_Zoom Wide(out) Standard\n");
                        [camera startZoomOut:1];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_FAR_VARIABLE:
                        fprintf(stdout, "CAM_Focus Far 0x%hx\n", messageParameters.oneByteParameters.byteValue);
                        [camera relativeFocusFar:messageParameters.oneByteParameters.byteValue];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_NEAR_VARIABLE:
                        fprintf(stdout, "CAM_Focus Near 0x%hx\n", messageParameters.oneByteParameters.byteValue);
                        [camera relativeFocusNear:messageParameters.oneByteParameters.byteValue];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_STOP:
                        fprintf(stdout, "CAM_Focus Stop\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_FAR_STANDARD:
                        fprintf(stdout, "CAM_Focus Far Standard\n");
                        [camera relativeFocusFar:1];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_NEAR_STANDARD:
                        fprintf(stdout, "CAM_Focus Near Standard\n");
                        [camera relativeFocusNear:1];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_TELE_VARIABLE:
                        fprintf(stdout, "CAM_Zoom Tele(in) 0x%hx\n", messageParameters.oneByteParameters.byteValue);
                        [camera startZoomIn:messageParameters.oneByteParameters.byteValue];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_WIDE_VARIABLE:
                        fprintf(stdout, "CAM_Zoom Wide(out) 0x%hx\n", messageParameters.oneByteParameters.byteValue);
                        [camera startZoomOut:messageParameters.oneByteParameters.byteValue];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PAN_TILT_DRIVE: {
                        fprintf(stdout, "Pan_TiltDrive: pan 0x%hx tilt 0x%hx", messageParameters.panTiltDriveParameters.panSpeed,
                                messageParameters.panTiltDriveParameters.tiltSpeed);
                        switch (messageParameters.panTiltDriveParameters.panDirection) {
                            case JR_VISCA_PAN_DIRECTION_LEFT:
                                fprintf(stdout, "left %d ", messageParameters.panTiltDriveParameters.panSpeed);
                                break;
                            case JR_VISCA_PAN_DIRECTION_RIGHT:
                                fprintf(stdout, "right  %d ", messageParameters.panTiltDriveParameters.panSpeed);
                                break;
                            case JR_VISCA_PAN_DIRECTION_STOP:
                                fprintf(stdout, "pan-stop ");
                                break;
                        }
                        
                        switch (messageParameters.panTiltDriveParameters.tiltDirection) {
                            case JR_VISCA_TILT_DIRECTION_DOWN:
                                fprintf(stdout, "down %d ", messageParameters.panTiltDriveParameters.tiltSpeed);
                                break;
                            case JR_VISCA_TILT_DIRECTION_UP:
                                fprintf(stdout, "up %d ", messageParameters.panTiltDriveParameters.tiltSpeed);
                                break;
                            case JR_VISCA_TILT_DIRECTION_STOP:
                                fprintf(stdout, "tilt-stop ");
                                break;
                        }
                        fprintf(stdout, "\n");
                        sendAck(1, clientSocket);
                        [camera startPanSpeed:messageParameters.panTiltDriveParameters.panSpeed
                                       tiltSpeed:messageParameters.panTiltDriveParameters.tiltSpeed
                                    panDirection:messageParameters.panTiltDriveParameters.panDirection
                                   tiltDirection:messageParameters.panTiltDriveParameters.tiltDirection
                                          onDone:^{sendCompletion(1, clientSocket);}];
                        }
                        break;
                    case JR_VISCA_MESSAGE_CAMERA_NUMBER:
                        fprintf(stdout, "Camera Number Inq\n");
                        response.cameraNumberParameters.cameraNum = IP_CAMERA_NUMBER;
                        sendMessage(JR_VISCA_MESSAGE_CAMERA_NUMBER, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_MEMORY:
                        if (messageParameters.memoryParameters.memory == 95) {
                            // PTZOptics cameras: This is toggle menu. No really. That's what the doc says, that's how real cameras work. Hidden in the support website, it mentions that presets 90-99 are reserved.
                            // See JR_VISCA_MESSAGE_SONY_MENU_MODE
                            fprintf(stdout, "CAM_OSD Open/Close\n");
                            [camera toggleMenu];
                            sendAckCompletion(1, clientSocket);
                            break;
                        }
                        switch (messageParameters.memoryParameters.mode) {
                            case JR_VISCA_MEMORY_MODE_SET:
                                fprintf(stdout, "CAM_Memory Set %d ", messageParameters.memoryParameters.memory);
                                sendAck(1, clientSocket);
                                [camera cameraSetAtIndex:messageParameters.memoryParameters.memory
                                             onDone:^{sendCompletion(1, clientSocket);}];
                               break;
                            case JR_VISCA_MEMORY_MODE_RESET:
                                fprintf(stdout, "CAM_Memory Reset %d ", messageParameters.memoryParameters.memory);
                                sendAckCompletion(1, clientSocket);
                                break;
                            case JR_VISCA_MEMORY_MODE_RECALL:
                                fprintf(stdout, "CAM_Memory Recall %d ", messageParameters.memoryParameters.memory);
                                sendAck(1, clientSocket);
                                [camera recallAtIndex:messageParameters.memoryParameters.memory
                                               onDone:^{sendCompletion(1, clientSocket);}];
                                break;
                        }
                        fprintf(stdout, "\n");
                        break;
                    case JR_VISCA_MESSAGE_CLEAR:
                        fprintf(stdout, "IF_Clear\n");
                        sendCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_MOTION_SYNC:
                        fprintf(stdout, "CAM_PTZMotionSync\n");
                        sendCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_HOME:
                        fprintf(stdout, "Pan_TiltDrive Home\n");
                        sendAck(1, clientSocket);
                        [camera cameraHome:^{sendAckCompletion(1, clientSocket);}];
                        sendCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RESET:
                        fprintf(stdout, "Pan_TiltDrive Reset\n");
                        sendAck(1, clientSocket);
                        [camera cameraReset:^{sendCompletion(1, clientSocket);}];
                        break;
                    case JR_VISCA_MESSAGE_CANCEL:
                        fprintf(stdout, "Cancel\n");
                        sendAck(1, clientSocket);
                        [camera cameraCancel:^{sendErrorReply(1, clientSocket, JR_VISCA_ERROR_CANCELLED);}];
                        break;
                    case JR_VISCA_MESSAGE_MENU_ENTER:
                        fprintf(stdout, "CAM_OSD Enter\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_MENU_RETURN:
                        fprintf(stdout, "CAM_OSD Return\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_MENU_MODE_INQ:
                        fprintf(stdout, "SYS_MenuModeInq\n");
                        response.oneByteParameters.byteValue = BOOL_TO_ONOFF(camera.menuVisible);
                        sendMessage(JR_VISCA_MESSAGE_MENU_MODE_RESPONSE, response, clientSocket);
                        break;
                        break;
                    case JR_VISCA_MESSAGE_PRESET_RECALL_SPEED:
                        SET_CAM_VALUE(@"presetSpeed", messageParameters.oneByteParameters   .byteValue);
                        hex_print(buffer, consumed);
                        fprintf(stdout, "Preset Recall Speed %hhu\n", messageParameters.oneByteParameters   .byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ABSOLUTE_PAN_TILT:
                        sendAck(1, clientSocket);
                        [camera absolutePanSpeed:messageParameters.absolutePanTiltPositionParameters.panSpeed
                                    tiltSpeed:messageParameters.absolutePanTiltPositionParameters.tiltSpeed
                                          pan:messageParameters.absolutePanTiltPositionParameters.panPosition
                                         tilt:messageParameters.absolutePanTiltPositionParameters.tiltPosition
                                       onDone:^{sendCompletion(1, clientSocket);}];
                        hex_print(buffer, consumed);
                        fprintf(stdout, "Pan_TiltDrive AbsolutePosition\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RELATIVE_PAN_TILT:
                        sendAck(1, clientSocket);
                        [camera relativePanSpeed:messageParameters.absolutePanTiltPositionParameters.panSpeed
                                    tiltSpeed:messageParameters.absolutePanTiltPositionParameters.tiltSpeed
                                          pan:messageParameters.absolutePanTiltPositionParameters.panPosition
                                         tilt:messageParameters.absolutePanTiltPositionParameters.tiltPosition
                                       onDone:^{sendCompletion(1, clientSocket);}];
                        hex_print(buffer, consumed);
                        fprintf(stdout, "Pan_TiltDrive RelativePosition\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_WB_MODE:
                        SET_CAM_VALUE(@"wbMode", messageParameters.oneByteParameters.byteValue);
                            fprintf(stdout, "CAM_WB %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_WB_MODE_INQ:
                        fprintf(stdout, "CAM_WBModeInq\n");
                        response.oneByteParameters.byteValue = camera.wbMode;
                        sendMessage(JR_VISCA_MESSAGE_WB_MODE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_TEMP_DIRECT:
                        SET_CAM_VALUE(@"colorTempIndex", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_ColorTemp Direct 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_TEMP_INQ:
                        fprintf(stdout, "CAM_ColorTempInq\n");
                        response.oneByteParameters.byteValue = camera.colorTempIndex;
                        sendMessage(JR_VISCA_MESSAGE_COLOR_TEMP_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PICTURE_EFFECT:
                        SET_CAM_VALUE(@"pictureEffectMode", messageParameters.oneByteParameters.byteValue);
                        fprintf(stdout, "CAM_PictureEffect %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PICTURE_EFFECT_INQ:
                        fprintf(stdout, "CAM_PictureEffectModeInq\n");
                        response.oneByteParameters.byteValue = camera.pictureEffectMode;
                        sendMessage(JR_VISCA_MESSAGE_PICTURE_EFFECT_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_LR_REVERSE:
                        SET_CAM_VALUE(@"flipHOnOff", messageParameters.oneByteParameters.byteValue);
                        fprintf(stdout, "CAM_LR_Reverse %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_LR_REVERSE_INQ:
                        fprintf(stdout, "CAM_LR_ReverseInq\n");
                        response.oneByteParameters.byteValue = camera.flipHOnOff;
                        sendMessage(JR_VISCA_MESSAGE_LR_REVERSE_RESPONSE, response, clientSocket);
                        break;

                    case JR_VISCA_MESSAGE_PICTURE_FLIP:
                        SET_CAM_VALUE(@"flipVOnOff", messageParameters.oneByteParameters.byteValue);
                        fprintf(stdout, "CAM_PictureFlip %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PICTURE_FLIP_INQ:
                        fprintf(stdout, "CAM_PictureFlipInq\n");
                        response.oneByteParameters.byteValue = camera.flipVOnOff;
                        sendMessage(JR_VISCA_MESSAGE_PICTURE_FLIP_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_APERTURE_VALUE:
                        SET_CAM_VALUE(@"aperture", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_Aperture 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_APERTURE_VALUE_INQ:
                         fprintf(stdout, "CAM_ApertureInq \n");
                         response.int16Parameters.int16Value = camera.aperture;
                         sendMessage(JR_VISCA_MESSAGE_APERTURE_VALUE_RESPONSE, response, clientSocket);
                         break;
                    case JR_VISCA_MESSAGE_BGAIN_VALUE:
                        SET_CAM_VALUE(@"bGain", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_BGain 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_BGAIN_VALUE_INQ:
                        fprintf(stdout, "CAM_BGainInq\n");
                        response.int16Parameters.int16Value = camera.bGain;
                        sendMessage(JR_VISCA_MESSAGE_BGAIN_VALUE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RGAIN_VALUE:
                        SET_CAM_VALUE(@"rGain", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_RGain 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RGAIN_VALUE_INQ:
                        fprintf(stdout, "CAM_RGainInq\n");
                        response.int16Parameters.int16Value = camera.rGain;
                        sendMessage(JR_VISCA_MESSAGE_RGAIN_VALUE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_GAIN_DIRECT:
                        SET_CAM_VALUE(@"colorgain", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_ColorGain 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_GAIN_INQ:
                        fprintf(stdout, "CAM_ColorGainInq\n");
                        response.int16Parameters.int16Value = camera.colorgain;
                        sendMessage(JR_VISCA_MESSAGE_COLOR_GAIN_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_HUE_DIRECT:
                        SET_CAM_VALUE(@"hue", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_ColorHue 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_HUE_INQ:
                        fprintf(stdout, "CAM_ColorHueInq\n");
                        response.int16Parameters.int16Value = camera.hue;
                        sendMessage(JR_VISCA_MESSAGE_COLOR_HUE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_AWB_SENS:
                        fprintf(stdout, "CAM_AWBSensitivity %d\n",  messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_AWB_SENS_INQ:
                        fprintf(stdout, "CAM_AWBSensitivityInq\n");
                        response.oneByteParameters.byteValue = camera.awbSens;
                        sendMessage(JR_VISCA_MESSAGE_AWB_SENS_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_AE_MODE:
                        SET_CAM_VALUE(@"aeMode", messageParameters.oneByteParameters.byteValue);
                            fprintf(stdout, "CAM_AE %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                   case JR_VISCA_MESSAGE_AE_MODE_INQ:
                        fprintf(stdout, "CAM_AEModeInq\n");
                        response.oneByteParameters.byteValue = camera.aeMode;
                        sendMessage(JR_VISCA_MESSAGE_AE_MODE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_SHUTTER_VALUE:
                        SET_CAM_VALUE(@"shutter", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_Shutter 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                   case JR_VISCA_MESSAGE_SHUTTER_POS_INQ:
                        response.int16Parameters.int16Value = camera.shutter;
                        fprintf(stdout, "CAM_ShutterPosInq\n");
                        sendMessage(JR_VISCA_MESSAGE_SHUTTER_POS_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_IRIS_VALUE:
                        SET_CAM_VALUE(@"iris", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_Iris 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_IRIS_POS_INQ:
                        fprintf(stdout, "CAM_IrisPosInq\n");
                        response.int16Parameters.int16Value = camera.iris;
                        sendMessage(JR_VISCA_MESSAGE_IRIS_POS_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_BRIGHT_DIRECT:
                        SET_CAM_VALUE(@"brightPos", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "CAM_Bright Direct 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_BRIGHT_POS_INQ:
                         fprintf(stdout, "CAM_BrightPosInq\n");
                         response.int16Parameters.int16Value = camera.brightPos;
                         sendMessage(JR_VISCA_MESSAGE_BRIGHT_POS_RESPONSE, response, clientSocket);
                         break;

                    default:
                        {
                        BOOL unknown = messageType < 0;
                        fprintf(stdout, "%s: (0x%X) ", (unknown ? "unknown" : "unhandled"), messageType);
                        hex_print(buffer, consumed);
#if 0
                        fprintf(stdout, " ErrorReply\n");
                        sendAck(1, clientSocket);
                        [camera cameraCancel:^{sendErrorReply(1, clientSocket, unknown ? JR_VISCA_ERROR_SYNTAX : JR_VISCA_ERROR_NOT_EXECUTABLE);}];
#else
                        fprintf(stdout, " Ignored\n");
                        sendAckCompletion(1, clientSocket);
#endif
                        }
                        break;
                }
                
                count -= consumed;
                // Crappy naive buffer management-- move remaining bytes up to buffer[0].
                // Maybe later we'll replace this with a circular buffer or something.
                // For now I just want it to work.
                memmove(buffer, buffer + consumed, count);
            }
        } while (consumed);
    }
bailTCPLoop:
    
    fprintf(stdout, "Connection spun down, closing socket.\n");
    
    jr_socket_closeSocket(clientSocket);
    jr_socket_closeServerSocket(serverSocket);
    return 0;
}

