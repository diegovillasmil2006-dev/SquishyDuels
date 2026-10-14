"""Squishy Duels lobby mesh library, round 1 (lobby look upgrade FIX 3, PLAN.md §5.1-§5.4).

Builds the 5 sets (Donut Arch, tower_pillar, Lollipop, Cupcake tree, Cloud Bunny) from the design's own formulas
(design-new/sd/toys.js, kit.js, lobby.js) at the game's sizes, exports SD_MeshLibrary.glb and renders previews.
Run it as its own Blender process, never inside an open scene:

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python lobby_meshes.py -- <out_dir>

Rules (PLAN §5.2): 1 Blender unit = 1 stud; every point is computed in Roblox axes (X, Y up, Z toward the path / hub /
viewer) and written to Blender as (X, -Z, Y), so the glTF "+Y up" export gives back Roblox (X, Y, Z). One closed object
per Palette colour, object and mesh data share the name, no UVs / materials / vertex colours, Shade Smooth by Angle
30 degrees, identity transforms. The printout gives each piece's triangles, size and centre in its set's frame (Roblox
axes), ready for WorldLook.MESHES. Colours in the preview are Art/Palette values (preview only, never exported).
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

TAU = 2 * math.pi
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not ARGV:  # never default to the script's folder: in the repo the snapshot would commit the .glb and previews
	raise SystemExit("usage: blender --background --factory-startup --python lobby_meshes.py -- <out_dir>")
OUT = os.path.abspath(ARGV[0])
os.makedirs(OUT, exist_ok=True)
SMOOTH_ANGLE = math.radians(30)

# ---------------------------------------------------------------------------------------------------- design helpers

M32 = 0xFFFFFFFF


def mulberry32(seed):
	"""kit.js rng(seed), bit-exact (uint32 masks stand in for JS's |0 / >>> 0 / Math.imul)."""
	a = seed & M32

	def imul(x, y):
		return (x * y) & M32

	def rand():
		nonlocal a
		a = (a + 0x6D2B79F5) & M32
		t = imul(a ^ (a >> 15), 1 | a)
		t = ((t + imul(t ^ (t >> 7), 61 | t)) & M32) ^ t
		return ((t ^ (t >> 14)) & M32) / 4294967296

	return rand


# Self-check against node running the design's kit.js rng(7) (rng_check.mjs, 2026-10-14).
_r = mulberry32(7)
_got = [_r(), _r(), _r()]
_want = [0.011704753153026104, 0.06195825757458806, 0.97690763277933]
assert _got == _want, f"mulberry32 port differs from kit.js rng(7): {_got} vs {_want}"
print("RNG self-check (kit.js rng(7) first 3):", _got)


def clamp(x, a, b):
	return min(b, max(a, x))


def smooth(a, b, x):  # kit.js smooth
	t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)


def sflat(y, t, k):  # kit.js sflat
	return y if y >= t else t - k * (1 - math.exp((y - t) / k))


def super_r(d, a, b, c, n=2, m=2):  # kit.js superR
	xz = (abs(d.x / a) ** n + abs(d.z / c) ** n) ** (m / n)
	yy = abs(d.y / b) ** m
	return (xz + yy) ** (-1 / m)


def v3(x, y, z):
	return Vector((x, y, z))


# ------------------------------------------------------------------------------------------ geometry (Roblox axes)


class Geo:
	"""Vertices (Roblox axes) and faces (index tuples); orientation is fixed later by recalc_face_normals."""

	def __init__(self, verts=None, faces=None):
		self.v = list(verts or [])
		self.f = list(faces or [])

	def add(self, other):
		o = len(self.v)
		self.v += other.v
		self.f += [tuple(i + o for i in f) for f in other.f]
		return self

	def mapped(self, fn):
		return Geo([fn(p) for p in self.v], self.f)


def grid(points, wrap_u=False, wrap_v=False):
	"""points[i][j] (i along u, j along v) -> quads. A wrapped direction must not repeat its first row."""
	nu, nv = len(points), len(points[0])
	idx = lambda i, j: (i % nu) * nv + (j % nv)
	faces = []
	for i in range(nu if wrap_u else nu - 1):
		for j in range(nv if wrap_v else nv - 1):
			faces.append((idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)))
	return Geo([p for row in points for p in row], faces)


def slab(outer, inner):
	"""A closed sheet: two open grids of the same shape plus the 4 border strips (a hand-made Solidify)."""
	nu, nv = len(outer), len(outer[0])
	g = grid(outer)
	g.add(grid(inner))
	n = nu * nv
	o = lambda i, j: i * nv + j
	border = [(i, 0) for i in range(nu)] + [(nu - 1, j) for j in range(1, nv)]
	border += [(i, nv - 1) for i in range(nu - 2, -1, -1)] + [(0, j) for j in range(nv - 2, 0, -1)]
	for k in range(len(border)):
		a, b = border[k], border[(k + 1) % len(border)]
		g.f.append((o(*a), o(*b), n + o(*b), n + o(*a)))
	return g


