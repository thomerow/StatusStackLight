// lampenzustand.h - der Zustand einer einzelnen Lampe und seine Uebersetzung
// von und nach JSON.
//
// Bewusst getrennt von der Ansteuerung (lampen.*): hier steht, was eine Lampe
// darstellen kann, dort, wie daraus ein PWM-Signal wird.

#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

#include "config.h"

enum class Effekt : uint8_t {
    Dauer,       // "steady"
    Blinken,     // "blink"
    Pulsieren,   // "pulse"
};

const char *effektName(Effekt e);
bool        effektAusName(const char *name, Effekt &ziel);

struct Lampenzustand {
    // Hauptschalter. Bewusst getrennt vom Effekt: wer eine blinkende Lampe
    // ausschaltet und wieder einschaltet, will sie blinkend zurueckbekommen.
    bool    an         = false;
    Effekt  effekt     = Effekt::Dauer;
    uint8_t helligkeit = HELLIGKEIT_STANDARD;   // 0...100 %
    float   frequenz   = FREQUENZ_STANDARD;     // Hz, nur fuer Blinken/Pulsieren
    uint8_t tastgrad   = TASTGRAD_STANDARD;     // 1...99 %, nur fuer Blinken
};

// Ergebnis einer Uebernahme aus JSON. Bei einem Fehler bleibt der Zustand
// unveraendert - es wird nie halb uebernommen.
struct Pruefergebnis {
    bool   ok = true;
    String fehler;   // Klartext, geht unveraendert an den Client
};

// Uebernimmt die in `quelle` vorhandenen Felder. Bei `vollstaendig` (PUT)
// werden fehlende Felder auf die Standardwerte gesetzt, sonst (PATCH) bleiben
// sie stehen.
//
// Werte ausserhalb der Grenzen werden NICHT stillschweigend zurechtgebogen,
// sondern als Fehler gemeldet: beim Verkabelungstest will man wissen, wenn
// etwas nicht so ankommt, wie man es geschickt hat.
Pruefergebnis uebernimmJson(Lampenzustand &zustand, JsonObjectConst quelle, bool vollstaendig);

// Dasselbe aus Query-Parametern (?brightness=50&effect=blink&...), fuer die
// GET-Kurzbefehle.
class WebServer;
Pruefergebnis uebernimmQuery(Lampenzustand &zustand, WebServer &server);

// Schreibt den Zustand als JSON-Objekt, angereichert um die unveraenderlichen
// Angaben des Kanals (id, Kanalnummer, GPIO, Anzeigename, Farbe).
void schreibeJson(const Lampenzustand &zustand, uint8_t index, JsonObject ziel);
