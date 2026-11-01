// The in-game settings menu's live side (duo/design/ingamemenu-v2.md §3.4): a row whose value is changed while the game runs either takes
// effect at once or waits for the next start, and the menu asks before the player touches anything, so its badge tells the truth.
//
// Nothing here writes the environment. POSIX does not promise a thread-safe setenv, and the host calls getenv from the present thread, the
// audio thread and the guest thread (§3.4, §5.1): the environment stays the launch-time record Play wrote, a run-time change goes through the
// setter that owns the state, and the saved choice goes through the shared SettingsStore (LauncherSettings.swift) — the menu commits there
// first, exactly as Play does, then calls dm_setting_live.
//
// A row this table does not know answers 0 (next start): the menu then says so instead of pretending. DM_RUMBLE only answers 1 once the rumble
// engine exists (front_ios.m dm_haptics_apple_init, at startGame), and the frame-step rows only on a build whose page exists — the two honest
// limits §2.3 and G6 name.
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "dm.h"
#include "hle.h"
#include "haptics_apple.h"

int dm_gamepad_set_layout(int layout);   // DmGamepad.m: the running pad's switches (G4)
int dm_gamepad_set_hidden(int hidden);
int dm_gamepad_set_touch_haptics(int on);   // the tap per touch-control press edge
int dm_gamepad_ready(void);              // whether the pad exists, i.e. a live change can take effect now
void dm_dual_set(int on);                // DmGamepad.m: split screen as runtime state (G2)
int dm_hud_set(int on);                  // front_ios.m: Apple's Metal performance HUD, a CAMetalLayer property
int dm_hud_ready(void);                  // whether the game view (and so the layer) exists yet
void front_ios_relayout(void);          // front_ios.m: the picture's rect follows the fill (letterbox = the 16:9 picture itself, so its bands show the background)

// DM_PRESENT_FILL takes the catalogue's numbers and the env file's words (nvn_mtl.m dm_present_fill reads both): 0 / "letterbox",
// 1 / "stretch", 2 / "crop"; -1 = neither (a value nothing would honour)
static int fill_mode(const char *v) {
    if (!strcmp(v, "letterbox")) return 0;
    if (!strcmp(v, "stretch")) return 1;
    if (!strcmp(v, "crop")) return 2;
    int m = atoi(v); return m >= 0 && m <= 2 ? m : -1;
}
static int on_value(const char *v) { return !strcmp(v, "1") || !strcmp(v, "on"); }

// 1 = the change is in effect now, 0 = it needs the next start (or this build has no live path for the row). A NULL value only asks: no side
// effect at all, which is how the menu draws the badge for a row before the player touches it
int dm_setting_live(const char *env, const char *value) {
    if (!env || !*env) return 0;
    int ask = value == NULL;
    if (!strcmp(env, "DM_FPS_TARGET")) {   // the loader wrote the frame-step page and fps_step_cap() re-reads +0x00 on every present (hle_nvn.c)
        if (!dm_fps_state) return 0;       // no page: g_present_cap is a one-shot static, or an engine limiter read the cap once
        if (!ask) dm_fps_state_set_fps(atoi(value));
        return 1;
    }
    if (!strcmp(env, "DM_RENDER_SCALE")) {   // the view-sizing stub loads [state+0x10] every time it runs (loader.c, patch_nso.py FRAME_STEP)
        if (!dm_fps_state) return 0;
        if (ask) return 1;
        char *end; float s = strtof(value, &end);
        if (end == value || *end || !(s >= 0.5f && s <= 1.0f)) return 0;   // refused: the stored choice still takes effect at the next start
        dm_fps_state_set_scale(s);
        LOG("front end: render scale -> %.2f (in-game settings)", s);
        return 1;
    }
    if (!strcmp(env, "DM_RUMBLE")) {   // dm_haptics_init is safe to re-call: it clears every motor under its own lock (hle_haptics.c, G7)
        if (!dm_haptics_apple_ready()) return 0;
        if (!ask) dm_haptics_apple_set(atoi(value) != 0, NAN, NAN);   // the strength and the cutoff keep their values
        return 1;
    }
    if (!strcmp(env, "DM_PRESENT_FILL")) {   // dm_present_set_fill: read every present (nvn_mtl.m), so no relaunch is involved
        if (ask) return 1;
        int mode = fill_mode(value); if (mode < 0) return 0;
        dm_present_set_fill(mode);
        front_ios_relayout();
        return 1;
    }
    if (!strcmp(env, "DM_DUAL_SCREEN")) {   // runtime state since G2; front_ios.m and -controlRect read dm_split_active on every layout
        if (!ask) dm_dual_set(on_value(value));
        return 1;
    }
    if (!strcmp(env, "DM_PAD_LAYOUT")) {
        if (!dm_gamepad_ready()) return 0;
        return ask || dm_gamepad_set_layout(atoi(value));
    }
    if (!strcmp(env, "DM_PAD_HIDDEN")) {
        if (!dm_gamepad_ready()) return 0;
        return ask || dm_gamepad_set_hidden(on_value(value));
    }
    if (!strcmp(env, "DM_TOUCH_HAPTICS")) {   // the pad's feedback generator: made on demand, released when off (DmGamepad.m applyTouchHaptics)
        if (!dm_gamepad_ready()) return 0;
        return ask || dm_gamepad_set_touch_haptics(on_value(value));
    }
    if (!strcmp(env, "DM_METAL_HUD")) {   // Apple's HUD is a CAMetalLayer property (front_ios.m dm_hud_set): Core Animation reads it on the next frame
        if (!dm_hud_ready()) return 0;
        return ask || dm_hud_set(on_value(value));
    }
    return 0;   // a row with no live path: the next start, and the menu says so
}

// The same answer without a change: the menu draws its badge from this before the player touches the row
int dm_setting_live_state(const char *env) { return dm_setting_live(env, NULL); }
