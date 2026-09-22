#include "lamp_state.h"

#include <WebServer.h>

#include "lamps.h"

const char *effectName(Effect e)
{
    switch (e) {
        case Effect::Blink: return "blink";
        case Effect::Pulse: return "pulse";
        default:            return "steady";
    }
}

bool effectFromName(const char *name, Effect &target)
{
    if (name == nullptr)              return false;
    if (!strcmp(name, "steady"))    { target = Effect::Steady; return true; }
    if (!strcmp(name, "blink"))     { target = Effect::Blink;  return true; }
    if (!strcmp(name, "pulse"))     { target = Effect::Pulse;  return true; }
    return false;
}

// --- Validation helpers ----------------------------------------------------

static ValidationResult failure(const String &text)
{
    ValidationResult r;
    r.ok    = false;
    r.error = text;
    return r;
}

static String rangeText(const char *field, const String &value, const String &from, const String &to)
{
    return String("field '") + field + "' out of range: got " + value + ", expected " + from + "..." + to;
}

// --- JSON ------------------------------------------------------------------

ValidationResult applyJson(LampState &state, JsonObjectConst source, bool complete)
{
    // Work on a copy: if any field fails, the state passed in stays
    // completely untouched.
    LampState next = complete ? LampState{} : state;

    for (JsonPairConst field : source) {
        const char *key = field.key().c_str();

        if (!strcmp(key, "on")) {
            if (!field.value().is<bool>()) {
                return failure("field 'on' must be a boolean");
            }
            next.on = field.value().as<bool>();

        } else if (!strcmp(key, "effect")) {
            Effect e;
            if (!field.value().is<const char *>() || !effectFromName(field.value().as<const char *>(), e)) {
                return failure("field 'effect' must be one of: steady, blink, pulse");
            }
            next.effect = e;

        } else if (!strcmp(key, "brightness")) {
            if (!field.value().is<int>()) {
                return failure("field 'brightness' must be an integer");
            }
            int v = field.value().as<int>();
            if (v < BRIGHTNESS_MIN || v > BRIGHTNESS_MAX) {
                return failure(rangeText("brightness", String(v), String(BRIGHTNESS_MIN), String(BRIGHTNESS_MAX)));
            }
            next.brightness = (uint8_t) v;

        } else if (!strcmp(key, "frequency")) {
            if (!field.value().is<float>()) {
                return failure("field 'frequency' must be a number");
            }
            float v = field.value().as<float>();
            if (v < FREQUENCY_MIN || v > FREQUENCY_MAX) {
                return failure(rangeText("frequency", String(v, 2), String(FREQUENCY_MIN, 1), String(FREQUENCY_MAX, 1)));
            }
            next.frequency = v;

        } else if (!strcmp(key, "duty")) {
            if (!field.value().is<int>()) {
                return failure("field 'duty' must be an integer");
            }
            int v = field.value().as<int>();
            if (v < DUTY_MIN || v > DUTY_MAX) {
                return failure(rangeText("duty", String(v), String(DUTY_MIN), String(DUTY_MAX)));
            }
            next.duty = (uint8_t) v;

        } else if (!strcmp(key, "id") || !strcmp(key, "channel") ||
                   !strcmp(key, "gpio") || !strcmp(key, "name") ||
                   !strcmp(key, "color") || !strcmp(key, "level")) {
            // Fields supplied by the device itself. A client that sends back
            // a lamp it has read, unchanged, should not fail on its own
            // response - so ignore them silently.

        } else {
            return failure(String("unknown field: '") + key + "'");
        }
    }

    state = next;
    return ValidationResult{};
}

// --- Query parameters ------------------------------------------------------

ValidationResult applyQuery(LampState &state, WebServer &server)
{
    // The easy way: copy the parameters into a JSON object and run the same
    // validation as above. A second set of limits would be a reliable source
    // of future discrepancies between the two paths.
    JsonDocument doc;
    JsonObject   o = doc.to<JsonObject>();

    for (int i = 0; i < server.args(); i++) {
        const String name  = server.argName(i);
        const String value = server.arg(i);

        if (name == "on") {
            o["on"] = (value == "1" || value == "true");
        } else if (name == "effect") {
            o["effect"] = value;
        } else if (name == "brightness") {
            o["brightness"] = value.toInt();
        } else if (name == "frequency") {
            o["frequency"] = value.toFloat();
        } else if (name == "duty") {
            o["duty"] = value.toInt();
        } else if (name == "plain") {
            // Inserted by the WebServer itself, not a user parameter.
        } else {
            return failure(String("unknown query parameter: '") + name + "'");
        }
    }

    // JsonObject converts implicitly to JsonObjectConst - ArduinoJson 7 has
    // no .as<>() on this class.
    return applyJson(state, o, false);
}

// --- Output ----------------------------------------------------------------

void writeJson(const LampState &state, uint8_t index, JsonObject target)
{
    const LampChannel &channel = LAMPS[index];

    target["id"]         = channel.id;
    target["channel"]    = index + 1;        // channel number as in the enclosure README
    target["gpio"]       = channel.gpio;
    target["name"]       = channel.name;
    target["color"]      = channel.color;

    target["on"]         = state.on;
    target["effect"]     = effectName(state.effect);
    target["brightness"] = state.brightness;
    target["frequency"]  = state.frequency;
    target["duty"]       = state.duty;

    // Brightness actually being output right now (0...100). This lets the
    // web interface show what the lamp is doing, not just what is set.
    target["level"]      = Lamps::currentLevel(index);
}
