#include "relay_client.h"

#include <HTTPClient.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "config.h"
#include "lamps.h"
#include "relay_ca.h"
#include "wifi_portal.h"

namespace {

const char *NVS_NAMESPACE = "ssl-relay";

// Settings and status are written by the web server (core 1, loop) and by the
// polling task - everything below is only touched under this lock.
SemaphoreHandle_t lock = nullptr;

bool     enabled    = false;
String   url;              // without a trailing slash
String   key;
// Goes up on every change of the settings. A poll that was started under an
// older generation is discarded - otherwise a request still waiting at the
// relay could switch the lamps after relay mode was turned off.
uint32_t generation = 0;

bool     connected   = false;
int64_t  version     = 0;
uint32_t lastSuccess = 0;   // millis() of the last successful poll, 0 = none yet
uint32_t lostSince   = 0;   // millis() from which "no contact" counts
String   lastError;

struct Settings {
    bool     enabled;
    String   url;
    String   key;
    uint32_t generation;
};

class Guard {
public:
    Guard()  { xSemaphoreTake(lock, portMAX_DELAY); }
    ~Guard() { xSemaphoreGive(lock); }
};

Settings current()
{
    Guard g;
    return Settings{ enabled, url, key, generation };
}

bool stillCurrent(uint32_t gen)
{
    Guard g;
    return gen == generation;
}

void recordFailure(uint32_t gen, const String &error)
{
    Guard g;
    if (gen != generation) return;
    if (error != lastError) {
        Serial.printf("[relay] %s\n", error.c_str());
    }
    connected = false;
    lastError = error;
}

// Shows the relay display once contact has been lost for long enough. The boot
// display and the portal take precedence: they are only replaced if nothing
// else is showing.
void checkLost(uint32_t gen)
{
    uint32_t since;
    {
        Guard g;
        if (gen != generation || !enabled) return;
        since = lostSince;
    }
    if (millis() - since >= RELAY_LOST_AFTER_MS &&
        Lamps::systemDisplay() == Lamps::SystemDisplay::None) {
        Lamps::setSystemDisplay(Lamps::SystemDisplay::RelayLost);
    }
}

String describe(int code)
{
    switch (code) {
        case 401: return "HTTP 401 - the relay does not know this key";
        case 403: return "HTTP 403 - this is not a lamp key";
        case 404: return "HTTP 404 - no relay at this address";
        default:  return "HTTP " + String(code);
    }
}

// One long poll. True if the relay answered with an image, which is then
// already applied.
bool poll(const Settings &s, int64_t knownVersion, int64_t &newVersion, String &error)
{
    char query[64];
    snprintf(query, sizeof(query), "/api/v1/lamps?version=%lld&wait=%u",
             (long long) knownVersion, (unsigned) RELAY_WAIT_S);

    const bool       secure = s.url.startsWith("https://");
    WiFiClient       plain;
    WiFiClientSecure tls;
    if (secure) {
        tls.setCACert(RELAY_ROOT_CA);
        tls.setHandshakeTimeout(RELAY_CONNECT_TIMEOUT_MS / 1000);
    }

    HTTPClient http;
    http.setConnectTimeout(RELAY_CONNECT_TIMEOUT_MS);
    http.setTimeout(RELAY_TIMEOUT_MS);
    http.setReuse(false);
    if (!http.begin(secure ? (WiFiClient &) tls : plain, s.url + query)) {
        error = "invalid relay address";
        return false;
    }
    http.addHeader("Authorization", "Bearer " + s.key);
    http.addHeader("X-StackLight-Firmware", SSL_FIRMWARE);
    http.addHeader("X-StackLight-Ip", WiFi.localIP().toString());

    const int code = http.GET();
    if (code != HTTP_CODE_OK) {
        error = code < 0 ? "no connection to the relay: " + HTTPClient::errorToString(code)
                         : describe(code);
        http.end();
        return false;
    }
    const String body = http.getString();
    http.end();

    JsonDocument doc;
    const DeserializationError parseError = deserializeJson(doc, body);
    if (parseError) {
        error = String("invalid answer from the relay: ") + parseError.c_str();
        return false;
    }
    JsonObjectConst lamps = doc["lamps"];
    if (lamps.isNull()) {
        error = "answer from the relay without lamps";
        return false;
    }

    // Settings changed while the request was waiting: this answer belongs to
    // the old ones.
    if (!stillCurrent(s.generation)) {
        error = "settings changed";
        return false;
    }

    const ValidationResult r = Lamps::applyBatch(lamps);
    if (!r.ok) {
        error = "relay sent an invalid image: " + r.error;
        return false;
    }
    newVersion = doc["version"] | (int64_t) 0;
    return true;
}

// Waits, but wakes up early when the settings change - so switching relay
// mode on or entering a new key does not wait out a 30 s backoff.
void pause(uint32_t ms, uint32_t gen)
{
    const uint32_t start = millis();
    while (millis() - start < ms && stillCurrent(gen)) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void relayTask(void *)
{
    uint32_t seenGeneration = UINT32_MAX;
    int64_t  known          = 0;
    uint8_t  failures       = 0;

    for (;;) {
        const Settings s = current();

        // New settings: fetch the complete image, whatever version was shown.
        if (s.generation != seenGeneration) {
            seenGeneration = s.generation;
            known          = 0;
            failures       = 0;
        }

        if (!s.enabled) {
            pause(1000, s.generation);
            continue;
        }

        if (Network::inApMode() || !Network::connected()) {
            recordFailure(s.generation, "no WiFi connection");
            checkLost(s.generation);
            pause(1000, s.generation);
            continue;
        }

        const uint32_t started = millis();
        int64_t        next    = known;
        String         error;
        if (poll(s, known, next, error)) {
            {
                Guard g;
                if (s.generation == generation) {
                    if (!connected || !lastError.isEmpty()) {
                        Serial.printf("[relay] connected to %s\n", s.url.c_str());
                    }
                    connected   = true;
                    version     = next;
                    lastSuccess = millis();
                    lostSince   = lastSuccess;
                    lastError   = "";
                }
            }
            known    = next;
            failures = 0;
            Lamps::clearSystemDisplay(Lamps::SystemDisplay::RelayLost);

            // A relay that answers at once every time (wrong wait, or a proxy
            // that cuts the request short) must not be hammered.
            if (millis() - started < 200) pause(200, s.generation);
            continue;
        }

        if (error == "settings changed") continue;

        recordFailure(s.generation, error);
        checkLost(s.generation);
        const size_t steps = sizeof(RELAY_BACKOFF_MS) / sizeof(RELAY_BACKOFF_MS[0]);
        pause(RELAY_BACKOFF_MS[failures < steps ? failures : steps - 1], s.generation);
        if (failures < 255) failures++;
    }
}

bool validUrl(const String &u)
{
    const int start = u.startsWith("https://") ? 8 : u.startsWith("http://") ? 7 : -1;
    if (start < 0 || (int) u.length() <= start) return false;
    for (size_t i = 0; i < u.length(); i++) {
        if (isSpace(u[i]) || u[i] == '?' || u[i] == '#') return false;
    }
    return u[start] != '/' && u[start] != ':';
}

}   // namespace

namespace Relay {

void begin()
{
    lock = xSemaphoreCreateMutex();

    Preferences prefs;
    prefs.begin(NVS_NAMESPACE, true);
    enabled = prefs.getBool("enabled", false);
    url     = prefs.getString("url", "");
    key     = prefs.getString("key", "");
    prefs.end();

    // Relay mode without a complete configuration would only ever fail.
    if (url.isEmpty() || key.isEmpty()) enabled = false;
    lostSince = millis();

    Serial.printf("[relay] %s%s\n", enabled ? "on, " : "off", enabled ? url.c_str() : "");

    // Core 1 with the web server: the HTTP client blocks while it waits, and
    // must never get in the way of the effect task on core 0. 12 KB stack for
    // the TLS handshake.
    xTaskCreatePinnedToCore(relayTask, "relay", 12288, nullptr, 1, nullptr, 1);
}

bool configure(bool newEnabled, const String *newUrl, const String *newKey, String &error)
{
    String u, k;
    {
        Guard g;
        u = newUrl ? *newUrl : url;
        k = newKey ? *newKey : key;
    }
    u.trim();
    k.trim();
    while (u.endsWith("/")) u.remove(u.length() - 1);

    if (u.length() > RELAY_URL_MAX) {
        error = "url longer than " + String(RELAY_URL_MAX) + " characters";
        return false;
    }
    if (!u.isEmpty() && !validUrl(u)) {
        error = "url must look like http://host:port or https://host/path";
        return false;
    }
    if (k.length() > RELAY_KEY_MAX) {
        error = "key longer than " + String(RELAY_KEY_MAX) + " characters";
        return false;
    }
    for (size_t i = 0; i < k.length(); i++) {
        if (isSpace(k[i])) {
            error = "key must not contain spaces";
            return false;
        }
    }
    if (newEnabled && (u.isEmpty() || k.isEmpty())) {
        error = "relay mode needs an address and a key";
        return false;
    }

    Preferences prefs;
    prefs.begin(NVS_NAMESPACE, false);
    prefs.putBool("enabled", newEnabled);
    prefs.putString("url", u);
    prefs.putString("key", k);
    prefs.end();

    {
        Guard g;
        enabled     = newEnabled;
        url         = u;
        key         = k;
        generation++;
        connected   = false;
        lastSuccess = 0;
        lostSince   = millis();
        lastError   = "";
    }
    if (!newEnabled) Lamps::clearSystemDisplay(Lamps::SystemDisplay::RelayLost);

    Serial.printf("[relay] settings changed: %s%s\n", newEnabled ? "on, " : "off", newEnabled ? u.c_str() : "");
    return true;
}

void writeConfig(JsonObject target)
{
    Guard g;
    target["enabled"] = enabled;
    target["url"]     = url;
    target["keySet"]  = !key.isEmpty();
}

void writeStatus(JsonObject target)
{
    Guard g;
    target["enabled"]   = enabled;
    target["connected"] = enabled && connected;
    target["version"]   = version;
    if (lastSuccess != 0) target["lastContact"] = (millis() - lastSuccess) / 1000;
    else                  target["lastContact"] = nullptr;
    if (!lastError.isEmpty()) target["lastError"] = lastError;
    else                      target["lastError"] = nullptr;
}

}   // namespace Relay
