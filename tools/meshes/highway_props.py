"""Squishy Duels highway traps: the 7 traps as big toy models (2026-11-07), built with highway_boosters.py's kit.

The owner on a sample of two (gum puddle, marshmallows) in the boosters' toy look (2026-11-06: "more roblox style, they
look so bland, take hit a golf ball as an example"): "Yes, build all 7". So these keep the objects of the owner's
"Launchers & Biomes - Concept Sheet" (Desktop "jason designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:282-300),
2-3 times bigger, round and smooth, in loud colours; the stud tile only on the rims (a "Stud" key). Next to the boosters
a trap must look like a bad thing to hit, with no sign: low and gooey with a dark edge on the bright lanes (the AoE
warning rule of the LihFolk vault), a bright rim inside the dark rim on the dark lava lane.
A trapped squishy stops on the lane's centre within course.trapSpread (2.5) of the trap's middle, its centre 1 stud over
the lane (HighwayMath CLEAR) and 4.8 studs wide (flyScale 3): the middle stays low so it sits half sunk in it, nothing
comes within a stud of it, and the right side (+X) stays low for the game's end cameras (Config.UI.Highway.landingShot,
Config.HighwayFx.hero, both on the right); the tall parts stand on the left, behind the squishy in both.
Run it as its own Blender process:

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python highway_props.py -- <out_dir>

Writes what highway_boosters.py writes, for the traps only (SD_HighwayProps.glb, manifest.json, <id>.png), plus
<id>_end.png: a stuck squishy as the end camera sees it. Import it and run highway_props_setup.luau: it keeps the
boosters. Roblox axes as in the kit (X right, Y up, Z back: a throw flies to -Z). Colours here are for the previews only;
the game paints the meshes from Art/HighwayTraps. The kit's limits hold: every trap stays inside course.trapClearStuds
along the lane.
"""

import math
import os
import sys

from mathutils import Vector

sys.dont_write_bytecode = True  # no __pycache__ in the repo (a snapshot commits everything)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import highway_boosters as kit  # noqa: E402  the toy kit; importing it builds nothing

PIECES = {}


def piece(pid, pal):
	def wrap(fn):
		PIECES[pid] = (pal, fn)
		return fn
	return wrap


# ------------------------------------------------------------------------------------------------------ helpers


def drop(k, key, rim, x, z, r, h):  # a spatter drop round a puddle, with its dark rim
	k.ball(rim, 2, (x, 0, z), (r + 0.45, 0.32, r + 0.45), dome=True, seg=12)
	k.ball(key, 2, (x, 0, z), (r, h, r), dome=True, seg=12)


def shiny(k, key, shine, d, p, seg=20):  # a glossy ball with a shine dot up towards the cameras (+X)
	k.ball(key, d, p, seg=seg)
	n = Vector((0.45, 0.62, 0.1)).normalized() * (d / 2 * 0.93)
	k.ball(shine, 2, (p[0] + n.x, p[1] + n.y, p[2] + n.z), (d * 0.1, d * 0.065, d * 0.1), seg=8)


def mallow(k, key, d, h, p, r=None, toast=True, seg=14):  # a soft marshmallow standing on p, its toasty end on top
	g = k.g(p, r)
	g.ucyl(key, d, h, (0, 0, 0), soft=min(1.4, 0.24 * d), seg=seg)
	if toast:
		g.ucyl("toast", d * 0.72, 0.5, (0, h - 0.25, 0), soft=0.2, seg=seg)


def lay(k, key, d, h, at, axis, toast=True):  # one lying along "x" or "z", centred on at = (x, its bottom y, z)
	x, y, z = at
	if axis == "z":  # local +Y -> +Z: the toasty end looks back to the start
		mallow(k, key, d, h, (x, y + d / 2, z - h / 2), (90, 0, 0), toast)
	else:  # local +Y -> +X: the toasty end looks right, at the end cameras
		mallow(k, key, d, h, (x - h / 2, y + d / 2, z), (0, 0, -90), toast)


def ring_at(deg, r):  # (x, z) at an angle from +X towards +Z (the back)
	return r * math.cos(math.radians(deg)), r * math.sin(math.radians(deg))


