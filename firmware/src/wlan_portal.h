// wlan_portal.h - Netzwerkanbindung und Erstkonfiguration.
//
// Zugangsdaten stehen nicht im Quelltext, sondern im NVS. Ist dort nichts
// hinterlegt oder scheitert die Verbindung, spannt das Geraet einen offenen
// Accesspoint mit Captive Portal auf.

#pragma once

#include <Arduino.h>
#include <IPAddress.h>

namespace Wlan {

void begin();

// Aus loop() aufrufen: bedient den DNS-Server des Konfig-APs und kuemmert sich
// um den Wiederaufbau einer verlorenen Verbindung.
void tick();

bool      imApModus();
bool      verbunden();
String    ssid();          // konfigurierte bzw. verbundene SSID
IPAddress ip();            // STA-Adresse, im AP-Modus die AP-Adresse
int       rssi();
String    apName();        // StatusStackLight-XXXX

// Probiert die Zugangsdaten aus und speichert sie nur, wenn die Verbindung
// zustande kommt.
//
// Das ist der Grund fuer den Umweg: wer sich bei der Eingabe vertippt und die
// Daten wuerden blind gespeichert, faende ein Geraet vor, das beim naechsten
// Start weder ins WLAN kommt noch - bis zum Timeout - seinen Konfig-AP zeigt.
bool speichereZugang(const String &neueSsid, const String &passwort, String &fehler);

// Loescht die gespeicherten Daten. Wirkt nach dem naechsten Neustart.
void loescheZugang();

}   // namespace Wlan
