# StatusStackLight – Firmware (ESP32-S3)

Firmware für die 5-Lampen-Signalsäule. Sie stellt eine HTTP-JSON-API zur Ansteuerung der
Lampen bereit und ein Web-Interface, mit dem sich jede Lampe einzeln in allen Parametern
durchspielen lässt – gedacht sowohl zum Prüfen der Verkabelung als auch als Grundlage für
die spätere Anbindung.

Das Gehäuse und die Mechanik liegen im Nachbarverzeichnis [`../Gehäuse`](../Geh%C3%A4use).

## Was die Lampen können

Jede Lampe hat einen Hauptschalter, eine Helligkeit und ein Zeitverhalten:

| Feld | Bereich | Bedeutung |
|---|---|---|
| `on` | `true` / `false` | Hauptschalter |
| `brightness` | 0…100 % | Spitzenhelligkeit, gammakorrigiert |
| `effect` | `steady`, `blink`, `pulse` | dauerhaft / hartes Blinken / weiches Pulsieren |
| `frequency` | 0.1…20.0 Hz | Takt für `blink` und `pulse` |
| `duty` | 1…99 % | nur `blink`: Anteil der Periode, in dem die Lampe leuchtet |

`on` ist bewusst vom Effekt getrennt. Wer eine blinkende Lampe ausschaltet und wieder
einschaltet, bekommt sie blinkend zurück – Helligkeit und Effekt überleben das Ausschalten.

Mehrere Lampen mit derselben Frequenz blinken synchron; die Effekt-Engine benutzt für alle
fünf eine gemeinsame Zeitbasis.

## Hardware

| Punkt | Wert |
|---|---|
| Board | ESP32-S3 DevKitC-1, **N16R8** (16 MB Flash, 8 MB Octal-PSRAM) |
| Treiber | 8-Kanal-MOSFET-Modul, low-side, **LOW-aktiv** (GPIO auf Masse = Lampe an) |
| Leuchtmittel | 12-V-LED-Module |
| Versorgung | USB-C-PD-Triggerboard (12 V) → Mini560-Buck → 5 V an den ESP32 |

### Kanalbelegung

| Kanal | GPIO | Farbe | API-ID |
|---|---|---|---|
| 1 | 4 | weiß | `white` |
| 2 | 5 | blau | `blue` |
| 3 | 6 | grün | `green` |
| 4 | 7 | orange | `orange` |
| 5 | 15 | rot | `red` |

Diese Zuordnung stammt aus der bisher produktiv laufenden Ansteuerung und war **nie gegen
die Hardware geprüft**. Genau dafür gibt es den Kanal-Durchlauf (siehe unten). Stimmt etwas
nicht, werden in `include/config.h` die Zeilen der Tabelle `LAMPEN[]` getauscht – sonst
nichts.

## Erstinbetriebnahme

