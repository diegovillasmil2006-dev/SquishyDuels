"""Squishy Duels Squish Pods: the floating cake of Diego's power-up pods as Blender meshes (2026-11-01).

The owner (2026-11-01): "each map should have their own box design as shown in the image" = Diego's pod gallery
(NEW MAPS FINALS zip, shots/pods/*.png; the 3D in "Squishy Duels TDM Demo.dc.html" :249-258 POD palette and :509-534
the pad build, `D:n` below). The cake is the same shape on every map; the game paints it per map, so this script
exports one set of shapes. The stand (base, top, 4 posts with knobs) is the maps' own stud boxes (SkyMapBuilder's box,
Diego's box()), so it is only drawn here for the previews. The posts and knobs are in his pictures but not in his code:
their sizes are read off the pictures.
Run it as its own Blender process:

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python squish_pods.py -- <out_dir>

Writes <out_dir>/SD_SquishPods.glb (objects "<piece>__<key>"), manifest.json (each object's centre and size in Roblox
axes) and previews (<map>.png per map, sheet.png). 1 Blender unit = 1 stud; points are computed in Roblox axes (X right,
Y up, Z back) and written as (X, -Z, Y), so the glTF "+Y up" export gives back Roblox axes.
Pieces: cake, cherry, bubble, crayon, star are in gem space (origin = the gem's centre, D:512 gem.y 3.2 above the pad;
the cube's 0.62 scale, D:512, is baked in); fx (beam, ring) is in pad space (origin = the pad's floor centre).
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
	raise SystemExit("usage: blender --background --factory-startup --python squish_pods.py -- <out_dir>")
OUT = os.path.abspath(ARGV[0])
os.makedirs(OUT, exist_ok=True)

INK = "1C1530"
CUBE = 0.78  # D:512 has 0.62; his pictures show a bigger cake (F2.png: the icing 193 px wide through his camera)
SPRINKLES = ("FF4F8B", "FFD23D", "7FD0FF", "5FD6A6", "9B7DFF", "FF9A3C")  # D:519 spC

# D:250-257, per map: the stand (base, top, post, knob) and the cake (body, icing, topper)
POD = {
	"T1": dict(base="D9773A", top="FF8FB8", post="FFF3E0", knob="FF5FA2", body="E8A55C", icing="FF8FB8", topper="cherry"),
	"T2": dict(base="3F7FE0", top="33D39B", post="FFFFFF", knob="FF6FAE", body="A6F0D4", icing="FFFFFF", topper="bubble"),
	"T3": dict(base="C97A3D", top="4EC92F", post="FFD77A", knob="FF5F87", body="FF5F87", icing="FFE066", topper="crayon"),
	"T4": dict(base="8A5A35", top="55C94A", post="D9A066", knob="3FA9FF", body="3FA9FF", icing="FFF7E0", topper="star"),
	"F1": dict(base="E8457F", top="FFCF3A", post="FFFFFF", knob="3FCF9C", body="3FCF9C", icing="FFFFFF", topper="cherry"),
	"F2": dict(base="7A4FE0", top="FF8FC8", post="FFFFFF", knob="FF9A3C", body="FFCF3A", icing="FF8FC8", topper="cherry"),
	"F3": dict(base="2A8FD6", top="FFD23D", post="FFFFFF", knob="FF6B5A", body="FF6B5A", icing="FFD23D", topper="star"),
	"F4": dict(base="D8643F", top="7A4FE0", post="FFE0C8", knob="3FB0FF", body="9B7DFF", icing="FFFFFF", topper="bubble"),
}

# The stand, pad space (preview only; the game builds it from the maps' stud parts): (key, shape, w, h, d, x, y, z, t).
# His pictures differ from his code (D:511 has a 6.2 x 0.22 box base and a 4.4 box top, no posts): the owner asked for
# the pictures, so the stand is measured on shots/pods/F2.png and F3.png through his podShots camera (D:1063, which
# looks from the base's top): a thicker, smaller square base, a round top disc, a post with a knob on each corner.
BASE_W, BASE_H, DISC_D, DISC_H = 5.4, 0.4, 4.4, 0.1
POST_AT, POST_W, POST_H, KNOB = 2.2, 0.7, 1.45, 0.45
STAND = [("base", "box", BASE_W, BASE_H, BASE_W, 0, 0, 0, 0.14), ("top", "cyl", DISC_D, DISC_H, DISC_D, 0, BASE_H, 0, 0.1)]
for sx in (-1, 1):
	for sz in (-1, 1):
		STAND.append(("post", "box", POST_W, POST_H, POST_W, sx * POST_AT, BASE_H, sz * POST_AT, 0.1))
		STAND.append(("knob", "box", KNOB, KNOB, KNOB, sx * POST_AT, BASE_H + POST_H, sz * POST_AT, 0.08))
GEM_Y = BASE_H + 2.85  # D:512 has 3.2 over the base's top; F2.png's cherry (y 140 px) puts the bigger cake lower
RING_Y = BASE_H + DISC_H + 0.02  # the pulse ring lies on the disc; in his pictures it starts at the disc's edge

# ------------------------------------------------------------------------------------------------------ shapes


def rot_matrix(r):  # three.js Euler "XYZ" = Rx * Ry * Rz (radians)
	if not r:
		return Matrix.Identity(4)
	return Matrix.Rotation(r[0], 4, "X") @ Matrix.Rotation(r[1], 4, "Y") @ Matrix.Rotation(r[2], 4, "Z")


def z_to_y(bm):  # Blender primitives run along Z: stand them up along Roblox Y
	for v in bm.verts:
		x, y, z = v.co
		v.co = Vector((x, z, -y))


def rbox(w, h, d, r):  # D:513 rbox: a box with rounded edges and corners
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * w, v.co.y * h, v.co.z * d))
	bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=r, offset_type="OFFSET", segments=4, profile=0.5,
		affect="EDGES", clamp_overlap=True)
	return bm


def ball(r, u=16, v=12):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r)
	z_to_y(bm)
	return bm


def capsule(r, length, radial=10):  # three.js CapsuleGeometry(r, length): along Y, length + 2r tall
	bm = ball(r, radial, 8)
	for v in bm.verts:
		v.co.y += length / 2 if v.co.y >= -1e-6 else -length / 2
	return bm


def cylinder(r_top, r_bottom, h, seg, caps=True):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r_bottom, radius2=r_top, depth=h)
	z_to_y(bm)
	return bm


def half_torus(radius, tube, radial, tubular):  # three.js TorusGeometry(radius, tube, radial, tubular, PI), XY plane
	bm = bmesh.new()
	rows = []
	for j in range(tubular + 1):
		u = j / tubular * math.pi
		rows.append([bm.verts.new(((radius + tube * math.cos(a)) * math.cos(u), (radius + tube * math.cos(a)) * math.sin(u),
			tube * math.sin(a))) for a in (i / radial * 2 * math.pi for i in range(radial))])
	for j in range(tubular):
		for i in range(radial):
			m = (i + 1) % radial
			bm.faces.new((rows[j][i], rows[j + 1][i], rows[j + 1][m], rows[j][m]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def star_prism(outer, inner, depth):  # D:526: 10 points, extruded along Z, centred, turned upside down (rotateZ PI)
	pts = []
	for k in range(10):
		a = -math.pi / 2 + k * math.pi / 5 + math.pi
		rr = inner if k % 2 else outer
		pts.append((math.cos(a) * rr, math.sin(a) * rr))
	bm = bmesh.new()
	lo = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
	hi = [bm.verts.new((x, y, depth / 2)) for x, y in pts]
	bm.faces.new(lo)
	bm.faces.new(hi)
	for i in range(10):
		bm.faces.new((lo[i], lo[(i + 1) % 10], hi[(i + 1) % 10], hi[i]))
	bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])  # the star is concave
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def ring(r_in, r_out, seg):  # D:533 RingGeometry, flat on the floor, facing up
	bm = bmesh.new()
	inner = [bm.verts.new((math.cos(a) * r_in, 0, math.sin(a) * r_in)) for a in (i / seg * 2 * math.pi for i in range(seg))]
	outer = [bm.verts.new((math.cos(a) * r_out, 0, math.sin(a) * r_out)) for a in (i / seg * 2 * math.pi for i in range(seg))]
	for i in range(seg):
		bm.faces.new((inner[i], inner[(i + 1) % seg], outer[(i + 1) % seg], outer[i]))
	for f in bm.faces:
		f.normal_update()
		if f.normal.y < 0:
			f.normal_flip()
	return bm


def tube_two_sided(r, h, seg):  # D:532 beam: an open cylinder, DoubleSided (here: a second, inward copy)
	bm = cylinder(r, r, h, seg, caps=False)
	inside = bm.copy()
	bmesh.ops.reverse_faces(inside, faces=inside.faces)
	append(bm, inside)
	inside.free()
	return bm


def append(dst, src):
	vmap = {v: dst.verts.new(v.co) for v in src.verts}
	for f in src.faces:
		dst.faces.new([vmap[v] for v in f.verts])


def outline_of(bm, s):  # D:326 outl / D:514 mk: the shape scaled by s about its own centre, seen from inside (BackSide)
	h = bm.copy()
	for v in h.verts:
		v.co = v.co * s
	bmesh.ops.reverse_faces(h, faces=h.faces)
	return h


class Kit:
	"""Parts in the piece's space: put(key, shape, position, rotation, outline scale, scale)."""

	def __init__(self, scale):
		self.scale = scale
		self.parts = []  # (key, bmesh)

	def put(self, key, bm, p=(0, 0, 0), r=None, s=None, size=None):
		if size:
			for v in bm.verts:
				v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
		m = Matrix.Scale(self.scale, 4) @ Matrix.Translation(Vector(p)) @ rot_matrix(r)
		shapes = [(key, bm)] + ([("Outline", outline_of(bm, s))] if s else [])
		for k, g in shapes:
			bmesh.ops.transform(g, matrix=m, verts=g.verts)
			self.parts.append((k, g))


