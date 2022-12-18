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
@property CGFloat zoomScale;
@property (readonly) CGFloat panScale, tiltScale;

// Does not affect UI, so it's thread safe.
@property NSUInteger presetSpeed;
@property (strong) NSMutableDictionary *scenes;

@property dispatch_queue_t recallQueue;

- (void)recallAtIndex:(NSInteger)index;
- (void)saveAtIndex:(NSInteger)index;
- (void)applyPanSpeed:(NSUInteger)panS tiltSpeed:(NSUInteger)tiltS pan:(NSInteger)targetPan tilt:(NSInteger)targetTilt;

- (void)incPan:(NSUInteger)delta;
- (void)incTilt:(NSUInteger)delta;
- (void)decPan:(NSUInteger)delta;
- (void)decTilt:(NSUInteger)delta;
- (void)zoomIn:(NSUInteger)delta;
- (void)zoomOut:(NSUInteger)delta;

- (void)zoomToPosition:(NSUInteger)zoom;
- (void)cameraHome;
- (void)cameraReset;
@end

NS_ASSUME_NONNULL_END
