#!/usr/bin/env python3
# NOQ Purser r1b case: white tray + shell, screwless (seven cantilever snap hooks), heat-stake pins, light through a thinned top.
# x: left -> right (RTC | Orange Pi | SSD), y: front (ports) -> back, z: up. Origin: outer front-left-bottom corner.
import cadquery as cq, svgelements as se, json, sys
from shapely.geometry import Polygon
from shapely.ops import unary_union

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

# ---- given measurements (OLCULER.md) ----
OPI = (55.0, 50.0, 1.2); OPI_HOLES = (49.5, 45.0)
RTC = (38.0, 21.7, 1.6)
SSD = (59.0, 59.6)                      # SSD + bridge mated footprint
# NeoPixel 8 stick — Umut's own stick (clones differ from Adafruit's layout, so his measurements rule):
# 51.3 x 9.6 mm; the two holes are 25 mm apart (centre to centre), in a 4 mm band along the DIN-side long edge
# (hole centres 2 mm in from that edge); the LEDs fill the other 5.6 mm. The LED row is centred under the window.
STICK = (51.3, 9.6, 1.6); STICK_HOLES = 25.0; STICK_PIN_D = 1.8   # 1.8 mm pin goes through any hole from 2 mm up
STICK_BAND = 4.0
LED_OFF = STICK[1] / 2 - (STICK[1] - STICK_BAND) / 2   # LED row centre is this far in front of the stick centre
HOLE_OFF = STICK[1] / 2 - STICK_BAND / 2              # hole line is this far behind the stick centre
SW_BODY = (22.0, 17.5, 8.5)             # into the box (x), along y, along z
SW_BUSH = 6.0

# ---- case ----
WALL, FLOOR, TOP = 2.5, 2.0, 2.0
LIP_H, LIP_T, CLR = 4.0, 1.4, 0.15
R_PLAN, R_EDGE = 12.0, 5.0
GAP = 3.0
X_RTC = 5.5                              # clear of the rounded inner corner
X_OPI = X_RTC + RTC[0] + GAP
X_SSD = X_OPI + OPI[0] + GAP
IN_X = X_SSD + SSD[0] + 7.0
IN_Y = SSD[1] + 2 * (CLR + 1.4 + 0.6)   # clear of the tray lip
IN_Z = 23.0
OX, OY, OZ = IN_X + 2 * WALL, IN_Y + 2 * WALL, IN_Z + FLOOR + TOP
SPLIT = 6.0                              # tray / shell seam, outer z
STAND = 4.0                              # standoff height for every board on the floor
PIN_D, PIN_OUT, BOSS_D = 2.3, 2.5, 5.5
SKIN = 0.8                               # top thickness over the light
STICK_GAP = 4.0                          # skin underside to stick PCB top

def P(x, y):                             # inner coords -> outer coords
    return (x + WALL, y + WALL)

z0 = FLOOR                               # inner floor
zb = z0 + STAND                          # board bottom
Y_OPI = 1.8                              # board edge to the front wall's inner face (r1b: was 0.5; micro HDMI nose 0.75 now clears)
OPI_C = P(X_OPI + OPI[0] / 2, Y_OPI + OPI[1] / 2)

def rrect(w, h, r, z, height, cx, cy):
    return cq.Workplane().box(w, h, height, centered=(True, True, False)).edges('|Z').fillet(r).translate((cx, cy, z))

outer = cq.Workplane().box(OX, OY, OZ, centered=False).edges('|Z').fillet(R_PLAN).faces('>Z or <Z').edges().fillet(R_EDGE)
inner = (cq.Workplane().box(IN_X, IN_Y, IN_Z, centered=False).edges('|Z').fillet(R_PLAN - WALL)
         .faces('>Z').edges().fillet(R_EDGE - TOP).translate((WALL, WALL, FLOOR)))
body = outer.cut(inner)

