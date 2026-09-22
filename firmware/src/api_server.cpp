#include "api_server.h"

#include <ArduinoJson.h>
#include <WebServer.h>
#include <WiFi.h>

#include "config.h"
#include "lamp_state.h"
#include "lamps.h"
#include "relay_client.h"
#include "web_assets.h"
#include "wifi_portal.h"

namespace {

WebServer server(80);

// --- Responses -------------------------------------------------------------

void sendJson(int code, const JsonDocument &doc)
{
    String text;
    serializeJson(doc, text);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(code, "application/json", text);
}

void sendError(int code, const String &message)
{
    JsonDocument doc;
    doc["error"] = message;
    sendJson(code, doc);
}

void sendUnknownLamp(const String &identifier)
{
    JsonDocument doc;
    doc["error"] = "unknown lamp: " + identifier;
    JsonArray list = doc["lamps"].to<JsonArray>();
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        list.add(LAMPS[i].id);
    }
    sendJson(404, doc);
}

void sendLamp(uint8_t index)
{
    JsonDocument doc;
    JsonObject   o = doc.to<JsonObject>();
    writeJson(Lamps::state(index), index, o);
    sendJson(200, doc);
}

void fillLamps(JsonArray target)
{
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        JsonObject o = target.add<JsonObject>();
        writeJson(Lamps::state(i), i, o);
    }
}

void sendAllLamps()
{
    JsonDocument doc;
    fillLamps(doc["lamps"].to<JsonArray>());
    sendJson(200, doc);
}

void sendPage(const uint8_t *data, size_t length, const char *etag)
{
    if (server.header("If-None-Match") == etag) {
        server.send(304);
        return;
    }
    server.sendHeader("Content-Encoding", "gzip");
    server.sendHeader("ETag", etag);
    server.sendHeader("Cache-Control", "no-cache");
    server.send_P(200, "text/html", (PGM_P) data, length);
}

// --- Reading JSON from the body --------------------------------------------

bool readBody(JsonDocument &doc)
{
    const String body = server.arg("plain");
    if (body.isEmpty()) {
        sendError(400, "request body is empty");
        return false;
    }

    const DeserializationError error = deserializeJson(doc, body);
    if (error) {
        sendError(400, String("invalid json: ") + error.c_str());
        return false;
    }
    if (!doc.is<JsonObject>()) {
        sendError(400, "request body must be a json object");
        return false;
    }
    return true;
}

// --- Fixed routes ----------------------------------------------------------

void handleStatus()
{
    JsonDocument doc;

    doc["device"]   = SSL_HOSTNAME;
    doc["firmware"] = SSL_FIRMWARE;
    doc["uptime"]   = millis() / 1000;
    doc["heap"]     = ESP.getFreeHeap();
    doc["psram"]    = ESP.getPsramSize();

    JsonObject wifi = doc["wifi"].to<JsonObject>();
    wifi["mode"]      = Network::inApMode() ? "ap" : "sta";
    wifi["ssid"]      = Network::inApMode() ? Network::apName() : Network::ssid();
    wifi["ip"]        = Network::ip().toString();
    wifi["rssi"]      = Network::rssi();
    wifi["connected"] = Network::connected();
    wifi["hostname"]  = String(SSL_HOSTNAME) + ".local";

    JsonObject pwm = doc["pwm"].to<JsonObject>();
    pwm["baseFrequency"] = PWM_BASE_FREQUENCY;
    pwm["resolution"]    = PWM_RESOLUTION_BITS;
    pwm["activeLow"]     = LAMP_ACTIVE_LOW;

    JsonObject sweep = doc["sweep"].to<JsonObject>();
    sweep["running"] = Lamps::sweepRunning();
    sweep["channel"] = Lamps::sweepChannel();

    // While a system display is running, the lamps do not show the state from
    // /api/lamps - this field says why.
    doc["display"] = Lamps::systemDisplayName(Lamps::systemDisplay());

    Relay::writeStatus(doc["relay"].to<JsonObject>());

    // Display order of the stack light from top to bottom - the web interface
    // should not have to know the order itself.
    JsonArray order = doc["order"].to<JsonArray>();
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        order.add(LAMPS[LAMP_UI_ORDER[i]].id);
    }

    fillLamps(doc["lamps"].to<JsonArray>());
    sendJson(200, doc);
}

// POST /api/lamps - several lamps in one go.
//
// Validate all changes first, then apply them all: otherwise a typo in the
// third entry would leave the first two already set to new values.
void handleLampsBatch()
{
    JsonDocument doc;
    if (!readBody(doc)) return;

    String                 unknown;
    const ValidationResult r = Lamps::applyBatch(doc.as<JsonObjectConst>(), &unknown);
    if (!r.ok) {
        if (!unknown.isEmpty()) sendUnknownLamp(unknown);
        else                    sendError(400, r.error);
        return;
    }
    sendAllLamps();
}

