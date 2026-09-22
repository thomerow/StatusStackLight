// ============================================================================
//  StatusStackLight - enclosure for an industrial stack light
//  Stage 1: two parts (main body with integrated lid + removable base plate)
//
//  Contents: ESP32-S3 DevKitC-1 (N16R8), 8-channel MOSFET module, Mini560 buck
//            12V->3.3V, USB-C PD trigger board (requests 12 V)
//
//  Coordinate system (all layout dimensions in "inner coordinates"):
//    x = 0 .. inner_x    left  -> right inner wall
//    y = 0 .. inner_y    front -> back inner wall
//    z = 0               parting plane = top of the base plate (inner floor)
//    z = inner_z         underside of the lid
//
//  Print orientation (support-free):
//    main body:  standing on the lid, opening facing up
//    base plate: flat, inner side (clips) facing up
// ============================================================================

/* [Render] */
// "both" | "body" | "base" | "explosion"
part            = "both";
show_boards     = true;      // boards as ghosts (%) - not included in the STL

$fa = 4;
$fs = 0.35;
eps = 0.01;

// ============================================================================
//  1) PARAMETERS
// ============================================================================

/* [Enclosure basic dimensions] */
inner_x         = 134;    // inner width  (X)
inner_y         = 116;    // inner depth  (Y)
wall            = 2.4;    // wall thickness
base_thickness  = 2.4;    // thickness of the base plate
lid_thickness   = 2.4;    // thickness of the lid
corner_r        = 3.0;    // outer radius of the vertical edges
cable_clearance = 12;     // free height above the tallest assembly
height_override = 0;      // > 0 : set the inner height instead of computing it

/* [Fits] */
clearance       = 0.2;    // general fit clearance (lip, connector collar)
pcb_clearance   = 0.3;    // clearance of the boards in XY
pcb_clearance_z = 0.2;    // clearance below the snap hook
pcb_thickness   = 1.6;    // standard board thickness

/* [Closure base plate <-> main body] */
boss_d          = 8.0;    // outer diameter of the corner bosses
boss_offset     = 3.0;    // axis distance from the inner corner (X and Y)
insert_d        = 4.0;    // hole for the M3 heat-set insert
insert_l        = 6.0;    // insertion depth of the insert
insert_pilot_d  = 2.8;    // clearance hole below the insert
screw_d         = 3.4;    // M3 through hole in the base plate
countersink_d   = 6.2;    // head diameter DIN 7991 (6.0) + clearance
countersink_angle = 90;   // included head angle DIN 7991
countersink_lead = 0.3;   // short cylindrical lead-in at the outer surface:
                          // absorbs the elephant's foot of the first layer and
                          // keeps the head clear of the radius under the head

/* [Centering lip of the base plate] */
lip             = true;
lip_h           = 4.0;
lip_thickness   = 1.2;

/* [Stack light - measured: bolt circle 55 mm, 4 x M4, base 70 mm] */
light_base_d         = 70;    // MEASURED: outer diameter of the stack light base
light_bolt_circle_d  = 55;    // MEASURED
light_screw_n        = 4;     // MEASURED
light_angle_offset   = 45;    // angular position of the first screw [degrees]
light_screw_d        = 4.4;   // M4 through hole in the lid
light_cable_d        = 12;    // central cable feed-through
light_cable_chamfer  = 1.2;   // chamfer as edge protection
light_insert         = true;  // true: M4 heat-set bosses, false: through hole only
light_insert_d       = 5.6;
light_insert_l       = 8.0;
light_boss_d         = 9.0;
light_boss_l         = 10.0;  // length of the bosses below the lid
light_reinforcement  = 2.0;   // additional lid thickness around the flange
// Raised ring around the stack light base. DISABLED: the main body is printed
// standing on the lid, so the ring would be the only thing resting on the
// print bed - the whole remaining lid surface would have hung 1.2 mm in the
// air. The 4 M4 screws on the 55 mm bolt circle centre the flange anyway.
// Only enable if the body is printed differently.
light_centering_ring = false;
light_ring_h         = 1.2;
light_ring_width     = 2.0;

/* [Clip mounting of the boards] */
clip_w                = 6.0;    // width of a clip
clip_hook_h           = 1.6;    // height of the snap hook (also the lead-in chamfer)
clip_thickness_fixed  = 2.5;    // rigid support ledge
clip_hook_fixed       = 1.0;    // overhang of the rigid ledge
clip_thickness_spring = 1.6;    // springy clip
clip_hook_spring      = 0.8;    // overhang of the snap hook
stop_thickness        = 2.5;    // end stop against sliding
stop_above            = 1.0;    // height of the stop above the board top
pad_d                 = 6.0;    // side length of the support pads
pad_inset             = 5.0;    // distance of the pad centre from the board corner

