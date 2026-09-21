#include "lampen.h"

#include <math.h>

namespace {

Lampenzustand zustaende[LAMPEN_ANZAHL];
uint8_t       niveau[LAMPEN_ANZAHL] = { 0 };       // zuletzt ausgegebene Helligkeit in %
uint16_t      gammaTabelle[HELLIGKEIT_MAX + 1];    // Prozent -> Registerwert

// Kurze kritische Abschnitte um die Zustandsstruktur. Geschrieben wird aus dem
// Webserver (Core 1), gelesen aus dem Effekt-Task (Core 0).
portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

volatile bool    durchlaufAngefordert = false;
volatile int     durchlaufAktuell     = 0;   // 1...5 waehrend des Durchlaufs

void baueGammaTabelle()
{
    for (int i = 0; i <= HELLIGKEIT_MAX; i++) {
        const float anteil = (float) i / (float) HELLIGKEIT_MAX;
        gammaTabelle[i] = (uint16_t) lroundf(powf(anteil, GAMMA) * (float) PWM_MAX);
    }
}

// Der einzige Ort, an dem die LOW-aktive Ansteuerung invertiert wird.
//
// Alles ueber dieser Funktion - API, Web-Interface, Effekt-Engine - rechnet in
// "0 = aus, 100 = volle Helligkeit". Wer die Invertierung an einer zweiten
// Stelle nachbaut, hat sie beim naechsten Umbau garantiert nur an einer von
// beiden korrigiert.
void schreibePwm(uint8_t index, uint8_t prozent)
{
    if (prozent > HELLIGKEIT_MAX) prozent = HELLIGKEIT_MAX;

    uint32_t wert = gammaTabelle[prozent];
    if (LAMPE_LOW_AKTIV) {
        wert = PWM_MAX - wert;
    }

    ledcWrite(index, wert);
    niveau[index] = prozent;
}

// Berechnet die momentane Helligkeit einer Lampe aus ihrem Zustand.
// `sekunden` ist eine gemeinsame Zeitbasis fuer alle Lampen - nur dadurch
// blinken zwei Lampen gleicher Frequenz synchron statt auseinanderzulaufen.
uint8_t berechneNiveau(const Lampenzustand &z, float sekunden)
{
    if (!z.an || z.helligkeit == 0) {
        return 0;
    }

    switch (z.effekt) {
        case Effekt::Blinken: {
            const float phase = fmodf(sekunden * z.frequenz, 1.0f);
            return (phase < (float) z.tastgrad / 100.0f) ? z.helligkeit : 0;
        }
        case Effekt::Pulsieren: {
            const float phase = fmodf(sekunden * z.frequenz, 1.0f);
            // Kosinus statt Dreieck: das Auge nimmt den weichen Umkehrpunkt
            // als "Atmen" wahr, ein Dreieck wirkt an den Spitzen abgehackt.
            const float f = 0.5f - 0.5f * cosf(2.0f * PI * phase);
            return (uint8_t) lroundf(f * (float) z.helligkeit);
        }
        default:
            return z.helligkeit;
    }
}

void fuehreDurchlaufAus()
{
    Lampenzustand gemerkt[LAMPEN_ANZAHL];
    taskENTER_CRITICAL(&mux);
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) gemerkt[i] = zustaende[i];
    taskEXIT_CRITICAL(&mux);

    Serial.println(F("[durchlauf] Kanal-Durchlauf gestartet"));

    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        durchlaufAktuell = i + 1;
        for (uint8_t j = 0; j < LAMPEN_ANZAHL; j++) {
            schreibePwm(j, j == i ? HELLIGKEIT_MAX : 0);
        }
        Serial.printf("[durchlauf] Kanal %u  GPIO %2u  erwartet: %s\n",
                      i + 1, LAMPEN[i].gpio, LAMPEN[i].name);
        vTaskDelay(pdMS_TO_TICKS(DURCHLAUF_MS));
    }

    durchlaufAktuell = 0;
    taskENTER_CRITICAL(&mux);
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) zustaende[i] = gemerkt[i];
    taskEXIT_CRITICAL(&mux);

    Serial.println(F("[durchlauf] fertig, vorheriger Zustand wiederhergestellt"));
}

