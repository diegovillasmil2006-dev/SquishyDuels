"""Squishy Duels highway boosters: the 14 boosters as big toy models (2026-11-06).

The owner on the old blocky ones: "more roblox style, they look so bland, take hit a golf ball as an example", then "Yes,
build all 14" on a sample. So these keep the objects of the owner's "Launchers & Biomes - Concept Sheet" (Desktop "jason
designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:280-299) but 2-3 times bigger, round and smooth, in 2-3 loud colours
with one bright detail; only the stands keep Diego's stud tile (a "Stud" key). The look is borrowed, their models are not.
highway_props.py builds the 7 traps with this kit (it imports this file, which then builds nothing, and calls main).
Run it as its own Blender process:

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python highway_boosters.py -- <out_dir>

Writes <out_dir>/SD_HighwayProps.glb (per piece one object per colour key "<id>__<key>", all at the piece's origin = the
lane top centre), manifest.json (each object's centre and size in Roblox axes, and each piece's tris and bounds) and
previews (<id>.png: the piece on its zone's lane with a player, always the same zoom). Import it and run
highway_props_setup.luau as for highway_props.py: it keeps the other pieces. 1 Blender unit = 1 stud; points are computed
in Roblox axes (X right, Y up, Z back, so a throw flies to -Z) and written as (X, -Z, Y), so the glTF "+Y up" export gives
back Roblox axes. Colours here are for the previews only; the game paints the meshes from Art/HighwayBoosters. The heights
where a squishy touches each piece are Config.Economy.Highway.course.touch.
The script stops with an error when a piece breaks a limit below.
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
	raise SystemExit("usage: blender --background --factory-startup --python highway_boosters.py -- <out_dir>")
OUT = os.path.abspath(ARGV[0])
os.makedirs(OUT, exist_ok=True)

MAX_TRIS = 4000  # a piece; the skill's "medium" ceiling: 35 of them stand on the lane at once
MAX_KEYS = 7  # a piece's MeshParts
MAX_Z = 14  # = Config course.clearStuds: a roll carries that far past a spot, and spots keep that far off the pads
MAX_X = 15  # over the rails (x +-14)
WIDE = {"dh_wing_gate": 23, "dh_halo_ring": 17.5}  # their wings reach out over the rails, as on the sheet
UV_STUDS = 2.0  # one stud tile every 2 studs, like Diego's lobby meshes
D = math.pi / 180
TAU = 2 * math.pi

GOLD = "FFD21F"
HOT = "FF2E93"
PINK = "FF6FC0"
CYAN = "35F0FF"
WHITE = "FFFFFF"

PIECES = {}


def piece(pid, pal):
	def wrap(fn):
		PIECES[pid] = (pal, fn)
		return fn
	return wrap


# -------------------------------------------------------------------------------------------------------- shapes


def star_pts(radius, inner=0.45):
	return [(math.cos(math.pi / 2 + i * math.pi / 5) * (radius * inner if i % 2 else radius),
		math.sin(math.pi / 2 + i * math.pi / 5) * (radius * inner if i % 2 else radius)) for i in range(10)]


def chevron(w, t, h):  # an arrow head pointing to local +Y
	return [(-w, -h), (0, h - t), (w, -h), (w, -h + t * 1.4), (0, h), (-w, -h + t * 1.4)]


def wing_pts(s):  # concept-kit.js wingPts
	pts = [(0, 0.1), (0.55, 0), (0.62, 0.3), (1.05, 0.28), (1.12, 0.62), (1.55, 0.62), (1.6, 1.0), (1.95, 1.05),
		(1.75, 1.45), (1.1, 1.38), (0.45, 1.05), (0, 0.75)]
	return [(x * s, y * s) for x, y in pts]


def mirror(pts):
	return [(-x, y) for x, y in pts]


def straight(z, half, low, high):  # (height, tilt in degrees) of a straight ramp, rising to the front
	return low + (half - z) / (2 * half) * (high - low), math.degrees(math.atan2(high - low, 2 * half))


def curved(z, half, low, rise):  # the same for a ski-jump curve
	t = (half - z) / (2 * half)
	return low + rise * t * t, math.degrees(math.atan2(rise * 2 * t, 2 * half))


def curved_profile(half, low, rise, bottom, n=10):
	top = [(-half + 2 * half * i / n, curved(-half + 2 * half * i / n, half, low, rise)[0]) for i in range(n + 1)]
	return [(half, bottom), (-half, bottom)] + top


# ----------------------------------------------------------------------------------------------------- the kit


def seg_for(radius, low=8, high=32):  # segments by size: small details stay cheap
	return int(max(low, min(high, 2 * round(radius * 1.7))))


def soften(bm, offset, seg, angle=0.5):
	bm.edges.ensure_lookup_table()
	edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > angle]
	if edges and offset > 0:
		bmesh.ops.bevel(bm, geom=edges, offset=offset, offset_type="OFFSET", segments=seg, profile=0.5,
			affect="EDGES", clamp_overlap=True)


def bm_box(s, soft):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2]))
	soften(bm, min(soft, 0.45 * min(s)), 3 if soft >= 1 else 2)
	return bm


def bm_cyl(top_d, bottom_d, h, seg, soft):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=bottom_d / 2, radius2=top_d / 2, depth=h)
	for v in bm.verts:  # Blender's cone runs along Z: stand it up along Roblox Y
		x, y, z = v.co
		v.co = Vector((x, z, -y))
	soften(bm, min(soft, 0.45 * h), 2)
	return bm


def bm_tube(r_out, r_in, h, seg, soft):  # a pipe along Y
	bm = bmesh.new()
	rows = []
	for y, r in ((-h / 2, r_out), (h / 2, r_out), (h / 2, r_in), (-h / 2, r_in)):
		rows.append([bm.verts.new((r * math.cos(j / seg * TAU), y, r * math.sin(j / seg * TAU))) for j in range(seg)])
	for i in range(4):
		for j in range(seg):
			bm.faces.new((rows[i][j], rows[(i + 1) % 4][j], rows[(i + 1) % 4][(j + 1) % seg], rows[i][(j + 1) % seg]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	soften(bm, soft, 1)
	return bm


def bm_ball(d, seg, dome):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=d / 2)
	for v in bm.verts:  # poles along Y: the top stays round
		x, y, z = v.co
		v.co = Vector((x, z, -y))
	if dome:  # the lower half would be hidden
		bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.co.y < 0.001 for v in f.verts)], context="FACES")
	return bm


def bm_lathe(profile, seg):  # a (radius, y) outline turned round Y, bottom to top; radius 0 = a point
	bm = bmesh.new()
	rows = []
	for r, y in profile:
		rows.append([bm.verts.new((0, y, 0))] if r == 0 else
			[bm.verts.new((r * math.cos(j / seg * TAU), y, r * math.sin(j / seg * TAU))) for j in range(seg)])
	for a, b in zip(rows, rows[1:]):
		for j in range(seg):
			quad = [a[j % len(a)], a[(j + 1) % len(a)], b[(j + 1) % len(b)], b[j % len(b)]]
			bm.faces.new(list(dict.fromkeys(quad)))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def bm_ring(radius, tube, seg, sides):  # three.js TorusGeometry in the XY plane
	bm = bmesh.new()
	rows = []
	for j in range(seg):
		u = j / seg * TAU
		rows.append([bm.verts.new(((radius + tube * math.cos(i / sides * TAU)) * math.cos(u),
			(radius + tube * math.cos(i / sides * TAU)) * math.sin(u), tube * math.sin(i / sides * TAU)))
			for i in range(sides)])
	for j in range(seg):
		for i in range(sides):
			n, m = (j + 1) % seg, (i + 1) % sides
			bm.faces.new((rows[j][i], rows[n][i], rows[n][m], rows[j][m]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def bm_flat(pts, depth):  # a flat shape along Z, flat shaded
	bm = bmesh.new()
	lo = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
	hi = [bm.verts.new((x, y, depth / 2)) for x, y in pts]
	bm.faces.new(lo)
	bm.faces.new(hi)
	n = len(pts)
	for i in range(n):
		bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
	bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])  # the outlines are concave
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def lobes(radius, waves, sx=1.0, sz=1.0):  # a splat's outline: its radius at angle a; waves = (n, amplitude, phase)
	def r(a):
		k = 1 + sum(amp * math.sin(n * a + ph) for n, amp, ph in waves)
		return radius * k / math.sqrt((math.cos(a) / sx) ** 2 + (math.sin(a) / sz) ** 2)
	return r


def bm_blob(outline, profile, seg, top):  # rows (inset in studs, y) under the outline, a low dome on top at `top`
	bm = bmesh.new()
	rows = []
	for inset, y in profile:
		rows.append([bm.verts.new((max(0.05, outline(j / seg * TAU) - inset) * math.cos(j / seg * TAU), y,
			max(0.05, outline(j / seg * TAU) - inset) * math.sin(j / seg * TAU))) for j in range(seg)])
	for lo, hi in zip(rows, rows[1:]):
		for j in range(seg):
			bm.faces.new((lo[j], lo[(j + 1) % seg], hi[(j + 1) % seg], hi[j]))
	centre = bm.verts.new((0, top, 0))
	for j in range(seg):
		bm.faces.new((rows[-1][j], rows[-1][(j + 1) % seg], centre))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def bm_slab(profile, width, soft):  # a (z, y) outline stretched along X
	bm = bmesh.new()
	lo = [bm.verts.new((-width / 2, y, z)) for z, y in profile]
	hi = [bm.verts.new((width / 2, y, z)) for z, y in profile]
	bm.faces.new(lo)
	bm.faces.new(hi)
	n = len(profile)
	for i in range(n):
		bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	soften(bm, soft, 2)
	return bm


def rot_matrix(r):  # three.js Euler "XYZ" = Rx * Ry * Rz (degrees), as in the sheet
	if not r:
		return Matrix.Identity(4)
	return Matrix.Rotation(r[0] * D, 4, "X") @ Matrix.Rotation(r[1] * D, 4, "Y") @ Matrix.Rotation(r[2] * D, 4, "Z")


class Kit:
	def __init__(self, parts=None, base=None):
		self.parts = [] if parts is None else parts  # (key, bmesh in piece space, Roblox axes)
		self.base = base or Matrix.Identity(4)

	def g(self, p, r):  # a group at p turned by r
		return Kit(self.parts, self.base @ Matrix.Translation(Vector(p)) @ rot_matrix(r))

	def box(self, key, s, p, r=None, soft=0.5):
		self._put(key, bm_box(s, soft), p, r)

	def ubox(self, key, s, p, r=None, soft=0.5):  # p = the bottom's centre
		self._put(key, bm_box(s, soft), (p[0], p[1] + s[1] / 2, p[2]), r)

	def cyl(self, key, d, h, p, r=None, soft=0.3, seg=None):  # d = a diameter, or (top, bottom)
		top, bottom = d if isinstance(d, tuple) else (d, d)
		self._put(key, bm_cyl(top, bottom, h, seg or seg_for(max(top, bottom) / 2), soft), p, r)

	def ucyl(self, key, d, h, p, r=None, soft=0.3, seg=None):
		self.cyl(key, d, h, (p[0], p[1] + h / 2, p[2]), r, soft, seg)

	def ball(self, key, d, p, scale=(1, 1, 1), r=None, seg=None, dome=False):
		self._put(key, bm_ball(d, seg or seg_for(d * max(scale) / 2, 8, 28), dome), p, r, scale)

	def ring(self, key, radius, tube, p, r=None, seg=None):  # the hole along Z until turned
		self._put(key, bm_ring(radius, tube, seg or seg_for(radius, 12, 36), max(6, min(10, int(tube * 8)))), p, r)

	def tube(self, key, r_out, r_in, h, p, r=None, seg=None, soft=0.15):  # along Y until turned
		self._put(key, bm_tube(r_out, r_in, h, seg or seg_for(r_out, 12, 36), soft), p, r)

	def lathe(self, key, profile, p, r=None, seg=14, scale=(1, 1, 1)):
		self._put(key, bm_lathe(profile, seg), p, r, scale)

	def flat(self, key, pts, depth, p, r=None):
		self._put(key, bm_flat(pts, depth), p, r, smooth=False)

	def slab(self, key, profile, width, x=0, soft=0.5):
		self._put(key, bm_slab(profile, width, soft), (x, 0, 0))

	def blob(self, key, outline, h, p=(0, 0, 0), seg=40, edge=1.0):  # a goo puddle h high with a round edge
		rows = ((0, 0), (0.04 * edge, 0.45 * h), (0.25 * edge, 0.8 * h), (0.6 * edge, 0.96 * h), (1.1 * edge, h))
		self._put(key, bm_blob(outline, rows, seg, h + 0.12), p)

	def _put(self, key, bm, p, r=None, scale=(1, 1, 1), smooth=True):
		for f in bm.faces:
			f.smooth = smooth
		m = self.base @ Matrix.Translation(Vector(p)) @ rot_matrix(r) @ Matrix.Diagonal((*scale, 1))
		bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
		self.parts.append((key, bm))


# ------------------------------------------------------------------------------------------------- 1 Candy Meadow


@piece("cm_jelly_pad", {"base": ("FFF3B0", "Stud"), "ring": (HOT, "Smooth"), "jelly": (PINK, "Smooth"),
	"bean": (GOLD, "Smooth"), "light": (CYAN, "Neon")})  # the sheet's :280
def _(k):
	k.ucyl("base", 26, 1.2, (0, 0, 0))
	k.ring("ring", 11, 1.9, (0, 2.2, 0), (90, 0, 0))
	radius, height = 10.2, 6.3
	k.ball("jelly", radius * 2, (0, 2.2, 0), (1, height / radius, 1), dome=True)
	for i in range(12):
		a = i / 12 * TAU
		k.ball("light", 1.8, (11 * math.cos(a), 3.85, 11 * math.sin(a)), seg=6)
	for x, z, turn in ((-4.2, 3, 20), (3.6, 4, -30), (-3, -4.4, 60), (4.6, -3, 10), (0, 0, 40)):
		y = 2.2 + height * math.sqrt(max(0, 1 - (x * x + z * z) / radius ** 2))
		k.ball("bean", 2, (x, y, z), (1.5, 0.75, 0.8), (0, turn, 0))


@piece("cm_sprinkle_ramp", {"base": ("FFF3B0", "Stud"), "ramp": ("18D8B4", "Smooth"), "wall": (HOT, "Smooth"),
	"post": (GOLD, "Smooth"), "chev": ("FFF6A8", "Neon"), "cream": (WHITE, "Smooth")})  # the sheet's :281
def _(k):
	half, low, high = 13, 1.1, 10.5
	k.ubox("base", (25.6, 0.8, 27.6), (0, 0, 0), soft=0.3)
	k.slab("ramp", ((half, 0.8), (-half, 0.8), (-half, high), (half, low)), 20)
	for s in (-1, 1):
		k.slab("wall", ((half + 0.6, 0.8), (-half - 0.6, 0.8), (-half - 0.6, high + 2), (half + 0.6, low + 1.4)), 2.6, s * 11.3,
			soft=0.8)
		k.ball("post", 3.8, (s * 11.3, high + 3.1, -half + 1.1))
	for z in (8, 0, -8):
		y, tilt = straight(z, half, low, high)
		k.flat("chev", chevron(7, 2, 2.4), 0.3, (0, y + 0.12, z), (tilt - 90, 0, 0))
	sprinkles = ((-8, 10.5, "wall"), (7.6, 11, "post"), (-8.2, 4, "cream"), (8, 3.5, "wall"), (-7.8, -3.5, "post"),
		(8.2, -4, "cream"), (-8, -10.5, "wall"), (7.6, -10.8, "post"), (-3, 11.8, "cream"), (3.4, -11.8, "cream"))
	for i, (x, z, key) in enumerate(sprinkles):
		y, tilt = straight(z, half, low, high)
		k.box(key, (3.2, 1, 1), (x, y + 0.5, z), (tilt, i * 47 + 20, 0), soft=0.45)


# --------------------------------------------------------------------------------------------------- 2 Bakery Town


@piece("bt_toaster_cannon", {"base": ("B8C4E8", "Stud"), "body": ("1F8FFF", "Smooth"), "trim": (GOLD, "Smooth"),
	"toast": ("F6B860", "Smooth"), "crumb": ("FFE6B8", "Smooth"), "dark": ("16103A", "Smooth"),
	"knob": ("FF2E4D", "Smooth")})  # the sheet's :283
def _(k):
	k.ucyl("base", (24, 25), 1.4, (0, 0, 0))
	k.ucyl("base", (19, 20.4), 1.2, (0, 1.4, 0))
	for i in range(8):
		a = i / 8 * TAU + 0.39
		k.ball("trim", 1.3, (11.1 * math.cos(a), 1.5, 11.1 * math.sin(a)), seg=6)
	k.box("body", (18, 11.5, 12.5), (0, 8.4, 0), soft=2.4)
	for z in (-4.1, 4.1):
		k.box("trim", (18.7, 12.2, 1.7), (0, 8.4, z), soft=0.8)
	k.flat("trim", star_pts(3.2), 0.6, (0, 8.4, 6.5))
	for z in (-1.9, 1.9):
		k.box("dark", (13.6, 0.5, 2.4), (0, 14.2, z), soft=0.2)
		k.box("toast", (11.5, 7.5, 1.8), (0, 16, z), (-10, 0, 0), soft=1)
		k.box("crumb", (10, 6, 1.95), (0, 16.1, z), (-10, 0, 0), soft=0.8)
	k.cyl("dark", 1.6, 3.6, (10.5, 9, 0), (0, 0, 90))
	k.ball("knob", 3.6, (12.4, 9, 0))


@piece("bt_butter_slide", {"foil": ("FFF6EC", "Stud"), "stripe": ("FF3E5C", "Smooth"), "butter": ("FFD21F", "Smooth"),
	"melt": ("FFF6B8", "Smooth"), "chev": ("FF5A1F", "Neon")})  # the sheet's :284
def _(k):
	half, low, rise = 12.6, 1.4, 6.8
	k.ubox("foil", (25.4, 1.2, 27.6), (0, 0, 0), soft=0.4)
	for s in (-1, 1):
		k.ubox("stripe", (1.8, 1.8, 27.6), (s * 11.8, 0.1, 0), soft=0.6)
	k.slab("butter", curved_profile(half, low, rise, 1), 20, soft=0.9)
	y, tilt = curved(-7.6, half, low, rise)
	k.box("butter", (9.5, 4.6, 8), (0, y + 1.9, -7.6), (tilt, 0, 0), soft=1.2)  # the pat
	k.ball("melt", 2, (0, y + 4.1, -7.6), (4.3, 0.7, 3.6), (tilt, 0, 0), seg=16)
	for x, z, w, d in ((0, -3, 6.2, 5.6), (-0.7, 0, 5.8, 5.8), (0.6, 3.2, 6, 5.6), (-0.4, 6.4, 7, 5.4), (0.4, 9.4, 8.6, 4.6)):
		y, tilt = curved(z, half, low, rise)
		k.ball("melt", 2, (x, y, z), (w / 2, 0.55, d / 2), (tilt, 0, 0), seg=12)
	for x, z in ((-10.1, 5), (10.1, -2), (-10.1, -7)):  # melted drips over the sides
		y = curved(z, half, low, rise)[0]
		k.ball("melt", 2, (x, y - 0.2, z), (0.9, 1.4, 1.5), seg=10)
	for x, z in ((-6.9, 7), (6.9, 7), (-6.9, 0.5), (6.9, 0.5)):
		y, tilt = curved(z, half, low, rise)
		k.flat("chev", chevron(2.7, 1.2, 1.7), 0.3, (x, y + 0.1, z), (tilt - 90, 0, 0))


# --------------------------------------------------------------------------------------------------- 3 Boba Lagoon


@piece("bl_pearl_bouncer", {"base": ("35D8C8", "Stud"), "ring": (HOT, "Smooth"), "pearl": ("4A2460", "Smooth"),
	"shine": (WHITE, "Smooth"), "light": (GOLD, "Neon")})  # the sheet's :286
def _(k):
	k.ucyl("base", 26, 1.2, (0, 0, 0))
	k.ring("ring", 11.6, 1.1, (0, 1.6, 0), (90, 0, 0))
	r = 5.3
	spots = [(6.1 * math.cos(i / 3 * TAU + 0.5), 1.2 + r, 6.1 * math.sin(i / 3 * TAU + 0.5)) for i in range(3)]
	spots.append((0, 1.2 + r + 8.67, 0))
	for x, y, z in spots:
		k.ball("pearl", r * 2, (x, y, z))
		k.ball("shine", 2.4, (x + 1.6, y + 3.1, z + 3.2), (1, 0.7, 1), seg=8)
	for i in range(10):
		a = i / 10 * TAU
		k.ball("light", 1.2, (11.6 * math.cos(a), 2.6, 11.6 * math.sin(a)), seg=6)


@piece("bl_straw_tube", {"base": ("35D8C8", "Stud"), "foot": (GOLD, "Smooth"), "pink": ("FF3E96", "Smooth"),
	"white": (WHITE, "Smooth"), "rim": (CYAN, "Neon")})  # the sheet's :287, round like a real straw
def _(k):
	k.ubox("base", (21, 0.8, 27), (0, 0, 0), soft=0.3)
	for z, h in ((-7.5, 2.8), (7.5, 2)):
		k.ubox("foot", (20, h, 3.4), (0, 0.8, z), soft=0.8)
	straw = k.g((0, 11.4, 0), (5, 0, 0))
	step = 24 / 5
	for i in range(5):
		straw.tube("pink" if i % 2 == 0 else "white", 9.4, 7.8, step, (0, 0, -12 + step * (i + 0.5)), (90, 0, 0), soft=0)
	for z in (-12, 12):
		straw.ring("rim", 8.6, 1.05, (0, 0, z))


# ------------------------------------------------------------------------------------------- 4 Frozen Dessert Peaks


@piece("fd_ice_slide", {"base": ("6FB8FF", "Stud"), "ice": ("5FE3FF", "Smooth"), "curb": ("1F8FFF", "Smooth"),
	"snow": (WHITE, "Smooth"), "cherry": ("FF2E93", "Smooth"), "chev": (WHITE, "Neon")})  # the sheet's :289
def _(k):
	half, low, rise = 13, 1.1, 8.6
	k.ubox("base", (25.6, 0.8, 27.6), (0, 0, 0), soft=0.3)
	k.slab("ice", curved_profile(half, low, rise, 0.8), 20, soft=0.5)
	for s in (-1, 1):
		k.slab("curb", curved_profile(half + 0.5, low + 1.6, rise, 0.8), 2.6, s * 11.3, soft=0.8)
		for z in (8.5, 0.5):
			k.ball("snow", 3.4, (s * 11.3, curved(z, half + 0.5, low + 1.6, rise)[0] + 0.7, z), (1, 0.8, 1.3))
		k.ball("snow", 5.2, (s * 11.3, low + rise + 3.4, -half + 1.9))
		k.ball("cherry", 1.8, (s * 11.3, low + rise + 6.2, -half + 1.9), seg=8)
	for z in (8, 0, -8):
		y, tilt = curved(z, half, low, rise)
		k.flat("chev", chevron(7, 2, 2.4), 0.3, (0, y + 0.12, z), (tilt - 90, 0, 0))


@piece("fd_cone_cannon", {"base": ("DFF4FF", "Stud"), "cheek": ("3FA8FF", "Smooth"), "trim": (GOLD, "Smooth"),
	"cone": ("E8A050", "Smooth"), "band": ("B86A28", "Smooth"), "scoop": ("FF6FB8", "Smooth"),
	"cherry": ("FF2E4D", "Smooth")})  # the sheet's :290
def _(k):
	k.ucyl("base", (23, 24), 1.4, (0, 0, 0))
	k.ucyl("base", (17, 19), 1.4, (0, 1.4, 0))
	for s in (-1, 1):
		k.box("cheek", (2.4, 9, 8.5), (s * 6.2, 7, 3.5), soft=1)
		k.cyl("trim", 3.4, 0.8, (s * 7.6, 8.2, 3.5), (0, 0, 90), soft=0.2)
	for i in range(6):
		a = i / 6 * TAU + 0.52
		k.ball("trim", 1.3, (10.6 * math.cos(a), 1.5, 10.6 * math.sin(a)), seg=6)
	barrel = k.g((0, 7.6, 3.7), (-50, 0, 0))
	barrel.cyl("cone", (14.4, 6.8), 18, (0, 5, 0), soft=0.4)
	for y, r in ((1.8, 4.6), (6.3, 5.6), (10.8, 6.6)):
		barrel.ring("band", r, 0.5, (0, y, 0), (90, 0, 0), seg=16)
	barrel.ring("scoop", 7.2, 1.3, (0, 14, 0), (90, 0, 0))
	barrel.ball("scoop", 12.8, (0, 14.4, 0), dome=True)
	barrel.ball("cherry", 2.8, (0, 21, 0), seg=10)
	barrel.flat("trim", star_pts(2.6), 0.5, (0, 6, 5.5), (12, 0, 0))


# --------------------------------------------------------------------------------------------------- 5 Lava Volcano


FLAME = ((0, 0), (2.6, 1), (4.3, 3.6), (4.2, 6.6), (3, 9.6), (1.5, 12.8), (0, 16.6))


@piece("lv_fire_jet", {"base": ("6A3A5C", "Stud"), "rock": ("4A2546", "Smooth"), "glow": ("FF5A1F", "Neon"),
	"mid": ("FFB03A", "Neon"), "core": ("FFF0A0", "Neon")})  # the sheet's :292
def _(k):
	k.ucyl("base", (24, 25), 1.2, (0, 0, 0))
	k.ring("glow", 11.3, 0.8, (0, 1.5, 0), (90, 0, 0))
	k.lathe("rock", ((9.8, 1.2), (8.4, 3.2), (6.6, 5.6), (5.5, 7.5), (5.7, 8.6), (4.7, 8.9), (0, 8.2)), (0, 0, 0), seg=16)
	for i in range(6):  # cracks of lava down the rock
		a = i / 6 * TAU + 0.26
		k.box("glow", (0.9, 6.4, 0.5), (7.75 * math.cos(a), 4.5, 7.75 * math.sin(a)), (0, -a / D, 33), soft=0.2)
	k.lathe("glow", FLAME, (0, 7.6, 0), seg=12)
	for s in (-1, 1):
		k.lathe("glow", FLAME, (s * 3.6, 7.8, 0), (0, 0, -s * 22), seg=10, scale=(0.62, 0.66, 0.62))
		k.lathe("mid", FLAME, (0, 7.8, s * 2.9), (s * 10, 0, 0), seg=10, scale=(0.66, 0.74, 0.5))
		k.lathe("core", FLAME, (0, 7.9, s * 4.5), (s * 14, 0, 0), seg=8, scale=(0.38, 0.42, 0.3))


@piece("lv_magma_ramp", {"base": ("6A3A5C", "Stud"), "ramp": ("7A2E3A", "Smooth"), "wall": ("FF4D1F", "Smooth"),
	"seam": ("FF9A1F", "Neon"), "rock": ("3A2340", "Smooth")})  # the sheet's :293
def _(k):
	half, low, high = 13, 1.1, 10.5
	k.ubox("base", (25.6, 0.8, 27.6), (0, 0, 0), soft=0.3)
	k.slab("ramp", ((half, 0.8), (-half, 0.8), (-half, high), (half, low)), 20)
	for s in (-1, 1):
		k.slab("wall", ((half + 0.6, 0.8), (-half - 0.6, 0.8), (-half - 0.6, high + 2), (half + 0.6, low + 1.4)), 2.6, s * 11.3,
			soft=0.8)
		k.ball("rock", 5, (s * 11.2, high + 3.2, -half + 1.8), (1, 0.85, 1), seg=8)
		k.ball("rock", 3.4, (s * 11.4, low + 3, half - 1.5), (1, 0.8, 1.1), seg=8)
	for z in (8, 0, -8):
		y, tilt = straight(z, half, low, high)
		k.flat("seam", chevron(7, 2, 2.4), 0.3, (0, y + 0.12, z), (tilt - 90, 0, 0))
	for x, z, turn in ((-7.5, 11, 25), (7.5, 4, -35), (-8, -4, 60), (7.8, -11, 15)):
		y, tilt = straight(z, half, low, high)
		k.box("rock", (3.2, 1.2, 2.2), (x, y + 0.5, z), (tilt, turn, 0), soft=0.5)


# --------------------------------------------------------------------------------------------------- 6 Rainbow Road


@piece("rr_star_ring", {"base": ("B98CFF", "Stud"), "post": ("6F5CFF", "Smooth"), "halo": ("FF4FA3", "Smooth"),
	"hoop": ("FFD84A", "Neon"), "star": (WHITE, "Neon")})  # the sheet's :295
def _(k):
	y = 13.5
	k.ucyl("base", (21, 22), 1.2, (0, 0, 0))
	k.ring("hoop", 9, 1.1, (0, y, 0))
	k.ring("halo", 10.6, 0.6, (0, y, 0))
	for s in (-1, 1):
		k.ucyl("post", (2.2, 3.4), y - 1.2, (s * 10.9, 1.2, 0), soft=0.4)
		k.ball("halo", 3.4, (s * 10.9, y + 0.2, 0))
	k.flat("star", star_pts(3.4), 1, (0, y + 13.2, 0))
	for s in (-1, 1):
		k.flat("star", star_pts(1.6), 0.6, (s * 6.4, y + 9.6, 0))


@piece("rr_comet_pad", {"base": ("6F5CFF", "Stud"), "pad": ("A06BFF", "Smooth"), "fin": ("FF4FA3", "Smooth"),
	"chev": (WHITE, "Neon"), "star": ("FFD84A", "Neon"), "tail": ("FF5C8A", "Neon")})  # the sheet's :296
def _(k):
	half, low, high = 13, 1.1, 4.6
	k.ubox("base", (25.6, 0.8, 27.6), (0, 0, 0), soft=0.3)
	k.slab("pad", ((half, 0.8), (-half, 0.8), (-half, high), (half, low)), 20)
	for s in (-1, 1):
		k.slab("fin", ((half + 0.6, 0.8), (-half - 0.6, 0.8), (-half - 0.6, 11), (-half + 5, 11), (half + 0.6, 2.8)), 2.4, s * 11.2,
			soft=0.9)
		k.flat("star", star_pts(2.2), 0.8, (s * 11.2, 13.4, -half + 1.2))
	for z in (-2.5, 5):
		y, tilt = straight(z, half, low, high)
		k.flat("chev", chevron(6.2, 2.1, 2.7), 0.3, (0, y + 0.12, z), (tilt - 90, 0, 0))
	y, tilt = straight(-9.5, half, low, high)
	k.flat("star", star_pts(3.6), 0.4, (0, y + 0.15, -9.5), (tilt - 90, 0, 0))
	y, tilt = straight(0.5, half, low, high)
	for x in (-8.2, 8.2):
		k.box("tail", (1.5, 0.3, 24), (x, y + 0.08, 0.5), (tilt, 0, 0), soft=0.1)


# -------------------------------------------------------------------------------------------------- 7 Divine Heaven


def clouds(k, key, x0, spots):
	for x, z, d in spots:
		k.ball(key, d, (x0 + x, d * 0.36 + 0.05, z), (1, 0.72, 1), seg=8)


def wing(k, s, size, depth, at):
	pts = wing_pts(size) if s > 0 else mirror(wing_pts(size))
	k.flat("gold", wing_pts(size * 1.1) if s > 0 else mirror(wing_pts(size * 1.1)), depth * 0.7, (at[0], at[1] - 0.15 * size, at[2]))
	k.flat("wing", pts, depth, at)


@piece("dh_wing_gate", {"plinth": ("FFD76A", "Stud"), "marble": (WHITE, "Smooth"), "gold": ("FFB300", "Smooth"),
	"wing": (WHITE, "Smooth"), "halo": ("FFE36A", "Neon"), "cloud": ("BFE8FF", "Smooth")})  # the sheet's :298
def _(k):
	for s in (-1, 1):
		k.ucyl("plinth", (6, 7), 1.4, (s * 10.5, 0, 0))
		clouds(k, "cloud", s * 10.5, ((2.6, 2.2, 5), (-2.8, 2, 4.4), (0.6, -2.8, 5.4)))
		k.ucyl("marble", (3.6, 4.4), 16, (s * 10.5, 1.4, 0), soft=0.3)
		for y in (6, 11.5):
			k.cyl("gold", 4.7, 1, (s * 10.5, y, 0), soft=0.3)
		k.ucyl("gold", (5.8, 4.6), 1.8, (s * 10.5, 17.4, 0), soft=0.4)
		wing(k, s, 4.9, 0.9, (s * 11.8, 10.5, 0))
	k.box("marble", (25, 2.6, 3.2), (0, 20.4, 0), soft=0.8)
	k.box("gold", (25.8, 1, 3.6), (0, 21.8, 0), soft=0.3)
	k.ring("gold", 3.9, 0.45, (0, 26.4, 0))
	k.ring("halo", 3.1, 0.75, (0, 26.4, 0))


@piece("dh_halo_ring", {"plinth": ("FFD76A", "Stud"), "gold": ("FFB300", "Smooth"), "halo": ("FFE36A", "Neon"),
	"wing": (WHITE, "Smooth")})  # the sheet's :299
def _(k):
	y = 12
	k.ucyl("plinth", (16, 18), 1.4, (0, 0, 0))
	clouds(k, "wing", 0, ((-5, 3, 7), (5.2, 2.6, 6.4), (0.6, -4.4, 7.4), (-4.4, -3, 5.4), (4.6, -3.2, 5.2)))
	k.ring("gold", 9.4, 1.4, (0, y, 0))
	k.ring("halo", 7.6, 0.7, (0, y, 0))
	for s in (-1, 1):
		wing(k, s, 3.1, 0.8, (s * 10.4, y - 2, 0))
	k.flat("gold", star_pts(2.2), 0.7, (0, y + 12.2, 0))


# ------------------------------------------------------------------------------------------------------- Blender


def linear(hexstr):
	out = []
	for i in (0, 2, 4):
		c = int(hexstr[i:i + 2], 16) / 255
		out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
	return (*out, 1.0)


def append(dst, src):
	vmap = {v: dst.verts.new(v.co) for v in src.verts}
	for f in src.faces:
		dst.faces.new([vmap[v] for v in f.verts]).smooth = f.smooth


def stud_uvs(bm):
	"""Box-projected UVs in studs / UV_STUDS, like Diego's lobby meshes."""
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
manifest = {"uvStuds": UV_STUDS, "objects": {}, "pieces": {}}
piece_objects = {}
problems = []

