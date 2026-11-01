// The Objective-C functions the Swift sources call (CloudSaves.h), and the host's C entry points InGameMenu.swift calls. project.yml points
// SWIFT_OBJC_BRIDGING_HEADER here. Only what Swift needs: dm.h / hle.h stay out, so the Swift side sees a small surface.
#import "CloudSaves.h"
#include <stdint.h>

// The live settings table (settings_live.m): 1 = the change is in effect now, 0 = it needs the next start (or this build has no live path).
// dm_setting_live_state is the same answer without a change: the menu draws its badge from it before the player touches the row
int dm_setting_live(const char *env, const char *value);
int dm_setting_live_state(const char *env);

// The present pass's picture fill (dm.h; nvn_mtl.m), the frame-rate counter (front_ios.m) and the thermal state (0 nominal, 1 fair,
// 2 serious, 3 critical): the in-game menu's footer
void dm_present_set_fill(int mode);
uint64_t mtl_present_count(void);
int dm_thermal_now(void);

// The pad's switches (DmGamepad.m): live layout, show / hide, Move / Play (the layout editor), Reset Layout and Controls opacity (the current
// orientation class's), and the suspension while the menu is open
int dm_gamepad_ready(void);
int dm_gamepad_set_layout(int layout);
int dm_gamepad_set_hidden(int hidden);
int dm_gamepad_set_editing(int on);
int dm_gamepad_reset_layout(void);
int dm_gamepad_editing(void);
int dm_gamepad_set_opacity(float opacity);
float dm_gamepad_opacity(void);
void dm_gamepad_suspend(int on);

// The player's background image behind the picture and the controls (front_ios.m): the picked photo's bytes (stored downscaled as
// Documents/background.jpg; 0 = not an image or not saved), removal, whether one is set, and its dimming 0…0.8
int dm_background_set_image(const void *bytes, long length);
void dm_background_remove(void);
int dm_background_present(void);
void dm_background_set_dim(float dim);
float dm_background_dim(void);
