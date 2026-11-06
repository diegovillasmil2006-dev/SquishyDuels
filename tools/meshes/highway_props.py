"""Squishy Duels highway props: the 7 traps + 14 boosters as blocky Blender meshes (2026-11-01; the sheet's other 7
boosters 2026-11-06: set HIGHWAY_PROPS_ONLY=id,id to build and export only those pieces).

The owner's style rule (2026-11-01, "everything was made in blender and made blocky", like Steal an Egg): the pieces of
the owner's "Launchers & Biomes - Concept Sheet" (Desktop "jason designs", Candy Toy-Box Park Lobby.zip,
concept-kit.js:280-300) keep the sheet's shapes, sizes and colours, drawn the way Diego's lobby and maps look: the
sheet's own 8-sided cylinders, faceted balls (icosahedron detail 1) and 4-sided torus tubes, chamfered boxes, the
lobby's stud tile UVs (1 UV unit = 2 studs, read back from Diego's lobby meshes; MaterialVariant SquishyStud) and an ink
hull round every part (Diego's maps: inward faces, ink #1c1530). The halo ring now has the sheet's two gold wings and
the fire jet its tapered 6-sided vent. Glass in the sheet becomes solid (blocky, not shiny).
Run it as its own Blender process:

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python highway_props.py -- <out_dir>
        [<stud_color.png> <stud_normal.png>]

Writes <out_dir>/SD_HighwayProps.glb (per piece one object per colour key "<id>__<key>" plus "<id>__Outline", all at
the piece's origin = the lane top centre), manifest.json (each object's centre and size in Roblox axes) and previews
(<id>.png, sheet.png; the stud pictures only tint the previews). 1 Blender unit = 1 stud; points are computed in Roblox
axes (X right, Y up, Z back) and written as (X, -Z, Y), so the glTF "+Y up" export gives back Roblox axes.
Colours here are for the previews only; the game paints the meshes from Art/HighwayTraps and Art/HighwayBoosters.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not ARGV:  # never default to the script's folder: in the repo the snapshot would commit the .glb and previews
	raise SystemExit("usage: blender --background --factory-startup --python highway_props.py -- <out_dir> [...]")
OUT = os.path.abspath(ARGV[0])
STUD_COLOR = ARGV[1] if len(ARGV) > 1 else None
STUD_NORMAL = ARGV[2] if len(ARGV) > 2 else None
os.makedirs(OUT, exist_ok=True)

UV_STUDS = 2.0  # one stud tile every 2 studs, like Diego's lobby meshes
INK = "1C1530"  # Diego's map outline ink (SkyMapBuilder INK)
D = math.pi / 180

# ------------------------------------------------------------------------------------------------- the 14 pieces


def wing_pts(s):  # concept-kit.js wingPts
	pts = [(0, 0.1), (0.55, 0), (0.62, 0.3), (1.05, 0.28), (1.12, 0.62), (1.55, 0.62), (1.6, 1.0), (1.95, 1.05),
		(1.75, 1.45), (1.1, 1.38), (0.45, 1.05), (0, 0.75)]
	return [(x * s, y * s) for x, y in pts]


def mirror(pts):
	return [(-x, y) for x, y in pts]


def star_pts(n, ro, ri):  # concept-kit.js starPts
	pts = []
	for i in range(n * 2):
		a = math.pi / 2 + i * math.pi / n
		q = ri if i % 2 else ro
		pts.append((math.cos(a) * q, math.sin(a) * q))
	return pts


# id -> palette (key -> (hex, glows)) and the sheet's build (concept-kit.js line in each comment)
PIECES = {}


def piece(pid, pal):
	def wrap(fn):
		PIECES[pid] = (pal, fn)
		return fn
	return wrap


@piece("cm_gum_puddle", {"gum": ("FF9ED2", False), "bub": ("FF7FC0", False)})  # :282
def _(k):
	k.u("gum", (8, 0.35, 5), (0, 0, 0))
	k.u("gum", (5, 0.36, 6.5), (1, 0, 0))
	k.u("gum", (3, 0.5, 3), (-2.4, 0, 1.4), (0, 20, 0))
	k.s("bub", 2.2, (1.6, 1.2, -0.6))


@piece("bt_jam_puddle", {"jam": ("C2185B", False), "seed": ("E0315F", False)})  # :285
def _(k):
	k.u("jam", (7, 0.4, 5), (0, 0, 0))
	k.u("jam", (4, 0.42, 7), (1.4, 0, 0.4), (0, 15, 0))
	k.u("jam", (2.4, 0.6, 2.4), (-2.6, 0, -1.6), (0, 30, 0))
	for x, z in ((-1, 1), (1.8, -1.2), (0.4, 2.6), (2.4, 1.6)):
		k.u("seed", (0.6, 0.3, 0.6), (x, 0.4, z), (0, 45, 0))


@piece("bl_splash_pool", {"rim": ("EED6B8", False), "water": ("7FD8D0", False), "drop": ("DFF4FF", False)})  # :288
def _(k):
	for s in (-1, 1):
		k.u("rim", (10, 1, 1), (0, 0, s * 4.5))
		k.u("rim", (1, 1, 8), (s * 4.5, 0, 0))
	k.u("water", (8, 0.7, 8), (0, 0, 0))
	for p in ((-1.5, 2, 0), (1.4, 2.8, -1), (0.2, 3.6, 1.2)):
		k.b("drop", (0.8, 0.8, 0.8), p, (45, 45, 0))


@piece("fd_marshmallow", {"m": ("FFF3F7", False), "toast": ("F2C487", False)})  # :291
def _(k):
	k.c("m", 3.2, 2.4, (-1.8, 1.2, 0))
	k.c("m", 3.2, 2.4, (1.8, 1.2, 0.4))
	k.c("m", 3.0, 2.2, (0, 3.0, 0.2), (90, 0, 70))
	k.c("toast", 3.0, 0.2, (-1.8, 2.5, 0))


@piece("lv_lava_pit", {"rim": ("3A2C3A", False), "lava": ("FF6A3D", True), "bub": ("FFB03A", True)})  # :294
def _(k):
	k.c("rim", 11, 0.8, (0, 0.4, 0))
	k.c("lava", 9, 0.85, (0, 0.43, 0))
	for x, z, s in ((-2, 1, 1), (1.6, -1.4, 0.8), (0.6, 2.2, 0.6)):
		k.u("bub", (s, s * 0.6, s), (x, 0.85, z), (0, 30, 0))


@piece("rr_cloud_gap", {"cloud": ("FFFFFF", False), "shade": ("E6DDFF", False)})  # :297
def _(k):
	k.u("shade", (12, 0.6, 9), (0, -0.6, 0))
	for w, h, d, x, y, z in ((9, 1.6, 7, 0, 0.5, 0), (5, 1.4, 4, -2.6, 1.3, 1), (4, 1.2, 4, 2.8, 1.2, -1.2),
			(3, 1, 3, 0.4, 2, 0.4)):
		k.b("cloud", (w, h, d), (x, y, z))


@piece("dh_soft_cloud", {"cloud": ("FFE9A8", False), "hi": ("FFF6EC", False)})  # :300
def _(k):
	for w, h, d, x, y, z in ((10, 1.6, 8, 0, 0.6, 0), (6, 1.6, 5, -2.4, 1.6, 0.8), (5, 1.4, 4, 2.6, 1.5, -1)):
		k.b("cloud", (w, h, d), (x, y, z))
	k.b("hi", (3, 1, 3), (0.4, 2.6, 0.2))


@piece("cm_jelly_pad", {"base": ("FF8FBF", False), "jelly": ("FF7FC0", False), "bean": ("FFD84A", False)})  # :280
def _(k):
	k.u("base", (8, 0.5, 8), (0, 0, 0))
	k.u("jelly", (7, 0.9, 7), (0, 0.5, 0))
	for x, z, r in ((-2.2, -2, 20), (2, -1.6, -30), (-1.6, 2.2, 60), (2.3, 2.1, 10)):
		k.u("bean", (0.9, 0.4, 0.55), (x, 1.4, z), (0, r, 0))


@piece("bt_toaster_cannon", {"body": ("9FB4C7", False), "dark": ("1E1428", False), "toast": ("F2C487", False),
	"lever": ("FF5C8A", False)})  # :283
def _(k):
	for x in (-2.4, 2.4):
		for z in (-1.5, 1.5):
			k.u("dark", (0.6, 0.3, 0.6), (x, 0, z))
	k.u("body", (6, 4, 4.2), (0, 0.3, 0))
	for z in (-0.9, 0.9):
		k.u("dark", (4, 0.12, 0.9), (0, 4.3, z))
		k.u("toast", (3.6, 2.2, 0.7), (0, 3.4, z))
	k.u("lever", (0.5, 0.7, 0.9), (3.25, 2.2, 0))


@piece("bl_pearl_bouncer", {"base": ("FF6FA3", False), "pearl": ("3B2630", False)})  # :286
def _(k):
	k.u("base", (10, 0.4, 8), (0, 0, 0))
	k.s("pearl", 4.4, (-2.2, 2.4, 0))
	k.s("pearl", 4.4, (2.2, 2.4, 0.6))
	k.s("pearl", 4, (0, 2.2, -2.2))


@piece("fd_ice_slide", {"ice": ("BDEBFF", False), "curb": ("8FD8FF", False), "snow": ("F4FBFF", False)})  # :289
def _(k):
	k.u("ice", (12, 0.5, 26), (0, 0, 0))
	for s in (-1, 1):
		k.u("curb", (1, 0.9, 26), (s * 6.5, 0, 0))
	for x, z in ((-7.4, -6), (7.4, 4), (-7.2, 9)):
		k.u("snow", (1.4, 1.1, 2.4), (x, 0, z))


@piece("lv_fire_jet", {"vent": ("3A2C3A", False), "ring": ("FF6A3D", True), "f1": ("FFB03A", True),
	"f2": ("FF6A3D", True)})  # :292
def _(k):
	k.c("vent", (2.6, 4.6), 1.6, (0, 0.8, 0), None, 6)
	k.c("ring", 2.7, 0.2, (0, 1.65, 0), None, 6)
	k.u("f2", (2.4, 4.4, 2.4), (0, 1.7, 0), (0, 45, 0))
	k.u("f1", (1.4, 3.6, 1.4), (0, 1.7, 0), (0, 20, 0))
	k.u("f1", (0.8, 2.2, 0.8), (0, 6.1, 0), (0, 45, 0))
	k.u("f2", (1.2, 1.4, 1.2), (0, 5.6, 0), (0, 10, 0))


@piece("rr_comet_pad", {"pad": ("B98CFF", False), "chev": ("FFFFFF", True), "tail": ("FF5C8A", True)})  # :296
def _(k):
	k.u("pad", (10, 0.5, 13), (0, 0, 0))
	for i in range(3):
		z = 3.5 - i * 3.5
		for s in (-1, 1):
			k.b("chev", (3.2, 0.12, 0.7), (s * 1.25, 0.56, z), (0, s * 35, 0))
	k.u("tail", (1.2, 0.12, 4), (0, 0.5, 5.4))


@piece("dh_halo_ring", {"halo": ("FFF0A0", True), "gold": ("FFC23C", False)})  # :299
def _(k):
	k.r("halo", 6, 0.6, (0, 7.5, 0), None, 12)
	k.r("gold", 6.9, 0.32, (0, 7.5, 0), None, 12)
	for s in (-1, 1):
		k.e("gold", wing_pts(1.8) if s > 0 else mirror(wing_pts(1.8)), 0.3, (s * 7, 7, 0))


@piece("cm_sprinkle_ramp", {"ramp": ("8EEAD0", False), "s1": ("FF8FBF", False), "s2": ("FFD84A", False),
	"s3": ("FFF6EC", False)})  # :281
def _(k):
	k.w("ramp", (10, 3, 12), (0, 1.5, 0), (0, 180, 0))
	for i in range(9):
		x = -3.6 + (i % 3) * 3.6 + (i % 2) * 0.8
		z = 4 - (i // 3) * 4
		k.b(("s1", "s2", "s3")[i % 3], (1.1, 0.25, 0.3), (x, (6 - z) / 4 + 0.12, z), (14, i * 40, 0))


@piece("bt_butter_slide", {"butter": ("FFE36E", False), "melt": ("FFE36E", False), "foil": ("FFF6EC", False)})  # :284
def _(k):
	k.u("butter", (11.8, 0.5, 24), (0, 0, 0))
	for x, z, w, d in ((-2.5, -6, 3.4, 5), (2.6, 2, 2.6, 6), (-1, 8, 4, 3)):
		k.u("melt", (w, 0.14, d), (x, 0.5, z))
	for s in (-1, 1):
		k.u("foil", (0.5, 0.65, 24), (s * 6.15, 0, 0))


@piece("bl_straw_tube", {"tube": ("FF6FA3", False), "stripe": ("FFF6EC", False)})  # :287
def _(k):
	for s in (-1, 1):
		k.u("tube", (1, 7, 16), (s * 5.5, 0, 0))
	k.u("tube", (12, 1, 16), (0, 7, 0))
	for z in (-4, 4):
		for s in (-1, 1):
			k.u("stripe", (1.2, 7.1, 1.4), (s * 5.5, 0, z))
		k.u("stripe", (12.2, 1.1, 1.4), (0, 7, z))


@piece("fd_cone_cannon", {"stand": ("F4FBFF", False), "cone": ("E0A062", False), "rim": ("FF8FBF", False)})  # :290
def _(k):
	k.u("stand", (6, 1.2, 6), (0, 0, 0))
	k.u("stand", (3.6, 1.2, 3.6), (0, 1.2, 0.6))
	g = k.g((0, 3.2, 0.6), (-55, 0, 0))
	g.c("cone", (4.6, 0.8), 7.4, (0, 3.2, 0))
	g.r("rim", 2.3, 0.45, (0, 6.9, 0), (90, 0, 0), 8)


@piece("lv_magma_ramp", {"ramp": ("3A2C3A", False), "seam": ("FF6A3D", True)})  # :293
def _(k):
	k.w("ramp", (12, 3.5, 10), (0, 1.75, 0), (0, 180, 0))
	for i in range(3):
		z = 3 - i * 3
		k.b("seam", (7 - i, 0.12, 0.4), (i - 1, (5 - z) * 0.35 + 0.08, z), (19.3, 10 - i * 12, 0))


@piece("rr_star_ring", {"ring": ("FFD84A", True), "halo": ("FFF0A0", False), "star": ("FFFFFF", True)})  # :295
def _(k):
	k.r("ring", 7, 0.7, (0, 8.5, 0), None, 10)
	k.r("halo", 7.9, 0.3, (0, 8.5, 0), None, 10)
	k.e("star", star_pts(5, 1.7, 0.75), 0.6, (0, 16.6, 0))


@piece("dh_wing_gate", {"marble": ("FBF7F2", False), "gold": ("FFC23C", False), "wing": ("FFFFFF", False),
	"halo": ("FFF0A0", True)})  # :298
def _(k):
	for s in (-1, 1):
		k.u("marble", (2, 15, 2), (s * 9, 0, 0))
		k.u("gold", (2.6, 1, 2.6), (s * 9, 15, 0))
		k.e("wing", wing_pts(4.6) if s > 0 else mirror(wing_pts(4.6)), 0.6, (s * 10, 9, 0))
	k.u("marble", (20, 1.6, 2), (0, 16, 0))
	k.r("halo", 2.4, 0.4, (0, 20, 0), None, 12)


# ------------------------------------------------------------------------------------------------ the sheet's kit


def rot_matrix(r):  # three.js Euler "XYZ" = Rx * Ry * Rz (degrees)
	if not r:
		return Matrix.Identity(4)
	return Matrix.Rotation(r[0] * D, 4, "X") @ Matrix.Rotation(r[1] * D, 4, "Y") @ Matrix.Rotation(r[2] * D, 4, "Z")


def bm_box(s):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2]))
	chamfer = min(0.12, 0.2 * min(s))  # toy-block edges
	bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=chamfer, offset_type="OFFSET", segments=1,
		profile=0.5, affect="EDGES", clamp_overlap=True)
	return bm


def bm_wedge(s):  # the sheet's k.w: width s[0], height s[1], depth s[2], rising towards +Z, centred
	w, h, d = s[0] / 2, s[1] / 2, s[2] / 2
	bm = bmesh.new()
	lo = [bm.verts.new((-w, y, z)) for y, z in ((-h, -d), (-h, d), (h, d))]
	hi = [bm.verts.new((w, y, z)) for y, z in ((-h, -d), (-h, d), (h, d))]
	bm.faces.new(lo)
	bm.faces.new(hi)
	for i in range(3):
		bm.faces.new((lo[i], lo[(i + 1) % 3], hi[(i + 1) % 3], hi[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=min(0.12, 0.2 * min(s)), offset_type="OFFSET", segments=1,
		profile=0.5, affect="EDGES", clamp_overlap=True)
	return bm


def bm_cyl(top_d, bottom_d, h, seg):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=bottom_d / 2,
		radius2=top_d / 2, depth=h)
	for v in bm.verts:  # Blender's cone runs along Z: stand it up along Roblox Y
		x, y, z = v.co
		v.co = Vector((x, z, -y))
	return bm


def bm_ball(d):
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=2, radius=d / 2)  # = three.js IcosahedronGeometry detail 1
	return bm


def bm_torus(radius, tube, seg, sides=4):  # three.js TorusGeometry(radius, tube, 4, seg) in the XY plane
	bm = bmesh.new()
	rows = []
	for j in range(seg):
		u = j / seg * 2 * math.pi
		rows.append([bm.verts.new(((radius + tube * math.cos(v)) * math.cos(u),
			(radius + tube * math.cos(v)) * math.sin(u), tube * math.sin(v)))
			for v in (i / sides * 2 * math.pi for i in range(sides))])
	for j in range(seg):
		for i in range(sides):
			n, m = (j + 1) % seg, (i + 1) % sides
			bm.faces.new((rows[j][i], rows[n][i], rows[n][m], rows[j][m]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def bm_extrude(pts, depth):  # three.js ExtrudeGeometry of a flat shape, centred on Z
	bm = bmesh.new()
	lo = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
	hi = [bm.verts.new((x, y, depth / 2)) for x, y in pts]
	bm.faces.new(lo)
	bm.faces.new(hi)
	n = len(pts)
	for i in range(n):
		bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
	bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])  # the wing outline is concave
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def hull_of(bm, flat_top):
	"""Diego's ink hull: the part pushed out by t along its normals (even thickness), faces turned inward. A flat
	slab on the lane keeps its hull below its top (Diego's floor: "ink hull below the top")."""
	xs = [v.co for v in bm.verts]
	size = [max(c[i] for c in xs) - min(c[i] for c in xs) for i in range(3)]
	top = max(c.y for c in xs)
	t = max(0.08, min(0.22, 0.1 * sum(size) / 3, 0.5 * min(size)))  # thinner than the maps' 0.32: seen up close
	h = bm.copy()
	h.normal_update()
	for v in h.verts:
		v.co = v.co + v.normal * (t * min(1.5, v.calc_shell_factor()))  # sharp corners would spike
		if flat_top:
			v.co.y = min(v.co.y, top)
	bmesh.ops.reverse_faces(h, faces=h.faces)
	return h


class Kit:
	def __init__(self, parts=None, base=None):
		self.parts = [] if parts is None else parts  # (key, bmesh in piece space, Roblox axes)
		self.base = base or Matrix.Identity(4)

	def g(self, p, r):  # the sheet's k.g: a group at p turned by r
		return Kit(self.parts, self.base @ Matrix.Translation(Vector(p)) @ rot_matrix(r))

	def b(self, key, s, p, r=None):
		self._put(key, bm_box(s), p, r)

	def w(self, key, s, p, r=None):
		self._put(key, bm_wedge(s), p, r)

	def u(self, key, s, p, r=None):
		self._put(key, bm_box(s), (p[0], p[1] + s[1] / 2, p[2]), r, s[1] <= 0.6 and p[1] <= 0)

	def c(self, key, d, h, p, r=None, seg=8):
		a, b = d if isinstance(d, tuple) else (d, d)
		self._put(key, bm_cyl(a, b, h, seg), p, r)

	def s(self, key, d, p):
		self._put(key, bm_ball(d), p)

	def r(self, key, radius, tube, p, r=None, seg=12):
		self._put(key, bm_torus(radius, tube, seg), p, r)

	def e(self, key, pts, depth, p, r=None):
		self._put(key, bm_extrude(pts, depth), p, r)

	def _put(self, key, bm, p, r=None, flat_top=False):
		hull = hull_of(bm, flat_top)
		m = self.base @ Matrix.Translation(Vector(p)) @ rot_matrix(r)
		for g in (bm, hull):
			bmesh.ops.transform(g, matrix=m, verts=g.verts)
		self.parts.append((key, bm))
		self.parts.append(("Outline", hull))


# ------------------------------------------------------------------------------------------------------- Blender


def srgb_to_linear(hexstr):
	out = []
	for k in (0, 2, 4):
		c = int(hexstr[k:k + 2], 16) / 255
		out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
	return (*out, 1.0)


def append(dst, src):
	vmap = {v: dst.verts.new(v.co) for v in src.verts}
	for f in src.faces:
		dst.faces.new([vmap[v] for v in f.verts])


def stud_uvs(bm):
	"""Box-projected UVs in studs / UV_STUDS (the sheet's fin() and Diego's lobby meshes)."""
	uv = bm.loops.layers.uv.new("UVMap")
	bm.normal_update()
	for f in bm.faces:
		ax, ay, az = (abs(c) for c in f.normal)
		for loop in f.loops:
			x, y, z = loop.vert.co
			a, b = (z, y) if ax >= ay and ax >= az else (x, z) if ay >= az else (x, y)
			loop[uv].uv = (a / UV_STUDS, b / UV_STUDS)


for o in list(bpy.data.objects):  # the factory scene's cube, camera and light
	bpy.data.objects.remove(o)
LIB = bpy.data.collections.new("SD_HighwayProps")
bpy.context.scene.collection.children.link(LIB)
manifest = {"uvStuds": UV_STUDS, "ink": INK, "objects": {}}
piece_objects = {}
problems = []

ONLY = [pid for pid in os.environ.get("HIGHWAY_PROPS_ONLY", "").split(",") if pid]
for pid in ONLY:
	if pid not in PIECES:
		raise SystemExit("highway_props: no piece " + pid)

for pid, (pal, build) in PIECES.items():
	if ONLY and pid not in ONLY:
		continue
	kit = Kit()
	build(kit)
	merged = {}
	for key, bm in kit.parts:
		if key != "Outline" and key not in pal:
			problems.append(f"{pid}: no palette key {key}")
		merged.setdefault(key, bmesh.new())
		append(merged[key], bm)
		bm.free()
	objs = []
	for key, bm in merged.items():
		if key != "Outline":
			stud_uvs(bm)
		cos = [v.co.copy() for v in bm.verts]
		lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
		hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
		for v in bm.verts:
			v.co = Vector((v.co.x, -v.co.z, v.co.y))
		bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
		name = f"{pid}__{key}"
		me = bpy.data.meshes.new(name)
		bm.to_mesh(me)
		bm.free()
		me.shade_flat()
		obj = bpy.data.objects.new(name, me)
		LIB.objects.link(obj)
		objs.append(obj)
		manifest["objects"][name] = {
			"piece": pid,
			"key": key,
			"center": [round((lo[i] + hi[i]) / 2, 4) for i in range(3)],
			"size": [round(hi[i] - lo[i], 4) for i in range(3)],
			"tris": len(me.polygons),
		}
	piece_objects[pid] = objs
	print(pid, {o.name.split("__")[1]: len(o.data.polygons) for o in objs})

with open(os.path.join(OUT, "manifest.json"), "w") as f:
	json.dump(manifest, f, indent=1)
if problems:
	raise SystemExit("highway_props: " + "; ".join(problems))

# ------------------------------------------------------------------------------------------------------- export

bpy.ops.object.select_all(action="DESELECT")
for o in LIB.objects:
	o.select_set(True)
bpy.context.view_layer.objects.active = LIB.objects[0]
glb = os.path.join(OUT, "SD_HighwayProps.glb")
bpy.ops.export_scene.gltf(
	filepath=glb,
	export_format="GLB",
	use_selection=True,
	export_yup=True,
	export_apply=True,
	export_texcoords=True,
	export_normals=True,
	export_tangents=False,
	export_materials="NONE",
	export_vertex_color="NONE",
	export_attributes=False,
	export_animations=False,
	export_morph=False,
	export_skins=False,
	export_cameras=False,
	export_lights=False,
	export_extras=False,
)
print("EXPORTED", glb, os.path.getsize(glb), "bytes")

# ------------------------------------------------------------------------------------------------------ previews


def load_image(path, colour):
	if not path or not os.path.exists(path):
		return None
	img = bpy.data.images.load(path)
	if not colour:
		img.colorspace_settings.name = "Non-Color"
	return img


STUD_IMG = load_image(STUD_COLOR, True)
STUD_NRM = load_image(STUD_NORMAL, False)


def material(name, hexstr, glows, ink):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nodes, links = m.node_tree.nodes, m.node_tree.links
	bsdf = nodes["Principled BSDF"]
	col = srgb_to_linear(hexstr)
	bsdf.inputs["Roughness"].default_value = 0.85
	if ink:
		bsdf.inputs["Base Color"].default_value = col
		m.use_backface_culling = True
	elif glows:
		bsdf.inputs["Base Color"].default_value = col
		bsdf.inputs["Emission Color"].default_value = col
		bsdf.inputs["Emission Strength"].default_value = 1.6
	elif STUD_IMG:
		tex = nodes.new("ShaderNodeTexImage")
		tex.image = STUD_IMG
		tint = nodes.new("ShaderNodeVectorMath")
		tint.operation = "MULTIPLY"
		tint.inputs[1].default_value = col[:3]
		links.new(tex.outputs["Color"], tint.inputs[0])
		links.new(tint.outputs["Vector"], bsdf.inputs["Base Color"])
		if STUD_NRM:
			ntex = nodes.new("ShaderNodeTexImage")
			ntex.image = STUD_NRM
			nmap = nodes.new("ShaderNodeNormalMap")
			links.new(ntex.outputs["Color"], nmap.inputs["Color"])
			links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
	else:
		bsdf.inputs["Base Color"].default_value = col
	return m


for pid, objs in piece_objects.items():
	pal = PIECES[pid][0]
	for o in objs:
		key = o.name.split("__")[1]
		hexstr, glows = (INK, False) if key == "Outline" else pal[key]
		o.data.materials.append(material(o.name, hexstr, glows, key == "Outline"))

scene = bpy.context.scene
for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
	try:
		scene.render.engine = engine
		break
	except TypeError:
		continue
scene.view_settings.view_transform = "Standard"
scene.world = bpy.data.worlds.new("Sky")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = srgb_to_linear("D9CCFF")
bg.inputs["Strength"].default_value = 0.9
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.2
sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(-35))
scene.collection.objects.link(sun)
ground_me = bpy.data.meshes.new("Ground")
gbm = bmesh.new()
bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=400)
gbm.to_mesh(ground_me)
gbm.free()
ground = bpy.data.objects.new("Ground", ground_me)
ground.location.z = -0.02
ground.data.materials.append(material("Ground", "8E7CC3", False, False))
scene.collection.objects.link(ground)
cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.type = "ORTHO"
cam_data.clip_end = 5000
cam = bpy.data.objects.new("PreviewCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def render(path, objs, yaw, pitch, res):
	"""Ortho view of `objs` from Roblox direction (yaw about Y from +Z, pitch up), framed to their bounds."""
	scene.render.resolution_x, scene.render.resolution_y = res
	scene.render.resolution_percentage = 100
	corners = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	ctr = sum(corners, Vector()) / len(corners)
	yr, pr = math.radians(yaw), math.radians(pitch)
	d_b = Vector((math.sin(yr) * math.cos(pr), -math.cos(yr) * math.cos(pr), math.sin(pr)))
	fwd = -d_b
	right = fwd.cross(Vector((0, 0, 1))).normalized()
	up = right.cross(fwd)
	xs = [(c - ctr).dot(right) for c in corners]
	ys = [(c - ctr).dot(up) for c in corners]
	ctr = ctr + right * (max(xs) + min(xs)) / 2 + up * (max(ys) + min(ys)) / 2
	cam.location = ctr + d_b * 1000
	cam.rotation_euler = fwd.to_track_quat("-Z", "Y").to_euler()
	cam_data.ortho_scale = max(max(xs) - min(xs), (max(ys) - min(ys)) * res[0] / res[1]) * 1.15
	for o in LIB.objects:
		o.hide_render = o not in objs
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	print("RENDERED", path)


TILE = (560, 440)
for pid, objs in piece_objects.items():
	render(os.path.join(OUT, f"{pid}.png"), objs, 35, 32, TILE)

# the sheet: the previews tiled, traps on the top row, boosters below, in highway order
import numpy as np

w, h = TILE
rows = math.ceil(len(piece_objects) / 7)
sheet = np.zeros((rows * h, 7 * w, 4), dtype=np.float32)
for i, pid in enumerate(piece_objects):
	row, col = divmod(i, 7)
	img = bpy.data.images.load(os.path.join(OUT, f"{pid}.png"))
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
	sheet[(rows - 1 - row) * h:(rows - row) * h, col * w:(col + 1) * w] = px  # Blender rows run bottom-up
out = bpy.data.images.new("sheet", 7 * w, rows * h, alpha=True)
out.pixels = sheet.ravel()
out.filepath_raw = os.path.join(OUT, "sheet.png")
out.file_format = "PNG"
out.save()
print("DONE")
