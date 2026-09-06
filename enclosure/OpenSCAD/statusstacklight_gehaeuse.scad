// ============================================================================
//  StatusStackLight - Gehaeuse fuer industrielle Signalsaeule
//  Stufe 1: zweiteilig (Hauptkoerper mit integriertem Deckel + abnehmbarer Boden)
//
//  Inhalt:  Lolin NodeMCU V3, 8-Kanal-MOSFET-Modul, LM2596 Buck 12V->5V,
//           USB-C-PD-Triggerboard (fordert 12 V an)
//
//  Koordinatensystem (alle Layoutmasse in "Innenkoordinaten"):
//    x = 0 .. innen_x    linke   -> rechte Innenwand
//    y = 0 .. innen_y    vordere -> hintere Innenwand
//    z = 0               Trennebene = Oberseite der Bodenplatte (Innenboden)
//    z = innen_z         Deckelunterseite
//
//  Druckorientierung (stuetzfrei):
//    Hauptkoerper: auf dem Deckel stehend, Oeffnung nach oben
//    Boden:        flach, Innenseite (Clipse) nach oben
// ============================================================================

/* [Render] */
// "beides" | "body" | "boden" | "explosion"
teil            = "beides";
zeige_platinen  = true;      // Platinen als Geister (%) - nicht im STL enthalten

$fa = 4;
$fs = 0.35;
eps = 0.01;

// ============================================================================
//  1) PARAMETER
// ============================================================================

/* [Gehaeuse-Grundmasse] */
innen_x         = 134;    // Innenbreite  (X)
innen_y         = 116;    // Innentiefe   (Y)
wand            = 2.4;    // Wandstaerke
boden_dicke     = 2.4;    // Dicke der Bodenplatte
deckel_dicke    = 2.4;    // Dicke des Deckels
ecken_r         = 3.0;    // Aussenradius der senkrechten Kanten
kabel_freiraum  = 12;     // freie Hoehe ueber der hoechsten Baugruppe
hoehe_override  = 0;      // > 0 : Innenhoehe fest vorgeben statt berechnen

/* [Passungen] */
spiel           = 0.2;    // allgemeine Fuegepassung (Lippe, Steckerkragen)
pcb_spiel       = 0.3;    // Spiel der Platinen in XY
pcb_spiel_z     = 0.2;    // Spiel unter dem Klemmhaken
pcb_dicke       = 1.6;    // Standard-Platinendicke

/* [Verschluss Boden <-> Hauptkoerper] */
dom_d           = 8.0;    // Aussendurchmesser der Eckdome
dom_abstand     = 3.0;    // Achsabstand von der Innenecke (X und Y)
insert_d        = 4.0;    // Bohrung fuer Heat-Set-Insert M3
insert_l        = 6.0;    // Einpresstiefe des Inserts
insert_pilot_d  = 2.8;    // Freibohrung unterhalb des Inserts
schraube_d      = 3.4;    // Durchgangsloch M3 in der Bodenplatte
senkung_d       = 6.2;    // Senkung fuer M3-Senkkopf (DIN 7991)
senkung_t       = 1.7;

/* [Zentrierlippe des Bodens] */
lippe           = true;
lippe_h         = 4.0;
lippe_dicke     = 1.2;

