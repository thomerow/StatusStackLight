# StatusStackLight – Firmware (ESP32-S3)

Firmware für die 5-Lampen-Signalsäule. Sie stellt eine HTTP-JSON-API zur Ansteuerung der
Lampen bereit und ein Web-Interface, mit dem sich jede Lampe einzeln in allen Parametern
durchspielen lässt.

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

Wie man diese Felder setzt, steht in [API.md](API.md).

## Hardware

| Punkt | Wert |
|---|---|
| Board | ESP32-S3 DevKitC-1, **N16R8** (16 MB Flash, 8 MB Octal-PSRAM) |
| Treiber | 8-Kanal-MOSFET-Modul, low-side, **LOW-aktiv** (GPIO auf Masse = Lampe an) |
| Leuchtmittel | 12-V-LED-Module |
| Versorgung | USB-C-PD-Triggerboard (12 V) → Mini560-Buck → 3,3 V an den 3V3-Pin des ESP32 |

### Kanalbelegung

| Kanal | GPIO | Farbe | API-ID |
|---|---|---|---|
| 1 | 4 | weiß | `white` |
| 2 | 5 | blau | `blue` |
| 3 | 6 | grün | `green` |
| 4 | 7 | orange | `orange` |
| 5 | 15 | rot | `red` |

Diese Zuordnung ist am 21.09.2026 gegen die aufgebaute Säule geprüft und stimmt.

