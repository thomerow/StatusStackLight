#include "lamps.h"

#include <math.h>

namespace {

LampState states[LAMP_COUNT];
uint8_t   levels[LAMP_COUNT] = { 0 };         // last output brightness in %
uint16_t  gammaTable[BRIGHTNESS_MAX + 1];     // percent -> register value

// Short critical sections around the state array. Written from the web
// server (core 1), read from the effect task (core 0).
portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

volatile bool    sweepRequested = false;
volatile int     sweepCurrent   = 0;   // 1...5 during the sweep

volatile Lamps::SystemDisplay display      = Lamps::SystemDisplay::None;
volatile uint32_t             displaySince = 0;   // millis() when it was set

// Lamps of the system display, resolved by their ID in begin() - so the
// display stays correct even if LAMPS[] is ever reordered.
int lampConnecting = -1;
int lampConnected  = -1;
int lampPortal     = -1;

void buildGammaTable()
{
    for (int i = 0; i <= BRIGHTNESS_MAX; i++) {
        const float fraction = (float) i / (float) BRIGHTNESS_MAX;
        gammaTable[i] = (uint16_t) lroundf(powf(fraction, GAMMA) * (float) PWM_MAX);
    }
}

// The only place where the active-LOW drive is inverted.
//
// Everything above this function - API, web interface, effect engine - works
// in "0 = off, 100 = full brightness". Whoever rebuilds the inversion in a
// second place is guaranteed to fix only one of the two in the next rework.
void writePwm(uint8_t index, uint8_t percent)
{
    if (percent > BRIGHTNESS_MAX) percent = BRIGHTNESS_MAX;

    uint32_t value = gammaTable[percent];
    if (LAMP_ACTIVE_LOW) {
        value = PWM_MAX - value;
    }

    ledcWrite(index, value);
    levels[index] = percent;
}

// Cosine instead of a triangle: the eye perceives the soft turning point as
// "breathing", a triangle looks choppy at the peaks. Starts dark at phase 0.
uint8_t pulse(float phase, uint8_t brightness)
{
    const float f = 0.5f - 0.5f * cosf(2.0f * PI * phase);
    return (uint8_t) lroundf(f * (float) brightness);
}

// Computes the momentary brightness of a lamp from its state.
// `seconds` is a common time base for all lamps - only this keeps two lamps
// with the same frequency in sync instead of drifting apart.
uint8_t computeLevel(const LampState &s, float seconds)
{
    if (!s.on || s.brightness == 0) {
        return 0;
    }

    switch (s.effect) {
        case Effect::Blink: {
            const float phase = fmodf(seconds * s.frequency, 1.0f);
            return (phase < (float) s.duty / 100.0f) ? s.brightness : 0;
        }
        case Effect::Pulse:
            return pulse(fmodf(seconds * s.frequency, 1.0f), s.brightness);
        default:
            return s.brightness;
    }
}

// Writes the system display instead of the lamp states. Returns false if none
// is active - then the caller shows the normal state.
bool showSystemDisplay()
{
    const Lamps::SystemDisplay d = display;
    if (d == Lamps::SystemDisplay::None) {
        return false;
    }

    // Time relative to when it was set, so every pulse starts dark instead of
    // in the middle of the curve.
    const uint32_t elapsed = millis() - displaySince;
    const float    seconds = (float) elapsed / 1000.0f;

    int     lamp  = -1;
    uint8_t value = 0;
    switch (d) {
        case Lamps::SystemDisplay::Connecting:
            lamp  = lampConnecting;
            value = pulse(fmodf(seconds * DISPLAY_CONNECTING_HZ, 1.0f), DISPLAY_BRIGHTNESS);
            break;
        case Lamps::SystemDisplay::Portal:
            lamp  = lampPortal;
            value = pulse(fmodf(seconds * DISPLAY_PORTAL_HZ, 1.0f), DISPLAY_BRIGHTNESS);
            break;
        case Lamps::SystemDisplay::Connected:
            if (elapsed >= DISPLAY_FLASH_MS + DISPLAY_PAUSE_MS) {
                // Only end it if nobody has set a different display in the
                // meantime.
                if (display == Lamps::SystemDisplay::Connected) {
                    display = Lamps::SystemDisplay::None;
                }
                return false;
            }
            lamp  = lampConnected;
            value = elapsed < DISPLAY_FLASH_MS ? DISPLAY_BRIGHTNESS : 0;
            break;
        default:
            break;
    }

    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        writePwm(i, (int) i == lamp ? value : 0);
    }
    return true;
}

