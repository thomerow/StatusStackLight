#include "lampenspeicher.h"

#include <Arduino.h>
#include <Preferences.h>

#include "config.h"
#include "lampen.h"

namespace {

const char   *NVS_BEREICH = "ssl-lampen";
const char   *NVS_SCHLUESSEL = "zustand";

// Bei jeder Aenderung am Aufbau von GespeicherteLampe hochzaehlen. Ein Abbild
// mit anderer Fassung wird verworfen statt falsch gedeutet.
const uint8_t FASSUNG = 1;

// Festes Speicherformat, unabhaengig vom Aufbau von Lampenzustand im RAM -
// sonst wuerde ein harmloses Umsortieren der Struktur beim naechsten Flashen
// Unsinn aus dem NVS lesen.
struct __attribute__((packed)) GespeicherteLampe {
    uint8_t an;
    uint8_t effekt;
    uint8_t helligkeit;
    uint8_t tastgrad;
    float   frequenz;
};

struct __attribute__((packed)) Abbild {
    uint8_t           fassung;
    GespeicherteLampe lampen[LAMPEN_ANZAHL];
};

Abbild   gespeichert;                // was zuletzt im NVS gelandet ist
bool     geaendert       = false;    // RAM weicht vom NVS ab
uint32_t letzteAenderung = 0;        // millis() der juengsten beobachteten Aenderung
uint32_t letztePruefung  = 0;
uint32_t sperreBis       = 0;        // nach einem Schreibfehler: nicht vor diesem millis()
bool     gesperrt        = false;

Abbild erzeugeAbbild()
{
    Abbild a;
    memset(&a, 0, sizeof(a));        // Fuellbytes definiert, damit memcmp taugt
    a.fassung = FASSUNG;
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        const Lampenzustand z = Lampen::zustand(i);
        a.lampen[i].an         = z.an ? 1 : 0;
        a.lampen[i].effekt     = (uint8_t) z.effekt;
        a.lampen[i].helligkeit = z.helligkeit;
        a.lampen[i].tastgrad   = z.tastgrad;
        a.lampen[i].frequenz   = z.frequenz;
    }
    return a;
}

// Ein einzelner kaputter Eintrag soll nicht den ganzen Rest verwerfen, aber
// auch nicht ungeprueft an die Effekt-Engine gehen.
bool istGueltig(const GespeicherteLampe &g)
{
    return g.an <= 1
        && g.effekt <= (uint8_t) Effekt::Pulsieren
        && g.helligkeit <= HELLIGKEIT_MAX
        && g.tastgrad >= TASTGRAD_MIN && g.tastgrad <= TASTGRAD_MAX
        && g.frequenz >= FREQUENZ_MIN && g.frequenz <= FREQUENZ_MAX;
}

}   // namespace

namespace Lampenspeicher {

void lade()
{
    Preferences speicher;
    Abbild      a;
    size_t      gelesen = 0;

    if (speicher.begin(NVS_BEREICH, true)) {
        gelesen = speicher.getBytes(NVS_SCHLUESSEL, &a, sizeof(a));
        speicher.end();
    }

    if (gelesen != sizeof(a) || a.fassung != FASSUNG) {
        Serial.println(F("[speicher] kein gespeicherter Zustand, Lampen bleiben aus"));
        gespeichert = erzeugeAbbild();
        return;
    }

    uint8_t uebernommen = 0;
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        const GespeicherteLampe &g = a.lampen[i];
        if (!istGueltig(g)) {
            Serial.printf("[speicher] Eintrag %u ungueltig, bleibt beim Standard\n", i + 1);
            continue;
        }
        Lampenzustand z;
        z.an         = g.an == 1;
        z.effekt     = (Effekt) g.effekt;
        z.helligkeit = g.helligkeit;
        z.tastgrad   = g.tastgrad;
        z.frequenz   = g.frequenz;
        Lampen::setzeZustand(i, z);
        uebernommen++;
    }

    // Vergleichsbasis ist, was jetzt tatsaechlich im RAM steht - dann loest ein
    // teilweise verworfenes Abbild beim naechsten tick() ein sauberes
    // Neuschreiben aus.
    gespeichert = erzeugeAbbild();
    geaendert   = memcmp(&gespeichert, &a, sizeof(a)) != 0;
    letzteAenderung = millis();

    Serial.printf("[speicher] Zustand von %u Lampen wiederhergestellt\n", uebernommen);
}

void tick()
{
    const uint32_t jetzt = millis();
    if (jetzt - letztePruefung < 100) return;
    letztePruefung = jetzt;

    // Verglichen wird der Inhalt, nicht die Zahl der Anfragen: das Hook-Skript
    // schickt bei jedem Ereignis den kompletten Sollzustand, meist unveraendert.
    // Wuerde jede Anfrage einen Schreibvorgang ausloesen, waere das bei einer
    // aktiven Session ein Flash-Zugriff alle paar Sekunden.
    static Abbild zuletztGesehen = gespeichert;
    const Abbild  aktuell        = erzeugeAbbild();
    if (memcmp(&aktuell, &zuletztGesehen, sizeof(aktuell)) != 0) {
        zuletztGesehen  = aktuell;
        geaendert       = memcmp(&aktuell, &gespeichert, sizeof(aktuell)) != 0;
        letzteAenderung = jetzt;
    }

    // Erst schreiben, wenn sich eine Weile nichts mehr tut. Ein gezogener
    // Schieberegler im Web-Interface erzeugt so einen Schreibvorgang statt
    // zwanzig, und der kurze Warnblitz des Hooks landet gar nicht erst im Flash.
    if (!geaendert || jetzt - letzteAenderung < SPEICHER_VERZOEGERUNG_MS) return;
    if (gesperrt && (int32_t) (jetzt - sperreBis) < 0) return;
    gesperrt = false;

    Preferences speicher;
    if (speicher.begin(NVS_BEREICH, false)) {
        const size_t geschrieben = speicher.putBytes(NVS_SCHLUESSEL, &aktuell, sizeof(aktuell));
        speicher.end();
        if (geschrieben == sizeof(aktuell)) {
            gespeichert = aktuell;
            geaendert   = false;
            return;
        }
    }
    // Fehlschlag: in einer Minute erneut versuchen statt alle 100 ms.
    Serial.println(F("[speicher] Schreiben ins NVS fehlgeschlagen"));
    gesperrt  = true;
    sperreBis = jetzt + 60000;
}

}   // namespace Lampenspeicher