// CONVENTION: all *_h are TOTAL HEIGHTS including the board (as measured with
// calipers across the whole module). *_standoff is the distance of the board
// underside from the parting plane.

/* [Board: 8-channel MOSFET module - measured 68 x 72 mm] */
mosfet_l        = 72;     // longer edge (X)
mosfet_w        = 68;     // shorter edge (Y) - the screw terminals sit here
mosfet_h        = 16;     // MEASURED: total height incl. board and screw terminals
mosfet_standoff = 3.0;
mosfet_pos      = [12, 42];   // terminal edges face the left/right side walls

/* [Board: ESP32-S3 DevKitC-1 N16R8 - MEASURED 57.3 x 28.1 x 1.6 mm] */
mcu_l            = 57.3;  // MEASURED: board length WITHOUT antenna overhang
mcu_w            = 28.1;  // MEASURED
mcu_h            = 5.0;   // total height incl. board (1.6 + 3.4 measured)
mcu_standoff     = 3.0;   // wires are fed into the solder eyes from above, so
                          // the solder joints protrude DOWNWARDS.
mcu_antenna      = 6.3;   // MEASURED: the module's antenna end overhangs the
                          // board edge. It sits at the height of the board
                          // top - the end stop below it must therefore not
                          // stick out above it (mcu_stop_above).
mcu_stop_above   = -0.2;  // 0.2 mm BELOW the board top. Exactly flush (0)
                          // would be ideal, but a tenth of print over-height
                          // would lift the front edge of the board. At -0.2
                          // the stop still engages 1.4 of the 1.6 mm edge.
mcu_pad_inset    = [8, 5];// Support pads further inwards in X than the default:
                          // the solder eyes sit along the long edges, and their
                          // solder joints would otherwise rest on the pads.
mcu_pos          = [90, inner_y - mcu_l];   // rotated by 90 degrees, USB side at
                          // the back wall, antenna pointing forward into the
                          // enclosure. x >= 90 keeps clear of the MOSFET end stop

// Both USB-C ports sit on the same short edge. Measured from the board edge
// that is on the RIGHT inside the enclosure (looking at the back wall from
// behind = from the USB side onto the board, it is the left one).
mcu_usb_edge     = 8.0;   // centre of the "USB" port (native) from the right edge
mcu_com_edge     = 19.5;  // centre of the "COM" port (UART)   from the right edge
mcu_usb_axis     = 1.65;  // axis height of the ports above the board top
mcu_usb_open_w   = 13.5;  // opening width per plug
mcu_usb_open_h   = 7.5;   // opening height

/* [Labels of the USB ports on the lid] */
mcu_text          = true;
mcu_text_size     = 4.5;
mcu_text_spread   = 1.6;  // The port centres are only 11.5 mm apart; at a
                          // legible font size "USB" and "COM" run into each
                          // other. The labels are therefore spread apart by
                          // this factor - left/right remains unambiguous, there
                          // are only two of them.
                          // 1.0 = exactly above the port centres.
mcu_text_depth    = 0.6;  // Engraving depth. The body is printed standing on
                          // the lid, so the text faces the print bed and comes
                          // out clean.
mcu_text_offset   = 4.0;  // centre of the text in front of the back wall's inner edge
mcu_text_rotation = 180;  // 180 = readable from behind, where you plug in
mcu_text_font     = "Liberation Sans:style=Bold";

/* [Board: Mini560 buck converter - MEASURED 30 x 18 x 6 mm] */
buck_l        = 30;       // longer edge
buck_w        = 18;       // shorter edge - the solder pads are here
buck_h        = 6;        // MEASURED: total height incl. board
buck_standoff = 3.0;      // room for the solder joints of the vias
buck_pos      = [100, 6];     // rotated by 90 degrees, front right zone
                              // -> clips grip the long edges, the solder pad
                              //    edges stay freely accessible

// Special case: front left support ledge (top view of the base plate, USB-C
// input at the bottom): a component sits flush with the left board edge, so
// the ledge cannot grip there. It therefore moves forward - but that is where
// the solder joint of the plus input is, so it also gets narrower.
// 0 / clip_w restores the symmetric default.
buck_clip_fl_shift = 3.0;     // forward (-Y)
buck_clip_fl_width = 4.0;     // instead of clip_w (6.0)

