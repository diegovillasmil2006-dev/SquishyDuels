"""Squishy Duels gear models: every tier of the 4 gear lines its own look (big job item 9, 2026-11-10).

The 14 launchers (held h1..h7, platform p1..p7) are the owner's "Launchers & Biomes - Concept Sheet" (Desktop "jason
designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:129-185), copied part by part with the sheet's own kit letters
(u b c s o e r w bar g, below) at their rest pose (pose(k, 0)). The arm gear and the armor (7 + 7) have no design: they
are Claude's, built from the same kit and each zone's colours of that sheet, sized for an R15 arm and chest. Blocky, as
the owner's style rule asks (chamfered boxes, 8-sided cylinders, low spheres), each piece with a dark outline hull.
Run it as its own Blender process (highway_boosters.py is the shape library; importing it builds nothing):

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python gear_models.py -- <out_dir>

Writes <out_dir>/SD_Gear_<line>.fbx and .glb (per piece one object per colour key "<id>__<key>" and its hull
"<id>__Outline", all at the piece's origin), manifest.json (each object's centre and size in Roblox axes; each piece's
line, tier, tris, bounds, grip and colours) and previews (<id>.png). 1 Blender unit = 1 stud; points are computed in
Roblox axes (X right, Y up, Z back; a launcher's front is -Z) and written as (X, -Z, Y), so a "+Y up" export gives back
Roblox axes. A piece's origin: a held launcher's bottom (its `grip` = where the hand holds it), a platform launcher's
floor centre, an arm piece's lower-arm centre (Y along the arm), an armor's upper-torso centre.
The script stops with an error when a piece breaks a limit below.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import highway_boosters as kit  # noqa: E402  the shape helpers and the out dir (argv)

OUT = kit.OUT
D = math.pi / 180
INK = "1C1530"  # Diego's outline ink (Art/Palette)
LIMITS = {  # per line: (tris with the hull, keys, half width x, height y, half depth z, hull thickness, chamfer)
	"held": (3200, 9, 2.0, 4.0, 3.0, 0.045, 0.04),
	"platform": (6500, 10, 3.2, 14.0, 5.6, 0.09, 0.1),
	"arm": (2600, 7, 1.3, 1.6, 1.6, 0.04, 0.035),
	"armor": (3200, 8, 2.4, 3.0, 1.6, 0.045, 0.04),
}

PIECES = {}  # id -> (line, tier, palette key -> (hex, kind), build, grip)


def piece(line, tier, pal, grip=(0, 0, 0)):
	def wrap(fn):
		PIECES[f"{line}_{tier}"] = (line, tier, pal, fn, grip)
		return fn
	return wrap


def bm_arc(radius, tube, seg, arc):  # three.js TorusGeometry with an arc: an open ring in the XY plane, 4-sided
	bm = bmesh.new()
	rows = []
	for j in range(seg + 1):
		u = j / seg * arc
		rows.append([bm.verts.new(((radius + tube * math.cos(i / 4 * kit.TAU)) * math.cos(u),
			(radius + tube * math.cos(i / 4 * kit.TAU)) * math.sin(u), tube * math.sin(i / 4 * kit.TAU))) for i in range(4)])
	for j in range(seg):
		for i in range(4):
			m = (i + 1) % 4
			bm.faces.new((rows[j][i], rows[j + 1][i], rows[j + 1][m], rows[j][m]))
	bm.faces.new(rows[0])
	bm.faces.new(rows[-1])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def bm_cbox(s, soft):  # a box with one flat chamfer on every edge: the blocky look, 44 triangles
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2]))
	offset = min(soft, 0.3 * min(s))
	if offset > 0.004:
		bmesh.ops.bevel(bm, geom=list(bm.edges), offset=offset, offset_type="OFFSET", segments=1, profile=0.5,
			affect="EDGES", clamp_overlap=True)
	return bm


def bm_prism(top_d, bottom_d, h, seg):  # the sheet's CylinderGeometry: a faceted prism or cone along Y
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=bottom_d / 2, radius2=top_d / 2, depth=h)
	for v in bm.verts:  # Blender's cone runs along Z: stand it up along Roblox Y
		x, y, z = v.co
		v.co = Vector((x, z, -y))
	return bm


class G(kit.Kit):
	"""The sheet's kit letters (concept-kit.js class K) on the shape library, kept blocky (flat faces, one chamfer)."""

	soft = 0.05

	def g(self, p, r=None):
		child = G(self.parts, self.base @ Matrix.Translation(Vector(p)) @ kit.rot_matrix(r))
		child.soft = self.soft
		return child

	def b(self, key, s, p, r=None):
		self._put(key, bm_cbox(s, self.soft), p, r, smooth=False)

	def u(self, key, s, p, r=None):  # p = the bottom's centre
		self.b(key, s, (p[0], p[1] + s[1] / 2, p[2]), r)

	def c(self, key, d, h, p, r=None, seg=8):  # d = a diameter or (top, bottom)
		top, bottom = d if isinstance(d, (list, tuple)) else (d, d)
		self._put(key, bm_prism(top, bottom, h, seg), p, r, smooth=False)

	def s(self, key, d, p):
		self.ball(key, d, p, seg=10)

	def o(self, key, d, p, r=None):  # an octahedron gem
		self._put(key, kit.bm_lathe(((0, -d / 2), (d / 2, 0), (0, d / 2)), 4), p, r, smooth=False)

	def e(self, key, pts, depth, p, r=None):  # a flat outline in XY, `depth` thick along Z
		self.flat(key, [tuple(q) for q in pts], depth, p, r)

	def r(self, key, radius, tube, p, r=None, seg=12, arc=None):  # a ring in the XY plane until turned
		bm = kit.bm_ring(radius, tube, seg, 4) if arc is None else bm_arc(radius, tube, seg, arc)
		self._put(key, bm, p, r)

	def w(self, key, s, p, r=None):  # a wedge: w wide (X), low at -Z, h tall at +Z
		w, h, d = s
		bm = kit.bm_flat([(-d / 2, -h / 2), (d / 2, -h / 2), (d / 2, h / 2)], w)
		bmesh.ops.transform(bm, matrix=Matrix.Rotation(-90 * D, 4, "Y"), verts=bm.verts)
		self._put(key, bm, p, r, smooth=False)

	def bar(self, key, a, b, t):  # a box beam from a to b, t = a thickness or (wide, tall)
		va, vb = Vector(a), Vector(b)
		d = vb - va
		tw, th = t if isinstance(t, (list, tuple)) else (t, t)
		bm = bm_cbox((tw, th, d.length), self.soft)
		turn = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
		bmesh.ops.transform(bm, matrix=turn, verts=bm.verts)
		self._put(key, bm, tuple((va + vb) / 2), smooth=False)


