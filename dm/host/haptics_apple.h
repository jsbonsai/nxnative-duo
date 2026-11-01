// Shared Core Haptics output for the Mac and iOS front ends. Configure routes before guest boot.
#pragma once
#import <GameController/GameController.h>
#include "hle_haptics.h"
void dm_haptics_apple_init(void);
void dm_haptics_apple_controller(int player, GCController *controller);
void dm_haptics_apple_shutdown(void);
// A rumble switch changed while the game runs (the in-game menu's Game rumble row): the engine re-initialised with `on`, every motor
// cleared. gain and min are the strength and the cutoff; NaN keeps the value in force. No engine yet: nothing happens
// dm_haptics_apple_ready() is 1 once init has run, i.e. a live change can take effect now
void dm_haptics_apple_set(int on, float gain, float min);
int dm_haptics_apple_ready(void);
