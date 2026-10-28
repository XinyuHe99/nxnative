// iOS front end (the iOS implementation of front.h): a centered 16:9 Metal view (black bars on both sides, or its edges extended into them in Ambient mode) + a full-screen virtual gamepad layer (DmGamepad.m, controls drawn over the picture)
// + the in-game menu over both (GameMenu.swift: a swipe in from the left edge; it holds the game while open, front_menu_hold).
// The host runs on the big-stack thread started by main.m; front_run runs the guest directly on the calling thread.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <AVFAudio/AVFAudio.h>
#include <errno.h>
#include "front.h"
#include "hle.h"
#include "dm.h"
#include "haptics_apple.h"

UIView *dm_gamepad_view(CGRect frame);
void dm_gamepad_reset(void);
void front_ios_boot(void);
int front_ios_boot_ok(void);
const char *front_ios_boot_message(void);   // main.m: why a build that keeps the game files off the IPA found none usable (NULL = the generic hint)
bool dm_show_launcher(void *view_controller, void (*done)(void));   // Launcher.swift: false = no launcher (no dm/launcher.json, or DM_LAUNCHER=0)
void dm_menu_install(void *view_controller);   // GameMenu.swift: the edge swipe and the menu over the root view

static CAMetalLayer *g_layer;
static void front_ios_power_watch(void);
static void front_ios_audio_watch(void);
static UIView *front_ios_perf_overlay(void);

@interface DmGameView : UIView
@end
@implementation DmGameView
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        CAMetalLayer *l = (CAMetalLayer *)self.layer;
        l.device = MTLCreateSystemDefaultDevice(); l.pixelFormat = MTLPixelFormatBGRA8Unorm;
        l.contentsScale = UIScreen.mainScreen.nativeScale; l.framebufferOnly = NO; l.opaque = YES;
        self.backgroundColor = UIColor.blackColor;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    l.drawableSize = CGSizeMake(self.bounds.size.width * l.contentsScale, self.bounds.size.height * l.contentsScale);
}
@end