S2 = (-1, 1)

# ------------------------------------------------------------------------------------------- held launchers (sheet)


@piece("held", 1, {"stick": ("FFF6EC", "Smooth"), "wrap": ("FF8FBF", "Smooth"), "disc": ("FF8FBF", "Glass"),
	"swirl": ("FFD84A", "Smooth"), "band": ("FF9ED2", "Smooth"), "pouch": ("FF5C8A", "Smooth")}, grip=(0, 0.6, 0))
def _(k):  # Lolli Sling (:130)
	k.u("stick", (0.32, 1.3, 0.32), (0, 0, 0))
	k.u("wrap", (0.4, 0.62, 0.4), (0, 0.22, 0))
	k.u("stick", (1.0, 0.3, 0.34), (0, 1.25, 0))
	for s in S2:
		k.b("stick", (0.28, 0.95, 0.28), (s * 0.42, 1.95, 0), (0, 0, -s * 12))
		k.c("disc", 1.05, 0.3, (s * 0.56, 2.55, 0), (90, 0, 0))
		k.c("swirl", 0.52, 0.36, (s * 0.56, 2.55, 0), (90, 0, 0))
		k.bar("band", (s * 0.56, 2.5, 0.12), (s * 0.24, 2.5, 0.12), 0.08)
	k.b("pouch", (0.5, 0.36, 0.22), (0, 2.5, 0.12))


@piece("held", 2, {"limb": ("E8A55A", "Smooth"), "tip": ("C9803F", "Smooth"), "butter": ("FFE36E", "Smooth"),
	"foil": ("FFF6EC", "Smooth"), "string": ("FFF6EC", "Smooth")}, grip=(0, 1.65, 0))
def _(k):  # Butter Bow (:134)
	g = 1.65
	k.b("butter", (0.44, 0.8, 0.44), (0, g, 0))
	k.b("foil", (0.5, 0.3, 0.5), (0, g, 0))
	for s in S2:
		k.bar("limb", (0, g + s * 0.38, 0), (0, g + s * 1.0, 0.3), (0.52, 0.36))
		k.bar("limb", (0, g + s * 1.0, 0.3), (0, g + s * 1.42, 0.42), (0.44, 0.3))
		k.bar("tip", (0, g + s * 1.42, 0.42), (0, g + s * 1.62, 0.26), 0.26)
		k.bar("string", (0, g + s * 1.42, 0.42), (0, g, 0.42), 0.06)
	k.b("butter", (0.38, 0.24, 0.3), (0, g, 0.54))


@piece("held", 3, {"body": ("EED6B8", "Smooth"), "grip": ("3FCFC0", "Smooth"), "cup": ("EED6B8", "Glass"),
	"pearl": ("3B2630", "Smooth"), "lid": ("FFF6EC", "Smooth"), "straw": ("FF6FA3", "Smooth"),
	"pump": ("FF6FA3", "Smooth")}, grip=(0, 0.55, 0.38))
def _(k):  # Boba Blaster (:138)
	k.b("grip", (0.46, 1.05, 0.56), (0, 0.55, 0.38), (-12, 0, 0))
	k.b("grip", (0.12, 0.32, 0.14), (0, 0.82, -0.18))
	k.b("body", (0.72, 0.62, 1.7), (0, 1.25, 0.05))
	k.c("straw", 0.34, 1.55, (0, 1.3, -1.45), (90, 0, 0))
	k.c("lid", 0.48, 0.2, (0, 1.3, -2.2), (90, 0, 0))
	k.c("cup", (0.78, 0.62), 0.95, (0, 2.03, 0.15))
	k.c("lid", 0.84, 0.12, (0, 2.56, 0.15))
	k.s("pearl", 0.24, (-0.13, 1.72, 0.08))
	k.s("pearl", 0.24, (0.14, 1.7, 0.24))
	k.s("pearl", 0.22, (0.02, 1.9, 0.02))
	k.b("pump", (0.5, 0.34, 0.66), (0, 0.95, -1.1))


@piece("held", 4, {"cone": ("F2C487", "Smooth"), "stick": ("E0A062", "Smooth"), "mitt": ("8FD8FF", "Smooth"),
	"hinge": ("D9F3FF", "Smooth"), "spring": ("CFEFFF", "Smooth"), "arm": ("BDEBFF", "Smooth"),
	"scoop": ("8FD8FF", "Smooth")}, grip=(0, 0.95, 0))
def _(k):  # Frosty Flick (:142)
	k.c("cone", (0.6, 0.12), 0.55, (0, 0.275, 0), None, 6)
	k.u("stick", (0.38, 1.35, 0.22), (0, 0.5, 0))
	k.u("mitt", (0.48, 0.6, 0.34), (0, 0.65, 0))
	k.u("hinge", (0.62, 0.46, 0.52), (0, 1.82, 0))
	k.b("spring", (0.34, 0.3, 0.3), (0, 2.1, 0.36))
	g = k.g((0, 2.08, 0), (35, 0, 0))
	g.u("arm", (0.24, 1.2, 0.18), (0, 0, 0))
	g.c("scoop", (0.86, 0.46), 0.36, (0, 1.36, 0), None, 6)


@piece("held", 5, {"handle": ("3A2C3A", "Smooth"), "jaw": ("4A3B4F", "Smooth"), "tooth": ("2E2230", "Smooth"),
	"core": ("FF6A3D", "Neon"), "ember": ("FFB03A", "Neon")}, grip=(0, 0.5, 0.45))
