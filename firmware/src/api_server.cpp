#include "api_server.h"

#include <ArduinoJson.h>
#include <WebServer.h>
#include <WiFi.h>

#include "config.h"
#include "lampen.h"
#include "lampenzustand.h"
#include "web_assets.h"
#include "wlan_portal.h"

namespace {

WebServer server(80);

// --- Antworten -------------------------------------------------------------

void sendeJson(int code, const JsonDocument &doc)
{
    String text;
    serializeJson(doc, text);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(code, "application/json", text);
}

void sendeFehler(int code, const String &meldung)
{
    JsonDocument doc;
    doc["error"] = meldung;
    sendeJson(code, doc);
}

void sendeUnbekannteLampe(const String &bezeichner)
{
    JsonDocument doc;
    doc["error"] = "unknown lamp: " + bezeichner;
    JsonArray liste = doc["lamps"].to<JsonArray>();
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        liste.add(LAMPEN[i].id);
    }
    sendeJson(404, doc);
}

void sendeLampe(uint8_t index)
{
    JsonDocument doc;
    JsonObject   o = doc.to<JsonObject>();
    schreibeJson(Lampen::zustand(index), index, o);
    sendeJson(200, doc);
}

void fuelleLampen(JsonArray ziel)
{
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        JsonObject o = ziel.add<JsonObject>();
        schreibeJson(Lampen::zustand(i), i, o);
    }
}

void sendeAlleLampen()
{
    JsonDocument doc;
    fuelleLampen(doc["lamps"].to<JsonArray>());
    sendeJson(200, doc);
}

void sendeSeite(const uint8_t *daten, size_t laenge, const char *etag)
{
    if (server.header("If-None-Match") == etag) {
        server.send(304);
        return;
    }
    server.sendHeader("Content-Encoding", "gzip");
    server.sendHeader("ETag", etag);
    server.sendHeader("Cache-Control", "no-cache");
    server.send_P(200, "text/html", (PGM_P) daten, laenge);
}

// --- JSON aus dem Rumpf lesen ----------------------------------------------

bool leseRumpf(JsonDocument &doc)
{
    const String rumpf = server.arg("plain");
    if (rumpf.isEmpty()) {
        sendeFehler(400, "request body is empty");
        return false;
    }

    const DeserializationError fehler = deserializeJson(doc, rumpf);
    if (fehler) {
        sendeFehler(400, String("invalid json: ") + fehler.c_str());
        return false;
    }
    if (!doc.is<JsonObject>()) {
        sendeFehler(400, "request body must be a json object");
        return false;
    }
    return true;
}

// --- feste Routen ----------------------------------------------------------

void handleStatus()
{
    JsonDocument doc;

    doc["device"]   = SSL_HOSTNAME;
    doc["firmware"] = SSL_FIRMWARE;
    doc["uptime"]   = millis() / 1000;
    doc["heap"]     = ESP.getFreeHeap();
    doc["psram"]    = ESP.getPsramSize();

    JsonObject wlan = doc["wifi"].to<JsonObject>();
    wlan["mode"]      = Wlan::imApModus() ? "ap" : "sta";
    wlan["ssid"]      = Wlan::imApModus() ? Wlan::apName() : Wlan::ssid();
    wlan["ip"]        = Wlan::ip().toString();
    wlan["rssi"]      = Wlan::rssi();
    wlan["connected"] = Wlan::verbunden();
    wlan["hostname"]  = String(SSL_HOSTNAME) + ".local";

    JsonObject pwm = doc["pwm"].to<JsonObject>();
    pwm["baseFrequency"] = PWM_GRUNDFREQUENZ;
    pwm["resolution"]    = PWM_AUFLOESUNG_BIT;
    pwm["activeLow"]     = LAMPE_LOW_AKTIV;

    JsonObject sweep = doc["sweep"].to<JsonObject>();
    sweep["running"] = Lampen::durchlaufLaeuft();
    sweep["channel"] = Lampen::durchlaufKanal();

    // Anzeigereihenfolge der Saeule von oben nach unten - das Web-Interface
    // soll die Reihenfolge nicht selbst kennen muessen.
    JsonArray reihenfolge = doc["order"].to<JsonArray>();
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        reihenfolge.add(LAMPEN[LAMPEN_UI_REIHENFOLGE[i]].id);
    }

    fuelleLampen(doc["lamps"].to<JsonArray>());
    sendeJson(200, doc);
}

