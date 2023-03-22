//
//  AppDelegate.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/12/22.
//

#import <Cocoa/Cocoa.h>
#import "PTZCamera.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSOpenSavePanelDelegate>
{
    dispatch_queue_t socketQueue;    
}

@property (strong) PTZCamera *camera;
@property (strong) IBOutlet NSLayoutConstraint *viewHeightConstraint;
@property (strong) IBOutlet NSLayoutConstraint *viewWidthConstraint;
@property (strong) IBOutlet NSImageView *imageView;
@property (strong) IBOutlet NSClipView *clipView;
@property (strong) IBOutlet NSScrollView *scrollView;
@property (strong) IBOutlet NSView *osdMenuView;

- (void)writeCameraSnapshot;

@end

