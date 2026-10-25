// Swift bridging header: the C entry points the in-game menu (GameMenu.swift) calls. front_ios.m and DmGamepad.m implement them, the host's hle_oe.c the console mode, nvn_mtl.m the screenshot
#include <stdbool.h>

// front_ios.m
void front_menu_hold(int on);            // the menu is open: the game is held as in the background (guest clock and graphics suspended, audio out, focus lost)
int front_menu_perf_mode(void);
void front_menu_set_perf_mode(int mode); // the performance overlay at the top left: 0 off, 1 frame rate, 2 performance panel (DmPerfPanel.m)
double front_menu_fps(void);             // frames put on screen per second, measured before the menu held the game; -1 before the first second
bool front_menu_muted(void);
void front_menu_set_muted(bool on);      // the real audio output off (the silent sink keeps pacing the game)
void front_menu_quit(void);              // the host's graceful exit (hle_lifecycle.c)
int dm_thermal_now(void);                // 0 nominal .. 3 critical

// DmGamepad.m: the virtual gamepad
int dm_pad_layout(void);                 // 0 = 2D, 1 = 3D, 2 = Tap
void dm_pad_set_layout(int l);           // Tap only in handheld mode
double dm_pad_opacity(void);
void dm_pad_set_opacity(double a);       // 0.2 .. 1; 0.5 is the default look
bool dm_pad_hidden(void);
void dm_pad_set_hidden(bool on);         // hidden: every touch goes to the game, as with a physical controller connected
bool dm_pad_haptics(void);
void dm_pad_set_haptics(bool on);
bool dm_pad_controller(void);            // a physical controller is connected (the virtual gamepad is hidden meanwhile)
void dm_pad_shake(double seconds);       // shake the controller for this long (the six-axis sensor, as shaking the phone)
bool dm_pad_takes(double x, double y);   // a touch landing there (root view points) would take a control: the edge swipe leaves it to the gamepad

// host
int dm_opmode(void);                     // 0 handheld, 1 docked (hle_oe.c)
void dm_set_opmode(int m);
void dm_gfx_shot_at(long k, const char *path);   // PNG of the k-th frame presented from now (nvn_mtl.m)
