//
//  PTZCamera.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>

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
@property (readonly) NSUInteger aperture;
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

// thread-safe visca command support
- (void)safeSetNumber:(NSInteger)value forKey:(NSString *)key;

- (void)recallAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock;
- (void)cameraSetAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock;
- (void)absolutePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)targetPan tilt:(NSInteger)targetTilt onDone:(dispatch_block_t)doneBlock;
- (void)relativePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS panDirection:(NSInteger)panDirection tiltDirection:(NSInteger)tiltDirection onDone:(dispatch_block_t)doneBlock;
- (void)cameraHome:(dispatch_block_t)doneBlock;
- (void)cameraReset:(dispatch_block_t)doneBlock;
- (void)cameraCancel:(dispatch_block_t)cancelBlock;
- (void)absoluteZoom:(NSUInteger)zoom;
- (void)relativeZoomIn:(NSUInteger)zoomDelta;
- (void)relativeZoomOut:(NSUInteger)zoomDelta;
- (void)focusDirect:(NSUInteger)focus;

- (void)toggleMenu;
- (void)toggleAutofocus;
- (void)focusAutomatic;
- (void)focusManual;
- (void)showMenu:(BOOL)visible;
- (void)applyPresetSpeed:(NSUInteger)speed;
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