# ------------------------------------------------------------------------------------------------------ pieces
# Positions are in Diego's cube space (D:513-530) and the Kit bakes the cube's 0.62 scale.


def build_cake(k):
	k.put("body", rbox(3.4, 3, 3.4, 0.8), s=1.07)  # D:516
	k.put("icing", rbox(3.56, 0.95, 3.56, 0.42), (0, 1.08, 0), s=1.09)  # D:517
	for x, y, z in ((-0.85, 0.35, 1.6), (0.8, 0.25, 1.6), (1.6, 0.35, -0.7), (-1.6, 0.3, 0.75), (0.35, 0.3, -1.6),
			(-1.6, 0.4, -0.85), (1.6, 0.2, 0.9)):  # D:518 the drips
		k.put("icing", capsule(0.3, 0.5), (x, y, z), s=1.2)
	for i in range(12):  # D:519-520 the sprinkles (no outline)
		a, rr = i * 2.4, 0.45 + (i % 4) * 0.28
		k.put(f"s{i % 6 + 1}", capsule(0.11, 0.36, 6), (math.cos(a) * rr, 1.57, math.sin(a) * rr), (math.pi / 2, 0, a * 1.7))
	for ry in (0, math.pi):  # D:528-530 the face, front and back
		turn = Matrix.Rotation(ry, 4, "Y")

		def at(x, y, z):
			return tuple(turn @ Vector((x, y, z)))

		for ex in (-0.6, 0.6):
			k.put("ink", ball(1, 12, 10), at(ex, -0.2, 1.69), (0, ry, 0), size=(0.24, 0.32, 0.1))
			k.put("white", ball(1, 12, 10), at(ex - 0.07, -0.08, 1.78), (0, ry, 0), size=(0.085, 0.085, 0.085))
			k.put("blush", ball(1, 12, 10), at(ex * 1.7, -0.62, 1.6), (0, ry, 0), size=(0.3, 0.15, 0.06))
		k.put("ink", half_torus(1, 0.24, 6, 14), at(0, -0.55, 1.71), (0, ry, math.pi), size=(0.2, 0.2, 0.2))
		k.put("white", ball(1, 12, 10), at(-1.05, 0.2, 1.62), (0, ry, 0.6), size=(0.42, 0.16, 0.06))


