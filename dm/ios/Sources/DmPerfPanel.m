// Performance overlay at the top left of the game: off, the frame-rate badge (DmFpsBadge.m) or the performance panel, one at a time (the panel has the frame rate too).
// The panel, in the app's language: frames per second with its last 20 seconds as a line, frame time, GPU time of the last finished frame (the front end's, -1 for none), the
// process's CPU time per second (100 % = one core), its memory footprint and the thermal state. Sampled twice a second on the main thread, nothing while the game is held
// (the in-game menu or the background: no frames); a solid translucent fill and no blur, which would be drawn again every frame the game presents.
// The front end (front_ios.m, the UI preview) gives the frame counter, the GPU reading, the game's target rate and whether the game is held; the overlay keeps the frame rate
// the menu shows (dm_perf_overlay_fps), whatever it displays. Neither part takes touches
#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <sys/resource.h>

UIView *dm_fps_badge(void);
void dm_fps_badge_set(UIView *badge, double fps, double target);

static NSString *L(NSString *k) { return NSLocalizedString(k, nil); }
static UIColor *status_color(double fps, double target) {   // the badge's dot colours
    double r = target > 0 ? fps / target : 1;
    return r >= 0.95 ? UIColor.systemGreenColor : r >= 0.75 ? UIColor.systemYellowColor : UIColor.systemRedColor;
}

// ---- The panel ----
enum { R_FRAME, R_GPU, R_CPU, R_MEM, R_THERMAL, R_N };
static const CGFloat k_w = 150, k_pad = 10, k_head = 26, k_row = 17;
enum { k_hist = 40 };   // samples in the line: 20 s

