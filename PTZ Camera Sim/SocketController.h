//
//  SocketController.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/13/22.
//

#ifndef SocketController_h
#define SocketController_h
// SocketController.h

#import <Foundation/Foundation.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>

@protocol SocketControllerDelegate

- (void) onSocketControllerConnect;
- (void) onSocketControllerError: (int) error;

@optional

- (void) onSocketControllerData: (NSMutableData *) data;
- (void) onSocketControllerMessage: (NSString *) message;

@end

@interface SocketController : NSObject {
    id <SocketControllerDelegate> _delegate;
    CFSocketRef _socket;
}

- (id) initWithIPAddress: (const char *) ip port: (int) port delegate: (id <SocketControllerDelegate>) delegate;
- (void) onConnect;
- (void) onError: (int) error;
- (void) onData: (NSMutableData *) data;
- (void) sendString: (NSString *) message;
- (void)replySuccess;

@end


#endif /* SocketController_h */