/* [Board: USB-C PD trigger board 31 x 20 mm] */
pd_w          = 20;       // edge WITH the USB-C port (at the front wall, X)
pd_l          = 31.5;     // MEASURED: edge without the port (reaching into the enclosure, Y)
pd_h          = 5.6;      // total height incl. board (1.6 board + 4.0 components)
pd_standoff   = 3.0;
pd_thickness  = 1.6;

/* [USB-C port] */
usbc_axis             = 1.65;  // axis height of the port above the board top
usbc_protrusion       = 1.0;   // MEASURED: protrusion of the port beyond the board edge
                               //           -> the port dips into the wall opening
usbc_open_w           = 13.5;  // wall opening width (plug housing + clearance)
usbc_open_h           = 7.5;   // wall opening height
usbc_recess_w         = 17.0;  // outer recess width
usbc_recess_d         = 1.2;   // outer recess depth -> the plug seats almost flush
usbc_recess_margin    = 1.5;   // recess reaches above the opening at the top
usbc_collar_clearance = 0.4;   // Fit of the connector collar. A value of its own
                               // instead of the general clearance: left and right
                               // of the opening, two wall tongues only 1.75 mm
                               // wide hang down and engage the notches between
                               // tongue and step. At 0.2 mm this was a press fit
                               // in print and had to be sanded.
usbc_saddle_d         = 5.0;   // depth of the saddle below the board's front edge
usbc_rib_thickness    = 3.0;   // stop rib behind the board (takes the plug-in forces)
usbc_rib_gap          = 10.0;  // central gap in it: the PD board's solder eyes sit
                               // at the back centre, the wires have to leave
                               // backwards there. 0 = continuous rib.

/* [Ventilation] */
vents       = true;
vent_n      = 6;          // slots per side wall
vent_w      = 3.0;        // width  (Y)
vent_h      = 16.0;       // height (Z)
vent_pitch  = 10.0;       // spacing
vent_z      = 16.0;       // centre height above the parting plane

// ============================================================================
//  2) DERIVED VALUES
// ============================================================================

outer_x = inner_x + 2*wall;
outer_y = inner_y + 2*wall;
inner_r = max(0.6, corner_r - wall);

mosfet_size = [mosfet_l, mosfet_w];     // terminals on the Y edges
mcu_size    = [mcu_w, mcu_l];           // rotated by 90 degrees
buck_size   = [buck_w, buck_l];         // rotated by 90 degrees
pd_size     = [pd_w, pd_l];
pd_pos      = [inner_x/2 - pd_w/2, 0];  // port exactly centred in the front wall

parts_height = max(mosfet_standoff + mosfet_h,
                   mcu_standoff + mcu_h,
                   buck_standoff + buck_h,
                   pd_standoff + max(pd_h, pd_thickness + 2*usbc_axis));

inner_z = height_override > 0
        ? height_override
        : parts_height + max(cable_clearance, light_boss_l + 2);

outer_z = base_thickness + inner_z + lid_thickness;

center_x = inner_x/2;
center_y = inner_y/2;

// USB-C
usbc_x           = pd_pos[0] + pd_w/2;
usbc_z           = pd_standoff + pd_thickness + usbc_axis;   // axis height above the parting plane
usbc_open_bottom = usbc_z - usbc_open_h/2;                   // lower edge of the opening
usbc_open_top    = usbc_z + usbc_open_h/2;                   // upper edge of the opening

// Longitudinal section through the front wall (y): -wall .. -wall+usbc_recess_d
// = recess, into which the port dips from the inside by usbc_protrusion.
usbc_face         = -usbc_protrusion;                // front face of the port
usbc_recess_floor = -wall + usbc_recess_d;           // floor of the outer recess
usbc_gap          = usbc_face - usbc_recess_floor;   // remaining wall in front of the port

// MCU USB ports
// The port centres are measured from the right board edge.
mcu_usb_x = mcu_pos[0] + mcu_w - mcu_usb_edge;
mcu_com_x = mcu_pos[0] + mcu_w - mcu_com_edge;
mcu_z     = mcu_standoff + pcb_thickness + mcu_usb_axis;
mcu_open_bottom = mcu_z - mcu_usb_open_h/2;
mcu_open_top    = mcu_z + mcu_usb_open_h/2;

// One shared opening for both ports instead of two separate windows: the web
// between them would be just over 1 mm wide and worthless in print.
mcu_open_left  = min(mcu_usb_x, mcu_com_x) - mcu_usb_open_w/2;
mcu_open_right = max(mcu_usb_x, mcu_com_x) + mcu_usb_open_w/2;
mcu_open_w     = mcu_open_right - mcu_open_left;