def build_cherry(k):  # D:523
	k.put("fruit", ball(0.5), (0, 2.02, 0), s=1.14)
	k.put("white", ball(0.13, 8, 6), (-0.2, 2.2, 0.36))
	k.put("stem", cylinder(0.07, 0.07, 0.75, 6), (0.15, 2.7, 0), (0, 0, -0.45))


def build_bubble(k):  # D:524
	for x, y, z, r in ((0, 2.15, 0, 0.62), (0.62, 2.7, 0.2, 0.3), (-0.5, 2.55, -0.3, 0.22)):
		k.put("bubble", ball(r), (x, y, z), s=1 + 0.1 / r)
		k.put("white", ball(r * 0.25, 8, 6), (x - r * 0.35, y + r * 0.4, z + r * 0.6))


def build_crayon(k):  # D:525 (the crayon's colour is the map's knob colour)
	k.put("crayon", cylinder(0.34, 0.34, 1.1, 14), (0, 2.1, 0), s=1.12)
	k.put("wrap", cylinder(0.36, 0.36, 0.35, 14), (0, 2.05, 0))
	k.put("crayon", cylinder(0, 0.34, 0.6, 14), (0, 2.95, 0), s=1.14)


def build_star(k):  # D:526
	k.put("star", star_prism(0.75, 0.32, 0.3), (0, 2.35, 0), s=1.14)


