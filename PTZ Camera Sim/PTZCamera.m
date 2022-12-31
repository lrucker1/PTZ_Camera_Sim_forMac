//
//  PTZCamera.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#include <arpa/inet.h>

#import "PTZCamera.h"
#import "AppDelegate.h"

#define RANGE_MAX 0x200
#define RND_MASK 0xFF
#define ZOOM_MAX 0x100
#define PT_MAX 0x100
#define PT_MIN -0x100
#define RANGE_SHIFT (0x100)

#define SPEED_MAX 24

@interface PTZCamera ()
@property (readwrite) NSInteger tilt;
@property (readwrite) NSInteger pan;
@property (readwrite) NSUInteger zoom;
@property (readwrite) NSUInteger presetSpeed;

@property NSUInteger tiltSpeed;
@property NSUInteger panSpeed;
@property NSUInteger zoomSpeed;
@property BOOL menuVisible;
@property NSString *ipAddress;

@property BOOL commandRunning;
@property dispatch_block_t cancelBlock;
@property (strong) NSMutableDictionary *scenes;

@property dispatch_queue_t recallQueue;

@end

@implementation PTZCamera

+ (NSString *)hostFromSockaddr4:(const struct sockaddr_in *)pSockaddr4
{
    char addrBuf[INET_ADDRSTRLEN];
    
    if (inet_ntop(AF_INET, &pSockaddr4->sin_addr, addrBuf, (socklen_t)sizeof(addrBuf)) == NULL)
    {
        addrBuf[0] = '\0';
    }
    
    return [NSString stringWithCString:addrBuf encoding:NSASCIIStringEncoding];
}

+ (NSInteger)randomPT {
    NSInteger sign = (random() & 0x01) ? 1 : -1;
    return (random() & RND_MASK) * sign;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pan = 0;//[[self class] randomPT];
        _tilt = 0;//[[self class] randomPT];
        _zoom = 0;
        _panSpeed = 5;
        _tiltSpeed = 5;
        _zoomSpeed = 5;
        _presetSpeed = SPEED_MAX; // Real camera default
        _recallQueue = dispatch_queue_create("recallQueue", NULL);
    }
    return self;
}

- (void)setSocketFD:(int)socketFD {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.ipAddress = [self localHostFromSocket4:socketFD];
    });
}

- (NSString *)connectedHostFromSocket4:(int)socketFD
{
    struct sockaddr_in sockaddr4;
    socklen_t sockaddr4len = sizeof(sockaddr4);
    
    if (getpeername(socketFD, (struct sockaddr *)&sockaddr4, &sockaddr4len) < 0)
    {
        return nil;
    }
    return [[self class] hostFromSockaddr4:&sockaddr4];
}

- (NSString *)localHostFromSocket4:(int)socketFD
{
    struct sockaddr_in sockaddr4;
    socklen_t sockaddr4len = sizeof(sockaddr4);
    
    if (getsockname(socketFD, (struct sockaddr *)&sockaddr4, &sockaddr4len) < 0)
    {
        return nil;
    }
    return [[self class] hostFromSockaddr4:&sockaddr4];
}

- (void)setZoomScale:(CGFloat)z {
    self.zoom = z * ZOOM_MAX;
}

- (CGFloat)zoomScale {
    CGFloat z = _zoom;
    return (z / ZOOM_MAX);
}

// Scaled to (0..1).
- (CGFloat)panScale {
    CGFloat p = _pan;
    return (p + RANGE_SHIFT) / RANGE_MAX;
}

- (CGFloat)tiltScale {
    CGFloat t = _tilt;
    return (t + RANGE_SHIFT) / RANGE_MAX;
}

- (void)incPan:(NSUInteger)delta {
    NSInteger newPan = self.pan + delta;
    self.pan = MIN(PT_MAX, newPan);
}

- (void)decPan:(NSUInteger)delta {
    NSInteger newPan = self.pan - delta;
    self.pan = MAX(PT_MIN, newPan);
}

- (void)incTilt:(NSUInteger)delta {
    NSInteger newTilt = self.tilt + delta;
    self.tilt = MIN(PT_MAX, newTilt);
}

- (void)decTilt:(NSUInteger)delta {
    NSInteger newTilt = self.tilt - delta;
    self.tilt = MAX(PT_MIN, newTilt);
}


