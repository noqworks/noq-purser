#!/usr/bin/env python3
# NOQ Purser r1 case: white tray + shell, screwless (snap ring), heat-stake pins, light through a thinned top.
# x: left -> right (RTC | Orange Pi | SSD), y: front (ports) -> back, z: up. Origin: outer front-left-bottom corner.
import cadquery as cq, svgelements as se, json, sys
from shapely.geometry import Polygon
from shapely.ops import unary_union

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

# ---- given measurements (OLCULER.md) ----
OPI = (55.0, 50.0, 1.6); OPI_HOLES = (49.5, 45.0)
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
OPI_C = P(X_OPI + OPI[0] / 2, 0.5 + OPI[1] / 2)

def rrect(w, h, r, z, height, cx, cy):
    return cq.Workplane().box(w, h, height, centered=(True, True, False)).edges('|Z').fillet(r).translate((cx, cy, z))

outer = cq.Workplane().box(OX, OY, OZ, centered=False).edges('|Z').fillet(R_PLAN).faces('>Z or <Z').edges().fillet(R_EDGE)
inner = (cq.Workplane().box(IN_X, IN_Y, IN_Z, centered=False).edges('|Z').fillet(R_PLAN - WALL)
         .faces('>Z').edges().fillet(R_EDGE - TOP).translate((WALL, WALL, FLOOR)))
body = outer.cut(inner)

# ---- front openings (Orange Pi ports; positions from the board model, relative to board centre) ----
top_pcb = zb + OPI[2]
def port_hole(dx, w, h, mw, mh, r):
    cx = OPI_C[0] + dx; cz = top_pcb + h / 2
    return (cq.Workplane('XZ').center(cx, cz).rect(w + mw, h + mh).extrude(-(WALL + 1.5))
            .edges('|Y').fillet(r).translate((0, -0.5, 0)))
# one rounded bay for USB-C, USB-A and RJ45: the plugs' overmoulds overlap, so separate holes would merge anyway
bx0, bx1 = OPI_C[0] - 7.85 - 6.6, OPI_C[0] + 14.0 + 8.2
bz0, bz1 = top_pcb - 1.9, top_pcb + 13.2 + 1.0
holes = [cq.Workplane('XZ').center((bx0 + bx1) / 2, (bz0 + bz1) / 2).rect(bx1 - bx0, bz1 - bz0).extrude(-(WALL + 1.5))
         .edges('|Y').fillet(2.5).translate((0, -0.5, 0))]
for h in holes:
    body = body.cut(h)

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

# tray lip (goes up inside the shell), cut away behind the Orange Pi's ports
lo = rrect(IN_X - 2 * CLR, IN_Y - 2 * CLR, R_PLAN - WALL - CLR, SPLIT, LIP_H, OX / 2, OY / 2)
li = rrect(IN_X - 2 * (CLR + LIP_T), IN_Y - 2 * (CLR + LIP_T), R_PLAN - WALL - CLR - LIP_T, SPLIT - 1, LIP_H + 2, OX / 2, OY / 2)
lip = lo.cut(li).cut(cq.Workplane().box(OPI[0] + 3, 6, 20, centered=(True, False, False)).translate((OPI_C[0], 0, SPLIT - 1)))
tray = tray.union(lip)

# snaps: half-round ridges on the lip, matching grooves in the shell
SNAP_Z = SPLIT + LIP_H / 2
def ridge(x, y, along, r):
    if along == 'x':
        return cq.Workplane('YZ').center(y, SNAP_Z).circle(r).extrude(8).translate((x - 4, 0, 0))
    return cq.Workplane('XZ').center(x, SNAP_Z).circle(r).extrude(-8).translate((0, y - 4, 0))
yf, yb = WALL + CLR, OY - WALL - CLR
xl, xr = WALL + CLR, OX - WALL - CLR
snaps = [(28, yf, 'x'), (OX - 30, yf, 'x'), (35, yb, 'x'), (OX / 2, yb, 'x'), (OX - 35, yb, 'x'), (xl, OY - 18, 'y'), (xr, OY / 2, 'y')]
for x, y, a in snaps:
    tray = tray.union(ridge(x, y, a, 0.55).intersect(lo))     # keep only the outward half
    shell = shell.cut(ridge(x, y, a, 0.7))
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
RTC_HOLES = [(8.5, RTC[1] - 2.1), (8.5, 2.1), (8.5 + 25.5, RTC[1] - 2.1)]
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

