#include "lamp_store.h"

#include <Arduino.h>
#include <Preferences.h>

#include "config.h"
#include "lamps.h"

namespace {

// Namespace and key are German for historical reasons. Renaming them would
// lose the state stored on existing devices.
const char   *NVS_NAMESPACE = "ssl-lampen";
const char   *NVS_KEY       = "zustand";

// Increment on every change to the layout of StoredLamp. An image with a
// different version is discarded instead of misread.
const uint8_t VERSION = 1;

// Fixed storage format, independent of the layout of LampState in RAM -
// otherwise a harmless reordering of the struct would read garbage from NVS
// after the next flash.
struct __attribute__((packed)) StoredLamp {
    uint8_t on;
    uint8_t effect;
    uint8_t brightness;
    uint8_t duty;
    float   frequency;
};

struct __attribute__((packed)) Image {
    uint8_t    version;
    StoredLamp lamps[LAMP_COUNT];
};

Image    stored;                     // what last went into NVS
bool     changed      = false;       // RAM differs from NVS
uint32_t lastChange   = 0;           // millis() of the most recent observed change
uint32_t lastCheck    = 0;
uint32_t blockedUntil = 0;           // after a write error: not before this millis()
bool     blocked      = false;

Image createImage()
{
    Image img;
    memset(&img, 0, sizeof(img));    // defined padding bytes, so memcmp works
    img.version = VERSION;
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        const LampState s = Lamps::state(i);
        img.lamps[i].on         = s.on ? 1 : 0;
        img.lamps[i].effect     = (uint8_t) s.effect;
        img.lamps[i].brightness = s.brightness;
        img.lamps[i].duty       = s.duty;
        img.lamps[i].frequency  = s.frequency;
    }
    return img;
}

// A single broken entry should not discard the rest, but it must not reach
// the effect engine unchecked either.
bool isValid(const StoredLamp &l)
{
    return l.on <= 1
        && l.effect <= (uint8_t) Effect::Pulse
        && l.brightness <= BRIGHTNESS_MAX
        && l.duty >= DUTY_MIN && l.duty <= DUTY_MAX
        && l.frequency >= FREQUENCY_MIN && l.frequency <= FREQUENCY_MAX;
}

}   // namespace

namespace LampStore {

void load()
{
    Preferences prefs;
    Image       img;
    size_t      bytesRead = 0;

    if (prefs.begin(NVS_NAMESPACE, true)) {
        bytesRead = prefs.getBytes(NVS_KEY, &img, sizeof(img));
        prefs.end();
    }

    if (bytesRead != sizeof(img) || img.version != VERSION) {
        Serial.println(F("[store] no stored state, lamps stay off"));
        stored = createImage();
        return;
    }

    uint8_t restored = 0;
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        const StoredLamp &l = img.lamps[i];
        if (!isValid(l)) {
            Serial.printf("[store] entry %u invalid, keeping the default\n", i + 1);
            continue;
        }
        LampState s;
        s.on         = l.on == 1;
        s.effect     = (Effect) l.effect;
        s.brightness = l.brightness;
        s.duty       = l.duty;
        s.frequency  = l.frequency;
        Lamps::setState(i, s);
        restored++;
    }

    // The baseline is what is actually in RAM now - so a partially discarded
    // image triggers a clean rewrite on the next tick().
    stored     = createImage();
    changed    = memcmp(&stored, &img, sizeof(img)) != 0;
    lastChange = millis();

    Serial.printf("[store] restored the state of %u lamps\n", restored);
}

void tick()
{
    const uint32_t now = millis();
    if (now - lastCheck < 100) return;
    lastCheck = now;

    // Compare content, not the number of requests: the hook script sends the
    // complete target state on every event, mostly unchanged. If every
    // request triggered a write, an active session would mean a flash write
    // every few seconds.
    static Image lastSeen = stored;
    const Image  current  = createImage();
    if (memcmp(&current, &lastSeen, sizeof(current)) != 0) {
        lastSeen   = current;
        changed    = memcmp(&current, &stored, sizeof(current)) != 0;
        lastChange = now;
    }

    // Only write once things have been quiet for a while. A slider dragged in
    // the web interface then causes one write instead of twenty, and the
    // hook's short warning flash never reaches the flash at all.
    if (!changed || now - lastChange < STORE_DELAY_MS) return;
    if (blocked && (int32_t) (now - blockedUntil) < 0) return;
    blocked = false;

    Preferences prefs;
    if (prefs.begin(NVS_NAMESPACE, false)) {
        const size_t written = prefs.putBytes(NVS_KEY, &current, sizeof(current));
        prefs.end();
        if (written == sizeof(current)) {
            stored  = current;
            changed = false;
            return;
        }
    }
    // Failure: retry in a minute instead of every 100 ms.
    Serial.println(F("[store] writing to NVS failed"));
    blocked      = true;
    blockedUntil = now + 60000;
}

}   // namespace LampStore
