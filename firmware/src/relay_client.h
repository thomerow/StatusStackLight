// relay_client.h - relay mode: the stack light fetches its state from a relay
// server instead of being switched over the local API.
//
// The relay (relay/ in this repo) runs somewhere on the internet, collects the
// events of the Claude Code hooks and turns them into the image of the five
// lamps. The stack light polls it with long polling: each request waits at
// the relay until the image changes, so a change arrives within a fraction of
// a second at the cost of one request every 25 seconds while nothing happens.
//
// The local API keeps working in relay mode - handy for trying things out -
// but the next change from the relay overwrites whatever was set locally.

#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

namespace Relay {

// Loads the settings from NVS and starts the polling task.
void begin();

// Changes the settings. `url` and `key` may be null to keep the stored value.
// Takes effect with the next poll; a poll that is still waiting at the relay
// is discarded when it returns. Returns false with a message if a value is
// invalid - then nothing is changed.
bool configure(bool enabled, const String *url, const String *key, String &error);

// Settings for GET /api/config. The key is never given out, only whether one
// is set.
void writeConfig(JsonObject target);

// Connection state for GET /api/status.
void writeStatus(JsonObject target);

}   // namespace Relay
