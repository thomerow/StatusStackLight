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
senkung_d       = 6.2;    // Kopfdurchmesser DIN 7991 (6,0) + Spiel
senkung_winkel  = 90;     // eingeschlossener Kopfwinkel DIN 7991
senkung_anlauf  = 0.3;    // kurzer zylindrischer Anlauf an der Aussenflaeche:
                          // faengt den Elefantenfuss der ersten Schicht ab und
                          // haelt den Kopf vom Radius unter dem Kopf frei

/* [Zentrierlippe des Bodens] */
lippe           = true;
lippe_h         = 4.0;
lippe_dicke     = 1.2;

/* [Signalsaeule - gemessen: Lochkreis 55 mm, 4 x M4, Fuss 70 mm] */
saeule_fuss_d        = 70;    // GEMESSEN: Aussendurchmesser des Saeulenfusses
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
// Erhabener Ring um den Saeulenfuss. ABGESCHALTET: der Hauptkoerper wird auf
// dem Deckel stehend gedruckt, der Ring waere dann das einzige, was auf dem
// Druckbett aufliegt - die gesamte restliche Deckelflaeche haette 1,2 mm in
// der Luft gehangen. Die 4 M4-Schrauben auf dem 55er Lochkreis zentrieren den
// Flansch ohnehin. Nur einschalten, wenn der Koerper anders gedruckt wird.
saeule_zentrierring  = false;
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

// KONVENTION: alle *_h sind GESAMTHOEHEN inkl. Platine (so, wie man sie mit
// dem Messschieber ueber das ganze Modul abgreift). *_unterbau ist der Abstand
// der Platinenunterseite von der Trennebene.

/* [Platine: 8-Kanal-MOSFET-Modul - gemessen 68 x 72 mm] */
mosfet_l        = 72;     // laengere Kante (X)
mosfet_b        = 68;     // kuerzere Kante (Y) - hier sitzen die Schraubklemmen
mosfet_h        = 16;     // GEMESSEN: Gesamthoehe inkl. Platine und Schraubklemmen
mosfet_unterbau = 3.0;
mosfet_pos      = [12, 42];   // Klemmkanten zeigen zur linken/rechten Seitenwand

/* [Platine: ESP32-S3 DevKitC-1 N16R8 - GEMESSEN 57,3 x 28,1 x 1,6 mm] */
mcu_l            = 57.3;  // GEMESSEN: Platinenlaenge OHNE Antennenueberstand
mcu_b            = 28.1;  // GEMESSEN
mcu_h            = 5.0;   // Gesamthoehe inkl. Platine (1,6 + 3,4 gemessen)
mcu_unterbau     = 3.0;   // Kabel werden von oben in die Loetaugen gefuehrt, die
                          // Loetpunkte tragen also nach UNTEN auf.
mcu_antenne      = 6.3;   // GEMESSEN: das Modul steht mit seinem Antennenende ueber
                          // die Platinenkante hinaus. Es liegt auf Hoehe der
                          // Platinenoberseite - der Endanschlag darunter darf
                          // deshalb nicht darueber hinausragen (mcu_anschlag_ueber).
mcu_anschlag_ueber = -0.2;// 0,2 mm UNTER der Platinenoberseite. Exakt buendig (0)
                          // waere ideal, nur wuerde ein Zehntel Druckueberhoehung
                          // die Platinenvorderkante anheben. Bei -0,2 greift der
                          // Anschlag immer noch ueber 1,4 der 1,6 mm Kante.
mcu_pad_inset    = [8, 5];// Auflagepads in X weiter nach innen als der Standard:
                          // an den Laengskanten liegen die Loetaugen, deren
                          // Loetpunkte sonst auf den Pads aufsetzen wuerden.
mcu_pos          = [90, innen_y - mcu_l];   // um 90 Grad gedreht, USB-Seite an der
                          // Rueckwand, Antenne zeigt nach vorn ins Gehaeuse.
                          // x >= 90 haelt Abstand zum MOSFET-Endanschlag