@interface DmRootVC : UIViewController
@property (nonatomic, strong) DmGameView *game;
@property (nonatomic, strong) UIBackgroundExtensionView *ambient;   // Ambient mode: holds the game view (below); nil while it is off
@property (nonatomic, strong) UIView *pad;
@property (nonatomic, strong) UIView *fps;
@property (nonatomic) BOOL launched;
- (void)startGame;
- (void)setAmbientOn:(BOOL)on;
@end
static DmRootVC *g_root;
static void launcher_done(void) { [g_root startGame]; }
@implementation DmRootVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    front_ios_power_watch();
    if (!front_ios_boot_ok()) {   // No game files: show a hint and do not start the host
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 40, 40)];
        lb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        lb.numberOfLines = 0; lb.textAlignment = NSTextAlignmentCenter; lb.textColor = UIColor.whiteColor;
        const char *why = front_ios_boot_message();
        lb.text = why ? [NSString stringWithFormat:@"%@\n%s", NSLocalizedString(@"Game files unusable.", nil), why] : NSLocalizedString(@"Game files not found.\nPut the RomFS folder into this App's Documents as \"romfs\" (Files app), then restart.", nil);
        [self.view addSubview:lb]; return;
    }
    front_ios_audio_watch();
}
// The game view, the pad and the performance overlay are made once the launcher has set the switches they read (DM_PERF_OVERLAY, DM_METAL_HUD); the host's loading began at app launch (main.m)
- (void)startGame {
    if (self.game) return;
    front_hud_env();   // before the game view makes its device (an env file's DM_METAL_HUD sets it in main.m already)
    self.game = [[DmGameView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.game];
    g_layer = (CAMetalLayer *)self.game.layer;
    if (getenv("DM_METAL_HUD") && atoi(getenv("DM_METAL_HUD"))) { g_layer.developerHUDProperties = @{@"mode": @"default"}; LOG("front end: Metal performance HUD on (DM_METAL_HUD)"); }   // Apple's HUD over the game (a diagnostic switch for env files)
    if (getenv("DM_AMBIENT") && atoi(getenv("DM_AMBIENT"))) [self setAmbientOn:YES];
    dm_haptics_apple_init();
    self.pad = dm_gamepad_view(self.view.bounds);
    self.pad.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pad];
    self.fps = front_ios_perf_overlay();   // above the pad, which hides while a controller is connected
    [self.view addSubview:self.fps];
    dm_menu_install((__bridge void *)self);   // over everything
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    front_ios_boot();
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds; if (!self.game) return;
    CGFloat w = b.size.width, h = b.size.height;   // Fit 16:9 into the whole screen
    if (w / h > 16.0 / 9.0) w = h * 16.0 / 9.0; else h = w * 9.0 / 16.0;
    self.game.frame = CGRectMake(floor((b.size.width - w) / 2), floor((b.size.height - h) / 2), w, h);   // the extension view fills the root view, so the frame is the same in it
    {   // the performance overlay: the top row's free stretch (the panel reaches down from there): right of DmGamepad.m's L3 key (102 + 17 of its units from the safe edge), level with − / + (22 units down); u is its unit
        CGRect s = UIEdgeInsetsInsetRect(b, self.view.safeAreaInsets); CGFloat u = MIN(b.size.height / 430.0, 1.3);
        CGSize fs = [self.fps sizeThatFits:CGSizeZero];
        self.fps.frame = CGRectMake(floor(CGRectGetMinX(s) + 130 * u), floor(CGRectGetMinY(s) + fmax(8 * u, 22 * u - fs.height / 2)), fs.width, fs.height);
    }
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    if (!front_ios_boot_ok() && front_ios_boot_message() && !self.presentedViewController) {   // a slim build whose game file image is missing or another version (main.m)
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Game files" message:@(front_ios_boot_message()) preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
    if (self.launched || !front_ios_boot_ok()) return;
    self.launched = YES; g_root = self;
    if (!dm_show_launcher((__bridge void *)self, launcher_done)) [self startGame];   // the settings screen first (Launcher.swift), when the app has one
}
// Ambient mode (DM_AMBIENT, off by default; the launcher and the in-game menu switch it): the bars beside the 16:9 picture show its edges mirrored and blurred, UIKit's background
// extension effect (UIBackgroundExtensionView, iOS 26: Apple's way of carrying content on under a sidebar or past the safe area). The game view moves into an extension view that
// fills the root view and keeps its own frame (automaticallyPlacesContentView off); while off, it sits in the root view as before, with no effect to composite
- (void)setAmbientOn:(BOOL)on {
    if (!self.game || on == (self.ambient != nil)) return;
    if (on) {
        UIBackgroundExtensionView *x = [[UIBackgroundExtensionView alloc] initWithFrame:self.view.bounds];
        x.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        x.automaticallyPlacesContentView = NO; x.backgroundColor = UIColor.blackColor;
        [self.view insertSubview:x belowSubview:self.game];   // the game's place under the pad and the menu
        x.contentView = self.game;
        self.ambient = x;
        self.game.frame = CGRectZero;   // the frame is set again below: the extension view lays out its edges only when its content changes size
    } else {
        self.ambient.contentView = nil;
        [self.view insertSubview:self.game aboveSubview:self.ambient];
        [self.ambient removeFromSuperview]; self.ambient = nil;
    }
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    LOG("front end: ambient mode %s", on ? "on" : "off");
}
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }   // Edge gestures need two swipes, to avoid accidental exits
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end
UIViewController *front_ios_root(void) { return [DmRootVC new]; }

// Thermal state and screen brightness for the power and present rows every 300 frames (hle_nvn.c; its weak defaults return -1 on the Mac). thermalState: 0 nominal, 1 fair, 2 serious, 3 critical.
// Brightness is read on the main thread at start and on each change; every change of the thermal state and of Low Power Mode (which lowers the CPU clock) is logged with the time since launch
static _Atomic double g_brightness = -1;
int dm_thermal_now(void) { return (int)NSProcessInfo.processInfo.thermalState; }
int dm_low_power_now(void) { return NSProcessInfo.processInfo.lowPowerModeEnabled; }   // the frame step does not probe in it (hle_nvn.c fstep_cpu_slowed)
double dm_brightness_now(void) { return g_brightness; }
static void front_ios_power_watch(void) {
    g_brightness = UIScreen.mainScreen.brightness;
    [NSNotificationCenter.defaultCenter addObserverForName:UIScreenBrightnessDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n; g_brightness = UIScreen.mainScreen.brightness; }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        (void)n; LOG("front end: thermal state → %d (%.0f s after launch)", dm_thermal_now(), (now_ns() - g_t0_ns) / 1e9); }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        (void)n; LOG("front end: Low Power Mode → %s (%.0f s after launch)", dm_low_power_now() ? "on" : "off", (now_ns() - g_t0_ns) / 1e9); }];
    LOG("front end: thermal state %d, brightness %.2f, Low Power Mode %s", dm_thermal_now(), g_brightness, dm_low_power_now() ? "on" : "off");
}

