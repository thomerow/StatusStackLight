// api_server.h - HTTP interface: JSON API, GET shortcuts and the two embedded
// web pages.
//
// Deliberately the synchronous WebServer from the Arduino core: no extra
// dependency, no AsyncTCP version traps. That this is good enough is thanks to
// the effect engine - it runs in its own task and cannot be stalled by a
// hanging HTTP client.

#pragma once

#include <Arduino.h>

namespace Api {

void begin();
void tick();   // call from loop()

}   // namespace Api