// Beide USB-C-Buchsen sitzen an derselben Schmalseite. Gemessen wurde von der
// Platinenkante, die im Gehaeuse RECHTS liegt (Blick von hinten auf die
// Rueckwand = von der USB-Seite auf die Platine, da ist es die linke).
mcu_usb_rand     = 8.0;   // Buchsenmitte "USB" (nativ)  von der rechten Kante
mcu_com_rand     = 19.5;  // Buchsenmitte "COM" (UART)   von der rechten Kante
mcu_usb_achse    = 1.65;  // Achshoehe der Buchsen ueber der Platinenoberseite
mcu_usb_oeff_b   = 13.5;  // Durchbruchbreite je Stecker
mcu_usb_oeff_h   = 7.5;   // Durchbruchhoehe

/* [Beschriftung der USB-Buchsen auf dem Deckel] */
mcu_text         = true;
mcu_text_groesse = 4.5;
mcu_text_spreizung = 1.6; // Die Buchsenmitten liegen nur 11,5 mm auseinander, bei
                          // lesbarer Schriftgroesse stossen "USB" und "COM"
                          // aneinander. Die Beschriftung wird deshalb um diesen
                          // Faktor auseinandergezogen - links/rechts bleibt
                          // eindeutig zugeordnet, es sind ja nur zwei.
                          // 1.0 = exakt ueber den Buchsenmitten.
mcu_text_tiefe   = 0.6;   // Vertiefung. Der Koerper wird auf dem Deckel gedruckt,
                          // die Schrift liegt also am Druckbett und wird sauber.
mcu_text_abstand = 4.0;   // Mitte der Schrift vor der Rueckwand-Innenkante
mcu_text_drehung = 180;   // 180 = liest sich von hinten, wo man steckt
mcu_text_font    = "Liberation Sans:style=Bold";

/* [Platine: Mini560 Buck-Converter - GEMESSEN 30 x 18 x 6 mm] */
buck_l        = 30;       // laengere Kante
buck_b        = 18;       // kuerzere Kante - hier liegen die Loetpads
buck_h        = 6;        // GEMESSEN: Gesamthoehe inkl. Platine
buck_unterbau = 3.0;      // Freiraum fuer die Loetstellen der Durchkontaktierungen
buck_pos      = [100, 6];     // um 90 Grad gedreht, rechte vordere Zone
                              // -> Clipse greifen die langen Kanten, die
                              //    Loetpad-Kanten bleiben frei zugaenglich

// Sonderfall vordere linke Auflageleiste (Draufsicht auf die Bodenplatte, der
// USB-C-Eingang unten): auf der linken Platinenkante sitzt ein Bauteil buendig
// mit der Kante, die Leiste greift dort nicht. Sie rueckt deshalb nach vorn -
// dort liegt aber die Loetstelle des Plus-Eingangs, also wird sie zugleich
// schmaler. 0 / klemm_b stellt den symmetrischen Standard wieder her.
buck_klemm_vl_versatz = 3.0;  // nach vorn (-Y)
buck_klemm_vl_breite  = 4.0;  // statt klemm_b (6.0)

/* [Platine: USB-C-PD-Triggerboard 31 x 20 mm] */
pd_b          = 20;       // Kante MIT der USB-C-Buchse (liegt an der Frontwand, X)
pd_l          = 31.5;     // GEMESSEN: Kante ohne Buchse (ragt ins Gehaeuse, Y)
pd_h          = 5.6;      // Gesamthoehe inkl. Platine (1,6 Platine + 4,0 Aufbau)
pd_unterbau   = 3.0;
pd_dicke      = 1.6;

/* [USB-C-Buchse] */
usbc_achse       = 1.65;  // Achshoehe der Buchse ueber der Platinenoberseite
usbc_ueberstand  = 1.0;   // GEMESSEN: Ueberstand der Buchse ueber die Platinenkante
                          //           -> die Buchse taucht in den Wanddurchbruch ein
