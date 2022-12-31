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

// Note: by default you don't have write access.
// See https://www.ddiinnxx.com/setting-web-server-mac-os-x-sierra/
// and https://www.maketecheasier.com/setup-local-web-server-all-platforms/#web-server-macos
static NSString *PTZLocalhostImageFile = @"/Library/WebServer/Documents/snapshot.jpg";

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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
        [self logMessage:stdOutString];
    });
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

    //  We don't want to zoom all the way out on the image itself, because then there's no room to pan/tilt.
    self.scrollView.minMagnification = 1.1;
    self.scrollView.maxMagnification = 25;
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

- (NSPoint)scrollPoint {
    NSPoint point = NSZeroPoint;
    NSSize docSize = self.scrollView.documentView.bounds.size;
    NSSize contentSize = self.scrollView.contentView.bounds.size;
    NSSize scrollSize = NSMakeSize(docSize.width - contentSize.width, docSize.height - contentSize.height);
    if (scrollSize.width > 0 && scrollSize.height > 0) {
        CGFloat panScale = self.camera.panScale;
        CGFloat tiltScale = self.camera.tiltScale;
        point = NSMakePoint(panScale * scrollSize.width, tiltScale * scrollSize.height);
    }
    return point;
}

- (void)writeCameraSnapshot {
    NSImage *camImage = self.imageView.image;
    NSSize docSize = self.scrollView.documentView.bounds.size;
    NSSize imgSize = camImage.size;
    NSRect visRect = self.scrollView.documentVisibleRect;
    // The scaling to make the image shrink to fit, separate from magnification, which visRect has already dealt with.
    CGFloat xScale = imgSize.width / docSize.width;
    CGFloat yScale = imgSize.height / docSize.height;

    visRect.origin = NSMakePoint(visRect.origin.x * xScale, visRect.origin.y * yScale);
    visRect.size = NSMakeSize(visRect.size.width * xScale, visRect.size.height * yScale);
    NSImage* image = [[NSImage alloc] initWithSize:docSize];
    [image lockFocus];
    NSRect dest = { NSZeroPoint, docSize };
    [camImage drawInRect:dest fromRect:visRect operation:NSCompositingOperationCopy fraction:1];
    [image unlockFocus];

    NSData *imageData = [image TIFFRepresentation];
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    NSDictionary *imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:1.0] forKey:NSImageCompressionFactor];
    imageData = [imageRep representationUsingType:NSBitmapImageFileTypeJPEG properties:imageProps];
    [imageData writeToFile:PTZLocalhostImageFile atomically:YES];
}

- (void)updateScrollPosition {
    [self.scrollView.documentView scrollPoint:[self scrollPoint]];
}

- (void)updateZoomFactor {
    // 0 : all the way out (fullZoom). Max: all the way in.
    CGFloat offset = self.scrollView.minMagnification;
    CGFloat zoom = self.camera.zoomScale * (self.scrollView.maxMagnification - offset);
    // Center on the middle of the visible rect. This is so not obvious.
    NSRect visibleRect = self.scrollView.documentVisibleRect;
    NSPoint centerPoint = NSMakePoint(NSMidX(visibleRect), NSMidY(visibleRect));
    [self.scrollView setMagnification:offset + zoom centeredAtPoint:centerPoint];
    [self updateScrollPosition];
}

- (IBAction)cameraHome:(id)sender {
    [self.camera cameraHome:^{}];
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
