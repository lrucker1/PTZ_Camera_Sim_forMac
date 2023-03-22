//
//  AppDelegate.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/12/22.
//

#import <Quartz/Quartz.h>
#import "AppDelegate.h"
#import "camera_handler.h"

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
@property (copy) NSImage *baseImage;
@property BOOL filterInProgress, needsFilter;

@end

@implementation AppDelegate

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
    NSMutableSet *keyPaths = [NSMutableSet set];
    
    if (   [key isEqualToString:@"menuFocus"]) {
        [keyPaths addObject:@"camera.focus"];
    }
    return keyPaths;
}


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
    NSArray *paths = @[@"camera.zoom", @"camera.pan", @"camera.tilt", @"camera.autofocus", @"camera.focus", @"camera.colorTempIndex", @"camera.wbMode", @"camera.bwMode", @"camera.flipH", @"camera.flipV"];
    // Insert code here to initialize your application
    for (NSString *path in paths) {
        [self addObserver:self
               forKeyPath:path
                  options:0
                  context:&selfType];
    }
    //  We don't want to zoom all the way out on the image itself, because then there's no room to pan/tilt.
    self.scrollView.minMagnification = 1.1;
    self.scrollView.maxMagnification = 25;
    self.baseImage = self.imageView.image;
    self.camera = [PTZCamera new];
    [self updateZoomFactor];

    [self configConsoleRedirect];
    socketQueue = dispatch_queue_create("socketQueue", NULL);
    dispatch_async(socketQueue, ^{
        int result;
        do {
            result = handle_camera(self.camera);
        } while (result == 0);
        printf("handle_camera failed, result = %d. Make sure there's not another instance running", result);
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

- (NSImage *)menuImage:(NSRect)bounds {
    NSSize imgSize = bounds.size;
    
    NSBitmapImageRep *bir = [self.osdMenuView bitmapImageRepForCachingDisplayInRect:bounds];
    [bir setSize:imgSize];
    [self.osdMenuView cacheDisplayInRect:bounds toBitmapImageRep:bir];
    
    NSImage* image = [[NSImage alloc] initWithSize:imgSize];
    [image addRepresentation:bir];
    return image;
}

// snapshot.jpg resolution options: 1920x1080 960x600 480x300
- (void)writeCameraSnapshot {
    NSImage *camImage = self.imageView.image;
    NSSize docSize = self.scrollView.documentView.bounds.size;
    NSSize snapshotSize = self.scrollView.contentSize;
    NSSize imgSize = camImage.size;
    NSRect visRect = self.scrollView.documentVisibleRect;
    // The scaling to make the image shrink to fit, separate from magnification, which visRect has already dealt with.
    CGFloat xScale = imgSize.width / docSize.width;
    CGFloat yScale = imgSize.height / docSize.height;

    visRect.origin = NSMakePoint(visRect.origin.x * xScale, visRect.origin.y * yScale);
    visRect.size = NSMakeSize(visRect.size.width * xScale, visRect.size.height * yScale);
    visRect = NSIntegralRect(visRect);
    NSImage *image = [[NSImage alloc] initWithSize:snapshotSize];
    [image lockFocus];
    NSRect dest = { NSZeroPoint, snapshotSize };
    [camImage drawInRect:dest fromRect:visRect operation:NSCompositingOperationCopy fraction:1];
    if (self.camera.menuVisible) {
        NSImage *menuImage = [self menuImage:dest];
        [menuImage drawInRect:dest fromRect:dest operation:NSCompositingOperationSourceOver fraction:0.5];
    }
    [image unlockFocus];

    NSData *imageData = [image TIFFRepresentation];
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    NSDictionary *imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:1.0] forKey:NSImageCompressionFactor];
    imageData = [imageRep representationUsingType:NSBitmapImageFileTypeJPEG properties:imageProps];
#if 0
    // Debugging, only works with sandbox disabled.
    BOOL result = [imageData writeToFile:PTZLocalhostImageFile atomically:NO];
    if (!result) {
        [self logMessage:@"Write failed"];
    }
#else
    CFDataRef bookmark = (__bridge CFDataRef)([[NSUserDefaults standardUserDefaults] objectForKey:@"WebServerBookmark"]);
    if (bookmark == nil) {
        [self getSandboxPermission:imageData];
    } else {
        CFErrorRef error = NULL;
        Boolean isStale;
        CFURLRef urlRef = CFURLCreateByResolvingBookmarkData(kCFAllocatorDefault, bookmark, kCFURLBookmarkResolutionWithSecurityScope, nil, NULL, &isStale, &error);
        if (isStale || error != NULL) {
            [self getSandboxPermission:imageData];
        } else {
            CFURLStartAccessingSecurityScopedResource(urlRef);
            BOOL result = [imageData writeToFile:PTZLocalhostImageFile atomically:NO];
            CFURLStopAccessingSecurityScopedResource(urlRef);
            if (!result) {
                [self logMessage:@"Write failed, deleting bookmark."];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WebServerBookmark"];
            }
        }
        CFRelease(urlRef);
    }
#endif
}