# ---- Orange Pi Zero 3 front connectors (hand-measured CAD model, MotorBottle/OrangePi-Zero3-CAD-3D-Model, < 0.3 mm):
#      USB-C and USB-A stand UPRIGHT. (x0, x1) from the board centre, (z0, z1) above the board's top face, nose past the board edge.
top_pcb = zb + OPI[2]
PORTS = {'hdmi': ((-21.3, -14.8), (0.18, 3.12), 0.75), 'usbc': ((-9.45, -6.25), (0.70, 9.62), 0.7), 'usba': ((-1.5, 4.3), (0.5, 13.7), 1.1), 'rj45': ((6.5, 21.5), (0.0, 13.5), 0.6)}
# openings: USB-C with room for the plug's overmould (about 7 x 12 upright), USB-A and RJ45 with 0.4 mm around.
# They run down to the seam: the connector noses reach into the wall, so the shell must slide down over them.
# USB-C: a stadium (rounded top) 9.4 wide, for an upright plug overmould up to about 9 x 12.5 mm; 1.25 mm of wall to USB-A.
SLOTS = {'usbc': (-12.55, -3.15, 11.96), 'usba': (-1.9, 4.7, 14.1), 'rj45': (6.1, 21.9, 13.9)}
ROUND = {'usbc': 4.69}
def slot(x0, x1, top, r=0.8):
    return (cq.Workplane('XZ').center(OPI_C[0] + (x0 + x1) / 2, (SPLIT - 2 + top_pcb + top) / 2).rect(x1 - x0, top_pcb + top - SPLIT + 2)
            .extrude(-(WALL + 1.5)).edges('|Y').fillet(r).translate((0, -0.5, 0)))

# ---- maintenance switch, left wall: bushing hole, ring seat (1 mm deep: the ring's thread reaches the bushing) ----
SW_Y, SW_Z = WALL + 20.0, 14.6
sw_hole = cq.Workplane('YZ').center(SW_Y, SW_Z).circle(SW_BUSH / 2 + 0.15).extrude(WALL + 2).translate((-1, 0, 0))
SEAT = 1.0
seat = cq.Workplane('YZ').center(SW_Y, SW_Z).circle(12.4 / 2).extrude(SEAT + 1).translate((-1, 0, 0))
body = body.cut(sw_hole).cut(seat)

# ---- split ----
big = 400
tray = body.intersect(cq.Workplane().box(big, big, SPLIT, centered=(True, True, False)).translate((OX / 2, OY / 2, 0)))
shell = body.intersect(cq.Workplane().box(big, big, OZ, centered=(True, True, False)).translate((OX / 2, OY / 2, SPLIT)))
for _n, (_a, _b, _t) in SLOTS.items():
    if _n == 'usbc':
        continue
    shell = shell.cut(slot(_a, _b, _t, ROUND.get(_n, 0.8)))
# USB-C (r1b): a full stadium, round at both ends (Umut). With the board 1.8 mm off the wall the connector no longer reaches
# into the wall, so the opening need not run down to the seam; it is centred on the connector and sized for an upright
# plug overmould up to about 9 x 12.5 mm. Its lowest 0.3 mm falls below the seam, so the tray's wall is cut too.
_c0, _c1 = PORTS['usbc'][0]; _cz0, _cz1 = PORTS['usbc'][1]
USBC_W, USBC_H = 9.4, 13.4
usbc_cut = (cq.Workplane('XZ').center(OPI_C[0] + (_c0 + _c1) / 2, top_pcb + (_cz0 + _cz1) / 2)
            .slot2D(USBC_H, USBC_W, 90).extrude(-(WALL + 1.5)).translate((0, -0.5, 0)))
shell = shell.cut(usbc_cut)
# micro HDMI stays closed (not used); with the board 1.8 mm off the wall its 0.75 mm nose clears the wall by about 1 mm

