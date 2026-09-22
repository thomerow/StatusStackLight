// config.h - every value that depends on the hardware, in one place.
//
// If something changes on the stack light (a different lamp, a different
// colour order, a replaced MOSFET module), this is the file to adjust - not
// the rest of the source.

#pragma once

#include <Arduino.h>

// --- Device ----------------------------------------------------------------

#define SSL_HOSTNAME       "StatusStackLight"   // DHCP name and mDNS -> statusstacklight.local
#define SSL_FIRMWARE       "1.1.0"
#define SSL_AP_PREFIX      "StatusStackLight"   // setup AP is called StatusStackLight-XXXX

// --- Lamps -----------------------------------------------------------------

static const uint8_t LAMP_COUNT = 5;

// Switching logic of the MOSFET module.
//
// The module in use is optocoupler-driven and switches active LOW: a GPIO
// pulled to ground turns the lamp on. The inversion happens exactly once,
// when writing the LEDC register (see lamps.cpp); everything above that works
// in "0 = off, 100 = full brightness" throughout.
//
// If testing shows the opposite behaviour (lamps on while nothing drives
// them), setting this to false is all it takes.
static const bool LAMP_ACTIVE_LOW = true;

struct LampChannel {
    uint8_t     gpio;
    const char *id;      // API identifier, lower case
    const char *name;    // display name in the web interface
    const char *color;   // CSS colour of the status dot in the web interface
};

// Order = channel number 1...5 (as in the enclosure README).
//
// VERIFIED: 2026-09-21 against the assembled stack light - this mapping is
// correct.
//
// After rewiring or replacing a lamp, the channel sweep in the web interface
// is the quickest way to check: if a different lamp lights up than the one
// announced, swap the lines here and nothing else.
static const LampChannel LAMPS[LAMP_COUNT] = {
    {  4, "white",  "white",  "#f8fafc" },   // channel 1
    {  5, "blue",   "blue",   "#3b82f6" },   // channel 2
    {  6, "green",  "green",  "#22c55e" },   // channel 3
    {  7, "orange", "orange", "#f59e0b" },   // channel 4
    { 15, "red",    "red",    "#ef4444" },   // channel 5
};

// Display order in the web interface, top to bottom - as indices into
// LAMPS[]. Mirrors the physical stack light (red on top), not the GPIO
// numbers.
static const uint8_t LAMP_UI_ORDER[LAMP_COUNT] = { 4, 3, 2, 1, 0 };

// --- PWM -------------------------------------------------------------------

// 12 bits comfortably cover 101 gamma-corrected brightness steps and still
// allow base frequencies above 20 kHz.
static const uint8_t  PWM_RESOLUTION_BITS = 12;

// Highest register value, i.e. full brightness.
//
// A pitfall that is easy to resolve the wrong way round: at 12 bits, 4095
// would only be a 4095/4096 duty cycle, so the lamp would never be fully on.
// The Arduino core handles this itself - ledcWrite() detects "all bits set"
// and internally writes 4096 = permanently on (see esp32-hal-ledc.c). That is
// why 4095 is correct here and 4096 would be wrong: the value would bypass
// that special case and reach ledc_set_duty() unchecked.
//
// This is exactly what matters for the active-LOW drive: the inversion is
// PWM_MAX - value, and because 0 becomes 4095, the special case applies and
// the lamp is truly dark instead of glowing at 1/4096.
static const uint32_t PWM_MAX             = (1u << PWM_RESOLUTION_BITS) - 1;  // 4095

// Carrier base frequency - fixed, not changeable at runtime.
//
// 1 kHz is the usual compromise for 12 V LED modules: high enough to avoid
// visible flicker, low enough for the MOSFETs to switch cleanly.
//
// There is little headroom anyway: the MOSFET module in use manages about
// 2 kHz. Its gates are charged through a series resistor and discharged
// through a 10 kOhm pull-down, which makes turn-off sluggish - above that, the
// MOSFET spends a growing share of each period in its linear region and heats
// up instead of switching cleanly. The ESP32 would not be the limit: its LEDC
// block derives its clock from 80 MHz, so frequency * 2^resolution <= 80 MHz,
// i.e. up to 19531 Hz at 12 bits.
//
// Not to be confused with the frequency of a lamp effect (FREQUENCY_MIN/MAX
// below) - that one is the blink or pulse rate.
static const uint32_t PWM_BASE_FREQUENCY = 1000;

