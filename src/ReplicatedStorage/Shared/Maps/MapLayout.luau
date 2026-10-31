--!strict
-- MapLayout: Diego's demos' layout(m) (NEW MAPS FINALS zip, "Squishy Duels {Duel,TDM,FFA} Demo.dc.html"): the seeded
-- decoration of one sky map (rim fence posts, string-light bulbs, team bunting, floor splats, floating sky props,
-- ambient bits, sparkles), the same numbers as his demo for the same map id. srng is his mulberry32 seeded by the id.
-- The doodles and the cloud bed are not built (the floor pattern is off in his demos, "no cloud bed under the
-- platforms"), but their draws stay so every later value matches the demo.
-- Pure: build(map) -> Layout; srng(seed) -> () -> number in [0, 1). MapLayout_Test checks values from the demo.

local MapData = require(script.Parent.MapData)

export type Bunting = { team: number, x: number, z0: number, z1: number, nF: number }
export type Layout = {
	RIM: number,
	off: number,
	posts: { { number } }, -- { x, z } on the rim's middle line
	bulbs: { { x: number, y: number, z: number, c: string } },
	bunting: { Bunting },
	splats: { { r: number, x: number, z: number, c: string } },
	sky: { { [string]: number } }, -- i, x, z, y, s, rx, ry, rz, ph, sp, amp, rs
	amb: { { [string]: any } }, -- x, z, y0, span, up, sp, ph, wf, wa, rx, ry, s, c
	sparkles: { { x: number, z: number, ph: number, sp: number, c: string } },
}

local MapLayout = {}

local TWO32 = 4294967296
local SPARKLE_COLOURS = { "#ffffff", "#ffe27a", "#ff7aa8", "#8fd8ff", "#b8f5c8" }

-- Math.imul: the low 32 bits of a * b (as an unsigned number), without losing bits to doubles.
local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xffff)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xffff)
	local cross = bit32.band(aHi * bLo + aLo * bHi, 0xffff)
	return (cross * 65536 + aLo * bLo) % TWO32
end

-- Diego's srng(seed): mulberry32 seeded with s = s * 31 + charCode (mod 2^32) over the seed's characters.
function MapLayout.srng(seed: string): () -> number
	local s = 0
	for i = 1, #seed do
		s = (s * 31 + string.byte(seed, i)) % TWO32
	end
	return function(): number
		s = (s + 0x6D2B79F5) % TWO32
		local t = s
		t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
		return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
	end
end

-- JS Math.round (halves go up).
local function round(x: number): number
	return math.floor(x + 0.5)
end

function MapLayout.build(map: MapData.Map): Layout
	local sr = MapLayout.srng(map.id)
	local function r(a: number, b: number): number
		return a + sr() * (b - a)
	end
	local W, H, D = map.W, map.H, map.deco
	local RIM = 6
	local off = RIM / 2
	local L = {} :: Layout
	L.RIM, L.off = RIM, off
	if D.floor == "doodle" then
		for _ = 1, 110 do -- not drawn (his floor pattern is off); keeps the draws in step
			r(0, W)
			r(0, H)
			r(1, 3.5)
		end
	end
	for _ = 1, 16 do -- the cloud bed: not built ("no cloud bed under the platforms"), draws kept
		for _ = 1, 6 do
			sr()
		end
	end
	L.sparkles = {}
	for i = 0, 17 do
		local x = r(4, W - 4)
		local z = r(4, H - 4)
		local ph = r(0, 1)
		local sp = r(0.12, 0.25)
		table.insert(L.sparkles, { x = x, z = z, ph = ph, sp = sp, c = SPARKLE_COLOURS[i % 5 + 1] })
	end
	local corners = { { -off, -off }, { W + off, -off }, { W + off, H + off }, { -off, H + off } }
	L.posts = {}
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, round(len / 26))
		for k = 0, n - 1 do
			table.insert(L.posts, { a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n })
		end
	end
	L.bulbs = {}
	for i, p in L.posts do
		local q = L.posts[i % #L.posts + 1]
		for k = 1, 5 do
			local t = k / 6
			table.insert(L.bulbs, {
				x = p[1] + (q[1] - p[1]) * t,
				y = MapLayout.sag(t) - 0.55,
				z = p[2] + (q[2] - p[2]) * t,
				c = D.pal[#L.bulbs % #D.pal + 1],
			})
		end
	end
	L.bunting = {}
	local spawnA, spawnB
	for _, e in map.elements do
		if e.type == "spawnA" and spawnA == nil then
			spawnA = e
		elseif e.type == "spawnB" and spawnB == nil then
			spawnB = e
		end
	end
	if spawnA and spawnB then
		for team, sp in { spawnA, spawnB } do
			local z0, z1 = sp.z - 6, sp.z + sp.d + 6
			table.insert(L.bunting, {
				team = team - 1,
				x = if team == 2 then W + off else -off,
				z0 = z0,
				z1 = z1,
				nF = round((z1 - z0) / 3.2),
			})
		end
	end
	L.splats = {}
	for i = 0, 9 do
		local rr = r(1.4, 3.6)
		local x = r(6, W / 2 - 6)
		local z = r(6, H - 6)
		local c = D.pal[i % #D.pal + 1]
		table.insert(L.splats, { r = rr, x = x, z = z, c = c })
		table.insert(L.splats, { r = rr, x = W - x, z = z, c = c })
	end
	local R0 = math.sqrt(W * W + H * H) / 2 + 45
	L.sky = {}
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2 + r(-0.15, 0.15)
		local d = R0 + r(10, 150)
		local q: { [string]: number } = { i = i, x = W / 2 + math.cos(a) * d, z = H / 2 + math.sin(a) * d }
		q.y = r(-45, 50)
		q.s = r(1.1, 2.3)
		q.rx = r(-0.5, 0.5)
		q.ry = r(0, 6)
		q.rz = r(-0.4, 0.4)
		q.ph = r(0, 6)
		q.sp = r(0.3, 0.6)
		q.amp = r(2, 4)
		q.rs = r(-0.18, 0.18)
		table.insert(L.sky, q)
	end
	local up = D.amb == "bubble"
	L.amb = {}
	for i = 0, 45 do
		local q: { [string]: any } = { up = up, y0 = if up then 0.5 else 2, span = if up then 26 else 32 }
		q.x = r(4, W - 4)
		q.z = r(4, H - 4)
		q.sp = if up then r(0.05, 0.1) else r(0.06, 0.12)
		q.ph = r(0, 1)
		q.wf = r(0.6, 1.4)
		q.wa = if up then 1.6 else 3
		q.rx = if up then 0 else r(-3, 3)
		q.ry = r(-3, 3)
		q.s = if up then r(0.7, 1.5) else 1
		q.c = D.pal[i % #D.pal + 1]
		table.insert(L.amb, q)
	end
	return L
end

-- The string lights' sag between two posts (t 0..1), L.sag.
function MapLayout.sag(t: number): number
	return 9 - 10.4 * t * (1 - t)
end

-- The team bunting's sag (t 0..1), L.bsag.
function MapLayout.bsag(t: number): number
	return 13.6 - 12 * t * (1 - t)
end

return MapLayout
