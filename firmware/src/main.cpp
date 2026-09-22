// StatusStackLight - firmware for the 5-lamp stack light.
//
// Structure:
//   lamps.*        LEDC drive and effect engine (own task, core 0)
//   lamp_state.*   state of a lamp, validation and JSON
//   lamp_store.*   last lamp state in NVS, survives restarts
//   wifi_portal.*  credentials, station connection, setup AP with captive portal
//   relay_client.* relay mode: fetches the lamp state from a relay server
//   api_server.*   HTTP routes and the embedded web pages
//
// Pin assignment and everything else that is configurable: include/config.h

#include <Arduino.h>

#include "api_server.h"
#include "config.h"
#include "lamp_store.h"
#include "lamps.h"
#include "relay_client.h"
#include "wifi_portal.h"

namespace {

void printBanner()
{
    Serial.println();
    Serial.println(F("========================================"));
    Serial.printf( "  %s  firmware %s\n", SSL_HOSTNAME, SSL_FIRMWARE);
    Serial.println(F("========================================"));
    Serial.printf( "  Chip      : %s, %u MHz, %u cores\n",
                   ESP.getChipModel(), ESP.getCpuFreqMHz(), ESP.getChipCores());
    Serial.printf( "  Flash     : %u MB\n", ESP.getFlashChipSize() / (1024 * 1024));
    // Shows 0 if board_build.arduino.memory_type does not match the module -
    // with the N16R8 this must be about 8 MB.
    Serial.printf( "  PSRAM     : %u bytes\n", ESP.getPsramSize());
    Serial.printf( "  PWM       : %u Hz, %u bits, active %s\n",
                   PWM_BASE_FREQUENCY, PWM_RESOLUTION_BITS,
                   LAMP_ACTIVE_LOW ? "LOW" : "HIGH");
    Serial.println(F("  Channels  :"));
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        Serial.printf("    %u  GPIO %2u  %s\n", i + 1, LAMPS[i].gpio, LAMPS[i].id);
    }
    Serial.println(F("========================================"));
}

}   // namespace

void setup()
{
    // First of all, even before serial output: drive the GPIOs to the off
    // level. After reset they are high-impedance, and with the active-LOW
    // MOSFET module that may well mean "on" - the stack light would flash
    // briefly on every start.
    Lamps::begin();

    Serial.begin(115200);
#if ARDUINO_USB_CDC_ON_BOOT
    // Native USB port: the host has to enumerate the port first, any output
    // before that is lost. With the UART port there is no need to wait.
    const uint32_t start = millis();
    while (!Serial && millis() - start < 3000) {
        delay(10);
    }
#endif
    delay(200);

    printBanner();

    LampStore::load();
    // Before the effect task, otherwise the stored state would flash briefly
    // between its start and Network::begin().
    Lamps::setSystemDisplay(Lamps::SystemDisplay::Connecting);
    Lamps::startEffectTask();
    Network::begin();
    Relay::begin();
    Api::begin();

    Serial.println(F("[start] ready"));
}

void loop()
{
    Network::tick();
    Api::tick();
    LampStore::tick();

    // The lamps do not depend on this loop - they are driven by the effect
    // task on core 0. The short wait only gives the idle task some air.
    delay(2);
}
