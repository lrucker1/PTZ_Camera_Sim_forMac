//
//  PTZCamera.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//


#import "PTZCamera.h"

#define RANGE_MAX 0x200
#define RND_MASK 0xFF
#define ZOOM_MAX 0x100
#define PT_MAX 0x100
#define PT_MIN -0x100
#define RANGE_SHIFT (0x100)

@implementation PTZCamera

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
   NSMutableSet *keyPaths = [NSMutableSet set];

  if ([key isEqualToString:@"zoomScale"]) {
      [keyPaths addObject:@"zoom"];
   }
   [keyPaths unionSet:[super keyPathsForValuesAffectingValueForKey:key]];

   return keyPaths;
}

+ (NSArray *)observationKeyPaths
{
   return @[
      @"pan", @"tilt", @"zoom"
   ];
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
        _recallQueue = dispatch_queue_create("recallQueue", NULL);
    }
    return self;
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

- (void)saveAtIndex:(NSInteger)index {
    if (self.scenes == nil) {
        self.scenes = [NSMutableDictionary new];
    }
    [self.scenes setObject:@[@(_pan), @(_tilt), @(_zoom)] forKey:@(index)];
}

- (void)getRecallPan:(NSInteger*)pan tilt:(NSInteger*)tilt zoom:(NSInteger*)zoom index:(NSInteger)index {
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

- (void)recallAtIndex:(NSInteger)index
{
    NSInteger targetPan, targetTilt, targetZoom;
    [self getRecallPan:&targetPan tilt:&targetTilt zoom:&targetZoom index:index];
    fprintf(stdout, "recall tilt %ld -> %ld, pan %ld -> %ld, zoom %ld -> %ld", (long)self.tilt, (long)targetTilt, (long)self.pan, (long)targetPan, (long)self.zoom, (long)targetZoom);

    dispatch_async(_recallQueue, ^{
        do {
            nanosleep((const struct timespec[]){{0, 100000000L}}, NULL);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSInteger dPan = targetPan - self.pan;
                NSInteger dTilt = targetTilt - self.tilt;
                NSInteger dZoom = targetZoom - self.zoom;
                if (labs(dPan) <= self.panSpeed) {
                    self.pan = targetPan;
                } else if (dPan > 0) {
                    self.pan += self.panSpeed;
                } else {
                    self.pan -= self.panSpeed;
                }
                if (labs(dTilt) <= self.tiltSpeed) {
                    self.tilt = targetTilt;
                } else if (dTilt > 0) {
                    self.tilt += self.tiltSpeed;
                } else {
                    self.tilt -= self.tiltSpeed;
                }
                if (labs(dZoom) <= self.zoomSpeed) {
                    self.zoom = targetZoom;
                } else if (dZoom > 0) {
                    self.zoom += self.zoomSpeed;
                } else {
                    self.zoom -= self.zoomSpeed;
                }
               // fprintf(stdout, "recall tilt %ld pan %ld", self.tilt, self.pan);
            });
        } while ((self.pan != targetPan) || (self.tilt != targetTilt) || (self.zoom != targetZoom));
        dispatch_async(dispatch_get_main_queue(), ^{
            fprintf(stdout, "recall done");
        });
    });
}


@end
