// The on-screen layout the editor changes (DmGamepad.m edit mode), one set per orientation class, and the rules it follows: the clamps, where a
// pinch goes, how far the picture may move. Foundation and CoreGraphics only, so dm/ios/tests/test_pad_layout.py runs it on the Mac.
//
// Stored in NSUserDefaults under DmControlLayout.portrait and DmControlLayout.landscape (dm_layout_orientation: taller than wide = portrait; not the
// old DmPadLayout key, the pad layout choice main.m migrates into launcher.DM_PAD_LAYOUT), each a
// property list — defaults hold nothing else, an NSValue threw on save and killed the app once (duo/design/dualscreen.md §0.9a):
//   offsets: { control key: [x, y] }   points, the drag from the control's home
//   scales:  { control key: s }        that control's size, 0.5…2.5
//   scale:   s                         every control (a factor on the layout unit), 0.5…2.5
//   picture: [dx, dy, s]               the game picture: points from its home rect, its size 0.5…1 of it
//   opacity: o                         the controls' opacity, 0.1…1
// The DmPadOffsets map older builds wrote (offsets only, no orientation) becomes the landscape set's offsets the first time either set loads.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

double dm_layout_control_scale(double s);   // a control's or all controls' scale: 0.5…2.5, not finite = 1
double dm_layout_picture_scale(double s);   // the picture's: 0.5…1 of its home size (never larger, so it never leaves the screen); not finite = 1
double dm_layout_opacity(double o);         // 0.1…1, not finite = 1
// The picture offset kept on screen: home = the picture's rect without placement, scaled by s about its centre and moved by off, stays inside
// a bounds-sized rect at the origin (a rect larger than bounds is centred)
CGPoint dm_layout_picture_clamp(CGRect home, CGSize bounds, double s, CGPoint off);
NSString *dm_layout_orientation(CGSize bounds);   // @"portrait" (taller than wide) or @"landscape"

// Which element a two-finger pinch resizes, from the control under each finger and under their midpoint (nil = none; grab radii, so "around"
// counts) and whether those points are on the picture: the control under the midpoint; else the one both fingers are on; else the only one a
// finger is on; two fingers on two different controls = all controls; no control: the picture when the midpoint or both fingers are on it,
// else all controls (empty pad space)
typedef NS_ENUM(int, DmPinch) { DmPinchControl, DmPinchAll, DmPinchPicture };
DmPinch dm_layout_pinch_target(NSString *_Nullable k1, NSString *_Nullable k2, NSString *_Nullable kMid, BOOL pic1, BOOL pic2, BOOL picMid,
                               NSString *_Nullable *_Nullable key);

@interface DmPadLayoutSet : NSObject
@property (nonatomic, readonly, copy) NSString *orientation;
@property (nonatomic) double controlsScale;   // setters clamp
@property (nonatomic) double pictureScale;
@property (nonatomic) double opacity;
@property (nonatomic) CGPoint pictureOffset;
+ (NSString *)defaultsKey:(NSString *)orientation;   // DmControlLayout.<orientation>
- (instancetype)initWithOrientation:(NSString *)orientation plist:(nullable id)plist;   // anything malformed in plist is skipped
+ (instancetype)loadOrientation:(NSString *)orientation from:(NSUserDefaults *)d;   // migrates DmPadOffsets first (once)
- (void)saveTo:(NSUserDefaults *)d;
- (NSDictionary *)plist;
- (CGPoint)offsetFor:(NSString *)key;
- (void)setOffset:(CGPoint)p forKey:(NSString *)key;
- (double)scaleFor:(NSString *)key;
- (void)setScale:(double)s forKey:(NSString *)key;
- (void)clearLayout;   // Reset Layout: offsets, scales, all-controls scale, picture placement; the opacity stays (its own slider)
@end

NS_ASSUME_NONNULL_END