// Performance overlay (DmPerfPanel.m): off, the frame-rate badge or the performance panel. Frames are those put on screen (nvn_mtl.m counts them for NVN and for the Vulkan
// layer alike; frames the display link merged away are not counted), the target is the frame step's (60 without one), GPU time is that of the last frame the GPU finished
// (hle_nvn.c's frame count, nvn_mtl.m's timing; none for a game whose GPU work is not timed). The mode: DM_PERF_OVERLAY=0 / 1 / 2 (the launcher's Performance overlay,
// or Documents/env.txt), else the frame-rate badge when the IPA was built with it (the NSP script's SHOW_FPS → DMShowFPS in Info.plist; DM_SHOW_FPS=0 / 1 in env.txt overrides
// that). The in-game menu changes it and shows the frame rate it keeps
uint64_t mtl_present_count(void);
uint64_t dm_nvn_frame_count(void);
double mtl_gpu_ms(uint64_t f);
UIView *dm_perf_overlay(uint64_t (*frames)(void), double (*gpu_ms)(void), double (*target)(void), bool (*held)(void));
void dm_perf_overlay_set_mode(UIView *v, int mode);
int dm_perf_overlay_mode(UIView *v);
double dm_perf_overlay_fps(UIView *v);
static int g_menu_hold;
static bool front_ios_held(void);   // the menu or the background holds the game (below)
static double front_ios_gpu_ms(void) {   // the last frame whose GPU work is done, up to 8 back (as hle_nvn.c's timing line)
    uint64_t n = dm_nvn_frame_count();
    for (uint64_t f = n; f-- > 0 && n - f <= 8;) { double g = mtl_gpu_ms(f); if (g >= 0) return g; }
    return -1;
}
static double front_ios_target_fps(void) { return dm_fps_state ? *(float *)dm_fps_state : 0; }
static UIView *front_ios_perf_overlay(void) {
    UIView *v = dm_perf_overlay(mtl_present_count, front_ios_gpu_ms, front_ios_target_fps, front_ios_held);
    const char *m = getenv("DM_PERF_OVERLAY"), *e = getenv("DM_SHOW_FPS");
    int mode = m ? atoi(m) : (e ? atoi(e) != 0 : [[NSBundle.mainBundle objectForInfoDictionaryKey:@"DMShowFPS"] boolValue]);
    dm_perf_overlay_set_mode(v, mode);
    if (mode) LOG("front end: performance overlay %s", mode == 2 ? "panel" : "frame rate");
    return v;
}
int front_menu_perf_mode(void) { return g_root.fps ? dm_perf_overlay_mode(g_root.fps) : 0; }
void front_menu_set_perf_mode(int mode) {
    dm_perf_overlay_set_mode(g_root.fps, mode); [g_root.view setNeedsLayout];
    LOG("front end: performance overlay %s from the menu", mode == 2 ? "panel" : mode == 1 ? "frame rate" : "off");
}
double front_menu_fps(void) { return dm_perf_overlay_fps(g_root.fps); }
bool front_menu_ambient(void) { return g_root.ambient != nil; }
void front_menu_set_ambient(bool on) { [g_root setAmbientOn:on]; }

// Progress screen of the prepare step (front.h front_progress): a dark view over the game's view and the pad, the title, a bar and a count, centered; UIKit views, so it draws while the game's thread waits
static UIView *g_prog; static UILabel *g_prog_count; static UIProgressView *g_prog_bar; static UILabel *g_prog_title;
void front_progress(const char *title, long done, long total) {
    if (!g_layer) return;
    NSString *tt = title ? @(title) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!tt) { [g_prog removeFromSuperview]; g_prog = nil; return; }
        if (!g_prog) {
            UIView *root = g_root.view; if (!root) return;
            g_prog = [[UIView alloc] initWithFrame:root.bounds]; g_prog.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            g_prog.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
            UIView *box = [[UIView alloc] initWithFrame:CGRectMake(floor((root.bounds.size.width - 320) / 2), floor((root.bounds.size.height - 96) / 2), 320, 96)];
            box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            g_prog_title = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, 320, 30)]; g_prog_title.textAlignment = NSTextAlignmentCenter; g_prog_title.textColor = UIColor.whiteColor;
            g_prog_title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
            g_prog_bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; g_prog_bar.frame = CGRectMake(20, 48, 280, 4);
            g_prog_count = [[UILabel alloc] initWithFrame:CGRectMake(0, 64, 320, 22)]; g_prog_count.textAlignment = NSTextAlignmentCenter;
            g_prog_count.textColor = [UIColor colorWithWhite:0.72 alpha:1]; g_prog_count.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
            [box addSubview:g_prog_title]; [box addSubview:g_prog_bar]; [box addSubview:g_prog_count]; [g_prog addSubview:box];
            [root addSubview:g_prog];
        }
        g_prog_title.text = NSLocalizedString(tt, nil); g_prog_bar.progress = total > 0 ? (float)done / (float)total : 0;   // the host's English titles, translated in Sources/<language>.lproj
        g_prog_count.text = [NSString stringWithFormat:NSLocalizedString(@"%@ of %@", nil), [NSNumberFormatter localizedStringFromNumber:@(done) numberStyle:NSNumberFormatterDecimalStyle],
                             [NSNumberFormatter localizedStringFromNumber:@(total) numberStyle:NSNumberFormatterDecimalStyle]];
    });
}
void *front_metal_layer(void) { return (__bridge void *)g_layer; }
void front_run(void (*guest)(void)) { guest(); }   // Already on main.m's big-stack thread

