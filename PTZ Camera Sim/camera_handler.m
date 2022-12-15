#include <stdio.h>
#include "jr_socket.h"

#include "jr_hex_print.h"
#include "jr_visca.h"
#include <string.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>
#include <time.h>
#include "PTZCamera.h"

void sendMessage(int messageType, union jr_viscaMessageParameters parameters, jr_socket socket) {
    uint8_t resultData[18];
    /* Original code assumed everything it sends is a 0x90 reply (0x80 + (frame.sender << 4) + frame.receiver), hardcoded "sender" (camera number) of 1.
     * but VISCA_set_address is 0x88!
     */
    uint8_t sender = (messageType == JR_VISCA_MESSAGE_CAMERA_NUMBER) ? 0 : 1;
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
                        response.zoomPositionParameters.zoomPosition = camera.zoom;
                        sendMessage(JR_VISCA_MESSAGE_ZOOM_POSITION_INQ_RESPONSE, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_AUTOMATIC:
                        fprintf(stdout, "focus automatic\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_FOCUS_MANUAL:
                        fprintf(stdout, "focus manual\n");
                        response.ackCompletionParameters.socketNumber = 1;
                        sendAckCompletion(1, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_DIRECT:
                        fprintf(stdout, "zoom direct to position %x\n", messageParameters.zoomPositionParameters.zoomPosition);
                        camera.zoom = messageParameters.zoomPositionParameters.zoomPosition;
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_STOP:
                        fprintf(stdout, "zoom stop\n");
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_TELE_STANDARD:
                        fprintf(stdout, "zoom in standard\n");
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_WIDE_STANDARD:
                        fprintf(stdout, "zoom out standard\n");
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_TELE_VARIABLE:
                        fprintf(stdout, "zoom in at %x\n", messageParameters.zoomVariableParameters.zoomSpeed);
                        break;
                    case JR_VISCA_MESSAGE_ZOOM_WIDE_VARIABLE:
                        fprintf(stdout, "zoom out at %x\n", messageParameters.zoomVariableParameters.zoomSpeed);
                        break;
                    case JR_VISCA_MESSAGE_PAN_TILT_DRIVE:
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
                        fprintf(stdout, "\n");
                        
                        break;
                    case JR_VISCA_MESSAGE_CAMERA_NUMBER:
                        fprintf(stdout, "camera number inq\n");
                        response.cameraNumberParameters.cameraNum = 2;
                        sendMessage(JR_VISCA_MESSAGE_CAMERA_NUMBER, response, clientSocket);
                        break;
                    case JR_VISCA_MESSAGE_MEMORY:
                        switch (messageParameters.memoryParameters.mode) {
                            case JR_VISCA_MEMORY_MODE_SET:
                                fprintf(stdout, "set %d ", messageParameters.memoryParameters.memory);
                                break;
                            case JR_VISCA_MEMORY_MODE_RESET:
                                fprintf(stdout, "reset %d ", messageParameters.memoryParameters.memory);
                                break;
                            case JR_VISCA_MEMORY_MODE_RECALL:
                                fprintf(stdout, "recall %d ", messageParameters.memoryParameters.memory);
                                [camera recallAtIndex:messageParameters.memoryParameters.memory];
                                break;
                        }
                        fprintf(stdout, "\n");
                        sendAckCompletion(1, clientSocket);
                        break;
                    default:
                        fprintf(stdout, "unknown: ");
                        hex_print(buffer, consumed);
                        fprintf(stdout, "\n");
                        sendAckCompletion(1, clientSocket);
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