/* [Signalsaeule - gemessen: Lochkreis 55 mm, 4 x M4, Fuss 70 mm] */
saeule_fuss_d        = 70;    // Aussendurchmesser des Saeulenfusses
saeule_lochkreis_d   = 55;    // GEMESSEN
saeule_schrauben_n   = 4;     // GEMESSEN
saeule_winkel_offset = 45;    // Winkellage der ersten Schraube [Grad]
saeule_schraube_d    = 4.4;   // Durchgangsloch M4 im Deckel
saeule_kabel_d       = 12;    // zentrale Kabeldurchfuehrung
saeule_kabel_fase    = 1.2;   // Fase als Kantenschutz
saeule_insert        = true;  // true: M4-Heat-Set-Dome, false: nur Durchgangsloch
saeule_insert_d      = 5.6;
saeule_insert_l      = 8.0;
saeule_dom_d         = 9.0;
saeule_dom_l         = 10.0;  // Laenge der Dome unterhalb des Deckels
saeule_verstaerkung  = 2.0;   // zusaetzliche Deckeldicke im Flanschbereich
saeule_zentrierring  = true;  // erhabener Ring, der den Saeulenfuss zentriert
saeule_ring_h        = 1.2;
saeule_ring_breite   = 2.0;

/* [Klemmhalterung der Platinen] */
klemm_b             = 6.0;    // Breite einer Klemme
klemm_haken_h       = 1.6;    // Hoehe des Rasthakens (zugleich Einfuehrfase)
klemm_dicke_fest    = 2.5;    // starre Auflageleiste
klemm_haken_fest    = 1.0;    // Ueberstand der starren Leiste
klemm_dicke_feder   = 1.6;    // federnder Clip
klemm_haken_feder   = 0.8;    // Ueberstand des Rasthakens
anschlag_dicke      = 2.5;    // Endanschlag gegen Verschieben
anschlag_ueber      = 1.0;    // Hoehe des Anschlags ueber der Platinenoberseite
pad_d               = 6.0;    // Kantenlaenge der Auflagepads
pad_inset           = 5.0;    // Abstand Padmitte von der Platinenecke

/* [Platine: 8-Kanal-MOSFET-Modul - gemessen 68 x 72 mm] */
mosfet_l        = 72;     // laengere Kante (X)
mosfet_b        = 68;     // kuerzere Kante (Y) - hier sitzen die Schraubklemmen
mosfet_h        = 15;     // ANNAHME: Bauhoehe inkl. Klemmen - bitte nachmessen
mosfet_unterbau = 3.0;
mosfet_pos      = [12, 42];   // Klemmkanten zeigen zur linken/rechten Seitenwand

/* [Platine: Lolin NodeMCU V3] */
nodemcu_l        = 58;    // Laenge
nodemcu_b        = 31.5;  // Breite
nodemcu_h        = 14;    // Bauhoehe ueber der Platine
nodemcu_unterbau = 4.0;   // Freiraum fuer die Stiftleisten
nodemcu_pos      = [90, 58];  // um 90 Grad gedreht: Micro-USB zeigt zur Rueckwand
                              // x >= 90 haelt Abstand zum MOSFET-Endanschlag
microusb_oeff_b  = 12;    // Wandausschnitt Breite
microusb_oeff_h  = 8;     // Wandausschnitt Hoehe
microusb_achse   = 1.35;  // Achshoehe der Buchse ueber der Platinenoberseite

/* [Platine: LM2596 Buck-Converter] */
buck_l        = 43;
buck_b        = 21;
buck_h        = 14;
buck_unterbau = 3.0;
buck_pos      = [100, 6];     // um 90 Grad gedreht, rechte vordere Zone

/* [Platine: USB-C-PD-Triggerboard 31 x 20 mm] */
pd_b          = 20;       // Kante MIT der USB-C-Buchse (liegt an der Frontwand, X)
pd_l          = 31;       // Kante ohne Buchse (ragt ins Gehaeuse, Y)
pd_h          = 4.0;      // Bauhoehe ueber der Platine
pd_unterbau   = 3.0;
pd_dicke      = 1.6;