@interface DmPerfPanel : UIView
- (void)setFps:(double)fps target:(double)target history:(const double *)h count:(int)n gpu:(double)gpu cpu:(double)cpu mem:(uint64_t)mem thermal:(int)thermal;
@end
@implementation DmPerfPanel {
    UIView *_dot; UILabel *_fps, *_unit; CAShapeLayer *_line;
    UILabel *_key[R_N], *_val[R_N];
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.66];
        self.layer.cornerRadius = 12; self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 0.5; self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
        _dot = [UIView new]; _dot.layer.cornerRadius = 3.5; _dot.backgroundColor = UIColor.systemGrayColor;
        _fps = [UILabel new]; _fps.font = [UIFont monospacedDigitSystemFontOfSize:19 weight:UIFontWeightSemibold]; _fps.textColor = UIColor.whiteColor; _fps.text = @"--";
        _unit = [UILabel new]; _unit.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]; _unit.textColor = [UIColor colorWithWhite:1 alpha:0.55]; _unit.text = L(@"frames/s");
        _line = [CAShapeLayer layer]; _line.fillColor = nil; _line.lineWidth = 1.5; _line.lineJoin = kCALineJoinRound; _line.lineCap = kCALineCapRound;
        _line.strokeColor = UIColor.systemGreenColor.CGColor;
        for (UIView *v in @[_dot, _fps, _unit]) [self addSubview:v];
        [self.layer addSublayer:_line];
        NSString *const keys[R_N] = {L(@"Frame time"), L(@"GPU time"), L(@"CPU usage"), L(@"Memory"), L(@"Thermal")};
        for (int i = 0; i < R_N; i++) {
            _key[i] = [UILabel new]; _key[i].font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular]; _key[i].textColor = [UIColor colorWithWhite:1 alpha:0.55]; _key[i].text = keys[i];
            _val[i] = [UILabel new]; _val[i].font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightSemibold]; _val[i].textColor = [UIColor colorWithWhite:1 alpha:0.92];
            _val[i].textAlignment = NSTextAlignmentRight; _val[i].text = @"—";
            [self addSubview:_key[i]]; [self addSubview:_val[i]];
        }
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (CGSize)sizeThatFits:(CGSize)s { (void)s; return CGSizeMake(k_w, k_pad + k_head + (CGFloat)R_N * k_row + k_pad); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, y = k_pad;
    CGSize f = [_fps sizeThatFits:CGSizeZero], u = [_unit sizeThatFits:CGSizeZero];
    _dot.frame = CGRectMake(k_pad, y + (k_head - 7) / 2, 7, 7);
    _fps.frame = CGRectMake(k_pad + 12, y + (k_head - f.height) / 2, f.width, f.height);
    _unit.frame = CGRectMake(CGRectGetMaxX(_fps.frame) + 3, CGRectGetMaxY(_fps.frame) - u.height - 3, u.width, u.height);   // on the number's baseline
    _line.frame = CGRectMake(w - k_pad - 52, y + 4, 52, k_head - 8);
    y += k_head + 4;
    for (int i = 0; i < R_N; i++, y += k_row) {
        _key[i].frame = CGRectMake(k_pad, y, 52, k_row);
        _val[i].frame = CGRectMake(k_pad + 50, y, w - 2 * k_pad - 50, k_row);
    }
}
- (void)setFps:(double)fps target:(double)target history:(const double *)h count:(int)n gpu:(double)gpu cpu:(double)cpu mem:(uint64_t)mem thermal:(int)thermal {
    UIColor *c = fps < 0 ? UIColor.systemGrayColor : status_color(fps, target);
    _fps.text = fps < 0 ? @"--" : [NSString stringWithFormat:@"%.0f", fps]; _dot.backgroundColor = c;
    _val[R_FRAME].text = fps > 0 ? [NSString stringWithFormat:@"%.1f ms", 1000 / fps] : @"—";
    _val[R_GPU].text = gpu >= 0 ? [NSString stringWithFormat:@"%.1f ms", gpu] : @"—";
    _val[R_CPU].text = cpu >= 0 ? [NSString stringWithFormat:@"%.0f%%", cpu] : @"—";
    _val[R_MEM].text = mem ? (mem >= 1ull << 30 ? [NSString stringWithFormat:@"%.2f GB", mem / 1073741824.0] : [NSString stringWithFormat:@"%.0f MB", mem / 1048576.0]) : @"—";
    static NSString *const th[] = {@"Normal", @"Fair", @"Serious", @"Critical"};
    int t = thermal < 0 ? 0 : thermal > 3 ? 3 : thermal;
    _val[R_THERMAL].text = L(th[t]);
    _val[R_THERMAL].textColor = t == 0 ? [UIColor colorWithWhite:1 alpha:0.92] : t == 1 ? UIColor.systemYellowColor : t == 2 ? UIColor.systemOrangeColor : UIColor.systemRedColor;
    // the line: the frame rate over the last samples, 0 at the bottom, the target (or the highest reading) at the top
    CGSize b = _line.bounds.size; double top = target > 0 ? target : 60;
    for (int i = 0; i < n; i++) if (h[i] > top) top = h[i];
    UIBezierPath *p = [UIBezierPath bezierPath];
    for (int i = 0; i < n; i++) {
        CGPoint q = CGPointMake(b.width * (k_hist - n + i) / (k_hist - 1), b.height * (1 - fmax(h[i], 0) / top));
        if (i) [p addLineToPoint:q]; else [p moveToPoint:q];
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _line.path = n > 1 ? p.CGPath : nil; _line.strokeColor = c.CGColor;
    [CATransaction commit];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ %@, %@ %@, GPU %@, CPU %@, %@ %@, %@ %@", _fps.text, _unit.text, _key[R_FRAME].text, _val[R_FRAME].text,
                               _val[R_GPU].text, _val[R_CPU].text, _key[R_MEM].text, _val[R_MEM].text, _key[R_THERMAL].text, _val[R_THERMAL].text];
    [self setNeedsLayout];
}
@end

// ---- The overlay: one of the two, and the sampling ----
typedef struct { uint64_t (*frames)(void); double (*gpu_ms)(void); double (*target)(void); bool (*held)(void); } dm_perf_source;

