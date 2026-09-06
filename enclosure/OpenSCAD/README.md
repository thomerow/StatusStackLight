# StatusStackLight – Gehäuse (OpenSCAD)

Parametrisches, 3D-druckbares Gehäuse, das eine industrielle Signalsäule trägt und die
Elektronik aufnimmt: Lolin NodeMCU V3, 8-Kanal-MOSFET-Modul, LM2596-Buck-Converter
(12 V → 5 V) und ein USB-C-PD-Triggerboard, das 12 V vom Netzteil anfordert.

**Stufe 1: zweiteilig** – Hauptkörper mit integriertem Deckel + abnehmbare Bodenplatte.

| Datei | Inhalt |
|---|---|
| `statusstacklight_gehaeuse.scad` | komplettes Modell, alle Maße als Variablen am Dateianfang |
| `body.stl` / `boden.stl` | exportierte Druckteile (aus den aktuellen Parametern) |
| `preview/` | Rendering-Vorschauen |

Aktuelle Außenmaße: **138,8 × 120,8 × 35,8 mm** (Innenraum 134 × 116 × 31 mm).

## Konstruktionsprinzip

* **Koordinaten:** `x = 0…innen_x` (links→rechts), `y = 0…innen_y` (vorn→hinten),
  `z = 0` ist die Trennebene = Oberseite der Bodenplatte. Alle Layout-Positionen sind in
  diesen Innenkoordinaten angegeben.
* **Die Bodenplatte trägt die gesamte Elektronik.** Sie wird außerhalb des Gehäuses
  bestückt und anschließend von unten senkrecht eingeschoben.
* **Keine Schrauben für die Platinen.** Jede Platine sitzt auf vier Auflagepads; an einer
  Kante liegen zwei starre Auflageleisten, an der gegenüberliegenden zwei federnde
  Schnappclipse mit 45°-Einführfase. Platine schräg unter die starre Seite schieben,
  gegenüber herunterdrücken – rastet ein.
* **Verschluss:** 4 Eckdome mit Heat-Set-Inserts M3 (Ø 4,0 × 6 mm), Senkkopfschrauben M3
  von unten.

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

```powershell
# Vorschau: OpenSCAD öffnen und statusstacklight_gehaeuse.scad laden
# (teil = "beides" zeigt beide Teile montiert, "explosion" auseinandergezogen)

$OS = "C:\Program Files\OpenSCAD\openscad.exe"
& $OS -o body.stl  -D "teil=""body"""  statusstacklight_gehaeuse.scad
& $OS -o boden.stl -D "teil=""boden""" statusstacklight_gehaeuse.scad
```

Beim Kompilieren gibt die Datei die abgeleiteten Maße per `echo()` aus, unter anderem eine
Kollisionsprüfung zwischen den Säulen-Insertdomen und der höchsten Baugruppe.

`zeige_platinen = true` blendet die Platinen als transparente Geister ein (`%`) – sie sind
im Rendering/STL **nicht** enthalten.

## Maße

### Gemessen und bestätigt

| Variable | Wert | |
|---|---|---|
| `mosfet_h` | 16 | Bauhöhe des MOSFET-Moduls inkl. Schraubklemmen |
| `saeule_fuss_d` | 70 | Außendurchmesser des Säulenfußes (bestimmt den Zentrierring) |
| `saeule_lochkreis_d` | 55 | |
| `saeule_schrauben_n` | 4 | |
| `pd_b` × `pd_l` | 20 × 30 | USB-C-PD-Triggerboard |
| `usbc_ueberstand` | 1,0 | Überstand der Buchse über die Platinenkante |

### Noch offen

| Variable | aktuell | Anmerkung |
|---|---|---|
| `saeule_kabel_d` | 12 | Durchmesser der zentralen Kabeldurchführung |
| `nodemcu_unterbau` | 4,0 | erhöhen, falls die Stiftleisten weiter durchstehen |
| `usbc_senk_t` | 1,2 | Reserve nach oben ist nur noch 0,2 mm (siehe oben) |

Nach jeder Änderung genügt ein erneuter Export – Layout, Gehäusehöhe und alle Ausschnitte
werden neu berechnet.

## Layout (Innenkoordinaten)

| Baugruppe | Maße | Fläche X / Y | Bemerkung |
|---|---|---|---|
| MOSFET 8-Kanal | 68 × 72 | 12…84 / 42…110 | Schraubklemmen zeigen zur linken/rechten Seitenwand, Clipse vorn/hinten |
| NodeMCU V3 | 31,5 × 58 | 90…121,5 / 58…116 | 90° gedreht, Micro-USB durch die Rückwand |
| LM2596 | 21 × 43 | 100…121 / 6…49 | 90° gedreht, rechte vordere Zone |
| PD-Trigger | 20 × 30 | 57…77 / 0…30 | Buchse exakt mittig in der Frontwand (x = 67) |

Die vordere linke Zone (x 12…50, y 0…40) bleibt frei für die Verdrahtung; die Lampenkabel
laufen von den MOSFET-Klemmen zur Kabeldurchführung im Deckel.

## Druckempfehlung

| Teil | Orientierung | Hinweis |
|---|---|---|
| `body.stl` | **auf dem Deckel stehend**, Öffnung nach oben | stützfrei; die nach unten offenen Steckerschlitze zeigen dabei nach oben |
| `boden.stl` | flach, Clipse nach oben | stützfrei |

* Schichthöhe 0,2 mm, 3 Perimeter (Bodenplatte gern 4, damit die Clipse nicht abscheren),
  Infill ≥ 25 %.
* Material: PETG oder PLA+. PLA-Clipse sind spröder – bei häufigem Öffnen PETG bevorzugen.
* Heat-Set-Inserts: 4 × M3 (Ø 4,0 × 6 mm) in den Eckdomen, 4 × M4 (Ø 5,6 × 8 mm) in den
  Säulendomen. Alternativ `saeule_insert = false` für reine Durchgangslöcher.

## Montagereihenfolge

1. Inserts in Hauptkörper einpressen (M3 in die Eckdome, M4 in die Säulendome von innen).
2. Bodenplatte bestücken: MOSFET-Modul, NodeMCU, Buck und PD-Board in die Clipse drücken.
3. Verdrahten: USB-C-PD → 12 V an MOSFET-Modul und Buck-Eingang, Buck-Ausgang 5 V → NodeMCU
   (VIN/5V), GPIOs → MOSFET-Steuereingänge, gemeinsame Masse.
4. Lampenkabel durch die Deckeldurchführung fädeln und an die MOSFET-Klemmen legen.
5. Bodenplatte senkrecht von unten einführen (USB-C und Micro-USB gleiten in ihre Schlitze),
   mit 4 × M3-Senkkopf verschrauben.
6. Signalsäule auf den Zentrierring setzen und mit 4 × M4 durch den Deckel verschrauben.

## Nächste Ausbaustufen

Kabelzugentlastung am USB-C-Eingang, Staubschutz/Dichtung, Wandmontagelaschen,
Beschriftung, ggf. dreiteiliger Aufbau mit separatem Deckel.