usbc_oeff_b      = 13.5;  // Wanddurchbruch Breite (Steckergehaeuse + Spiel)
usbc_oeff_h      = 7.5;   // Wanddurchbruch Hoehe
usbc_senk_b      = 17.0;  // Aussenansenkung Breite
usbc_senk_t      = 1.2;   // Aussenansenkung Tiefe -> Stecker taucht fast buendig ein
usbc_senk_rand   = 1.5;   // Ansenkung ragt oben ueber den Durchbruch hinaus
usbc_kragen_spiel= 0.4;   // Passung des Steckerkragens. Eigener Wert statt des
                          // allgemeinen spiel: links und rechts des Durchbruchs
                          // haengen zwei nur 1,75 mm schmale Wandzungen nach
                          // unten, die in die Kerben zwischen Zunge und Stufe
                          // fassen. Mit 0,2 mm war das im Druck eine Presspassung
                          // und musste nachgeschliffen werden.
usbc_sattel_t    = 5.0;   // Tiefe des Sattels unter der Platinenvorderkante
usbc_rippe_dicke = 3.0;   // Anschlagrippe hinter der Platine (nimmt Steckkraefte)
usbc_rippe_luecke= 10.0;  // mittige Luecke darin: die Loetaugen des PD-Boards
                          // sitzen hinten mittig, die Kabel muessen dort nach
                          // hinten heraus. 0 = durchgehende Rippe.

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
mcu_gr     = [mcu_b, mcu_l];            // 90 Grad gedreht
buck_gr    = [buck_b, buck_l];          // 90 Grad gedreht
pd_gr      = [pd_b, pd_l];
pd_pos     = [innen_x/2 - pd_b/2, 0];   // Buchse exakt mittig in der Frontwand

hoehe_bauteile = max(mosfet_unterbau + mosfet_h,
                     mcu_unterbau + mcu_h,
                     buck_unterbau + buck_h,
                     pd_unterbau + max(pd_h, pd_dicke + 2*usbc_achse));

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

// Laengsschnitt durch die Frontwand (y):  -wand .. -wand+usbc_senk_t = Ansenkung,
// darin taucht die Buchse mit usbc_ueberstand von innen ein.
usbc_stirn      = -usbc_ueberstand;         // Stirnflaeche der Buchse
usbc_senkboden  = -wand + usbc_senk_t;      // Boden der Aussenansenkung
usbc_luft       = usbc_stirn - usbc_senkboden;   // Restwand vor der Buchse

// Micro-USB
// Die Buchsenmitten werden von der rechten Platinenkante aus gemessen.
mcu_usb_x = mcu_pos[0] + mcu_b - mcu_usb_rand;
mcu_com_x = mcu_pos[0] + mcu_b - mcu_com_rand;
mcu_z     = mcu_unterbau + pcb_dicke + mcu_usb_achse;
mcu_o_u   = mcu_z - mcu_usb_oeff_h/2;
mcu_o_o   = mcu_z + mcu_usb_oeff_h/2;

// Ein gemeinsamer Durchbruch fuer beide Buchsen statt zweier Einzelfenster:
// die Stege dazwischen waeren nur gut 1 mm breit und im Druck wertlos.
mcu_oeff_l = min(mcu_usb_x, mcu_com_x) - mcu_usb_oeff_b/2;
mcu_oeff_r = max(mcu_usb_x, mcu_com_x) + mcu_usb_oeff_b/2;
mcu_oeff_b = mcu_oeff_r - mcu_oeff_l;

// Vorderkante der Antenne und Oberkante des Endanschlags darunter
mcu_antenne_y = mcu_pos[1] - mcu_antenne;
mcu_pcb_oben  = mcu_unterbau + pcb_dicke;

// Wirksame Ringhoehe: geht in die Laenge der Deckeldurchbrueche ein, damit
// diese den Ring durchstossen - ohne Ring waeren es unnoetige Ueberlaengen.
ring_h_eff = saeule_zentrierring ? saeule_ring_h : 0;