def torus(R, t, ring, tube, center=v3(0, 0, 0), axis="Z", theta0=0.0):
	"""Closed torus; vertex 0 of every ring sits on the outer equator (theta0 = 0), so the bounds are exact."""
	pts = []
	for i in range(ring):
		phi = TAU * i / ring
		row = []
		for j in range(tube):
			th = theta0 + TAU * j / tube
			rad = R + t * math.cos(th)
			a, b, h = rad * math.cos(phi), rad * math.sin(phi), t * math.sin(th)
			p = v3(a, b, h) if axis == "Z" else v3(a, h, b)  # axis Y: the ring lies in XZ
			row.append(center + p)
		pts.append(row)
	return grid(pts, wrap_u=True, wrap_v=True)


def cylinder(radius, y0, y1, sides, axis="Y", center=v3(0, 0, 0)):
	"""Closed cylinder with n-gon caps; along Y from y0 to y1, or along Z (centred on `center`, length y1 - y0)."""
	ring0, ring1 = [], []
	for k in range(sides):
		a = TAU * k / sides
		c, s = radius * math.cos(a), radius * math.sin(a)
		if axis == "Y":
			ring0.append(center + v3(c, y0, s))
			ring1.append(center + v3(c, y1, s))
		else:
			ring0.append(center + v3(c, s, y0))
			ring1.append(center + v3(c, s, y1))
	g = grid([ring0, ring1], wrap_v=True)
	g.f.append(tuple(range(sides)))
	g.f.append(tuple(range(sides, 2 * sides)))
	return g


def uv_sphere(ws, hs, fn):
	"""kit.js warpSphere on our own UV sphere: fn(unit direction) -> point. Poles are single vertices."""
	verts = [fn(v3(0, 1, 0))]
	for k in range(1, hs):
		th = math.pi * k / hs
		for j in range(ws):
			ph = TAU * j / ws
			verts.append(fn(v3(math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph))))
	verts.append(fn(v3(0, -1, 0)))
	ring = lambda k, j: 1 + (k - 1) * ws + (j % ws)
	south = len(verts) - 1
	faces = [(0, ring(1, j + 1), ring(1, j)) for j in range(ws)]
	for k in range(1, hs - 1):
		for j in range(ws):
			faces.append((ring(k, j), ring(k, j + 1), ring(k + 1, j + 1), ring(k + 1, j)))
	faces += [(south, ring(hs - 1, j), ring(hs - 1, j + 1)) for j in range(ws)]
	return Geo(verts, faces)


def ring_sphere(dys, ws, fn):
	"""A UV sphere with rings at the given direction heights d.y (poles added); fn(unit direction) -> point.
	Each quad is split along (ring k, column j) -> (ring k + 1, column j + 1): the frosting swirl's ridges
	(3 phi + 16 d.y = const) run that way as d.y falls, so the triangle edges follow them."""
	verts = [fn(v3(0, 1, 0))]
	for dy in dys:
		s = math.sqrt(1 - dy * dy)
		for j in range(ws):
			ph = TAU * j / ws
			verts.append(fn(v3(s * math.cos(ph), dy, s * math.sin(ph))))
	verts.append(fn(v3(0, -1, 0)))
	hs = len(dys) + 1
	ring = lambda k, j: 1 + (k - 1) * ws + (j % ws)
	south = len(verts) - 1
	faces = [(0, ring(1, j + 1), ring(1, j)) for j in range(ws)]
	for k in range(1, hs - 1):
		for j in range(ws):
			faces.append((ring(k, j), ring(k, j + 1), ring(k + 1, j + 1)))
			faces.append((ring(k, j), ring(k + 1, j + 1), ring(k + 1, j)))
	faces += [(south, ring(hs - 1, j), ring(hs - 1, j + 1)) for j in range(ws)]
	return Geo(verts, faces)