void runSweep()
{
    LampState saved[LAMP_COUNT];
    taskENTER_CRITICAL(&mux);
    for (uint8_t i = 0; i < LAMP_COUNT; i++) saved[i] = states[i];
    taskEXIT_CRITICAL(&mux);

    Serial.println(F("[sweep] channel sweep started"));

    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        sweepCurrent = i + 1;
        for (uint8_t j = 0; j < LAMP_COUNT; j++) {
            writePwm(j, j == i ? BRIGHTNESS_MAX : 0);
        }
        Serial.printf("[sweep] channel %u  GPIO %2u  expected: %s\n",
                      i + 1, LAMPS[i].gpio, LAMPS[i].name);
        vTaskDelay(pdMS_TO_TICKS(SWEEP_HOLD_MS));
    }

    sweepCurrent = 0;
    taskENTER_CRITICAL(&mux);
    for (uint8_t i = 0; i < LAMP_COUNT; i++) states[i] = saved[i];
    taskEXIT_CRITICAL(&mux);

    Serial.println(F("[sweep] done, previous state restored"));
}

void effectTask(void *)
{
    const TickType_t tick = pdMS_TO_TICKS(1000 / EFFECT_TICK_HZ);
    TickType_t       last = xTaskGetTickCount();

    for (;;) {
        if (sweepRequested) {
            sweepRequested = false;
            runSweep();
            last = xTaskGetTickCount();
        }

        if (showSystemDisplay()) {
            vTaskDelayUntil(&last, tick);
            continue;
        }

        // Common time base. millis() overflows after 49 days; fmodf() below
        // makes the jump harmless - it costs a single swallowed blink cycle,
        // no misbehaviour.
        const float seconds = (float) millis() / 1000.0f;

        LampState copy[LAMP_COUNT];
        taskENTER_CRITICAL(&mux);
        for (uint8_t i = 0; i < LAMP_COUNT; i++) copy[i] = states[i];
        taskEXIT_CRITICAL(&mux);

        for (uint8_t i = 0; i < LAMP_COUNT; i++) {
            writePwm(i, computeLevel(copy[i], seconds));
        }

        vTaskDelayUntil(&last, tick);
    }
}

}   // namespace

namespace Lamps {

void begin()
{
    buildGammaTable();

    // The order matters here.
    //
    // After reset the GPIOs are high-impedance. With the active-LOW MOSFET
    // module that means: undefined, possibly on - the stack light flashes
    // briefly while booting. So first drive them to the off level by hand and
    // only then attach LEDC.
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        pinMode(LAMPS[i].gpio, OUTPUT);
        digitalWrite(LAMPS[i].gpio, LAMP_ACTIVE_LOW ? HIGH : LOW);
    }

    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        ledcSetup(i, PWM_BASE_FREQUENCY, PWM_RESOLUTION_BITS);
        ledcAttachPin(LAMPS[i].gpio, i);
        writePwm(i, 0);
    }

    lampConnecting = findIndex("blue");
    lampConnected  = findIndex("green");
    lampPortal     = findIndex("orange");
}

void startEffectTask()
{
    // Core 0: the Arduino loop with the web server runs on core 1. This
    // separation is why the synchronous web server is good enough here.
    xTaskCreatePinnedToCore(effectTask, "lamps", 4096, nullptr, 2, nullptr, 0);
}

LampState state(uint8_t index)
{
    LampState s;
    taskENTER_CRITICAL(&mux);
    s = states[index];
    taskEXIT_CRITICAL(&mux);
    return s;
}

void setState(uint8_t index, const LampState &state)
{
    taskENTER_CRITICAL(&mux);
    states[index] = state;
    taskEXIT_CRITICAL(&mux);
}

int findIndex(const String &identifier)
{
    for (uint8_t i = 0; i < LAMP_COUNT; i++) {
        if (identifier.equalsIgnoreCase(LAMPS[i].id)) {
            return i;
        }
    }

    // Channel number 1...5 as an alternative - handy for loops in scripts.
    if (identifier.length() == 1 && isDigit(identifier[0])) {
        const int number = identifier.toInt();
        if (number >= 1 && number <= LAMP_COUNT) {
            return number - 1;
        }
    }

    return -1;
}

uint8_t currentLevel(uint8_t index)
{
    return levels[index];
}

void startSweep()
{
    sweepRequested = true;
}

bool sweepRunning()
{
    return sweepRequested || sweepCurrent != 0;
}

int sweepChannel()
{
    return sweepCurrent;
}

void setSystemDisplay(SystemDisplay d)
{
    // Time first, then the display: the effect task reads both without a lock
    // and must never see the new display with the old start time.
    displaySince = millis();
    display      = d;
}

SystemDisplay systemDisplay()
{
    return display;
}

const char *systemDisplayName(SystemDisplay d)
{
    switch (d) {
        case SystemDisplay::Connecting: return "connecting";
        case SystemDisplay::Portal:     return "portal";
        case SystemDisplay::Connected:  return "connected";
        default:                        return "none";
    }
}

}   // namespace Lamps