/* [USB-C-Buchse] */
usbc_achse       = 1.65;  // Achshoehe der Buchse ueber der Platinenoberseite
usbc_oeff_b      = 13.5;  // Wanddurchbruch Breite (Steckergehaeuse + Spiel)
usbc_oeff_h      = 7.5;   // Wanddurchbruch Hoehe
usbc_senk_b      = 17.0;  // Aussenansenkung Breite
usbc_senk_t      = 1.2;   // Aussenansenkung Tiefe -> Stecker taucht fast buendig ein
usbc_senk_rand   = 1.5;   // Ansenkung ragt oben ueber den Durchbruch hinaus
usbc_sattel_t    = 5.0;   // Tiefe des Sattels unter der Platinenvorderkante
usbc_rippe_dicke = 3.0;   // Anschlagrippe hinter der Platine (nimmt Steckkraefte)

/* [Lueftung] */
lueftung          = true;
lueftung_n        = 6;    // Schlitze je Seitenwand
lueftung_b        = 3.0;  // Breite (Y)
lueftung_h        = 16.0; // Hoehe  (Z)
lueftung_abstand  = 10.0; // Rastermass
lueftung_z        = 16.0; // Mittenhoehe ueber der Trennebene

// ============================================================================
//  2) ABGELEITETE GROESSEN
// ============================================================================

aussen_x = innen_x + 2*wand;
aussen_y = innen_y + 2*wand;
innen_r  = max(0.6, ecken_r - wand);

mosfet_gr  = [mosfet_l, mosfet_b];      // Klemmen an den Y-Kanten
nodemcu_gr = [nodemcu_b, nodemcu_l];    // 90 Grad gedreht
buck_gr    = [buck_b, buck_l];          // 90 Grad gedreht
pd_gr      = [pd_b, pd_l];
pd_pos     = [innen_x/2 - pd_b/2, 0];   // Buchse exakt mittig in der Frontwand

hoehe_bauteile = max(mosfet_unterbau + mosfet_h,
                     nodemcu_unterbau + nodemcu_h,
                     buck_unterbau + buck_h,
                     pd_unterbau + pd_dicke + 2*usbc_achse);

innen_z = hoehe_override > 0
        ? hoehe_override
        : hoehe_bauteile + max(kabel_freiraum, saeule_dom_l + 2);

aussen_z = boden_dicke + innen_z + deckel_dicke;

mitte_x = innen_x/2;
mitte_y = innen_y/2;

// USB-C
usbc_x   = pd_pos[0] + pd_b/2;
usbc_z   = pd_unterbau + pd_dicke + usbc_achse;   // Achshoehe ueber der Trennebene
usbc_o_u = usbc_z - usbc_oeff_h/2;                // Unterkante Durchbruch
usbc_o_o = usbc_z + usbc_oeff_h/2;                // Oberkante Durchbruch

// Micro-USB
mu_x   = nodemcu_pos[0] + nodemcu_gr[0]/2;
mu_z   = nodemcu_unterbau + pcb_dicke + microusb_achse;
mu_o_u = mu_z - microusb_oeff_h/2;
mu_o_o = mu_z + microusb_oeff_h/2;

// Eckdome
dom_pos = [[dom_abstand,           dom_abstand],
           [innen_x - dom_abstand, dom_abstand],
           [dom_abstand,           innen_y - dom_abstand],
           [innen_x - dom_abstand, innen_y - dom_abstand]];

echo(str("Innenmasse  : ", innen_x, " x ", innen_y, " x ", innen_z, " mm"));
echo(str("Aussenmasse : ", aussen_x, " x ", aussen_y, " x ", aussen_z, " mm"));
echo(str("USB-C       : x=", usbc_x, "  Achse z=", usbc_z,
         "  Durchbruch z ", usbc_o_u, " .. ", usbc_o_o));
echo(str("Micro-USB   : x=", mu_x, "  Achse z=", mu_z));
echo(str("Saeulendome : Unterkante z=", innen_z - saeule_dom_l,
         "  hoechste Baugruppe z=", hoehe_bauteile,
         (innen_z - saeule_dom_l >= hoehe_bauteile) ? "  -> OK" : "  -> KOLLISION!"));

// ============================================================================
//  3) HILFSMODULE
// ============================================================================