def catmull_rom_centripetal(points):
	"""three.js CatmullRomCurve3(points, false, 'centripetal').getPoint(t)."""
	P = [v3(*p) for p in points]
	n = len(P)

	def get_point(t):
		p = (n - 1) * t
		i = math.floor(p)
		w = p - i
		if w == 0 and i == n - 1:
			i, w = n - 2, 1.0
		p0 = P[i - 1] if i > 0 else P[0] + (P[0] - P[1])
		p1, p2 = P[i], P[i + 1]
		p3 = P[i + 2] if i + 2 < n else P[n - 1] + (P[n - 1] - P[n - 2])
		dt0 = (p1 - p0).length_squared ** 0.25
		dt1 = (p2 - p1).length_squared ** 0.25
		dt2 = (p3 - p2).length_squared ** 0.25
		if dt1 < 1e-4:
			dt1 = 1.0
		if dt0 < 1e-4:
			dt0 = dt1
		if dt2 < 1e-4:
			dt2 = dt1
		out = []
		for x0, x1, x2, x3 in zip(p0, p1, p2, p3):
			t1 = ((x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1) * dt1
			t2 = ((x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2) * dt1
			c2 = -3 * x1 + 3 * x2 - 2 * t1 - t2
			c3 = 2 * x1 - 2 * x2 + t1 + t2
			out.append(x1 + t1 * w + c2 * w * w + c3 * w * w * w)
		return Vector(out)

	# three.js Curve.getPointAt: arc-length parameter over 200 divisions.
	div = 200
	samples = [get_point(k / div) for k in range(div + 1)]
	lengths = [0.0]
	for k in range(1, div + 1):
		lengths.append(lengths[-1] + (samples[k] - samples[k - 1]).length)

	def get_point_at(u):
		target = u * lengths[-1]
		lo = 0
		while lo < div - 1 and lengths[lo + 1] <= target:
			lo += 1
		seg = lengths[lo + 1] - lengths[lo]
		frac = (target - lengths[lo]) / seg if seg > 0 else 0
		return get_point((lo + frac) / div)

	return get_point_at


def taper_tube(points, r_fn, tubular, radial):
	"""kit.js taperTube (closed: n-gon cap at the start; a radius-0 end becomes one tip vertex)."""
	at = catmull_rom_centripetal(points)
	cs = [at(i / tubular) for i in range(tubular + 1)]
	ref = v3(0, 0, 1)
	verts, faces, rings = [], [], []
	normal = None
	for i, c in enumerate(cs):
		tan = (cs[min(i + 1, tubular)] - cs[max(i - 1, 0)]).normalized()
		if normal is None:
			normal = tan.cross(ref).normalized()
		normal = (normal - tan * normal.dot(tan)).normalized()  # parallel transport
		binormal = tan.cross(normal)
		r = r_fn(i / tubular)
		if r <= 1e-9:
			rings.append([len(verts)])
			verts.append(c)
			continue
		ring = []
		for j in range(radial):
			a = TAU * j / radial
			ring.append(len(verts))
			verts.append(c + (normal * math.cos(a) + binormal * math.sin(a)) * r)
		rings.append(ring)
	faces.append(tuple(rings[0]))
	for a, b in zip(rings, rings[1:]):
		if len(b) == 1:
			faces += [(a[j], a[(j + 1) % radial], b[0]) for j in range(radial)]
		else:
			faces += [(a[j], a[(j + 1) % radial], b[(j + 1) % radial], b[j]) for j in range(radial)]
	return Geo(verts, faces)


def oriented_sprinkle(p, axis, radius=0.15, body=0.5):
	"""A 4-sided stand-in for the design's capsule along `axis` centred at `p`: square body 0.5 long, one pyramid tip
	per end (16 triangles, the budget). Not a smooth capsule: up close the tips read as small pointed crystals.
	Roll = three.js setFromUnitVectors(Y, axis) of a capsule whose 4 sides sit on +-X and +-Z."""
	rot = v3(0, 1, 0).rotation_difference(axis)
	h = body / 2
	local = [v3(0, h + radius, 0)]
	for y in (h, -h):
		for k in range(4):
			a = k * math.pi / 2
			local.append(v3(radius * math.sin(a), y, radius * math.cos(a)))
	local.append(v3(0, -h - radius, 0))
	verts = [p + rot @ q for q in local]
	faces = [(0, 1 + k, 1 + (k + 1) % 4) for k in range(4)]
	faces += [(1 + k, 5 + k, 5 + (k + 1) % 4, 1 + (k + 1) % 4) for k in range(4)]
	faces += [(9, 5 + (k + 1) % 4, 5 + k) for k in range(4)]
	return Geo(verts, faces)


def mirror_z(g):
	return Geo([v3(p.x, p.y, -p.z) for p in g.v], g.f)


# ----------------------------------------------------------------------------------------------------- the 5 sets

PALETTE = {  # Art/Palette.luau values: the preview's colours only (the game colours every piece itself)
	"White": "#FFFFFF",
	"LobbyWafer": "#E5B06C",
	"LobbySky": "#8FD3F4",
	"LobbyButter": "#FFD25E",
	"LobbyMint": "#5FD3AE",
	"LobbyStrawberry": "#F2687F",
	"LobbyTrimWhite": "#FFFDF8",
	"LobbyCottonPink": "#F9B8D0",
	"BasePink": "#FF5FA2",  # stands in for open.full: BaseService tints the icing with the plot's colour
}


def donut_arch():
	"""Frame: arch = F * CFrame.new(0, GATE_PILLAR.Y, gateZ); ring in XY, +Z faces the path and the hub."""
	R, r, SZ = 9.0, 1.3, 0.82  # archRadius, DONUT_TUBE, toys.js:187
	pieces = {}

	# Dough: half torus (phi 0..pi), z * SZ, flat end caps on y = 0.
	n_phi, n_th = 30, 16
	pts = []
	for i in range(n_phi + 1):
		phi = math.pi * i / n_phi
		row = []
		for j in range(n_th):
			th = TAU * j / n_th
			rad = R + r * math.cos(th)
			row.append(v3(rad * math.cos(phi), rad * math.sin(phi), SZ * r * math.sin(th)))
		pts.append(row)
	dough = grid(pts, wrap_v=True)
	dough.f.append(tuple(range(n_th)))
	dough.f.append(tuple(range(n_phi * n_th, (n_phi + 1) * n_th)))
	pieces["DonutArch_Dough"] = dough

	# Icing: toys.js:189-190 with our R and r, phi 0.12..pi-0.12, closed by a 0.08 inward skin, mirrored onto -Z.
	A = lambda phi: 1.28 + 0.2 * math.sin(5 * phi + 0.6) + 0.12 * math.sin(11 * phi + 2.0) + 0.06 * math.sin(17 * phi)

	def ice(phi, v, extra=0.0, inset=0.0):
		a = A(phi)
		beta = math.pi / 2 - a + 2 * a * v
		rr = r * (0.985 + 0.085 * max(0.0, math.sin(math.pi * v)) ** 0.3) + extra - inset
		rad = R + rr * math.cos(beta)
		return v3(rad * math.cos(phi), rad * math.sin(phi), rr * math.sin(beta))  # unscaled z (SZ applied later)

	n_u, n_v, lo, hi = 34, 8, 0.12, math.pi - 0.12
	squash = lambda p: v3(p.x, p.y, SZ * p.z)
	outer = [[squash(ice(lo + (hi - lo) * i / n_u, j / n_v)) for j in range(n_v + 1)] for i in range(n_u + 1)]
	inner = [[squash(ice(lo + (hi - lo) * i / n_u, j / n_v, inset=0.08)) for j in range(n_v + 1)] for i in range(n_u + 1)]
	front = slab(outer, inner)
	pieces["DonutArch_Icing"] = Geo().add(front).add(mirror_z(front))

	# Sprinkles: toys.js:191-203 exactly (same draws), kept on the arch half, mirrored with the icing.
	rand = mulberry32(7)
	bins = [Geo() for _ in range(4)]
	kept = 0
	for i in range(64):
		u = rand()
		v = 0.18 + rand() * 0.64
		phi = u * TAU
		dphi = abs(((phi - math.pi * 1.5 + math.pi * 3) % TAU) - math.pi)
		if dphi < 0.8 and 0.28 < v < 0.72:
			continue
		p = ice(phi, v, extra=0.03)
		c0 = v3(R * math.cos(phi), R * math.sin(phi), 0)
		n = p - c0
		p = v3(p.x, p.y, p.z * SZ)
		n = v3(n.x, n.y, n.z / SZ).normalized()
		tg = v3(rand() - 0.5, rand() - 0.5, rand() - 0.5).cross(n).normalized()
		if not (lo <= phi <= hi):
			continue  # the draws above are still taken, so the kept ones sit where the design puts them
		s = oriented_sprinkle(p, tg)
		bins[i % 4].add(s).add(mirror_z(s))
		kept += 1
	print(f"DonutArch: {kept} sprinkles kept per face ({2 * kept} in all)")
	for k, token in enumerate(("White", "Sky", "Butter", "Mint")):
		pieces["DonutArch_Sprinkles_" + token] = bins[k]
	tokens = {
		"DonutArch_Dough": "LobbyWafer",
		"DonutArch_Icing": "BasePink",
		"DonutArch_Sprinkles_White": "White",
		"DonutArch_Sprinkles_Sky": "LobbySky",
		"DonutArch_Sprinkles_Butter": "LobbyButter",
		"DonutArch_Sprinkles_Mint": "LobbyMint",
	}
	return pieces, tokens


def tower_pillar():
	"""lobby.js:174 rb(6, 26, 6, 4) = superF(w/2, h/2, d/2, 4, 4), i.e. |x/a|^4 + |z/a|^4 + |y/b|^4 = 1, at the game's
	7 x 34.2 x 7; frame = the pillar centre. Sampled with the superquadric map p = (a, b, a) * signed sqrt(s) of the UV
	sphere point s: the same surface, but the vertices gather where it curves (a radial projection of a plain sphere
	puts only 2 rings on the rounded top at this 4.9 aspect)."""
	a, b = 3.5, 17.1
	sq = lambda t: math.copysign(math.sqrt(abs(t)), t)
	return {"tower_pillar": uv_sphere(32, 24, lambda s: v3(a * sq(s.x), b * sq(s.y), a * sq(s.z)))}, {
		"tower_pillar": "LobbyMint"}


def lollipop():
	"""lobby.js:40-47 with h 24, rad 7 (WorldLayout lollipops); frame = CFrame.new(foot)."""
	h, rad = 24.0, 7.0
	white = cylinder(rad * 0.09, 0, h, 16)
	white.add(cylinder(rad, -rad * 0.125, rad * 0.125, 56, axis="Z", center=v3(0, h, 0)))
	ring_a, ring_b = Geo(), Geo()
	segs = {0.9: 56, 0.7: 44, 0.5: 32, 0.3: 24}
	for i, k in enumerate((0.9, 0.7, 0.5, 0.3)):
		for side in (-1, 1):
			t = torus(rad * k, rad * 0.07, segs[k], 8, center=v3(0, h, side * rad * 0.12))
			(ring_b if i % 2 else ring_a).add(t)
	pieces = {"Lollipop_White": white, "Lollipop_RingA": ring_a, "Lollipop_RingB": ring_b}
	tokens = {"Lollipop_White": "LobbyTrimWhite", "Lollipop_RingA": "LobbyStrawberry", "Lollipop_RingB": "LobbyMint"}
	return pieces, tokens


def cupcake_tree():
	"""toys.js:390-392 at x11.1 on the tree's ground frame; trunk (y 0-4) and cherry (y 8.3) stay parts."""
	# Cup: pleated liner wall (radius linear in height, so one row is the exact shape), flat base and top caps,
	# plus the rim bead in the same colour.
	n = 56
	wall = []
	for w, y in ((0.0, 4.0), (1.0, 4.0 + 1.78)):
		row = []
		for k in range(n):
			phi = TAU * k / n
			rr = (1.443 + 0.555 * w) * (1 + 0.028 * math.cos(28 * phi))
			row.append(v3(rr * math.cos(phi), y, -rr * math.sin(phi)))
		wall.append(row)
	cup = grid(wall, wrap_v=True)
	cup.f.append(tuple(range(n)))
	cup.f.append(tuple(range(n, 2 * n)))
	cup.add(torus(2.02, 0.12, 40, 4, center=v3(0, 5.78, 0), axis="Y"))

	# Frosting: superF(0.19, 0.15, 0.18) x the swirl (no face mask), sflat bottom, then fitted to today's bounds
	# (the tree_frosting egg: 4.6 x 4.6 across, flat bottom at 5.6, top at 8.0). 576 triangles without decimation:
	# 24 columns (8 per swirl turn) and 12 rings about 0.1 apart in d.y (4 per swirl wave), gathered on the visible
	# dome. (A 40 x 28 warpSphere collapse-decimated to 600 came out blotchy with a pinched top, and columns twisted
	# along the swirl folded into a sawtooth: previews, 2026-10-14.)
	def f(d):
		p = d * super_r(d, 0.19, 0.15, 0.18)
		phi = math.atan2(p.z, p.x)
		p = p * (1 + 0.035 * math.sin(3 * phi + 16 * d.y) * smooth(-0.2, 0.2, d.y))
		return v3(p.x, sflat(p.y, -0.01, 0.012), p.z)

	frost = ring_sphere([0.93, 0.85, 0.76, 0.66, 0.55, 0.44, 0.33, 0.22, 0.11, 0.0, -0.12, -0.4], 24, f)
	xs = [p.x for p in frost.v]
	ys = [p.y for p in frost.v]
	zs = [p.z for p in frost.v]
	kx, kz = 4.6 / (max(xs) - min(xs)), 4.6 / (max(zs) - min(zs))
	ky = (8.0 - 5.6) / (max(ys) - min(ys))
	y0 = min(ys)
	frost = frost.mapped(lambda p: v3(p.x * kx, 5.6 + (p.y - y0) * ky, p.z * kz))
	pieces = {"CupcakeTree_Cup": cup, "CupcakeTree_Frosting": frost}
	tokens = {"CupcakeTree_Cup": "LobbyWafer", "CupcakeTree_Frosting": "LobbyCottonPink"}
	return pieces, tokens


def cloud_bunny():
	"""toys.js:365-375 body + ears (no face, pink inner ears or rainbow); frame = buildSky's groundFrame, +Z to the
	island centre. Scaled evenly so the body is 17 wide with its centre at (0, 1, 0); remeshed later."""
	lumps = [(0, 1, 0.2, 0.12), (0.7, 0.6, 0, 0.13), (-0.7, 0.6, 0, 0.13), (0.5, 0.5, -0.6, 0.12),
		(-0.5, 0.5, -0.6, 0.12), (1, 0, 0.2, 0.14), (-1, 0, 0.2, 0.14), (0.6, 0.1, -0.8, 0.12),
		(-0.6, 0.1, -0.8, 0.12), (0, 0.4, -1, 0.13), (0.9, -0.3, 0.5, 0.1), (-0.9, -0.3, 0.5, 0.1), (0, -0.2, -1, 0.1)]
	lumps = [(v3(x, y, z).normalized(), a) for x, y, z, a in lumps]

	def f(d):
		p = d * super_r(d, 0.24, 0.17, 0.19)
		b = sum(a * 1.5 * math.exp(-(1 - d.dot(l)) / 0.045) for l, a in lumps)
		p = p * (1 + b)
		return v3(p.x, sflat(p.y, -0.12, 0.03), p.z)

	body = uv_sphere(48, 32, f)
	ear_r = lambda u: 0.04 * max(0.0, math.sin(math.pi * (0.1 + 0.9 * u))) ** 0.5
	ears = Geo()
	for pts in (
		[(0.07, 0.14, -0.01), (0.085, 0.26, -0.03), (0.1, 0.36, -0.06), (0.11, 0.43, -0.09)],
		[(-0.07, 0.14, -0.01), (-0.09, 0.26, -0.02), (-0.15, 0.31, -0.02), (-0.22, 0.3, 0.0)],
	):
		z0 = pts[0][2]
		ear = taper_tube(pts, ear_r, 16, 8).mapped(lambda p: v3(p.x, p.y, z0 + (p.z - z0) * 0.6))  # pivot scale.z 0.6
		ears.add(ear)
	xs = [p.x for p in body.v]
	ys = [p.y for p in body.v]
	zs = [p.z for p in body.v]
	k = 17.0 / (max(xs) - min(xs))
	c = v3((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)
	place = lambda p: (p - c) * k + v3(0, 1, 0)
	print(f"CloudBunny: design body {max(xs) - min(xs):.4f} wide, scale x{k:.3f}")
	return {"CloudBunny": body.mapped(place).add(ears.mapped(place))}, {"CloudBunny": "White"}


# ------------------------------------------------------------------------------------------------------- Blender


def to_blender(p):
	return (p.x, -p.z, p.y)  # Roblox (X, Y, Z) -> Blender (X, -Z, Y); glTF +Y up gives back (X, Y, Z)


def to_roblox(co):
	return v3(co[0], co[2], -co[1])


def srgb_to_linear(hexstr):
	out = []
	for k in (1, 3, 5):
		c = int(hexstr[k:k + 2], 16) / 255
		out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
	return (*out, 1.0)


LIB = bpy.data.collections.new("SD_MeshLibrary")
bpy.context.scene.collection.children.link(LIB)


def finish_mesh(me, full_smooth):
	"""Outward normals, triangles (what the exporter writes), then Smooth by Angle 30 degrees."""
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
	closed = all(len(e.link_faces) == 2 for e in bm.edges)
	bm.to_mesh(me)
	bm.free()
	me.shade_smooth()
	if not full_smooth:
		me.set_sharp_from_angle(angle=SMOOTH_ANGLE)
	me.update()
	return closed


def make_object(name, geo, offset, color_token):
	me = bpy.data.meshes.new(name)
	bm = bmesh.new()
	vs = [bm.verts.new(to_blender(p + offset)) for p in geo.v]
	for f in geo.f:
		bm.faces.new([vs[i] for i in f])
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	LIB.objects.link(obj)
	obj.color = srgb_to_linear(PALETTE[color_token])
	return obj


def bake_modifier(obj, mod):
	"""Applies one modifier through the evaluated mesh (no operator context needed in background mode)."""
	dg = bpy.context.evaluated_depsgraph_get()
	new = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
	old = obj.data
	obj.modifiers.remove(mod)
	obj.data = new
	bpy.data.meshes.remove(old)
	new.name = obj.name


def tri_count(me):
	return sum(len(p.vertices) - 2 for p in me.polygons)


def decimate_to(obj, budget):
	"""Collapse-decimates to `budget` triangles or fewer; returns the triangle count before."""
	start = tri_count(obj.data)
	base = obj.data.copy()
	ratio = budget / start * 0.97
	for _ in range(20):
		mod = obj.modifiers.new("Decimate", "DECIMATE")
		mod.decimate_type = "COLLAPSE"
		mod.use_collapse_triangulate = True
		mod.ratio = ratio
		bake_modifier(obj, mod)
		if tri_count(obj.data) <= budget:
			break
		bad = obj.data  # retry from the undecimated mesh with a smaller ratio
		obj.data = base.copy()
		bpy.data.meshes.remove(bad)
		ratio *= 0.97
	bpy.data.meshes.remove(base)
	obj.data.name = obj.name
	assert tri_count(obj.data) <= budget, f"{obj.name}: {tri_count(obj.data)} > {budget}"
	return start


def bounds_roblox(obj, offset):
	pts = [to_roblox(v.co) - offset for v in obj.data.vertices]
	lo = v3(min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))
	hi = v3(max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))
	return hi - lo, (hi + lo) / 2


# -------------------------------------------------------------------------------------------------------- build

for o in list(bpy.data.objects):  # the factory scene's cube, light and camera (this process only)
	bpy.data.objects.remove(o)

BUDGET = {  # PLAN §5.2 (per piece; Lollipop = all pieces)
	"DonutArch_Dough": 1000,
	"DonutArch_Icing": 2600,
	"tower_pillar": 1500,
	"CupcakeTree_Cup": 600,
	"CupcakeTree_Frosting": 600,
	"CloudBunny": 1500,
}
SPRINKLE_TRIS = 16
LOLLIPOP_BUDGET = 5300
# Smooth all over like the design's own normals, where 30 degrees would facet a round body the budget keeps coarse:
# the 8-sided candy tubes (design TOR(.., 8, 56)), the sprinkles (4-sided with short pointed ends for the budget, not
# the design's round capsules; smoothing only softens their sides) and the frosting swirl.
FULL_SMOOTH = {"Lollipop_RingA", "Lollipop_RingB", "DonutArch_Sprinkles_White", "DonutArch_Sprinkles_Sky",
	"DonutArch_Sprinkles_Butter", "DonutArch_Sprinkles_Mint", "CupcakeTree_Frosting"}
# noShadow in the printout (WorldLook.MESHES): the sprinkles and the cloud (big bounds, the < 2-stud rule misses them),
# and the lollipop rings (their shadow falls inside the disk's, and they spin: shadow work every frame for nothing).
NO_SHADOW = {"DonutArch_Sprinkles_White", "DonutArch_Sprinkles_Sky", "DonutArch_Sprinkles_Butter",
	"DonutArch_Sprinkles_Mint", "CloudBunny", "Lollipop_RingA", "Lollipop_RingB"}

SETS = [
	("DonutArch", donut_arch),
	("TowerPillar", tower_pillar),
	("Lollipop", lollipop),
	("CupcakeTree", cupcake_tree),
	("CloudBunny", cloud_bunny),
]

report = {"sets": [], "objects": {}}
cursor = 0.0
GAP = 8.0
set_objects = {}
for set_name, build in SETS:
	pieces, tokens = build()
	xs = [p.x for g in pieces.values() for p in g.v]
	offset = v3(cursor - min(xs), 0, 0)  # library layout only: sets side by side along X
	cursor += max(xs) - min(xs) + GAP
	objs = []
	for name, geo in pieces.items():
		obj = make_object(name, geo, offset, tokens[name])
		if name == "CloudBunny":
			mod = obj.modifiers.new("Remesh", "REMESH")
			mod.mode = "VOXEL"
			mod.voxel_size = 0.2
			mod.adaptivity = 0.0
			bake_modifier(obj, mod)
			raw = decimate_to(obj, BUDGET[name])
			print(f"CloudBunny: voxel remesh 0.2 -> {raw} triangles, decimated to {tri_count(obj.data)}")
		closed = finish_mesh(obj.data, name in FULL_SMOOTH)
		objs.append(obj)
		size, center = bounds_roblox(obj, offset)
		me = obj.data
		info = {
			"set": set_name,
			"tris": tri_count(me),
			"size": [round(c, 3) for c in size],
			"center": [round(c, 3) for c in center],
			"offset_x": offset.x,
			"closed": closed,
			"uvs": len(me.uv_layers),
			"materials": len(me.materials),
			"colors": len(me.color_attributes),
			"token": tokens[name],
		}
		report["objects"][name] = info
	set_objects[set_name] = objs
	report["sets"].append({"name": set_name, "offset_x": offset.x, "pieces": list(pieces.keys())})

# ------------------------------------------------------------------------------------------------- checks + print

problems = []
for name, info in report["objects"].items():
	if name in BUDGET and info["tris"] > BUDGET[name]:
		problems.append(f"{name}: {info['tris']} triangles > {BUDGET[name]}")
	if not info["closed"]:
		problems.append(f"{name}: not closed")
	if info["uvs"] or info["materials"] or info["colors"]:
		problems.append(f"{name}: has UVs / materials / colours")
for name in ("White", "Sky", "Butter", "Mint"):
	obj = bpy.data.objects["DonutArch_Sprinkles_" + name]
	if tri_count(obj.data) % SPRINKLE_TRIS or len(obj.data.polygons) == 0:
		problems.append(f"sprinkles {name}: {tri_count(obj.data)} triangles is not a whole number of 16-tri sprinkles")
lolli = sum(report["objects"][n]["tris"] for n in ("Lollipop_White", "Lollipop_RingA", "Lollipop_RingB"))
if lolli > LOLLIPOP_BUDGET:
	problems.append(f"Lollipop: {lolli} triangles > {LOLLIPOP_BUDGET}")
for o in LIB.objects:
	if o.data.name != o.name or o.matrix_world != Matrix.Identity(4):
		problems.append(f"{o.name}: mesh name or transform off")

print("\n==== SD_MeshLibrary round 1 (Roblox axes; size and centre in each set's frame) ====")
fmt = lambda v: f"Vector3.new({v[0]:g}, {v[1]:g}, {v[2]:g})"
for s in report["sets"]:
	tris = sum(report["objects"][n]["tris"] for n in s["pieces"])
	print(f"-- {s['name']} ({tris} triangles)")
	for n in s["pieces"]:
		i = report["objects"][n]
		print(f"   {n:28s} {i['tris']:5d} tris  size ({i['size'][0]:g}, {i['size'][1]:g}, {i['size'][2]:g})  "
			f"centre ({i['center'][0]:g}, {i['center'][1]:g}, {i['center'][2]:g})  closed={i['closed']}")
print("\n-- Lua for WorldLook.MESHES")
for s in report["sets"]:
	print(f"\t{s['name']} = {{")
	for n in s["pieces"]:
		i = report["objects"][n]
		ns = ", noShadow = true" if n in NO_SHADOW else ""
		print(f'\t\t{{ name = "{n}", size = {fmt(i["size"])}, center = {fmt(i["center"])}{ns} }},')
	print("\t},")
report["problems"] = problems
print("\nPROBLEMS:", problems if problems else "none")
with open(os.path.join(OUT, "lobby_meshes_report.json"), "w", encoding="utf-8") as fh:
	json.dump(report, fh, indent=1)

# ------------------------------------------------------------------------------------------------------- export

bpy.ops.object.select_all(action="DESELECT")
for o in LIB.objects:
	o.select_set(True)
bpy.context.view_layer.objects.active = LIB.objects[0]
glb = os.path.join(OUT, "SD_MeshLibrary.glb")
bpy.ops.export_scene.gltf(
	filepath=glb,
	export_format="GLB",
	use_selection=True,
	export_yup=True,
	export_apply=True,
	export_texcoords=False,
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

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
scene.display.shading.show_backface_culling = True  # a flipped face would show as a hole
scene.display.shading.show_object_outline = True
scene.display.shading.show_cavity = True
scene.display.shading.show_shadows = True
scene.display.shading.shadow_intensity = 0.35
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = 0.35  # studio light alone leaves white reading grey
scene.world.color = srgb_to_linear("#CFEAFB")[:3]
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
	d_r = v3(math.sin(yr) * math.cos(pr), math.sin(pr), math.cos(yr) * math.cos(pr))
	d_b = Vector(to_blender(d_r))
	fwd = -d_b
	right = fwd.cross(Vector((0, 0, 1))).normalized()
	up = right.cross(fwd)
	xs = [(c - ctr).dot(right) for c in corners]
	ys = [(c - ctr).dot(up) for c in corners]
	ctr = ctr + right * (max(xs) + min(xs)) / 2 + up * (max(ys) + min(ys)) / 2
	cam.location = ctr + d_b * 1000
	cam.rotation_euler = fwd.to_track_quat("-Z", "Y").to_euler()
	cam_data.ortho_scale = max(max(xs) - min(xs), (max(ys) - min(ys)) * res[0] / res[1]) * 1.08
	for o in LIB.objects:
		o.hide_render = o not in objs
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	print("RENDERED", path)


everything = list(LIB.objects)
render(os.path.join(OUT, "preview.png"), everything, 25, 18, (1920, 900))
views = {"DonutArch": (25, 15), "TowerPillar": (35, 12), "Lollipop": (30, 10), "CupcakeTree": (30, 22),
	"CloudBunny": (25, 12)}
for set_name, objs in set_objects.items():
	yaw, pitch = views[set_name]
	render(os.path.join(OUT, f"preview_{set_name}.png"), objs, yaw, pitch, (1200, 1000))
render(os.path.join(OUT, "check_DonutArch_back.png"), set_objects["DonutArch"], 180 + 25, 15, (1200, 1000))
render(os.path.join(OUT, "check_CupcakeTree_eye.png"), set_objects["CupcakeTree"], 30, -12, (1200, 1000))
render(os.path.join(OUT, "check_CloudBunny_below.png"), set_objects["CloudBunny"], 15, -30, (1200, 1000))
for o in LIB.objects:
	o.hide_render = False
if problems:
	raise SystemExit("lobby_meshes: " + "; ".join(problems))
print("DONE")