def build_fx(k):  # D:532-533, pad space (the ring's size from F2.png: D:533's 2.7-3.3 is wider than his pictures)
	k.put("beam", tube_two_sided(2.4, 14, 18), (0, BASE_H + 8.5, 0))
	k.put("ring", ring(DISC_D / 2, DISC_D / 2 + 0.4, 36), (0, RING_Y, 0))


PIECES = {"cake": (CUBE, build_cake), "cherry": (CUBE, build_cherry), "bubble": (CUBE, build_bubble),
	"crayon": (CUBE, build_crayon), "star": (CUBE, build_star), "fx": (1, build_fx)}
SMOOTH = {"body", "icing", "fruit", "bubble", "blush", "white", "ink", "crayon"}  # Diego's toon cake is smooth

# ------------------------------------------------------------------------------------------------------- Blender


def srgb_to_linear(hexstr):
	out = []
	for i in (0, 2, 4):
		c = int(hexstr[i:i + 2], 16) / 255
		out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
	return (*out, 1.0)


def to_object(name, bm, smooth, collection):
	cos = [v.co.copy() for v in bm.verts]
	lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
	hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
	for v in bm.verts:
		v.co = Vector((v.co.x, -v.co.z, v.co.y))
	bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	if smooth:
		me.shade_smooth()
	else:
		me.shade_flat()
	obj = bpy.data.objects.new(name, me)
	collection.objects.link(obj)
	return obj, lo, hi


for o in list(bpy.data.objects):  # the factory scene's cube, camera and light
	bpy.data.objects.remove(o)
LIB = bpy.data.collections.new("SD_SquishPods")
bpy.context.scene.collection.children.link(LIB)
manifest = {"cube": CUBE, "gemY": GEM_Y, "ink": INK, "objects": {}}
piece_objects = {}

for pid, (scale, build) in PIECES.items():
	kit = Kit(scale)
	build(kit)
	merged = {}
	for key, bm in kit.parts:
		merged.setdefault(key, bmesh.new())
		append(merged[key], bm)
		bm.free()
	objs = []
	for key, bm in merged.items():
		name = f"{pid}__{key}"
		obj, lo, hi = to_object(name, bm, key in SMOOTH, LIB)
		objs.append(obj)
		manifest["objects"][name] = {
			"piece": pid,
			"key": key,
			"center": [round((lo[i] + hi[i]) / 2, 4) for i in range(3)],
			"size": [round(hi[i] - lo[i], 4) for i in range(3)],
			"tris": len(obj.data.polygons),
		}
	piece_objects[pid] = objs
	print(pid, {o.name.split("__")[1]: len(o.data.polygons) for o in objs})

with open(os.path.join(OUT, "manifest.json"), "w") as f:
	json.dump(manifest, f, indent=1)

# ------------------------------------------------------------------------------------------------------- export

bpy.ops.object.select_all(action="DESELECT")
for o in LIB.objects:
	o.select_set(True)
bpy.context.view_layer.objects.active = LIB.objects[0]
glb = os.path.join(OUT, "SD_SquishPods.glb")
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
# Each map's whole pod (the stand as plain boxes, the cake at the gem height) at Diego's picture angle.

MATS = {}


def material(hexstr, ink=False, alpha=1.0):
	k = (hexstr, ink, alpha)
	if k in MATS:
		return MATS[k]
	m = bpy.data.materials.new(f"m{len(MATS)}")
	m.use_nodes = True
	bsdf = m.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = srgb_to_linear(hexstr)
	bsdf.inputs["Roughness"].default_value = 0.8
	bsdf.inputs["Emission Color"].default_value = srgb_to_linear(hexstr)  # Diego's toon look is bright
	bsdf.inputs["Emission Strength"].default_value = 0.45
	m.use_backface_culling = True  # Roblox draws front faces only (the ink hulls, the beam's two layers)
	if alpha < 1:
		bsdf.inputs["Alpha"].default_value = alpha
		if hasattr(m, "surface_render_method"):  # EEVEE Next
			m.surface_render_method = "BLENDED"
		elif hasattr(m, "blend_method"):
			m.blend_method = "BLEND"
	MATS[k] = m
	return m


