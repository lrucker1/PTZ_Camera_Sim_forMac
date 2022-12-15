// simple socket wrapper class for objective-c


// SocketController.m

#import "SocketController.h"

@implementation SocketController

static void socketCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void * data, void * info)
{
    SocketController * socketController = (__bridge SocketController *) info;
	
	if (type == kCFSocketConnectCallBack)
	{
		if (data)
		{
			[socketController onError: (long) data];
		}
		else
		{
			[socketController onConnect];
		}
		return;
	}
	
	if (type == kCFSocketDataCallBack)
	{
        [socketController onData: (__bridge NSMutableData *) data];
	}
}

- (void) dealloc
{
	if (_socket)
	{
		CFSocketInvalidate(_socket);
		_socket = nil;
	}
}

- (id) initWithIPAddress: (const char *) ip port: (int) port delegate: (id <SocketControllerDelegate>) delegate
{
	if ((self = [super init]))
	{
		_delegate = delegate;
		
		CFSocketContext context = {
			.version = 0,
            .info = (__bridge void *)(self),
			.retain = NULL,
			.release = NULL,
			.copyDescription = NULL
		};
		
		_socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketDataCallBack ^ kCFSocketConnectCallBack, socketCallBack, &context);
		
		struct sockaddr_in addr4;
		memset(&addr4, 0, sizeof(addr4));
		addr4.sin_family = AF_INET;
		addr4.sin_len = sizeof(addr4);
		addr4.sin_port = htons(port);

        if (ip != nil) {
            inet_aton(ip, &addr4.sin_addr);
            NSData * address = [NSData dataWithBytes: &addr4 length: sizeof(addr4)];
            CFSocketConnectToAddress(_socket, (CFDataRef) address, -1);
        } else {
            addr4.sin_addr.s_addr = htonl(INADDR_ANY);
            CFDataRef addressData =
                CFDataCreate(NULL, (const UInt8 *)&addr4, sizeof(addr4));
            
            if (CFSocketSetAddress(_socket, addressData) != kCFSocketSuccess)
            {
                NSLog(@"Unable to bind socket to address.");
                return nil;
            }
        }
        
		CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, _socket, 1);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
		CFRelease(source);
	}
	return self;
}

- (void) onConnect
{
	if (_delegate)
	{
		[_delegate onSocketControllerConnect];
	}
}

- (void) onError: (int) error
{
	if (_delegate)
	{
		[_delegate onSocketControllerError: error];
	}
}

- (void) onData: (NSMutableData *) data
{
	if (_delegate && [(id) _delegate respondsToSelector: @selector(onSocketControllerMessage:)])
	{
		[_delegate onSocketControllerMessage: [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding]];
	}
	if (_delegate && [(id) _delegate respondsToSelector: @selector(onSocketControllerData:)])
	{
		[_delegate onSocketControllerData: data];
	}
}

- (void)replySuccess {
    const char reply[3] = {0x90, 0x50, 0xff};
    NSData *data = [NSData dataWithBytes:reply length:3];
    
    CFSocketError error = CFSocketSendData(_socket, NULL, (CFDataRef) data, 0);
    if (error > 0 && _delegate)
    {
        [_delegate onSocketControllerError: (int)error];
    }

}

- (void) sendString: (NSString *) message
{
	const char * sendStrUTF = [message UTF8String];
	NSData * data = [NSData dataWithBytes: sendStrUTF length: strlen(sendStrUTF)];
	
	CFSocketError error = CFSocketSendData(_socket, NULL, (CFDataRef) data, 0);
	
	if (error > 0 && _delegate)
	{
		[_delegate onSocketControllerError: (int)error];
	}
}

@end
