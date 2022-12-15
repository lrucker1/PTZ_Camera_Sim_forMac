//
//  AppDelegate.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/12/22.
//

#import <Quartz/Quartz.h>
#import "AppDelegate.h"
#import "camera_handler.h"
#import "PTZClipView.h"

#define PORT 5678

static AppDelegate *selfType;

@interface NSAttributedString (PTZAdditions)
+ (id)attributedStringWithString: (NSString *)string;
@end

@implementation NSAttributedString (PTZAdditions)

+ (id)attributedStringWithString: (NSString *)string
{
   // Use self, so we get NSMutableAttributedStrings when called on that class.
   NSAttributedString *attributedString = [[self alloc] initWithString:string];
   return attributedString;
}

@end

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSTextView *console;
@property (strong) NSFileHandle* pipeReadHandle;
@property (strong) NSPipe *pipe;

@end

@implementation AppDelegate


- (void)handlePipeNotification:(NSNotification *)notification {
    [_pipeReadHandle readInBackgroundAndNotify];
    NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
    [self logMessage:stdOutString];
}

- (void)configConsoleRedirect {
    _pipe = [NSPipe pipe];
    _pipeReadHandle = [_pipe fileHandleForReading];
    dup2([[_pipe fileHandleForWriting] fileDescriptor], fileno(stdout));
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePipeNotification:) name:NSFileHandleReadCompletionNotification object:_pipeReadHandle];
    [_pipeReadHandle readInBackgroundAndNotify];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [self addObserver:self
           forKeyPath:@"camera.zoom"
              options:0
              context:&selfType];
    [self addObserver:self
           forKeyPath:@"camera.pan"
              options:0
              context:&selfType];
    [self addObserver:self
           forKeyPath:@"camera.tilt"
              options:0
              context:&selfType];


    self.camera = [PTZCamera new];
    [self updateZoomFactor];

    [self configConsoleRedirect];
    socketQueue = dispatch_queue_create("socketQueue", NULL);
    dispatch_async(socketQueue, ^{
        while (1) {
            handle_camera(self.camera);
        }
    });

}

- (CGFloat)zoomFactor {
    CGFloat zoom = self.camera.zoomScale;
    CGFloat fullZoom = 1.0;
    NSSize imSize = self.imageView.image.size;
    NSSize clipSize = self.clipView.bounds.size;
    if (imSize.width > 0 && imSize.height > 0 && clipSize.width > 0 && clipSize.height > 0) {
        CGFloat clipAspectRatio = clipSize.width / clipSize.height;
        CGFloat imAspectRatio = imSize.width / imSize.height;
        
        if (clipAspectRatio > imAspectRatio) {
            fullZoom = clipSize.height / imSize.height;
        } else {
            fullZoom = clipSize.width / imSize.width;
        }
    }
    // 0 : all the way out (fullZoom). Max: all the way in
    return (1 + zoom * 4) * fullZoom;

}
- (void)updateZoomFactor {
    // 0 : all the way out (fullZoom). Max: all the way in
    // But once we're faking PT too, we never want to show the whole image.
    CGFloat zoomFactor = [self zoomFactor];

    if (self.imageView.image != nil) {
        self.viewHeightConstraint.constant = self.imageView.image.size.height * zoomFactor;
        self.viewWidthConstraint.constant = self.imageView.image.size.width * zoomFactor;
    }
    // Zoom affects scroll location.
    [self updateScrollPosition];
}

- (void)updateScrollPosition {
    NSSize scrollSize = self.scrollView.bounds.size;
    if (scrollSize.width > 0 && scrollSize.height > 0) {
        CGFloat panScale = self.camera.panScale;
        CGFloat tiltScale = self.camera.tiltScale;
        NSPoint point = NSMakePoint(panScale * scrollSize.width, tiltScale * scrollSize.height);
        [self.scrollView.contentView scrollPoint:point];
    }
}

- (IBAction)panLeft:(id)sender {
    [self.camera decPan:5];
}

- (IBAction)panRight:(id)sender {
    [self.camera incPan:5];
}

- (IBAction)tiltUp:(id)sender {
    [self.camera incTilt:5];
}

- (IBAction)tiltDown:(id)sender {
    [self.camera decTilt:5];
}

- (IBAction)zoomIn:(id)sender {
    [self.camera zoomIn:5];
}

- (IBAction)zoomOut:(id)sender {
    [self.camera zoomOut:5];
}

- (void)logError:(NSString *)msg
{
    NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    [attributes setObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
    
    [[self.console textStorage] appendAttributedString:as];
    [self scrollToBottom];
}

- (void)logInfo:(NSString *)msg
{
    NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    [attributes setObject:[NSColor purpleColor] forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
    
    [[self.console textStorage] appendAttributedString:as];
    [self scrollToBottom];
}

- (void)logMessage:(NSString *)msg
{
    NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    [attributes setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
    
    [[self.console textStorage] appendAttributedString:as];
    [self scrollToBottom];
}

- (void)scrollToBottom {
    NSRange range = NSMakeRange([[self.console string] length], 0);
    [self.console scrollRangeToVisible:range];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)observeValueForKeyPath: (NSString *)keyPath    // IN
                      ofObject: (id)object             // IN
                        change: (NSDictionary *)change // IN
                       context: (void *)context        // IN
{
   if (context != &selfType) {
      [super observeValueForKeyPath:keyPath
                           ofObject:object
                             change:change
                            context:context];
   } else if ([keyPath isEqualToString:@"camera.zoom"]) {
      [self updateZoomFactor];
   } else {
      [self updateScrollPosition];
   }
}

@end
