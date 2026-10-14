"""Re-imports SD_MeshLibrary.glb in a fresh background Blender and checks it against lobby_meshes_report.json:
names, triangle counts, sizes and centres (Roblox axes, in each set's frame), and that the file carries only
POSITION + NORMAL (no UVs, materials or vertex colours) and +Y-up node names.

    "<blender.exe>" --background --factory-startup --python-exit-code 1 --python reimport_check.py -- <out_dir>
"""

import json
import os
import struct
import sys

import bpy

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGV[0]) if ARGV else os.path.dirname(os.path.abspath(__file__))
GLB = os.path.join(OUT, "SD_MeshLibrary.glb")
report = json.load(open(os.path.join(OUT, "lobby_meshes_report.json"), encoding="utf-8"))
want = report["objects"]
problems = []

# 1. The file itself (glTF JSON chunk).
with open(GLB, "rb") as fh:
	magic, version, _ = struct.unpack("<4sII", fh.read(12))
	length, kind = struct.unpack("<I4s", fh.read(8))
	gltf = json.loads(fh.read(length))
assert magic == b"glTF" and version == 2 and kind == b"JSON", "not a glTF 2 binary"
node_names = sorted(n["name"] for n in gltf["nodes"])
mesh_names = sorted(m["name"] for m in gltf["meshes"])
attrs = sorted({a for m in gltf["meshes"] for p in m["primitives"] for a in p["attributes"]})
print("GLB nodes:", node_names)
print("GLB meshes:", mesh_names)
print("GLB attributes:", attrs, "| materials:", len(gltf.get("materials", [])), "| animations:",
	len(gltf.get("animations", [])), "| textures:", len(gltf.get("textures", [])))
if node_names != sorted(want) or mesh_names != sorted(want):
	problems.append("node / mesh names differ from the build")
if attrs != ["NORMAL", "POSITION"]:
	problems.append(f"unexpected vertex attributes {attrs}")
if gltf.get("materials") or gltf.get("animations") or gltf.get("textures"):
	problems.append("materials, animations or textures present")
for n in gltf["nodes"]:
	if any(k in n for k in ("rotation", "scale", "matrix")) or any(abs(t) > 1e-9 for t in n.get("translation", [])):
		problems.append(f"{n['name']}: node carries a transform")
for m in gltf["meshes"]:
	if any(p.get("mode", 4) != 4 for p in m["primitives"]):
		problems.append(f"{m['name']}: not triangles")

# 2. Blender's own importer.
for o in list(bpy.data.objects):
	bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=GLB, merge_vertices=False, import_shading="NORMALS")
got = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
if sorted(got) != sorted(want):
	problems.append(f"imported objects {sorted(got)} != built {sorted(want)}")
print(f"\n{'object':28s} {'tris':>5s} {'size (Roblox, studs)':>28s} {'centre in set frame':>28s}  match")
for name in sorted(want):
	o = got.get(name)
	if o is None:
		continue
	me = o.data
	mw = o.matrix_world
	pts = [mw @ v.co for v in me.vertices]
	rb = [(p.x, p.z, -p.y) for p in pts]  # Blender (X, Y, Z) -> Roblox (X, Z, -Y)
	lo = [min(c[i] for c in rb) for i in range(3)]
	hi = [max(c[i] for c in rb) for i in range(3)]
	size = [round(hi[i] - lo[i], 3) for i in range(3)]
	center = [round((hi[i] + lo[i]) / 2 - (want[name]["offset_x"] if i == 0 else 0), 3) for i in range(3)]
	tris = sum(len(p.vertices) - 2 for p in me.polygons)
	w = want[name]
	ok = (tris == w["tris"] and all(abs(a - b) <= 2e-3 for a, b in zip(size, w["size"]))
		and all(abs(a - b) <= 2e-3 for a, b in zip(center, w["center"])))
	extra = []
	if len(me.uv_layers):
		extra.append("UVs")
	if len(me.color_attributes):
		extra.append("colours")
	if extra:
		problems.append(f"{name}: imported with {extra}")
	if me.name != name:
		problems.append(f"{name}: mesh data named {me.name}")
	if not ok:
		problems.append(f"{name}: tris/size/centre changed ({tris} {size} {center} vs {w['tris']} {w['size']} {w['center']})")
	print(f"{name:28s} {tris:5d} {str(tuple(size)):>28s} {str(tuple(center)):>28s}  {'yes' if ok else 'NO'}")
print("\nREIMPORT PROBLEMS:", problems if problems else "none")
if problems:
	raise SystemExit("reimport_check: " + "; ".join(problems))