def _(k):  # Magma Snap (:146)
	k.b("handle", (0.46, 1.0, 0.5), (0, 0.5, 0.45), (-15, 0, 0))
	k.b("jaw", (0.82, 0.42, 1.9), (0, 1.15, -0.32))
	k.b("jaw", (0.92, 0.72, 0.62), (0, 1.45, 0.78))
	k.b("core", (0.5, 0.5, 0.5), (0, 1.52, 0.4))
	for s in S2:
		k.w("tooth", (0.28, 0.3, 0.3), (s * 0.2, 1.51, -1.1), (0, 180, 0))
		k.w("ember", (0.24, 0.42, 0.3), (s * 0.26, 2.02, 0.82))
	g = k.g((0, 1.55, 0.45), (40, 0, 0))
	g.b("jaw", (0.82, 0.36, 1.75), (0, 0.18, -0.85))
	for s in S2:
		g.w("tooth", (0.28, 0.3, 0.3), (s * 0.2, -0.13, -1.55), (180, 0, 0))


@piece("held", 6, {"prism": ("B98CFF", "Glass"), "core": ("FFFFFF", "Neon"), "grip": ("B98CFF", "Smooth"),
	"f1": ("FF5C8A", "Neon"), "f2": ("FFD84A", "Neon"), "f3": ("5FE0E8", "Neon"), "star": ("FFD84A", "Neon"),
	"ring": ("FFD84A", "Smooth")}, grip=(0, 0.5, 0.25))
def _(k):  # Prism Popper (:150)
	k.e("prism", ((-0.58, -0.42), (0.58, -0.42), (0, 0.58)), 1.8, (0, 1.35, -0.3))
	k.b("core", (0.18, 0.18, 1.86), (0, 1.27, -0.3))
	k.b("grip", (0.42, 0.95, 0.5), (0, 0.5, 0.25), (-12, 0, 0))
	k.b("grip", (0.1, 0.26, 0.12), (0, 0.82, -0.15))
	k.b("f1", (0.08, 0.55, 0.45), (0, 2.1, 0.5))
	k.b("f2", (0.55, 0.08, 0.45), (-0.62, 1.0, 0.5), (0, 0, 30))
	k.b("f3", (0.55, 0.08, 0.45), (0.62, 1.0, 0.5), (0, 0, -30))
	k.e("star", kit.star_pts(0.44, 0.2 / 0.44), 0.16, (0, 1.3, -1.3))
	k.b("ring", (0.1, 0.1, 0.9), (0, 1.27, 0.95))
	k.r("ring", 0.22, 0.05, (0, 1.27, 1.6), (0, 90, 0), 10)


@piece("held", 7, {"staff": ("FBF7F2", "Smooth"), "gold": ("FFC23C", "Smooth"), "wing": ("FFD45C", "Smooth"),
	"halo": ("FFF0A0", "Neon"), "gem": ("FFD45C", "Glass"), "cloud": ("FFE9A8", "Smooth")}, grip=(0, 0.75, 0))
def _(k):  # Halo Hurler (:154)
	k.s("cloud", 0.52, (0, 0.26, 0))
	k.s("cloud", 0.36, (0.22, 0.2, 0.05))
	k.u("staff", (0.3, 2.0, 0.3), (0, 0.4, 0))
	k.u("gold", (0.44, 0.22, 0.44), (0, 1.0, 0))
	k.u("gold", (1.0, 0.24, 0.4), (0, 2.3, 0))
	k.o("gem", 0.62, (0, 2.78, -0.05))
	k.r("halo", 0.42, 0.07, (0, 3.35, 0), (90, 0, 0), 12)
	for s in S2:
		k.u("gold", (0.24, 0.34, 0.3), (s * 0.42, 2.5, 0))
		wing = kit.wing_pts(0.72)
		k.e("wing", wing if s > 0 else kit.mirror(wing), 0.1, (s * 0.42, 2.6, 0))


# --------------------------------------------------------------------------------------- platform launchers (sheet)


@piece("platform", 1, {"wood": ("E0A062", "Stud"), "pink": ("FF8FBF", "Smooth"), "white": ("FFF6EC", "Smooth"),
	"rope": ("FF9ED2", "Smooth"), "cup": ("8EEAD0", "Smooth"), "g1": ("FFD84A", "Smooth"), "g2": ("FF8FBF", "Smooth")})
def _(k):  # Gumdrop Catapult (:159)
	for s in S2:
		k.b("wood", (0.6, 0.6, 4.0), (s * 1.9, 0.95, 0))
		for z in (-1.4, 1.4):
			k.c("pink", 1.3, 0.35, (s * 2.38, 0.65, z), (0, 0, 90))
		k.bar("wood", (s * 1.9, 1.2, -1.8), (s * 1.9, 3.3, -0.8), 0.42)
		k.bar("wood", (s * 1.9, 1.2, 0.9), (s * 1.9, 3.3, -0.8), 0.42)
		k.c("g1" if s < 0 else "g2", (0.45, 0.95), 0.7, (s * 1.9, 1.6, 1.6), None, 6)
	for z in (-1.5, 1.5):
		k.b("wood", (3.2, 0.5, 0.6), (0, 0.95, z))
	k.b("white", (4.2, 0.4, 0.42), (0, 3.42, -0.8))
	k.c("white", 0.4, 3.6, (0, 1.6, -0.5), (0, 0, 90))
	k.c("rope", 0.85, 1.0, (0, 1.6, -0.5), (0, 0, 90))
	g = k.g((0, 1.6, -0.5), (12, 0, 0))
	for i, key in enumerate(("white", "pink", "white")):
		g.b(key, (0.45, 0.45, 0.86), (0, 0, 0.43 + i * 0.86))
	g.c("cup", (1.3, 0.8), 0.6, (0, 0.45, 2.5), None, 6)


@piece("platform", 2, {"board": ("E0A062", "Stud"), "body": ("9FB4C7", "Stud"), "dark": ("1E1428", "Smooth"),
	"band": ("C9803F", "Smooth"), "knob": ("FF5C8A", "Smooth"), "toast": ("F2C487", "Smooth"),
	"crust": ("C9803F", "Smooth"), "butter": ("FFE36E", "Smooth")})
