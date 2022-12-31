//
//  PTZCamera.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZCamera : NSObject

// Protect from writes that aren't on main.
@property (readonly) NSInteger tilt;
@property (readonly) NSInteger pan;
@property (readonly) NSUInteger zoom;
@property (readonly) BOOL menuVisible;
@property (readonly) NSUInteger presetSpeed;

// Utilities to convert to 0,1.0 range for camera view.
@property (readonly) CGFloat zoomScale;
@property (readonly) CGFloat panScale, tiltScale;

// thread-safe visca command support
- (void)recallAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock;
- (void)saveAtIndex:(NSInteger)index onDone:(dispatch_block_t)doneBlock;
- (void)absolutePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)targetPan tilt:(NSInteger)targetTilt onDone:(dispatch_block_t)doneBlock;
- (void)relativePanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS panDirection:(NSInteger)panDirection tiltDirection:(NSInteger)tiltDirection onDone:(dispatch_block_t)doneBlock ;
- (void)cameraHome:(dispatch_block_t)doneBlock;
- (void)cameraReset:(dispatch_block_t)doneBlock;
- (void)cameraCancel:(dispatch_block_t)cancelBlock;
- (void)absoluteZoom:(NSUInteger)zoom;
- (void)relativeZoomIn:(NSUInteger)zoomDelta;
- (void)relativeZoomOut:(NSUInteger)zoomDelta;

- (void)toggleMenu;
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
