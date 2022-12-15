//
//  PTZCamera.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZCamera : NSObject

@property NSInteger tilt;
@property NSInteger pan;
@property NSUInteger zoom;
@property CGFloat zoomScale;
@property (readonly) CGFloat panScale, tiltScale;

@property NSUInteger tiltSpeed;
@property NSUInteger panSpeed;
@property NSUInteger zoomSpeed;

@property dispatch_queue_t recallQueue;

- (void)recallAtIndex:(NSInteger)index;
- (void)incPan:(NSUInteger)delta;
- (void)incTilt:(NSUInteger)delta;
- (void)decPan:(NSUInteger)delta;
- (void)decTilt:(NSUInteger)delta;
- (void)zoomIn:(NSUInteger)delta;
- (void)zoomOut:(NSUInteger)delta;

@end

NS_ASSUME_NONNULL_END
