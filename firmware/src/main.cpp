// StatusStackLight - Firmware fuer die 5-Lampen-Signalsaeule.
//
// Aufbau:
//   lampen.*         LEDC-Ansteuerung und Effekt-Engine (eigener Task, Core 0)
//   lampenzustand.*  Zustand einer Lampe, Pruefung und JSON
//   lampenspeicher.* letzter Lampenzustand im NVS, ueberlebt Neustarts
//   wlan_portal.*    Zugangsdaten, STA-Verbindung, Konfig-AP mit Captive Portal
//   api_server.*     HTTP-Routen und die eingebetteten Web-Seiten
//
// Pinbelegung und alles sonst Einstellbare: include/config.h

#include <Arduino.h>

#include "api_server.h"
#include "config.h"
#include "lampen.h"
#include "lampenspeicher.h"
#include "wlan_portal.h"

namespace {

void zeigeStartmeldung()
{
    Serial.println();
    Serial.println(F("========================================"));
    Serial.printf( "  %s  Firmware %s\n", SSL_HOSTNAME, SSL_FIRMWARE);
    Serial.println(F("========================================"));
    Serial.printf( "  Chip      : %s, %u MHz, %u Kerne\n",
                   ESP.getChipModel(), ESP.getCpuFreqMHz(), ESP.getChipCores());
    Serial.printf( "  Flash     : %u MB\n", ESP.getFlashChipSize() / (1024 * 1024));
    // Zeigt 0, wenn board_build.arduino.memory_type nicht zum Modul passt -
    // beim N16R8 muessen hier rund 8 MB stehen.
    Serial.printf( "  PSRAM     : %u Bytes\n", ESP.getPsramSize());
    Serial.printf( "  PWM       : %u Hz, %u Bit, %s-aktiv\n",
                   PWM_GRUNDFREQUENZ, PWM_AUFLOESUNG_BIT,
                   LAMPE_LOW_AKTIV ? "LOW" : "HIGH");
    Serial.println(F("  Kanaele   :"));
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        Serial.printf("    %u  GPIO %2u  %-6s (%s)\n",
                      i + 1, LAMPEN[i].gpio, LAMPEN[i].id, LAMPEN[i].name);
    }
    Serial.println(F("========================================"));
}

}   // namespace

void setup()
{
    // Als allererstes, noch vor der seriellen Ausgabe: die GPIOs auf den
    // Aus-Pegel legen. Nach dem Reset sind sie hochohmig, und beim LOW-aktiven
    // MOSFET-Modul heisst das im Zweifel "an" - die Saeule wuerde bei jedem
    // Start kurz aufleuchten.
    Lampen::begin();

    Serial.begin(115200);
#if ARDUINO_USB_CDC_ON_BOOT
    // Native USB-Buchse: der Host muss den Port erst aufzaehlen, vorher geht
    // jede Ausgabe verloren. Bei der UART-Buchse entfaellt das Warten.
    const uint32_t start = millis();
    while (!Serial && millis() - start < 3000) {
        delay(10);
    }
#endif
    delay(200);

    zeigeStartmeldung();

    Lampenspeicher::lade();
    // Vor dem Effekt-Task, sonst blitzte zwischen seinem Start und
    // Wlan::begin() kurz der gespeicherte Zustand auf.
    Lampen::setzeSystemanzeige(Lampen::Systemanzeige::Verbinden);
    Lampen::starteEffektTask();
    Wlan::begin();
    Api::begin();

    Serial.println(F("[start] bereit"));
}

void loop()
{
    Wlan::tick();
    Api::tick();
    Lampenspeicher::tick();

    // Die Lampen haengen nicht an dieser Schleife - sie werden vom Effekt-Task
    // auf Core 0 bedient. Das kurze Warten gibt nur dem Leerlauf-Task Luft.
    delay(2);
}