// Front edge of the antenna and top edge of the end stop below it
mcu_antenna_y = mcu_pos[1] - mcu_antenna;
mcu_pcb_top   = mcu_standoff + pcb_thickness;

// Effective ring height: added to the length of the lid holes so they pierce
// the ring - without a ring these would be unnecessary extra lengths.
ring_h_eff = light_centering_ring ? light_ring_h : 0;

// Countersink of the base screws: cone with countersink_angle, countersink_d
// wide at the outer surface, tapering to the through hole. The depth follows
// from the angle - do not set it separately, or the cone no longer matches
// the screw head.
cs_cone_d    = (countersink_d - screw_d)/2 / tan(countersink_angle/2);
cs_total_d   = countersink_lead + cs_cone_d;
cs_remaining = base_thickness - cs_total_d;   // material left below the countersink

// Corner bosses
boss_pos = [[boss_offset,           boss_offset],
            [inner_x - boss_offset, boss_offset],
            [boss_offset,           inner_y - boss_offset],
            [inner_x - boss_offset, inner_y - boss_offset]];

echo(str("Inner size  : ", inner_x, " x ", inner_y, " x ", inner_z, " mm"));
echo(str("Outer size  : ", outer_x, " x ", outer_y, " x ", outer_z, " mm",
         light_centering_ring ? str(" + ", light_ring_h, " mm centering ring") : " (flat lid)"));
echo(str("USB-C       : x=", usbc_x, "  axis z=", usbc_z,
         "  opening z ", usbc_open_bottom, " .. ", usbc_open_top));
echo(str("MCU         : ", mcu_w, " x ", mcu_l, " at x=", mcu_pos[0],
         " y=", mcu_pos[1], "  antenna to y=", mcu_antenna_y));
echo(str("MCU USB     : USB x=", mcu_usb_x, "  COM x=", mcu_com_x,
         "  opening x ", mcu_open_left, " .. ", mcu_open_right,
         " (", mcu_open_w, " mm)  axis z=", mcu_z));
// Spread-apart text centres
mcu_text_center = (mcu_usb_x + mcu_com_x) / 2;
mcu_text_usb_x  = mcu_text_center + (mcu_usb_x - mcu_text_center) * mcu_text_spread;
mcu_text_com_x  = mcu_text_center + (mcu_com_x - mcu_text_center) * mcu_text_spread;

// OpenSCAD cannot measure text width. 0.95 x size per character was measured
// on the rendered image for Liberation Sans Bold in capitals - the 0.62 used
// before was far too optimistic.
mcu_text_width = 3 * 0.95 * mcu_text_size;
mcu_text_gap   = abs(mcu_text_usb_x - mcu_text_com_x) - mcu_text_width;
echo(str("MCU text    : ~", mcu_text_width, " mm wide, text centres ",
         abs(mcu_text_usb_x - mcu_text_com_x), " apart  gap=", mcu_text_gap, " mm",
         (mcu_text_gap > 2) ? "  -> OK"
                            : "  -> too tight, increase mcu_text_spread or reduce the size!"));
echo(str("MCU stop    : top z=", mcu_pcb_top + mcu_stop_above,
         "  board top z=", mcu_pcb_top,
         "  engagement with the edge=", min(pcb_thickness, pcb_thickness + mcu_stop_above), " mm",
         (mcu_stop_above > 0)    ? "  -> sticks out, antenna COLLISION!" :
         (mcu_stop_above < -0.8) ? "  -> engagement getting thin"
                                 : "  -> OK, antenna clear"));
echo(str("USB-C port  : face y=", usbc_face, "  recess floor y=", usbc_recess_floor,
         "  remaining wall=", usbc_gap, " mm",
         (usbc_gap >= 0) ? "  -> OK" : "  -> recess cuts into the port!"));
echo(str("USB-C collar: tongue ", usbc_open_w - 2*usbc_collar_clearance, " in ", usbc_open_w,
         ", step ", usbc_recess_w - 2*usbc_collar_clearance, " in ", usbc_recess_w,
         "  notch clearance=", usbc_collar_clearance, " mm per flank",
         (usbc_collar_clearance >= 0.3) ? "  -> OK" : "  -> probably tight in print"));