// POST /api/lamps/all - the same partial change applied to all five.
void handleLampsAll()
{
    JsonDocument doc;
    if (!readBody(doc)) return;

    LampState next[LAMP_COUNT];
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        next[i] = Lamps::state(i);
        const ValidationResult r = applyJson(next[i], doc.as<JsonObjectConst>(), false);
        if (!r.ok) {
            sendError(400, r.error);
            return;
        }
    }

    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        Lamps::setState(i, next[i]);
    }
    sendAllLamps();
}

void handleAllOff()
{
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        LampState s = Lamps::state(i);
        s.on = false;
        Lamps::setState(i, s);
    }
    sendAllLamps();
}

void handleScan()
{
    JsonDocument doc;
    JsonArray    networks = doc["networks"].to<JsonArray>();

    const int count = WiFi.scanNetworks();
    for (int i = 0; i < count; i++) {
        JsonObject n = networks.add<JsonObject>();
        n["ssid"]      = WiFi.SSID(i);
        n["rssi"]      = WiFi.RSSI(i);
        n["encrypted"] = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
    }
    WiFi.scanDelete();

    sendJson(200, doc);
}

void handleConfig()
{
    JsonDocument doc;
    doc["hostname"]      = SSL_HOSTNAME;
    doc["mode"]          = Network::inApMode() ? "ap" : "sta";
    doc["ssid"]          = Network::ssid();
    doc["apName"]        = Network::apName();
    doc["baseFrequency"] = PWM_BASE_FREQUENCY;
    Relay::writeConfig(doc["relay"].to<JsonObject>());
    sendJson(200, doc);
}

// POST /api/config/relay - {"enabled": true, "url": "...", "key": "..."}.
// url and key may be left out to keep the stored values; the key is never
// sent back.
void handleConfigRelay()
{
    JsonDocument doc;
    if (!readBody(doc)) return;

    for (JsonPairConst entry : doc.as<JsonObjectConst>()) {
        const String name = entry.key().c_str();
        if (name != "enabled" && name != "url" && name != "key" && name != "keySet") {
            sendError(400, "unknown field: '" + name + "'");
            return;
        }
    }
    if (!doc["enabled"].is<bool>()) {
        sendError(400, "field 'enabled' must be true or false");
        return;
    }
    if (!doc["url"].isNull() && !doc["url"].is<const char *>()) {
        sendError(400, "field 'url' must be a string");
        return;
    }
    if (!doc["key"].isNull() && !doc["key"].is<const char *>()) {
        sendError(400, "field 'key' must be a string");
        return;
    }

    const bool   hasUrl = doc["url"].is<const char *>();
    const bool   hasKey = doc["key"].is<const char *>();
    const String url    = hasUrl ? doc["url"].as<String>() : String();
    const String key    = hasKey ? doc["key"].as<String>() : String();

    String error;
    if (!Relay::configure(doc["enabled"], hasUrl ? &url : nullptr, hasKey ? &key : nullptr, error)) {
        sendError(400, error);
        return;
    }

    JsonDocument response;
    Relay::writeConfig(response.to<JsonObject>());
    sendJson(200, response);
}

void handleConfigWifi()
{
    JsonDocument doc;
    if (!readBody(doc)) return;

    const String newSsid  = doc["ssid"] | "";
    const String password = doc["password"] | "";

    String error;
    if (!Network::saveCredentials(newSsid, password, error)) {
        sendError(400, error);
        return;
    }

    JsonDocument response;
    response["ok"]   = true;
    response["ssid"] = newSsid;
    response["ip"]   = Network::ip().toString();
    sendJson(200, response);
}

void handleSweep()
{
    Lamps::startSweep();

    JsonDocument doc;
    doc["ok"]       = true;
    doc["holdMs"]   = SWEEP_HOLD_MS;
    doc["channels"] = LAMP_COUNT;
    sendJson(200, doc);
}

void handleReset()
{
    Network::clearCredentials();

    JsonDocument doc;
    doc["ok"]      = true;
    doc["message"] = "wifi credentials cleared, rebooting";
    sendJson(200, doc);

    delay(250);
    ESP.restart();
}

void handleReboot()
{
    JsonDocument doc;
    doc["ok"] = true;
    sendJson(200, doc);

    delay(250);
    ESP.restart();
}

// --- Dynamic routes --------------------------------------------------------

