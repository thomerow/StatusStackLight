# StatusStackLight – Gehäuse (OpenSCAD)

Parametrisches, 3D-druckbares Gehäuse, das eine industrielle Signalsäule trägt und die
Elektronik aufnimmt: ESP32-S3 DevKitC-1 (N16R8), 8-Kanal-MOSFET-Modul, Mini560-Buck-Converter
(12 V → 5 V) und ein USB-C-PD-Triggerboard, das 12 V vom Netzteil anfordert.

**Die Säule hat 5 Lampen.** Genutzt werden also nur 5 der 8 MOSFET-Kanäle; die restlichen
drei bleiben absichtlich frei. Das 8-Kanal-Modul steckt trotzdem drin, weil es vorhanden
war – es ist mit 68 × 72 × 16 mm das größte Bauteil und bestimmt damit sowohl die
Innenmaße als auch die Innenhöhe des Gehäuses. Wer die Kiste kleiner haben will, setzt
dort an, nicht beim Mikrocontroller.

**Stufe 1: zweiteilig** – Hauptkörper mit integriertem Deckel + abnehmbare Bodenplatte.

| Datei | Inhalt |
|---|---|
| `statusstacklight_gehaeuse.scad` | komplettes Modell, alle Maße als Variablen am Dateianfang |
| `render.ps1` | erzeugt STLs und Vorschaubilder über die Kommandozeile |
| `body.stl` / `boden.stl` | exportierte Druckteile (aus den aktuellen Parametern) |
| `preview/` | Rendering-Vorschauen |

Aktuelle Außenmaße: **138,8 × 120,8 × 35,8 mm** (Innenraum 134 × 116 × 31 mm).

## Konstruktionsprinzip

* **Koordinaten:** `x = 0…innen_x` (links→rechts), `y = 0…innen_y` (vorn→hinten),
  `z = 0` ist die Trennebene = Oberseite der Bodenplatte. Alle Layout-Positionen sind in
  diesen Innenkoordinaten angegeben.
* **Die Bodenplatte trägt die gesamte Elektronik.** Sie wird außerhalb des Gehäuses
  bestückt und anschließend von unten senkrecht eingeschoben.
* **Plane Oberseite.** Der Deckel ist außen völlig glatt – nur die vier M4-Löcher und die
  Kabeldurchführung. Ein erhabener Zentrierring um den Säulenfuß ist zwar als
  `saeule_zentrierring` weiterhin im Modell, aber **abgeschaltet**: der Hauptkörper wird auf
  dem Deckel stehend gedruckt, der Ring wäre dann das Einzige, was auf dem Druckbett
  aufliegt, und die gesamte restliche Deckelfläche hinge 1,2 mm in der Luft. Zentriert wird
  der Flansch ohnehin durch die vier M4-Schrauben auf dem 55er Lochkreis.
* **Keine Schrauben für die Platinen.** Jede Platine sitzt auf vier Auflagepads; an einer
  Kante liegen zwei starre Auflageleisten, an der gegenüberliegenden zwei federnde
  Schnappclipse mit 45°-Einführfase. Platine schräg unter die starre Seite schieben,
  gegenüber herunterdrücken – rastet ein.
* **Verschluss:** 4 Eckdome mit Heat-Set-Inserts M3 (Ø 4,0 × 6 mm), Senkkopfschrauben M3
  von unten. Die Senkungen sind **kegelig** ausgeführt (90° nach DIN 7991), der Kopf liegt
  also flächig auf der Kegelflanke auf statt auf einer Kante. Die Tiefe wird aus
  `senkung_winkel` und `senkung_d` berechnet und nicht separat vorgegeben – sonst passt der
  Kegel nicht mehr zum Schraubenkopf. Ein kurzer zylindrischer Anlauf (`senkung_anlauf`,
  0,3 mm) an der Außenfläche fängt den Elefantenfuß der ersten Druckschicht ab; der Kopf
  sitzt damit rund 0,4 mm unter der Oberfläche. Bei 2,4 mm Bodenstärke bleiben 0,7 mm
  Material unter der Senkung stehen – das Modell rechnet es aus und warnt, wenn es zu
  dünn wird.

### USB-C-PD-Triggerboard – Zugentlastung

Die Buchse sitzt mittig an einer 20-mm-Kante und tritt mittig durch die Frontwand:

* Der Wanddurchbruch (13,5 × 7,5 mm) ist **nach unten bis zur Trennebene offen**, damit die
  bestückte Bodenplatte kollisionsfrei einfährt – und er druckt dadurch ohne Brücke.
* Ein **Steckerkragen** auf der Bodenplatte füllt den Schlitz unterhalb der Öffnung wieder
  auf und bildet die Unterkante der sichtbaren Öffnung.