# tray lip (goes up inside the shell), cut away behind the Orange Pi's ports
lo = rrect(IN_X - 2 * CLR, IN_Y - 2 * CLR, R_PLAN - WALL - CLR, SPLIT, LIP_H, OX / 2, OY / 2)
li = rrect(IN_X - 2 * (CLR + LIP_T), IN_Y - 2 * (CLR + LIP_T), R_PLAN - WALL - CLR - LIP_T, SPLIT - 1, LIP_H + 2, OX / 2, OY / 2)
lip = lo.cut(li).cut(cq.Workplane().box(OPI[0] + 3, 6, 20, centered=(True, False, False)).translate((OPI_C[0], 0, SPLIT - 1)))
tray = tray.union(lip)
tray = tray.cut(usbc_cut)                 # the USB-C stadium's lowest part

# ---- snap hooks (r1b; the r1 lip ridges did not hold) ----
# Seven cantilever hooks stand up from the tray floor along the walls, flex inward and catch a pocket in the shell wall.
# Beam 1.6 thick, 9 wide, free 11 mm above the seam (PETG strain ~1.6 % at 0.8 mm deflection); root fused to the tray
# wall from the floor up, with a fillet. Hook: 1.0 mm out, 30 deg lead-in on top, 45 deg catch underneath (prints without
# support; a firm pull opens it). The lip stays for alignment only and is cut away around each hook.
HK_T, HK_W, HK_L, HK_OUT, HK_GAP = 1.6, 9.0, 11.0, 1.0, 0.2
HK_TOP = SPLIT + HK_L
# (along-wall position measured in inner coords, wall): kept on straight wall runs, clear of ports, switch, RTC and SSD
HOOKS = [(20.0, 'f'), (36.0, 'f'), (58.0, 'b'), (90.0, 'b'), (46.0, 'l'), (18.0, 'r'), (46.0, 'r')]
def hook_parts(pos, wall):
    # build for the front wall (outward = -y), then place
    T = HK_TOP
    # beam profile (local y = outward negative): 45 deg catch, short flat, ~29 deg lead-in up to the tip
    prof = (cq.Workplane('YZ').polyline([(0, z0), (0, T - 3.6), (-HK_OUT, T - 2.6), (-HK_OUT, T - 2.1),
                                          (0, T - 0.3), (0, T), (HK_T, T), (HK_T, z0)]).close().extrude(HK_W)
            .translate((-HK_W / 2, 0, 0)))
    root = cq.Workplane().box(HK_W, HK_GAP + 0.01, SPLIT - z0, centered=(True, False, False)).translate((0, -HK_GAP - 0.01, z0))
    beam = prof.union(root).translate((0, HK_GAP, 0))                                      # beam outer face 0.2 off the wall
    slot = cq.Workplane().box(HK_W + 2.0, HK_T + HK_GAP + 0.6, LIP_H + 1, centered=(True, False, False)).translate((0, -0.1, SPLIT - 0.5))
    # pocket in the shell wall (wall face at local y = 0): catch face 0.1 below the hook's, 45 deg roof (prints inverted)
    pocket = (cq.Workplane('YZ').polyline([(0.3, T - 3.8), (-1.2, T - 2.3), (-1.2, T - 1.6), (0.3, T - 0.1)]).close()
              .extrude(HK_W + 0.8).translate((-(HK_W + 0.8) / 2, 0, 0)))
    if wall == 'f':
        m = lambda s: s.translate((WALL + pos, WALL, 0))
    elif wall == 'b':
        m = lambda s: s.mirror('XZ').translate((WALL + pos, OY - WALL, 0))
    elif wall == 'l':
        m = lambda s: s.rotate((0, 0, 0), (0, 0, 1), -90).translate((WALL, WALL + pos, 0))
    else:
        m = lambda s: s.rotate((0, 0, 0), (0, 0, 1), 90).translate((OX - WALL, WALL + pos, 0))
    return m(beam), m(slot), m(pocket)
for _p, _w in HOOKS:
    _beam, _slot, _pocket = hook_parts(_p, _w)
    tray = tray.cut(_slot).union(_beam)
    shell = shell.cut(_pocket)