// Senkung der Bodenschrauben: Kegel mit senkung_winkel, an der Aussenflaeche
// senkung_d breit, verjuengt auf das Durchgangsloch. Die Tiefe folgt aus dem
// Winkel - nicht separat vorgeben, sonst passt der Kegel nicht zum Schraubenkopf.
senk_kegel_t = (senkung_d - schraube_d)/2 / tan(senkung_winkel/2);
senk_t_ges   = senkung_anlauf + senk_kegel_t;
senk_rest    = boden_dicke - senk_t_ges;   // Restmaterial unter der Senkung

// Eckdome
dom_pos = [[dom_abstand,           dom_abstand],
           [innen_x - dom_abstand, dom_abstand],
           [dom_abstand,           innen_y - dom_abstand],
           [innen_x - dom_abstand, innen_y - dom_abstand]];

echo(str("Innenmasse  : ", innen_x, " x ", innen_y, " x ", innen_z, " mm"));
echo(str("Aussenmasse : ", aussen_x, " x ", aussen_y, " x ", aussen_z, " mm",
         saeule_zentrierring ? str(" + ", saeule_ring_h, " mm Zentrierring") : " (Deckel plan)"));
echo(str("USB-C       : x=", usbc_x, "  Achse z=", usbc_z,
         "  Durchbruch z ", usbc_o_u, " .. ", usbc_o_o));
echo(str("MCU         : ", mcu_b, " x ", mcu_l, " bei x=", mcu_pos[0],
         " y=", mcu_pos[1], "  Antenne bis y=", mcu_antenne_y));
echo(str("MCU-USB     : USB x=", mcu_usb_x, "  COM x=", mcu_com_x,
         "  Durchbruch x ", mcu_oeff_l, " .. ", mcu_oeff_r,
         " (", mcu_oeff_b, " mm)  Achse z=", mcu_z));
// Auseinandergezogene Schriftmitten
mcu_text_mitte = (mcu_usb_x + mcu_com_x) / 2;
mcu_text_usb_x = mcu_text_mitte + (mcu_usb_x - mcu_text_mitte) * mcu_text_spreizung;
mcu_text_com_x = mcu_text_mitte + (mcu_com_x - mcu_text_mitte) * mcu_text_spreizung;

// Textbreite laesst sich in OpenSCAD nicht messen. 0,95 x Groesse je Zeichen ist
// fuer Liberation Sans Bold in Grossbuchstaben am gerenderten Bild nachgemessen -
// die vorher angesetzten 0,62 waren deutlich zu optimistisch.
mcu_text_breite = 3 * 0.95 * mcu_text_groesse;
mcu_text_luft   = abs(mcu_text_usb_x - mcu_text_com_x) - mcu_text_breite;
echo(str("MCU-Text    : ~", mcu_text_breite, " mm breit, Schriftmitten ",
         abs(mcu_text_usb_x - mcu_text_com_x), " auseinander  Luft=", mcu_text_luft, " mm",
         (mcu_text_luft > 2) ? "  -> OK"
                             : "  -> zu eng, mcu_text_spreizung hoch oder Groesse runter!"));
echo(str("MCU-Anschlag: Oberkante z=", mcu_pcb_oben + mcu_anschlag_ueber,
         "  Platinenoberseite z=", mcu_pcb_oben,
         "  Eingriff in die Kante=", min(pcb_dicke, pcb_dicke + mcu_anschlag_ueber), " mm",
         (mcu_anschlag_ueber > 0)    ? "  -> ragt ueber, Antenne kollidiert!" :
         (mcu_anschlag_ueber < -0.8) ? "  -> Eingriff wird duenn"
                                     : "  -> OK, Antenne frei"));
echo(str("USB-C-Buchse: Stirn y=", usbc_stirn, "  Ansenkungsboden y=", usbc_senkboden,
         "  Restwand=", usbc_luft, " mm",
         (usbc_luft >= 0) ? "  -> OK" : "  -> Ansenkung schneidet die Buchse an!"));