// 2D-Rechteck mit verrundeten Ecken, Ursprung in der linken unteren Ecke
module rr2d(sx, sy, r) {
    translate([r, r]) offset(r = r) square([sx - 2*r, sy - 2*r]);
}

// Prisma entlang X: das 2D-Polygon liegt in der (y,z)-Ebene, x = 0 .. breite
module prisma_x(breite, pts) {
    rotate([90, 0, 90]) linear_extrude(height = breite) polygon(points = pts);
}

// Klemme: Kante der Platine liegt bei y = 0, die Platine selbst bei y > 0.
// Der Haken greift mit haken_u ueber die Platine, die Oberseite ist als
// 45-Grad-Fase ausgefuehrt (Einfuehrschraege beim Eindruecken).
module klemme(h_unter, dicke, haken_u) {
    hb = h_unter + pcb_dicke + pcb_spiel_z;    // Unterkante des Rasthakens
    translate([-klemm_b/2, -dicke, 0])
        cube([klemm_b, dicke, hb + klemm_haken_h]);
    translate([-klemm_b/2, 0, 0])
        prisma_x(klemm_b, [[0, hb], [haken_u, hb], [0, hb + klemm_haken_h]]);
}

// Endanschlag ohne Haken
module anschlag(breite, h_unter, dicke) {
    translate([-breite/2, -dicke, 0])
        cube([breite, dicke, h_unter + pcb_dicke + anschlag_ueber]);
}

// Positioniert children() an einer Platinenkante (lokal: Kante y=0, Platine y>0)
module an_kante(pos, gr, seite, entlang) {
    px = pos[0]; py = pos[1]; sx = gr[0]; sy = gr[1]; s = pcb_spiel/2;
    if (seite == "vorn")
        translate([px + entlang, py - s, 0]) children();
    if (seite == "hinten")
        translate([px + entlang, py + sy + s, 0]) rotate([0, 0, 180]) children();
    if (seite == "links")
        translate([px - s, py + entlang, 0]) rotate([0, 0, -90]) children();
    if (seite == "rechts")
        translate([px + sx + s, py + entlang, 0]) rotate([0, 0, 90]) children();
}

// Auflagepads unter den Platinenecken - halten Loetstellen vom Boden fern
module pcb_pads(pos, gr, h_unter) {
    px = pos[0]; py = pos[1]; sx = gr[0]; sy = gr[1];
    for (dx = [pad_inset, sx - pad_inset], dy = [pad_inset, sy - pad_inset])
        translate([px + dx - pad_d/2, py + dy - pad_d/2, 0])
            cube([pad_d, pad_d, h_unter]);
}

// Vollstaendige schraubenlose Halterung einer Platine:
// eine Seite starre Auflageleisten, gegenueber federnde Schnappclipse.
//   klemm_achse : "x" -> Klemmen an der linken/rechten Kante
//                 "y" -> Klemmen an der vorderen/hinteren Kante
//   anschlaege  : Liste der Kanten, die einen Endanschlag bekommen
module platine_halter(pos, gr, h_unter, klemm_achse = "x", anschlaege = []) {
    sx = gr[0]; sy = gr[1];
    pcb_pads(pos, gr, h_unter);

    if (klemm_achse == "x")
        for (p = [sy*0.28, sy*0.72]) {
            an_kante(pos, gr, "links",  p) klemme(h_unter, klemm_dicke_fest,  klemm_haken_fest);
            an_kante(pos, gr, "rechts", p) klemme(h_unter, klemm_dicke_feder, klemm_haken_feder);
        }
    else
        for (p = [sx*0.28, sx*0.72]) {
            an_kante(pos, gr, "vorn",   p) klemme(h_unter, klemm_dicke_fest,  klemm_haken_fest);
            an_kante(pos, gr, "hinten", p) klemme(h_unter, klemm_dicke_feder, klemm_haken_feder);
        }