# --------------------------------------------------------------------------------------------- the 7 traps


GUM_WAVES = ((3, 0.08, 0.4), (5, 0.06, 1.3), (7, 0.035, 2.1))


@piece("cm_gum_puddle", {"edge": ("B0157A", "Smooth"), "gum": ("FF4FAE", "Smooth"), "bub": ("FF8AD0", "Smooth"),
	"shine": ("FFFFFF", "Smooth")})  # 1 Candy Meadow, the sheet's :282: a gum puddle and a bubble
def _(k):
	k.blob("edge", kit.lobes(11.2, GUM_WAVES, 1.0, 1.05), 0.4)
	k.blob("gum", kit.lobes(10.5, GUM_WAVES, 1.0, 1.05), 0.8)
	for x, z, r in ((-12.2, 7.4, 1.3), (11.9, -5.6, 1.0), (6.4, 11.9, 0.9), (-7.6, -12.3, 1.1), (12.4, 4.2, 0.7)):
		drop(k, "gum", "edge", x, z, r, 0.75)
	shiny(k, "bub", "shine", 9.5, (-8.2, 5.1, 4.2))  # the big one, behind the squishy in the end camera
	shiny(k, "bub", "shine", 5.0, (-5.2, 2.85, -7.4))
	shiny(k, "bub", "shine", 3.0, (6.4, 1.85, 6.4))


JAM_WAVES = ((2, 0.05, 0.9), (4, 0.07, 2.4), (7, 0.04, 0.2))
DOLLOP = ((5.0, 0), (4.9, 1.0), (4.4, 2.2), (3.6, 3.2), (2.6, 4.0), (1.7, 4.6), (0.9, 5.1), (0.35, 5.45), (0, 5.6))


def berry(k, x, z, s, turn):  # a plump berry bit sitting in the jam, gold seeds on top
	r = 1.7 * s
	y = 0.85 * r + 0.1
	k.ball("berry", 2, (x, y, z), (r, 0.85 * r, r), (0, turn, 0), seg=12)
	for i in range(5):
		a = math.radians(turn) + i * kit.TAU / 5
		n = Vector((0.62 * math.cos(a), 0.75, 0.62 * math.sin(a))).normalized()
		k.ball("seed", 2, (x + n.x * r, y + n.y * 0.85 * r, z + n.z * r), (0.22 * s, 0.14 * s, 0.22 * s), seg=6)


@piece("bt_jam_puddle", {"edge": ("5E0B2A", "Smooth"), "jam": ("D81458", "Smooth"), "berry": ("FF3D6B", "Smooth"),
	"seed": ("FFD21F", "Smooth")})  # 2 Bakery Town, the sheet's :285: a jam puddle with berry bits
def _(k):
	k.blob("edge", kit.lobes(11.2, JAM_WAVES, 1.05, 1.0), 0.4)
	k.blob("jam", kit.lobes(10.5, JAM_WAVES, 1.05, 1.0), 0.85)
	for x, z, r in ((12.2, 6.4, 1.1), (-5.8, 12.2, 1.1), (8.4, -11.0, 0.9), (-12.2, -5.2, 1.0)):
		drop(k, "jam", "edge", x, z, r, 0.8)
	k.lathe("jam", DOLLOP, (-8.6, 0.4, 3.8), seg=20)  # a big dollop, behind the squishy in the end camera
	k.lathe("jam", DOLLOP, (-4.8, 0.4, -8.4), seg=16, scale=(0.6, 0.62, 0.6))
	for x, z, s, turn in ((-3.2, 8.0, 1.0, 20), (6.6, 3.4, 0.85, -35), (0.2, -10.4, 0.9, 60), (-10.6, -3.6, 1.1, 10)):
		berry(k, x, z, s, turn)


TEAR = ((0, 0), (0.55, 0.12), (0.8, 0.45), (0.78, 0.85), (0.55, 1.25), (0.28, 1.65), (0, 2.0))  # a drop, its tip up