def _(k):  # Toaster Tosser (:163)
	k.u("board", (5.0, 0.4, 4.4), (0, 0, 0))
	for x in (-1.8, 1.8):
		for z in (-1.3, 1.3):
			k.u("dark", (0.5, 0.3, 0.5), (x, 0.4, z))
	k.u("body", (4.4, 2.8, 3.4), (0, 0.7, 0))
	k.u("body", (4.0, 0.3, 3.0), (0, 3.5, 0))
	k.u("band", (4.5, 0.42, 3.5), (0, 1.0, 0))
	for z in (-0.7, 0.7):
		k.u("dark", (3.0, 0.1, 0.7), (0, 3.8, z))
	k.c("knob", 0.62, 0.2, (-1.4, 2.6, -1.75), (90, 0, 0))
	k.b("dark", (0.12, 1.9, 0.32), (2.21, 2.3, 0))
	g = k.g((0, 2.9, 0), (0, 0, 0))
	for z in (-0.7, 0.7):
		g.b("crust", (2.6, 2.4, 0.46), (0, 0, z))
		g.b("toast", (2.3, 2.1, 0.52), (0, 0, z))
	g.b("butter", (0.7, 0.26, 0.5), (0.3, 1.33, -0.7))
	k.b("knob", (0.5, 0.42, 0.5), (2.47, 1.6, 0))


@piece("platform", 3, {"base": ("3FCFC0", "Stud"), "frame": ("EED6B8", "Stud"), "wheel": ("3B2630", "Smooth"),
	"hub": ("5FE0E8", "Neon"), "jug": ("EED6B8", "Glass"), "lid": ("FFF6EC", "Smooth"), "straw": ("FF6FA3", "Smooth"),
	"bub": ("8DF27A", "Glass")})
def _(k):  # Pearl Pitcher (:167)
	k.u("base", (4.8, 0.8, 4.4), (0, 0, 0))
	k.u("base", (3.6, 0.5, 3.2), (0, 0.8, 0))
	for s in S2:
		k.u("frame", (0.35, 3.3, 1.9), (s * 0.85, 1.3, -1.35))
	k.u("frame", (2.0, 1.7, 1.6), (0, 1.3, 0.55))
	for y in (2.2, 3.85):
		k.c("wheel", 1.5, 1.2, (0, y, -1.4), (0, 0, 90))
		k.c("hub", 0.5, 1.95, (0, y, -1.4), (0, 0, 90))
	k.c("jug", (1.75, 1.3), 1.8, (0, 3.95, 0.85))
	k.c("lid", 1.85, 0.2, (0, 4.95, 0.85))
	for p in ((-0.3, 3.4, 0.8), (0.32, 3.45, 1.0), (0, 3.8, 0.7)):
		k.s("wheel", 0.42, p)
	k.bar("straw", (0, 3.3, 0.5), (0, 3.02, -0.7), 0.5)
	k.s("bub", 0.6, (-1.9, 1.1, 1.6))
	k.s("bub", 0.45, (1.95, 1.0, 1.7))


@piece("platform", 4, {"berg": ("8FD8FF", "Stud"), "plank": ("BDEBFF", "Smooth"), "cup": ("E0A062", "Smooth"),
	"snow": ("F4FBFF", "Smooth"), "stick": ("E0A062", "Smooth"), "shelf": ("D9F3FF", "Smooth"),
	"cherry": ("E0315F", "Smooth"), "icicle": ("D9F3FF", "Smooth")})
def _(k):  # Glacier Flinger (:171)
	k.u("berg", (4.6, 1.0, 4.0), (0, 0, -0.3))
	k.u("berg", (1.6, 1.3, 1.3), (0, 1.0, -0.35))
	for s in S2:
		k.u("stick", (0.45, 5.0, 0.45), (s * 1.2, 1.0, 1.15))
	k.u("shelf", (2.9, 0.42, 1.2), (0, 6.0, 1.15))
	for x in (-0.85, 0, 0.85):
		k.c("icicle", (0.4, 0.05), 0.9, (x, 5.55, 1.15), None, 4)
	g = k.g((0, 2.45, -0.35), (-14, 0, 0))
	g.b("plank", (1.3, 0.36, 3.8), (0, 0, 0))
	g.c("cup", (1.5, 0.9), 0.7, (0, 0.5, -1.45), None, 6)
	g.u("snow", (1.0, 0.25, 1.0), (0, 0.18, 1.45))
	k.s("snow", 2.0, (0, 7.2, 1.15))
	k.s("cherry", 0.5, (0.1, 8.35, 1.1))


@piece("platform", 5, {"rock": ("3A2C3A", "Stud"), "crack": ("4A3B4F", "Stud"), "lava": ("FF6A3D", "Neon"),
	"glow": ("FFB03A", "Neon")})
def _(k):  # Volcano Vaulter (:175)
	k.u("rock", (5.2, 1.6, 4.4), (0, 0, 0))
	k.u("crack", (4.1, 1.6, 3.5), (0, 1.6, 0))
	k.u("rock", (3.0, 1.4, 2.6), (0, 3.2, 0))
	for x, z, w, d in ((0, -1.1, 3.0, 0.4), (0, 1.1, 3.0, 0.4), (-1.3, 0, 0.4, 1.8), (1.3, 0, 0.4, 1.8)):
		k.u("rock", (w, 0.7, d), (x, 4.6, z))
	k.u("lava", (2.2, 0.15, 1.8), (0, 4.6, 0))
	k.u("lava", (0.5, 0.06, 2.0), (-0.7, 1.6, -1.79), (-90, 0, 0))
	k.u("lava", (0.45, 0.06, 1.6), (0.9, 0.05, -2.24), (-90, 0, 0))
	for p in ((-2.3, 0, -2.0), (2.4, 0, 1.8), (2.2, 0, -2.0)):
		k.s("rock", 0.9, (p[0], 0.4, p[2]))
	g = k.g((0, 4.7, 0), (0, 0, 0))
	g.u("crack", (1.9, 0.4, 1.6), (0, 0, 0))
	g.u("glow", (1.7, 0.1, 1.4), (0, 0.4, 0))


@piece("platform", 6, {"rail": ("3A2A7A", "Stud"), "frame": ("B98CFF", "Glass"), "axle": ("FFD84A", "Smooth"),
	"beam": ("FFF0A0", "Neon"), "star": ("FFD84A", "Neon"), "sling": ("FFFFFF", "Smooth"), "a1": ("FF5C8A", "Neon"),
	"a2": ("FFD84A", "Neon"), "a3": ("5FE0E8", "Neon")})
