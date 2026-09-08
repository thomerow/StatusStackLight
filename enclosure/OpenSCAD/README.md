# StatusStackLight – Gehäuse (OpenSCAD)

Parametrisches, 3D-druckbares Gehäuse, das eine industrielle Signalsäule trägt und die
Elektronik aufnimmt: Lolin NodeMCU V3, 8-Kanal-MOSFET-Modul, Mini560-Buck-Converter
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
| `pd_b` × `pd_l` | 20 × 30 | USB-C-PD-Triggerboard |
| `usbc_ueberstand` | 1,0 | Überstand der Buchse über die Platinenkante |
| `buck_l` × `buck_b` × `buck_h` | 30 × 18 × 6 | Mini560 – löst den LM2596 ab, 13 mm kürzer und 8 mm flacher |
| `nodemcu_unterbau` | 4,0 | Kabel werden direkt angelötet, keine Stiftleisten – 4 mm sind reichlich Luft für die Lötstellen. Bis 5,0 kostet das keine Gehäusehöhe. |
| `saeule_kabel_d` | 12 | zentrale Kabeldurchführung im Deckel, passt für die Adern der 5 Lampen |

> **Konvention:** alle `*_h` sind **Gesamthöhen inklusive Platine**, so wie man sie mit dem
> Messschieber über das ganze Modul abgreift. `*_unterbau` ist der Abstand der
> Platinenunterseite von der Trennebene.

### Noch offen

| Variable | aktuell | Anmerkung |
|---|---|---|
| `nodemcu_h` | 14 | großzügige Annahme, real eher ~6 mm. Schadet nichts – das MOSFET-Modul ist mit 19 mm ohnehin die höchste Baugruppe. |
| `usbc_senk_t` | 1,2 | Reserve nach oben ist nur noch 0,2 mm (siehe oben) |

Nach jeder Änderung genügt ein erneuter Export – Layout, Gehäusehöhe und alle Ausschnitte
werden neu berechnet.

## Layout (Innenkoordinaten)

| Baugruppe | Maße | Fläche X / Y | Bemerkung |
|---|---|---|---|
| MOSFET 8-Kanal | 68 × 72 | 12…84 / 42…110 | Schraubklemmen zeigen zur linken/rechten Seitenwand, Clipse vorn/hinten. Nur 5 Kanäle belegt (5 Lampen), 3 bleiben frei. Höchste Baugruppe – gibt die Innenhöhe vor. |
| NodeMCU V3 | 31,5 × 58 | 90…121,5 / 58…116 | 90° gedreht, Micro-USB durch die Rückwand |
| Mini560 | 18 × 30 | 100…118 / 6…36 | 90° gedreht, rechte vordere Zone; die Clipse greifen die langen Kanten, die Lötpad-Kanten bleiben frei |
| PD-Trigger | 20 × 30 | 57…77 / 0…30 | Buchse exakt mittig in der Frontwand (x = 67) |

Die vordere linke Zone (x 12…50, y 0…40) bleibt frei für die Verdrahtung; die Lampenkabel
laufen von den MOSFET-Klemmen zur Kabeldurchführung im Deckel.

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

## Pinbelegung (NodeMCU V3 / ESP8266)

| Kanal | Pin | GPIO |
|---|---|---|
| 1 | **D1** | GPIO5 |
| 2 | **D2** | GPIO4 |
| 3 | **D5** | GPIO14 |
| 4 | **D6** | GPIO12 |
| 5 | **D7** | GPIO13 |

Das sind genau die fünf Pins des ESP8266, die beim Start unbeteiligt sind: keine
Strapping-Funktion, keine LED, kein Pull-up oder Pull-down auf dem Board, beim Boot
hochohmig, PWM- und interruptfähig.

**Nicht** die naheliegenden Reihen D0–D4 oder D1–D5 verwenden – beide enthalten die zwei
kritischen Pins:

* **D3 = GPIO0** entscheidet beim Reset über den Bootmodus und hat dafür einen Pull-up.
  Der typische 10-kΩ-Pulldown am Eingang eines MOSFET-Moduls zieht dagegen: der ESP geht
  dann in den Flash-Modus und startet die Firmware **nicht**. Der Fehler tritt gern
  sporadisch auf und ist entsprechend unangenehm zu finden.
* **D4 = GPIO2** muss beim Boot ebenfalls HIGH sein und trägt die blaue LED des
  ESP-12-Moduls – die Lampe an diesem Kanal ginge bei jedem Reset an.

**D0 = GPIO16** ist kein Boot-Problem, hängt aber am RTC-Block statt am normalen
GPIO-Peripheriemodul: kein Interrupt, je nach Framework kein PWM. Nur als Ausweichpin.

Auch die fünf empfohlenen Pins sind beim Boot Eingänge, das Gate schwebt also für die
ersten paar hundert Millisekunden. Hat das MOSFET-Modul keine Pulldowns an den
Steuereingängen, je 10 kΩ nach Masse nachrüsten – auf D1/D2/D5/D6/D7 ohne Nebenwirkung.

Wird später I²C gebraucht (SCL = D1, SDA = D2), rücken diese beiden Lampen auf **D8**
(GPIO15, unkritisch: Pulldown an Bord, beim Boot ohnehin LOW) und **D0**. D3 und D4
bleiben in jedem Fall tabu.

> Bei einem Wechsel auf ein ESP32-C3-Board (z. B. SuperMini) entsprechend GPIO 3, 4, 5, 6, 7
> – dort sind 2, 8 und 9 die Strapping-Pins.

## Montagereihenfolge

1. Inserts in Hauptkörper einpressen (M3 in die Eckdome, M4 in die Säulendome von innen).
2. Bodenplatte bestücken: MOSFET-Modul, NodeMCU, Buck und PD-Board in die Clipse drücken.
3. Verdrahten: USB-C-PD → 12 V an MOSFET-Modul und Mini560-Eingang, Ausgang 5 V → NodeMCU
   (VIN/5V), GPIOs → MOSFET-Steuereingänge (Pinbelegung siehe oben), gemeinsame Masse.
4. Lampenkabel durch die Deckeldurchführung fädeln und an die MOSFET-Klemmen legen –
   5 Lampen, also 5 belegte Kanäle plus gemeinsame Rückleitung.
5. Bodenplatte senkrecht von unten einführen (USB-C und Micro-USB gleiten in ihre Schlitze),
   mit 4 × M3-Senkkopf verschrauben.
6. Signalsäule mittig auf den Deckel setzen und mit 4 × M4 verschrauben – die Schrauben
   auf dem 55er Lochkreis übernehmen die Zentrierung.

## Nächste Ausbaustufen

Kabelzugentlastung am USB-C-Eingang, Staubschutz/Dichtung, Wandmontagelaschen,
Beschriftung, ggf. dreiteiliger Aufbau mit separatem Deckel.
