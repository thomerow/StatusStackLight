#include "wlan_portal.h"

#include <DNSServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WiFi.h>

#include "config.h"

namespace {

Preferences  speicher;
DNSServer    dns;

bool     apModus       = false;
bool     mdnsLaeuft    = false;
String   gespeicherteSsid;
String   gespeichertesPasswort;
uint32_t getrenntSeit  = 0;   // millis() des Verbindungsverlusts, 0 = verbunden

const char *NVS_BEREICH = "ssl-wlan";

String macSuffix()
{
    uint8_t mac[6];
    WiFi.macAddress(mac);
    char puffer[5];
    snprintf(puffer, sizeof(puffer), "%02X%02X", mac[4], mac[5]);
    return String(puffer);
}

void starteMdns()
{
    if (mdnsLaeuft) {
        MDNS.end();
    }
    // mDNS ist nicht case-sensitiv: aus SSL_HOSTNAME wird statusstacklight.local
    if (MDNS.begin(SSL_HOSTNAME)) {
        MDNS.addService("http", "tcp", 80);
        mdnsLaeuft = true;
        Serial.printf("[wlan] mDNS aktiv: http://%s.local/\n", SSL_HOSTNAME);
    } else {
        Serial.println(F("[wlan] mDNS konnte nicht gestartet werden"));
    }
}

// Versucht eine Verbindung und blockiert dabei bis zum Timeout.
bool verbinde(const String &ssid, const String &passwort, uint32_t timeout)
{
    if (ssid.isEmpty()) {
        return false;
    }

    Serial.printf("[wlan] verbinde mit '%s' ...\n", ssid.c_str());

    // Der Hostname muss VOR WiFi.begin() stehen, sonst traegt sich das Geraet
    // beim DHCP-Server unter "espressif" ein und taucht im Router mit diesem
    // Namen auf.
    WiFi.setHostname(SSL_HOSTNAME);
    WiFi.begin(ssid.c_str(), passwort.c_str());

    const uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < timeout) {
        delay(250);
    }

    return WiFi.status() == WL_CONNECTED;
}

void starteAp()
{
    apModus = true;

    WiFi.mode(WIFI_AP);
    const String name = Wlan::apName();
    WiFi.softAP(name.c_str());

    // Wildcard: jede Namensanfrage wird auf die AP-Adresse beantwortet. Genau
    // das laesst die Betriebssysteme ein Captive Portal erkennen und die
    // Konfigurationsseite von selbst aufgehen.
    dns.start(53, "*", WiFi.softAPIP());

    Serial.printf("[wlan] Konfig-AP '%s' offen, http://%s/\n",
                  name.c_str(), WiFi.softAPIP().toString().c_str());
}

}   // namespace

namespace Wlan {

void begin()
{
    speicher.begin(NVS_BEREICH, true);
    gespeicherteSsid      = speicher.getString("ssid", "");
    gespeichertesPasswort = speicher.getString("pass", "");
    speicher.end();

    if (gespeicherteSsid.isEmpty()) {
        Serial.println(F("[wlan] keine Zugangsdaten hinterlegt"));
        starteAp();
        return;
    }

    WiFi.mode(WIFI_STA);
    if (verbinde(gespeicherteSsid, gespeichertesPasswort, WLAN_VERBINDE_TIMEOUT)) {
        apModus = false;
        Serial.printf("[wlan] verbunden, IP %s, RSSI %d dBm\n",
                      WiFi.localIP().toString().c_str(), WiFi.RSSI());
        starteMdns();
    } else {
        Serial.println(F("[wlan] Verbindung fehlgeschlagen"));
        starteAp();
    }
}

void tick()
{
    if (apModus) {
        dns.processNextRequest();
        return;
    }

    if (WiFi.status() == WL_CONNECTED) {
        if (getrenntSeit != 0) {
            Serial.printf("[wlan] wieder verbunden, IP %s\n", WiFi.localIP().toString().c_str());
            getrenntSeit = 0;
            starteMdns();
        }
        return;
    }

    if (getrenntSeit == 0) {
        getrenntSeit = millis();
        Serial.println(F("[wlan] Verbindung verloren, versuche erneut"));
        WiFi.reconnect();
        return;
    }

    // Bleibt es laenger aussichtslos, ist der Konfig-AP die bessere Anzeige als
    // ein Geraet, das still vor sich hin blinkt und nicht erreichbar ist.
    if (millis() - getrenntSeit > WLAN_NEUSTART_NACH) {
        Serial.println(F("[wlan] dauerhaft keine Verbindung - oeffne Konfig-AP"));
        starteAp();
    }
}

bool imApModus()  { return apModus; }
bool verbunden()  { return WiFi.status() == WL_CONNECTED; }

String ssid()
{
    return apModus ? gespeicherteSsid : WiFi.SSID();
}

IPAddress ip()
{
    return apModus ? WiFi.softAPIP() : WiFi.localIP();
}

int rssi()
{
    return apModus ? 0 : WiFi.RSSI();
}

String apName()
{
    return String(SSL_AP_PRAEFIX) + "-" + macSuffix();
}

bool speichereZugang(const String &neueSsid, const String &passwort, String &fehler)
{
    if (neueSsid.isEmpty()) {
        fehler = "ssid must not be empty";
        return false;
    }

    // Im AP-Modus parallel als Station verbinden, damit die Konfigurationsseite
    // waehrend des Versuchs erreichbar bleibt und das Ergebnis melden kann.
    if (apModus) {
        WiFi.mode(WIFI_AP_STA);
    }

    if (!verbinde(neueSsid, passwort, WLAN_VERBINDE_TIMEOUT)) {
        fehler = "could not connect to '" + neueSsid + "' - check password and range";
        WiFi.disconnect(false, true);
        if (apModus) {
            WiFi.mode(WIFI_AP);
        }
        return false;
    }

    speicher.begin(NVS_BEREICH, false);
    speicher.putString("ssid", neueSsid);
    speicher.putString("pass", passwort);
    speicher.end();

    gespeicherteSsid      = neueSsid;
    gespeichertesPasswort = passwort;

    if (apModus) {
        dns.stop();
        WiFi.mode(WIFI_STA);
        apModus = false;
    }
    getrenntSeit = 0;
    starteMdns();

    Serial.printf("[wlan] Zugangsdaten gespeichert, IP %s\n", WiFi.localIP().toString().c_str());
    return true;
}

void loescheZugang()
{
    speicher.begin(NVS_BEREICH, false);
    speicher.clear();
    speicher.end();
    gespeicherteSsid      = "";
    gespeichertesPasswort = "";
    Serial.println(F("[wlan] Zugangsdaten geloescht"));
}

}   // namespace Wlan
