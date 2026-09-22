# StatusStackLight – Firmware (ESP32-S3)

Firmware for the 5-lamp stack light. It provides an HTTP JSON API for driving the lamps and
a web interface that lets you play through every parameter of each lamp individually.

The enclosure and mechanics live in [`../enclosure`](../enclosure/OpenSCAD/README.md), the
display of Claude Code sessions in [`../claude-code`](../claude-code/README.md). The
[README in the root directory](../README.md) gives an overview of the whole project.

## What the lamps can do

Each lamp has a master switch, a brightness and a timing behaviour:

| Field | Range | Meaning |
|---|---|---|
| `on` | `true` / `false` | master switch |
| `brightness` | 0…100 % | peak brightness, gamma corrected |
| `effect` | `steady`, `blink`, `pulse` | constant / hard blinking / soft pulsing |
| `frequency` | 0.1…20.0 Hz | rate for `blink` and `pulse` |
| `duty` | 1…99 % | `blink` only: share of the period during which the lamp is lit |

`on` is deliberately separate from the effect. Turn a blinking lamp off and on again and you
get it back blinking – brightness and effect survive being switched off.

Several lamps with the same frequency blink in sync; the effect engine uses a common time
base for all five.

How to set these fields is described in [API.md](API.md).

## Hardware

| Item | Value |
|---|---|
| Board | ESP32-S3 DevKitC-1, **N16R8** (16 MB flash, 8 MB octal PSRAM) |
| Driver | 8-channel MOSFET module, low side, **active LOW** (GPIO to ground = lamp on) |
| Lamps | 12 V LED modules |
| Power | USB-C PD trigger board (12 V) → Mini560 buck → 3.3 V into the ESP32's 3V3 pin |

### Channel mapping

| Channel | GPIO | Colour | API ID |
|---|---|---|---|
| 1 | 4 | white | `white` |
| 2 | 5 | blue | `blue` |
| 3 | 6 | green | `green` |
| 4 | 7 | orange | `orange` |
| 5 | 15 | red | `red` |

This mapping was verified against the assembled stack light on 2026-09-21.