@piece("bl_splash_pool", {"rim": ("4A2460", "Stud"), "water": ("1FB8C8", "Smooth"), "ripple": ("BFF6FF", "Smooth"),
	"drop": ("E8FBFF", "Smooth")})  # 3 Boba Lagoon, the sheet's :288: a board rim round milk-tea water, splash drops
def _(k):
	for s in (-1, 1):
		k.ubox("rim", (25.4, 2.4, 3.2), (0, 0, s * 11.9), soft=0.9)
		k.ubox("rim", (3.2, 2.4, 20.6), (s * 11.1, 0, 0), soft=0.9)
	k.ubox("water", (19.6, 0.7, 21.0), (0, 0, 0), soft=0.3)
	for radius, tube in ((4.4, 0.32), (7.4, 0.28)):
		k.ring("ripple", radius, tube, (0, 0.75, 0), (90, 0, 0))
	for i in range(7):  # the splash crown over the squishy, the tips leaning out
		a = i / 7 * kit.TAU + 0.3
		size = 1.25 if i % 2 else 1.0
		k.lathe("drop", TEAR, (4.6 * math.cos(a), 4.2 + (i % 3) * 0.9, 4.6 * math.sin(a)),
			(math.sin(a) * 25, 0, -math.cos(a) * 25), seg=10, scale=(size, size, size))
	for x, y, z, size in ((-7.0, 8.0, 2.4, 1.6), (-4.4, 9.6, -3.0, 1.3)):  # big ones up on the left
		k.lathe("drop", TEAR, (x, y, z), seg=12, scale=(size, size, size))


MALLOW_WAVES = ((3, 0.07, 1.9), (5, 0.05, 0.3), (8, 0.03, 1.1))


@piece("fd_marshmallow", {"edge": ("7A3E2A", "Smooth"), "goo": ("FFE4EF", "Smooth"), "m": ("FFF8FB", "Smooth"),
	"pink": ("FF9CC9", "Smooth"), "toast": ("DE8A3E", "Smooth")})  # 4 Frozen Dessert Peaks, the sheet's :291
def _(k):
	k.blob("edge", kit.lobes(10.6, MALLOW_WAVES, 1.05, 1.0), 0.4)  # melted goo, burnt at the edge
	k.blob("goo", kit.lobes(9.9, MALLOW_WAVES, 1.05, 1.0), 0.75)
	for x, z, r in ((12.3, -6.8, 0.9), (5.0, 12.4, 1.0), (-2.0, -12.6, 0.8)):
		drop(k, "goo", "edge", x, z, r, 0.6)
	for z, key in ((3.7, "m"), (-3.7, "pink")):  # the sheet's 2 standing + 1 on top, on the left: behind the squishy
		mallow(k, key, 6.6, 5.6, (-9.6, 0, z), toast=False)
	lay(k, "m", 6.2, 9.6, (-9.6, 5.6, 0), "z")
	mallow(k, "pink", 5.4, 4.6, (-5.6, 0, 7.0))  # a heap round the squishy, low on the cameras' side (+X)
	mallow(k, "m", 5.4, 4.6, (-5.8, 0, -7.2))
	lay(k, "pink", 4.8, 5.8, (-2.2, 0, -10.2), "x")
	lay(k, "m", 4.8, 5.8, (-0.4, 0, 9.8), "x")
	lay(k, "pink", 4.4, 5.2, (9.6, 0, 0.4), "z")
	for x, z, key in ((-5.0, 4.8, "m"), (-5.2, -4.2, "pink")):  # small ones stuck in the goo
		mallow(k, key, 3.2, 2.4, (x, 0.2, z), toast=False)


RIM = ((12.9, 0), (12.7, 0.9), (12.1, 1.9), (11.2, 2.5), (10.2, 2.5), (9.5, 1.9), (9.2, 1.2), (9.1, 0.5))


@piece("lv_lava_pit", {"rim": ("4A2546", "Stud"), "rock": ("2E1A33", "Smooth"), "lava": ("FF5A1F", "Neon"),
	"glow": ("FFB03A", "Neon")})  # 5 Lava Volcano, the sheet's :294: a basalt rim round lava, bubbles
