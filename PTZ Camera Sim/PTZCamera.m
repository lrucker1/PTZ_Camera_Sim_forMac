//
//  PTZCamera.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#include <arpa/inet.h>

#import "PTZCamera.h"
#import "AppDelegate.h"
#import "jr_visca.h"

#define RANGE_MAX 0x200
#define RND_MASK 0xFF
#define ZOOM_MAX 0x100
#define PT_MAX 0x100
#define PT_MIN -0x100
#define RANGE_SHIFT (0x100)

#define SPEED_MAX 24


@interface NSDictionary (PTZ_Sim_Extras)
- (NSInteger)sim_numberForKey:(NSString *)key ifNil:(NSInteger)value;
@end

@implementation NSDictionary (PTZ_Sim_Extras)
- (NSInteger)sim_numberForKey:(NSString *)key ifNil:(NSInteger)value {
    NSNumber *num = [self objectForKey:key];
    return num ? [num integerValue]: value;
}
@end

@interface PTZCameraScene : NSObject
// Old firmware saved values
@property (readwrite) NSInteger tilt;
@property (readwrite) NSInteger pan;
@property (readwrite) NSUInteger zoom;
@property BOOL autofocus;
// New firmware saved values
// https://help.ptzoptics.com/support/discussions/topics/13000031504

@end


@interface PTZCamera ()
@property (readwrite) NSInteger tilt;
@property (readwrite) NSInteger pan;
@property (readwrite) NSUInteger zoom;
@property (readwrite) NSUInteger presetSpeed;
@property (readwrite) NSUInteger focus;
@property (readwrite) NSUInteger wbMode;
@property (readwrite) NSUInteger colorTempIndex;
@property (readwrite) BOOL bwMode;
@property (readwrite) BOOL flipH;
@property (readwrite) BOOL flipV;

@property NSUInteger tiltSpeed;
@property NSUInteger panSpeed;
@property NSUInteger zoomSpeed;
@property BOOL menuVisible;
@property BOOL autofocus;
@property NSString *ipAddress;

@property BOOL commandRunning;
@property BOOL pantiltMoving, zoomMoving, focusMoving;
@property dispatch_block_t cancelBlock;
@property (strong) NSMutableDictionary *scenes;

@property dispatch_queue_t recallQueue;

@end

@implementation PTZCameraScene
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _pan = [dict[@"pan"] integerValue];
        _tilt = [dict[@"tilt"] integerValue];
        _zoom = [dict[@"zoom"] integerValue];
        _autofocus = [dict[@"autofocus"] boolValue];
        // iris default = F2.8 on Sony
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{@"pan":@(_pan), @"tilt":@(_tilt), @"zoom": @(_zoom), @"autofocus":@(_autofocus)};
}

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
        _focus = 80;
        _autofocus = YES;
        _presetSpeed = SPEED_MAX; // Real camera default
        _colorTempIndex = 0x37;
        _recallQueue = dispatch_queue_create("recallQueue", NULL);
        NSDictionary *defaultScenes = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"Scenes"];
        if (defaultScenes) {
            _scenes = [NSMutableDictionary dictionaryWithDictionary:defaultScenes];
        }
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

// PTZ: 0x00: 2500K ~ 0x37: 8000K
- (NSUInteger)colorTemp {
    return (self.colorTempIndex * 100) + 2500;
}

// Focus Position Direct 81 01 04 48 0p 0q 0r 0s FF
// Focus Position Inq [81 09 04 48 FF] reply [90 50 0p 0q 0r 0s FF]
// Convert to a range from 0-20 for the fake camera.
- (CGFloat)focusPixelRadius {
    CGFloat f = _focus;
    return (f / FOCUS_MAX) * 20.0;
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

- (NSArray *)presetKeys {
    return @[@"pan", @"tilt", @"zoom", @"presetSpeed", @"focus", @"wbMode", @"colorTempIndex", @"pictureEffectMode", @"flipHOnOff", @"flipVOnOff", @"autofocus"];
}

- (NSDictionary *)sceneDictionaryValue {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"UseOldFirmwareForPresets"]) {
        
        return @{@"pan":@(_pan), @"tilt":@(_tilt), @"zoom": @(_zoom), @"autofocus":@(_autofocus)};
    }
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSArray *keys = [self presetKeys];
    for (NSString *key in keys) {
        id obj = [self valueForKey:key];
        if (obj) {
            [dictionary setObject:obj forKey:key];
        }
    }
    return dictionary;
}

- (void)writeScenesToDefaults {
    if (self.scenes != nil) {
        [[NSUserDefaults standardUserDefaults] setObject:self.scenes forKey:@"Scenes"];
    }
}