    for (s = anschlaege) {
        laenge = (s == "vorn" || s == "hinten") ? sx : sy;
        an_kante(pos, gr, s, laenge/2)
            anschlag(laenge*0.5, h_unter, anschlag_dicke);
    }
}

// Platinen-Geist zur Kollisionskontrolle (% = nicht im Rendering/STL)
module platine_geist(pos, gr, h_unter, h_bauteil, dicke = 1.6) {
    %translate([pos[0], pos[1], h_unter]) {
        color("green")   cube([gr[0], gr[1], dicke]);
        translate([0, 0, dicke]) color("dimgray") cube([gr[0], gr[1], h_bauteil]);
    }
}

// ============================================================================
//  4) NEGATIVE (Wandausschnitte)
// ============================================================================

// USB-C: nach unten offener Durchbruch, damit die komplett bestueckte
// Bodenbaugruppe von unten senkrecht eingefahren werden kann.
module usbc_negativ() {
    translate([usbc_x - usbc_oeff_b/2, -wand - 1, -eps])
        cube([usbc_oeff_b, wand + 2, usbc_o_o + eps]);
    if (usbc_senk_t > 0)
        translate([usbc_x - usbc_senk_b/2, -wand - eps, -eps])
            cube([usbc_senk_b, usbc_senk_t + eps, usbc_o_o + usbc_senk_rand + eps]);
}

// Micro-USB des NodeMCU in der Rueckwand, ebenfalls nach unten offen
module microusb_negativ() {
    translate([mu_x - microusb_oeff_b/2, innen_y - 1, -eps])
        cube([microusb_oeff_b, wand + 2, mu_o_o + eps]);
}

module lueftung_negativ() {
    if (lueftung)
        for (seite = [0, 1])
            for (i = [0 : lueftung_n - 1]) {
                y = mitte_y + (i - (lueftung_n - 1)/2) * lueftung_abstand;
                x = (seite == 0) ? -wand - 1 : innen_x - 1;
                translate([x, y, lueftung_z])
                    rotate([0, 90, 0])
                        linear_extrude(height = wand + 2)
                            offset(r = lueftung_b/2)
                                square([lueftung_h - lueftung_b, 0.01], center = true);
            }
}

// ============================================================================
//  5) HAUPTKOERPER (Waende + Deckel)
// ============================================================================

module schale() {
    difference() {
        translate([-wand, -wand, 0])
            linear_extrude(height = innen_z + deckel_dicke)
                rr2d(aussen_x, aussen_y, ecken_r);
        translate([0, 0, -eps])
            linear_extrude(height = innen_z + eps)
                rr2d(innen_x, innen_y, innen_r);
    }
}

module eckdome() {
    for (p = dom_pos)
        translate([p[0], p[1], 0]) cylinder(h = innen_z, d = dom_d);
}

module eckdom_bohrungen() {
    for (p = dom_pos)
        translate([p[0], p[1], -eps]) {
            cylinder(h = insert_l + eps, d = insert_d);
            cylinder(h = insert_l + 4, d = insert_pilot_d);
        }
}

module saeule_positionen() {
    r = saeule_lochkreis_d/2;
    for (i = [0 : saeule_schrauben_n - 1]) {
        a = saeule_winkel_offset + i * 360/saeule_schrauben_n;
        translate([mitte_x + r*cos(a), mitte_y + r*sin(a), 0]) children();
    }
}

module deckel_additiv() {
    // lokale Verstaerkung im Flanschbereich (Deckelinnenseite)
    translate([mitte_x, mitte_y, innen_z - saeule_verstaerkung])
        cylinder(h = saeule_verstaerkung, d = saeule_fuss_d + 10);

    // Insert-Dome fuer die Flanschschrauben
    if (saeule_insert)
        saeule_positionen()
            translate([0, 0, innen_z - saeule_dom_l])
                cylinder(h = saeule_dom_l, d = saeule_dom_d);

