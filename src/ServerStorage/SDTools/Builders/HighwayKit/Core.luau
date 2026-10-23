--!strict
-- HighwayKit.Core: the shared helpers of Claude Design's highway kit v2 (owner 2026-10-23: "rebuild from Claude Design's
-- sketches"; the delivery "3D highway zones model.zip", kit-core.js), ported 1:1 so every seeded layout (trees,
-- flowers, crystals, drips...) lands where Design's renders show it. Edit time only (ServerStorage.SDTools); data and
-- pure functions, no Instances.
-- Units: studs. x across the road (+ = right of the chase camera), y up (0 = road surface), d along the road. A part's
-- `at` is in its asset's own frame, +x pointing OUTWARD (HighwayZones mirrors the left-side copies). r = {rx, ry, rz}
-- degrees, Euler XYZ (three.js: rz > 0 leans the top inward, rx > 0 leans it back toward the camera). Colours are hex
-- strings ("#RRGGBB"), as Design's tone() works on them; the base colours come from Art/Palette (HighwayKit/init).
-- Part shapes: box {w, h, l}; ball {dia}; cyl {dia, len} along `axis`; wedge {w, h, l} (its right angle at +x, -y,
-- extruded along z); pyr {w, h, l} (a square pyramid, apex up); poly {thickness} with `pts` {x, d} (a flat prism).

export type Part = {
	n: string,
	s: string,
	d: { number },
	at: { number },
	c: string,
	m: string,
	r: { number }?,
	axis: string?,
	pts: { { number } }?,
	cyc: { string }?,
}
export type Rng = () -> number

local Core = {}

-- Design's ROAD and CHASE (kit-core.js:6, :8).
Core.ROAD = { inner = 60, lane = 30, railX = 15.5, signX = 19, keepX = 18, keepY = 72, maxLen = 2048 }