- (void)cameraSetAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.scenes == nil) {
            self.scenes = [NSMutableDictionary new];
        }
        [self.scenes setObject:[self sceneDictionaryValue] forKey:[NSString stringWithFormat:@"%ld", (long)index]];
        [self writeScenesToDefaults];
        [(AppDelegate *)[NSApp delegate] writeCameraSnapshot];
        fprintf(stdout, "set %ld done\n", index);
        if (doneBlock) {
            doneBlock();
        }
    });
}

// PTZOptics cameras don't return "Completion" if there's no scene to recall. This may be a bug but strictRecallMode will let us find a workaround.
- (BOOL)strictRecallMode {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"StrictRecallMode"];
}

- (NSDictionary *)getRecallAtIndex:(NSInteger)index {
    NSDictionary *data = [self.scenes objectForKey:[NSString stringWithFormat:@"%ld", (long)index]];
    if (index == 0) {
        if (data == nil) {
            return @{@"pan":@(0), @"tilt":@(0), @"zoom": @(0), @"autofocus":@(YES), @"focus":@(80), @"wbMode":@(0), @"colorTempIndex":@(0x37)};
        }
        return data;
    }
    if (data == nil && !self.strictRecallMode) {
        return @{@"pan":@([[self class] randomPT]), @"tilt":@([[self class] randomPT]), @"zoom": @(random() & 0xFF), @"autofocus":@(YES), @"focus":@(80), @"wbMode":@(0), @"colorTempIndex":@(0x37)};
    }
    return data;
}

- (void)focusDirect:(NSUInteger)newFocus {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.focus = MAX(0, MIN(newFocus, FOCUS_MAX));
    });
}

- (void)relativeFocusFar:(NSUInteger)delta {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger newFocus = self.focus + delta;
        self.focus = MAX(0, MIN(newFocus, FOCUS_MAX));
    });
}

- (void)relativeFocusNear:(NSUInteger)delta {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger newFocus = self.focus - delta;
        self.focus = MAX(0, MIN(newFocus, FOCUS_MAX));
    });
}

- (void)absoluteZoom:(NSUInteger)newZoom {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.zoom = MAX(0, MIN(newZoom, ZOOM_MAX));
    });
}

- (void)relativeZoomIn:(NSUInteger)delta {
    if (self.zoomMoving) {
        return;
    }
    self.zoomMoving = YES;
    dispatch_async(_recallQueue, ^{
        while (self.zoomMoving && self.zoom < ZOOM_MAX) {
            nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self zoomIn:delta];
            });
        }
        self.zoomMoving = NO;
    });
}

- (void)relativeZoomOut:(NSUInteger)delta {
    if (self.zoomMoving) {
        return;
    }
    self.zoomMoving = YES;
    dispatch_async(_recallQueue, ^{
        while (self.zoomMoving && self.zoom > 0) {
            nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self zoomOut:delta];
            });
        }
        self.zoomMoving = NO;
    });
}

- (void)zoomStop {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.zoomMoving = NO;
    });
}

- (void)safeSetNumber:(NSInteger)value forKey:(NSString *)key {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setValue:@(value) forKey:key];
    });
}

- (void)setPictureEffectMode:(NSUInteger)picFX {
    self.bwMode = (picFX == JR_VISCA_PICTURE_FX_MODE_BW);
}

- (NSUInteger)pictureEffectMode {
    return self.bwMode ? JR_VISCA_PICTURE_FX_MODE_BW : JR_VISCA_PICTURE_FX_MODE_OFF_REPLY;
}

- (void)setFlipHOnOff:(NSUInteger)flip {
    self.flipH = ONOFF_TO_BOOL(flip);
}

- (NSUInteger)flipHOnOff {
    return BOOL_TO_ONOFF(self.flipH);
}

- (void)setFlipVOnOff:(NSUInteger)flip {
    self.flipV = ONOFF_TO_BOOL(flip);
}

- (NSUInteger)flipVOnOff {
    return BOOL_TO_ONOFF(self.flipV);
}

- (void)focusAutomatic {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.autofocus = YES;
    });
}

- (void)focusManual {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.autofocus = NO;
    });
}

- (void)toggleAutofocus {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.autofocus = !self.autofocus;
    });
}

- (void)toggleMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.menuVisible = !self.menuVisible;
    });
}

- (void)showMenu:(BOOL)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.menuVisible = visible;
    });
}

/* Doc says osd menu navigation uses exact same command structure as relative PanTilt, except with magic numbers for the speed:
 Navigate Up 81 01 06 01 0E 0E 03 01 FF
 PanTilt  Up 81 01 06 01 VV WW 03 01 FF
 
 But the PTZOptics app doesn't send the magic numbers - and they're legit speeds, anyway - so I think the camera is modal.
 That explains why the Home button doesn't work like the center button on the remote.
 */