# finger notch at the seam, right end, to lift the shell
shell = shell.cut(cq.Workplane('YZ').center(OY / 2, SPLIT).ellipse(9, 2.2).extrude(4).translate((OX - 3, 0, 0)))

# ---- floor: standoffs + heat-stake pins ----
def stake(x, y, z, h, pcb, down=False):
    boss = cq.Workplane().circle(BOSS_D / 2).extrude(h)
    pin = cq.Workplane().circle(PIN_D / 2).extrude(pcb + PIN_OUT).edges('>Z').chamfer(0.3).translate((0, 0, h))
    s = boss.union(pin)
    if down:
        s = s.mirror('XY')
    return s.translate((x, y, z))

for sx in (-1, 1):
    for sy in (-1, 1):
        tray = tray.union(stake(OPI_C[0] + sx * OPI_HOLES[0] / 2, OPI_C[1] + sy * OPI_HOLES[1] / 2, z0 - 0.01, STAND, OPI[2]))

# RTC (HW-084 / ZS-042), battery up, 6-pin edge to the left, at the back of the left bay
rx, ry = P(X_RTC, IN_Y - 2.3 - RTC[1])
RTC_HOLES = [(8.5, RTC[1] - 2.1), (8.5, 2.1), (8.5 + 25.5, 2.1)]   # r1b: the single far hole is on the front edge (Umut)
for hx, hy in RTC_HOLES:
    tray = tray.union(stake(rx + hx, ry + hy, z0 - 0.01, STAND, RTC[2]))

# SSD + bridge: four corner guides (no holes given)
sx0, sy0 = P(X_SSD, (IN_Y - SSD[1]) / 2)
for cx, cy, dx, dy in ((sx0, sy0, 1, 1), (sx0 + SSD[0], sy0, -1, 1), (sx0, sy0 + SSD[1], 1, -1), (sx0 + SSD[0], sy0 + SSD[1], -1, -1)):
    # one solid L per corner (two overlapping bars from the outer corner; bars that only touch at an edge are non-manifold)
    qx, qy = cx - 1.6 * dx, cy - 1.6 * dy
    a = cq.Workplane().box(9.2, 1.2, 6, centered=False).translate((qx if dx > 0 else qx - 9.2, qy if dy > 0 else qy - 1.2, z0 - 0.01))
    b = cq.Workplane().box(1.2, 9.2, 6, centered=False).translate((qx if dx > 0 else qx - 1.2, qy if dy > 0 else qy - 9.2, z0 - 0.01))
    tray = tray.union(a.union(b))

# floor vents under the Orange Pi
for i in range(-3, 4):
    tray = tray.cut(cq.Workplane().center(OPI_C[0] + i * 5.0, OPI_C[1]).slot2D(30, 1.8, 90).extrude(FLOOR + 2).translate((0, 0, -1)))

# ---- top: thinned window over the light stick, hanging stakes, logo ----
SC = (OX / 2, OY / 2)                     # LED row centre = box centre
STICK_C = SC[1] + LED_OFF                 # stick centre (y): behind the LED row
win = rrect(STICK[0] + 3, STICK[1] + 2, 1.0, OZ - TOP - 1, TOP - SKIN + 1, SC[0], SC[1])
shell = shell.cut(win)
z_skin = OZ - SKIN
# the stick hangs on two pins; two thin rails on its PCB margins (outside the LEDs) set the gap
for s in (-1, 1):
    # boss (sets the 4 mm gap; fits the LED-free band) + pin through the hole
    hx, hy = SC[0] + s * STICK_HOLES / 2, STICK_C + HOLE_OFF
    boss = cq.Workplane().circle(3.2 / 2).extrude(STICK_GAP)   # clear of the LEDs (row edge 1.8 mm away) and the board edge
    shell = shell.union(boss.translate((hx, hy, z_skin - STICK_GAP + 0.01)))
    pin = cq.Workplane().circle(STICK_PIN_D / 2).extrude(STICK[2] + PIN_OUT + 0.5).edges('<Z').chamfer(0.3)
    shell = shell.union(pin.translate((hx, hy, z_skin - STICK_GAP - STICK[2] - PIN_OUT + 0.01)))

