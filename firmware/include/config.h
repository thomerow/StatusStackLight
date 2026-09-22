// config.h - alle Werte, die von der Hardware abhaengen, an einer Stelle.
//
// Aendert sich etwas an der Saeule (andere Lampe, andere Farbreihenfolge,
// getauschtes MOSFET-Modul), wird hier geschraubt - nicht im uebrigen
// Quelltext.

#pragma once

#include <Arduino.h>

// --- Geraet ----------------------------------------------------------------

#define SSL_HOSTNAME       "StatusStackLight"   // DHCP-Name und mDNS -> statusstacklight.local
#define SSL_FIRMWARE       "1.0.0"
#define SSL_AP_PRAEFIX     "StatusStackLight"   // Konfig-AP heisst StatusStackLight-XXXX

// --- Lampen ----------------------------------------------------------------

static const uint8_t LAMPEN_ANZAHL = 5;

// Schaltlogik des MOSFET-Moduls.
//
// Das verbaute Modul ist optokopplergesteuert und schaltet LOW-aktiv: ein
// GPIO auf Masse laesst die Lampe leuchten. Die Invertierung passiert genau
// einmal, beim Schreiben ins LEDC-Register (siehe lampen.cpp); alles darueber
// rechnet durchgehend in "0 = aus, 100 = volle Helligkeit".
//
// Zeigt sich beim Test das umgekehrte Verhalten (Lampen an, solange nichts
// angesteuert wird), genuegt hier false.
static const bool LAMPE_LOW_AKTIV = true;

struct LampenKanal {
    uint8_t     gpio;
    const char *id;      // API-Bezeichner, klein und englisch
    const char *name;    // Anzeigename im Web-Interface
    const char *farbe;   // CSS-Farbe fuer den Zustandspunkt im Web-Interface
};

// Reihenfolge = Kanalnummer 1...5 (wie in der Gehaeuse-README).
//
// GEPRUEFT: 21.09.2026 gegen die aufgebaute Saeule - diese Zuordnung stimmt.
//
// Wird einmal umverdrahtet oder eine Lampe getauscht, ist der Kanal-Durchlauf
// im Web-Interface der schnellste Weg zur Kontrolle: leuchtet dabei eine
// andere Lampe als angesagt, werden hier die Zeilen getauscht und sonst
// nichts.
static const LampenKanal LAMPEN[LAMPEN_ANZAHL] = {
    {  4, "white",  "weiß",   "#f8fafc" },   // Kanal 1
    {  5, "blue",   "blau",   "#3b82f6" },   // Kanal 2
    {  6, "green",  "grün",   "#22c55e" },   // Kanal 3
    {  7, "orange", "orange", "#f59e0b" },   // Kanal 4
    { 15, "red",    "rot",    "#ef4444" },   // Kanal 5
};

// Anzeigereihenfolge im Web-Interface, von oben nach unten - als Index in
// LAMPEN[]. Bildet die physische Saeule ab (rot oben), nicht die GPIO-Nummern.
// Auch das ist eine Annahme, die beim ersten Blick auf die Saeule zu pruefen ist.
static const uint8_t LAMPEN_UI_REIHENFOLGE[LAMPEN_ANZAHL] = { 4, 3, 2, 1, 0 };

// --- PWM -------------------------------------------------------------------

// 12 Bit reichen fuer 101 Helligkeitsstufen mit Gammakorrektur bequem aus und
// erlauben gleichzeitig Grundfrequenzen bis ueber 20 kHz.
static const uint8_t  PWM_AUFLOESUNG_BIT = 12;

// Hoechster Registerwert, also volle Helligkeit.
//
// Stolperfalle, die man leicht falsch herum loest: bei 12 Bit waere 4095 nur
// 4095/4096 Tastverhaeltnis, die Lampe also nie ganz durchgeschaltet. Der
// Arduino-Core faengt das selbst ab - ledcWrite() erkennt "alle Bits gesetzt"
// und schreibt intern 4096 = dauerhaft an (siehe esp32-hal-ledc.c). Deshalb
// ist 4095 hier korrekt und 4096 waere falsch: der Wert liefe an dieser
// Sonderbehandlung vorbei und ginge ungeprueft an ledc_set_duty().
//
// Fuer die LOW-aktive Ansteuerung zaehlt genau das: invertiert wird als
// PWM_MAX - wert, und weil 0 dadurch zu 4095 wird, greift die Sonderbehandlung
// und die Lampe ist wirklich vollstaendig dunkel statt mit 1/4096 zu glimmen.
static const uint32_t PWM_MAX            = (1u << PWM_AUFLOESUNG_BIT) - 1;  // 4095