* Die Buchse **steht 1 mm über die Platinenkante** vor und taucht damit selbst in den
  Wanddurchbruch ein.
* Eine **Außenansenkung** (17 mm breit, 1,2 mm tief) dünnt die Wand vor der Buchse aus.
  Zusammen mit dem Überstand bleiben nur noch **0,2 mm Restwand** vor der Steckermündung –
  der Stecker rastet praktisch bündig ein und die volle Steckerlänge greift. Das Modell
  prüft das beim Kompilieren (`usbc_luft`); die Ansenkung darf `wand − usbc_ueberstand`
  nicht überschreiten.
* **Kraftfluss:** Der **Sattel** unter der Platinenvorderkante nimmt Kräfte nach unten auf,
  die Clipse halten nach oben, die **Anschlagrippe** hinter der Platine nimmt die
  Einsteckkraft, und die Frontwand selbst (links und rechts der Öffnung liegt die
  Platinenkante an) hält beim Herausziehen dagegen. Die Lötstellen der Buchse werden
  in keiner Richtung belastet.
* **Die Anschlagrippe ist zweigeteilt** (`usbc_rippe_luecke`, 10 mm): die Lötaugen des
  PD-Boards sitzen hinten mittig, die Kabel brauchen dort einen Ausgang nach hinten.
  Übrig bleiben zwei Segmente von je 7 mm an den hinteren Platinenecken. Für den
  Kraftfluss ist das kein Verlust, eher das Gegenteil – die Einsteckkraft geht jetzt in
  die Ecken statt in die Mitte, die Platine wird also nicht mehr auf Biegung belastet.
  `usbc_rippe_luecke = 0` stellt die durchgehende Rippe wieder her.

Rundum bleibt Spiel: die Buchse wird geführt, nicht geklemmt.

## Nutzung

Alles, was das Repo enthält, entsteht mit einem Aufruf – **ohne die OpenSCAD-GUI**:

```powershell
.\render.ps1                 # body.stl, boden.stl und alle preview/*.png
.\render.ps1 -Only Stl       # nur die Druckteile
.\render.ps1 -Only Preview   # nur die Bilder (< 1 s pro Bild)
```

Das Skript sucht `openscad.exe` selbst (sonst `-OpenScad <pfad>`) und gibt am Ende die
abgeleiteten Maße und die Kollisionsprüfungen des Modells aus:

```
Innenmasse  : 134 x 116 x 31 mm
Aussenmasse : 138.8 x 120.8 x 35.8 mm (Deckel plan)
USB-C-Buchse: Stirn y=-1  Ansenkungsboden y=-1.2  Restwand=0.2 mm  -> OK
Senkung     : 90 Grad, Tiefe 1.7 mm  Restboden=0.7 mm  -> OK
Saeulendome : Unterkante z=21  hoechste Baugruppe z=19  -> OK
```

Zum Konstruieren die Datei wie gewohnt in der OpenSCAD-GUI öffnen; `teil` schaltet
zwischen `"beides"`, `"body"`, `"boden"` und `"explosion"` um.

> Stolperfalle für eigene Skripte: `openscad.exe` ist ein GUI-Subsystem-Binary und kehrt
> **sofort** zurück, wenn PowerShell seine Ausgabe nicht über eine echte Pipeline
> konsumiert – eine Zuweisung wie `$log = & $OS @args 2>&1` wartet **nicht** auf das Ende
> des Renderns. `render.ps1` liest deshalb über `| ForEach-Object { "$_" }` und prüft
> zusätzlich den Zeitstempel der geschriebenen Datei.

`zeige_platinen = true` blendet die Platinen als transparente Geister ein (`%`) – sie sind
im Rendering/STL **nicht** enthalten.

## Maße

### Gemessen und bestätigt

| Variable | Wert | |
|---|---|---|
| `mosfet_h` | 16 | Bauhöhe des MOSFET-Moduls inkl. Schraubklemmen |
| `saeule_fuss_d` | 70 | Außendurchmesser des Säulenfußes; bestimmt die Deckelverstärkung (Fuß + 10 mm) auf der Innenseite |
| `saeule_lochkreis_d` | 55 | |
| `saeule_schrauben_n` | 4 | |
| `pd_b` × `pd_l` | 20 × 31,5 | USB-C-PD-Triggerboard |
| `usbc_ueberstand` | 1,0 | Überstand der Buchse über die Platinenkante |
| `buck_l` × `buck_b` × `buck_h` | 30 × 18 × 6 | Mini560 – löst den LM2596 ab, 13 mm kürzer und 8 mm flacher |
| `mcu_l` × `mcu_b` × `mcu_h` | 57,3 × 28,1 × 5,0 | ESP32-S3 DevKitC-1 N16R8; Höhe = 1,6 Platine + 3,4 Aufbau |
| `mcu_antenne` | 6,3 | Überstand des Modul-Antennenendes über die Platinenkante |
| `mcu_anschlag_ueber` | −0,2 | Oberkante des Endanschlags relativ zur Platinenoberseite. Negativ, damit eine Zehntel Drucküberhöhung die Platinenvorderkante nicht anhebt; der Anschlag greift weiterhin über 1,4 der 1,6 mm Kante. |
| `mcu_unterbau` | 3,0 | Kabel werden von oben in die Lötaugen geführt, die Lötpunkte tragen also nach unten auf |
| `mcu_usb_rand` / `mcu_com_rand` | 8,0 / 19,5 | Buchsenmitten von der im Gehäuse **rechten** Platinenkante |
| `saeule_kabel_d` | 12 | zentrale Kabeldurchführung im Deckel, passt für die Adern der 5 Lampen |