for pid, (pal, build) in PIECES.items():
	kit = Kit()
	build(kit)
	merged = {}
	for key, bm in kit.parts:
		if key not in pal:
			problems.append(f"{pid}: no palette key {key}")
		merged.setdefault(key, bmesh.new())
		append(merged[key], bm)
		bm.free()
	objs = []
	lows, highs, tris = [], [], 0
	for key, bm in merged.items():
		bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.co.y < 0.02 for v in f.verts)], context="FACES")  # on the lane
		stud_uvs(bm)
		cos = [v.co.copy() for v in bm.verts]
		lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
		hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
		lows.append(lo)
		highs.append(hi)
		for v in bm.verts:
			v.co = Vector((v.co.x, -v.co.z, v.co.y))
		bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
		name = f"{pid}__{key}"
		me = bpy.data.meshes.new(name)
		bm.to_mesh(me)
		bm.free()
		obj = bpy.data.objects.new(name, me)
		LIB.objects.link(obj)
		obj.modifiers.new("Normals", "WEIGHTED_NORMAL").keep_sharp = True  # big faces stay flat, the bevels stay round
		objs.append(obj)
		tris += len(me.polygons)
		manifest["objects"][name] = {
			"piece": pid,
			"key": key,
			"center": [round((lo[i] + hi[i]) / 2, 4) for i in range(3)],
			"size": [round(hi[i] - lo[i], 4) for i in range(3)],
			"tris": len(me.polygons),
		}
	lo = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
	hi = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
	manifest["pieces"][pid] = {"tris": tris, "keys": len(objs), "min": [round(c, 2) for c in lo], "max": [round(c, 2) for c in hi]}
	piece_objects[pid] = objs
	print(pid, "tris", tris, "keys", len(objs), "x", round(lo.x, 1), round(hi.x, 1), "y", round(lo.y, 1), round(hi.y, 1), "z",
		round(lo.z, 1), round(hi.z, 1))
	if tris > MAX_TRIS:
		problems.append(f"{pid}: {tris} tris, the limit is {MAX_TRIS}")
	if len(objs) > MAX_KEYS:
		problems.append(f"{pid}: {len(objs)} keys, the limit is {MAX_KEYS}")
	if max(abs(lo.z), abs(hi.z)) > MAX_Z:
		problems.append(f"{pid}: reaches z {round(lo.z, 2)} .. {round(hi.z, 2)}, the limit is +-{MAX_Z}")
	if max(abs(lo.x), abs(hi.x)) > WIDE.get(pid, MAX_X):
		problems.append(f"{pid}: reaches x {round(lo.x, 2)} .. {round(hi.x, 2)}, the limit is +-{WIDE.get(pid, MAX_X)}")
	if lo.y < -0.01:
		problems.append(f"{pid}: goes under the lane top ({round(lo.y, 2)})")

