// Makes the pictures and the outline-mesh file the sky maps need, from Diego's demos (NEW MAPS FINALS zip):
//   docs/new-maps/textures/MapStud.png    his setupGlobals() stud canvas: 8x8 studs, 4x4-stud white/#d4d4d4 checker,
//                                         an inset square per stud (dark top-left, white bottom-right edges)
//   docs/new-maps/textures/FloorCheck.png drawFloor's 4-stud checker squares (white, tinted to theme.grid in Roblox)
//   docs/new-maps/textures/FloorStud.png  drawFloor's per-stud inset (ink .16 square, white .35 bottom-right edges)
//   docs/new-maps/textures/Sky{Up,Side,Dn}.png  buildSky()'s gradient (top #2f8fe6, mid #8fcdf7, bottom #dff1ff)
//   docs/new-maps/outline-meshes/Hulls.glb  his 3 inverted-hull OBJs in one glTF (nodes HullBox, HullCylinder, HullSphere)
// Run from the repo root: node tools/maps/make_assets.mjs
// Uploaded 2026-10-30: images MapStud 137735286152608, FloorCheck 75578035159252, FloorStud 72408158301076, SkyUp
// 126503081362555, SkySide 101839995386908, SkyDn 89166293545610 (Studio MCP upload_image); Hulls.glb as a DIJAY Studios
// Model (see ReplicatedStorage.SquishyOutlineMeshes).
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const ROOT = process.cwd();
const TEX = path.join(ROOT, "docs/new-maps/textures");
const MESH = path.join(ROOT, "docs/new-maps/outline-meshes");
fs.mkdirSync(TEX, { recursive: true });

// ---- PNG ---------------------------------------------------------------------------------------------------------
const CRC = new Uint32Array(256).map((_, n) => {
	let c = n;
	for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
	return c >>> 0;
});
function crc32(buf) {
	let c = 0xffffffff;
	for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
	const len = Buffer.alloc(4);
	len.writeUInt32BE(data.length);
	const td = Buffer.concat([Buffer.from(type), data]);
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(td));
	return Buffer.concat([len, td, crc]);
}
function png(w, h, rgba) {
	const raw = Buffer.alloc((w * 4 + 1) * h);
	for (let y = 0; y < h; y++) {
		raw[y * (w * 4 + 1)] = 0;
		for (let x = 0; x < w * 4; x++) raw[y * (w * 4 + 1) + 1 + x] = Math.max(0, Math.min(255, Math.round(rgba[y * w * 4 + x])));
	}
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 6;
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}
function canvas(w, h, fill) {
	const px = new Float64Array(w * h * 4);
	for (let i = 0; i < w * h; i++) px.set(fill, i * 4);
	return { w, h, px };
}
// Source-over a colour [r,g,b] with alpha a * coverage onto one pixel (straight alpha).
function blend(c, x, y, rgb, a) {
	if (a <= 0) return;
	const i = (y * c.w + x) * 4, da = c.px[i + 3] / 255, oa = a + da * (1 - a);
	for (let k = 0; k < 3; k++) c.px[i + k] = oa > 0 ? (rgb[k] * a + c.px[i + k] * da * (1 - a)) / oa : 0;
	c.px[i + 3] = oa * 255;
}
// A canvas stroke of an axis-aligned polyline (butt caps, mitre joins), drawn by 4x4 supersampling.
function stroke(c, pts, width, rgb, alpha, closed) {
	const rects = [], hw = width / 2, n = pts.length, segs = closed ? n : n - 1;
	for (let i = 0; i < segs; i++) {
		const a = pts[i], b = pts[(i + 1) % n];
		const joinA = closed || i > 0, joinB = closed || i < n - 2;
		if (a[1] === b[1]) {
			const x0 = Math.min(a[0], b[0]) - ((a[0] < b[0] ? joinA : joinB) ? hw : 0), x1 = Math.max(a[0], b[0]) + ((a[0] < b[0] ? joinB : joinA) ? hw : 0);
			rects.push([x0, a[1] - hw, x1, a[1] + hw]);
		} else {
			const y0 = Math.min(a[1], b[1]) - ((a[1] < b[1] ? joinA : joinB) ? hw : 0), y1 = Math.max(a[1], b[1]) + ((a[1] < b[1] ? joinB : joinA) ? hw : 0);
			rects.push([a[0] - hw, y0, a[0] + hw, y1]);
		}
	}
	const bx0 = Math.max(0, Math.floor(Math.min(...rects.map((r) => r[0])))), bx1 = Math.min(c.w - 1, Math.ceil(Math.max(...rects.map((r) => r[2]))));
	const by0 = Math.max(0, Math.floor(Math.min(...rects.map((r) => r[1])))), by1 = Math.min(c.h - 1, Math.ceil(Math.max(...rects.map((r) => r[3]))));
	for (let y = by0; y <= by1; y++)
		for (let x = bx0; x <= bx1; x++) {
			let hits = 0;
			for (let sy = 0; sy < 4; sy++)
				for (let sx = 0; sx < 4; sx++) {
					const px = x + (sx + 0.5) / 4, py = y + (sy + 0.5) / 4;
					if (rects.some((r) => px >= r[0] && px < r[2] && py >= r[1] && py < r[3])) hits++;
				}
			blend(c, x, y, rgb, (alpha * hits) / 16);
		}
}
const save = (name, c) => fs.writeFileSync(path.join(TEX, name), png(c.w, c.h, c.px));