echo(str("USB-C-Kragen: Zunge ", usbc_oeff_b - 2*usbc_kragen_spiel, " in ", usbc_oeff_b,
         ", Stufe ", usbc_senk_b - 2*usbc_kragen_spiel, " in ", usbc_senk_b,
         "  Kerbenluft=", usbc_kragen_spiel, " mm je Flanke",
         (usbc_kragen_spiel >= 0.3) ? "  -> OK" : "  -> im Druck vermutlich stramm"));
echo(str("Buck-Leiste : vorne links y=", buck_pos[1] + buck_gr[1]*0.28 - buck_klemm_vl_versatz,
         " (", buck_klemm_vl_breite, " mm breit), hinten links y=",
         buck_pos[1] + buck_gr[1]*0.72, "  Rand zur Platinenvorderkante=",
         buck_gr[1]*0.28 - buck_klemm_vl_versatz - buck_klemm_vl_breite/2, " mm"));
echo(str("PD-Rippe    : 2 x ", (pd_b + 4 - usbc_rippe_luecke)/2,
         " mm breit, Luecke ", usbc_rippe_luecke, " mm mittig fuer die Loetaugen",
         ((pd_b + 4 - usbc_rippe_luecke)/2 >= 4) ? "  -> OK" : "  -> Segmente zu schmal!"));
echo(str("Senkung     : ", senkung_winkel, " Grad, Tiefe ", senk_t_ges,
         " mm  Restboden=", senk_rest, " mm",
         (senk_rest >= 0.6) ? "  -> OK" : "  -> zu duenn, boden_dicke erhoehen!"));
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
module klemme(h_unter, dicke, haken_u, breite = klemm_b) {
    hb = h_unter + pcb_dicke + pcb_spiel_z;    // Unterkante des Rasthakens
    translate([-breite/2, -dicke, 0])
        cube([breite, dicke, hb + klemm_haken_h]);
    translate([-breite/2, 0, 0])
        prisma_x(breite, [[0, hb], [haken_u, hb], [0, hb + klemm_haken_h]]);
}