- (void)navigateMenuPanDirection:(NSInteger)panDirection tiltDirection:(NSInteger)tiltDirection {
    // Only one of left/right and up/down should be set.
    // I used to translate events into keyboard navigation in my day job. That's why I'm not doing it now.
    // You don't really want to remote control the sim menu
    switch (panDirection) {
        case JR_VISCA_PAN_DIRECTION_LEFT:
            fprintf(stdout, "  Menu Left\n");
            break;
        case JR_VISCA_PAN_DIRECTION_RIGHT:
            fprintf(stdout, "  Menu Right\n");
            break;
        case JR_VISCA_PAN_DIRECTION_STOP:
            break;
    }

    switch (tiltDirection) {
        case JR_VISCA_TILT_DIRECTION_DOWN:
            fprintf(stdout, "  Menu Down\n");
            break;
        case JR_VISCA_TILT_DIRECTION_UP:
            fprintf(stdout, "  Menu Up\n");
            break;
        case JR_VISCA_TILT_DIRECTION_STOP:
            break;
    }
}

// Relative means start moving and keep on until "stop".
- (void)relativePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS panDirection:(NSInteger)panDirection tiltDirection:(NSInteger)tiltDirection onDone:(dispatch_block_t)doneBlock {
    if (self.menuVisible) {
        [self navigateMenuPanDirection:panDirection tiltDirection:tiltDirection];
        return;
    }
    if (doneBlock) {
        doneBlock();
    }
    if (self.pantiltMoving) {
        if (panDirection == JR_VISCA_PAN_DIRECTION_STOP && tiltDirection == JR_VISCA_TILT_DIRECTION_STOP) {
            self.pantiltMoving = NO;
        }
        return;
    }
    dispatch_async(_recallQueue, ^{
        NSInteger pan = self.pan;
        NSInteger tilt = self.tilt;
        self.pantiltMoving = YES;
        BOOL moving = YES;
        while (self.pantiltMoving && moving) {
            nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
            switch (panDirection) {
                case JR_VISCA_PAN_DIRECTION_LEFT:
                    pan -= panS;
                    break;
                case JR_VISCA_PAN_DIRECTION_RIGHT:
                    pan += panS;
                    break;
                case JR_VISCA_PAN_DIRECTION_STOP:
                    break;
            }
            
            switch (tiltDirection) {
                case JR_VISCA_TILT_DIRECTION_DOWN:
                    tilt -= tiltS;
                    break;
                case JR_VISCA_TILT_DIRECTION_UP:
                    tilt += tiltS;
                    break;
                case JR_VISCA_TILT_DIRECTION_STOP:
                    break;
            }
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (panDirection != JR_VISCA_PAN_DIRECTION_STOP) {
                    self.pan = MAX(PT_MIN, MIN(pan, PT_MAX));
                }
                if (tiltDirection != JR_VISCA_TILT_DIRECTION_STOP) {
                    self.tilt = MAX(PT_MIN, MIN(tilt, PT_MAX));
                }
                fprintf(stdout, "pan %ld, tilt %ld\n", (long)self.pan, (long)self.tilt);
            });
            if (tiltS == 0) {
                moving = labs(pan) < PT_MAX;
            } else if (panS == 0) {
                moving = labs(tilt) < PT_MAX;
            } else {
                moving = labs(pan) < PT_MAX && labs(tilt) < PT_MAX;
            }
        }
        self.pantiltMoving = NO;
    });
}

- (void)absolutePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)targetPan tilt:(NSInteger)targetTilt onDone:(dispatch_block_t)doneBlock {
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
    
    NSDictionary *scene = [self getRecallAtIndex:index];
    if (scene != nil) {
        fprintf(stdout, "recall %ld %s\n", (long)index, [[scene debugDescription] UTF8String]);
    } else {
        fprintf(stdout, "recall failed\n");
        return; // Yes, without calling the done block. This is emulating a PTZOptics camera bug.
    }
    
    NSMutableArray *keys = [NSMutableArray arrayWithArray:[scene allKeys]];
    [keys removeObjectsInArray:@[@"pan", @"tilt", @"zoom"]];
    
    for (NSString *key in keys) {
        id obj = [scene objectForKey:key];
        if (obj) {
            [self setValue:obj forKey:key];
        }
    }
    NSInteger targetPan = [scene[@"pan"] integerValue];
    NSInteger targetTilt = [scene[@"tilt"] integerValue];
    NSInteger targetZoom = [scene[@"zoom"] integerValue];

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
//        self.wbMode = [scene sim_numberForKey:@"wbMode" ifNil:0];
//        self.colorTempIndex = [scene sim_numberForKey:@"colorTempIndex" ifNil:0x37];
//        self.autofocus = [scene sim_numberForKey:@"autofocus" ifNil:YES];
//        self.focus = [scene sim_numberForKey:@"focus" ifNil:80];
        fprintf(stdout, "recall %ld done\n", index);
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
