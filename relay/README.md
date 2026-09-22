# StatusStackLight – Relay

A small ASP.NET Core service that sits between the Claude Code hooks and the stack light, so
computer and stack light no longer need to be on the same network:

```
 Claude Code ──hook──▶ stacklight.ps1 ──POST /api/v1/events──▶ ┌────────┐
 (any number of                                                 │ relay  │ ◀── admin interface
  computers)                                                    └────────┘     (browser)
                                                                    ▲
 stack light ──────────── GET /api/v1/lamps (long poll) ────────────┘
```

- The **hook script** reports every event (`SessionStart`, `Approval`, `Stop`, …) with its
  session ID – in [relay mode](../claude-code/README.md#relay-mode).
- The **relay** keeps the sessions of all computers and turns them into the image of the five
  lamps: which state wins, when green falls back to white, when a crashed session is
  forgotten, when the warning flash ends.
- The **stack light** fetches that image by long polling – in
  [relay mode](../firmware/README.md#relay-mode). A change arrives within a fraction of a
  second; while nothing happens, there is one request every 25 seconds.
- The **admin interface** sets what each event does and how each state looks, and manages
  the API keys. Out of the box it does exactly what the script does in LAN mode.

The relay needs no inbound connection to your home network – the stack light always calls
out.

## Admin interface

| Page | |
|---|---|
| Dashboard | what the stack light shows right now (animated), open sessions, polling stack lights, test events |
| Display | per state (ready, done, working, asking, waiting, error, warning flash): which lamps, effect, brightness, rate, duty cycle – with a live preview |
| Events | per hook event: which session state it sets, whether it sets or clears the error, an optional condition, warning flash |
| Settings | priority of the main states, done → ready after, forget sessions after, flash duration, long poll duration |
| Keys | create, rename, delete API keys |

Every page has *Reset to defaults*. The defaults live in one place,
[`Domain/Defaults.cs`](src/StatusStackLight.Relay/Domain/Defaults.cs).

**Keys** have a role: *lamp* keys may only fetch the display, *client* keys may only report
events. Give every stack light and every computer a key of its own – then a lost laptop is
one click away from being locked out. A key is shown exactly once when it is created; the
relay only stores its SHA-256 hash.

**The admin password** is set on the server, never over the web: an admin interface on the
internet that lets its first visitor choose the password is an open door until someone gets
there first. Login attempts are limited to ten per minute and address.

## Trying it locally

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download).

```powershell
cd relay/src/StatusStackLight.Relay
dotnet run -- set-password        # once: the admin password
dotnet run                        # http://localhost:5080
```

Create a *client* key and a *lamp* key under **Keys**. Then:

- **Hook script:** `setx STACKLIGHT_RELAY_URL "http://<this computer's IP>:5080"` and
  `setx STACKLIGHT_RELAY_KEY "ssl_…"` (the client key), restart Claude Code.
- **Stack light:** in its web interface under *Relay*: address
  `http://<this computer's IP>:5080`, the lamp key, relay mode on.

On Windows the firewall asks the first time whether `StatusStackLight.Relay.exe` may accept
connections – allow it for private networks, otherwise the stack light cannot reach it.

Data (database and login keys) ends up in `App_Data/` next to the project.

## Running it on a server

The following assumes a Linux server with nginx and a host name, e.g. `relay.example.org`.

**1. Publish** – self-contained, so the server needs no .NET runtime:

```bash
dotnet publish src/StatusStackLight.Relay -c Release -r linux-x64 --self-contained -o publish
```

For an ARM server (e.g. a Raspberry Pi): `-r linux-arm64`.

**2. Install:**

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin statusstacklight
sudo mkdir -p /opt/statusstacklight-relay
sudo rsync -a --delete publish/ /opt/statusstacklight-relay/     # or scp
sudo chmod +x /opt/statusstacklight-relay/StatusStackLight.Relay

sudo cp deploy/statusstacklight-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now statusstacklight-relay
```

**3. Set the admin password** – as the service user, with the same data directory as the
service:

```bash
cd /opt/statusstacklight-relay
sudo -u statusstacklight env DataDirectory=/var/lib/statusstacklight-relay \
     ./StatusStackLight.Relay set-password
```

The command can be run again at any time to change the password; logins stay valid.

**4. nginx with HTTPS:** adapt [`deploy/nginx.conf.example`](deploy/nginx.conf.example),
then `sudo certbot --nginx -d relay.example.org`. Important for long polling:
`proxy_read_timeout` must be longer than the relay's long poll duration (25 s by default);
the example uses 60 s.

The address for hook script and stack light is then `https://relay.example.org`.

**Updates:** publish again, copy over, `sudo systemctl restart statusstacklight-relay`. The
database is migrated automatically at startup. Stack lights reconnect by themselves within a
few seconds; sessions are held in memory only and come back with each session's next hook.

### Without nginx

The relay can also listen on a port directly: set `Urls=http://0.0.0.0:5080` in the systemd
unit and open the port in the firewall. **Then the API keys and the admin password travel over
the internet in plain text** – only do that for a test, or give Kestrel a certificate of its
own (see the ASP.NET Core documentation on `Kestrel:Certificates`).

### Configuration

Environment variables (or `appsettings.json`):

| Name | Default | |
|---|---|---|
| `Urls` | `http://*:5080` | address and port to listen on |
| `DataDirectory` | `App_Data` | database `relay.db` and the key ring for the login cookie `keys/`; relative to the working directory |
| `PathBase` | – | sub-path when served under e.g. `https://example.org/stacklight/` |

**Backup:** the data directory is all there is. Losing `keys/` only logs you out; losing
`relay.db` loses the API keys, the configuration and the admin password.

## API

For stack lights and scripts – see **[API.md](API.md)**.

## Development

```powershell
cd relay
dotnet test                                   # domain logic, API, admin pages
dotnet tool restore                           # once, for dotnet-ef
dotnet dotnet-ef migrations add <Name> -p src/StatusStackLight.Relay -o Data/Migrations
```

```
src/StatusStackLight.Relay/
  Domain/     display logic: sessions, event rules, lamp image, defaults – no ASP.NET
  Data/       SQLite via EF Core: API keys and the configuration (as JSON per section)
  Api/        JSON API, API key authentication, stack light registry
  Pages/      admin interface (Razor Pages)
  Services/   timer for time-driven transitions, admin password
  wwwroot/    CSS and the small script for preview and dashboard
tests/        xUnit: engine, validation, API, admin pages
deploy/       systemd unit, nginx example
```

**How the image comes about** – a port of `Get-MainState` and `Get-Lamps` from
[`stacklight.ps1`](../claude-code/stacklight.ps1):

1. Every event changes its session according to its rule (state, error flag).
2. Of the sessions, exactly one main state wins by priority: waiting > asking > working >
   done > ready. Done only counts while it is fresh (5 min); after that the session counts as
   ready. Sessions without events for an hour are forgotten.
3. On top: error (if any session has one), then the warning flash (for 1.2 s after `Danger`).
4. Lamps that are off still carry the parameters of their state, so the stack light's web
   interface shows sensible values.

The image carries a **version** that only changes when the image changes. A stack light
polls with the version it shows and gets an answer as soon as there is a different one –
a burst of events that ends where it started costs it nothing.
