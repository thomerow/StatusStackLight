#include "wifi_portal.h"

#include <DNSServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WiFi.h>

#include "config.h"
#include "lamps.h"

namespace {

Preferences  prefs;
DNSServer    dns;

bool     apMode          = false;
bool     mdnsRunning     = false;
String   storedSsid;
String   storedPassword;
uint32_t disconnectedAt  = 0;   // millis() of the connection loss, 0 = connected

// The namespace is German for historical reasons. Renaming it would lose the
// credentials stored on existing devices.
const char *NVS_NAMESPACE = "ssl-wlan";

String macSuffix()
{
    uint8_t mac[6];
    WiFi.macAddress(mac);
    char buffer[5];
    snprintf(buffer, sizeof(buffer), "%02X%02X", mac[4], mac[5]);
    return String(buffer);
}

void startMdns()
{
    if (mdnsRunning) {
        MDNS.end();
    }
    // mDNS is not case-sensitive: SSL_HOSTNAME becomes statusstacklight.local
    if (MDNS.begin(SSL_HOSTNAME)) {
        MDNS.addService("http", "tcp", 80);
        mdnsRunning = true;
        Serial.printf("[wifi] mDNS active: http://%s.local/\n", SSL_HOSTNAME);
    } else {
        Serial.println(F("[wifi] could not start mDNS"));
    }
}

// Attempts a connection and blocks until the timeout.
bool connect(const String &ssid, const String &password, uint32_t timeout)
{
    if (ssid.isEmpty()) {
        return false;
    }

    Serial.printf("[wifi] connecting to '%s' ...\n", ssid.c_str());

    // The hostname must be set BEFORE WiFi.begin(), otherwise the device
    // registers with the DHCP server as "espressif" and shows up in the router
    // under that name.
    WiFi.setHostname(SSL_HOSTNAME);
    WiFi.begin(ssid.c_str(), password.c_str());

    const uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < timeout) {
        delay(250);
    }

    return WiFi.status() == WL_CONNECTED;
}

void startAp()
{
    apMode = true;
    Lamps::setSystemDisplay(Lamps::SystemDisplay::Portal);

    WiFi.mode(WIFI_AP);
    const String name = Network::apName();
    WiFi.softAP(name.c_str());

    // Wildcard: every name lookup is answered with the AP address. This is
    // exactly what makes operating systems detect a captive portal and open
    // the setup page by themselves.
    dns.start(53, "*", WiFi.softAPIP());

    Serial.printf("[wifi] setup AP '%s' open, http://%s/\n",
                  name.c_str(), WiFi.softAPIP().toString().c_str());
}

}   // namespace

namespace Network {

void begin()
{
    prefs.begin(NVS_NAMESPACE, true);
    storedSsid     = prefs.getString("ssid", "");
    storedPassword = prefs.getString("pass", "");
    prefs.end();

    if (storedSsid.isEmpty()) {
        Serial.println(F("[wifi] no credentials stored"));
        startAp();
        return;
    }

    WiFi.mode(WIFI_STA);
    Lamps::setSystemDisplay(Lamps::SystemDisplay::Connecting);
    if (connect(storedSsid, storedPassword, WIFI_CONNECT_TIMEOUT_MS)) {
        apMode = false;
        Lamps::setSystemDisplay(Lamps::SystemDisplay::Connected);
        Serial.printf("[wifi] connected, IP %s, RSSI %d dBm\n",
                      WiFi.localIP().toString().c_str(), WiFi.RSSI());
        startMdns();
    } else {
        Serial.println(F("[wifi] connection failed"));
        startAp();
    }
}

void tick()
{
    if (apMode) {
        dns.processNextRequest();
        return;
    }

    if (WiFi.status() == WL_CONNECTED) {
        if (disconnectedAt != 0) {
            Serial.printf("[wifi] reconnected, IP %s\n", WiFi.localIP().toString().c_str());
            disconnectedAt = 0;
            startMdns();
        }
        return;
    }

    if (disconnectedAt == 0) {
        disconnectedAt = millis();
        Serial.println(F("[wifi] connection lost, retrying"));
        WiFi.reconnect();
        return;
    }

    // If it stays hopeless for longer, the setup AP is a better indication
    // than a device that quietly keeps blinking and cannot be reached.
    if (millis() - disconnectedAt > WIFI_PORTAL_AFTER_MS) {
        Serial.println(F("[wifi] no connection for too long - opening setup AP"));
        startAp();
    }
}

bool inApMode()   { return apMode; }
bool connected()  { return WiFi.status() == WL_CONNECTED; }

String ssid()
{
    return apMode ? storedSsid : WiFi.SSID();
}

IPAddress ip()
{
    return apMode ? WiFi.softAPIP() : WiFi.localIP();
}

int rssi()
{
    return apMode ? 0 : WiFi.RSSI();
}

String apName()
{
    return String(SSL_AP_PREFIX) + "-" + macSuffix();
}

bool saveCredentials(const String &newSsid, const String &password, String &error)
{
    if (newSsid.isEmpty()) {
        error = "ssid must not be empty";
        return false;
    }

    // In AP mode, connect as a station in parallel, so the setup page stays
    // reachable during the attempt and can report the result.
    // The boot display only exists in the setup AP: during normal operation
    // the Claude status stays visible.
    if (apMode) {
        WiFi.mode(WIFI_AP_STA);
        Lamps::setSystemDisplay(Lamps::SystemDisplay::Connecting);
    }

    if (!connect(newSsid, password, WIFI_CONNECT_TIMEOUT_MS)) {
        error = "could not connect to '" + newSsid + "' - check password and range";
        WiFi.disconnect(false, true);
        if (apMode) {
            WiFi.mode(WIFI_AP);
            Lamps::setSystemDisplay(Lamps::SystemDisplay::Portal);
        } else {
            // During normal operation, the attempt has dropped the existing
            // connection. Without this step, tick() would keep retrying the
            // credentials that just failed via reconnect() and open the setup
            // AP after WIFI_PORTAL_AFTER_MS, although the old credentials are
            // still stored.
            Serial.println(F("[wifi] returning to the previous network"));
            if (connect(storedSsid, storedPassword, WIFI_CONNECT_TIMEOUT_MS)) {
                startMdns();
            }
            // If that fails too, tick() takes over as with any other
            // connection loss - now with the old credentials.
            disconnectedAt = 0;
        }
        return false;
    }

    prefs.begin(NVS_NAMESPACE, false);
    prefs.putString("ssid", newSsid);
    prefs.putString("pass", password);
    prefs.end();

    storedSsid     = newSsid;
    storedPassword = password;

    if (apMode) {
        dns.stop();
        WiFi.mode(WIFI_STA);
        apMode = false;
        Lamps::setSystemDisplay(Lamps::SystemDisplay::Connected);
    }
    disconnectedAt = 0;
    startMdns();

    Serial.printf("[wifi] credentials saved, IP %s\n", WiFi.localIP().toString().c_str());
    return true;
}

void clearCredentials()
{
    prefs.begin(NVS_NAMESPACE, false);
    prefs.clear();
    prefs.end();
    storedSsid     = "";
    storedPassword = "";
    Serial.println(F("[wifi] credentials deleted"));
}

}   // namespace Network
