//
//  PTZClipView.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import "PTZClipView.h"

@implementation PTZClipView
#if 0
- (void)positionDocument
{

   NSRect docRect = [[self documentView] frame];
   NSRect clipRect = [self bounds];

   if (NSWidth(docRect) < NSWidth(clipRect)) {
      clipRect.origin.x = roundf((NSWidth(docRect) - NSWidth(clipRect)) / 2.0);
   } else {
      clipRect.origin.x = 0;
   }

   if (NSHeight(docRect) < NSHeight(clipRect) ) {
      clipRect.origin.y = NSMaxY(docRect) - NSHeight(clipRect);
   }

   [self scrollToPoint:clipRect.origin];

   [[self superview] setNeedsDisplay:YES];
}

// Note that you can move an implementation of the deprecated constrainScrollPoint: to this method by adjusting the origin of proposedBounds (instead of using the newOrigin parameter in -constrainScrollPoint:). To preserve compatibility, if a subclass overrides -constrainScrollPoint:, the default behavior of constrainBoundsRect: will be to use that -constrainScrollPoint: to adjust the origin of proposedBounds, and to not change the size
#if 1
- (NSRect)constrainBoundsRect:(NSRect)proposedClipViewBoundsRect {

    NSRect constrainedClipViewBoundsRect = [super constrainBoundsRect:proposedClipViewBoundsRect];
    
    NSRect documentViewFrameRect = [self.documentView frame];
                
    // If proposed clip view bounds width is greater than document view frame width, center it horizontally.
    if (proposedClipViewBoundsRect.size.width >= documentViewFrameRect.size.width) {
        // Adjust the proposed origin.x
        constrainedClipViewBoundsRect.origin.x = centeredCoordinateUnitWithProposedContentViewBoundsDimensionAndDocumentViewFrameDimension(proposedClipViewBoundsRect.size.width, documentViewFrameRect.size.width);
    }

    // If proposed clip view bounds is hight is greater than document view frame height, center it vertically.
    if (proposedClipViewBoundsRect.size.height >= documentViewFrameRect.size.height) {
        
        // Adjust the proposed origin.y
        constrainedClipViewBoundsRect.origin.y = centeredCoordinateUnitWithProposedContentViewBoundsDimensionAndDocumentViewFrameDimension(proposedClipViewBoundsRect.size.height, documentViewFrameRect.size.height);
    }

    return constrainedClipViewBoundsRect;
}


CGFloat centeredCoordinateUnitWithProposedContentViewBoundsDimensionAndDocumentViewFrameDimension
(CGFloat proposedContentViewBoundsDimension,
 CGFloat documentViewFrameDimension )
{
    CGFloat result = floor( (proposedContentViewBoundsDimension - documentViewFrameDimension) / -2.0F );
    return result;
}
#else
- (NSPoint)constrainScrollPoint: (NSPoint)proposedScrollPoint // IN
{
   NSRect docRect = [[self documentView] frame];
   NSRect clipRect = [self bounds];
   proposedScrollPoint = [super constrainScrollPoint:proposedScrollPoint];

   if (NSWidth(docRect) < NSWidth(clipRect)) {
        proposedScrollPoint.x = roundf((NSWidth(docRect) - NSWidth(clipRect)) / 2.0);
   }

   if (NSHeight(docRect) < NSHeight(clipRect)) {
      proposedScrollPoint.y = NSMaxY(docRect) - NSHeight(clipRect);
   }

   return proposedScrollPoint;
}
#endif
- (void)setFrame: (NSRect)frameRect // IN
{
   // This ends up calling setFrameOrigin: and setFrameSize:.
   [super setFrame:frameRect];

   [self positionDocument];
}
#endif
@end