with open(os.path.join(OUT, "manifest.json"), "w") as f:
	json.dump(manifest, f, indent=1)
if problems:
	raise SystemExit("highway_boosters: " + "; ".join(problems))

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

# ----------------------------------------------------------------------------------------------------- previews


def material(name, hexstr, kind):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Base Color"].default_value = linear(hexstr)
	b.inputs["Roughness"].default_value = {"Smooth": 0.28, "Stud": 0.8, "Neon": 0.4}[kind]
	if kind == "Neon":
		b.inputs["Emission Color"].default_value = linear(hexstr)
		b.inputs["Emission Strength"].default_value = 1.2
	return m


for pid, objs in piece_objects.items():
	pal = PIECES[pid][0]
	for o in objs:
		hexstr, kind = pal[o.name.split("__")[1]]
		o.data.materials.append(material(o.name, hexstr, kind))

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
bg.inputs["Color"].default_value = linear("BFE6FF")
bg.inputs["Strength"].default_value = 0.62
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 2.3
sun.rotation_euler = (40 * D, 10 * D, -35 * D)
scene.collection.objects.link(sun)

STAGE = bpy.data.collections.new("Stage")
scene.collection.children.link(STAGE)


def stage_box(hexstr, size, at):  # Roblox axes
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	me = bpy.data.meshes.new("stage")
	for v in bm.verts:
		v.co = Vector((v.co.x * size[0] + at[0], -(v.co.z * size[2] + at[2]), v.co.y * size[1] + at[1]))
	bm.to_mesh(me)
	bm.free()
	o = bpy.data.objects.new("stage", me)
	o.data.materials.append(material("stage", hexstr, "Stud"))
	STAGE.objects.link(o)
	return o


