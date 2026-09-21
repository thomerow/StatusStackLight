// lampen.h - Ansteuerung der fuenf Lampen ueber LEDC.
//
// Die Effekt-Engine laeuft in einem eigenen FreeRTOS-Task auf Core 0 und ist
// damit vollstaendig vom Webserver entkoppelt: selbst ein haengender
// HTTP-Client kann das Blinken nicht ins Stocken bringen.

#pragma once

#include <Arduino.h>

#include "config.h"
#include "lampenzustand.h"

namespace Lampen {

// Setzt die GPIOs auf "aus" und richtet die LEDC-Kanaele ein.
// Muss so frueh wie moeglich in setup() laufen - siehe Kommentar in lampen.cpp.
void begin();

// Startet den Effekt-Task. Getrennt von begin(), damit die Pins schon dunkel
// sind, bevor irgendetwas anderes hochfaehrt.
void starteEffektTask();

Lampenzustand zustand(uint8_t index);
void          setzeZustand(uint8_t index, const Lampenzustand &neu);

// Sucht eine Lampe ueber ihre ID ("red") oder ihre Kanalnummer ("5").
// Liefert -1, wenn es sie nicht gibt.
int findeIndex(const String &bezeichner);

// Momentan ausgegebene Helligkeit in Prozent (0...100), also der Wert nach
// Anwendung des Effekts, aber vor der Gammakorrektur.
uint8_t aktuellesNiveau(uint8_t index);

// Kanal-Durchlauf: schaltet die Kanaele 1...5 nacheinander einzeln ein.
// Dient dazu, die Zuordnung GPIO -> Lampe gegen die echte Saeule zu pruefen.
// Laeuft im Effekt-Task und stellt danach den vorherigen Zustand wieder her.
void starteDurchlauf();
bool durchlaufLaeuft();
int  durchlaufKanal();   // 1...5 waehrend des Durchlaufs, sonst 0

}   // namespace Lampen