    // Zentrierring aussen, nimmt den Saeulenfuss auf
    // (taucht 0.5 mm in den Deckel ein - koinzidente Flaechen vermeiden)
    if (saeule_zentrierring)
        translate([mitte_x, mitte_y, innen_z + deckel_dicke - 0.5])
            difference() {
                cylinder(h = saeule_ring_h + 0.5,
                         d = saeule_fuss_d + 2*spiel + 2*saeule_ring_breite);
                translate([0, 0, -eps])
                    cylinder(h = saeule_ring_h + 0.5 + 2*eps, d = saeule_fuss_d + 2*spiel);
            }
}

module deckel_negativ() {
    oben = innen_z + deckel_dicke;

    // zentrale Kabeldurchfuehrung mit Fase auf beiden Seiten
    translate([mitte_x, mitte_y, innen_z - saeule_verstaerkung - 1])
        cylinder(h = deckel_dicke + saeule_verstaerkung + 2 + saeule_ring_h,
                 d = saeule_kabel_d);
    translate([mitte_x, mitte_y, oben - saeule_kabel_fase])
        cylinder(h = saeule_kabel_fase + eps,
                 d1 = saeule_kabel_d, d2 = saeule_kabel_d + 2*saeule_kabel_fase);
    translate([mitte_x, mitte_y, innen_z - saeule_verstaerkung - eps])
        cylinder(h = saeule_kabel_fase + eps,
                 d1 = saeule_kabel_d + 2*saeule_kabel_fase, d2 = saeule_kabel_d);

    // Flanschschrauben: Durchgang von oben, darunter das Insert
    saeule_positionen() {
        translate([0, 0, innen_z - saeule_dom_l - 1])
            cylinder(h = saeule_dom_l + deckel_dicke + saeule_ring_h + 2,
                     d = saeule_schraube_d);
        if (saeule_insert)
            translate([0, 0, innen_z - saeule_dom_l - eps])
                cylinder(h = saeule_insert_l + eps, d = saeule_insert_d);
    }
}

module hauptkoerper() {
    difference() {
        union() {
            schale();
            eckdome();
            deckel_additiv();
        }
        eckdom_bohrungen();
        deckel_negativ();
        usbc_negativ();
        microusb_negativ();
        lueftung_negativ();
    }
}

// ============================================================================
//  6) BODEN (Platte + Platinenhalterung + Steckerkragen)
// ============================================================================

// Der Steckerkragen fuellt den nach unten offenen Wandschlitz und bildet die
// Unterkante der Steckeroeffnung. Er umschliesst die USB-C-Buchse und leitet
// die Steckkraefte ueber die Bodenplatte in die Verschraubung - nicht in die
// Loetstellen der Buchse.
module usbc_kragen() {
    f = spiel;
    // Zunge im Durchbruch
    translate([usbc_x - (usbc_oeff_b - 2*f)/2, -wand + usbc_senk_t, 0])
        cube([usbc_oeff_b - 2*f, wand - usbc_senk_t, usbc_o_u]);
    // Stufe in der Aussenansenkung
    if (usbc_senk_t > 0)
        translate([usbc_x - (usbc_senk_b - 2*f)/2, -wand, 0])
            cube([usbc_senk_b - 2*f, usbc_senk_t, usbc_o_u]);
    // Sattel unter der Platinenvorderkante: traegt Buchse und Platine
    translate([usbc_x - pd_b/2, 0, 0])
        cube([pd_b, usbc_sattel_t, pd_unterbau]);
}

module microusb_fueller() {
    f = spiel;
    translate([mu_x - (microusb_oeff_b - 2*f)/2, innen_y, 0])
        cube([microusb_oeff_b - 2*f, wand, mu_o_u]);
}

