// api_server.h - HTTP-Schnittstelle: JSON-API, GET-Kurzbefehle und die beiden
// eingebetteten Web-Seiten.
//
// Bewusst der synchrone WebServer aus dem Arduino-Core: keine zusaetzliche
// Abhaengigkeit, keine AsyncTCP-Versionsfallen. Dass das genuegt, liegt an der
// Effekt-Engine - die laeuft in einem eigenen Task und kann durch einen
// haengenden HTTP-Client nicht ins Stocken geraten.

#pragma once

#include <Arduino.h>

namespace Api {

void begin();
void tick();   // aus loop() aufrufen

}   // namespace Api