def colour_of(key, pal):
	return {"body": pal["body"], "icing": pal["icing"], "ink": INK, "wrap": INK, "stem": INK, "white": "FFFFFF",
		"blush": "FF9BB8", "fruit": "FF4F6B", "bubble": "E6F6FF", "star": "FFD23D", "crayon": pal["knob"],
		"beam": pal["knob"], "ring": pal["knob"], **{f"s{i + 1}": c for i, c in enumerate(SPRINKLES)}}[key]


scene = bpy.context.scene
for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
	try:
		scene.render.engine = engine
		break
	except TypeError:
		continue
scene.render.film_transparent = False
scene.view_settings.view_transform = "Standard"
scene.world = bpy.data.worlds.new("Sky")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb_to_linear("8FCDF7")
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 2.5
sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(-35))
scene.collection.objects.link(sun)
cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.sensor_fit = "VERTICAL"  # three.js fov is vertical
cam_data.angle_y = math.radians(45)  # D:1061 podShots fov 45, 640x480
cam = bpy.data.objects.new("PreviewCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
scene.render.resolution_x, scene.render.resolution_y = 640, 480
PREV = bpy.data.collections.new("Preview")
scene.collection.children.link(PREV)


def to_blender(p):
	return Vector((p[0], -p[2], p[1]))


def preview(map_id, pal):
	for o in list(PREV.objects):
		bpy.data.objects.remove(o)
	floor = bmesh.new()
	bmesh.ops.create_cube(floor, size=1.0)
	for v in floor.verts:
		v.co = Vector((v.co.x * 40, v.co.y * 0.5 - 0.25, v.co.z * 40))
	fo, _, _ = to_object("floor", floor, False, PREV)
	fo.data.materials.append(material("EADCF5"))
	for key, shape, w, h, d, x, y, z, t in STAND:  # D:331 box / cyl: bottom at y, ink hull t out (bottom 0.08 lower)
		for name, s, col, ink in ((key, (w, h, d), pal[key], False), (key + "_o", (w + 2 * t, h + t, d + 2 * t), INK, True)):
			bm = bmesh.new()
			if shape == "cyl":
				bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=28, radius1=0.5, radius2=0.5, depth=1)
				z_to_y(bm)
			else:
				bmesh.ops.create_cube(bm, size=1.0)
			lift = y + (h / 2 if not ink else (h + t) / 2 - 0.08)
			for v in bm.verts:
				v.co = Vector((v.co.x * s[0] + x, v.co.y * s[1] + lift, v.co.z * s[2] + z))
			if ink:
				bmesh.ops.reverse_faces(bm, faces=bm.faces)
			o, _, _ = to_object(name, bm, False, PREV)
			o.data.materials.append(material(col, ink))
	for pid in ("cake", pal["topper"], "fx"):
		for src in piece_objects[pid]:
			key = src.name.split("__")[1]
			o = src.copy()
			o.hide_render = False  # the copy would keep the hidden flag set on LIB after the first preview
			o.data = src.data.copy()
			o.data.materials.clear()
			if key == "Outline":
				o.data.materials.append(material(INK, True))
			else:
				o.data.materials.append(material(colour_of(key, pal), False, 0.16 if key == "beam" else 0.8 if key == "ring" else 1))
			if pid != "fx":
				o.location = to_blender((0, GEM_Y, 0))
			PREV.objects.link(o)
	cam.location = to_blender((8, BASE_H + 5.5, 8))  # D:1063 camera at the pad + (8, 5.5, 8), looking at the pad + 2.4 up
	cam.rotation_euler = (to_blender((0, BASE_H + 2.4, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
	for o in LIB.objects:
		o.hide_render = True
	scene.render.filepath = os.path.join(OUT, f"{map_id}.png")
	bpy.ops.render.render(write_still=True)
	print("RENDERED", map_id)


for map_id, pal in POD.items():
	preview(map_id, pal)

import numpy as np

w, h = 640, 480
sheet = np.zeros((2 * h, 4 * w, 4), dtype=np.float32)
for i, map_id in enumerate(POD):
	row, col = divmod(i, 4)
	img = bpy.data.images.load(os.path.join(OUT, f"{map_id}.png"))
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
	sheet[(1 - row) * h:(2 - row) * h, col * w:(col + 1) * w] = px  # Blender rows run bottom-up
out = bpy.data.images.new("sheet", 4 * w, 2 * h, alpha=True)
out.pixels = sheet.ravel()
out.filepath_raw = os.path.join(OUT, "sheet.png")
out.file_format = "PNG"
out.save()
print("DONE")