@interface DmPerfOverlay : UIView
@property (nonatomic) int mode;   // 0 off, 1 frame rate, 2 panel
@property (nonatomic, readonly) double fps;
@end
@implementation DmPerfOverlay {
    dm_perf_source _src;
    UIView *_badge; DmPerfPanel *_panel;
    double _t[3]; uint64_t _n[3]; int _have;   // the last samples: frames over about a second
    double _cpu0, _ct0;
    double _hist[k_hist]; int _hn;
}
- (instancetype)initWithSource:(dm_perf_source)src {
    if ((self = [super initWithFrame:CGRectZero])) {
        _src = src; _fps = -1; _cpu0 = -1;
        self.userInteractionEnabled = NO; self.hidden = YES;
        _badge = dm_fps_badge(); _badge.hidden = NO; _panel = [DmPerfPanel new];
        [self addSubview:_badge]; [self addSubview:_panel];
        __weak DmPerfOverlay *me = self;
        NSTimer *t = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *x) { if (me) [me sample]; else [x invalidate]; }];
        [NSRunLoop.mainRunLoop addTimer:t forMode:NSRunLoopCommonModes];
        [self setMode:0];
    }
    return self;
}
- (void)setMode:(int)mode {
    _mode = mode < 0 || mode > 2 ? 0 : mode;
    self.hidden = _mode == 0; _badge.hidden = _mode != 1; _panel.hidden = _mode != 2;
    [self show];
    [self.superview setNeedsLayout];
}
- (UIView *)current { return _mode == 2 ? _panel : _badge; }
- (CGSize)sizeThatFits:(CGSize)s { return [self.current sizeThatFits:s]; }
- (void)layoutSubviews { [super layoutSubviews]; CGRect b = self.bounds; _badge.frame = b; _panel.frame = b; }
static double cpu_seconds(void) { struct rusage r; getrusage(RUSAGE_SELF, &r); return r.ru_utime.tv_sec + r.ru_stime.tv_sec + (r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6; }
static uint64_t footprint(void) {
    task_vm_info_data_t vi; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n) == KERN_SUCCESS ? vi.phys_footprint : 0;
}
- (void)sample {
    double now = CACurrentMediaTime(); uint64_t n = _src.frames();
    if (_src.held && _src.held()) { _have = 0; _cpu0 = -1; return; }   // a held game presents nothing: keep the last readings
    if (_have && now - _t[_have - 1] > 1.5) { _have = 0; _cpu0 = -1; }   // back from the background
    if (_have == 3) { memmove(_t, _t + 1, 2 * sizeof *_t); memmove(_n, _n + 1, 2 * sizeof *_n); _have = 2; }
    _t[_have] = now; _n[_have] = n; _have++;
    if (_have >= 2) {
        _fps = (_n[_have - 1] - _n[0]) / (_t[_have - 1] - _t[0]);
        if (_hn == k_hist) { memmove(_hist, _hist + 1, (k_hist - 1) * sizeof *_hist); _hn--; }
        _hist[_hn++] = _fps;
    }
    double c = cpu_seconds(), cpu = _cpu0 >= 0 && now > _ct0 ? (c - _cpu0) / (now - _ct0) * 100 : -1;
    _cpu0 = c; _ct0 = now;
    if (_mode == 2) {
        [_panel setFps:_fps target:self.target history:_hist count:_hn gpu:_src.gpu_ms ? _src.gpu_ms() : -1 cpu:cpu mem:footprint()
               thermal:(int)NSProcessInfo.processInfo.thermalState];
    } else if (_mode == 1) dm_fps_badge_set(_badge, _fps, self.target);
}
- (double)target { double t = _src.target ? _src.target() : 0; return t > 0 ? t : 60; }
- (void)show {   // a fresh reading at once on a change of mode (the last sample's)
    if (_mode == 1) dm_fps_badge_set(_badge, _fps, self.target);
    if (_mode == 2) [_panel setFps:_fps target:self.target history:_hist count:_hn gpu:_src.gpu_ms ? _src.gpu_ms() : -1 cpu:-1 mem:footprint()
                           thermal:(int)NSProcessInfo.processInfo.thermalState];
}
@end

UIView *dm_perf_overlay(uint64_t (*frames)(void), double (*gpu_ms)(void), double (*target)(void), bool (*held)(void)) {
    return [[DmPerfOverlay alloc] initWithSource:(dm_perf_source){frames, gpu_ms, target, held}];
}
void dm_perf_overlay_set_mode(UIView *v, int mode) { ((DmPerfOverlay *)v).mode = mode; }
int dm_perf_overlay_mode(UIView *v) { return ((DmPerfOverlay *)v).mode; }
double dm_perf_overlay_fps(UIView *v) { return v ? ((DmPerfOverlay *)v).fps : -1; }