1. **Flashen** (siehe [Bauen und flashen](#bauen-und-flashen)).
2. Beim ersten Start findet das Gerät keine WLAN-Zugangsdaten und spannt einen offenen
   Accesspoint **`StatusStackLight-XXXX`** auf (`XXXX` = die letzten beiden Bytes der
   MAC-Adresse, siehe serielle Konsole).
3. Mit dem Handy verbinden – die Konfigurationsseite öffnet sich als Captive Portal von
   selbst. Falls nicht: `http://192.168.4.1/setup`.
4. Netz auswählen, Passwort eingeben, speichern. Das Gerät **probiert die Daten erst aus**
   und speichert sie nur, wenn die Verbindung zustande kommt – ein Tippfehler sperrt dich
   also nicht aus. Deshalb dauert die Antwort bis zu 20 Sekunden.
5. Danach ist es unter **`http://statusstacklight.local/`** erreichbar (bzw. unter der IP,
   die die Konfigurationsseite meldet – Android löst `.local` nicht zuverlässig auf).

Die Lampen funktionieren auch im Accesspoint-Modus. Die Verkabelung lässt sich damit
vollständig ohne vorhandenes WLAN prüfen.

## Verkabelung prüfen

Im Web-Interface unten: **Kanal-Durchlauf**. Er schaltet die Kanäle 1 bis 5 nacheinander für
je eine Sekunde einzeln ein und meldet dabei auf der seriellen Konsole, welche Farbe erwartet
wird:

```
[durchlauf] Kanal 1  GPIO  4  erwartet: weiss
[durchlauf] Kanal 2  GPIO  5  erwartet: blau
...
```

Danach wird der vorherige Zustand wiederhergestellt. Auch per API: `GET /api/sweep`.

Worauf beim ersten Test zu achten ist:

- **Direkt nach dem Reset** müssen alle fünf GPIOs auf 3,3 V liegen (= aus), ohne kurzes
  Absacken. Sackt die Spannung ab und die Säule blitzt beim Booten auf, fehlen dem
  MOSFET-Modul die Pullups an den Steuereingängen – dann je 10 kΩ nach 3,3 V nachrüsten.
- **Bei `brightness = 0` bzw. `on = false`** muss die Lampe vollständig dunkel sein. Im
  Dunkeln gegenprüfen (siehe den Kommentar zu `PWM_MAX` in `config.h`).
- **Weiß bei 10–20 %** ist der eigentliche Grund für die PWM-Regelung: die Lampe soll als
  Präsenzanzeige dauerhaft leuchten können, ohne zu blenden.
- Verhält sich das Modul invertiert zur Erwartung, genügt `LAMPE_LOW_AKTIV = false` in
  `config.h`.

## API

Alle Antworten sind JSON und enthalten immer den **resultierenden** Zustand – der Client muss
nie raten, was angekommen ist.

### Lesen

```
GET /api/status          Firmware, Uptime, Heap, WLAN, PWM-Einstellung, alle Lampen
GET /api/lamps           alle fünf Lampen
GET /api/lamps/red       eine Lampe
```

### Schreiben

```
PATCH /api/lamps/red     nur die gesendeten Felder ändern sich
PUT   /api/lamps/red     vollständiger Zustand, fehlende Felder auf Standard
POST  /api/lamps         mehrere Lampen atomar
POST  /api/lamps/all     dieselbe Teiländerung auf alle fünf
```

```bash
curl -X PATCH http://statusstacklight.local/api/lamps/orange \
     -H 'Content-Type: application/json' \
     -d '{"on":true,"effect":"blink","brightness":80,"frequency":2.0,"duty":50}'

curl -X POST http://statusstacklight.local/api/lamps \
     -H 'Content-Type: application/json' \
     -d '{"blue":{"on":true,"effect":"pulse"},"green":{"on":false}}'
```

Bei `POST /api/lamps` wird erst alles geprüft und dann alles übernommen. Ein Tippfehler im
dritten Eintrag lässt die ersten beiden also nicht auf halbem Weg stehen.

### Kurzbefehle (GET)

Formal unsauber, praktisch unschlagbar für Skripte und die Browser-Adresszeile:

```
GET /api/lamps/red/on?brightness=50&effect=blink&frequency=2&duty=30
GET /api/lamps/red/off
GET /api/lamps/red/toggle
GET /api/lamps/3/on             Ansprache per Kanalnummer (3 = grün)
GET /api/off                    alle aus
```

### Konfiguration und Wartung

```
GET  /api/config          Hostname, Modus, SSID, PWM-Grundfrequenz
POST /api/config/wifi     {"ssid":"...","password":"..."}
GET  /api/scan            gefundene Netze
GET  /api/sweep           Kanal-Durchlauf starten
POST /api/reset           WLAN-Daten löschen und neu starten
POST /api/reboot
```

### Fehler

- Unbekannte Lampe → `404` mit der Liste der gültigen IDs.
- Wert außerhalb des Bereichs → `400` mit Feld, empfangenem Wert und gültigem Bereich.
  **Kein stilles Zurechtbiegen** – beim Verkabelungstest will man wissen, wenn etwas nicht
  so ankommt, wie man es geschickt hat.
- Ungültiges JSON → `400` mit der Meldung des Parsers im Klartext.

## Bauen und flashen

```powershell
pio run                 # bauen
pio run -t upload       # bauen und flashen
pio device monitor      # serielle Konsole, 115200 Baud
```

Zwei Umgebungen, je nach benutzter USB-C-Buchse am DevKitC-1 (auf dem Gehäusedeckel als
`USB` und `COM` beschriftet):

| Umgebung | Buchse | |
|---|---|---|
| `uart` (Standard) | **COM** | Empfohlen. Der Port bleibt über Reset und Flashen hinweg bestehen, und man sieht zusätzlich die Ausgabe des ROM-Bootloaders. |
| `usb` | **USB** | Native USB-Buchse. Funktioniert, aber der COM-Port verschwindet bei jedem Reset. |

```powershell
pio run -e usb -t upload
```

Der erste Build lädt Plattform und Xtensa-Toolchain nach – das dauert und braucht Internet.

### Zwei Dinge, die hier absichtlich so stehen

**`build_dir` zeigt aus dem Projekt heraus** (`C:/pio/StatusStackLight`). Zum einen enthält
der Projektpfad einen Umlaut (`Signalsäule`), und Nicht-ASCII in Pfaden ist von PlatformIO
ausdrücklich nicht unterstützt. Zum anderen sind `.pio/build` rund zehntausend Dateien – in
einem Dropbox-Ordner heißt das Dauersynchronisation und gelegentlich eine gesperrte Datei
mitten im Build.

**`board_build.arduino.memory_type = qio_opi`** passt zum ESP32-S3-**WROOM-1** N16R8 (Quad-Flash,
Octal-PSRAM). Das ähnlich heißende WROOM-**2** N16R8**V** hat Octal-Flash mit 1,8 V und bräuchte
`opi_opi` plus `flash_mode = dout` – damit startet das Board sonst gar nicht erst. Im Zweifel
den Aufdruck auf dem Modul lesen. Die Startmeldung gibt die PSRAM-Größe aus; stehen dort
statt rund 8 MB null Bytes, stimmt die Einstellung nicht.

## Aufbau

```
platformio.ini          Board, Umgebungen, Bibliotheken
include/config.h        Pins, Farben, Grenzwerte, Standardwerte  <- hier wird geschraubt
scripts/embed_web.py    Pre-Build: web/*.html -> include/web_assets.h (gzip)
web/index.html          Steuerseite (Quelle)
web/setup.html          WLAN-Konfigurationsseite (Quelle)
src/main.cpp            setup/loop
src/lampen.*            LEDC, Effekt-Engine, Gamma, Invertierung
src/lampenzustand.*     Zustand einer Lampe, Prüfung, JSON
src/wlan_portal.*       Zugangsdaten, STA-Verbindung, Konfig-AP, Captive Portal
src/api_server.*        HTTP-Routen
```

Das Web-Interface wird beim Build gzippt und als Bytefeld ins Firmware-Image eingebettet.
Die HTML-Dateien bleiben dadurch normale, editierbare Dateien, und trotzdem genügt ein
einziger Upload-Schritt – kein separates Flashen eines Dateisystems, das man nach einem OTA
garantiert vergisst. `include/web_assets.h` ist generiert und steht in `.gitignore`.

### Warum die Effekte in einem eigenen Task laufen

Die LEDC-Grundfrequenz bleibt konstant bei 1 kHz; die Effekte modulieren nur das
Tastverhältnis. Das erledigt ein FreeRTOS-Task mit 100 Hz auf **Core 0**, während der
Webserver im Arduino-Loop auf Core 1 läuft. Diese Trennung ist der Grund, warum der
synchrone `WebServer` aus dem Arduino-Core genügt: selbst ein hängender HTTP-Client kann das
Blinken nicht ins Stocken bringen. Dadurch spart sich das Projekt die Abhängigkeit auf
ESPAsyncWebServer und AsyncTCP samt deren Versionsfallen.

### PWM-Grundfrequenz

Fest auf **1 kHz** (`PWM_GRUNDFREQUENZ` in `config.h`), nicht zur Laufzeit änderbar. Nach oben
wäre ohnehin wenig Luft: das MOSFET-Modul schafft rund 2 kHz, weil seine Gates über einen
10-kΩ-Pulldown entladen werden und der Abschaltvorgang dadurch träge ist. Der ESP32 wäre
nicht die Grenze – sein LEDC-Block käme bei 12 Bit bis 19,5 kHz.

Nicht zu verwechseln mit dem `frequency`-Feld einer Lampe: das ist der Blink- bzw.
Pulsiertakt (0.1–20 Hz) und hat mit der PWM-Trägerfrequenz nichts zu tun.

## Offen

Das Hook-Skript `~/.claude/stacklight.ps1`, das die Säule bisher angesteuert hat, benutzt die
alte API (`/api/set?ch=0-4&val=0|1`). Diese Firmware macht einen **sauberen Schnitt** und
bildet sie nicht nach. Bis das Skript auf `/api/lamps/<farbe>/on|off` umgestellt ist, zeigt
die Säule keinen Session-Status an. Die weiße Präsenzlampe kann dann endlich gedimmt laufen
(`?brightness=15`) – das war der Grund, warum sie bisher abgeschaltet war.