void effektTask(void *)
{
    const TickType_t takt = pdMS_TO_TICKS(1000 / EFFEKT_TAKT_HZ);
    TickType_t       letzter = xTaskGetTickCount();

    for (;;) {
        if (durchlaufAngefordert) {
            durchlaufAngefordert = false;
            fuehreDurchlaufAus();
            letzter = xTaskGetTickCount();
        }

        // Gemeinsame Zeitbasis. millis() laeuft nach 49 Tagen ueber; fmodf()
        // unten macht den Sprung unkritisch - er kostet einen einzigen
        // verschluckten Blinktakt, kein Fehlverhalten.
        const float sekunden = (float) millis() / 1000.0f;

        Lampenzustand kopie[LAMPEN_ANZAHL];
        taskENTER_CRITICAL(&mux);
        for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) kopie[i] = zustaende[i];
        taskEXIT_CRITICAL(&mux);

        for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
            schreibePwm(i, berechneNiveau(kopie[i], sekunden));
        }

        vTaskDelayUntil(&letzter, takt);
    }
}

}   // namespace

namespace Lampen {

void begin()
{
    baueGammaTabelle();

    // Reihenfolge ist hier entscheidend.
    //
    // Nach dem Reset sind die GPIOs hochohmig. Beim LOW-aktiven MOSFET-Modul
    // heisst das: undefiniert, im Zweifel an - die Saeule leuchtet waehrend des
    // Bootens kurz auf. Deshalb erst von Hand auf den Aus-Pegel legen und erst
    // danach LEDC anhaengen.
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        pinMode(LAMPEN[i].gpio, OUTPUT);
        digitalWrite(LAMPEN[i].gpio, LAMPE_LOW_AKTIV ? HIGH : LOW);
    }

    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        ledcSetup(i, PWM_GRUNDFREQUENZ, PWM_AUFLOESUNG_BIT);
        ledcAttachPin(LAMPEN[i].gpio, i);
        schreibePwm(i, 0);
    }
}

void starteEffektTask()
{
    // Core 0: der Arduino-Loop mit dem Webserver laeuft auf Core 1. Die
    // Trennung ist der Grund, warum der synchrone Webserver hier genuegt.
    xTaskCreatePinnedToCore(effektTask, "lampen", 4096, nullptr, 2, nullptr, 0);
}

Lampenzustand zustand(uint8_t index)
{
    Lampenzustand z;
    taskENTER_CRITICAL(&mux);
    z = zustaende[index];
    taskEXIT_CRITICAL(&mux);
    return z;
}

void setzeZustand(uint8_t index, const Lampenzustand &neu)
{
    taskENTER_CRITICAL(&mux);
    zustaende[index] = neu;
    taskEXIT_CRITICAL(&mux);
}

int findeIndex(const String &bezeichner)
{
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        if (bezeichner.equalsIgnoreCase(LAMPEN[i].id)) {
            return i;
        }
    }

    // Kanalnummer 1...5 als Zweitweg - praktisch fuer Schleifen in Skripten.
    if (bezeichner.length() == 1 && isDigit(bezeichner[0])) {
        const int nummer = bezeichner.toInt();
        if (nummer >= 1 && nummer <= LAMPEN_ANZAHL) {
            return nummer - 1;
        }
    }

    return -1;
}

uint8_t aktuellesNiveau(uint8_t index)
{
    return niveau[index];
}

void starteDurchlauf()
{
    durchlaufAngefordert = true;
}

bool durchlaufLaeuft()
{
    return durchlaufAngefordert || durchlaufAktuell != 0;
}

int durchlaufKanal()
{
    return durchlaufAktuell;
}

}   // namespace Lampen
