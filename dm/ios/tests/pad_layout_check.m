// The layout editor's model (DmPadLayout.m), run by test_pad_layout.py on macOS: the old offsets move into landscape once, the two orientation
// classes are separate, what is stored is a property list, malformed stored values and out-of-range sizes cannot get in, Reset Layout keeps
// the opacity, the picture stays on screen, and where a pinch goes
#import "DmPadLayout.h"
#include <math.h>
#include <stdio.h>

static int failed;
static void expect(BOOL c, const char *what) { printf("%s %s\n", c ? "PASS" : "FAIL", what); if (!c) failed++; }
static BOOL near(double a, double b) { return fabs(a - b) < 1e-9; }

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"nxnative.padlayout-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:suite];

        [d setObject:@{@"face": @[@10, @-5], @"stick": @[@"x", @1]} forKey:@"DmPadOffsets"];
        DmPadLayoutSet *p = [DmPadLayoutSet loadOrientation:@"portrait" from:d];
        DmPadLayoutSet *l = [DmPadLayoutSet loadOrientation:@"landscape" from:d];
        expect(CGPointEqualToPoint([l offsetFor:@"face"], CGPointMake(10, -5)) && CGPointEqualToPoint([l offsetFor:@"stick"], CGPointZero),
               "the old DmPadOffsets become landscape's offsets (a malformed pair is dropped)");
        expect(CGPointEqualToPoint([p offsetFor:@"face"], CGPointZero), "portrait does not get the old offsets");
        expect(![d objectForKey:@"DmPadOffsets"] && [d dictionaryForKey:@"DmControlLayout.landscape"], "the old key is gone and landscape is stored");

        [d setObject:@{@"face": @[@99, @99]} forKey:@"DmPadOffsets"];   // an old build ran again: landscape's own set wins
        l = [DmPadLayoutSet loadOrientation:@"landscape" from:d];
        expect(CGPointEqualToPoint([l offsetFor:@"face"], CGPointMake(10, -5)) && ![d objectForKey:@"DmPadOffsets"], "migration does not overwrite a stored landscape set");

        [p setOffset:CGPointMake(3, 4) forKey:@"dpad"]; [p setScale:1.75 forKey:@"face"]; p.controlsScale = 1.25;
        p.pictureOffset = CGPointMake(0, -40); p.pictureScale = 0.8; p.opacity = 0.5;
        [p saveTo:d];
        expect([NSPropertyListSerialization propertyList:[d objectForKey:@"DmControlLayout.portrait"] isValidForFormat:NSPropertyListBinaryFormat_v1_0],
               "the stored set is a property list");
        DmPadLayoutSet *p2 = [DmPadLayoutSet loadOrientation:@"portrait" from:d];
        expect(CGPointEqualToPoint([p2 offsetFor:@"dpad"], CGPointMake(3, 4)) && near([p2 scaleFor:@"face"], 1.75) && near([p2 scaleFor:@"stick"], 1)
               && near(p2.controlsScale, 1.25) && CGPointEqualToPoint(p2.pictureOffset, CGPointMake(0, -40)) && near(p2.pictureScale, 0.8) && near(p2.opacity, 0.5),
               "a saved set loads back the same");
        l = [DmPadLayoutSet loadOrientation:@"landscape" from:d];
        expect(near([l scaleFor:@"face"], 1) && near(l.controlsScale, 1) && near(l.pictureScale, 1) && near(l.opacity, 1) && CGPointEqualToPoint([l offsetFor:@"face"], CGPointMake(10, -5)),
               "saving portrait leaves landscape as it was");

        [p2 setScale:9 forKey:@"a"]; [p2 setScale:0.1 forKey:@"b"]; [p2 setScale:NAN forKey:@"c"];
        p2.controlsScale = 3; p2.pictureScale = 1.5; p2.opacity = 0;
        expect(near([p2 scaleFor:@"a"], 2.5) && near([p2 scaleFor:@"b"], 0.5) && near([p2 scaleFor:@"c"], 1) && near(p2.controlsScale, 2.5)
               && near(p2.pictureScale, 1) && near(p2.opacity, 0.1), "scales are clamped to 0.5…2.5, the picture's to 0.5…1, the opacity to 0.1…1");
        DmPadLayoutSet *bad = [[DmPadLayoutSet alloc] initWithOrientation:@"portrait" plist:@{@"offsets": @[@1], @"scales": @{@"face": @"big", @"stick": @7},
                                                                                              @"scale": @"x", @"picture": @[@1, @2], @"opacity": @2}];
        expect(near([bad scaleFor:@"face"], 1) && near([bad scaleFor:@"stick"], 2.5) && near(bad.controlsScale, 1) && CGPointEqualToPoint(bad.pictureOffset, CGPointZero)
               && near(bad.opacity, 1), "malformed stored values are skipped, out-of-range ones clamped");

        [p2 clearLayout];
        expect(CGPointEqualToPoint([p2 offsetFor:@"dpad"], CGPointZero) && near([p2 scaleFor:@"a"], 1) && near(p2.controlsScale, 1)
               && CGPointEqualToPoint(p2.pictureOffset, CGPointZero) && near(p2.pictureScale, 1) && near(p2.opacity, 0.1), "Reset Layout clears placement and sizes, keeps the opacity");

        CGRect home = CGRectMake(0, 40, 400, 225); CGSize b = CGSizeMake(400, 860);
        CGPoint o = dm_layout_picture_clamp(home, b, 1, CGPointMake(50, -100));
        expect(near(o.x, 0) && near(o.y, -40), "a full-size picture moves only vertically, and not past the top");
        o = dm_layout_picture_clamp(home, b, 0.5, CGPointMake(500, 2000));
        expect(near(o.x, 100) && near(o.y, 860 - 56.25 - 152.5), "a half-size picture stops at the right and bottom edges");
        o = dm_layout_picture_clamp(home, b, 0.5, CGPointMake(NAN, 10));
        expect(near(o.x, 0) && near(o.y, 10), "a non-finite offset is no offset; an in-bounds one is kept");

        NSString *k = nil;
        expect(dm_layout_pinch_target(@"l", @"r", @"face", NO, NO, NO, &k) == DmPinchControl && [k isEqual:@"face"], "the control under the midpoint wins");
        expect(dm_layout_pinch_target(@"face", @"face", nil, NO, NO, NO, &k) == DmPinchControl && [k isEqual:@"face"], "both fingers on one control");
        expect(dm_layout_pinch_target(nil, @"stick", nil, YES, NO, YES, &k) == DmPinchControl && [k isEqual:@"stick"], "one finger on a control, one beside it: that control");
        expect(dm_layout_pinch_target(@"stick", @"face", nil, NO, NO, NO, &k) == DmPinchAll, "two different controls: all of them");
        expect(dm_layout_pinch_target(nil, nil, nil, YES, NO, YES, &k) == DmPinchPicture, "midpoint on the picture: the picture");
        expect(dm_layout_pinch_target(nil, nil, nil, NO, NO, NO, &k) == DmPinchAll && !k, "empty pad space: all controls");
        expect([dm_layout_orientation(CGSizeMake(430, 932)) isEqual:@"portrait"] && [dm_layout_orientation(CGSizeMake(932, 430)) isEqual:@"landscape"], "orientation class by shape");

        [d removePersistentDomainForName:suite];
    }
    printf("pad layout: %d failed\n", failed);
    return failed != 0;
}