echo(str("Buck ledge  : front left y=", buck_pos[1] + buck_size[1]*0.28 - buck_clip_fl_shift,
         " (", buck_clip_fl_width, " mm wide), back left y=",
         buck_pos[1] + buck_size[1]*0.72, "  margin to the board front edge=",
         buck_size[1]*0.28 - buck_clip_fl_shift - buck_clip_fl_width/2, " mm"));
echo(str("PD rib      : 2 x ", (pd_w + 4 - usbc_rib_gap)/2,
         " mm wide, gap ", usbc_rib_gap, " mm centred for the solder eyes",
         ((pd_w + 4 - usbc_rib_gap)/2 >= 4) ? "  -> OK" : "  -> segments too narrow!"));
echo(str("Countersink : ", countersink_angle, " degrees, depth ", cs_total_d,
         " mm  remaining floor=", cs_remaining, " mm",
         (cs_remaining >= 0.6) ? "  -> OK" : "  -> too thin, increase base_thickness!"));
echo(str("Light bosses: bottom z=", inner_z - light_boss_l,
         "  tallest assembly z=", parts_height,
         (inner_z - light_boss_l >= parts_height) ? "  -> OK" : "  -> COLLISION!"));

// ============================================================================
//  3) HELPER MODULES
// ============================================================================

// 2D rectangle with rounded corners, origin at the lower left corner
module rr2d(sx, sy, r) {
    translate([r, r]) offset(r = r) square([sx - 2*r, sy - 2*r]);
}

// Prism along X: the 2D polygon lies in the (y,z) plane, x = 0 .. width
module prism_x(width, pts) {
    rotate([90, 0, 90]) linear_extrude(height = width) polygon(points = pts);
}

// Clip: the board edge is at y = 0, the board itself at y > 0.
// The hook reaches over the board by hook_over, its top is a 45-degree
// chamfer (lead-in when pressing the board in).
module clip(h_below, thickness, hook_over, width = clip_w) {
    hb = h_below + pcb_thickness + pcb_clearance_z;    // lower edge of the snap hook
    translate([-width/2, -thickness, 0])
        cube([width, thickness, hb + clip_hook_h]);
    translate([-width/2, 0, 0])
        prism_x(width, [[0, hb], [hook_over, hb], [0, hb + clip_hook_h]]);
}

// End stop without a hook. above = height above the board top; 0 makes it
// flush, needed when a component overhangs the edge.
module end_stop(width, h_below, thickness, above = undef) {
    a = is_undef(above) ? stop_above : above;
    translate([-width/2, -thickness, 0])
        cube([width, thickness, h_below + pcb_thickness + a]);
}

// Places children() at a board edge (local: edge at y=0, board at y>0)
module at_edge(pos, size, side, along) {
    px = pos[0]; py = pos[1]; sx = size[0]; sy = size[1]; s = pcb_clearance/2;
    if (side == "front")
        translate([px + along, py - s, 0]) children();
    if (side == "back")
        translate([px + along, py + sy + s, 0]) rotate([0, 0, 180]) children();
    if (side == "left")
        translate([px - s, py + along, 0]) rotate([0, 0, -90]) children();
    if (side == "right")
        translate([px + sx + s, py + along, 0]) rotate([0, 0, 90]) children();
}

// Support pads under the board corners - keep solder joints off the floor.
// inset: distance of the pad centre from the board corner. A number = both
// axes, [x, y] = separately. Separate is needed when the solder eyes only sit
// on one pair of edges: then the pads only move inwards along that axis and
// the support stays as wide as possible along the other.
module pcb_pads(pos, size, h_below, inset = undef) {
    px = pos[0]; py = pos[1]; sx = size[0]; sy = size[1];
    v  = is_undef(inset) ? [pad_inset, pad_inset]
       : is_list(inset)  ? inset : [inset, inset];
    for (dx = [v[0], sx - v[0]], dy = [v[1], sy - v[1]])
        translate([px + dx - pad_d/2, py + dy - pad_d/2, 0])
            cube([pad_d, pad_d, h_below]);
}

