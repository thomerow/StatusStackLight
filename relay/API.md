# StatusStackLight Relay – HTTP API

The API for hook scripts and stack lights. The admin interface is not part of it; it uses
its own forms. All responses shown are real responses from the relay.

**Ground rules:**

- Requests and responses are JSON, names in camelCase, enum values in lower case.
- Every request needs an API key: `Authorization: Bearer ssl_…`. Keys are created in the
  admin interface under *Keys* and have a role:

  | Role | May |
  |---|---|
  | `client` | report events (`POST /api/v1/events`), read the status |
  | `lamp` | fetch the display (`GET /api/v1/lamps`), read the status |

- Use HTTPS – the key is in a header. See the [README](README.md#running-it-on-a-server).

| Method | Path | Role | |
|---|---|---|---|
| POST | [`/api/v1/events`](#post-apiv1events) | client | report a hook event |
| GET | [`/api/v1/lamps`](#get-apiv1lamps) | lamp | the lamp image, long poll |
| GET | [`/api/v1/status`](#get-apiv1status) | client, lamp | state, sessions, stack lights |
| GET | [`/healthz`](#get-healthz) | – | for monitoring |

## POST /api/v1/events

Reports an event of a Claude Code session. What the event does is set in the admin interface
under *Events*.

```http
POST /api/v1/events
Authorization: Bearer ssl_...
Content-Type: application/json

{"event": "Approval", "session": "4f1c2a9e-docs", "host": "DESKTOP"}
```

| Field | | |
|---|---|---|
| `event` | required | `SessionStart`, `UserPromptSubmit`, `Approval`, `Question`, `ToolDone`, `Stop`, `StopFailure`, `ToolFailure`, `SessionEnd`, `Danger` – or `AllOff`, see below. Case does not matter. |
| `session` | required | ID of the session, at most 128 characters. Claude Code passes it to the hook as `session_id`. |
| `host` | optional | name of the computer, at most 64 characters – only for the dashboard |

```json
{"applied":true,"state":"waiting","error":false,"version":1790086577}
```

| Field | |
|---|---|
| `applied` | `false` if the event's rule has a condition that did not hold (e.g. `ToolDone` while the session is not waiting) – then nothing changed |
| `state` | main state the stack light now shows: `ready`, `done`, `working`, `asking`, `waiting`, or `null` without an open session |
| `error` | whether the error overlay is on |
| `version` | version of the lamp image |

**`AllOff`** is not a hook event: it makes the relay forget all sessions of all computers,
and the stack light goes dark until the next event. `session` is not needed for it.

Errors – `400`:

```json
{"error":"unknown event: Nope","events":["SessionStart","UserPromptSubmit","Approval","Question","ToolDone","Stop","StopFailure","ToolFailure","SessionEnd","Danger","AllOff"]}
```

```powershell
$event = @{ event = 'Stop'; session = 'test'; host = $env:COMPUTERNAME } | ConvertTo-Json
Invoke-RestMethod https://relay.example.org/api/v1/events -Method Post -Body $event `
                  -ContentType 'application/json' -Headers @{ Authorization = 'Bearer ssl_...' }
```

## GET /api/v1/lamps

The image of the five lamps, exactly in the form the firmware's
[`POST /api/lamps`](../firmware/API.md#post-apilamps) takes – a stack light can apply
`lamps` as it is.

**Long polling:** `version` is the version the caller already shows. If the relay has a
different one, it answers at once. Otherwise it holds the request until the image changes,
at the latest `wait` seconds, and then answers with the unchanged image.

| Parameter | Default | |
|---|---|---|
| `version` | `0` | version the caller shows; `0` always gets an immediate answer |
| `wait` | long poll duration (25 s) | longest wait in seconds; capped at the long poll duration from *Settings* |

```
GET /api/v1/lamps?version=1790086576&wait=25
Authorization: Bearer ssl_...
```

```json
{"version":1790086577,"state":"waiting","error":false,"lamps":{
  "white":{"on":false,"effect":"pulse","brightness":30,"frequency":0.15,"duty":50},
  "blue":{"on":false,"effect":"pulse","brightness":70,"frequency":0.3,"duty":50},
  "green":{"on":false,"effect":"steady","brightness":45,"frequency":1,"duty":50},
  "orange":{"on":true,"effect":"blink","brightness":40,"frequency":1.2,"duty":55},
  "red":{"on":false,"effect":"steady","brightness":100,"frequency":1,"duty":50}}}
```

All five lamps are always included. Lamps that are off carry the parameters of their state,
so the stack light's web interface shows sensible values.

The version only changes when the image changes, and it starts at the relay's start time in
Unix seconds – after a restart of the relay, a stack light therefore never mistakes the new
count for the one it shows. Callers should only compare for equality.

The stack light sends `X-StackLight-Firmware` and `X-StackLight-Ip` along; the dashboard
shows them.

## GET /api/v1/status

What the relay shows and why. Readable with either role.

```json
{"state":"waiting","error":false,"flash":false,"version":1790086577,
 "sessions":[{"id":"4f1c2a9e","host":"DESKTOP","state":"waiting","error":false,"idleSeconds":0}],
 "stackLights":[{"name":"Desk","remoteAddress":"203.0.113.7","localAddress":"192.168.178.72",
                 "firmware":"1.1.0","lastSeen":"2026-09-22T14:19:04.1559465+00:00",
                 "version":1790086577,"polling":true}],
 "lamps":{ … as with /api/v1/lamps … }}
```

| Field | |
|---|---|
| `flash` | the warning flash is on right now |
| `sessions[].id` | the first 8 characters of the session ID |
| `sessions[].state` | `idle`, `working`, `asking`, `waiting`, `done` – the state of this one session |
| `sessions[].idleSeconds` | seconds since its last event |
| `stackLights[]` | stack lights that have polled since the relay started, one per key |
| `stackLights[].polling` | a request of this stack light is waiting at the relay right now |

`stacklight.ps1 -Event Status` shows the same in relay mode.

## GET /healthz

No key needed. Answers `ok` as plain text – for monitoring or a load balancer.

## Errors

A JSON object with `error` – except for a body that is not valid JSON at all, which
ASP.NET Core rejects with an empty `400`.

| Status | When |
|---|---|
| 400 | invalid event, missing or too long session, body not valid JSON |
| 401 | no key or an unknown key: `{"error":"missing or unknown api key"}` |
| 403 | key with the wrong role: `{"error":"this api key is not allowed here"}` |
