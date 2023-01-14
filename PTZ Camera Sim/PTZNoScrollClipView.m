//
//  PTZNoScrollClipView.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 1/9/23.
//

#import "PTZNoScrollClipView.h"

@implementation PTZNoScrollClipView

// Scroll wheel or trackpad! The latter is far too easy to hit, and even virtual cameras do not like being manually moved.
- (void)scrollWheel:(NSEvent *)event {
    // nope!
}
@end