// /api/lamps/<identifier>            GET, PATCH, PUT
// /api/lamps/<identifier>/<action>   GET   (on, off, toggle)
bool handleLampPath(const String &uri)
{
    const String rest = uri.substring(strlen("/api/lamps/"));
    if (rest.isEmpty()) {
        return false;
    }

    const int    slash      = rest.indexOf('/');
    const String identifier = slash < 0 ? rest : rest.substring(0, slash);
    const String action     = slash < 0 ? String() : rest.substring(slash + 1);

    const int index = Lamps::findIndex(identifier);
    if (index < 0) {
        sendUnknownLamp(identifier);
        return true;
    }

    LampState state = Lamps::state(index);

    // Shortcut: /api/lamps/red/on?brightness=50&effect=blink
    if (!action.isEmpty()) {
        if (server.method() != HTTP_GET) {
            sendError(405, "shortcut " + action + " is GET only");
            return true;
        }

        if (action == "on") {
            state.on = true;
        } else if (action == "off") {
            state.on = false;
        } else if (action == "toggle") {
            state.on = !state.on;
        } else {
            sendError(404, "unknown action: " + action + " (on, off, toggle)");
            return true;
        }

        // Further parameters may come along and are applied after switching -
        // /api/lamps/red/on?brightness=20 is a single call.
        const ValidationResult r = applyQuery(state, server);
        if (!r.ok) {
            sendError(400, r.error);
            return true;
        }

        Lamps::setState(index, state);
        sendLamp(index);
        return true;
    }

    switch (server.method()) {
        case HTTP_GET:
            sendLamp(index);
            return true;

        case HTTP_PATCH:
        case HTTP_PUT: {
            JsonDocument doc;
            if (!readBody(doc)) return true;

            const bool             complete = server.method() == HTTP_PUT;
            const ValidationResult r        = applyJson(state, doc.as<JsonObjectConst>(), complete);
            if (!r.ok) {
                sendError(400, r.error);
                return true;
            }

            Lamps::setState(index, state);
            sendLamp(index);
            return true;
        }

        default:
            sendError(405, "method not allowed (GET, PATCH, PUT)");
            return true;
    }
}

void handleNotFound()
{
    const String uri = server.uri();

    if (server.method() == HTTP_OPTIONS) {
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.sendHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS");
        server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
        server.send(204);
        return;
    }

    if (uri.startsWith("/api/lamps/") && handleLampPath(uri)) {
        return;
    }

    if (uri.startsWith("/api/")) {
        sendError(404, "unknown endpoint: " + uri);
        return;
    }

    // Captive portal: in AP mode, every other request is redirected to the
    // setup page. The connectivity check URLs of the operating systems
    // (/generate_204, /hotspot-detect.html, /connecttest.txt, /ncsi.txt,
    // /canonical.html) also end up here. It is important NOT to answer them
    // with 204 or "Success" - otherwise the system considers the connection
    // fully working and shows no portal at all.
    if (Network::inApMode()) {
        server.sendHeader("Location", "http://" + Network::ip().toString() + "/setup", true);
        server.send(302, "text/plain", "");
        return;
    }

    server.send(404, "text/plain", "not found");
}

}   // namespace

namespace Api {

void begin()
{
    // So that sendPage() can evaluate the browser's ETag. The WebServer drops
    // all headers that were not explicitly registered.
    static const char *collectedHeaders[] = { "If-None-Match" };
    server.collectHeaders(collectedHeaders, 1);

    server.on("/",      HTTP_GET, [] { sendPage(INDEX_HTML_GZ, INDEX_HTML_GZ_LEN, INDEX_HTML_ETAG); });
    server.on("/setup", HTTP_GET, [] { sendPage(SETUP_HTML_GZ, SETUP_HTML_GZ_LEN, SETUP_HTML_ETAG); });

    server.on("/api/status",      HTTP_GET,  handleStatus);
    server.on("/api/lamps",       HTTP_GET,  sendAllLamps);
    server.on("/api/lamps",       HTTP_POST, handleLampsBatch);
    server.on("/api/lamps/all",   HTTP_POST, handleLampsAll);
    server.on("/api/off",         HTTP_GET,  handleAllOff);
    server.on("/api/scan",        HTTP_GET,  handleScan);
    server.on("/api/config",      HTTP_GET,  handleConfig);
    server.on("/api/config/wifi", HTTP_POST, handleConfigWifi);
    server.on("/api/config/relay", HTTP_POST, handleConfigRelay);
    server.on("/api/sweep",       HTTP_GET,  handleSweep);
    server.on("/api/sweep",       HTTP_POST, handleSweep);
    server.on("/api/reset",       HTTP_POST, handleReset);
    server.on("/api/reboot",      HTTP_POST, handleReboot);

    server.onNotFound(handleNotFound);
    server.begin();

    Serial.println(F("[api] HTTP server running on port 80"));
}

void tick()
{
    server.handleClient();
}

}   // namespace Api
