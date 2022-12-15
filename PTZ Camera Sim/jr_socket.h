/*
    Copyright 2021 Jacob Rau

    This file is part of libjr_socket.

    libjr_socket is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    libjr_socket is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with libjr_socket.  If not, see <https://www.gnu.org/licenses/>.
*/

#ifndef JRSOCKET_H
#define JRSOCKET_H

typedef struct _jr_socket {
    int _socket;
} jr_socket;

typedef struct _jr_server_socket {
    int _serverSocket;
} jr_server_socket;


int jr_socket_setupServerSocket(int port, jr_server_socket *serverSocket);

int jr_socket_accept(jr_server_socket serverSocket, jr_socket *socket);

/**
 * Receives up to `buffer_size` bytes (but can return fewer).
 * 
 * Returns actual number of bytes received on success, -1 on error, or
 * 0 on an orderly shutdown of the connection.
 */
ssize_t jr_socket_receive(jr_socket socket, char* buffer, ssize_t buffer_size);

/**
 * Sends all the bytes given in the buffer.
 * 
 * Returns 0 on success, -1 on error.
 */
ssize_t jr_socket_send(jr_socket socket, char* buffer, ssize_t buffer_size);

void jr_socket_closeSocket(jr_socket socket);

void jr_socket_closeServerSocket(jr_server_socket socket);

#endif