- (void)getSandboxPermission:(NSData *)imageData {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = NSLocalizedString(@"Sandbox requires permission to write the image snapshot to /Library/WebServer/Documents.", @"Sandbox Panel message");
    
    NSURL *directoryURL = [NSURL fileURLWithPath:[PTZLocalhostImageFile stringByDeletingLastPathComponent]];
    panel.directoryURL = directoryURL;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = NO;
    panel.delegate = self;
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            if ([panel.URL isEqualTo:directoryURL]) {
                 CFErrorRef error = NULL;
                 CFDataRef bookmark = CFURLCreateBookmarkData(kCFAllocatorDefault, (__bridge CFURLRef)(directoryURL),
                         kCFURLBookmarkCreationWithSecurityScope, nil, nil, &error);
                if (error == NULL) {
                    [[NSUserDefaults standardUserDefaults] setObject:(__bridge id _Nullable)(bookmark) forKey:@"WebServerBookmark"];
                }
                [imageData writeToFile:PTZLocalhostImageFile atomically:NO];
            }
        }
   }];
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

// Real cameras generate the snapshot.jpg on demand, but it's accessed through the web server (port 80) and we are only simulating the camera port (5678).
- (IBAction)takeSnapshot:(id)sender {
    [self writeCameraSnapshot];
}

// For reasons not immediately apparent (maybe the font?) KVO is treating the value as a string.
- (NSString *)menuFocus {
    return [NSString stringWithFormat:@"%d", (int)self.camera.focus];
}

- (void)setMenuFocus:(NSString *)menuFocusStr {
    NSInteger menuFocus = [menuFocusStr integerValue];
    menuFocus = MAX(0, MIN(menuFocus, FOCUS_MAX));
    [self.camera focusDirect:menuFocus];
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

// To simulate focus vs autofocus, we blur the image.
- (void)applyImageFilters {
    if (self.filterInProgress) {
        self.needsFilter = YES;
        return;
    }
    BOOL useFocusFilter = self.camera.autofocus == NO && self.camera.focusPixelRadius > 1;
    BOOL useTempFilter = self.camera.wbMode == WB_MODE_COLOR;
    BOOL mirrorX = self.camera.flipH;
    BOOL mirrorY = self.camera.flipV;
    BOOL useFlipFilter = mirrorX || mirrorY;
    BOOL useBlackWhiteFilter = self.camera.bwMode;
    if (!useFocusFilter && !useTempFilter && !useFlipFilter && !useBlackWhiteFilter) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.image = [self.baseImage copy];
        });
        return;
    }
    
    self.filterInProgress = YES;
    CIContext *context = [CIContext contextWithOptions:nil];
    CIImage *inputImage = [CIImage imageWithData:[self.baseImage TIFFRepresentation]];

    if (useFocusFilter) {
        CIFilter *blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
        [blurFilter setDefaults];
        [blurFilter setValue:inputImage forKey:@"inputImage"];
        CGFloat blurLevel = self.camera.focusPixelRadius;
        [blurFilter setValue:[NSNumber numberWithFloat:blurLevel] forKey:@"inputRadius"];
        inputImage = [blurFilter valueForKey:@"outputImage"];
    }
    if (useTempFilter) {
        // Tweak it; the image is already warm. Camera range is 2500-8000, filter range is 0-13000
        NSInteger colorTemp = self.camera.colorTemp+3000;

        CIFilter *tempFilter = [CIFilter filterWithName:@"CITemperatureAndTint"];
        [tempFilter setDefaults];
        [tempFilter setValue:inputImage forKey:@"inputImage"];
        [tempFilter setValue:[CIVector vectorWithX:colorTemp Y:0] forKey:@"inputTargetNeutral"];
        inputImage = [tempFilter valueForKey:@"outputImage"];
    }
    if (useFlipFilter) {
        inputImage = [inputImage imageByApplyingTransform:CGAffineTransformMakeScale(mirrorX?-1:1, mirrorY?-1:1)];
        inputImage = [inputImage imageByApplyingTransform:CGAffineTransformMakeTranslation(mirrorX?self.imageView.image.size.width:0, mirrorY?self.imageView.image.size.height:0)];
    }
    // CIColorMonochrome for CAM_PictureEffect B&W
    if (useBlackWhiteFilter) {
        CIFilter *tempFilter = [CIFilter filterWithName:@"CIColorMonochrome"];
        [tempFilter setDefaults];
        [tempFilter setValue:inputImage forKey:@"inputImage"];
        [tempFilter setValue:[CIColor grayColor] forKey:@"inputColor"];
        inputImage = [tempFilter valueForKey:@"outputImage"];
    }
    CGImageRef cgImage = [context createCGImage:inputImage fromRect:inputImage.extent];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.imageView.image = [[NSImage alloc] initWithCGImage:cgImage size:self.baseImage.size];
    });

    // Create an NSImage with the same size as the original; extent is not the same.
    self.filterInProgress = NO;
    // TODO: This is totally comp 101 level of request consolidation.
    if (self.needsFilter) {
        [self performSelector:_cmd withObject:nil afterDelay:0];
    }
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(delete:) && [NSApp keyWindow] == self.console.window) {
        return YES;
    }
    return NO;
}

- (IBAction)delete:(id)sender {
    [[self.console textStorage] setAttributedString:[NSAttributedString new]];
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
   } else if (   [keyPath isEqualToString:@"camera.autofocus"]
              || [keyPath isEqualToString:@"camera.focus"]
              || [keyPath isEqualToString:@"camera.colorTempIndex"]
              || [keyPath isEqualToString:@"camera.wbMode"]
              || [keyPath isEqualToString:@"camera.bwMode"]
              || [keyPath isEqualToString:@"camera.flipH"]
              || [keyPath isEqualToString:@"camera.flipV"]) {
      [self applyImageFilters];
   } else { // pan, tilt.
      [self updateScrollPosition];
   }
}

@end