// Software keyboard: show a UIAlertController on the main thread, the calling thread waits for the result
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap) {
    (void)max_chars;
    if (!g_layer) return -1;
    __block int r = 0; __block NSString *text = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSString *t = title && *title ? @(title) : @"", *m = [NSString stringWithFormat:@"%s%s%s", sub ? sub : "", sub && *sub && guide && *guide ? "\n" : "", guide ? guide : ""];
    NSString *init = initial ? @(initial) : @"", *ph = guide ? @(guide) : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
        [ac addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = init; f.placeholder = ph; }];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { (void)x; r = 1; text = ac.textFields.firstObject.text; dispatch_semaphore_signal(done); }]];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { (void)x; dispatch_semaphore_signal(done); }]];
        UIViewController *vc = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) vc = w.rootViewController;
        if (!vc) { dispatch_semaphore_signal(done); return; }
        [vc presentViewController:ac animated:YES completion:nil];
    });
    // The guest clock keeps running meanwhile, as on the Switch (hle_swkbd.c): a freeze here as well stopped Octopath Traveler 0's frame loop for as long as the box was up and made its sound stutter
    // (4,977 ms and 2,577 ms frames, 5,181 wakeups a second). The inline keyboard freezes around its own call (hle_swkbd.c)
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (!r) return 0;
    snprintf(out, out_cap, "%s", text.UTF8String ? text.UTF8String : "");
    return 1;
}

// Save write failed (most likely the phone's storage is full): show a notice on the main thread without blocking the game. hle_fs.c calls this when a save transaction is refused or a mount has to fall back to read-only;
// the iOS front end used not to implement it, so there was only a log line and the player never learned that progress was not being saved
void front_save_failed(int err) {
    LOG("front end: save data write failed errno=%d, telling the player", err);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) vc = w.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if (!vc) { LOG("[RED] front end: no window for the save-failure alert errno=%d", err); return; }
        NSString *m = err == ENOSPC ? NSLocalizedString(@"Storage is full, so progress was not saved. Free up space and save again.", nil)
                                    : [NSString stringWithFormat:NSLocalizedString(@"Saving failed (errno %d); progress was not saved.", nil), err];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Save failed", nil) message:m preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

// Audio session: the frames RemoteIO asks for in each callback follow the I/O buffer duration, about 21 ms by default on iOS (1024 frames at 48 kHz). The game keeps only 4 blocks × 5 ms = 20 ms in flight,
// so every callback came up 1.3 ms short and was zero-filled, about 47 gaps per second (crackling; reproducible on the Mac by forcing 1024-frame callbacks: 1999 underruns in 2000 callbacks). Ask for 5 ms and the system picks the nearest it supports;
// the category is Playback, as a game's or media app's: the ring / silent switch does not mute it (the default SoloAmbient follows the switch, which silenced the game whenever the phone was on silent) and it still interrupts other apps' audio.
// Set once at boot and again on return to the foreground (the system may reset it after an interruption)
static int g_session_off;   // the last activation failed (another app or a call still held the session): tried again when the app becomes active
void front_ios_audio_session(void) {
    AVAudioSession *s = AVAudioSession.sharedInstance; NSError *e = nil;
    if (![s setCategory:AVAudioSessionCategoryPlayback error:&e]) LOG("[RED] audio session category could not be set: %s", e.localizedDescription.UTF8String);
    [s setPreferredSampleRate:48000 error:nil];
    if (![s setPreferredIOBufferDuration:0.005 error:&e]) LOG("[RED] audio session I/O buffer duration could not be set: %s", e.localizedDescription.UTF8String);
    g_session_off = ![s setActive:YES error:&e];
    if (g_session_off) LOG("[RED] audio session activation failed: %s", e.localizedDescription.UTF8String);
    LOG("audio session: sample rate %.0f Hz, I/O buffer %.2f ms (asked for 5 ms)", s.sampleRate, s.IOBufferDuration * 1000);
}