// POST /api/lamps - mehrere Lampen in einem Zug.
//
// Erst alle Aenderungen pruefen, dann alle uebernehmen: sonst stuenden bei
// einem Tippfehler im dritten Eintrag die ersten beiden schon auf neuen Werten.
void handleLampenSammel()
{
    JsonDocument doc;
    if (!leseRumpf(doc)) return;

    Lampenzustand neu[LAMPEN_ANZAHL];
    bool          betroffen[LAMPEN_ANZAHL] = { false };
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        neu[i] = Lampen::zustand(i);
    }

    for (JsonPairConst eintrag : doc.as<JsonObjectConst>()) {
        const String bezeichner = eintrag.key().c_str();
        const int    index      = Lampen::findeIndex(bezeichner);
        if (index < 0) {
            sendeUnbekannteLampe(bezeichner);
            return;
        }
        if (!eintrag.value().is<JsonObjectConst>()) {
            sendeFehler(400, "value for " + bezeichner + " must be an object");
            return;
        }

        const Pruefergebnis e = uebernimmJson(neu[index], eintrag.value().as<JsonObjectConst>(), false);
        if (!e.ok) {
            sendeFehler(400, "lamp " + bezeichner + ": " + e.fehler);
            return;
        }
        betroffen[index] = true;
    }

    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        if (betroffen[i]) Lampen::setzeZustand(i, neu[i]);
    }
    sendeAlleLampen();
}

// POST /api/lamps/all - dieselbe Teilaenderung auf alle fuenf.
void handleLampenAlle()
{
    JsonDocument doc;
    if (!leseRumpf(doc)) return;

    Lampenzustand neu[LAMPEN_ANZAHL];
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        neu[i] = Lampen::zustand(i);
        const Pruefergebnis e = uebernimmJson(neu[i], doc.as<JsonObjectConst>(), false);
        if (!e.ok) {
            sendeFehler(400, e.fehler);
            return;
        }
    }

    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        Lampen::setzeZustand(i, neu[i]);
    }
    sendeAlleLampen();
}

void handleAllesAus()
{
    for (uint8_t i = 0; i < LAMPEN_ANZAHL; i++) {
        Lampenzustand z = Lampen::zustand(i);
        z.an = false;
        Lampen::setzeZustand(i, z);
    }
    sendeAlleLampen();
}

void handleScan()
{
    JsonDocument doc;
    JsonArray    netze = doc["networks"].to<JsonArray>();

    const int anzahl = WiFi.scanNetworks();
    for (int i = 0; i < anzahl; i++) {
        JsonObject n = netze.add<JsonObject>();
        n["ssid"]      = WiFi.SSID(i);
        n["rssi"]      = WiFi.RSSI(i);
        n["encrypted"] = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
    }
    WiFi.scanDelete();

    sendeJson(200, doc);
}

void handleConfig()
{
    JsonDocument doc;
    doc["hostname"]      = SSL_HOSTNAME;
    doc["mode"]          = Wlan::imApModus() ? "ap" : "sta";
    doc["ssid"]          = Wlan::ssid();
    doc["apName"]        = Wlan::apName();
    doc["baseFrequency"] = PWM_GRUNDFREQUENZ;
    sendeJson(200, doc);
}

void handleConfigWlan()
{
    JsonDocument doc;
    if (!leseRumpf(doc)) return;

    const String neueSsid = doc["ssid"] | "";
    const String passwort = doc["password"] | "";

    String fehler;
    if (!Wlan::speichereZugang(neueSsid, passwort, fehler)) {
        sendeFehler(400, fehler);
        return;
    }

    JsonDocument antwort;
    antwort["ok"]   = true;
    antwort["ssid"] = neueSsid;
    antwort["ip"]   = Wlan::ip().toString();
    sendeJson(200, antwort);
}

void handleSweep()
{
    Lampen::starteDurchlauf();

    JsonDocument doc;
    doc["ok"]       = true;
    doc["holdMs"]   = DURCHLAUF_MS;
    doc["channels"] = LAMPEN_ANZAHL;
    sendeJson(200, doc);
}

void handleReset()
{
    Wlan::loescheZugang();

    JsonDocument doc;
    doc["ok"]      = true;
    doc["message"] = "wifi credentials cleared, rebooting";
    sendeJson(200, doc);

    delay(250);
    ESP.restart();
}

void handleReboot()
{
    JsonDocument doc;
    doc["ok"] = true;
    sendeJson(200, doc);

    delay(250);
    ESP.restart();
}

// --- dynamische Routen -----------------------------------------------------

