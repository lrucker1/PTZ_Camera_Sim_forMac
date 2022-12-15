//
//  HTTPServer.h
//  TextTransfer
//
//  Created by Matt Gallagher on 2009/07/13.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

#import <Cocoa/Cocoa.h>

typedef enum
{
	SERVER_STATE_IDLE,
	SERVER_STATE_STARTING,
	SERVER_STATE_RUNNING,
	SERVER_STATE_STOPPING
} HTTPServerState;

@class HTTPResponseHandler;

@interface HTTPServer : NSObject
{
	NSError *lastError;
	HTTPServerState state;
	CFMutableDictionaryRef incomingRequests;
	NSMutableSet *responseHandlers;
}

@property (nonatomic, readonly, retain) NSError *lastError;
@property (readonly, assign) HTTPServerState state;
@property (readwrite) CFSocketRef socket;
@property (strong) NSFileHandle *listeningHandle;


+ (HTTPServer *)sharedHTTPServer;

- (void)start;
- (void)stop;

- (void)closeHandler:(HTTPResponseHandler *)aHandler;

@end

extern NSString * const HTTPServerNotificationStateChanged;