- (void)zoomIn:(NSUInteger)delta {
    NSInteger newZoom = self.zoom + delta;
    self.zoom = MIN(ZOOM_MAX, newZoom);
}

- (void)zoomOut:(NSUInteger)delta {
    NSInteger newZoom = self.zoom - delta;
    self.zoom = MAX(0, newZoom);
}

- (void)saveAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.scenes == nil) {
            self.scenes = [NSMutableDictionary new];
        }
        [self.scenes setObject:@[@(self.pan), @(self.tilt), @(self.zoom)] forKey:@(index)];
        [(AppDelegate *)[NSApp delegate] writeCameraSnapshot];
        if (doneBlock) {
            doneBlock();
        }
    });
}

- (void)getRecallPan:(NSInteger*)pan tilt:(NSInteger*)tilt zoom:(NSInteger*)zoom index:(NSInteger)index {
    if (index == 0) {
        if (pan) *pan = 0;
        if (tilt) *tilt = 0;
        if (zoom) *zoom = self.zoom;
        return;
    }
    NSArray *data = [self.scenes objectForKey:@(index)];
    if (data == nil) {
        if (pan) *pan = [[self class] randomPT];
        if (tilt) *tilt = [[self class] randomPT];
        if (zoom) *zoom = (random() & 0xFF);
    } else {
        if (pan) *pan = [[data objectAtIndex:0] integerValue];
        if (tilt) *tilt = [[data objectAtIndex:1] integerValue];
        if (zoom) *zoom = [[data objectAtIndex:2] unsignedIntegerValue];
    }
}

- (void)zoomToPosition:(NSUInteger)newZoom {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.zoom = newZoom;
    });
}

- (void)applyPresetSpeed:(NSUInteger)newSpeed {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.presetSpeed = newSpeed;
    });
}

- (void)showMenu:(BOOL)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.menuVisible = visible;
    });
}

- (void)applyPanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)targetPan tilt:(NSInteger)targetTilt onDone:(dispatch_block_t)doneBlock {
    panS = MAX(1, MIN(panS, 0x18));
    tiltS = MAX(1, MIN(tiltS, 0x14));
    fprintf(stdout, "pan %ld -> %ld at %lu, tilt %ld -> %ld at %lu\n", (long)self.pan, (long)targetPan, (unsigned long)panS, (long)self.tilt, (long)targetTilt, (unsigned long)tiltS);
    dispatch_async(_recallQueue, ^{
        self.commandRunning = YES;
        do {
            dispatch_sync(dispatch_get_main_queue(), ^{
                nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
                NSInteger dPan = targetPan - self.pan;
                NSInteger dTilt = targetTilt - self.tilt;

                if (labs(dPan) <= panS) {
                    self.pan = targetPan;
                } else if (dPan > 0) {
                    self.pan += panS;
                } else {
                    self.pan -= panS;
                }
                if (labs(dTilt) <= tiltS) {
                    self.tilt = targetTilt;
                } else if (dTilt > 0) {
                    self.tilt += tiltS;
                } else {
                    self.tilt -= tiltS;
                }
               // fprintf(stdout, "recall tilt %ld pan %ld", self.tilt, self.pan);
            });
        } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));
        if (self.cancelBlock) {
            dispatch_sync(dispatch_get_main_queue(), self.cancelBlock);
            self.cancelBlock = nil;
        } else if (doneBlock) {
            dispatch_sync(dispatch_get_main_queue(), doneBlock);
        }
        self.commandRunning = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            fprintf(stdout, "pan/tilt done");
        });
    });
}

- (void)cameraCancel:(dispatch_block_t)cancelBlock{
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (self.cancelBlock != nil) {
            self.cancelBlock();
        }
        if (self.commandRunning) {
            self.cancelBlock = cancelBlock;
        } else {
            cancelBlock();
        }
    });
}

- (void)cameraHome:(dispatch_block_t)doneBlock {
    [self recallAtIndex:0 withSpeed:SPEED_MAX onDone:doneBlock];
}