// Real audio output is suspended (the silent sink paces the game) while the app is in the background or another audio session has interrupted ours (Siri, an alarm, a call).
// Without the interruption observer the AudioUnits stayed "started" while iOS no longer called them, and a game waiting for its buffers back lost its sound until restart.
// All of this runs on the main queue, like the scene callbacks
static int g_audio_bg, g_audio_intr, g_audio_mute;
static bool front_ios_held(void) { return g_menu_hold || g_audio_bg; }
static void front_ios_audio_apply(void) { dm_audio_suspend(g_audio_bg || g_audio_intr || g_audio_mute || g_menu_hold); }
bool front_menu_muted(void) { return g_audio_mute; }
void front_menu_set_muted(bool on) { g_audio_mute = on; LOG("front end: sound %s from the menu", on ? "muted" : "on"); front_ios_audio_apply(); }
static void front_ios_audio_watch(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue], reason = [n.userInfo[AVAudioSessionInterruptionReasonKey] unsignedIntegerValue];
        if (type == AVAudioSessionInterruptionTypeBegan) { LOG("audio session: interrupted (reason %lu)", (unsigned long)reason); g_audio_intr = 1; }
        else {
            LOG("audio session: interruption ended"); g_audio_intr = 0;
            if (!g_audio_bg) front_ios_audio_session();
        }
        front_ios_audio_apply();
    }];
    [nc addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; LOG("audio session: the media services were reset; setting the session and the outputs up again");
        front_ios_audio_session(); dm_audio_reset();
    }];
}

// Graphics are suspended while the app is in the background or the in-game menu holds the game, resumed when neither does (the two come and go independently)
static int g_gfx_held;
static void front_ios_gfx_hold(void) {
    int want = g_audio_bg || g_menu_hold;
    if (want != g_gfx_held) { g_gfx_held = want; dm_gfx_suspend(want); }
}

// Scene lifecycle (called by SceneDelegate in main.m): 0 resign active, 1 enter background, 2 return to foreground, 3 become active. On entering background, freeze the guest clock and suspend after in-flight GPU work completes (submitting GPU work in background gets the process killed).
// The screen stays on while the game is active: only touches reset the idle timer, so with a controller (or during a cutscene) the screen dimmed and locked mid-game
void front_ios_focus_event(int ev) {
    if (!g_layer) return;
    switch (ev) {
        case 0: dm_gamepad_reset(); dm_focus_set(2); break;
        case 1: UIApplication.sharedApplication.idleTimerDisabled = NO; dm_focus_set(3); g_audio_bg = 1; front_ios_audio_apply(); guest_clock_freeze_for(1, 1); front_ios_gfx_hold(); break;
        case 2: g_audio_bg = 0; front_ios_gfx_hold(); guest_clock_freeze_for(1, 0); front_ios_audio_session(); front_ios_audio_apply(); dm_focus_set(2); break;
        case 3:   // Becoming active again also ends an interruption whose "ended" never came (not every one sends it), and retries a session that would not activate on the way back
            UIApplication.sharedApplication.idleTimerDisabled = YES;
            if (g_audio_intr) { LOG("audio session: active again with no interruption-ended notice; resuming"); g_audio_intr = 0; g_session_off = 1; }
            if (g_session_off) front_ios_audio_session();
            front_ios_audio_apply(); dm_focus_set(g_menu_hold ? 2 : 1); break;   // the menu still open: out of focus until it closes
    }
}

// The in-game menu holds the game while it is open, as the background does (the Switch's HOME menu likewise takes the focus and suspends the game): focus lost, guest clock frozen
// with guest reads of it waiting (reason 3, hle_os.c), the real audio output off and graphics suspended, the last picture staying on screen. Every key is released first
void front_menu_hold(int on) {
    if (!g_layer || g_menu_hold == !!on) return;
    uint64_t t0 = now_ns();
    if (on) {
        g_menu_hold = 1; dm_gamepad_reset(); dm_focus_set(2); guest_clock_freeze_for(3, 1); front_ios_audio_apply(); front_ios_gfx_hold();
    } else {
        g_menu_hold = 0; front_ios_gfx_hold(); guest_clock_freeze_for(3, 0); front_ios_audio_apply();
        dm_focus_set(UIApplication.sharedApplication.applicationState == UIApplicationStateActive ? 1 : 2);
    }
    LOG("front end: in-game menu %s the game (%.1f ms)", on ? "holds" : "releases", (now_ns() - t0) / 1e6);
}
void front_menu_quit(void) { dm_host_shutdown("quit from the in-game menu"); }