// Complete screwless mounting of a board:
// rigid support ledges on one side, springy snap clips on the opposite side.
//   clip_axis    : "x" -> clips on the left/right edge
//                  "y" -> clips on the front/back edge
//   stops        : list of edges that get an end stop
//   clips_fixed / clips_spring : optional list [[position, width], ...]
//     per clip, position measured along the edge. Empty = default, i.e. two
//     clips at 28 % and 72 % of the edge length, clip_w wide.
//     This allows individual clips to be placed around components without
//     giving up the symmetry for all other boards.
//   stop_height  : height of the end stops, undef = stop_above
//   pad_inset_xy : see pcb_pads()
module board_holder(pos, size, h_below, clip_axis = "x", stops = [],
                    clips_fixed = [], clips_spring = [],
                    stop_height = undef, pad_inset_xy = undef) {
    sx = size[0]; sy = size[1];
    pcb_pads(pos, size, h_below, pad_inset_xy);

    edge = (clip_axis == "x") ? sy : sx;
    std  = [[edge*0.28, clip_w], [edge*0.72, clip_w]];
    cf   = (len(clips_fixed)  > 0) ? clips_fixed  : std;
    cs   = (len(clips_spring) > 0) ? clips_spring : std;

    s_fixed  = (clip_axis == "x") ? "left"  : "front";
    s_spring = (clip_axis == "x") ? "right" : "back";

    for (c = cf)
        at_edge(pos, size, s_fixed,  c[0]) clip(h_below, clip_thickness_fixed,  clip_hook_fixed,  c[1]);
    for (c = cs)
        at_edge(pos, size, s_spring, c[0]) clip(h_below, clip_thickness_spring, clip_hook_spring, c[1]);

    for (s = stops) {
        length = (s == "front" || s == "back") ? sx : sy;
        at_edge(pos, size, s, length/2)
            end_stop(length*0.5, h_below, stop_thickness, stop_height);
    }
}

// Board ghost for collision checks (% = not in the render/STL)
module board_ghost(pos, size, h_below, h_part, thickness = 1.6) {
    %translate([pos[0], pos[1], h_below]) {
        color("green")   cube([size[0], size[1], thickness]);
        // h_part is the total height -> the components are lower by the board
        translate([0, 0, thickness])
            color("dimgray") cube([size[0], size[1], max(h_part - thickness, 0.1)]);
    }
}

// ============================================================================
//  4) CUTOUTS (wall openings)
// ============================================================================

// USB-C: opening that is open towards the bottom, so the fully populated base
// assembly can be slid in vertically from below.
module usbc_cutout() {
    translate([usbc_x - usbc_open_w/2, -wall - 1, -eps])
        cube([usbc_open_w, wall + 2, usbc_open_top + eps]);
    if (usbc_recess_d > 0)
        translate([usbc_x - usbc_recess_w/2, -wall - eps, -eps])
            cube([usbc_recess_w, usbc_recess_d + eps, usbc_open_top + usbc_recess_margin + eps]);
}

// Both USB-C ports of the MCU in the back wall - one shared window, also open
// towards the bottom so the populated base plate can slide in.
module mcu_usb_cutout() {
    translate([mcu_open_left, inner_y - 1, -eps])
        cube([mcu_open_w, wall + 2, mcu_open_top + eps]);
}

// Engraved labels of the two ports on the outside of the lid
module mcu_labels() {
    if (mcu_text)
        for (b = [["USB", mcu_text_usb_x], ["COM", mcu_text_com_x]])
            translate([b[1], inner_y - mcu_text_offset,
                       inner_z + lid_thickness - mcu_text_depth])
                rotate([0, 0, mcu_text_rotation])
                    linear_extrude(height = mcu_text_depth + eps)
                        text(b[0], size = mcu_text_size, halign = "center",
                             valign = "center", font = mcu_text_font);
}

module vent_cutouts() {
    if (vents)
        for (side = [0, 1])
            for (i = [0 : vent_n - 1]) {
                y = center_y + (i - (vent_n - 1)/2) * vent_pitch;
                x = (side == 0) ? -wall - 1 : inner_x - 1;
                translate([x, y, vent_z])
                    rotate([0, 90, 0])
                        linear_extrude(height = wall + 2)
                            offset(r = vent_w/2)
                                square([vent_h - vent_w, 0.01], center = true);
            }
}

// ============================================================================
//  5) MAIN BODY (walls + lid)
// ============================================================================

module shell() {
    difference() {
        translate([-wall, -wall, 0])
            linear_extrude(height = inner_z + lid_thickness)
                rr2d(outer_x, outer_y, corner_r);
        translate([0, 0, -eps])
            linear_extrude(height = inner_z + eps)
                rr2d(inner_x, inner_y, inner_r);
    }
}

module corner_bosses() {
    for (p = boss_pos)
        translate([p[0], p[1], 0]) cylinder(h = inner_z, d = boss_d);
}

module corner_boss_holes() {
    for (p = boss_pos)
        translate([p[0], p[1], -eps]) {
            cylinder(h = insert_l + eps, d = insert_d);
            cylinder(h = insert_l + 4, d = insert_pilot_d);
        }
}