// ---- MapStud: setupGlobals() (P 32 px a stud, N 8 studs; inset q 20, o 6, line 2.5) ------------------------------
{
	const P = 32, N = 8, c = canvas(P * N, P * N, [255, 255, 255, 255]);
	for (let j = 0; j < N; j++)
		for (let i = 0; i < N; i++) {
			const v = ((i >> 2) + (j >> 2)) % 2 ? 0xd4 : 0xff;
			for (let y = j * P; y < (j + 1) * P; y++) for (let x = i * P; x < (i + 1) * P; x++) c.px.set([v, v, v, 255], (y * c.w + x) * 4);
		}
	const q = 20, o = (P - q) / 2;
	for (let j = 0; j < N; j++)
		for (let i = 0; i < N; i++) {
			const X = i * P + o, Y = j * P + o;
			stroke(c, [[X, Y + q], [X, Y], [X + q, Y]], 2.5, [0, 0, 0], 0.2, false);
			stroke(c, [[X + q, Y + 1], [X + q, Y + q], [X + 1, Y + q]], 2.5, [255, 255, 255], 0.85, false);
		}
	save("MapStud.png", c);
}

// ---- Floor: drawFloor() at 32 px a stud over an 8x8-stud tile ------------------------------------------------------
{
	const S = 32, c = canvas(8 * S, 8 * S, [255, 255, 255, 0]);
	for (let yy = 0; yy < 8; yy += 4)
		for (let xx = (yy / 4) % 2 ? 4 : 0; xx < 8; xx += 8)
			for (let y = yy * S; y < (yy + 4) * S; y++) for (let x = xx * S; x < (xx + 4) * S; x++) c.px.set([255, 255, 255, 255], (y * c.w + x) * 4);
	save("FloorCheck.png", c);
}
{
	// his s = 8 px a stud: q = s * .62, o = (s - q) / 2, line max(1, s * .12) = .12 stud, the white edge starts 1 px (1/8 stud) in
	const S = 32, c = canvas(8 * S, 8 * S, [255, 255, 255, 0]);
	const q = S * 0.62, o = (S - q) / 2, lw = S * 0.12, px1 = S / 8;
	for (let yy = 0; yy < 8; yy++)
		for (let xx = 0; xx < 8; xx++) {
			const X = xx * S + o, Y = yy * S + o;
			stroke(c, [[X, Y], [X + q, Y], [X + q, Y + q], [X, Y + q]], lw, [28, 21, 48], 0.16, true);
			stroke(c, [[X + q, Y + px1], [X + q, Y + q], [X + px1, Y + q]], lw, [255, 255, 255], 0.35, false);
		}
	save("FloorStud.png", c);
}