After rewiring or replacing a lamp, it can be checked again with the
[channel sweep](#diagnostics). If it no longer matches, swap the lines of the `LAMPS[]`
table in `include/config.h` – nothing else.

## WiFi setup

Credentials are stored in NVS, not in the source. If the device finds none there – freshly
flashed, on a different board or after `POST /api/reset` – it opens an open access point
itself:

1. The access point **`StatusStackLight-XXXX`** appears in the WiFi list (`XXXX` = the last
   two bytes of the MAC address, also printed on the serial console).
2. Connect – the setup page opens by itself as a captive portal. If not:
   `http://192.168.4.1/setup`.
3. Choose a network, enter the password, save. The device **tries the credentials first**
   and only stores them if the connection succeeds – a typo does not lock you out. That is
   why the response takes up to 20 seconds.
4. After that it is reachable at **`http://statusstacklight.local/`** (or at the IP the
   setup page reports – Android does not resolve `.local` reliably).

If the connection drops during operation, the device keeps retrying on its own; the lamps
keep showing their last state meanwhile. If it stays unsuccessful for more than two minutes,
the setup AP opens again. The API is then reachable at the AP address; changes to the lamps
are stored but only shown after the next connection – until then, orange pulses (see
below).

### Boot display

When plugged in, the stack light shows how far along it is instead of showing the stored
lamp state right away:

| Display | Meaning |
|---|---|
| blue pulsing (1 Hz) | connecting to the stored WiFi network |
| green lit for one second, then briefly dark | connected – then the stored lamp state appears |
| orange pulsing slowly | setup AP open: no WiFi stored or none reachable |
| red pulsing slowly, dim | relay mode: no contact to the relay for a minute, see [Relay mode](#relay-mode) |

Orange stays until a WiFi network has been entered via the setup AP; during the connection
attempt blue pulses again, and on success the green signal follows. Blue deliberately pulses
faster than "Claude is working" (0.3 Hz). If the connection only drops briefly during
operation, no display appears – the Claude status stays visible. Rate, flash duration and
brightness are set in `config.h` under `DISPLAY_*`.

## Relay mode

Normally the stack light waits on the local network for the hook script to switch it. In
**relay mode** it fetches its state itself from a [relay server](../relay/README.md) on the
internet instead – then the computers running Claude Code need not be on the same network,
and several of them can feed the same stack light.

Set it up at the bottom of the web interface under **Relay**: switch on relay mode, enter the
relay's address (for example `https://relay.example.org` or `http://192.168.178.10:5080`) and
a key with the role *lamp* from the relay's admin interface, save. The key is stored in NVS
(namespace `ssl-relay`) and never shown again; to keep it, leave the field empty.

- **Long polling:** the stack light asks the relay for the current image and names the
  version it shows. The relay holds the request until something changes, at the latest
  25 seconds (`RELAY_WAIT_S`). A change thus arrives within a fraction of a second, and while
  nothing happens there is one request every 25 seconds.
- **HTTPS** works with certificates from Let's Encrypt: the firmware trusts the roots ISRG
  Root X1 and X2 (`include/relay_ca.h`). For another CA, add its root certificate there.
  Without TLS, the key travels over the network in plain text.
- **The local API stays usable** – handy for trying things out. What is set locally stays
  until the relay's next change overwrites it. The web interface shows a banner in relay mode.
- **Without contact to the relay** for more than a minute (`RELAY_LOST_AFTER_MS`), **red
  pulses slowly and dimly** – the display is out of date, nothing is broken. Retries back off
  from 2 to 30 seconds; as soon as the relay answers, its image appears. The web interface
  names the last error (wrong key, address unreachable, …).

Over the API: `POST /api/config/relay`, see [API.md](API.md#post-apiconfigrelay).

## Diagnostics

At the bottom of the web interface: **Channel sweep**. It turns channels 1 to 5 on one at a
time for one second each and reports on the serial console which colour is expected – the
quickest way to see each channel on its own after replacing a lamp or when a loose contact
is suspected:

```
[sweep] channel 1  GPIO  4  expected: white
[sweep] channel 2  GPIO  5  expected: blue
...
```

Afterwards the previous state is restored. Also available via the API: `GET /api/sweep`.

If a channel misbehaves:

- **One lamp stays dark while the others work** – the fault is behind the GPIO. To narrow it
  down, measure at the MOSFET output while the sweep is on that channel.
- **The wrong lamp lights up** – swap the lines in `LAMPS[]` in `include/config.h`.
- **The stack light flashes briefly while booting** – the MOSFET module lacks pull-ups on its
  control inputs; add 10 kΩ to 3.3 V on each. The firmware drives the GPIOs to the off level
  first thing, but cannot bridge the time before that.
- **Everything switches exactly the wrong way round** – `LAMP_ACTIVE_LOW = false` in
  `config.h`.

## API

The complete description of all endpoints with requests, real responses, error codes and
examples in curl and PowerShell is in **[API.md](API.md)**.

A quick start:

```bash
curl http://statusstacklight.local/api/status                     # everything at a glance
curl 'http://statusstacklight.local/api/lamps/red/on?brightness=50' # turn red on
curl -X PATCH http://statusstacklight.local/api/lamps/orange \
     -H 'Content-Type: application/json' -d '{"effect":"blink","frequency":2}'
```

Invalid values are rejected with `400` and a plain-text message instead of being silently
clamped – a silently halved brightness sends you looking in the wrong place when debugging.

## Building and flashing

```powershell
pio run                 # build
pio run -t upload       # build and flash
pio device monitor      # serial console, 115200 baud
```

Two environments, depending on which USB-C port of the DevKitC-1 you use (labelled `USB` and
`COM` on the enclosure lid):

| Environment | Port | |
|---|---|---|
| `uart` (default) | **COM** | Recommended. The port survives reset and flashing, and you also see the output of the ROM bootloader. |
| `usb` | **USB** | Native USB port. Works, but the COM port disappears on every reset. |

```powershell
pio run -e usb -t upload
```

The first build downloads the platform and the Xtensa toolchain – that takes a while and
needs internet access.

**Power while flashing:** The Mini560 feeds 3.3 V directly into the 3V3 pin, bypassing the
board's voltage regulator. If USB is plugged in as well, two sources drive the same rail –
Espressif explicitly calls the two supply paths "mutually exclusive". For a short flash this
usually works in practice; the clean way is to disconnect the 3.3 V line first (ground may
stay). The board is a clone with a CH343 instead of a CP2102N, so protection diodes on the
USB ports are not guaranteed.

### Two things that are this way on purpose

**`build_dir` points outside the project** (`C:/pio/StatusStackLight`). For one, non-ASCII
characters in paths are explicitly unsupported by PlatformIO, and a build directory outside
the project keeps that independent of where the project lives. For another, `.pio/build` is
around ten thousand files – in a Dropbox folder that means constant syncing and now and then
a locked file in the middle of a build.

**`board_build.arduino.memory_type = qio_opi`** matches the ESP32-S3-**WROOM-1** N16R8 (quad
flash, octal PSRAM). The similarly named WROOM-**2** N16R8**V** has 1.8 V octal flash and
would need `opi_opi` plus `flash_mode = dout` – otherwise the board does not even boot. When
in doubt, read the marking on the module. The startup banner prints the PSRAM size; if it
shows zero bytes instead of about 8 MB, the setting is wrong.

### If the build fails

**`ModuleNotFoundError: No module named 'intelhex'`** while creating `bootloader.bin`: the
bundled esptool 4.9 needs this Python package, but PlatformIO's own environment does not
include it. Install it once:

```powershell
& "$env:USERPROFILE\.platformio\penv\Scripts\python.exe" -m pip install intelhex
```

**Strange errors when opening files**: first suspect non-ASCII characters in the path (see
`build_dir` above) before searching the source.

## Structure

```
API.md                  HTTP API: all endpoints with examples
platformio.ini          board, environments, libraries
include/config.h        pins, colours, limits, defaults  <- adjust things here
scripts/embed_web.py    pre-build: web/*.html -> include/web_assets.h (gzip)
web/index.html          control page (source)
web/setup.html          WiFi setup page (source)
src/main.cpp            setup/loop
src/lamps.*             LEDC, effect engine, gamma, inversion, system displays
src/lamp_state.*        state of a lamp, validation, JSON
src/lamp_store.*        last lamp state in NVS, survives restarts
src/wifi_portal.*       credentials, station connection, setup AP, captive portal
src/relay_client.*      relay mode: long polling in its own task
include/relay_ca.h      root certificates for HTTPS to the relay
src/api_server.*        HTTP routes
```

The web interface is gzipped during the build and embedded into the firmware image as a byte
array. The HTML files thus remain normal, editable files, while a single upload step is
still enough – no separate flashing of a file system that you are guaranteed to forget after
an OTA. `include/web_assets.h` is generated and listed in `.gitignore`.

### Why the effects run in their own task

The LEDC base frequency stays constant at 1 kHz; the effects only modulate the duty cycle.
That is handled by a FreeRTOS task at 100 Hz on **core 0**, while the web server runs in the
Arduino loop on core 1. This separation is why the synchronous `WebServer` from the Arduino
core is good enough: not even a hanging HTTP client can make the blinking stutter. This
spares the project a dependency on ESPAsyncWebServer and AsyncTCP along with their version
traps.

### State across restarts

The firmware remembers the state of all five lamps in NVS (namespace `ssl-lampen`, separate
from the WiFi credentials – `/api/reset` leaves it alone) and restores it at startup, before
the effect task starts. Without that, the stack light would stay dark after a power cut,
restart or flash until the next hook happens to send the target state – and if Claude is
waiting for input, none fires.

It only writes on a real change and only after 2 s of quiet (`STORE_DELAY_MS`). The hook
script sends the complete state on every event, mostly unchanged – that does not trigger a
write. A slider dragged in the web interface results in one write instead of twenty, and the
warning flash is over before it reaches the flash.

The restored state may be outdated – say, blue pulsing from a session that ended during the
power cut. The next hook corrects that.

The NVS namespaces (`ssl-lampen`, `ssl-wlan`) and keys keep their original German names, so
devices keep their stored state and credentials across firmware updates. The relay settings
live in `ssl-relay`.

### PWM base frequency

Fixed at **1 kHz** (`PWM_BASE_FREQUENCY` in `config.h`), not changeable at runtime. There is
little headroom anyway: the MOSFET module manages about 2 kHz because its gates are
discharged through a 10 kΩ pull-down, which makes turn-off sluggish. The ESP32 would not be
the limit – its LEDC block would reach 19.5 kHz at 12 bits.

Not to be confused with a lamp's `frequency` field: that is the blink or pulse rate
(0.1–20 Hz) and has nothing to do with the PWM carrier frequency.

## Displaying Claude Code sessions

Through hooks, the stack light shows the state of running Claude Code sessions. The script,
hook configuration and display scheme are in [`../claude-code`](../claude-code/README.md);
across networks through the relay, see [Relay mode](#relay-mode).
