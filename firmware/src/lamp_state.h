// lamp_state.h - the state of a single lamp and its conversion from and to
// JSON.
//
// Deliberately separate from the drive code (lamps.*): this file defines what
// a lamp can show, that one how it becomes a PWM signal.

#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

#include "config.h"

// The numeric values are stored in NVS (lamp_store.cpp) - do not reorder.
enum class Effect : uint8_t {
    Steady,   // "steady"
    Blink,    // "blink"
    Pulse,    // "pulse"
};

const char *effectName(Effect e);
bool        effectFromName(const char *name, Effect &target);

struct LampState {
    // Master switch. Deliberately separate from the effect: whoever turns a
    // blinking lamp off and on again wants it back blinking.
    bool    on         = false;
    Effect  effect     = Effect::Steady;
    uint8_t brightness = BRIGHTNESS_DEFAULT;   // 0...100 %
    float   frequency  = FREQUENCY_DEFAULT;    // Hz, only for blink/pulse
    uint8_t duty       = DUTY_DEFAULT;         // 1...99 %, only for blink
};

// Result of applying JSON. On error the state stays unchanged - it is never
// applied halfway.
struct ValidationResult {
    bool   ok = true;
    String error;   // plain text, passed to the client as is
};

// Applies the fields present in `source`. With `complete` (PUT), missing
// fields are reset to their defaults, otherwise (PATCH) they stay as they are.
//
// Out-of-range values are NOT silently clamped but reported as errors. A
// silently halved brightness sends you looking in the wrong place when
// debugging - a clear answer beats a plausible result.
ValidationResult applyJson(LampState &state, JsonObjectConst source, bool complete);

// The same from query parameters (?brightness=50&effect=blink&...), for the
// GET shortcuts.
class WebServer;
ValidationResult applyQuery(LampState &state, WebServer &server);

// Writes the state as a JSON object, enriched with the fixed properties of
// the channel (id, channel number, GPIO, display name, colour).
void writeJson(const LampState &state, uint8_t index, JsonObject target);
