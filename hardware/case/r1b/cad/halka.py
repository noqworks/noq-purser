"""Anahtar halkası r1b.2: M6×0,75 iç diş modelli (Umut: 'tamamen dolu ve dişli olmalı'). Gövde cadquery (koni + üst pah),
diş manifold3d ile: diş kesitinin yarıçapı açıya göre değişen 2B şekli, adım başına 360° bükülerek çekilir = tam sarmal."""
import math, sys, numpy as np, trimesh, manifold3d as mf
import cadquery as cq
RH, RD0, RD1 = 6.0, 12.0, 10.5
P = 0.75
D_MIN, D_MAJ = 5.35, 6.30          # M6×0,75: D1 5,19 / D 6,0; baskı payı ile
govde = cq.Workplane().circle(RD0 / 2).workplane(offset=RH).circle(RD1 / 2).loft().faces('>Z').edges().fillet(0.6)
cq.exporters.export(govde, '_govde.stl', tolerance=0.01, angularTolerance=0.05)
g = trimesh.load('_govde.stl')
G = mf.Manifold(mf.Mesh(vert_properties=np.asarray(g.vertices, np.float32), tri_verts=np.asarray(g.faces, np.uint32)))
# diş profili (60°, tepe ve dip düz): faz u ∈ [0,1) bir adım
rmin, rmaj = D_MIN / 2, D_MAJ / 2
def r(u):
    u = u % 1.0
    duz = 0.125; yan = (1 - 2 * duz) / 2       # dip düzlüğü, yan, tepe düzlüğü, yan
    if u < duz: return rmin
    if u < duz + yan: return rmin + (rmaj - rmin) * (u - duz) / yan
    if u < 2 * duz + yan: return rmaj
    return rmaj - (rmaj - rmin) * (u - 2 * duz - yan) / yan
N = 360
kesit = [(r(i / N) * math.cos(2 * math.pi * i / N), r(i / N) * math.sin(2 * math.pi * i / N)) for i in range(N)]
L = RH + 2.0
tur = L / P
kesici = mf.Manifold.extrude(mf.CrossSection([kesit]), L, n_divisions=int(tur * 24), twist_degrees=-360.0 * tur).translate((0, 0, -1.0))
H = G - kesici
# giriş pahı (alt): 0,6 mm
pah = mf.Manifold.cylinder(0.6, rmaj + 0.3, rmin, 96).translate((0, 0, -0.001))
H = H - pah
m = H.to_mesh()
t = trimesh.Trimesh(m.vert_properties[:, :3], m.tri_verts)
print('su geçirmez', t.is_watertight, 'gövde', len(t.split(only_watertight=False)), 'hacim', round(t.volume, 1), 'boyut', t.extents)
t.export(sys.argv[1] if len(sys.argv) > 1 else 'purser-anahtar-halkasi.stl')
