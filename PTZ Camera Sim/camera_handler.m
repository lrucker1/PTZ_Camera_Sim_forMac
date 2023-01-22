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
     printf("send: ");
     hex_print((char*)resultData, dataLength);
     printf("\n");

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
    
    [camera setSocketFD:serverSocket._serverSocket];
    
    fprintf(stdout, "ready\n");
    
    int count = 0;
    char buffer[1024];
    
    ssize_t latestCount;
    while ((latestCount = jr_socket_receive(clientSocket, buffer + count, 1024 - count)) > 0) {
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
                        fprintf(stdout, "pan tilt inq\n");
                        response.panTiltPositionInqResponseParameters.panPosition = camera.pan;
                        response.panTiltPositionInqResponseParameters.tiltPosition = camera.tilt;
                        sendMessage(JR_VISCA_MESSAGE_PAN_TILT_POSITION_INQ_RESPONSE, response, clientSocket);
                        break;
                    }
                    case JR_VISCA_MESSAGE_ZOOM_POSITION_INQ:
                        fprintf(stdout, "zoom inq\n");
                        response.int16Parameters.int16Value = camera.zoom;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_AUTOMATIC:
                        fprintf(stdout, "focus automatic\n");
                        [camera focusAutomatic];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_MANUAL:
                        fprintf(stdout, "focus manual\n");
                        [camera focusManual];
                        response.ackCompletionParameters.socketNumber = 1;
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_AF_MODE_INQ:
                        fprintf(stdout, "focus mode inq\n");
                        response.oneByteParameters.byteValue = camera.autofocus ? JR_VISCA_AF_MODE_AUTO : JR_VISCA_AF_MODE_MANUAL;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_VALUE_INQ:
                        fprintf(stdout, "focus inq\n");
                        response.int16Parameters.int16Value = camera.focus;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_DIRECT:
                        fprintf(stdout, "zoom direct to position %x\n", messageParameters.int16Parameters.int16Value);
                        [camera absoluteZoom:messageParameters.int16Parameters.int16Value];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_STOP:
                        fprintf(stdout, "zoom stop\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_TELE_STANDARD:
                        fprintf(stdout, "zoom in standard\n");
                        [camera relativeZoomIn:1];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_WIDE_STANDARD:
                        fprintf(stdout, "zoom out standard\n");
                        [camera relativeZoomOut:1];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_TELE_VARIABLE:
                        fprintf(stdout, "zoom in at %x\n", messageParameters.zoomVariableParameters.zoomSpeed);
                        [camera relativeZoomIn:messageParameters.zoomVariableParameters.zoomSpeed];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_WIDE_VARIABLE:
                        fprintf(stdout, "zoom out at %x\n", messageParameters.zoomVariableParameters.zoomSpeed);
                        [camera relativeZoomOut:messageParameters.zoomVariableParameters.zoomSpeed];
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PAN_TILT_DRIVE: {
                        fprintf(stdout, "pan tilt drive: ");
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
                        [camera relativePanSpeed:messageParameters.panTiltDriveParameters.panSpeed
                                       tiltSpeed:messageParameters.panTiltDriveParameters.tiltSpeed
                                    panDirection:messageParameters.panTiltDriveParameters.panDirection
                                   tiltDirection:messageParameters.panTiltDriveParameters.tiltDirection
                                          onDone:^{sendCompletion(1, clientSocket);}];
                        fprintf(stdout, "\n");
                        sendAckCompletion(1, clientSocket);
                        }
                        break;
                    case JR_VISCA_MESSAGE_CAMERA_NUMBER:
                        fprintf(stdout, "camera number inq\n");
                        response.cameraNumberParameters.cameraNum = IP_CAMERA_NUMBER;
                        sendMessage(JR_VISCA_MESSAGE_CAMERA_NUMBER, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_MEMORY:
                        if (messageParameters.memoryParameters.memory == 95) {
                            // PTZOptics cameras: This is toggle menu. No really. That's what the doc says, that's how real cameras work. Hidden in the support website, it mentions that presets 90-99 are reserved.
                            // Other cameras: ???
                            fprintf(stdout, "toggle menu\n");
                            [camera toggleMenu];
                            sendAckCompletion(1, clientSocket);
                            break;
                        }
                        switch (messageParameters.memoryParameters.mode) {
                            case JR_VISCA_MEMORY_MODE_SET:
                                fprintf(stdout, "set %d ", messageParameters.memoryParameters.memory);
                                sendAck(1, clientSocket);
                                [camera cameraSetAtIndex:messageParameters.memoryParameters.memory
                                             onDone:^{sendCompletion(1, clientSocket);}];
                               break;
                            case JR_VISCA_MEMORY_MODE_RESET:
                                fprintf(stdout, "reset %d ", messageParameters.memoryParameters.memory);
                                sendAckCompletion(1, clientSocket);
                                break;
                            case JR_VISCA_MEMORY_MODE_RECALL:
                                fprintf(stdout, "recall %d ", messageParameters.memoryParameters.memory);
                                sendAck(1, clientSocket);
                                [camera recallAtIndex:messageParameters.memoryParameters.memory
                                               onDone:^{sendCompletion(1, clientSocket);}];
                                break;
                        }
                        fprintf(stdout, "\n");
                        break;
                    case JR_VISCA_MESSAGE_CLEAR:
                        fprintf(stdout, "clear\n");
                        sendCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_HOME:
                        fprintf(stdout, "home\n");
                        sendAck(1, clientSocket);
                        [camera cameraHome:^{sendAckCompletion(1, clientSocket);}];
                        sendCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RESET:
                        fprintf(stdout, "reset\n");
                        sendAck(1, clientSocket);
                        [camera cameraReset:^{sendCompletion(1, clientSocket);}];
                        break;
                    case JR_VISCA_MESSAGE_CANCEL:
                        fprintf(stdout, "cancel\n");
                        sendAck(1, clientSocket);
                        [camera cameraCancel:^{sendErrorReply(1, clientSocket, JR_VISCA_ERROR_CANCELLED);}];
                        break;
                    case JR_VISCA_MESSAGE_PRESET_RECALL_SPEED:
                        SET_CAM_VALUE(@"presetSpeed", messageParameters.presetSpeedParameters.presetSpeed);
                        hex_print(buffer, consumed);
                        fprintf(stdout, "preset speed %hhu\n", messageParameters.presetSpeedParameters.presetSpeed);
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
                        fprintf(stdout, "preset speed %lu\n", (unsigned long)camera.presetSpeed);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_WB_MODE:
                        SET_CAM_VALUE(@"wbMode", messageParameters.oneByteParameters.byteValue);
                            fprintf(stdout, "WB mode %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_WB_MODE_INQ:
                        fprintf(stdout, "WB mode inq\n");
                        response.oneByteParameters.byteValue = camera.wbMode;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_TEMP_DIRECT:
                        SET_CAM_VALUE(@"colorTempIndex", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "color temp 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_TEMP_INQ:
                        fprintf(stdout, "WB mode inq\n");
                        response.oneByteParameters.byteValue = camera.colorTempIndex;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PICTURE_EFFECT:
                        SET_CAM_VALUE(@"pictureEffectMode", messageParameters.oneByteParameters.byteValue);
                        fprintf(stdout, "Picture Effect %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PICTURE_EFFECT_INQ:
                        fprintf(stdout, "Picture Effect inq\n");
                        response.oneByteParameters.byteValue = camera.pictureEffectMode;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_LR_REVERSE:
                        SET_CAM_VALUE(@"flipHOnOff", messageParameters.oneByteParameters.byteValue);
                        fprintf(stdout, "LR Reverse %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_LR_REVERSE_INQ:
                        fprintf(stdout, "LR Reverse inq\n");
                        response.oneByteParameters.byteValue = camera.flipHOnOff;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;

                    case JR_VISCA_MESSAGE_PICTURE_FLIP:
                        SET_CAM_VALUE(@"flipVOnOff", messageParameters.oneByteParameters.byteValue);
                        fprintf(stdout, "Picture Flip %lu\n", (unsigned long)messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_PICTURE_FLIP_INQ:
                        fprintf(stdout, "Picture Flip inq\n");
                        response.oneByteParameters.byteValue = camera.flipVOnOff;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_APERTURE_VALUE:
                        SET_CAM_VALUE(@"aperture", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "aperture 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_BGAIN_VALUE:
                        SET_CAM_VALUE(@"bGain", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "bGain 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RGAIN_VALUE:
                        SET_CAM_VALUE(@"rGain", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "rGain 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_GAIN_DIRECT:
                        SET_CAM_VALUE(@"colorgain", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "colorgain 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_HUE_DIRECT:
                        SET_CAM_VALUE(@"hue", messageParameters.int16Parameters.int16Value);
                        fprintf(stdout, "hue 0x%hx\n", messageParameters.int16Parameters.int16Value);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_AWB_SENS:
                        fprintf(stdout, "AWB Sens value= %d\n",  messageParameters.oneByteParameters.byteValue);
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_APERTURE_VALUE_INQ:
                        fprintf(stdout, "Aperture inq\n");
                        response.int16Parameters.int16Value = camera.aperture;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_BGAIN_VALUE_INQ:
                        fprintf(stdout, "Blue Gain inq\n");
                        response.int16Parameters.int16Value = camera.bGain;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_RGAIN_VALUE_INQ:
                        fprintf(stdout, "Red Gain inq\n");
                        response.int16Parameters.int16Value = camera.rGain;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_GAIN_INQ:
                        fprintf(stdout, "Color Gain inq\n");
                        response.int16Parameters.int16Value = camera.colorgain;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_COLOR_HUE_INQ:
                        fprintf(stdout, "Color Hue inq\n");
                        response.int16Parameters.int16Value = camera.hue;
                        sendMessage(JR_VISCA_MESSAGE_PQRS_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_AWB_SENS_INQ:
                        fprintf(stdout, "AWB Sens inq\n");
                        response.oneByteParameters.byteValue = camera.awbSens;
                        sendMessage(JR_VISCA_MESSAGE_ONE_BYTE_RESPONSE, response, clientSocket);
                        break;

                    default:
                        // Sent by PTZOptics:
                        // 81 01 06 06 05 ff - OSD/Menu Enter
                        // 81 01 06 06 04 ff - OSD/Menu Return
                        {
                        BOOL unknown = messageType < 0;
                        fprintf(stdout, "%s: (0x%X) ", (unknown ? "unknown" : "unhandled"), messageType);
                        hex_print(buffer, consumed);
                        fprintf(stdout, "\n");
                        sendAck(1, clientSocket);
                        [camera cameraCancel:^{sendErrorReply(1, clientSocket, unknown ? JR_VISCA_ERROR_SYNTAX : JR_VISCA_ERROR_NOT_EXECUTABLE);}];
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