def _(k):  # Starbeam Trebuchet (:179)
	for s in S2:
		k.u("rail", (0.6, 0.6, 4.4), (s * 2.2, 0, 0))
		k.bar("frame", (s * 2.2, 0.5, -1.9), (s * 2.2, 5.0, 0), 0.5)
		k.bar("frame", (s * 2.2, 0.5, 1.9), (s * 2.2, 5.0, 0), 0.5)
	for z in (-1.9, 1.9):
		k.u("rail", (4.0, 0.5, 0.5), (0, 0.05, z))
	k.c("axle", 0.45, 4.8, (0, 5.0, 0), (0, 0, 90))
	for i, key in enumerate(("a1", "a2", "a3")):
		k.r(key, 1.6 - i * 0.32, 0.12, (0, 0.55, -2.25), (0, 0, 0), 10, math.pi)
	g = k.g((0, 5.0, 0), (55, 0, 0))
	g.b("beam", (0.4, 0.4, 5.6), (0, 0, 1.2))
	g.e("star", kit.star_pts(1.25, 0.55 / 1.25), 0.5, (0, 0, -2.0), (0, 90, 0))
	g.bar("sling", (0, 0, 4.0), (0, -0.9, 4.4), 0.08)
	g.u("sling", (0.7, 0.3, 0.6), (0, -1.15, 4.45))


@piece("platform", 7, {"marble": ("FBF7F2", "Stud"), "gold": ("FFC23C", "Smooth"), "wing": ("FFD45C", "Smooth"),
	"halo": ("FFF0A0", "Neon"), "gem": ("FFD45C", "Glass"), "cloud": ("FFE9A8", "Smooth")})
def _(k):  # Angel Ascender (:183)
	k.u("marble", (5.2, 0.8, 4.4), (0, 0, 0))
	k.u("marble", (4.2, 0.6, 3.4), (0, 0.8, 0))
	for s in S2:
		k.u("gold", (1.2, 0.5, 1.2), (s * 1.75, 1.4, 0.3))
		k.c("marble", 0.9, 8.6, (s * 1.75, 6.2, 0.3))
		k.u("gold", (1.3, 0.6, 1.3), (s * 1.75, 10.5, 0.3))
		wing = kit.wing_pts(1.3)
		k.e("wing", wing if s > 0 else kit.mirror(wing), 0.3, (s * 1.8, 10.9, 0.5), (0, 0, s * 75))
		k.s("cloud", 1.2, (s * 1.95, 0.6, -1.7))
	k.u("marble", (4.6, 0.7, 1.4), (0, 11.1, 0.3))
	k.r("halo", 0.75, 0.12, (0, 12.6, 0.3), (90, 0, 0), 12)
	k.o("gem", 0.9, (0, 12.25, 0.3))
	k.s("cloud", 1.0, (0.6, 0.5, -2.2))
	g = k.g((0, 2.4, 0.3), (0, 0, 0))
	g.r("halo", 1.1, 0.16, (0, 0.3, 0), (90, 0, 0), 12)
	g.c("gem", (1.6, 0.9), 0.5, (0, 0.25, 0), None, 8)
	for s in S2:
		g.b("gold", (0.9, 0.22, 0.3), (s * 1.3, 0.3, 0))


# ------------------------------------------------------------------------------------------- arm gear (Claude's)
# Worn on the right lower arm (an R15 lower arm is about 1 x 1.2 x 1 studs): origin = its centre, Y along the arm.


def cuff(k, key, h, y=0.0, out=1.24, wall=0.15):  # a square band round the arm
	half = out / 2 - wall / 2
	for s in S2:
		k.b(key, (out, h, wall), (0, y, s * half))
		k.b(key, (wall, h, out - 2 * wall), (s * half, y, 0))


@piece("arm", 1, {"gum": ("FF8FBF", "Smooth"), "band": ("FFD84A", "Smooth"), "drop": ("8EEAD0", "Smooth"),
	"hot": ("FF5C8A", "Smooth")})
def _(k):  # Gummy Grip: a gummy cuff with two sugar bands and gumdrops on its back
	cuff(k, "gum", 0.9)
	cuff(k, "band", 0.14, 0.32, 1.32, 0.19)
	cuff(k, "band", 0.14, -0.32, 1.32, 0.19)
	k.c("drop", (0.16, 0.42), 0.3, (0.74, 0.12, 0), (0, 0, -90), 6)
	k.c("hot", (0.14, 0.36), 0.26, (0.72, -0.16, 0.24), (0, 0, -90), 6)
	k.c("hot", (0.14, 0.36), 0.26, (0.72, -0.16, -0.24), (0, 0, -90), 6)


@piece("arm", 2, {"biscuit": ("E8A55A", "Smooth"), "crust": ("C9803F", "Smooth"), "butter": ("FFE36E", "Smooth"),
	"cream": ("FFF6EC", "Smooth")})
def _(k):  # Biscuit Bracer: a biscuit plate cuff, crust rims, a butter pat
	cuff(k, "biscuit", 0.95)
	cuff(k, "crust", 0.16, 0.42, 1.34, 0.2)
	cuff(k, "crust", 0.16, -0.42, 1.34, 0.2)
	k.b("cream", (0.1, 0.5, 0.66), (0.7, 0, 0))
	k.b("butter", (0.14, 0.26, 0.34), (0.78, 0, 0), (12, 0, 0))
	for z in (-0.4, 0.4):
		k.s("crust", 0.14, (0.66, 0.2, z))
		k.s("crust", 0.14, (0.66, -0.2, z))


@piece("arm", 3, {"tea": ("EED6B8", "Smooth"), "teal": ("3FCFC0", "Smooth"), "pearl": ("3B2630", "Smooth"),
	"straw": ("FF6FA3", "Smooth")})
def _(k):  # Bubble Band: a milk-tea cuff, a lagoon band, three pearls, a straw stub
	cuff(k, "tea", 0.9)
	cuff(k, "teal", 0.2, 0, 1.33, 0.19)
	for z in (-0.32, 0, 0.32):
		k.s("pearl", 0.26, (0.72, 0, z))
	k.c("straw", 0.16, 0.7, (0.5, 0.5, -0.5), (0, 0, -18), 6)
	k.s("pearl", 0.2, (-0.7, 0.2, 0.2))
	k.s("pearl", 0.2, (-0.7, -0.15, -0.2))