Wird umverdrahtet oder eine Lampe getauscht, lässt sie sich mit dem
[Kanal-Durchlauf](#diagnose) erneut kontrollieren. Stimmt sie nicht mehr, werden in
`include/config.h` die Zeilen der Tabelle `LAMPEN[]` getauscht – sonst nichts.

## WLAN einrichten

Zugangsdaten stehen im NVS, nicht im Quelltext. Findet das Gerät dort keine – frisch
geflasht, auf einem anderen Board oder nach `POST /api/reset` –, spannt es selbst einen
offenen Accesspoint auf:

1. Accesspoint **`StatusStackLight-XXXX`** erscheint in der WLAN-Liste (`XXXX` = die letzten
   beiden Bytes der MAC-Adresse, steht auch auf der seriellen Konsole).
2. Verbinden – die Konfigurationsseite öffnet sich als Captive Portal von selbst. Falls
   nicht: `http://192.168.4.1/setup`.
3. Netz auswählen, Passwort eingeben, speichern. Das Gerät **probiert die Daten erst aus**
   und speichert sie nur, wenn die Verbindung zustande kommt – ein Tippfehler sperrt dich
   also nicht aus. Deshalb dauert die Antwort bis zu 20 Sekunden.
4. Danach ist es unter **`http://statusstacklight.local/`** erreichbar (bzw. unter der IP,
   die die Konfigurationsseite meldet – Android löst `.local` nicht zuverlässig auf).

Reißt die Verbindung im Betrieb ab, versucht das Gerät es selbstständig weiter; bleibt es
länger als zwei Minuten erfolglos, geht der Konfig-AP wieder auf. Die Lampen laufen dabei
unverändert weiter, und die API ist über die AP-Adresse erreichbar – die Säule lässt sich
also auch ohne WLAN vollständig bedienen.

## Diagnose

Im Web-Interface unten: **Kanal-Durchlauf**. Er schaltet die Kanäle 1 bis 5 nacheinander für
je eine Sekunde einzeln ein und meldet dabei auf der seriellen Konsole, welche Farbe erwartet
wird – der schnellste Weg, nach einem Lampenwechsel oder bei Verdacht auf einen
Wackelkontakt jeden Kanal einzeln zu sehen:

```
[durchlauf] Kanal 1  GPIO  4  erwartet: weiß
[durchlauf] Kanal 2  GPIO  5  erwartet: blau
...
```

Danach wird der vorherige Zustand wiederhergestellt. Auch per API: `GET /api/sweep`.

Wenn ein Kanal auffällig ist:

- **Bleibt eine Lampe dunkel, die anderen gehen** – der Fehler sitzt hinter dem GPIO. Zum
  Eingrenzen am MOSFET-Ausgang messen, während der Durchlauf auf diesem Kanal steht.
- **Leuchtet die falsche Lampe** – die Zeilen in `LAMPEN[]` in `include/config.h` tauschen.
- **Blitzt die Säule beim Booten kurz auf** – dem MOSFET-Modul fehlen die Pullups an den
  Steuereingängen; je 10 kΩ nach 3,3 V nachrüsten. Die Firmware legt die GPIOs zwar als
  allererstes auf den Aus-Pegel, kann aber die Zeit bis dahin nicht überbrücken.
- **Schaltet alles genau verkehrt herum** – `LAMPE_LOW_AKTIV = false` in `config.h`.

## API

Die vollständige Beschreibung aller Endpunkte mit Anfragen, echten Antworten, Fehlercodes
und Beispielen in curl und PowerShell steht in **[API.md](API.md)**.

Kurz zum Einstieg:

```bash
curl http://statusstacklight.local/api/status                     # alles auf einen Blick
curl 'http://statusstacklight.local/api/lamps/red/on?brightness=50' # rot einschalten
curl -X PATCH http://statusstacklight.local/api/lamps/orange \
     -H 'Content-Type: application/json' -d '{"effect":"blink","frequency":2}'
```

Ungültige Werte werden mit `400` und einer Klartext-Meldung abgelehnt statt still
zurechtgebogen – eine stillschweigend halbierte Helligkeit sucht man bei der Fehlersuche
sonst an der falschen Stelle.

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

**Versorgung beim Flashen:** Der Mini560 speist 3,3 V direkt in den 3V3-Pin, am
Spannungsregler des Boards vorbei. Steckt zusätzlich USB, arbeiten zwei Quellen auf dieselbe
Leitung – Espressif nennt die beiden Versorgungswege ausdrücklich „mutually exclusive“. Für
einen kurzen Flashvorgang geht das in der Praxis meist gut; sauber ist, die 3,3-V-Leitung
vorher zu trennen (Masse darf bleiben). Das Board ist ein Nachbau mit CH343 statt CP2102N,
Schutzdioden an den USB-Buchsen sind also nicht gesichert.

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

### Wenn der Build abbricht

**`ModuleNotFoundError: No module named 'intelhex'`** beim Erzeugen von `bootloader.bin`:
Das mitgelieferte esptool 4.9 braucht dieses Python-Paket, PlatformIOs eigene Umgebung bringt
es aber nicht mit. Einmalig nachinstallieren:

```powershell
& "$env:USERPROFILE\.platformio\penv\Scripts\python.exe" -m pip install intelhex
```

**Merkwürdige Fehler beim Öffnen von Dateien**: zuerst den Umlaut im Projektpfad verdächtigen
(siehe `build_dir` oben), bevor man im Quelltext sucht.

## Aufbau

```
API.md                  HTTP-API: alle Endpunkte mit Beispielen
platformio.ini          Board, Umgebungen, Bibliotheken
include/config.h        Pins, Farben, Grenzwerte, Standardwerte  <- hier wird geschraubt
scripts/embed_web.py    Pre-Build: web/*.html -> include/web_assets.h (gzip)
web/index.html          Steuerseite (Quelle)
web/setup.html          WLAN-Konfigurationsseite (Quelle)
src/main.cpp            setup/loop
src/lampen.*            LEDC, Effekt-Engine, Gamma, Invertierung
src/lampenzustand.*     Zustand einer Lampe, Prüfung, JSON
src/lampenspeicher.*    letzter Lampenzustand im NVS, übersteht Neustarts
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

### Zustand über Neustarts hinweg

Die Firmware merkt sich den Zustand aller fünf Lampen im NVS (Bereich `ssl-lampen`, getrennt
von den WLAN-Daten – `/api/reset` lässt ihn stehen) und stellt ihn beim Start wieder her,
noch bevor der Effekt-Task anläuft. Ohne das stünde die Säule nach Stromausfall, Neustart
oder Flashen dunkel, bis der nächste Hook zufällig den Sollzustand schickt – und wartet
Claude gerade auf Eingabe, feuert keiner.

Geschrieben wird nur bei einer echten Änderung und erst nach 2 s Ruhe
(`SPEICHER_VERZOEGERUNG_MS`). Das Hook-Skript schickt bei jedem Ereignis den kompletten
Zustand, meist unverändert – das löst keinen Schreibvorgang aus. Ein gezogener Regler im
Web-Interface ergibt einen statt zwanzig, und der Warnblitz ist vorbei, bevor er im Flash
landet.

Der wiederhergestellte Zustand kann veraltet sein – etwa blau pulsierend von einer Session,
die während des Stromausfalls zu Ende ging. Der nächste Hook korrigiert das.

### PWM-Grundfrequenz

Fest auf **1 kHz** (`PWM_GRUNDFREQUENZ` in `config.h`), nicht zur Laufzeit änderbar. Nach oben
wäre ohnehin wenig Luft: das MOSFET-Modul schafft rund 2 kHz, weil seine Gates über einen
10-kΩ-Pulldown entladen werden und der Abschaltvorgang dadurch träge ist. Der ESP32 wäre
nicht die Grenze – sein LEDC-Block käme bei 12 Bit bis 19,5 kHz.

Nicht zu verwechseln mit dem `frequency`-Feld einer Lampe: das ist der Blink- bzw.
Pulsiertakt (0.1–20 Hz) und hat mit der PWM-Trägerfrequenz nichts zu tun.

## Anzeige der Claude-Code-Sessions

Angesteuert wird die Säule von `~/.claude/stacklight.ps1`, das über Hooks in
`~/.claude/settings.json` hängt (liegt außerhalb dieses Repos). Jede Session legt ihren
Zustand als Datei unter `~/.claude/stacklight/` ab; daraus wird berechnet, was die Lampen
zeigen, und in **einem** `POST /api/lamps` gesetzt – bei jedem Ereignis vollständig, auch
wenn sich nichts geändert hat. So heilt der nächste Hook jede Abweichung, ob durch Neustart,
Web-Interface oder curl.

| Lampe | Zustand | Darstellung |
|---|---|---|
| weiß | bereit – Session offen, nichts los | atmet sehr langsam, 0,1 Hz, bis 25 % |
| grün | fertig – gerade fertig geworden | dauerhaft, 45 %, fünf Minuten lang |
| blau | arbeitet | pulsierend, 0,3 Hz, 70 % |
| orange | Rückfrage an dich | dauerhaft, 40 % |
| orange | wartet auf eine Freigabe | blinkend, 1,2 Hz, 50 % |
| rot | Fehler | dauerhaft, 100 %, rastet bis zum nächsten Prompt |
| rot | gefährlicher Befehl (`rm -rf`, `git push --force`, …) | kurzer Blitz, 6 Hz, über dem übrigen Zustand |

Genau eine von bereit/fertig/arbeitet/Rückfrage/Freigabe brennt (Rangfolge von rechts nach
links), rot liegt unabhängig darüber.

**Orange nur, wenn Claude dich braucht.** Der Notification-Hook hat Matcher auf den
Benachrichtigungstyp: `permission_prompt` ist eine Freigabe (blinkt),
`elicitation_dialog`, `elicitation_url_dialog` und `agent_needs_input` sind Rückfragen
(ruhig). Die Leerlauf-Meldung nach einer Minute ohne Eingabe (`idle_prompt`) ist bewusst
nicht dabei – sie würde jedes Grün nach 60 s zu Orange machen. Zusätzlich lösen die
Werkzeuge `ExitPlanMode` (Freigabe) und `AskUserQuestion` (Rückfrage) über `PreToolUse`
direkt aus. Getrennt wird über eigene Hook-Einträge mit den Events `Freigabe` und
`Rueckfrage`, nicht über Felder der Hook-Eingabe: deren Aufbau ist für Notification nicht
dokumentiert.

**Orange geht wieder aus**, sobald das freigegebene Werkzeug gelaufen bzw. die Frage
beantwortet ist: `PostToolUse` ruft das Skript mit `ToolDone` auf, und es springt zurück
auf blau. Ohne das bliebe Orange bis zum Ende der Antwort stehen, denn eine Freigabe ist
kein neuer Prompt. Grenze: Einen Zeitpunkt „Freigabe erteilt" meldet Claude Code nicht –
bei einem langen Build blinkt es also, bis der freigegebene Befehl fertig ist.
`PostToolUse` feuert nach jedem Werkzeugaufruf; wartet die Session nicht, beendet sich das
Skript sofort ohne Anfrage an die Säule.

**Grün fällt nach fünf Minuten auf weiß** – „frisch fertig" ist eine andere Information
als „steht schon eine Weile da". Weil danach womöglich lange kein Hook mehr feuert, startet
`Stop` einen versteckten Nachzügler, der die Zeit absitzt und einmal neu rechnet. Es läuft
immer nur einer; ein neuer `Stop` beendet den vorigen.

**Helligkeiten:** Weiß ist mit Abstand die hellste Lampe und braucht viel weniger Prozent,
um gleich hell zu wirken – ungedimmt ist es als Dauerlicht nicht zu ertragen. Beim Atmen ist
die Prozentzahl der Gipfel: der Atemzug läuft von 0 bis dorthin, und durch die
Gammakorrektur ist das untere Drittel praktisch dunkel. Deshalb liegt der Gipfel mit 25 %
deutlich über dem, was Weiß als Dauerlicht bräuchte. Orange ist mit
voller Helligkeit aus der Nähe grell und läuft deshalb gedimmt; die Aufmerksamkeit kommt vom
Blinken, nicht von der Helligkeit. Alle Werte stehen in der Tabelle `$Anzeige` oben im
Skript.

**Warnblitz nur bei echten Treffern.** Die `if`-Bedingungen im `PreToolUse`-Hook
(`Bash(rm -rf *)` usw.) sind nur ein grober Vorfilter: Befehle, die Claude Code nicht sauber
zerlegen kann – Schleifen, `$(…)`, Heredocs –, lässt es sicherheitshalber durch; schon
`for i in 1; do echo "$(echo harmlos)"; done` passiert den Vorfilter. Das Skript prüft
deshalb den tatsächlichen Befehlstext noch einmal selbst.

Zum Ausprobieren ohne Hooks:

```powershell
$s = "$HOME\.claude\stacklight.ps1"
& $s -Event Status      # zeigt, was die Säule zeigen sollte, ohne etwas zu schalten
& $s -Event SelfTest    # Kanal-Durchlauf der Firmware, danach zurück in den Istzustand
& $s -Event AllOff
```
