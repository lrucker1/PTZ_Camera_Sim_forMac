//
//  PTZCamera.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>
#import "jr_socket.h"

NS_ASSUME_NONNULL_BEGIN

#define FOCUS_MAX 0x100
#define WB_MODE_COLOR 0x20

@interface PTZCamera : NSObject

// Protect from writes that aren't on main.
@property (readonly) NSInteger tilt;
@property (readonly) NSInteger pan;
@property (readonly) NSUInteger zoom;
@property (readonly) BOOL menuVisible;
@property (readonly) BOOL autofocus;
@property (readonly) NSUInteger focus;
@property (readonly) NSUInteger presetSpeed;
@property (readonly) NSUInteger colorTempIndex;
@property (readonly) NSUInteger wbMode;
@property (readonly) BOOL flipH;
@property (readonly) BOOL flipV;
@property (readonly) BOOL bwMode;
@property (readonly) NSUInteger pictureEffectMode;
@property (readonly) NSUInteger flipHOnOff;
@property (readonly) NSUInteger flipVOnOff;
@property (readonly) NSUInteger aeMode;     // 39
@property (readonly) NSUInteger aperture;   // 42
@property (readonly) NSUInteger shutter;    // 4A
@property (readonly) NSUInteger iris;       // 4B
@property (readonly) NSUInteger brightPos;  // 4D
@property (readonly) NSUInteger brightness; // A1
@property (readonly) NSUInteger contrast;   // A2
@property (readonly) NSUInteger bGain;
@property (readonly) NSUInteger rGain;
@property (readonly) NSUInteger colorgain;
@property (readonly) NSUInteger hue;
@property (readonly) NSUInteger awbSens;

// Utilities to convert to appropriate ranges for fake camera view.
@property (readonly) CGFloat zoomScale;
@property (readonly) CGFloat panScale, tiltScale;
@property (readonly) CGFloat focusPixelRadius;
@property (readonly) NSUInteger colorTemp;

// Keep alive
- (void)pingCamera:(jr_socket)clientSocket;

// thread-safe visca command support
- (void)safeSetNumber:(NSInteger)value forKey:(NSString *)key;

- (void)recallAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock;
- (void)cameraSetAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock;
- (void)absolutePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)targetPan tilt:(NSInteger)targetTilt onDone:(dispatch_block_t)doneBlock;
- (void)relativePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)deltaPan tilt:(NSInteger)deltaTilt onDone:(dispatch_block_t)doneBlock;
- (void)startPanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS panDirection:(NSInteger)panDirection tiltDirection:(NSInteger)tiltDirection onDone:(dispatch_block_t)doneBlock;
- (void)cameraHome:(dispatch_block_t)doneBlock;
- (void)cameraReset:(dispatch_block_t)doneBlock;
- (void)cameraCancel:(dispatch_block_t)cancelBlock;
- (void)absoluteZoom:(NSUInteger)zoom;
- (void)startZoomIn:(NSUInteger)delta;
- (void)startZoomOut:(NSUInteger)delta;
- (void)zoomStop;
- (void)focusDirect:(NSUInteger)focus;
- (void)relativeFocusFar:(NSUInteger)delta;
- (void)relativeFocusNear:(NSUInteger)delta;

- (void)toggleMenu;
- (void)toggleAutofocus;
- (void)focusAutomatic;
- (void)focusManual;
- (void)showMenu:(BOOL)visible;
- (void)setSocketFD:(int)socketFD;

// utilities
- (void)incPan:(NSUInteger)delta;
- (void)incTilt:(NSUInteger)delta;
- (void)decPan:(NSUInteger)delta;
- (void)decTilt:(NSUInteger)delta;
- (void)zoomIn:(NSUInteger)delta;
- (void)zoomOut:(NSUInteger)delta;

@end

NS_ASSUME_NONNULL_END