def _(k):
	k.lathe("rim", RIM, (0, 0, 0), seg=32)
	k.blob("lava", kit.lobes(9.5, ()), 0.7, seg=32, edge=0.4)
	k.ring("glow", 9.3, 0.42, (0, 0.75, 0), (90, 0, 0))  # a bright rim inside the dark one: the lava lane is dark
	for x, z, d in ((4.0, 5.2, 2.6), (-3.6, -5.4, 2.0), (6.2, -2.6, 1.5), (-6.0, 1.0, 1.7)):
		k.ball("glow", d, (x, 0.7, z), dome=True, seg=10)
		k.ring("glow", d * 0.75, 0.16, (x, 0.78, z), (90, 0, 0), seg=12)
	for x, z, w, h, turn, tilt in ((-11.2, 0.4, 4.0, 4.8, 15, 14), (-10.0, 6.0, 3.4, 3.8, 50, -18),
			(-9.6, -6.2, 3.4, 3.4, -30, 20), (-5.0, 10.6, 2.8, 2.8, 80, -16), (-4.8, -10.8, 2.6, 2.4, 10, 18),
			(2.4, 11.6, 2.2, 2.0, 40, -14)):  # chunky rocks sunk in the rim, high on the left
		k.box("rock", (w, h, w * 0.9), (x, 1.4 + h / 2, z), (tilt, turn, tilt * 0.6), soft=0.45)


def puff(k, key, shade, d, x, z):  # a cloud puff on the lane, its shade round the foot
	k.ball(shade, 2, (x, 0, z), (d * 0.54, d * 0.16, d * 0.54), dome=True, seg=16)  # an even ring count: a flat foot
	k.ball(key, d, (x, 0.39 * d, z), (1, 0.78, 1))


@piece("rr_cloud_gap", {"hole": ("2B1E66", "Smooth"), "swirl": ("7C5CFF", "Smooth"), "shade": ("C7B6FF", "Smooth"),
	"cloud": ("FFFFFF", "Smooth")})  # 6 Rainbow Road, the sheet's :297: soft clouds round a gap, their shade
def _(k):
	k.blob("hole", kit.lobes(8.2, ((3, 0.05, 0.7), (5, 0.04, 2.0))), 0.3, edge=0.3)
	for radius, tube in ((3.0, 0.24), (5.6, 0.24)):  # it swirls
		k.ring("swirl", radius, tube, (0, 0.34, 0), (90, 0, 0))
	for deg, r, d in ((110, 9.4, 6.0), (140, 9.6, 7.4), (172, 9.4, 8.0), (204, 9.6, 7.6), (232, 9.6, 6.4), (258, 9.8, 5.2),
			(-88, 10.4, 4.6), (-18, 10.6, 4.2), (22, 10.6, 4.2), (88, 10.2, 4.8)):
		puff(k, "cloud", "shade", d, *ring_at(deg, r))


SOFT_WAVES = ((3, 0.06, 2.6), (6, 0.05, 0.4))


@piece("dh_soft_cloud", {"edge": ("D98A00", "Smooth"), "cloud": ("FFC93C", "Smooth"), "hi": ("FFF1BF", "Smooth")})
def _(k):  # 7 Divine Heaven, the sheet's :300: a soft gold cloud with highlights
	k.blob("edge", kit.lobes(11.0, SOFT_WAVES), 0.4)
	k.blob("cloud", kit.lobes(10.3, SOFT_WAVES), 0.8)
	for deg, r, d in ((112, 9.2, 6.4), (145, 9.6, 7.6), (178, 9.4, 8.2), (210, 9.6, 7.4), (240, 9.4, 6.0), (-80, 10.2, 4.4),
			(-10, 10.6, 4.0), (30, 10.4, 4.4), (90, 10.0, 5.0)):
		x, z = ring_at(deg, r)
		k.ball("cloud", d, (x, 0.39 * d, z), (1, 0.78, 1))
		k.ball("hi", d * 0.5, (x + 0.06 * d, 0.7 * d, z), (1, 0.45, 1), seg=14)  # a soft light cap on top


kit.main(PIECES, yaw=32, figure=(12.6, -12.5), end_shot=True)