@piece("arm", 4, {"ice": ("BDEBFF", "Smooth"), "glacier": ("8FD8FF", "Smooth"), "snow": ("F4FBFF", "Smooth"),
	"frost": ("D9F3FF", "Smooth")})
def _(k):  # Frost Fist: an ice cuff, a snow knuckle plate, icicle spikes
	cuff(k, "ice", 0.95)
	cuff(k, "glacier", 0.18, 0.4, 1.34, 0.2)
	k.b("snow", (0.16, 0.5, 0.9), (0.72, -0.1, 0))
	for z in (-0.3, 0, 0.3):
		k.c("frost", (0.04, 0.22), 0.46, (0.98, -0.1, z), (0, 0, -90), 4)
	for s in S2:
		k.c("frost", (0.04, 0.2), 0.4, (0, 0.1, s * 0.82), (s * 90, 0, 0), 4)


@piece("arm", 5, {"basalt": ("3A2C3A", "Smooth"), "crack": ("4A3B4F", "Smooth"), "lava": ("FF6A3D", "Neon"),
	"ember": ("FFB03A", "Neon")})
def _(k):  # Magma Mitt: a basalt cuff with lava seams and ember spikes
	cuff(k, "basalt", 0.95)
	cuff(k, "crack", 0.2, 0.4, 1.34, 0.2)
	cuff(k, "lava", 0.08, -0.05, 1.27, 0.165)
	k.b("crack", (0.2, 0.52, 0.8), (0.72, -0.12, 0))
	k.b("lava", (0.08, 0.3, 0.5), (0.84, -0.12, 0))
	for z in (-0.3, 0.3):
		k.w("ember", (0.2, 0.34, 0.3), (0.72, 0.42, z), (0, 90, 0))
	k.w("ember", (0.22, 0.4, 0.34), (0.74, 0.46, 0), (0, 90, 0))


@piece("arm", 6, {"violet": ("B98CFF", "Smooth"), "night": ("3A2A7A", "Smooth"), "r1": ("FF5C8A", "Neon"),
	"r2": ("FFD84A", "Neon"), "r3": ("5FE0E8", "Neon"), "star": ("FFD84A", "Neon")})
def _(k):  # Rainbow Wrap: a violet cuff wrapped in three light bands, a star on its back
	cuff(k, "violet", 0.95)
	cuff(k, "night", 0.14, 0.44, 1.32, 0.19)
	cuff(k, "night", 0.14, -0.44, 1.32, 0.19)
	for i, key in enumerate(("r1", "r2", "r3")):
		cuff(k, key, 0.12, 0.24 - i * 0.24, 1.29, 0.175)
	k.e("star", kit.star_pts(0.34, 0.45), 0.12, (0.74, 0, 0), (0, 90, 0))


@piece("arm", 7, {"marble": ("FBF7F2", "Smooth"), "gold": ("FFC23C", "Smooth"), "wing": ("FFD45C", "Smooth"),
	"halo": ("FFF0A0", "Neon"), "gem": ("FFD45C", "Glass")})
def _(k):  # Halo Gauntlet: a marble cuff, gold rims, a sun gem, two small wings and a halo
	cuff(k, "marble", 0.95)
	cuff(k, "gold", 0.16, 0.42, 1.34, 0.2)
	cuff(k, "gold", 0.16, -0.42, 1.34, 0.2)
	k.o("gem", 0.4, (0.74, 0, 0))
	for s in S2:
		wing = kit.wing_pts(0.42)
		k.e("wing", wing if s > 0 else kit.mirror(wing), 0.08, (0, -0.1, s * 0.66), (0, 90, 0) if s > 0 else (0, -90, 0))
	k.r("halo", 0.34, 0.05, (0, 0.78, 0), (90, 0, 0), 12)


# ---------------------------------------------------------------------------------------------- armor (Claude's)
# Worn on the upper torso (an R15 upper torso is about 2 x 1.6 x 1 studs): origin = its centre, front = -Z.


def plate(k, key, rim, w=2.2, h=1.5, z=0.62):  # a chest plate, a back plate and two side straps, a rim over the top
	k.b(key, (w, h, 0.18), (0, 0, -z))
	k.b(key, (w, h, 0.18), (0, 0, z))
	for s in S2:
		k.b(key, (0.18, h * 0.7, 2 * z - 0.1), (s * (w / 2 - 0.09), -0.1, 0))
	k.b(rim, (w + 0.12, 0.18, 0.24), (0, h / 2 - 0.02, -z))
	k.b(rim, (w + 0.12, 0.18, 0.24), (0, h / 2 - 0.02, z))


@piece("armor", 1, {"gum": ("FF8FBF", "Smooth"), "hot": ("FF5C8A", "Smooth"), "lemon": ("FFD84A", "Smooth"),
	"mint": ("8EEAD0", "Smooth")})
def _(k):  # Gumdrop Guard: a gummy plate, gumdrop shoulders, a lemon heart of two drops
	plate(k, "gum", "hot")
	for s in S2:
		k.c("mint" if s < 0 else "lemon", (0.3, 0.9), 0.62, (s * 1.28, 0.92, 0), None, 6)
		k.s("lemon", 0.36, (s * 0.16, 0.12, -0.76))
	k.w("lemon", (0.5, 0.36, 0.14), (0, -0.14, -0.76), (90, 0, 0))
	for x in (-0.6, 0, 0.6):
		k.s("hot", 0.2, (x, -0.52, -0.74))


@piece("armor", 2, {"crust": ("C9803F", "Smooth"), "bread": ("E8A55A", "Smooth"), "butter": ("FFE36E", "Smooth"),
	"cream": ("FFF6EC", "Smooth")})
def _(k):  # Crust Coat: a bread plate with a cream front, butter buttons, crust-roll shoulders
	plate(k, "bread", "crust")
	k.b("cream", (0.5, 1.2, 0.1), (0, -0.05, -0.74))
	for y in (0.34, 0, -0.34):
		k.b("butter", (0.24, 0.2, 0.12), (0, y, -0.8))
	for s in S2:
		k.c("crust", 0.62, 1.1, (s * 1.3, 0.9, 0), (90, 0, 0))
		k.c("bread", 0.5, 1.16, (s * 1.3, 0.9, 0), (90, 0, 0))


