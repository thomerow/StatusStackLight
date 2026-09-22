// lamps.h - drives the five lamps via LEDC.
//
// The effect engine runs in its own FreeRTOS task on core 0 and is therefore
// completely decoupled from the web server: not even a hanging HTTP client
// can make the blinking stutter.

#pragma once

#include <Arduino.h>

#include "config.h"
#include "lamp_state.h"

namespace Lamps {

// Sets the GPIOs to "off" and configures the LEDC channels.
// Must run as early as possible in setup() - see the comment in lamps.cpp.
void begin();

// Starts the effect task. Separate from begin() so the pins are already dark
// before anything else starts up.
void startEffectTask();

LampState state(uint8_t index);
void      setState(uint8_t index, const LampState &state);

// Applies several partial lamp states at once, as POST /api/lamps and the
// relay deliver them: {"red": {...}, "blue": {...}}. Lamps not mentioned stay
// as they are. Everything is validated first, and all changes land in one
// step - the effect task never shows a half-applied image. On an unknown lamp,
// `unknownLamp` (if given) receives its name.
ValidationResult applyBatch(JsonObjectConst source, String *unknownLamp = nullptr);

// Looks up a lamp by its ID ("red") or its channel number ("5").
// Returns -1 if there is no such lamp.
int findIndex(const String &identifier);

// Brightness currently being output in percent (0...100), i.e. the value
// after applying the effect but before gamma correction.
uint8_t currentLevel(uint8_t index);

// Channel sweep: turns channels 1...5 on one at a time.
// Used to check the GPIO -> lamp mapping against the real stack light.
// Runs in the effect task and restores the previous state afterwards.
void startSweep();
bool sweepRunning();
int  sweepChannel();   // 1...5 during the sweep, 0 otherwise

// System display: overlays the lamp state while active, without changing it.
// The stored state can still be changed via the API and appears as soon as
// the display ends.
enum class SystemDisplay : uint8_t {
    None,
    Connecting,   // blue pulsing
    Portal,       // orange pulsing slowly
    Connected,    // green flash, ends by itself
    RelayLost,    // red pulsing slowly and dimly - relay mode without contact
};

void          setSystemDisplay(SystemDisplay d);
// Ends the display, but only if it is still `expected` - so the relay client
// cannot switch off the portal display the WiFi code has set in the meantime.
void          clearSystemDisplay(SystemDisplay expected);
SystemDisplay systemDisplay();
const char   *systemDisplayName(SystemDisplay d);   // for /api/status

}   // namespace Lamps
