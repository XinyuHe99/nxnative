// Swift bridging header: the C entry points the in-game menu (GameMenu.swift) calls. front_ios.m and DmGamepad.m implement them, the host's hle_oe.c the console mode, nvn_mtl.m the screenshot
// and the frame count
#include <stdbool.h>

// front_ios.m
bool front_menu_muted(void);
void front_menu_set_muted(bool on);      // the real audio output off (the silent sink keeps pacing the game)
bool front_menu_ambient(void);
void front_menu_set_ambient(bool on);   // Ambient mode: the picture's edges extended into the bars beside it
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
void dm_gfx_shot_at(long k, const char *path);
unsigned long long mtl_present_count(void);   // frames put on screen so far (nvn_mtl.m, for NVN and the Vulkan layer alike): the menu's frame rate   // PNG of the k-th frame presented from now (nvn_mtl.m)
