// Frame-rate badge (front_ios.m's counter): a capsule over the game with a status dot (green at the game's target, yellow a little below it, red well below) and the frames per second.
// A solid translucent fill, no blur: a blur over the game picture is drawn again every frame the game presents, GPU time taken from the game the badge is there to watch.
// Hidden until shown; it takes no touches (they go on to the gamepad and the game)
#import <UIKit/UIKit.h>

@interface DmFpsBadge : UIView
@end
@implementation DmFpsBadge {
    UIView *_dot;
    UILabel *_value, *_unit;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO; self.hidden = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.62];
        self.layer.borderWidth = 0.5; self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
        _dot = [UIView new]; _dot.layer.cornerRadius = 3.5; _dot.backgroundColor = UIColor.systemGrayColor;
        _value = [UILabel new]; _value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold]; _value.textColor = UIColor.whiteColor; _value.text = @"--";
        _unit = [UILabel new]; _unit.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold]; _unit.textColor = [UIColor colorWithWhite:1 alpha:0.55]; _unit.text = @"FPS";
        for (UIView *v in @[_dot, _value, _unit]) [self addSubview:v];
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (CGSize)sizeThatFits:(CGSize)s {
    (void)s; CGFloat w = 10 + 7 + 6 + [_value sizeThatFits:CGSizeZero].width + 3 + [_unit sizeThatFits:CGSizeZero].width + 11;
    return CGSizeMake(ceil(fmax(w, 74)), 26);   // wide enough for three digits, so the badge does not change width as the reading does
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height; self.layer.cornerRadius = h / 2;
    _dot.frame = CGRectMake(10, (h - 7) / 2, 7, 7);
    CGSize v = [_value sizeThatFits:CGSizeZero], u = [_unit sizeThatFits:CGSizeZero];
    CGFloat x = CGRectGetMaxX(_dot.frame) + 6;
    _value.frame = CGRectMake(x, (h - v.height) / 2, v.width, v.height);
    _unit.frame = CGRectMake(CGRectGetMaxX(_value.frame) + 3, (h - v.height) / 2 + (v.height - u.height) - 1.5, u.width, u.height);   // on the value's baseline
}
- (void)setFps:(double)fps target:(double)target {
    if (fps < 0) { _value.text = @"--"; _dot.backgroundColor = UIColor.systemGrayColor; }
    else {
        _value.text = [NSString stringWithFormat:@"%.0f", fps];
        double r = target > 0 ? fps / target : 1;
        _dot.backgroundColor = r >= 0.95 ? UIColor.systemGreenColor : r >= 0.75 ? UIColor.systemYellowColor : UIColor.systemRedColor;
    }
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ FPS", _value.text];
    [self setNeedsLayout];
}
@end

UIView *dm_fps_badge(void) { return [DmFpsBadge new]; }
void dm_fps_badge_set(UIView *badge, double fps, double target) { [(DmFpsBadge *)badge setFps:fps target:target]; }