module light_screw_positions() {
    r = light_bolt_circle_d/2;
    for (i = [0 : light_screw_n - 1]) {
        a = light_angle_offset + i * 360/light_screw_n;
        translate([center_x + r*cos(a), center_y + r*sin(a), 0]) children();
    }
}

module lid_additions() {
    // local reinforcement around the flange (inside of the lid)
    translate([center_x, center_y, inner_z - light_reinforcement])
        cylinder(h = light_reinforcement, d = light_base_d + 10);

    // insert bosses for the flange screws
    if (light_insert)
        light_screw_positions()
            translate([0, 0, inner_z - light_boss_l])
                cylinder(h = light_boss_l, d = light_boss_d);

    // centering ring on the outside, takes the stack light base
    // (dips 0.5 mm into the lid - avoids coincident faces)
    if (light_centering_ring)
        translate([center_x, center_y, inner_z + lid_thickness - 0.5])
            difference() {
                cylinder(h = light_ring_h + 0.5,
                         d = light_base_d + 2*clearance + 2*light_ring_width);
                translate([0, 0, -eps])
                    cylinder(h = light_ring_h + 0.5 + 2*eps, d = light_base_d + 2*clearance);
            }
}

module lid_cutouts() {
    top = inner_z + lid_thickness;   // outer lid surface - the top without a ring

    // central cable feed-through with a chamfer on both sides
    translate([center_x, center_y, inner_z - light_reinforcement - 1])
        cylinder(h = lid_thickness + light_reinforcement + 2 + ring_h_eff,
                 d = light_cable_d);
    translate([center_x, center_y, top - light_cable_chamfer])
        cylinder(h = light_cable_chamfer + eps,
                 d1 = light_cable_d, d2 = light_cable_d + 2*light_cable_chamfer);
    translate([center_x, center_y, inner_z - light_reinforcement - eps])
        cylinder(h = light_cable_chamfer + eps,
                 d1 = light_cable_d + 2*light_cable_chamfer, d2 = light_cable_d);

    // flange screws: through hole from above, the insert below
    light_screw_positions() {
        translate([0, 0, inner_z - light_boss_l - 1])
            cylinder(h = light_boss_l + lid_thickness + ring_h_eff + 2,
                     d = light_screw_d);
        if (light_insert)
            translate([0, 0, inner_z - light_boss_l - eps])
                cylinder(h = light_insert_l + eps, d = light_insert_d);
    }
}

module main_body() {
    difference() {
        union() {
            shell();
            corner_bosses();
            lid_additions();
        }
        corner_boss_holes();
        lid_cutouts();
        usbc_cutout();
        mcu_usb_cutout();
        mcu_labels();
        vent_cutouts();
    }
}

// ============================================================================
//  6) BASE PLATE (plate + board mounting + connector collar)
// ============================================================================

// The connector collar fills the wall slot that is open towards the bottom and
// forms the lower edge of the connector opening. It surrounds the USB-C port
// and routes the plug-in forces through the base plate into the screws - not
// into the port's solder joints.
module usbc_collar() {
    f = usbc_collar_clearance;
    // tongue in the opening
    translate([usbc_x - (usbc_open_w - 2*f)/2, -wall + usbc_recess_d, 0])
        cube([usbc_open_w - 2*f, wall - usbc_recess_d, usbc_open_bottom]);
    // step in the outer recess
    if (usbc_recess_d > 0)
        translate([usbc_x - (usbc_recess_w - 2*f)/2, -wall, 0])
            cube([usbc_recess_w - 2*f, usbc_recess_d, usbc_open_bottom]);
    // saddle below the board's front edge: carries port and board
    translate([usbc_x - pd_w/2, 0, 0])
        cube([pd_w, usbc_saddle_d, pd_standoff]);
}

module mcu_usb_filler() {
    f = usbc_collar_clearance;
    translate([mcu_open_left + f, inner_y, 0])
        cube([mcu_open_w - 2*f, wall, mcu_open_bottom]);
}

// Stop rib behind the PD board - takes the plug-in forces through the board
// edge, not through the port's solder pads.
// Two segments instead of one continuous rib - the centre stays free for the
// wires at the solder eyes. The plug-in force therefore goes through the two
// back board corners instead of the middle. That actually suits the board
// better: it is no longer loaded in bending.
module pd_stop_rib() {
    total  = pd_w + 4;
    seg    = max((total - usbc_rib_gap) / 2, 0.01);
    height = pd_standoff + pd_thickness + stop_above;
    y      = pd_pos[1] + pd_l + pcb_clearance/2;
    for (x = [pd_pos[0] - 2, pd_pos[0] - 2 + total - seg])
        translate([x, y, 0]) cube([seg, usbc_rib_thickness, height]);
}