// /api/lamps/<bezeichner>            GET, PATCH, PUT
// /api/lamps/<bezeichner>/<aktion>   GET   (on, off, toggle)
bool behandleLampenPfad(const String &uri)
{
    const String rest = uri.substring(strlen("/api/lamps/"));
    if (rest.isEmpty()) {
        return false;
    }

    const int    schraegstrich = rest.indexOf('/');
    const String bezeichner    = schraegstrich < 0 ? rest : rest.substring(0, schraegstrich);
    const String aktion        = schraegstrich < 0 ? String() : rest.substring(schraegstrich + 1);

    const int index = Lampen::findeIndex(bezeichner);
    if (index < 0) {
        sendeUnbekannteLampe(bezeichner);
        return true;
    }

    Lampenzustand zustand = Lampen::zustand(index);

    // Kurzbefehl: /api/lamps/red/on?brightness=50&effect=blink
    if (!aktion.isEmpty()) {
        if (server.method() != HTTP_GET) {
            sendeFehler(405, "shortcut " + aktion + " is GET only");
            return true;
        }

        if (aktion == "on") {
            zustand.an = true;
        } else if (aktion == "off") {
            zustand.an = false;
        } else if (aktion == "toggle") {
            zustand.an = !zustand.an;
        } else {
            sendeFehler(404, "unknown action: " + aktion + " (on, off, toggle)");
            return true;
        }

        // Weitere Parameter duerfen mitkommen und werden nach dem Schalten
        // angewandt - /api/lamps/red/on?brightness=20 ist damit ein Aufruf.
        const Pruefergebnis e = uebernimmQuery(zustand, server);
        if (!e.ok) {
            sendeFehler(400, e.fehler);
            return true;
        }

        Lampen::setzeZustand(index, zustand);
        sendeLampe(index);
        return true;
    }

    switch (server.method()) {
        case HTTP_GET:
            sendeLampe(index);
            return true;

        case HTTP_PATCH:
        case HTTP_PUT: {
            JsonDocument doc;
            if (!leseRumpf(doc)) return true;

            const bool          vollstaendig = server.method() == HTTP_PUT;
            const Pruefergebnis e = uebernimmJson(zustand, doc.as<JsonObjectConst>(), vollstaendig);
            if (!e.ok) {
                sendeFehler(400, e.fehler);
                return true;
            }

            Lampen::setzeZustand(index, zustand);
            sendeLampe(index);
            return true;
        }

        default:
            sendeFehler(405, "method not allowed (GET, PATCH, PUT)");
            return true;
    }
}

void handleNichtGefunden()
{
    const String uri = server.uri();

    if (server.method() == HTTP_OPTIONS) {
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.sendHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS");
        server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
        server.send(204);
        return;
    }

    if (uri.startsWith("/api/lamps/") && behandleLampenPfad(uri)) {
        return;
    }

    if (uri.startsWith("/api/")) {
        sendeFehler(404, "unknown endpoint: " + uri);
        return;
    }

    // Captive Portal: im AP-Modus wird jede sonstige Anfrage auf die
    // Konfigurationsseite umgeleitet. Die Erkennungsadressen der
    // Betriebssysteme (/generate_204, /hotspot-detect.html, /connecttest.txt,
    // /ncsi.txt, /canonical.html) laufen ebenfalls hier durch. Wichtig ist, sie
    // NICHT mit 204 oder "Success" zu beantworten - sonst haelt das System die
    // Verbindung fuer voll funktionsfaehig und zeigt gar kein Portal an.
    if (Wlan::imApModus()) {
        server.sendHeader("Location", "http://" + Wlan::ip().toString() + "/setup", true);
        server.send(302, "text/plain", "");
        return;
    }

    server.send(404, "text/plain", "not found");
}

}   // namespace

namespace Api {

void begin()
{
    // Damit sendeSeite() den ETag des Browsers auswerten kann. Der WebServer
    // verwirft alle nicht ausdruecklich angemeldeten Header.
    static const char *beobachteteHeader[] = { "If-None-Match" };
    server.collectHeaders(beobachteteHeader, 1);

    server.on("/",      HTTP_GET, [] { sendeSeite(INDEX_HTML_GZ, INDEX_HTML_GZ_LEN, INDEX_HTML_ETAG); });
    server.on("/setup", HTTP_GET, [] { sendeSeite(SETUP_HTML_GZ, SETUP_HTML_GZ_LEN, SETUP_HTML_ETAG); });

    server.on("/api/status",      HTTP_GET,  handleStatus);
    server.on("/api/lamps",       HTTP_GET,  sendeAlleLampen);
    server.on("/api/lamps",       HTTP_POST, handleLampenSammel);
    server.on("/api/lamps/all",   HTTP_POST, handleLampenAlle);
    server.on("/api/off",         HTTP_GET,  handleAllesAus);
    server.on("/api/scan",        HTTP_GET,  handleScan);
    server.on("/api/config",      HTTP_GET,  handleConfig);
    server.on("/api/config/wifi", HTTP_POST, handleConfigWlan);
    server.on("/api/sweep",       HTTP_GET,  handleSweep);
    server.on("/api/sweep",       HTTP_POST, handleSweep);
    server.on("/api/reset",       HTTP_POST, handleReset);
    server.on("/api/reboot",      HTTP_POST, handleReboot);

    server.onNotFound(handleNichtGefunden);
    server.begin();

    Serial.println(F("[api] HTTP-Server laeuft auf Port 80"));
}

void tick()
{
    server.handleClient();
}

}   // namespace Api