@piece("armor", 3, {"teal": ("3FCFC0", "Smooth"), "tea": ("EED6B8", "Smooth"), "pearl": ("3B2630", "Smooth"),
	"hub": ("5FE0E8", "Neon")})
def _(k):  # Pearl Plate: a lagoon plate, a row of pearls, milk-tea shoulder pads
	plate(k, "teal", "tea")
	for x in (-0.66, -0.22, 0.22, 0.66):
		k.s("pearl", 0.3, (x, 0.2, -0.76))
	k.c("hub", 0.5, 0.12, (0, -0.32, -0.74), (90, 0, 0))
	for s in S2:
		k.u("tea", (0.7, 0.26, 1.1), (s * 1.3, 0.72, 0))
		k.s("pearl", 0.34, (s * 1.3, 1.08, 0))


@piece("armor", 4, {"ice": ("BDEBFF", "Smooth"), "glacier": ("8FD8FF", "Smooth"), "snow": ("F4FBFF", "Smooth"),
	"frost": ("D9F3FF", "Smooth")})
def _(k):  # Ice Shell: an ice plate, a snow collar, icicle shoulders, a frost diamond
	plate(k, "ice", "snow")
	k.o("glacier", 0.6, (0, 0, -0.76))
	for s in S2:
		k.u("glacier", (0.66, 0.24, 1.0), (s * 1.3, 0.72, 0))
		for z in (-0.3, 0, 0.3):
			k.c("frost", (0.04, 0.24), 0.5, (s * 1.34, 1.2, z), None, 4)
	for x in (-0.7, 0.7):
		k.c("frost", (0.2, 0.04), 0.4, (x, -0.9, -0.66), None, 4)


@piece("armor", 5, {"basalt": ("3A2C3A", "Smooth"), "crack": ("4A3B4F", "Smooth"), "lava": ("FF6A3D", "Neon"),
	"ember": ("FFB03A", "Neon")})
def _(k):  # Volcano Vest: a basalt plate, a lava core with seams, rock shoulders with ember spikes
	plate(k, "basalt", "crack")
	k.b("lava", (0.5, 0.5, 0.1), (0, 0.05, -0.74), (0, 0, 45))
	k.b("lava", (1.5, 0.08, 0.08), (0, -0.45, -0.73), (0, 0, 8))
	k.b("lava", (0.08, 0.5, 0.08), (0.5, -0.2, -0.73), (0, 0, -20))
	for s in S2:
		k.u("crack", (0.78, 0.44, 1.1), (s * 1.3, 0.7, 0))
		k.w("ember", (0.26, 0.44, 0.34), (s * 1.3, 1.34, -0.2))
		k.w("ember", (0.22, 0.34, 0.3), (s * 1.3, 1.3, 0.25), (0, 180, 0))


@piece("armor", 6, {"violet": ("B98CFF", "Smooth"), "night": ("3A2A7A", "Smooth"), "r1": ("FF5C8A", "Neon"),
	"r2": ("FFD84A", "Neon"), "r3": ("5FE0E8", "Neon"), "star": ("FFD84A", "Neon")})
def _(k):  # Prism Plate: a violet plate, three light chevrons, a star, prism shoulders
	plate(k, "violet", "night")
	k.e("star", kit.star_pts(0.34, 0.45), 0.12, (0, 0.3, -0.76))
	for i, key in enumerate(("r1", "r2", "r3")):
		k.e(key, kit.chevron(0.62, 0.1, 0.14), 0.1, (0, -0.16 - i * 0.22, -0.74), (0, 0, 180))
	for s in S2:
		k.e("night", ((-0.42, 0), (0.42, 0), (0, 0.62)), 1.0, (s * 1.3, 0.72, 0))


@piece("armor", 7, {"marble": ("FBF7F2", "Smooth"), "gold": ("FFC23C", "Smooth"), "wing": ("FFD45C", "Smooth"),
	"halo": ("FFF0A0", "Neon"), "gem": ("FFD45C", "Glass")})
def _(k):  # Angel Aegis: a marble plate, gold trim, a sun gem, wings on the back, a halo
	plate(k, "marble", "gold")
	k.o("gem", 0.5, (0, 0.12, -0.78))
	k.b("gold", (1.3, 0.1, 0.1), (0, -0.4, -0.74))
	for s in S2:
		k.u("gold", (0.72, 0.26, 1.06), (s * 1.3, 0.72, 0))
		wing = kit.wing_pts(0.8)
		k.e("wing", wing if s > 0 else kit.mirror(wing), 0.1, (s * 0.3, 0, 0.78), (0, 0, s * 20))
	k.r("halo", 0.5, 0.06, (0, 1.75, 0.1), (90, 0, 0), 12)


# ------------------------------------------------------------------------------------------------------- Blender


def to_object(name, bm, collection):
	for v in bm.verts:
		v.co = Vector((v.co.x, -v.co.z, v.co.y))
	bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	collection.objects.link(obj)
	return obj