// Grundfrequenz der Traegerschwingung - fest, nicht zur Laufzeit aenderbar.
//
// 1 kHz ist fuer 12-V-LED-Module der uebliche Kompromiss: hoch genug gegen
// sichtbares Flimmern, niedrig genug, dass die MOSFETs sauber schalten.
//
// Nach oben ist ohnehin wenig Luft: das verbaute MOSFET-Modul schafft rund
// 2 kHz. Seine Gates werden ueber einen Vorwiderstand geladen und ueber einen
// 10-kOhm-Pulldown wieder entladen, was den Abschaltvorgang traege macht -
// oberhalb davon verbringt der MOSFET einen wachsenden Teil jeder Periode im
// linearen Bereich und wird heiss, statt sauber zu schalten. Der ESP32 waere
// nicht die Grenze: sein LEDC-Block leitet den Takt aus 80 MHz ab, es gilt
// Frequenz * 2^Aufloesung <= 80 MHz, bei 12 Bit also bis 19531 Hz.
//
// Nicht zu verwechseln mit der Frequenz eines Lampeneffekts (FREQUENZ_MIN/MAX
// weiter unten) - das ist der Blink- beziehungsweise Pulsiertakt.
static const uint32_t PWM_GRUNDFREQUENZ = 1000;

// Gamma fuer die Helligkeitskennlinie. 2.2 entspricht grob der Empfindlichkeit
// des Auges - ohne das wirken 50 % deutlich heller als halb so hell.
static const float GAMMA = 2.2f;

// --- Grenzwerte der Effektparameter ----------------------------------------

static const uint8_t HELLIGKEIT_MIN = 0;
static const uint8_t HELLIGKEIT_MAX = 100;

static const float FREQUENZ_MIN = 0.1f;
static const float FREQUENZ_MAX = 20.0f;

static const uint8_t TASTGRAD_MIN = 1;    // "duty" in der API
static const uint8_t TASTGRAD_MAX = 99;

// --- Standardzustand nach dem Start ----------------------------------------

static const uint8_t HELLIGKEIT_STANDARD = 100;
static const float   FREQUENZ_STANDARD   = 1.0f;
static const uint8_t TASTGRAD_STANDARD   = 50;

// --- Zeiten ----------------------------------------------------------------

static const uint32_t EFFEKT_TAKT_HZ        = 100;    // Aktualisierungsrate der Effekt-Engine
static const uint32_t WLAN_VERBINDE_TIMEOUT = 20000;  // ms, danach oeffnet der Konfig-AP
static const uint32_t WLAN_NEUSTART_NACH    = 120000; // ms ohne Verbindung -> Konfig-AP
static const uint32_t DURCHLAUF_MS          = 1000;   // Haltezeit je Kanal beim Durchlauftest
static const uint32_t SPEICHER_VERZOEGERUNG_MS = 2000; // ms Ruhe, bevor der Lampenzustand ins NVS geht

// --- Startanzeige ----------------------------------------------------------
//
// Beim Start und im Konfig-AP zeigt die Saeule den WLAN-Zustand statt des
// gespeicherten Lampenzustands: blau pulsierend = verbindet, gruener Blitz =
// verbunden, orange langsam pulsierend = Konfig-AP offen.
//
// Blau pulsiert bewusst deutlich schneller als "Claude arbeitet" (0,3 Hz im
// Hook-Skript), damit man die beiden nicht verwechselt.

static const float    ANZEIGE_VERBINDEN_HZ = 1.0f;
static const float    ANZEIGE_PORTAL_HZ    = 0.3f;
static const uint32_t ANZEIGE_BLITZ_MS     = 1000;
// Dunkelpause nach dem Blitz. Ohne sie ginge das Gruen nahtlos in einen
// gespeicherten gruenen Zustand ("fertig") ueber und waere nicht als eigenes
// Signal zu erkennen.
static const uint32_t ANZEIGE_PAUSE_MS     = 400;
static const uint8_t  ANZEIGE_HELLIGKEIT   = 100;   // %
