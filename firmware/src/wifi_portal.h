// wifi_portal.h - network connection and first-time setup.
//
// Credentials are not in the source but in NVS. If nothing is stored there or
// the connection fails, the device opens an open access point with a captive
// portal.

#pragma once

#include <Arduino.h>
#include <IPAddress.h>

namespace Network {

void begin();

// Call from loop(): serves the DNS server of the setup AP and takes care of
// re-establishing a lost connection.
void tick();

bool      inApMode();
bool      connected();
String    ssid();          // configured or connected SSID
IPAddress ip();            // station address, the AP address in AP mode
int       rssi();
String    apName();        // StatusStackLight-XXXX

// Tries the credentials and stores them only if the connection succeeds.
//
// That is the reason for the detour: if a typo were stored blindly, you would
// find a device that on its next start neither joins the WiFi nor - until
// the timeout - shows its setup AP.
bool saveCredentials(const String &newSsid, const String &password, String &error);

// Deletes the stored credentials. Takes effect after the next restart.
void clearCredentials();

}   // namespace Network