- (void)cameraReset:(dispatch_block_t)doneBlock {
    __block NSInteger targetPan = 0, targetTilt = 0;
    dispatch_block_t block = ^{
        nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
        NSInteger dPan = targetPan - self.pan;
        NSInteger dTilt = targetTilt - self.tilt;
        NSUInteger speed = SPEED_MAX;

        if (labs(dPan) <= speed) {
            self.pan = targetPan;
        } else if (dPan > 0) {
            self.pan += speed;
        } else {
            self.pan -= speed;
        }
        if (labs(dTilt) <= speed) {
            self.tilt = targetTilt;
        } else if (dTilt > 0) {
            self.tilt += speed;
        } else {
            self.tilt -= speed;
        }
       // fprintf(stdout, "recall tilt %ld pan %ld", self.tilt, self.pan);
    };
    dispatch_async(_recallQueue, ^{
        self.commandRunning = YES;
        do {
            dispatch_sync(dispatch_get_main_queue(), block);
        } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));
        
        targetTilt = PT_MIN;
        if (self.cancelBlock == nil) do {
            dispatch_sync(dispatch_get_main_queue(), block);
         } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));
        
        targetTilt = PT_MAX;
        if (self.cancelBlock == nil) do {
            dispatch_sync(dispatch_get_main_queue(), block);
         } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));

        targetTilt = 0;
        if (self.cancelBlock == nil) do {
            dispatch_sync(dispatch_get_main_queue(), block);
         } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));

        targetPan = PT_MIN;
        if (self.cancelBlock == nil) do {
            dispatch_sync(dispatch_get_main_queue(), block);
         } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));

        targetPan = PT_MAX;
        if (self.cancelBlock == nil) do {
            dispatch_sync(dispatch_get_main_queue(), block);
        } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));

        targetPan = 0;
        if (self.cancelBlock == nil) do {
            dispatch_sync(dispatch_get_main_queue(), block);
        } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt)));
        dispatch_sync(dispatch_get_main_queue(), ^{
            fprintf(stdout, "reset done\n");
        });
        if (self.cancelBlock) {
            dispatch_sync(dispatch_get_main_queue(), self.cancelBlock);
            self.cancelBlock = nil;
        } else if (doneBlock) {
            dispatch_sync(dispatch_get_main_queue(), doneBlock);
        }
        self.commandRunning = NO;
     });

}

- (void)recallAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock {
    [self recallAtIndex:index withSpeed:self.presetSpeed onDone:doneBlock];
}

- (void)recallAtIndex:(NSInteger)index withSpeed:(NSUInteger)speed onDone:(dispatch_block_t)doneBlock {
    
    NSInteger targetPan, targetTilt, targetZoom;
    [self getRecallPan:&targetPan tilt:&targetTilt zoom:&targetZoom index:index];
    fprintf(stdout, "recall tilt %ld -> %ld, pan %ld -> %ld, zoom %ld -> %ld", (long)self.tilt, (long)targetTilt, (long)self.pan, (long)targetPan, (long)self.zoom, (long)targetZoom);

    dispatch_async(_recallQueue, ^{
        self.commandRunning = YES;
        do {
            dispatch_sync(dispatch_get_main_queue(), ^{
                nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
                NSInteger dPan = targetPan - self.pan;
                NSInteger dTilt = targetTilt - self.tilt;
                NSInteger dZoom = targetZoom - self.zoom;

                if (labs(dPan) <= speed) {
                    self.pan = targetPan;
                } else if (dPan > 0) {
                    self.pan += speed;
                } else {
                    self.pan -= speed;
                }
                if (labs(dTilt) <= speed) {
                    self.tilt = targetTilt;
                } else if (dTilt > 0) {
                    self.tilt += speed;
                } else {
                    self.tilt -= speed;
                }
                if (labs(dZoom) <= speed) {
                    self.zoom = targetZoom;
                } else if (dZoom > 0) {
                    self.zoom += speed;
                } else {
                    self.zoom -= speed;
                }
               // fprintf(stdout, "recall tilt %ld pan %ld", self.tilt, self.pan);
            });
        } while (self.cancelBlock == nil && ((self.pan != targetPan) || (self.tilt != targetTilt) || (self.zoom != targetZoom)));
        fprintf(stdout, "recall done\n");
        if (self.cancelBlock) {
            dispatch_sync(dispatch_get_main_queue(), self.cancelBlock);
            self.cancelBlock = nil;
        } else if (doneBlock) {
            dispatch_sync(dispatch_get_main_queue(), doneBlock);
        }
        self.commandRunning = NO;
    });
}


@end