> **Konvention:** alle `*_h` sind **Gesamthöhen inklusive Platine**, so wie man sie mit dem
> Messschieber über das ganze Modul abgreift. `*_unterbau` ist der Abstand der
> Platinenunterseite von der Trennebene.

### Noch offen

| Variable | aktuell | Anmerkung |
|---|---|---|
| `usbc_senk_t` | 1,2 | Reserve nach oben ist nur noch 0,2 mm (siehe oben) |

Nach jeder Änderung genügt ein erneuter Export – Layout, Gehäusehöhe und alle Ausschnitte
werden neu berechnet.

## Layout (Innenkoordinaten)

| Baugruppe | Maße | Fläche X / Y | Bemerkung |
|---|---|---|---|
| MOSFET 8-Kanal | 68 × 72 | 12…84 / 42…110 | Schraubklemmen zeigen zur linken/rechten Seitenwand, Clipse vorn/hinten. Nur 5 Kanäle belegt (5 Lampen), 3 bleiben frei. Höchste Baugruppe – gibt die Innenhöhe vor. |
| ESP32-S3 | 28,1 × 57,3 | 90…118,1 / 58,7…116 | 90° gedreht, beide USB-C durch die Rückwand. Das Antennenende des Moduls ragt bis y = 52,4 über die Platinenkante hinaus |
| Mini560 | 18 × 30 | 100…118 / 6…36 | 90° gedreht, rechte vordere Zone; die Clipse greifen die langen Kanten, die Lötpad-Kanten bleiben frei. Vordere **linke** Auflageleiste versetzt, siehe unten |
| PD-Trigger | 20 × 31,5 | 57…77 / 0…31,5 | Buchse exakt mittig in der Frontwand (x = 67) |

Die vordere linke Zone (x 12…50, y 0…40) bleibt frei für die Verdrahtung; die Lampenkabel
laufen von den MOSFET-Klemmen zur Kabeldurchführung im Deckel.

### Sonderfall: vordere linke Auflageleiste des Mini560

Auf der linken Platinenkante des Mini560 (Draufsicht auf die Bodenplatte, der
USB-C-Eingang unten) sitzt ein Bauteil bündig mit der Kante – die Auflageleiste greift
dort nicht. Sie rückt deshalb **3 mm nach vorn** (`buck_klemm_vl_versatz`) und ist
zugleich **4 statt 6 mm breit** (`buck_klemm_vl_breite`), weil sie sonst der Lötstelle des
Plus-Eingangs im Weg wäre. Zur Platinenvorderkante bleiben damit 3,4 mm.

| Klemme | y | Breite |
|---|---|---|
| links hinten | 27,6 | 6,0 |
| rechts hinten | 27,6 | 6,0 |
| rechts vorn | 14,4 | 6,0 |
| **links vorn** | **11,4** | **4,0** |

Möglich wird das durch die optionalen Parameter `klemmen_fest` / `klemmen_feder` von
`platine_halter()`: eine Liste `[[position, breite], …]` je Kante. Ohne Angabe bleibt es
beim symmetrischen Standard (zwei Klemmen bei 28 % und 72 % der Kantenlänge, je `klemm_b`
breit), sodass sich einzelne Klemmen um Bauteile herumlegen lassen, ohne die Symmetrie
für alle anderen Platinen aufzugeben.

## Druckempfehlung

| Teil | Orientierung | Hinweis |
|---|---|---|
| `body.stl` | **auf dem Deckel stehend**, Öffnung nach oben | stützfrei: die plane Deckelfläche liegt vollflächig auf dem Bett, die nach unten offenen Steckerschlitze zeigen dabei nach oben, und die Fase der Kabeldurchführung ist als 45°-Überhang selbsttragend |
| `boden.stl` | flach, Clipse nach oben | stützfrei; die Senkungen liegen auf dem Druckbett und sind mit 45° selbsttragend |