-- tone(hex, k): toward white (k > 0) or black (k < 0) by |k| (kit-core.js:15-19).
function Core.tone(hex: string, k: number): string
	local n = tonumber(string.sub(hex, 2), 16) :: number
	local t = if k < 0 then 0 else 255
	local a = math.abs(k)
	local function f(v: number): number
		return math.floor(v + (t - v) * a + 0.5)
	end
	return string.format("#%02X%02X%02X", f(n // 65536), f((n // 256) % 256), f(n % 256))
end

-- Math.imul's low 32 bits, unsigned (exact in doubles: every partial product stays under 2^53).
local function imul(a: number, b: number): number
	a, b = a % 4294967296, b % 4294967296
	local ah, al = a // 65536, a % 65536
	local bh, bl = b // 65536, b % 65536
	return (al * bl + ((ah * bl + al * bh) % 65536) * 65536) % 4294967296
end

-- rng(seed): Design's LCG (kit-core.js:20-23), the same sequence for the same seed.
function Core.rng(seed: number): Rng
	local s = imul(seed, 2654435761)
	if s == 0 then
		s = 7
	end
	return function(): number
		s = (imul(s, 1664525) + 1013904223) % 4294967296
		return s / 4294967296
	end
end

function Core.rr(r: Rng, a: number, b: number): number
	return a + (b - a) * r()
end

local function make(n: string, s: string, d: { number }, at: { number }, c: string, m: string, o: { [string]: any }?): Part
	local p: any = { n = n, s = s, d = d, at = at, c = c, m = m }
	if o then
		for k, v in o do
			p[k] = v
		end
	end
	return p
end

function Core.box(n, w, h, l, x, y, d, c, m, o): Part
	return make(n, "box", { w, h, l }, { x, y, d }, c, m, o)
end
function Core.ball(n, dia, x, y, d, c, m, o): Part
	return make(n, "ball", { dia }, { x, y, d }, c, m, o)
end
function Core.cyl(n, dia, len, axis, x, y, d, c, m, o): Part
	local p = make(n, "cyl", { dia, len }, { x, y, d }, c, m, o)
	p.axis = axis
	return p
end
function Core.wedge(n, w, h, l, x, y, d, c, m, o): Part
	return make(n, "wedge", { w, h, l }, { x, y, d }, c, m, o)
end
function Core.pyr(n, w, h, l, x, y, d, c, m, o): Part
	return make(n, "pyr", { w, h, l }, { x, y, d }, c, m, o)
end
function Core.poly(n, pts, t, y, c, m, o): Part
	local p = make(n, "poly", { t }, { 0, y, 0 }, c, m, o)
	p.pts = pts
	return p
end

-- turn(v, r): rotates an offset {x, y, d} the way the renderer rotates a part with r (kit-core.js:35-43).
function Core.turn(v: { number }, r: { number }?): { number }
	if not r then
		return { v[1], v[2], v[3] }
	end
	local x, y, z = v[1], v[2], -v[3]
	local a, b, c = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
	local t = x * math.cos(c) - y * math.sin(c)
	y = x * math.sin(c) + y * math.cos(c)
	x = t
	t = x * math.cos(b) + z * math.sin(b)
	z = -x * math.sin(b) + z * math.cos(b)
	x = t
	t = y * math.cos(a) - z * math.sin(a)
	z = y * math.sin(a) + z * math.cos(a)
	y = t
	return { x, y, -z }
end

function Core.add(a: { number }, b: { number }): { number }
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

local function append(o: { Part }, list: { Part })
	for _, p in list do
		table.insert(o, p)
	end
end
Core.append = append

-- blob(r, rx, rd, k, lo): a lumpy outline of k points around the origin (kit-core.js:45-49).
function Core.blob(r: Rng, rx: number, rd: number, k: number?, lo: number?): { { number } }
	local kk, low = k or 9, lo or 0.78
	local pts = {}
	for i = 0, kk - 1 do
		local a = (i / kk) * 6.283
		local q = Core.rr(r, low, 1.04)
		table.insert(pts, { math.cos(a) * rx * q, math.sin(a) * rd * q })
	end
	return pts
end

-- ---------- generators (kit-core.js:52-175; every random draw in Design's order) ----------

function Core.canopy(r: Rng, n, x, y, d, s, cols: { string }, m, k: number?): { Part }
	local rr, box = Core.rr, Core.box
	local kk = k or 6
	local o = { box(n, s, s * 0.82, s, x, y, d, cols[1], m, { r = { 0, rr(r, 0, 90), 0 } }) }
	for i = 0, kk - 1 do
		local a = (i / kk) * 6.283 + rr(r, -0.4, 0.4)
		local rad = s * rr(r, 0.32, 0.5)
		local q = rr(r, 0.42, 0.66)
		local yy = y + s * rr(r, -0.22, 0.34)
		local ry = rr(r, 0, 90)
		table.insert(o, box(n, s * q, s * q * 0.86, s * q, x + math.cos(a) * rad, yy, d + math.sin(a) * rad, cols[(i + 1) % #cols + 1], m, { r = { 0, ry, 0 } }))
	end
	local xx = x + rr(r, -1, 1)
	local dd = d + rr(r, -1, 1)
	local ry = rr(r, 0, 90)
	table.insert(o, box(n, s * 0.55, s * 0.5, s * 0.55, xx, y + s * 0.52, dd, cols[if #cols > 1 then 2 else 1], m, { r = { 0, ry, 0 } }))
	return o
end

function Core.tree(r: Rng, n, x, d, h, s, tc, tm, lc: { string }, lm, y0: number?): { Part }
	local base = y0 or 0
	local w = math.max(1.2, s * 0.15)
	local o = {
		Core.box(n .. " trunk", w, h, w, x, base + h / 2, d, tc, tm),
		Core.box(n .. " branch", w * 0.7, h * 0.4, w * 0.7, x + w * 0.9, base + h * 0.72, d, tc, tm, { r = { 0, 0, -38 } }),
	}
	append(o, Core.canopy(r, n .. " leaves", x, base + h + s * 0.18, d, s, lc, lm))
	return o
end

function Core.palm(r: Rng, n, x, d, h, lean, tc, lc, nc, y0: number?): { Part }
	local rr, box, tone = Core.rr, Core.box, Core.tone
	local o = {}
	local segs = 7
	local px, py = x, y0 or 0
	for i = 0, segs - 1 do
		local t = (i + 0.5) / segs
		local ang = lean * t * 1.5
		local q = math.rad(ang)
		local len = (h / segs) * 1.12
		local w = 1.9 - t * 0.6
		table.insert(o, box(n .. " trunk", w, len, w, px - (math.sin(q) * len) / 2, py + (math.cos(q) * len) / 2, d, if i % 2 == 1 then tc else tone(tc, -0.14), "Wood", { r = { 0, 0, ang } }))
		px -= math.sin(q) * len * 0.93
		py += math.cos(q) * len * 0.93
	end
	for i = 0, 7 do
		local ry = i * 45 + rr(r, -10, 10)
		local rz = -rr(r, 26, 40)
		local rot = { 0, ry, rz }
		local L = h * 0.42
		local c = Core.turn({ L / 2, 0, 0 }, rot)
		table.insert(o, box(n .. " frond", L, 0.5, 2.6, px + c[1], py + 0.6 + c[2], d + c[3], if i % 2 == 1 then lc else tone(lc, -0.16), "LeafyGrass", { r = rot }))
	end
	for i = 0, 2 do
		table.insert(o, Core.ball(n .. " coconut", 1.7, px + math.cos(i * 2.1) * 1.1, py - 0.7, d + math.sin(i * 2.1) * 1.1, nc, "Wood"))
	end
	return o
end

function Core.pine(_r: Rng, n, x, d, h, s, tc, lc, sc: string?, y0: number?): { Part }
	local box, tone = Core.box, Core.tone
	local base = y0 or 0
	local o = { box(n .. " trunk", s * 0.16, h * 0.3, s * 0.16, x, base + h * 0.15, d, tc, "Wood") }
	for i = 0, 3 do
		local w = s * (1 - i * 0.22)
		local th = h * 0.2
		local y = base + h * 0.22 + i * h * 0.18
		table.insert(o, box(n .. " tier", w, th, w, x, y + th / 2, d, if i % 2 == 1 then lc else tone(lc, -0.12), "LeafyGrass", { r = { 0, i * 22, 0 } }))
		if sc then
			table.insert(o, box(n .. " snow", w * 0.8, th * 0.3, w * 0.8, x, y + th + th * 0.1, d, sc, "Snow", { r = { 0, i * 22 + 11, 0 } }))
		end
	end
	table.insert(o, Core.pyr(n .. " top", s * 0.34, h * 0.18, s * 0.34, x, base + h * 0.98, d, sc or lc, if sc then "Snow" else "LeafyGrass"))
	return o
end

function Core.rocks(r: Rng, n, x, d, k, s, c, m, y0: number?): { Part }
	local rr = Core.rr
	local base = y0 or 0
	local o = {}
	for i = 0, k - 1 do
		local q = s * rr(r, 0.5, 1)
		local a = r() * 6.283
		local rad = if i ~= 0 then s * rr(r, 0.5, 0.95) else 0
		local w = q * rr(r, 0.9, 1.3)
		local h = q * rr(r, 0.6, 0.9)
		local rot = { rr(r, -20, 20), 0, 0 }
		rot[2] = rr(r, 0, 90)
		rot[3] = rr(r, -20, 20)
		table.insert(o, Core.box(n, w, h, q, x + math.cos(a) * rad, base + q * 0.28, d + math.sin(a) * rad, if i % 2 == 1 then Core.tone(c, -0.12) else c, m, { r = rot }))
	end
	return o
end

function Core.flowers(r: Rng, n, x, d, k, spread, pcs: { string }, cc, sc, m: string?): { Part }
	local rr, box = Core.rr, Core.box
	local mat = m or "Plastic"
	local o = {}
	for i = 0, k - 1 do
		local fx = x + rr(r, -spread, spread)
		local fd = d + rr(r, -spread, spread)
		local h = rr(r, 1.6, 3.6)
		local pc = pcs[i % #pcs + 1]
		local s = rr(r, 0.8, 1.25)
		table.insert(o, box(n .. " stem", 0.35, h, 0.35, fx, h / 2, fd, sc, mat))
		table.insert(o, box(n .. " leaf", 1.3, 0.25, 0.6, fx + 0.6, h * 0.4, fd, sc, mat, { r = { 0, 0, 25 } }))
		for _, off in { { 0.75, 0 }, { -0.75, 0 }, { 0, 0.75 }, { 0, -0.75 } } do
			table.insert(o, box(n .. " petal", s, 0.32, s, fx + off[1] * s, h + 0.1, fd + off[2] * s, pc, mat))
		end
		table.insert(o, box(n .. " centre", 0.7 * s, 0.45, 0.7 * s, fx, h + 0.3, fd, cc, mat))
	end
	return o
end

function Core.crystals(r: Rng, n, x, d, k, h, w, cols: { string }, m, tipM: string?, y0: number?): { Part }
	local rr = Core.rr
	local base = y0 or 0
	local o = {}
	for i = 0, k - 1 do
		local hh = h * rr(r, 0.45, 1)
		local ww = w * rr(r, 0.6, 1)
		local a = r() * 6.283
		local rad = if i ~= 0 then w * rr(r, 0.7, 1.4) else 0
		local rot = { rr(r, -24, 24), 0, 0 }
		rot[2] = rr(r, 0, 90)
		rot[3] = rr(r, -24, 24)
		local foot = { x + math.cos(a) * rad, base - 0.5, d + math.sin(a) * rad }
		local c = cols[i % #cols + 1]
		local mid = Core.add(foot, Core.turn({ 0, hh / 2, 0 }, rot))
		local tip = Core.add(foot, Core.turn({ 0, hh + ww * 0.45, 0 }, rot))
		table.insert(o, Core.box(n, ww, hh, ww, mid[1], mid[2], mid[3], c, m, { r = rot }))
		table.insert(o, Core.pyr(n .. " tip", ww, ww * 0.9, ww, tip[1], tip[2], tip[3], c, tipM or m, { r = rot }))
	end
	return o
end

function Core.coral(r: Rng, n, x, d, h, cols: { string }, m, y0: number?): { Part }
	local rr = Core.rr
	local base = y0 or 0
	local o = {}
	local function grow(p: { number }, len: number, rot: { number }, dep: number, c: string)
		local mid = Core.add(p, Core.turn({ 0, len / 2, 0 }, rot))
		local tip = Core.add(p, Core.turn({ 0, len, 0 }, rot))
		table.insert(o, Core.cyl(n, 0.8 + dep * 0.45, len, "y", mid[1], mid[2], mid[3], c, m, { r = rot }))
		if dep > 0 then
			-- Design's loop re-draws its bound each pass: `i < 2 + (r() < 0.4 ? 1 : 0)`.
			local i = 0
			while i < 2 + (if r() < 0.4 then 1 else 0) do
				local l2 = len * rr(r, 0.6, 0.8)
				local a2 = rot[1] + rr(r, -38, 38)
				local c2 = rot[3] + rr(r, -38, 38)
				grow(tip, l2, { a2, 0, c2 }, dep - 1, c)
				i += 1
			end
		else
			table.insert(o, Core.ball(n .. " tip", 1.5, tip[1], tip[2], tip[3], c, m))
		end
	end
	for i, c in cols do
		local k = i - 1
		local len = h * rr(r, 0.34, 0.44)
		local rx = rr(r, -12, 12)
		local rz = rr(r, -12, 12)
		grow({ x + (k - (#cols - 1) / 2) * 3.2, base, d + (k % 2) * 2.2 }, len, { rx, 0, rz }, 2, c)
	end
	return o
end

function Core.arc(n, R, y0, th, dep, segs, c, m, a0: number?, a1: number?): { Part }
	local from, to = a0 or 0, a1 or 180
	local o = {}
	local da = (to - from) / segs
	local chord = 2 * R * math.sin((da * math.pi) / 360) * 1.05
	for i = 0, segs - 1 do
		local t = from + (i + 0.5) * da
		local q = math.rad(t)
		table.insert(o, Core.box(n, chord, th, dep, R * math.cos(q), y0 + R * math.sin(q), 0, c, m, { r = { 0, 0, t + 90 } }))
	end
	return o
end

-- 5-point star. face: "d" faces the camera, "x" lies on a wall face, "y" lies flat on the floor.
function Core.star(n, x, y, d, s, c, m, face: string?, th: number?): { Part }
	local f = face or "d"
	local B = if f == "x" then { 0, 90 } elseif f == "y" then { 90, 0 } else { 0, 0 }
	local t = if th and th ~= 0 then th else s * 0.18
	local o = {}
	for k = 0, 4 do
		local a = 90 + k * 72
		local q = math.rad(a)
		local off = Core.turn({ math.cos(q) * s * 0.26, math.sin(q) * s * 0.26, 0 }, { B[1], B[2], 0 })
		table.insert(o, Core.box(n, s * 0.52, s * 0.2, t, x + off[1], y + off[2], d + off[3], c, m, { r = { B[1], B[2], a } }))
	end
	table.insert(o, Core.box(n, s * 0.32, s * 0.32, t * 1.1, x, y, d, c, m, { r = { B[1], B[2], 45 } }))
	return o
end

function Core.flame(n, x, y, d, s, c1, c2): { Part }
	return {
		Core.box(n, s, s, s, x, y + s * 0.5, d, c1, "Neon", { r = { 45, 0, 45 } }),
		Core.box(n, s * 0.68, s * 0.68, s * 0.68, x, y + s * 1.25, d, c2, "Neon", { r = { 45, 20, 45 } }),
		Core.box(n, s * 0.38, s * 0.38, s * 0.38, x, y + s * 1.8, d, c2, "Neon", { r = { 45, 40, 45 } }),
	}
end

function Core.column(n, x, d, h, dia, c, m, capC, capM, y0: number?): { Part }
	local base = y0 or 0
	return {
		Core.box(n .. " base", dia * 1.5, dia * 0.4, dia * 1.5, x, base + dia * 0.2, d, capC, capM),
		Core.cyl(n .. " shaft", dia, h - dia * 0.9, "y", x, base + dia * 0.4 + (h - dia * 0.9) / 2, d, c, m),
		Core.box(n .. " capital", dia * 1.5, dia * 0.5, dia * 1.5, x, base + h - dia * 0.25, d, capC, capM),
	}
end

function Core.fence(n, x, d, len, c, m, h: number?): { Part }
	local hh = h or 4
	local o = {}
	local z = 0
	while z <= len do
		table.insert(o, Core.box(n .. " picket", 0.8, hh, 0.5, x, hh / 2, d + z, c, m))
		table.insert(o, Core.pyr(n .. " tip", 0.8, 0.8, 0.5, x, hh + 0.4, d + z, c, m))
		z += 3
	end
	table.insert(o, Core.box(n .. " rail", 0.4, 0.5, len + 1, x - 0.5, hh * 0.35, d + len / 2, c, m))
	table.insert(o, Core.box(n .. " rail", 0.4, 0.5, len + 1, x - 0.5, hh * 0.75, d + len / 2, c, m))
	return o
end

function Core.drips(r: Rng, n, x0, y0, len, c, m, maxL: number?): { Part }
	local rr = Core.rr
	local top = maxL or 4.2
	local o = {}
	local z = 1
	while z < len do
		local L = rr(r, 0.8, top)
		local w = rr(r, 1.2, 2)
		table.insert(o, Core.box(n, w, L, w, x0, y0 - L / 2, z, c, m))
		table.insert(o, Core.ball(n .. " drop", w * 1.05, x0, y0 - L, z, c, m))
		z += rr(r, 2.2, 3.6)
	end
	return o
end

-- ---------- counting and checks (kit-core.js:178-218) ----------

function Core.matsOf(parts: { Part }): { string }
	local seen, out = {}, {}
	for _, p in parts do
		if not seen[p.m] then
			seen[p.m] = true
			table.insert(out, p.m)
		end
	end
	return out
end

local function ext(p: Part): { number }
	local d = p.d
	if p.s == "ball" then
		return { d[1] / 2, d[1] / 2, d[1] / 2 }
	elseif p.s == "cyl" then
		return if p.axis == "y"
			then { d[1] / 2, d[2] / 2, d[1] / 2 }
			elseif p.axis == "x" then { d[2] / 2, d[1] / 2, d[1] / 2 }
			else { d[1] / 2, d[1] / 2, d[2] / 2 }
	elseif p.s == "poly" then
		local xs, ds = 0, 0
		for _, q in p.pts :: { { number } } do
			xs, ds = math.max(xs, math.abs(q[1])), math.max(ds, math.abs(q[2]))
		end
		return { xs, d[1] / 2, ds }
	end
	return { d[1] / 2, d[2] / 2, d[3] / 2 }
end

-- The box of a part in its asset frame: lo / hi {x, y, d} (kit-core.js:195-202).
function Core.partBox(p: Part): ({ number }, { number })
	local e = ext(p)
	local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local v = { sx * e[1], sy * e[2], sz * e[3] }
				if p.s ~= "ball" and p.s ~= "poly" then
					v = Core.turn(v, p.r)
				end
				v = Core.add(p.at, v)
				for i = 1, 3 do
					lo[i], hi[i] = math.min(lo[i], v[i]), math.max(hi[i], v[i])
				end
			end
		end
	end
	return lo, hi
end

-- Parts inside the flight tube (|x| < keepX below keepY), by "asset / part" (kit-core.js:209-218): always empty.
function Core.tubeHits(z: any): { string }
	local hits = {}
	for _, a in z.props do
		for _, pl in a.pl do
			for _, p in a.parts do
				local lo, hi = Core.partBox(p)
				local y0 = lo[2] + (pl.y or 0)
				local side = if pl.x < 0 then -1 else 1
				local xa, xb = pl.x + side * lo[1], pl.x + side * hi[1]
				if y0 < Core.ROAD.keepY and math.min(xa, xb) < Core.ROAD.keepX and math.max(xa, xb) > -Core.ROAD.keepX then
					table.insert(hits, a.n .. " / " .. p.n)
					break
				end
			end
		end
	end
	return hits
end

return Core