// Anschlagrippe hinter dem PD-Board - nimmt die Steckkraefte ueber die
// Platinenkante auf, nicht ueber die Loetpads der Buchse
module pd_anschlagrippe() {
    translate([pd_pos[0] - 2, pd_pos[1] + pd_l + pcb_spiel/2, 0])
        cube([pd_b + 4, usbc_rippe_dicke, pd_unterbau + pd_dicke + anschlag_ueber]);
}

module lippe_koerper() {
    linear_extrude(height = lippe_h)
        difference() {
            offset(delta = -spiel)               rr2d(innen_x, innen_y, innen_r);
            offset(delta = -spiel - lippe_dicke) rr2d(innen_x, innen_y, innen_r);
        }
}

module lippe_negativ() {
    // Eckdome freistellen
    for (p = dom_pos)
        translate([p[0], p[1], -eps])
            cylinder(h = lippe_h + 2*eps, d = dom_d + 2*spiel);
    // Unterbrechung vor dem PD-Board (Frontwand)
    translate([pd_pos[0] - 4, -1, -eps])
        cube([pd_b + 8, lippe_dicke + spiel + 2, lippe_h + 2*eps]);
    // Unterbrechung hinter dem NodeMCU (Rueckwand)
    translate([nodemcu_pos[0] - 4, innen_y - lippe_dicke - spiel - 1, -eps])
        cube([nodemcu_gr[0] + 8, lippe_dicke + spiel + 2, lippe_h + 2*eps]);
}

module platinen_halterungen() {
    // MOSFET: Klemmkanten seitlich -> Clipse vorne/hinten, Anschlaege seitlich
    platine_halter(mosfet_pos, mosfet_gr, mosfet_unterbau, "y", ["links", "rechts"]);
    // NodeMCU: Rueckkante liegt an der Wand -> nur vorne ein Anschlag
    platine_halter(nodemcu_pos, nodemcu_gr, nodemcu_unterbau, "x", ["vorn"]);
    // Buck-Converter
    platine_halter(buck_pos, buck_gr, buck_unterbau, "x", ["vorn", "hinten"]);
    // PD-Board: Vorderkante stuetzt sich an der Frontwand ab, hinten die Rippe
    platine_halter(pd_pos, pd_gr, pd_unterbau, "x", []);
}

module boden() {
    difference() {
        union() {
            translate([-wand, -wand, -boden_dicke])
                linear_extrude(height = boden_dicke)
                    rr2d(aussen_x, aussen_y, ecken_r);
            if (lippe)
                difference() { lippe_koerper(); lippe_negativ(); }
            platinen_halterungen();
            usbc_kragen();
            microusb_fueller();
            pd_anschlagrippe();
        }
        // Verschraubung mit Senkung von unten
        for (p = dom_pos)
            translate([p[0], p[1], -boden_dicke - 1]) {
                cylinder(h = boden_dicke + 2, d = schraube_d);
                cylinder(h = 1 + senkung_t, d = senkung_d);
            }
    }
}

// ============================================================================
//  7) GEISTER-PLATINEN
// ============================================================================

module platinen() {
    if (zeige_platinen) {
        platine_geist(mosfet_pos,  mosfet_gr,  mosfet_unterbau,  mosfet_h);
        platine_geist(nodemcu_pos, nodemcu_gr, nodemcu_unterbau, nodemcu_h);
        platine_geist(buck_pos,    buck_gr,    buck_unterbau,    buck_h);
        platine_geist(pd_pos,      pd_gr,      pd_unterbau,      pd_h, pd_dicke);
    }
}

// ============================================================================
//  8) RENDER-AUSWAHL
// ============================================================================

if (teil == "body") {
    hauptkoerper();
} else if (teil == "boden") {
    boden();
} else if (teil == "explosion") {
    translate([0, 0, 45]) hauptkoerper();
    boden();
    platinen();
} else {
    color("gainsboro", 0.30) hauptkoerper();
    color("steelblue")       boden();
    platinen();
}