* Schichthöhe 0,2 mm, 3 Perimeter (Bodenplatte gern 4, damit die Clipse nicht abscheren),
  Infill ≥ 25 %.
* Material: PETG oder PLA+. PLA-Clipse sind spröder – bei häufigem Öffnen PETG bevorzugen.
* Heat-Set-Inserts: 4 × M3 (Ø 4,0 × 6 mm) in den Eckdomen, 4 × M4 (Ø 5,6 × 8 mm) in den
  Säulendomen. Alternativ `saeule_insert = false` für reine Durchgangslöcher.

## Pinbelegung (ESP32-S3 DevKitC-1, N16R8)

| Kanal | GPIO |
|---|---|
| 1 | **4** |
| 2 | **5** |
| 3 | **6** |
| 4 | **7** |
| 5 | **15** |

Beim S3 ist PWM kein Thema mehr: der LEDC-Block hat 16 unabhängige Kanäle mit bis zu
14 Bit, und **jeder** GPIO kann darauf geroutet werden. Fünf gedimmte Lampen sind damit
ein Dreizeiler – genau der Grund für den Wechsel.

### Finger weg von

| Pin | Warum |
|---|---|
| **35, 36, 37** | **Octal-PSRAM.** Das `R8` in N16R8 steht für 8 MB PSRAM, und die läuft über genau diese drei Pins. Bei den Quad-Varianten wären sie frei – bei dieser nicht. |
| 26–32 | SPI-Flash des Moduls |
| 0, 3, 45, 46 | Strapping-Pins (Bootmodus, JTAG-Quelle, VDD_SPI) |
| 19, 20 | native USB-Datenleitungen (die „USB"-Buchse) |
| 43, 44 | UART0, die „COM"-Buchse |
| 38 (bzw. 48) | Onboard-RGB-LED. DevKitC-1 v1.1 nutzt GPIO38, v1.0 GPIO48; bei Klonen variiert das – im Zweifel beide probieren. |

Die fünf empfohlenen Pins sind beim Boot hochohmig. Hat das MOSFET-Modul keine Pulldowns
an den Steuereingängen, je 10 kΩ nach Masse nachrüsten, sonst kann es beim Einschalten
kurz flackern.

## Beschriftung der USB-Buchsen

Auf der Deckeloberseite sitzt vertiefter Text (`mcu_text_tiefe` = 0,6 mm) über den beiden
Buchsen. Um 180° gedreht, liest sich also **von hinten** – dort, wo man steckt.

Die Buchsenmitten liegen nur 11,5 mm auseinander; bei lesbarer Schriftgröße stoßen „USB"
und „COM" aneinander. Die Beschriftung wird deshalb über `mcu_text_spreizung` (1,6) gegen
die Mitte auseinandergezogen. Bei nur zwei Buchsen bleibt die Zuordnung links/rechts
eindeutig. `1.0` setzt sie exakt über die Buchsenmitten – dann muss `mcu_text_groesse`
unter etwa 3,5 mm.

Das Modell schätzt die Textbreite ab (0,95 × Größe je Zeichen, am Rendering nachgemessen)
und warnt beim Kompilieren, wenn es zu eng wird. Messen kann OpenSCAD Text nicht.

Gedruckt wird der Hauptkörper auf dem Deckel stehend – die Schrift liegt also am
Druckbett und kommt sauber heraus, ohne Stützen.


## Montagereihenfolge

1. Inserts in Hauptkörper einpressen (M3 in die Eckdome, M4 in die Säulendome von innen).
2. Bodenplatte bestücken: MOSFET-Modul, ESP32-S3, Buck und PD-Board in die Clipse drücken.
3. Verdrahten: USB-C-PD → 12 V an MOSFET-Modul und Mini560-Eingang, Ausgang 5 V → ESP32-S3
   (5V-Pin), GPIOs → MOSFET-Steuereingänge (Pinbelegung siehe oben), gemeinsame Masse.
4. Lampenkabel durch die Deckeldurchführung fädeln und an die MOSFET-Klemmen legen –
   5 Lampen, also 5 belegte Kanäle plus gemeinsame Rückleitung.
5. Bodenplatte senkrecht von unten einführen (alle drei USB-C-Buchsen gleiten in ihre Schlitze),
   mit 4 × M3-Senkkopf verschrauben.
6. Signalsäule mittig auf den Deckel setzen und mit 4 × M4 verschrauben – die Schrauben
   auf dem 55er Lochkreis übernehmen die Zentrierung.

## Nächste Ausbaustufen

Kabelzugentlastung am USB-C-Eingang, Staubschutz/Dichtung, Wandmontagelaschen,
Beschriftung, ggf. dreiteiliger Aufbau mit separatem Deckel.