# logo, engraved 0.6 mm on the top, right half
svg = se.SVG.parse(__import__('os').path.join(__import__('os').path.dirname(__file__), 'purser.svg'))
polys = []
for e in svg.elements():
    if isinstance(e, se.Path):
        for sp in e.as_subpaths():
            import numpy as np
            pts = [tuple(p) for p in se.Path(sp).npoint(np.linspace(0, 1, 801))]
            pg = Polygon(pts).buffer(0)
            if pg.area > 50:
                polys.append(pg)
logo = unary_union(polys)
minx, miny, maxx, maxy = logo.bounds
LOGO_W = 32.0; k = LOGO_W / (maxx - minx)
LC = (OX - 34.0, OY / 2)
geoms = list(logo.geoms) if hasattr(logo, 'geoms') else [logo]
cutter = None
for g in geoms:
    ext = [((x - (minx + maxx) / 2) * k + LC[0], -(y - (miny + maxy) / 2) * k + LC[1]) for x, y in g.exterior.coords]
    w = cq.Workplane().polyline(ext[:-1]).close()
    for ring in g.interiors:
        w = w.polyline([((x - (minx + maxx) / 2) * k + LC[0], -(y - (miny + maxy) / 2) * k + LC[1]) for x, y in ring.coords][:-1]).close()
    sol = w.extrude(2).translate((0, 0, OZ - 0.6))
    cutter = sol if cutter is None else cutter.union(sol)
shell = shell.cut(cutter)

# ---- switch ring (separate colour): 6 high cone, 12 -> 10.5, screwed straight onto the switch bushing ----
RH, RD0, RD1 = 6.0, 12.0, 10.5
ring = cq.Workplane().circle(RD0 / 2).workplane(offset=RH).circle(RD1 / 2).loft()
ring = ring.faces('>Z').edges().fillet(0.6)
# r1b (Umut: no nut underneath; it must grip from the very bottom): no nut pocket, no plain bore. One straight hole,
# 5.6 mm, all the way up: the switch's metal bushing thread (M6 x 0.75 or 1/4"-40, both fit) cuts its own thread into
# the PETG from the first turn. A 0.5 mm lead-in chamfer at the bottom starts it straight.
ring = ring.cut(cq.Workplane().circle(5.6 / 2).extrude(RH + 1).translate((0, 0, -0.5)))
ring = ring.cut(cq.Workplane().circle(5.6 / 2 + 0.5).workplane(offset=0.5).circle(5.6 / 2).loft().translate((0, 0, -0.001)))
# placed: bottom on the 1 mm seat, axis out of the left wall
ring_placed = ring.rotate((0, 0, 0), (0, 1, 0), -90).translate((SEAT, SW_Y, SW_Z))

# ---- USB-A dust plug (r1b): goes INTO the USB-A socket, independent of the case (r1's case-pressed plug did not close).
#      A plate fills the gap between the socket's tongue and its shell (where a USB plug's contact block goes); the socket's
#      spring tabs hold it. Fits either way round (turn it 180 deg if the tongue is on the other side). The head sits in the
#      case opening, 0.1 mm inside the outer face, and stops on the socket's rim.
_ux = OPI_C[0] + (PORTS['usba'][0][0] + PORTS['usba'][0][1]) / 2           # socket centre (x)
_uz = top_pcb + (PORTS['usba'][1][0] + PORTS['usba'][1][1]) / 2             # socket centre (z)
_uy = WALL + Y_OPI - PORTS['usba'][2]                                        # socket face (y, outer coords)
HEAD = (5.6, _uy - 0.1, 12.8)
head = cq.Workplane().box(*HEAD, centered=(True, False, True)).edges('|Y').fillet(1.2).faces('<Y').edges().chamfer(0.4)
plate = (cq.Workplane().box(2.2, 8.0, 11.4, centered=(False, False, True)).translate((-2.5, HEAD[1], 0))
         .faces('>Y').edges().chamfer(0.5))