// Screw hole of the base plate: through hole + conical countersink from
// outside. z = -base_thickness is the outer surface; the plate is printed with
// this surface on the print bed - the 45-degree cone is self-supporting.
module countersunk_hole() {
    translate([0, 0, -base_thickness - 1])
        cylinder(h = base_thickness + 2, d = screw_d);
    if (countersink_lead > 0)
        translate([0, 0, -base_thickness - eps])
            cylinder(h = countersink_lead + eps, d = countersink_d);
    translate([0, 0, -base_thickness + countersink_lead])
        cylinder(h = cs_cone_d, d1 = countersink_d, d2 = screw_d);
}

module lip_body() {
    linear_extrude(height = lip_h)
        difference() {
            offset(delta = -clearance)                 rr2d(inner_x, inner_y, inner_r);
            offset(delta = -clearance - lip_thickness) rr2d(inner_x, inner_y, inner_r);
        }
}

module lip_cutouts() {
    // clear the corner bosses
    for (p = boss_pos)
        translate([p[0], p[1], -eps])
            cylinder(h = lip_h + 2*eps, d = boss_d + 2*clearance);
    // gap in front of the PD board (front wall)
    translate([pd_pos[0] - 4, -1, -eps])
        cube([pd_w + 8, lip_thickness + clearance + 2, lip_h + 2*eps]);
    // gap behind the MCU (back wall)
    translate([mcu_pos[0] - 4, inner_y - lip_thickness - clearance - 1, -eps])
        cube([mcu_size[0] + 8, lip_thickness + clearance + 2, lip_h + 2*eps]);
}

module board_holders() {
    // MOSFET: terminal edges at the sides -> clips front/back, stops at the sides
    board_holder(mosfet_pos, mosfet_size, mosfet_standoff, "y", ["left", "right"]);
    // MCU: the back edge rests against the wall -> only one stop at the front,
    // and it must stay flush with the board top (antenna overhang).
    board_holder(mcu_pos, mcu_size, mcu_standoff, "x", ["front"],
                 stop_height  = mcu_stop_above,
                 pad_inset_xy = mcu_pad_inset);
    // Buck converter: front left ledge shifted and narrower, see parameters
    board_holder(buck_pos, buck_size, buck_standoff, "x", ["front", "back"],
                 clips_fixed = [[buck_size[1]*0.28 - buck_clip_fl_shift, buck_clip_fl_width],
                                [buck_size[1]*0.72, clip_w]]);
    // PD board: the front edge rests against the front wall, the rib at the back
    board_holder(pd_pos, pd_size, pd_standoff, "x", []);
}

module base_plate() {
    difference() {
        union() {
            translate([-wall, -wall, -base_thickness])
                linear_extrude(height = base_thickness)
                    rr2d(outer_x, outer_y, corner_r);
            if (lip)
                difference() { lip_body(); lip_cutouts(); }
            board_holders();
            usbc_collar();
            mcu_usb_filler();
            pd_stop_rib();
        }
        // screws with a conical countersink from below
        for (p = boss_pos)
            translate([p[0], p[1], 0]) countersunk_hole();
    }
}

// ============================================================================
//  7) GHOST BOARDS
// ============================================================================

module boards() {
    if (show_boards) {
        board_ghost(mosfet_pos, mosfet_size, mosfet_standoff, mosfet_h);
        board_ghost(mcu_pos,    mcu_size,    mcu_standoff,    mcu_h);
        // overhanging antenna end of the module
        %translate([mcu_pos[0], mcu_antenna_y, mcu_pcb_top])
            color("darkgreen") cube([mcu_w, mcu_antenna, 1.0]);
        board_ghost(buck_pos,   buck_size,   buck_standoff,   buck_h);
        board_ghost(pd_pos,     pd_size,     pd_standoff,     pd_h, pd_thickness);
    }
}

// ============================================================================
//  8) RENDER SELECTION
// ============================================================================

if (part == "body") {
    main_body();
} else if (part == "base") {
    base_plate();
} else if (part == "explosion") {
    translate([0, 0, 45]) main_body();
    base_plate();
    boards();
} else {
    color("gainsboro", 0.30) main_body();
    color("steelblue")       base_plate();
    boards();
}