# the lane top and the ground of each zone (Art/Palette), and the rails
ZONES = {"cm": ("FFE3EF", "9EE89B"), "bt": ("F2C487", "F3D9A4"), "bl": ("EED6B8", "7FD8D0"), "fd": ("DFF4FF", "F4FBFF"),
	"lv": ("4A3B4F", "3A2C3A"), "rr": ("FF9C5B", "BFE6FF"), "dh": ("FFF6EC", "BFE6FF")}
lanes = {}
for zone, (lane, ground) in ZONES.items():
	parts = [stage_box(lane, (26, 1, 120), (0, -0.5, 0)), stage_box(ground, (500, 1, 500), (0, -2, 0))]
	for s in (-1, 1):
		parts.append(stage_box("FF8FBF", (0.6, 0.6, 120), (s * 14, 1, 0)))
	lanes[zone] = parts
figure = [stage_box("2E7BFF", (0.9, 2, 0.9), (-10.5 - 0.5, 1, 13)), stage_box("2E7BFF", (0.9, 2, 0.9), (-10.5 + 0.5, 1, 13)),
	stage_box("FF4D4D", (2, 2, 1), (-10.5, 3, 13)), stage_box("FFD21F", (0.9, 2, 0.9), (-10.5 - 1.5, 3, 13)),
	stage_box("FFD21F", (0.9, 2, 0.9), (-10.5 + 1.5, 3, 13)), stage_box("FFD21F", (1.2, 1.2, 1.2), (-10.5, 4.6, 13))]

cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.type = "ORTHO"
cam_data.clip_end = 5000
cam_data.ortho_scale = 62
cam = bpy.data.objects.new("PreviewCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
yaw, pitch = -32 * D, 24 * D
d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
cam.location = Vector((0, 0, 11)) + d * 300
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x, scene.render.resolution_y = 640, 520
scene.render.resolution_percentage = 100

for pid, objs in piece_objects.items():
	for o in LIB.objects:
		o.hide_render = o not in objs
	for zone, parts in lanes.items():
		for o in parts:
			o.hide_render = zone != pid[:2]
	scene.render.filepath = os.path.join(OUT, f"{pid}.png")
	bpy.ops.render.render(write_still=True)
print("DONE")