plug = head.union(plate)
plug_placed = plug.translate((_ux, 0.1, _uz))
# ---- export ----
# print orientation: tray floor down, shell top down (logo and light window first), ring wide end down, plug face down
def on_bed(p):
    bb = p.val().BoundingBox(); return p.translate((-bb.xmin, -bb.ymin, -bb.zmin))
shell_p = on_bed(shell.rotate((0, 0, 0), (1, 0, 0), 180))
plug_p = on_bed(plug.rotate((0, 0, 0), (1, 0, 0), 90))   # head face down, plate up
for name, part in (('purser-kasa-taban', on_bed(tray)), ('purser-kasa-kapak', shell_p), ('purser-anahtar-halkasi', on_bed(ring)), ('purser-usb-tapasi', plug_p)):
    cq.exporters.export(part, f'{OUT}/{name}.step')
    cq.exporters.export(part, f'{OUT}/{name}.stl', tolerance=0.02, angularTolerance=0.1)
cq.exporters.export(ring_placed, f'{OUT}/_halka-yerinde.stl', tolerance=0.02, angularTolerance=0.1)
cq.exporters.export(plug_placed, f'{OUT}/_tapa-yerinde.stl', tolerance=0.02, angularTolerance=0.1)

# ghost parts for the render and the fit check
ghosts = {
 'opi': cq.Workplane().box(*OPI, centered=(True, True, False)).translate((OPI_C[0], OPI_C[1], zb)),
 **{n: cq.Workplane().box(x1 - x0, 12, z1 - z0, centered=False).translate((OPI_C[0] + x0, OPI_C[1] - 25 - nose, top_pcb + z0))
    for n, ((x0, x1), (z0, z1), nose) in PORTS.items()},
 'rtc': cq.Workplane().box(RTC[0], RTC[1], 10.6 - STAND + 0.0, centered=False).translate((rx, ry, zb)),
 'ssd': cq.Workplane().box(SSD[0], SSD[1], 12, centered=False).translate((sx0, sy0, z0 + 0.2)),
 'stick': cq.Workplane().box(STICK[0], STICK[1], STICK[2], centered=(True, True, False)).translate((SC[0], STICK_C, z_skin - STICK_GAP - STICK[2])),
 'leds': cq.Workplane().box(STICK[0] - 2, 5.0, 1.6, centered=(True, True, False)).translate((SC[0], SC[1], z_skin - STICK_GAP)),   # LED row centred under the window
 'switch': cq.Workplane().box(SW_BODY[0], SW_BODY[1], SW_BODY[2], centered=(False, True, True)).translate((WALL + 0.5, SW_Y, SW_Z)),
}
for n, g in ghosts.items():
    cq.exporters.export(g, f'{OUT}/_g-{n}.stl', tolerance=0.05)

# interference check: ghosts vs tray/shell (ports are allowed into the front wall openings)
rep = {}
for n, g in ghosts.items():
    v = 0.0
    for part in (tray, shell):
        try:
            v += g.intersect(part).val().Volume()
        except Exception:
            pass
    rep[n] = round(v, 2)
rep['tapa_vs_kasa'] = round(sum((plug_placed.intersect(p).val().Volume() if plug_placed.intersect(p).vals() else 0) for p in (tray, shell)), 2)
rep['halka_vs_kasa'] = round(sum((ring_placed.intersect(p).val().Volume() if ring_placed.intersect(p).vals() else 0) for p in (tray, shell)), 2)
info = {'outer_mm': [round(OX, 1), round(OY, 1), round(OZ, 1)], 'split_z': SPLIT, 'interference_mm3': rep,
        'tray_vol_cm3': round(tray.val().Volume() / 1000, 1), 'shell_vol_cm3': round(shell.val().Volume() / 1000, 1)}
json.dump(info, open(f'{OUT}/olcu.json', 'w'), indent=1)
print(json.dumps(info))