def main():
	for o in list(bpy.data.objects):  # the factory scene's cube, camera and light
		bpy.data.objects.remove(o)
	lib = bpy.data.collections.new("SD_Gear")
	bpy.context.scene.collection.children.link(lib)
	manifest = {"uvStuds": kit.UV_STUDS, "ink": INK, "objects": {}, "pieces": {}}
	by_piece, problems = {}, []

	for pid, (line, tier, pal, build, grip) in PIECES.items():
		max_tris, max_keys, max_x, max_y, max_z, ink, soft = LIMITS[line]
		k = G()
		k.soft = soft
		build(k)
		merged = {}
		for key, bm in k.parts:
			if key not in pal:
				problems.append(f"{pid}: no palette key {key}")
			merged.setdefault(key, bmesh.new())
			kit.append(merged[key], bm)
			bm.free()
		hull = bmesh.new()
		for bm in merged.values():
			kit.append(hull, bm)
		objs, lows, highs, tris = [], [], [], 0
		for key, bm in merged.items():
			kit.stud_uvs(bm)
			cos = [v.co.copy() for v in bm.verts]
			lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
			hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
			lows.append(lo)
			highs.append(hi)
			name = f"{pid}__{key}"
			obj = to_object(name, bm, lib)
			obj.modifiers.new("Normals", "WEIGHTED_NORMAL").keep_sharp = True  # big faces flat, the bevels round
			objs.append(obj)
			tris += len(obj.data.polygons)
			manifest["objects"][name] = {
				"piece": pid, "key": key, "tris": len(obj.data.polygons),
				"center": [round((lo[i] + hi[i]) / 2, 4) for i in range(3)],
				"size": [round(hi[i] - lo[i], 4) for i in range(3)],
			}
		# The outline: the whole piece pushed out along its normals and turned inside out (the game draws it in ink).
		hull.normal_update()
		for v in hull.verts:
			v.co += v.normal * ink
		bmesh.ops.reverse_faces(hull, faces=hull.faces)
		cos = [v.co.copy() for v in hull.verts]
		lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
		hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
		name = f"{pid}__Outline"
		outline = to_object(name, hull, lib)
		tris += len(outline.data.polygons)
		manifest["objects"][name] = {
			"piece": pid, "key": "Outline", "tris": len(outline.data.polygons),
			"center": [round((lo[i] + hi[i]) / 2, 4) for i in range(3)],
			"size": [round(hi[i] - lo[i], 4) for i in range(3)],
		}
		lo = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
		hi = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
		manifest["pieces"][pid] = {
			"line": line, "tier": tier, "tris": tris, "keys": len(objs), "grip": list(grip),
			"min": [round(c, 3) for c in lo], "max": [round(c, 3) for c in hi],
			"colors": {key: {"hex": hexstr, "kind": kind} for key, (hexstr, kind) in pal.items()},
		}
		by_piece[pid] = (objs, outline)
		print(pid, "tris", tris, "keys", len(objs), "x", round(lo.x, 2), round(hi.x, 2), "y", round(lo.y, 2), round(hi.y, 2),
			"z", round(lo.z, 2), round(hi.z, 2))
		if tris > max_tris:
			problems.append(f"{pid}: {tris} tris, the limit is {max_tris}")
		if len(objs) > max_keys:
			problems.append(f"{pid}: {len(objs)} keys, the limit is {max_keys}")
		if max(abs(lo.x), abs(hi.x)) > max_x or hi.y - lo.y > max_y or max(abs(lo.z), abs(hi.z)) > max_z:
			problems.append(f"{pid}: bounds {[round(c, 2) for c in lo]} .. {[round(c, 2) for c in hi]} over the line's limits")
		for key in pal:
			if key not in merged:
				problems.append(f"{pid}: palette key {key} is not used")

	with open(os.path.join(OUT, "manifest.json"), "w") as f:
		json.dump(manifest, f, indent=1)
	if problems:
		raise SystemExit("gear models: " + "; ".join(problems))

	# ---------------------------------------------------------------------------------------------------- export

	for line in LIMITS:
		bpy.ops.object.select_all(action="DESELECT")
		chosen = [o for o in lib.objects if o.name.startswith(line + "_")]
		for o in chosen:
			o.select_set(True)
		bpy.context.view_layer.objects.active = chosen[0]
		fbx = os.path.join(OUT, f"SD_Gear_{line}.fbx")
		bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, object_types={"MESH"}, use_mesh_modifiers=True,
			mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y",
			apply_scale_options="FBX_SCALE_ALL", bake_space_transform=True)
		glb = os.path.join(OUT, f"SD_Gear_{line}.glb")
		bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
			export_texcoords=True, export_normals=True, export_tangents=False, export_materials="NONE",
			export_vertex_color="NONE", export_attributes=False, export_animations=False, export_morph=False,
			export_skins=False, export_cameras=False, export_lights=False, export_extras=False)
		print("EXPORTED", line, len(chosen), "objects", os.path.getsize(fbx), "bytes fbx", os.path.getsize(glb), "bytes glb")

	# -------------------------------------------------------------------------------------------------- previews

	def material(name, hexstr, kind):
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = kit.linear(hexstr)
		b.inputs["Roughness"].default_value = {"Smooth": 0.35, "Stud": 0.8, "Neon": 0.4, "Glass": 0.12, "Ink": 1.0}[kind]
		if kind == "Neon":
			b.inputs["Emission Color"].default_value = kit.linear(hexstr)
			b.inputs["Emission Strength"].default_value = 1.2
		if kind == "Ink":
			m.use_backface_culling = True
		return m

	ink_material = material("ink", INK, "Ink")
	for pid, (objs, outline) in by_piece.items():
		pal = PIECES[pid][2]
		for o in objs:
			hexstr, kind = pal[o.name.split("__")[1]]
			o.data.materials.append(material(o.name, hexstr, kind))
		outline.data.materials.append(ink_material)

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
	bg.inputs["Color"].default_value = kit.linear("EAF4FF")
	bg.inputs["Strength"].default_value = 0.7
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 2.4
	sun.rotation_euler = (42 * D, 8 * D, -30 * D)
	scene.collection.objects.link(sun)
	cam_data = bpy.data.cameras.new("PreviewCam")
	cam_data.type = "ORTHO"
	cam_data.clip_end = 5000
	cam = bpy.data.objects.new("PreviewCam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam
	yaw, pitch = -35 * D, 20 * D  # from the front left (a launcher's front is -Z = Blender +Y)
	d = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
	scene.render.resolution_x, scene.render.resolution_y = 360, 420
	scene.render.resolution_percentage = 100
	scene.render.film_transparent = False
	for pid, (objs, outline) in by_piece.items():
		info = manifest["pieces"][pid]
		lo, hi = Vector(info["min"]), Vector(info["max"])
		centre = Vector(((lo.x + hi.x) / 2, -(lo.z + hi.z) / 2, (lo.y + hi.y) / 2))
		cam_data.ortho_scale = max(hi.y - lo.y, (hi - lo).length * 0.8) * 1.25
		cam.location = centre + d * 300
		cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
		for o in lib.objects:
			o.hide_render = not (o in objs or o == outline)
		scene.render.filepath = os.path.join(OUT, f"{pid}.png")
		bpy.ops.render.render(write_still=True)
	print("DONE", len(PIECES), "pieces")


if __name__ == "__main__":
	main()