# ---- switch ring (separate colour): 6 high cone, 12 -> 10.5; nut + washer inside the lower part,
#      solid from 5 mm with an M6 x 0.75 internal thread (the usual bushing on mini toggles) ----
RH, RD0, RD1 = 6.0, 12.0, 10.5
ring = cq.Workplane().circle(RD0 / 2).workplane(offset=RH).circle(RD1 / 2).loft()
ring = ring.faces('>Z').edges().fillet(0.6)
ring = ring.cut(cq.Workplane().circle(9.7 / 2).extrude(2.6).translate((0, 0, -0.01)))        # nut (8 AF) + washer
ring = ring.cut(cq.Workplane().circle(7.2 / 2).extrude(5.0))                                  # over the bushing thread
ring = ring.cut(cq.Workplane().circle(5.3 / 2).extrude(RH + 1))                               # thread minor
helix = cq.Wire.makeHelix(pitch=0.75, height=2.2, radius=2.55).translate((0, 0, 4.4))
tooth = (cq.Workplane('XZ').polyline([(2.55, 4.4 - 0.32), (3.15, 4.4), (2.55, 4.4 + 0.32)]).close()
         .sweep(cq.Workplane().add(helix), isFrenet=True))
ring = ring.cut(tooth.intersect(cq.Workplane().circle(4).extrude(RH - 5.0 + 0.01).translate((0, 0, 5.0))))
# placed: bottom on the 1 mm seat, axis out of the left wall
ring_placed = ring.rotate((0, 0, 0), (0, 1, 0), -90).translate((SEAT, SW_Y, SW_Z))

# ---- USB-A plug: a face that fills the USB-A part of the port bay, held by a blade in the socket ----
ua_x0, ua_x1 = OPI_C[0] + 1.4 - 3.0, OPI_C[0] + 1.4 + 4.7          # clear of the USB-C plug's overmould and the RJ45
ua_z0, ua_z1 = top_pcb - 0.2, top_pcb + 6.6 + 0.4
plug = cq.Workplane().box(ua_x1 - ua_x0, 1.9, ua_z1 - ua_z0, centered=False).translate((ua_x0, 0.0, ua_z0))
plug = plug.edges('|Y').fillet(0.6)
blade = cq.Workplane().box(8.2, 5.5, 1.5, centered=(True, False, True)).translate((OPI_C[0] + 1.4, 1.9, top_pcb + 6.6 * 0.33))
bumps = [cq.Workplane('YZ').circle(0.35).extrude(2.4).translate((OPI_C[0] + 1.4 + dx - 1.2, 1.9 + 3.5, top_pcb + 6.6 * 0.33 + 0.75)) for dx in (-2.5, 2.5)]   # friction ridges
plug = plug.union(blade)
for b_ in bumps:
    plug = plug.union(b_)
# the shell's front wall runs from y = 0 to WALL; the plug face sits flush with the outside
plug_placed = plug.translate((0, 0, 0))
# ---- export ----
# print orientation: tray floor down, shell top down (logo and light window first), ring wide end down, plug face down
def on_bed(p):
    bb = p.val().BoundingBox(); return p.translate((-bb.xmin, -bb.ymin, -bb.zmin))
shell_p = on_bed(shell.rotate((0, 0, 0), (1, 0, 0), 180))
plug_p = on_bed(plug.rotate((0, 0, 0), (1, 0, 0), 90))
for name, part in (('purser-kasa-taban', on_bed(tray)), ('purser-kasa-kapak', shell_p), ('purser-anahtar-halkasi', on_bed(ring)), ('purser-usb-tapasi', plug_p)):
    cq.exporters.export(part, f'{OUT}/{name}.step')
    cq.exporters.export(part, f'{OUT}/{name}.stl', tolerance=0.02, angularTolerance=0.1)
cq.exporters.export(ring_placed, f'{OUT}/_halka-yerinde.stl', tolerance=0.02, angularTolerance=0.1)
cq.exporters.export(plug_placed, f'{OUT}/_tapa-yerinde.stl', tolerance=0.02, angularTolerance=0.1)

# ghost parts for the render and the fit check
ghosts = {
 'opi': cq.Workplane().box(*OPI, centered=(True, True, False)).translate((OPI_C[0], OPI_C[1], zb)),
 'rj45': cq.Workplane().box(15, 21.8, 13.2, centered=(True, False, False)).translate((OPI_C[0] + 14, OPI_C[1] - 26, top_pcb)),
 'usba': cq.Workplane().box(9.8, 12, 6.6, centered=(True, False, False)).translate((OPI_C[0] + 1.4, OPI_C[1] - 26, top_pcb)),
 'usbc': cq.Workplane().box(8.6, 7.2, 3.2, centered=(True, False, False)).translate((OPI_C[0] - 7.85, OPI_C[1] - 26, top_pcb)),
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
rep['tapa_vs_kasa'] = round(sum((plug.intersect(p).val().Volume() if plug.intersect(p).vals() else 0) for p in (tray, shell)), 2)
rep['halka_vs_kasa'] = round(sum((ring_placed.intersect(p).val().Volume() if ring_placed.intersect(p).vals() else 0) for p in (tray, shell)), 2)
info = {'outer_mm': [round(OX, 1), round(OY, 1), round(OZ, 1)], 'split_z': SPLIT, 'interference_mm3': rep,
        'tray_vol_cm3': round(tray.val().Volume() / 1000, 1), 'shell_vol_cm3': round(shell.val().Volume() / 1000, 1)}
json.dump(info, open(f'{OUT}/olcu.json', 'w'), indent=1)
print(json.dumps(info))
