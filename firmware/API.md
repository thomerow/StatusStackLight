# StatusStackLight – HTTP API

The stack light is controlled through a JSON API on the local network. This document
describes every endpoint with request and response. All responses shown are real responses
from the device; they are shortened where noted, and network names are replaced by example
names.

**Address:** `http://statusstacklight.local/` or the device's IP address. In the setup
access point it is `http://192.168.4.1/`.

**Ground rules:**

- Requests and responses are JSON (`Content-Type: application/json`).
- Every write request responds with the **resulting** state. The client never has to guess
  what arrived.
- Invalid values are **rejected, not clamped**. A request is either applied completely or
  not at all.
- There is no authentication. Anyone on the same network can switch the stack light and
  change the WiFi settings.
- CORS is open (`Access-Control-Allow-Origin: *`), so the API can also be used from a web
  page.

## Overview

| Method | Path | Body | Response | Purpose |
|---|---|---|---|---|
| GET | [`/api/status`](#get-apistatus) | – | device status + all lamps | everything at a glance |
| GET | [`/api/lamps`](#get-apilamps) | – | `{lamps: [...]}` | all five lamps |
| GET | [`/api/lamps/{id}`](#get-apilampsid) | – | lamp | one lamp |
| PATCH | [`/api/lamps/{id}`](#patch-apilampsid) | partial state | lamp | change individual fields |
| PUT | [`/api/lamps/{id}`](#put-apilampsid) | state | lamp | set the complete state |
| POST | [`/api/lamps`](#post-apilamps) | `{id: partial state, ...}` | `{lamps: [...]}` | several lamps at once |
| POST | [`/api/lamps/all`](#post-apilampsall) | partial state | `{lamps: [...]}` | the same change for all |
| GET | [`/api/lamps/{id}/on`](#shortcuts) | query | lamp | turn on |
| GET | [`/api/lamps/{id}/off`](#shortcuts) | query | lamp | turn off |
| GET | [`/api/lamps/{id}/toggle`](#shortcuts) | query | lamp | toggle |
| GET | [`/api/off`](#get-apioff) | – | `{lamps: [...]}` | all off |
| GET | [`/api/config`](#get-apiconfig) | – | configuration | hostname, WiFi mode |
| GET | [`/api/scan`](#get-apiscan) | – | `{networks: [...]}` | WiFi networks in range |
| POST | [`/api/config/wifi`](#post-apiconfigwifi) | `{ssid, password}` | `{ok, ssid, ip}` | set WiFi credentials |
| POST | [`/api/config/relay`](#post-apiconfigrelay) | `{enabled, url, key}` | relay settings | relay mode on/off, address, key |
| GET/POST | [`/api/sweep`](#get-apisweep) | – | `{ok, holdMs, channels}` | channel sweep |
| POST | [`/api/reset`](#post-apireset) | – | `{ok, message}` | delete WiFi credentials, restart |
| POST | [`/api/reboot`](#post-apireboot) | – | `{ok}` | restart |

`{id}` is the colour ID of a lamp (`white`, `blue`, `green`, `orange`, `red`) or its
channel number `1` to `5`. Case does not matter.

| Channel | ID | Colour |
|---|---|---|
| 1 | `white` | white |
| 2 | `blue` | blue |
| 3 | `green` | green |
| 4 | `orange` | orange |
| 5 | `red` | red |

## The lamp object

This is what a lamp looks like in every response:

```json
{
  "id": "orange",
  "channel": 4,
  "gpio": 7,
  "name": "orange",
  "color": "#f59e0b",
  "on": true,
  "effect": "blink",
  "brightness": 50,
  "frequency": 1.2,
  "duty": 55,
  "level": 50
}
```

**Writable fields:**

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `on` | boolean | `true` / `false` | `false` | master switch |
| `effect` | string | `steady`, `blink`, `pulse` | `steady` | constant / hard blinking / soft pulsing |
| `brightness` | integer | 0…100 | 100 | peak brightness in %, gamma corrected |
| `frequency` | number | 0.1…20.0 | 1.0 | rate in Hz for `blink` and `pulse` |
| `duty` | integer | 1…99 | 50 | `blink` only: share of the period in % during which the lamp is lit |

`on` is separate from the effect. Turn a blinking lamp off and on again and you get it back
blinking: brightness, effect and rate survive being switched off.

Lamps with the same frequency blink and pulse in sync, because the firmware uses a common
time base for all of them. Sending a state again does not reset the phase.

**Read-only fields:**

| Field | Meaning |
|---|---|
| `id` | colour ID, fixed |
| `channel` | channel number 1…5 |
| `gpio` | GPIO pin on the ESP32 |
| `name` | display name in the web interface |
| `color` | display colour in the web interface |
| `level` | brightness in % actually being output at this moment – changes constantly with `pulse` and `blink` |

The read-only fields may be included in a write request and are then ignored. A lamp that
has been read can therefore be sent back unchanged.

`level` comes from the last tick of the effect engine, which computes every 10 ms. In the
response to a change it therefore still shows the value from before the change.

The state of all lamps survives a restart; the firmware stores it in flash.

## Reading

### GET /api/status

Everything at a glance: device, WiFi, PWM, channel sweep, display order and all lamps.

```json
{
  "device": "StatusStackLight",
  "firmware": "1.0.0",
  "uptime": 2192,
  "heap": 275504,
  "psram": 8385831,
  "wifi": {
    "mode": "sta",
    "ssid": "MyWiFi",
    "ip": "192.168.178.72",
    "rssi": -66,
    "connected": true,
    "hostname": "StatusStackLight.local"
  },
  "pwm": { "baseFrequency": 1000, "resolution": 12, "activeLow": true },
  "sweep": { "running": false, "channel": 0 },
  "display": "none",
  "relay": { "enabled": false, "connected": false, "version": 0, "lastContact": null, "lastError": null },
  "order": ["red", "orange", "green", "blue", "white"],
  "lamps": [ … five lamp objects … ]
}
```

| Field | Meaning |
|---|---|
| `uptime` | seconds since startup |
| `heap` | free heap in bytes |
| `psram` | PSRAM size in bytes; about 8 MB on the N16R8 |
| `wifi.mode` | `sta` = on the WiFi network, `ap` = setup access point open |
| `wifi.ssid` | in `sta` mode the connected network, in `ap` mode the name of the access point |
| `wifi.rssi` | signal strength in dBm; always 0 in `ap` mode |
| `pwm` | PWM carrier frequency in Hz, resolution in bits, whether the outputs are active LOW |
| `sweep.channel` | during the channel sweep the channel currently lit, 1…5, otherwise 0 |
| `display` | system display currently overlaying the lamp state: `connecting` (blue pulsing), `portal` (orange pulsing), `connected` (green signal), `relay-lost` (red pulsing dimly, relay mode without contact) or `none`. As long as it is not `none`, the lamps do not show the state from `lamps` – changes are still applied and appear afterwards. |
| `relay.enabled` | relay mode on |
| `relay.connected` | the last poll of the relay succeeded |
| `relay.version` | version of the image last fetched from the relay |
| `relay.lastContact` | seconds since the last successful poll, `null` if none yet. Up to 25 s is normal: the relay holds each request until something changes. |
| `relay.lastError` | plain-text reason of the last failure, `null` after a success |
| `order` | order of the lamps on the stack light from top to bottom |

```bash
curl http://statusstacklight.local/api/status
```

```powershell
$s = Invoke-RestMethod http://statusstacklight.local/api/status
"{0} {1}, {2}, {3} dBm" -f $s.device, $s.firmware, $s.wifi.ip, $s.wifi.rssi
```

### GET /api/lamps

```json
{ "lamps": [ … five lamp objects, channel 1 to 5 … ] }
```

### GET /api/lamps/{id}

```bash
curl http://statusstacklight.local/api/lamps/orange
curl http://statusstacklight.local/api/lamps/4          # the same lamp
```

```powershell
Invoke-RestMethod http://statusstacklight.local/api/lamps/orange
```

Response: a [lamp object](#the-lamp-object).

## Writing

### PATCH /api/lamps/{id}

Changes only the fields sent; all others stay as they are. The usual way to adjust a lamp.

```http
PATCH /api/lamps/orange
Content-Type: application/json

{"on": true, "effect": "blink", "frequency": 2}
```

```json
{"id":"orange","channel":4,"gpio":7,"name":"orange","color":"#f59e0b",
 "on":true,"effect":"blink","brightness":50,"frequency":2,"duty":55,"level":0}
```

`brightness` and `duty` stayed unchanged.

```bash
curl -X PATCH http://statusstacklight.local/api/lamps/orange \
     -H 'Content-Type: application/json' \
     -d '{"on":true,"effect":"blink","frequency":2}'
```

```powershell
$change = @{ on = $true; effect = 'blink'; frequency = 2 } | ConvertTo-Json
Invoke-RestMethod http://statusstacklight.local/api/lamps/orange -Method Patch `
                  -Body $change -ContentType 'application/json'
```

### PUT /api/lamps/{id}

Sets the complete state. Missing fields get their [default value](#the-lamp-object) – not
their previous one.

```http
PUT /api/lamps/orange
Content-Type: application/json

{"on": true}
```

```json
{"id":"orange","channel":4,"gpio":7,"name":"orange","color":"#f59e0b",
 "on":true,"effect":"steady","brightness":100,"frequency":1,"duty":50,"level":50}
```

Effect, brightness, rate and duty cycle are at their defaults afterwards, even though only
`on` was sent. If you only want to turn a lamp on, use `PATCH`.

### POST /api/lamps

Several lamps in one request. The key is the ID or channel number, the value a partial state
as with `PATCH`. Lamps not mentioned stay unchanged.

The firmware first validates all entries and then applies them all at once. If one is
invalid, no lamp changes. This is the right endpoint when several lamps together represent a
state, as in a status display.

```http
POST /api/lamps
Content-Type: application/json

{
  "blue":  {"on": true, "effect": "pulse", "frequency": 0.3},
  "green": {"on": false}
}
```

Response: `{"lamps": [...]}` with all five lamps.

```bash
curl -X POST http://statusstacklight.local/api/lamps \
     -H 'Content-Type: application/json' \
     -d '{"blue":{"on":true,"effect":"pulse","frequency":0.3},"green":{"on":false}}'
```

```powershell
$target = @{
    blue  = @{ on = $true; effect = 'pulse'; frequency = 0.3 }
    green = @{ on = $false }
} | ConvertTo-Json
(Invoke-RestMethod http://statusstacklight.local/api/lamps -Method Post `
                   -Body $target -ContentType 'application/json').lamps
```

### POST /api/lamps/all

The same partial change for all five lamps, for example to dim them all:

```http
POST /api/lamps/all
Content-Type: application/json

{"brightness": 20}
```

Response: `{"lamps": [...]}` with all five lamps.

### Shortcuts

Switching via `GET`, without a body. Formally unclean, because a `GET` changes something,
but handy for the browser address bar and simple scripts.

```
GET /api/lamps/{id}/on
GET /api/lamps/{id}/off
GET /api/lamps/{id}/toggle
```

The [writable fields](#the-lamp-object) may also come along as query parameters. They are
applied after switching:

```
GET /api/lamps/red/on?brightness=30&effect=pulse&frequency=0.5
GET /api/lamps/3/on                  (channel 3 = green)
```

Response: the [lamp object](#the-lamp-object) of the lamp that was switched.

```bash
curl 'http://statusstacklight.local/api/lamps/red/on?brightness=30'
curl http://statusstacklight.local/api/lamps/red/off
```

```powershell
Invoke-RestMethod 'http://statusstacklight.local/api/lamps/red/on?brightness=30'
Invoke-RestMethod http://statusstacklight.local/api/lamps/red/off
```

The shortcuts only accept `GET`; other methods get `405`.

### GET /api/off

Turns all lamps off. Effect, brightness and rate are kept.

Response: `{"lamps": [...]}` with all five lamps.

## WiFi and maintenance

### GET /api/config

```json
{
  "hostname": "StatusStackLight",
  "mode": "sta",
  "ssid": "MyWiFi",
  "apName": "StatusStackLight-88A8",
  "baseFrequency": 1000,
  "relay": { "enabled": true, "url": "https://relay.example.org", "keySet": true }
}
```

`ssid` is the configured network, even while the setup access point is open. `apName` is
the name under which that access point appears; the suffix is the last two bytes of the MAC
address. `relay` holds the [relay settings](#post-apiconfigrelay); the key itself is never
given out, only whether one is set.

### GET /api/scan

Scans for WiFi networks in range. The response takes a few seconds.

```json
{
  "networks": [
    { "ssid": "MyWiFi",      "rssi": -64, "encrypted": true },
    { "ssid": "Neighbour-5G", "rssi": -81, "encrypted": true }
  ]
}
```

A network with several access points may appear more than once.

### POST /api/config/wifi

Sets the WiFi credentials. This is meant for the setup page `/setup`, which uses this
endpoint.

```http
POST /api/config/wifi
Content-Type: application/json

{"ssid": "MyWiFi", "password": "secret"}
```

**The device tries the credentials before storing them.** It connects to the given network
and waits up to **20 seconds**. Only if that works do the credentials go into flash. The
response therefore only comes after the attempt.

Success – `200`:

```json
{"ok": true, "ssid": "MyWiFi", "ip": "192.168.178.72"}
```

`ip` is the address the device got on the new network.

Failure – `400`:

```json
{"error": "could not connect to 'MyWiFi' - check password and range"}
```

```json
{"error": "ssid must not be empty"}
```

**From the setup access point** – the intended way:

- The access point stays open during the attempt, so the request can be answered.
- On failure, the error message arrives and the access point stays open.
- On success, the device closes the access point. The response is often lost because the
  client loses its connection at exactly that moment. In this case an aborted request is
  therefore the sign of success. Afterwards the device is reachable on the new network at
  `http://statusstacklight.local/`.

**During normal operation** (device already on a WiFi network): the connection attempt drops
the existing connection, so the response usually does not arrive.

- On success, the device is on the new network afterwards.
- On failure, the device reconnects to the previous network, at the latest 20 seconds after
  the failed attempt. The stored credentials stay unchanged. Whether the attempt worked is
  shown afterwards by [`/api/config`](#get-apiconfig) in the `ssid` field.

The password is transmitted in plain text – HTTP is unencrypted, and the setup access point
is an open network.

```bash
curl -X POST http://192.168.4.1/api/config/wifi \
     -H 'Content-Type: application/json' \
     -d '{"ssid":"MyWiFi","password":"secret"}' \
     --max-time 30
```

```powershell
$credentials = @{ ssid = 'MyWiFi'; password = 'secret' } | ConvertTo-Json
Invoke-RestMethod http://192.168.4.1/api/config/wifi -Method Post `
                  -Body $credentials -ContentType 'application/json' -TimeoutSec 30
```

The timeout must be longer than the 20 seconds of the connection attempt.

### POST /api/config/relay

Switches [relay mode](README.md#relay-mode) on or off and sets the relay's address and API
key. In relay mode the stack light fetches its state from the relay by long polling; the
lamp endpoints above keep working, but the relay's next change overwrites what was set
locally.

```http
POST /api/config/relay
Content-Type: application/json

{"enabled": true, "url": "https://relay.example.org", "key": "ssl_..."}
```

| Field | Type | Meaning |
|---|---|---|
| `enabled` | boolean, required | relay mode on or off |
| `url` | string, optional | `http://` or `https://`, host, optional port and path, no query. A trailing slash is removed. Left out: stays as stored. |
| `key` | string, optional | API key with the role *lamp* from the relay. Left out: stays as stored. |

Response: the stored settings, as under `relay` in [`/api/config`](#get-apiconfig):

```json
{"enabled": true, "url": "https://relay.example.org", "keySet": true}
```

The object from `/api/config` may be sent back as it is; `keySet` is ignored. Turning relay
mode on needs an address and a key – stored or sent along:

```json
{"error": "relay mode needs an address and a key"}
```

Switching off takes effect at once: an answer that is still on its way is discarded. New
settings are used from the next poll on, which then fetches the complete image. If a poll is
still waiting at the relay, that is at the latest after about 25 seconds. Whether it worked is
shown by [`/api/status`](#get-apistatus) under `relay`.

```powershell
$relay = @{ enabled = $true; url = 'https://relay.example.org'; key = 'ssl_...' } | ConvertTo-Json
Invoke-RestMethod http://statusstacklight.local/api/config/relay -Method Post `
                  -Body $relay -ContentType 'application/json'

# off again, address and key stay stored
Invoke-RestMethod http://statusstacklight.local/api/config/relay -Method Post `
                  -Body '{"enabled":false}' -ContentType 'application/json'
```

### GET /api/sweep

Starts the channel sweep: channels 1 to 5 light up one at a time for one second each at full
brightness, then the firmware restores the previous state. Also accepts `POST`.

```json
{"ok": true, "holdMs": 1000, "channels": 5}
```

The response comes immediately. The sweep takes `channels × holdMs`, and
[`/api/status`](#get-apistatus) shows under `sweep` whether it is still running. Write
requests during the sweep are lost: at the end, the firmware restores the state from before
the sweep.

### POST /api/reset

Deletes the WiFi credentials and restarts. Afterwards the device opens the setup access
point. The lamp state stays stored.

```json
{"ok": true, "message": "wifi credentials cleared, rebooting"}
```

### POST /api/reboot

Restarts the device. After a few seconds it is reachable again, and the lamps show the state
from before the restart.

```json
{"ok": true}
```

## Errors

Errors always come as a JSON object with an `error` field, in plain text.

| Status | When | Example of `error` |
|---|---|---|
| 400 | value out of range | `field 'brightness' out of range: got 150, expected 0...100` |
| 400 | wrong type or value | `field 'effect' must be one of: steady, blink, pulse` |
| 400 | unknown field | `unknown field: 'colour'` |
| 400 | unknown query parameter | `unknown query parameter: 'colour'` |
| 400 | not valid JSON | `invalid json: InvalidInput` |
| 400 | empty body | `request body is empty` |
| 400 | error in `POST /api/lamps` | `lamp green: field 'duty' out of range: got 0, expected 1...99` |
| 404 | unknown lamp | `unknown lamp: purple` |
| 404 | unknown shortcut | `unknown action: blink (on, off, toggle)` |
| 404 | unknown endpoint | `unknown endpoint: /api/foo` |
| 405 | method not allowed | `method not allowed (GET, PATCH, PUT)` |
| 405 | shortcut not via GET | `shortcut on is GET only` |

An unknown lamp also returns the list of valid IDs:

```json
{"error": "unknown lamp: purple", "lamps": ["white", "blue", "green", "orange", "red"]}
```

Handling errors in PowerShell:

```powershell
try {
    Invoke-RestMethod http://statusstacklight.local/api/lamps/red -Method Patch `
                      -Body '{"brightness":150}' -ContentType 'application/json'
} catch {
    "Status : " + [int] $_.Exception.Response.StatusCode
    "Error  : " + ($_.ErrorDetails.Message | ConvertFrom-Json).error
}
```

```
Status : 400
Error  : field 'brightness' out of range: got 150, expected 0...100
```

The PowerShell examples work in PowerShell 7 and in Windows PowerShell 5.1.