// Gamma for the brightness curve. 2.2 roughly matches the sensitivity of the
// eye - without it, 50 % looks much brighter than half as bright.
static const float GAMMA = 2.2f;

// --- Limits of the effect parameters ---------------------------------------

static const uint8_t BRIGHTNESS_MIN = 0;
static const uint8_t BRIGHTNESS_MAX = 100;

static const float FREQUENCY_MIN = 0.1f;
static const float FREQUENCY_MAX = 20.0f;

static const uint8_t DUTY_MIN = 1;
static const uint8_t DUTY_MAX = 99;

// --- Defaults --------------------------------------------------------------

static const uint8_t BRIGHTNESS_DEFAULT = 100;
static const float   FREQUENCY_DEFAULT  = 1.0f;
static const uint8_t DUTY_DEFAULT       = 50;

// --- Timing ----------------------------------------------------------------

static const uint32_t EFFECT_TICK_HZ          = 100;    // update rate of the effect engine
static const uint32_t WIFI_CONNECT_TIMEOUT_MS = 20000;  // then the setup AP opens
static const uint32_t WIFI_PORTAL_AFTER_MS    = 120000; // without connection -> setup AP
static const uint32_t SWEEP_HOLD_MS           = 1000;   // hold time per channel during the sweep
static const uint32_t STORE_DELAY_MS          = 2000;   // quiet time before the lamp state goes to NVS

// --- Boot display ----------------------------------------------------------
//
// At startup and while the setup AP is open, the stack light shows the WiFi
// state instead of the stored lamp state: blue pulsing = connecting, green
// flash = connected, orange pulsing slowly = setup AP open.
//
// Blue deliberately pulses much faster than "Claude is working" (0.3 Hz in
// the hook script), so the two cannot be confused.

static const float    DISPLAY_CONNECTING_HZ = 1.0f;
static const float    DISPLAY_PORTAL_HZ     = 0.3f;
static const uint32_t DISPLAY_FLASH_MS      = 1000;
// Dark pause after the flash. Without it, the green would blend seamlessly
// into a stored green state ("done") and would not read as a signal of its
// own.
static const uint32_t DISPLAY_PAUSE_MS      = 400;
static const uint8_t  DISPLAY_BRIGHTNESS    = 100;   // %

// Relay mode: the relay has not answered for RELAY_LOST_AFTER_MS. Red, but
// slow and dim - clearly different from the steady red of an error, and quiet
// enough not to alarm anyone: the stack light is only out of date.
static const float    DISPLAY_RELAY_LOST_HZ         = 0.2f;
static const uint8_t  DISPLAY_RELAY_LOST_BRIGHTNESS = 30;   // %

// --- Relay mode ------------------------------------------------------------
//
// The stack light fetches its state from a relay server (relay/ in this repo)
// instead of being switched over the local API. Long polling: the relay holds
// each request until the state changes, at the latest RELAY_WAIT_S seconds.

static const uint32_t RELAY_WAIT_S             = 25;
// Longer than the wait, or every quiet poll would count as a failure.
static const uint32_t RELAY_TIMEOUT_MS         = (RELAY_WAIT_S + 10) * 1000;
static const uint32_t RELAY_CONNECT_TIMEOUT_MS = 5000;
// Without a successful poll for this long, the relay display shows.
static const uint32_t RELAY_LOST_AFTER_MS      = 60000;
// Waiting time after the 1st, 2nd, 3rd, ... failure in a row; the last value
// repeats.
static const uint32_t RELAY_BACKOFF_MS[]       = { 2000, 5000, 10000, 30000 };
static const size_t   RELAY_URL_MAX            = 200;
static const size_t   RELAY_KEY_MAX            = 100;