// Endanschlag ohne Haken. ueber = Ueberstand ueber die Platinenoberseite;
// 0 macht ihn buendig, noetig wenn ein Bauteil ueber die Kante hinausragt.
module anschlag(breite, h_unter, dicke, ueber = undef) {
    u = is_undef(ueber) ? anschlag_ueber : ueber;
    translate([-breite/2, -dicke, 0])
        cube([breite, dicke, h_unter + pcb_dicke + u]);
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
// versatz: Abstand der Padmitte von der Platinenecke. Zahl = beide Achsen,
// [x, y] = getrennt. Getrennt ist noetig, wenn die Loetaugen nur an einem
// Kantenpaar liegen: dann weichen die Pads nur in dieser Achse nach innen aus
// und die Auflage bleibt in der anderen so breit wie moeglich.
module pcb_pads(pos, gr, h_unter, versatz = undef) {
    px = pos[0]; py = pos[1]; sx = gr[0]; sy = gr[1];
    v  = is_undef(versatz) ? [pad_inset, pad_inset]
       : is_list(versatz)  ? versatz : [versatz, versatz];
    for (dx = [v[0], sx - v[0]], dy = [v[1], sy - v[1]])
        translate([px + dx - pad_d/2, py + dy - pad_d/2, 0])
            cube([pad_d, pad_d, h_unter]);
}

// Vollstaendige schraubenlose Halterung einer Platine:
// eine Seite starre Auflageleisten, gegenueber federnde Schnappclipse.
//   klemm_achse : "x" -> Klemmen an der linken/rechten Kante
//                 "y" -> Klemmen an der vorderen/hinteren Kante
//   anschlaege  : Liste der Kanten, die einen Endanschlag bekommen
//   klemmen_fest / klemmen_feder : optionale Liste [[position, breite], ...]
//     je Klemme, Position entlang der Kante gemessen. Leer = Standard, also
//     zwei Klemmen bei 28 % und 72 % der Kantenlaenge mit klemm_b Breite.
//     Damit lassen sich einzelne Klemmen um Bauteile herumlegen, ohne die
//     Symmetrie fuer alle anderen Platinen aufzugeben.
//   anschlag_hoehe : Ueberstand der Endanschlaege, undef = anschlag_ueber
//   pad_versatz    : siehe pcb_pads()
module platine_halter(pos, gr, h_unter, klemm_achse = "x", anschlaege = [],
                      klemmen_fest = [], klemmen_feder = [],
                      anschlag_hoehe = undef, pad_versatz = undef) {
    sx = gr[0]; sy = gr[1];
    pcb_pads(pos, gr, h_unter, pad_versatz);

    kante = (klemm_achse == "x") ? sy : sx;
    std   = [[kante*0.28, klemm_b], [kante*0.72, klemm_b]];
    kf    = (len(klemmen_fest)  > 0) ? klemmen_fest  : std;
    kd    = (len(klemmen_feder) > 0) ? klemmen_feder : std;

    s_fest  = (klemm_achse == "x") ? "links"  : "vorn";
    s_feder = (klemm_achse == "x") ? "rechts" : "hinten";

    for (k = kf)
        an_kante(pos, gr, s_fest,  k[0]) klemme(h_unter, klemm_dicke_fest,  klemm_haken_fest,  k[1]);
    for (k = kd)
        an_kante(pos, gr, s_feder, k[0]) klemme(h_unter, klemm_dicke_feder, klemm_haken_feder, k[1]);

    for (s = anschlaege) {
        laenge = (s == "vorn" || s == "hinten") ? sx : sy;
        an_kante(pos, gr, s, laenge/2)
            anschlag(laenge*0.5, h_unter, anschlag_dicke, anschlag_hoehe);
    }
}

// Platinen-Geist zur Kollisionskontrolle (% = nicht im Rendering/STL)
module platine_geist(pos, gr, h_unter, h_bauteil, dicke = 1.6) {
    %translate([pos[0], pos[1], h_unter]) {
        color("green")   cube([gr[0], gr[1], dicke]);
        // h_bauteil ist die Gesamthoehe -> der Aufbau ist um die Platine niedriger
        translate([0, 0, dicke])
            color("dimgray") cube([gr[0], gr[1], max(h_bauteil - dicke, 0.1)]);
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

// Beide USB-C-Buchsen des MCU in der Rueckwand - ein gemeinsames Fenster,
// ebenfalls nach unten offen, damit die bestueckte Bodenplatte einfahren kann.
module mcu_usb_negativ() {
    translate([mcu_oeff_l, innen_y - 1, -eps])
        cube([mcu_oeff_b, wand + 2, mcu_o_o + eps]);
}

// Vertiefte Beschriftung der beiden Buchsen auf der Deckelaussenseite
module mcu_beschriftung() {
    if (mcu_text)
        for (b = [["USB", mcu_text_usb_x], ["COM", mcu_text_com_x]])
            translate([b[1], innen_y - mcu_text_abstand,
                       innen_z + deckel_dicke - mcu_text_tiefe])
                rotate([0, 0, mcu_text_drehung])
                    linear_extrude(height = mcu_text_tiefe + eps)
                        text(b[0], size = mcu_text_groesse, halign = "center",
                             valign = "center", font = mcu_text_font);
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
    oben = innen_z + deckel_dicke;   // Deckelaussenflaeche - ohne Ring die Oberseite

    // zentrale Kabeldurchfuehrung mit Fase auf beiden Seiten
    translate([mitte_x, mitte_y, innen_z - saeule_verstaerkung - 1])
        cylinder(h = deckel_dicke + saeule_verstaerkung + 2 + ring_h_eff,
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
            cylinder(h = saeule_dom_l + deckel_dicke + ring_h_eff + 2,
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
        mcu_usb_negativ();
        mcu_beschriftung();
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
    f = usbc_kragen_spiel;
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

module mcu_usb_fueller() {
    f = usbc_kragen_spiel;
    translate([mcu_oeff_l + f, innen_y, 0])
        cube([mcu_oeff_b - 2*f, wand, mcu_o_u]);
}

// Anschlagrippe hinter dem PD-Board - nimmt die Steckkraefte ueber die
// Platinenkante auf, nicht ueber die Loetpads der Buchse
// Zwei Segmente statt einer durchgehenden Rippe - mittig bleibt Platz fuer die
// Kabel an den Loetaugen. Die Steckkraft laeuft dadurch ueber die beiden
// hinteren Platinenecken statt ueber die Mitte. Das kommt der Platine eher
// entgegen: sie wird nicht mehr auf Biegung belastet.
module pd_anschlagrippe() {
    gesamt = pd_b + 4;
    seg    = max((gesamt - usbc_rippe_luecke) / 2, 0.01);
    hoehe  = pd_unterbau + pd_dicke + anschlag_ueber;
    y      = pd_pos[1] + pd_l + pcb_spiel/2;
    for (x = [pd_pos[0] - 2, pd_pos[0] - 2 + gesamt - seg])
        translate([x, y, 0]) cube([seg, usbc_rippe_dicke, hoehe]);
}

// Schraubloch der Bodenplatte: Durchgang + kegelige Senkung von aussen.
// z = -boden_dicke ist die Aussenflaeche; die Platte wird mit dieser Flaeche
// auf dem Druckbett gedruckt - der 45-Grad-Kegel ist dabei selbsttragend.
module senkloch() {
    translate([0, 0, -boden_dicke - 1])
        cylinder(h = boden_dicke + 2, d = schraube_d);
    if (senkung_anlauf > 0)
        translate([0, 0, -boden_dicke - eps])
            cylinder(h = senkung_anlauf + eps, d = senkung_d);
    translate([0, 0, -boden_dicke + senkung_anlauf])
        cylinder(h = senk_kegel_t, d1 = senkung_d, d2 = schraube_d);
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
    // Unterbrechung hinter dem MCU (Rueckwand)
    translate([mcu_pos[0] - 4, innen_y - lippe_dicke - spiel - 1, -eps])
        cube([mcu_gr[0] + 8, lippe_dicke + spiel + 2, lippe_h + 2*eps]);
}

module platinen_halterungen() {
    // MOSFET: Klemmkanten seitlich -> Clipse vorne/hinten, Anschlaege seitlich
    platine_halter(mosfet_pos, mosfet_gr, mosfet_unterbau, "y", ["links", "rechts"]);
    // MCU: Rueckkante liegt an der Wand -> nur vorne ein Anschlag, und der
    // muss buendig mit der Platinenoberseite bleiben (Antennenueberstand).
    platine_halter(mcu_pos, mcu_gr, mcu_unterbau, "x", ["vorn"],
                   anschlag_hoehe = mcu_anschlag_ueber,
                   pad_versatz    = mcu_pad_inset);
    // Buck-Converter: vordere linke Leiste versetzt und schmaler, siehe Parameter
    platine_halter(buck_pos, buck_gr, buck_unterbau, "x", ["vorn", "hinten"],
                   klemmen_fest = [[buck_gr[1]*0.28 - buck_klemm_vl_versatz, buck_klemm_vl_breite],
                                   [buck_gr[1]*0.72, klemm_b]]);
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
            mcu_usb_fueller();
            pd_anschlagrippe();
        }
        // Verschraubung mit kegeliger Senkung von unten
        for (p = dom_pos)
            translate([p[0], p[1], 0]) senkloch();
    }
}

// ============================================================================
//  7) GEISTER-PLATINEN
// ============================================================================

module platinen() {
    if (zeige_platinen) {
        platine_geist(mosfet_pos,  mosfet_gr,  mosfet_unterbau,  mosfet_h);
        platine_geist(mcu_pos, mcu_gr, mcu_unterbau, mcu_h);
        // ueberstehendes Antennenende des Moduls
        %translate([mcu_pos[0], mcu_antenne_y, mcu_pcb_oben])
            color("darkgreen") cube([mcu_b, mcu_antenne, 1.0]);
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
