// The editor's layout sets and rules (DmPadLayout.h)
#import "DmPadLayout.h"
#include <math.h>

static double clampd(double v, double lo, double hi, double bad) { return isfinite(v) ? fmin(fmax(v, lo), hi) : bad; }
double dm_layout_control_scale(double s) { return clampd(s, 0.5, 2.5, 1); }
double dm_layout_picture_scale(double s) { return clampd(s, 0.5, 1, 1); }
double dm_layout_opacity(double o) { return clampd(o, 0.1, 1, 1); }

static double keep_in(double c, double half, double extent) { return 2 * half >= extent ? extent / 2 : fmin(fmax(c, half), extent - half); }
CGPoint dm_layout_picture_clamp(CGRect home, CGSize bounds, double s, CGPoint off) {
    s = dm_layout_picture_scale(s);
    double cx = CGRectGetMidX(home), cy = CGRectGetMidY(home);
    double x = isfinite(off.x) ? cx + off.x : cx, y = isfinite(off.y) ? cy + off.y : cy;
    x = keep_in(x, home.size.width * s / 2, bounds.width);
    y = keep_in(y, home.size.height * s / 2, bounds.height);
    return CGPointMake(x - cx, y - cy);
}
NSString *dm_layout_orientation(CGSize b) { return b.height > b.width ? @"portrait" : @"landscape"; }

DmPinch dm_layout_pinch_target(NSString *k1, NSString *k2, NSString *kMid, BOOL pic1, BOOL pic2, BOOL picMid, NSString **key) {
    NSString *k = kMid ?: (k1 && k2 ? ([k1 isEqualToString:k2] ? k1 : nil) : (k1 ?: k2));
    if (key) *key = k;
    if (k) return DmPinchControl;
    if (k1 && k2) return DmPinchAll;   // two different controls
    return picMid || (pic1 && pic2) ? DmPinchPicture : DmPinchAll;
}

static NSString *const k_old_offsets = @"DmPadOffsets";   // older builds: control key -> [x, y], one map for every orientation
static BOOL num(id v) { return [v isKindOfClass:NSNumber.class] && isfinite([v doubleValue]); }
static BOOL pair(id v, NSUInteger n) {
    if (![v isKindOfClass:NSArray.class] || [v count] != n) return NO;
    for (id x in v) if (!num(x)) return NO;
    return YES;
}

@implementation DmPadLayoutSet {
    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *_offsets;   // plist values only, so a save can never throw
    NSMutableDictionary<NSString *, NSNumber *> *_scales;
}
+ (NSString *)defaultsKey:(NSString *)o { return [@"DmControlLayout." stringByAppendingString:o]; }
- (instancetype)initWithOrientation:(NSString *)o plist:(id)p {
    if ((self = [super init])) {
        _orientation = [o copy];
        _offsets = [NSMutableDictionary dictionary]; _scales = [NSMutableDictionary dictionary];
        _controlsScale = _pictureScale = _opacity = 1;
        NSDictionary *d = [p isKindOfClass:NSDictionary.class] ? p : nil;
        NSDictionary *offs = [d[@"offsets"] isKindOfClass:NSDictionary.class] ? d[@"offsets"] : nil;
        for (id k in offs) if ([k isKindOfClass:NSString.class] && pair(offs[k], 2)) _offsets[k] = offs[k];
        NSDictionary *sc = [d[@"scales"] isKindOfClass:NSDictionary.class] ? d[@"scales"] : nil;
        for (id k in sc) if ([k isKindOfClass:NSString.class] && num(sc[k])) [self setScale:[sc[k] doubleValue] forKey:k];
        if (num(d[@"scale"])) self.controlsScale = [d[@"scale"] doubleValue];
        if (num(d[@"opacity"])) self.opacity = [d[@"opacity"] doubleValue];
        if (pair(d[@"picture"], 3)) {
            NSArray *pic = d[@"picture"];
            _pictureOffset = CGPointMake([pic[0] doubleValue], [pic[1] doubleValue]);
            self.pictureScale = [pic[2] doubleValue];
        }
    }
    return self;
}
+ (instancetype)loadOrientation:(NSString *)o from:(NSUserDefaults *)d {
    NSDictionary *old = [d dictionaryForKey:k_old_offsets];
    if (old) {   // once: the old map is landscape's offsets (it was made for, and mostly in, the whole-screen layout), unless landscape has its own already
        NSString *lk = [self defaultsKey:@"landscape"];
        if (![d objectForKey:lk]) [[[DmPadLayoutSet alloc] initWithOrientation:@"landscape" plist:@{@"offsets": old}] saveTo:d];
        [d removeObjectForKey:k_old_offsets];
    }
    return [[DmPadLayoutSet alloc] initWithOrientation:o plist:[d objectForKey:[self defaultsKey:o]]];
}
- (NSDictionary *)plist {
    return @{@"offsets": [_offsets copy], @"scales": [_scales copy], @"scale": @(_controlsScale), @"opacity": @(_opacity),
             @"picture": @[@(_pictureOffset.x), @(_pictureOffset.y), @(_pictureScale)]};
}
- (void)saveTo:(NSUserDefaults *)d { [d setObject:[self plist] forKey:[DmPadLayoutSet defaultsKey:_orientation]]; }
- (void)setControlsScale:(double)s { _controlsScale = dm_layout_control_scale(s); }
- (void)setPictureScale:(double)s { _pictureScale = dm_layout_picture_scale(s); }
- (void)setOpacity:(double)o { _opacity = dm_layout_opacity(o); }
- (void)setPictureOffset:(CGPoint)p { _pictureOffset = CGPointMake(isfinite(p.x) ? p.x : 0, isfinite(p.y) ? p.y : 0); }
- (CGPoint)offsetFor:(NSString *)k { NSArray<NSNumber *> *xy = _offsets[k]; return xy ? CGPointMake(xy[0].doubleValue, xy[1].doubleValue) : CGPointZero; }
- (void)setOffset:(CGPoint)p forKey:(NSString *)k { if (isfinite(p.x) && isfinite(p.y)) _offsets[k] = @[@(p.x), @(p.y)]; }
- (double)scaleFor:(NSString *)k { NSNumber *s = _scales[k]; return s ? s.doubleValue : 1; }
- (void)setScale:(double)s forKey:(NSString *)k { _scales[k] = @(dm_layout_control_scale(s)); }
- (void)clearLayout {
    [_offsets removeAllObjects]; [_scales removeAllObjects];
    _controlsScale = _pictureScale = 1; _pictureOffset = CGPointZero;
}
@end
