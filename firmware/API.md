# StatusStackLight – HTTP-API

Die Säule wird über eine JSON-API im lokalen Netz gesteuert. Dieses Dokument beschreibt alle
Endpunkte mit Anfrage und Antwort. Alle gezeigten Antworten sind echte Antworten des Geräts;
gekürzt ist, wo es vermerkt ist, und Netznamen sind durch Beispielnamen ersetzt.

**Adresse:** `http://statusstacklight.local/` oder die IP-Adresse des Geräts. Im
Konfigurations-Accesspoint ist es `http://192.168.4.1/`.

**Grundregeln:**

- Anfragen und Antworten sind JSON (`Content-Type: application/json`).
- Jede schreibende Anfrage antwortet mit dem **resultierenden** Zustand. Der Client muss nie
  raten, was angekommen ist.
- Ungültige Werte werden **abgelehnt, nicht zurechtgebogen**. Eine Anfrage wird entweder
  vollständig übernommen oder gar nicht.
- Es gibt keine Anmeldung. Jeder im selben Netz kann die Säule schalten und die
  WLAN-Einstellungen ändern.
- CORS ist offen (`Access-Control-Allow-Origin: *`), die API lässt sich also auch aus einer
  Web-Seite heraus ansprechen.

## Übersicht

| Methode | Pfad | Body | Antwort | Zweck |
|---|---|---|---|---|
| GET | [`/api/status`](#get-apistatus) | – | Gerätestatus + alle Lampen | alles auf einen Blick |
| GET | [`/api/lamps`](#get-apilamps) | – | `{lamps: [...]}` | alle fünf Lampen |
| GET | [`/api/lamps/{id}`](#get-apilampsid) | – | Lampe | eine Lampe |
| PATCH | [`/api/lamps/{id}`](#patch-apilampsid) | Teilzustand | Lampe | einzelne Felder ändern |
| PUT | [`/api/lamps/{id}`](#put-apilampsid) | Zustand | Lampe | Zustand komplett setzen |
| POST | [`/api/lamps`](#post-apilamps) | `{id: Teilzustand, ...}` | `{lamps: [...]}` | mehrere Lampen auf einmal |
| POST | [`/api/lamps/all`](#post-apilampsall) | Teilzustand | `{lamps: [...]}` | dieselbe Änderung für alle |
| GET | [`/api/lamps/{id}/on`](#kurzbefehle) | Query | Lampe | einschalten |
| GET | [`/api/lamps/{id}/off`](#kurzbefehle) | Query | Lampe | ausschalten |
| GET | [`/api/lamps/{id}/toggle`](#kurzbefehle) | Query | Lampe | umschalten |
| GET | [`/api/off`](#get-apioff) | – | `{lamps: [...]}` | alle aus |
| GET | [`/api/config`](#get-apiconfig) | – | Konfiguration | Hostname, WLAN-Modus |
| GET | [`/api/scan`](#get-apiscan) | – | `{networks: [...]}` | WLANs in Reichweite |
| POST | [`/api/config/wifi`](#post-apiconfigwifi) | `{ssid, password}` | `{ok, ssid, ip}` | WLAN-Zugang setzen |
| GET/POST | [`/api/sweep`](#get-apisweep) | – | `{ok, holdMs, channels}` | Kanal-Durchlauf |
| POST | [`/api/reset`](#post-apireset) | – | `{ok, message}` | WLAN-Zugang löschen, Neustart |
| POST | [`/api/reboot`](#post-apireboot) | – | `{ok}` | Neustart |

`{id}` ist die Farb-ID einer Lampe (`white`, `blue`, `green`, `orange`, `red`) oder ihre
Kanalnummer `1` bis `5`. Groß- und Kleinschreibung spielt keine Rolle.

| Kanal | ID | Farbe |
|---|---|---|
| 1 | `white` | weiß |
| 2 | `blue` | blau |
| 3 | `green` | grün |
| 4 | `orange` | orange |
| 5 | `red` | rot |

## Das Lampenobjekt

So sieht eine Lampe in jeder Antwort aus:

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

**Schreibbare Felder:**

| Feld | Typ | Bereich | Standard | Bedeutung |
|---|---|---|---|---|
| `on` | Boolean | `true` / `false` | `false` | Hauptschalter |
| `effect` | String | `steady`, `blink`, `pulse` | `steady` | dauerhaft / hartes Blinken / weiches Pulsieren |
| `brightness` | Ganzzahl | 0…100 | 100 | Spitzenhelligkeit in %, gammakorrigiert |
| `frequency` | Zahl | 0.1…20.0 | 1.0 | Takt in Hz für `blink` und `pulse` |
| `duty` | Ganzzahl | 1…99 | 50 | nur `blink`: Anteil der Periode in %, in dem die Lampe leuchtet |

`on` ist vom Effekt getrennt. Wer eine blinkende Lampe ausschaltet und wieder einschaltet,
bekommt sie blinkend zurück: Helligkeit, Effekt und Takt überleben das Ausschalten.

Lampen mit derselben Frequenz blinken und pulsieren synchron, weil die Firmware für alle eine
gemeinsame Zeitbasis benutzt. Einen Zustand erneut zu senden, setzt die Phase nicht zurück.

**Nur lesbare Felder:**

| Feld | Bedeutung |
|---|---|
| `id` | Farb-ID, fest |
| `channel` | Kanalnummer 1…5 |
| `gpio` | GPIO-Pin am ESP32 |
| `name` | Anzeigename im Web-Interface |
| `color` | Anzeigefarbe im Web-Interface |
| `level` | Helligkeit in %, die in diesem Moment tatsächlich ausgegeben wird – bei `pulse` und `blink` ändert sie sich ständig |

Die nur lesbaren Felder dürfen in einer schreibenden Anfrage mitgeschickt werden und werden
dann ignoriert. Eine gelesene Lampe lässt sich also unverändert zurückschicken.

`level` stammt aus dem letzten Takt der Effekt-Engine, die alle 10 ms rechnet. In der Antwort
auf eine Änderung zeigt es deshalb noch den Stand von vor der Änderung.

Der Zustand aller Lampen übersteht einen Neustart; die Firmware speichert ihn im Flash.

## Lesen

### GET /api/status

Alles auf einen Blick: Gerät, WLAN, PWM, Kanal-Durchlauf, Anzeigereihenfolge und alle
Lampen.

```json
{
  "device": "StatusStackLight",
  "firmware": "1.0.0",
  "uptime": 2192,
  "heap": 275504,
  "psram": 8385831,
  "wifi": {
    "mode": "sta",
    "ssid": "MeinWLAN",
    "ip": "192.168.178.72",
    "rssi": -66,
    "connected": true,
    "hostname": "StatusStackLight.local"
  },
  "pwm": { "baseFrequency": 1000, "resolution": 12, "activeLow": true },
  "sweep": { "running": false, "channel": 0 },
  "display": "none",
  "order": ["red", "orange", "green", "blue", "white"],
  "lamps": [ … fünf Lampenobjekte … ]
}
```

| Feld | Bedeutung |
|---|---|
| `uptime` | Sekunden seit dem Start |
| `heap` | freier Arbeitsspeicher in Byte |
| `psram` | Größe des PSRAM in Byte; beim N16R8 rund 8 MB |
| `wifi.mode` | `sta` = im WLAN, `ap` = Konfigurations-Accesspoint offen |
| `wifi.ssid` | im Modus `sta` das verbundene WLAN, im Modus `ap` der Name des Accesspoints |
| `wifi.rssi` | Signalstärke in dBm; im Modus `ap` immer 0 |
| `pwm` | PWM-Trägerfrequenz in Hz, Auflösung in Bit, ob die Ausgänge LOW-aktiv sind |
| `sweep.channel` | während des Kanal-Durchlaufs der gerade leuchtende Kanal 1…5, sonst 0 |
| `display` | Startanzeige, die gerade den Lampenzustand überlagert: `connecting` (blau pulsiert), `portal` (orange pulsiert), `connected` (grünes Signal) oder `none`. Solange sie nicht `none` ist, zeigen die Lampen nicht den Zustand aus `lamps` – Änderungen werden trotzdem übernommen und erscheinen danach. |
| `order` | Reihenfolge der Lampen an der Säule von oben nach unten |

```bash
curl http://statusstacklight.local/api/status
```

```powershell
$s = Invoke-RestMethod http://statusstacklight.local/api/status
"{0} {1}, {2}, {3} dBm" -f $s.device, $s.firmware, $s.wifi.ip, $s.wifi.rssi
```

### GET /api/lamps

```json
{ "lamps": [ … fünf Lampenobjekte, Kanal 1 bis 5 … ] }
```

### GET /api/lamps/{id}

```bash
curl http://statusstacklight.local/api/lamps/orange
curl http://statusstacklight.local/api/lamps/4          # dieselbe Lampe
```

```powershell
Invoke-RestMethod http://statusstacklight.local/api/lamps/orange
```

Antwort: ein [Lampenobjekt](#das-lampenobjekt).

## Schreiben

### PATCH /api/lamps/{id}

Ändert nur die gesendeten Felder, alle anderen bleiben, wie sie sind. Der übliche Weg, eine
Lampe zu verstellen.

```http
PATCH /api/lamps/orange
Content-Type: application/json

{"on": true, "effect": "blink", "frequency": 2}
```

```json
{"id":"orange","channel":4,"gpio":7,"name":"orange","color":"#f59e0b",
 "on":true,"effect":"blink","brightness":50,"frequency":2,"duty":55,"level":0}
```

`brightness` und `duty` sind unverändert geblieben.

```bash
curl -X PATCH http://statusstacklight.local/api/lamps/orange \
     -H 'Content-Type: application/json' \
     -d '{"on":true,"effect":"blink","frequency":2}'
```

```powershell
$aenderung = @{ on = $true; effect = 'blink'; frequency = 2 } | ConvertTo-Json
Invoke-RestMethod http://statusstacklight.local/api/lamps/orange -Method Patch `
                  -Body $aenderung -ContentType 'application/json'
```

### PUT /api/lamps/{id}

Setzt den kompletten Zustand. Felder, die fehlen, bekommen ihren
[Standardwert](#das-lampenobjekt) – nicht den bisherigen.

```http
PUT /api/lamps/orange
Content-Type: application/json

{"on": true}
```

```json
{"id":"orange","channel":4,"gpio":7,"name":"orange","color":"#f59e0b",
 "on":true,"effect":"steady","brightness":100,"frequency":1,"duty":50,"level":50}
```

Effekt, Helligkeit, Takt und Tastgrad stehen danach auf Standard, obwohl nur `on` gesendet
wurde. Wer nur einschalten will, nimmt `PATCH`.

### POST /api/lamps

Mehrere Lampen in einer Anfrage. Schlüssel ist die ID oder Kanalnummer, Wert ein Teilzustand
wie bei `PATCH`. Nicht genannte Lampen bleiben unverändert.

Die Firmware prüft erst alle Einträge und übernimmt dann alle zugleich. Ist einer ungültig,
ändert sich an keiner Lampe etwas. Dieser Endpunkt ist der richtige, wenn mehrere Lampen
zusammen einen Zustand darstellen, etwa bei einer Statusanzeige.

```http
POST /api/lamps
Content-Type: application/json

{
  "blue":  {"on": true, "effect": "pulse", "frequency": 0.3},
  "green": {"on": false}
}
```

Antwort: `{"lamps": [...]}` mit allen fünf Lampen.

```bash
curl -X POST http://statusstacklight.local/api/lamps \
     -H 'Content-Type: application/json' \
     -d '{"blue":{"on":true,"effect":"pulse","frequency":0.3},"green":{"on":false}}'
```

```powershell
$ziel = @{
    blue  = @{ on = $true; effect = 'pulse'; frequency = 0.3 }
    green = @{ on = $false }
} | ConvertTo-Json
(Invoke-RestMethod http://statusstacklight.local/api/lamps -Method Post `
                   -Body $ziel -ContentType 'application/json').lamps
```

### POST /api/lamps/all

Dieselbe Teiländerung für alle fünf Lampen, zum Beispiel alle dimmen:

```http
POST /api/lamps/all
Content-Type: application/json

{"brightness": 20}
```

Antwort: `{"lamps": [...]}` mit allen fünf Lampen.

### Kurzbefehle

Schalten per `GET`, ohne Body. Das ist formal unsauber, weil ein `GET` etwas verändert, aber
praktisch für die Browser-Adresszeile und einfache Skripte.

```
GET /api/lamps/{id}/on
GET /api/lamps/{id}/off
GET /api/lamps/{id}/toggle
```

Zusätzlich dürfen die [schreibbaren Felder](#das-lampenobjekt) als Query-Parameter
mitkommen. Sie werden nach dem Schalten angewandt:

```
GET /api/lamps/red/on?brightness=30&effect=pulse&frequency=0.5
GET /api/lamps/3/on                  (Kanal 3 = grün)
```

Antwort: das [Lampenobjekt](#das-lampenobjekt) der geschalteten Lampe.

```bash
curl 'http://statusstacklight.local/api/lamps/red/on?brightness=30'
curl http://statusstacklight.local/api/lamps/red/off
```

```powershell
Invoke-RestMethod 'http://statusstacklight.local/api/lamps/red/on?brightness=30'
Invoke-RestMethod http://statusstacklight.local/api/lamps/red/off
```

Die Kurzbefehle nehmen nur `GET` an; andere Methoden bekommen `405`.

### GET /api/off

Schaltet alle Lampen aus. Effekt, Helligkeit und Takt bleiben dabei erhalten.

Antwort: `{"lamps": [...]}` mit allen fünf Lampen.

## WLAN und Wartung

### GET /api/config

```json
{
  "hostname": "StatusStackLight",
  "mode": "sta",
  "ssid": "MeinWLAN",
  "apName": "StatusStackLight-88A8",
  "baseFrequency": 1000
}
```

`ssid` ist das eingerichtete WLAN, auch dann, wenn gerade der Konfigurations-Accesspoint
offen ist. `apName` ist der Name, unter dem dieser Accesspoint erscheint; die Endung sind die
letzten beiden Bytes der MAC-Adresse.

### GET /api/scan

Sucht WLANs in Reichweite. Die Antwort braucht einige Sekunden.

```json
{
  "networks": [
    { "ssid": "MeinWLAN",   "rssi": -64, "encrypted": true },
    { "ssid": "Nachbar-5G", "rssi": -81, "encrypted": true }
  ]
}
```

Ein WLAN mit mehreren Accesspoints kann mehrfach vorkommen.

### POST /api/config/wifi

Setzt die WLAN-Zugangsdaten. Dafür ist die Konfigurationsseite `/setup` gedacht, die diesen
Endpunkt benutzt.

```http
POST /api/config/wifi
Content-Type: application/json

{"ssid": "MeinWLAN", "password": "geheim"}
```

**Das Gerät probiert die Daten aus, bevor es sie speichert.** Es verbindet sich mit dem
angegebenen WLAN und wartet bis zu **20 Sekunden**. Erst wenn das klappt, landen die Daten im
Flash. Die Antwort kommt deshalb erst nach dem Versuch.

Erfolg – `200`:

```json
{"ok": true, "ssid": "MeinWLAN", "ip": "192.168.178.72"}
```

`ip` ist die Adresse, die das Gerät im neuen WLAN bekommen hat.

Fehlschlag – `400`:

```json
{"error": "could not connect to 'MeinWLAN' - check password and range"}
```

```json
{"error": "ssid must not be empty"}
```

**Aus dem Konfigurations-Accesspoint heraus** – der vorgesehene Weg:

- Während des Versuchs bleibt der Accesspoint offen, die Anfrage kann also antworten.
- Bei einem Fehlschlag kommt die Fehlermeldung an, und der Accesspoint bleibt offen.
- Bei Erfolg schließt das Gerät den Accesspoint. Die Antwort geht dabei oft verloren, weil
  der Client in genau diesem Moment die Verbindung verliert. Ein Abbruch der Anfrage ist in
  diesem Fall also das Zeichen für Erfolg. Danach ist das Gerät im neuen WLAN unter
  `http://statusstacklight.local/` erreichbar.

**Im laufenden Betrieb** (Gerät bereits im WLAN): Der Verbindungsversuch trennt die
bestehende Verbindung, die Antwort kommt deshalb in aller Regel nicht an.

- Bei Erfolg ist das Gerät danach im neuen WLAN.
- Bei einem Fehlschlag verbindet sich das Gerät wieder mit dem bisherigen WLAN, spätestens
  20 Sekunden nach dem gescheiterten Versuch. Die gespeicherten Zugangsdaten bleiben
  unverändert. Ob der Versuch geklappt hat, zeigt danach [`/api/config`](#get-apiconfig) im
  Feld `ssid`.

Das Passwort wird im Klartext übertragen – HTTP ist unverschlüsselt, und der
Konfigurations-Accesspoint ist ein offenes WLAN.

```bash
curl -X POST http://192.168.4.1/api/config/wifi \
     -H 'Content-Type: application/json' \
     -d '{"ssid":"MeinWLAN","password":"geheim"}' \
     --max-time 30
```

```powershell
$zugang = @{ ssid = 'MeinWLAN'; password = 'geheim' } | ConvertTo-Json
Invoke-RestMethod http://192.168.4.1/api/config/wifi -Method Post `
                  -Body $zugang -ContentType 'application/json' -TimeoutSec 30
```

Das Zeitlimit muss über den 20 Sekunden des Verbindungsversuchs liegen.

### GET /api/sweep

Startet den Kanal-Durchlauf: Die Kanäle 1 bis 5 leuchten nacheinander je eine Sekunde einzeln
mit voller Helligkeit, danach stellt die Firmware den vorherigen Zustand wieder her. Nimmt
auch `POST` an.

```json
{"ok": true, "holdMs": 1000, "channels": 5}
```

Die Antwort kommt sofort. Der Durchlauf dauert `channels × holdMs`, und
[`/api/status`](#get-apistatus) zeigt unter `sweep`, ob er noch läuft. Schreibende Anfragen
während des Durchlaufs gehen verloren: Am Ende stellt die Firmware den Zustand von vor dem
Durchlauf wieder her.

### POST /api/reset

Löscht die WLAN-Zugangsdaten und startet neu. Danach öffnet das Gerät den
Konfigurations-Accesspoint. Der Lampenzustand bleibt gespeichert.

```json
{"ok": true, "message": "wifi credentials cleared, rebooting"}
```

### POST /api/reboot

Startet das Gerät neu. Nach einigen Sekunden ist es wieder erreichbar, und die Lampen zeigen
den Zustand von vor dem Neustart.

```json
{"ok": true}
```

## Fehler

Fehler kommen immer als JSON-Objekt mit dem Feld `error`, im Klartext.

| Status | Wann | Beispiel für `error` |
|---|---|---|
| 400 | Wert außerhalb des Bereichs | `field 'brightness' out of range: got 150, expected 0...100` |
| 400 | falscher Typ oder Wert | `field 'effect' must be one of: steady, blink, pulse` |
| 400 | unbekanntes Feld | `unknown field: 'colour'` |
| 400 | unbekannter Query-Parameter | `unknown query parameter: 'colour'` |
| 400 | kein gültiges JSON | `invalid json: InvalidInput` |
| 400 | leerer Body | `request body is empty` |
| 400 | Fehler in `POST /api/lamps` | `lamp green: field 'duty' out of range: got 0, expected 1...99` |
| 404 | unbekannte Lampe | `unknown lamp: purple` |
| 404 | unbekannter Kurzbefehl | `unknown action: blink (on, off, toggle)` |
| 404 | unbekannter Endpunkt | `unknown endpoint: /api/foo` |
| 405 | Methode nicht erlaubt | `method not allowed (GET, PATCH, PUT)` |
| 405 | Kurzbefehl nicht per GET | `shortcut on is GET only` |

Eine unbekannte Lampe liefert zusätzlich die Liste der gültigen IDs:

```json
{"error": "unknown lamp: purple", "lamps": ["white", "blue", "green", "orange", "red"]}
```

Fehler in PowerShell auswerten:

```powershell
try {
    Invoke-RestMethod http://statusstacklight.local/api/lamps/red -Method Patch `
                      -Body '{"brightness":150}' -ContentType 'application/json'
} catch {
    "Status : " + [int] $_.Exception.Response.StatusCode
    "Fehler : " + ($_.ErrorDetails.Message | ConvertFrom-Json).error
}
```

```
Status : 400
Fehler : field 'brightness' out of range: got 150, expected 0...100
```

Die PowerShell-Beispiele laufen in PowerShell 7 und in Windows PowerShell 5.1.