// ---- Sky: buildSky()'s shader on the 6 cube faces (three.js mixes in linear light) ------------------------------
{
	const lin = (v) => ((v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
	const srgb = (v) => 255 * (v <= 0.0031308 ? v * 12.92 : 1.055 * v ** (1 / 2.4) - 0.055);
	const hex = (h) => [0, 2, 4].map((i) => lin(parseInt(h.slice(1 + i, 3 + i), 16)));
	const TOP = hex("#2f8fe6"), MID = hex("#8fcdf7"), BOT = hex("#dff1ff");
	const sstep = (e0, e1, x) => { const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); };
	const colour = (h) => {
		const [a, b, t] = h > 0 ? [MID, TOP, sstep(0, 0.6, h)] : [MID, BOT, sstep(0, -0.45, h)];
		return a.map((v, k) => srgb(v + (b[k] - v) * t));
	};
	const N = 512;
	for (const [name, f] of [["SkySide.png", (u, v) => v / Math.hypot(u, v, 1)], ["SkyUp.png", (u, v) => 1 / Math.hypot(u, v, 1)], ["SkyDn.png", (u, v) => -1 / Math.hypot(u, v, 1)]]) {
		const c = canvas(N, N, [0, 0, 0, 255]);
		for (let y = 0; y < N; y++)
			for (let x = 0; x < N; x++) {
				const u = (2 * (x + 0.5)) / N - 1, v = 1 - (2 * (y + 0.5)) / N;
				c.px.set([...colour(f(u, v)), 255], (y * N + x) * 4);
			}
		save(name, c);
	}
}

// ---- Hulls.glb: his 3 OBJs (faces point inward) as one glTF, positions as they are -------------------------------
{
	const meshes = [];
	for (const name of ["HullBox", "HullCylinder", "HullSphere"]) {
		const v = [], idx = [];
		for (const line of fs.readFileSync(path.join(MESH, name + ".obj"), "utf8").split(/\r?\n/)) {
			const p = line.trim().split(/\s+/);
			if (p[0] === "v") v.push(p.slice(1, 4).map(Number));
			else if (p[0] === "f") {
				const f = p.slice(1).map((s) => parseInt(s.split("/")[0], 10) - 1);
				// reversed: Roblox showed his OBJ order as an outward (solid) box, so the hull is wound the other way
				for (let k = 1; k + 1 < f.length; k++) idx.push(f[0], f[k + 1], f[k]);
			}
		}
		// flat normals from the winding, one vertex per corner
		const pos = [], nor = [];
		for (let i = 0; i < idx.length; i += 3) {
			const [a, b, c] = [v[idx[i]], v[idx[i + 1]], v[idx[i + 2]]];
			const e1 = b.map((x, k) => x - a[k]), e2 = c.map((x, k) => x - a[k]);
			const n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
			const l = Math.hypot(...n) || 1;
			for (const p of [a, b, c]) { pos.push(...p); nor.push(...n.map((x) => x / l)); }
		}
		meshes.push({ name, pos: new Float32Array(pos), nor: new Float32Array(nor) });
	}
	const bufs = [], views = [], accessors = [], gltfMeshes = [], nodes = [];
	let offset = 0;
	const addView = (arr) => { const b = Buffer.from(arr.buffer); views.push({ buffer: 0, byteOffset: offset, byteLength: b.length, target: 34962 }); bufs.push(b); offset += b.length; return views.length - 1; };
	meshes.forEach((m, i) => {
		const min = [0, 1, 2].map((k) => Math.min(...m.pos.filter((_, j) => j % 3 === k))), max = [0, 1, 2].map((k) => Math.max(...m.pos.filter((_, j) => j % 3 === k)));
		accessors.push({ bufferView: addView(m.pos), componentType: 5126, count: m.pos.length / 3, type: "VEC3", min, max });
		accessors.push({ bufferView: addView(m.nor), componentType: 5126, count: m.nor.length / 3, type: "VEC3" });
		gltfMeshes.push({ name: m.name, primitives: [{ attributes: { POSITION: 2 * i, NORMAL: 2 * i + 1 }, material: 0 }] });
		nodes.push({ name: m.name, mesh: i, translation: [i * 3, 0, 0] });
	});
	const bin = Buffer.concat(bufs);
	const json = { asset: { version: "2.0", generator: "SquishyDuels make_assets.mjs" }, scene: 0, scenes: [{ nodes: nodes.map((_, i) => i) }], nodes, meshes: gltfMeshes, materials: [{ name: "Ink", pbrMetallicRoughness: { baseColorFactor: [0.011, 0.007, 0.03, 1], metallicFactor: 0, roughnessFactor: 1 } }], accessors, bufferViews: views, buffers: [{ byteLength: bin.length }] };
	let js = Buffer.from(JSON.stringify(json));
	js = Buffer.concat([js, Buffer.alloc((4 - (js.length % 4)) % 4, 0x20)]);
	const binP = Buffer.concat([bin, Buffer.alloc((4 - (bin.length % 4)) % 4)]);
	const head = Buffer.alloc(12);
	head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(12 + 8 + js.length + 8 + binP.length, 8);
	const ch = (len, type) => { const b = Buffer.alloc(8); b.writeUInt32LE(len, 0); b.writeUInt32LE(type, 4); return b; };
	fs.writeFileSync(path.join(MESH, "Hulls.glb"), Buffer.concat([head, ch(js.length, 0x4e4f534a), js, ch(binP.length, 0x004e4942), binP]));
}
console.log("textures:", fs.readdirSync(TEX).join(", "), "| Hulls.glb", fs.statSync(path.join(MESH, "Hulls.glb")).size, "bytes");
