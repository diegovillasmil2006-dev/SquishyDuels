--!strict
-- HighwayKit.Zones67: zones 6-7 of Claude Design's highway kit v2 (kit-z67.js, ported 1:1). See HighwayKit/init.

return function(K: any, C: any): { any }
	local W = C.W
	local PK, GR, Y, LV, IC, LI = C.PK, C.GR, C.Y, C.LV, C.IC, C.LI
	local AU, GC = C.AU, C.GC
	local SP = "SmoothPlastic"
	local RAINBOW = { PK, LV, Y, GR, IC, LI }
	local tone, rng, rr, box, ball, cyl, pyr, turn, append = K.tone, K.rng, K.rr, K.box, K.ball, K.cyl, K.pyr, K.turn, K.append

	-- ---------- Zone 6 ----------
	local function starTower(n)
		local o = { cyl(n .. " shaft", 12, 92, "y", 0, 46, 0, W, "Marble") }
		for _, y in { 24, 50, 76 } do
			table.insert(o, cyl(n .. " band", 13.2, 2.4, "y", 0, y, 0, Y, "Foil"))
		end
		table.insert(o, cyl(n .. " crown", 16, 2.4, "y", 0, 93, 0, Y, "Foil"))
		for i = 0, 5 do
			local a = (i / 6) * 6.283
			table.insert(o, box(n .. " crenel", 3, 3, 3, math.cos(a) * 6.4, 95.6, math.sin(a) * 6.4, Y, "Foil"))
		end
		append(o, K.star(n .. " star", 0, 107, 0, 14, Y, "Neon"))
		return o
	end
	local function rainbowArch(n)
		local o = {}
		for i, c in RAINBOW do
			append(o, K.arc(n .. " band", 64 - (i - 1) * 2.1, 50, 2.2, 5, 22, c, "Neon", 14, 166))
		end
		return o
	end
	local function cloudPuff(r, n, s, y0, c: string?)
		local col = c or W
		local o = {}
		for _ = 0, 6 do
			local q = s * rr(r, 0.45, 0.85)
			local x = rr(r, -s * 0.6, s * 0.6)
			local y = y0 + rr(r, 0, s * 0.35)
			local d = rr(r, -s * 0.7, s * 0.7)
			table.insert(o, ball(n, q, x, y, d, col, "Snow"))
		end
		return o
	end
	local function starLamp(n)
		local o = {
			box(n .. " base", 2.4, 1, 2.4, 0, 0.5, 0, W, SP),
			cyl(n .. " post", 1, 18, "y", 0, 9, 0, W, SP),
			box(n .. " cross", 4, 0.6, 0.6, 0, 16, 0, W, SP),
		}
		append(o, K.star(n .. " star", 0, 21.5, 0, 6, Y, "Neon"))
		return o
	end
	local function planet(_r, n)
		local o = { ball(n .. " planet", 36, 0, 0, 0, Y, SP), ball(n .. " moon", 6, 30, 14, -6, W, SP), ball(n .. " moon", 4, -27, -10, 8, LI, SP) }
		for i = 0, 27 do
			local a = (i / 28) * 360
			local q = math.rad(a)
			local p = turn({ math.cos(q) * 30, 0, math.sin(q) * 30 }, { 22, 0, 0 })
			table.insert(o, box(n .. " ring", 7, 0.8, 2.4, p[1], p[2], p[3], if i % 2 == 1 then PK else tone(PK, 0.3), "Neon", { r = { 22, a + 90, 0 } }))
		end
		return o
	end
	local function floatIsland(r, n)
		local o = {}
		for i, s in { { 30, 6, 0 }, { 22, 6, -6 }, { 14, 6, -12 }, { 7, 5, -17.5 } } do
			local w, h, y = s[1], s[2], s[3]
			local k = i - 1
			table.insert(o, box(n .. " rock", w, h, w, 0, y, 0, if k % 2 == 1 then tone(LI, -0.2) else tone(LI, -0.3), "Rock", { r = { 0, k * 20, 0 } }))
		end
		table.insert(o, box(n .. " grass", 31, 1.6, 31, 0, 3.8, 0, GR, "Grass"))
		append(o, K.canopy(r, n .. " tree", -4, 14, 3, 9, { GR, tone(GR, -0.18) }, "Grass", 5))
		table.insert(o, box(n .. " trunk", 1.6, 8, 1.6, -4, 8.5, 3, tone(LI, -0.4), "Grass"))
		return o
	end
	local function wallStars(r, n)
		local o = {}
		for i = 0, 6 do
			local y = rr(r, 8, 40)
			local d = 6 + i * 14 + rr(r, -3, 3)
			local s = rr(r, 3, 6.5)
			append(o, K.star(n, -0.3, y, d, s, if i % 3 ~= 0 then W else Y, "Neon", "x", 0.4))
		end
		return o
	end
	local bands = {}
	for i, c in { IC, GR, Y, LV, PK } do
		table.insert(bands, { n = "Rainbow band", c = c, m = "SmoothPlastic", y0 = 44 + (i - 1) * 2.4, y1 = 46.4 + (i - 1) * 2.4, inset = -1, thick = 1, u = "bands" })
	end
	local tiers6 = { { n = "Crystal wall", c = LI, m = "Glacier", y0 = 0, y1 = 44, inset = 0, thick = 8 } }
	for _, b in bands do
		table.insert(tiers6, b)
	end
	table.insert(tiers6, { n = "Cloud tier", c = W, m = "Marble", y0 = 56, y1 = 61, inset = 2, thick = 6 })
	table.insert(tiers6, { n = "Lemon cap", c = Y, m = "Foil", y0 = 61, y1 = 64, inset = 2, thick = 6, over = 1 })
	local Z6 = {
		id = 6,
		name = "Rainbow Road",
		from = 4000,
		to = 6000,
		floor = { n = "Lilac floor", c = LI, m = "Ice", w = 140, th = 2, checker = 10 },
		lane = { stripes = RAINBOW, m = "Neon" },
		rail = { c = W, m = SP },
		tiers = tiers6,
		strips = {},
		once = {},
		outside = { clouds = { c = C.CLOUD6, y = -36, from = 80, size = 70 } },
		arch = { pillar = W, pillarM = "Marble", beam = LI, beamM = "Glacier", strip = Y, stripM = "Neon" },
		props = {
			{ k = "tower", n = "Star tower", parts = starTower("Star tower"), pl = { { x = 66, d = 50 }, { x = -66, d = 50 } } },
			{ k = "arch", n = "Rainbow arch", parts = rainbowArch("Rainbow arch"), pl = { { x = 0, d = 50, every = 2 } } },
			{ k = "wall", n = "Wall stars", parts = wallStars(rng(61), "Wall star"), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "wall", n = "Cloud spill", spill = true, parts = cloudPuff(rng(62), "Cloud spill", 20, 62), pl = { { x = 62, d = 80, alt = true } } },
			{ k = "verge", n = "Cloud puff", parts = cloudPuff(rng(63), "Cloud puff", 10, 2), pl = { { x = 42, d = 20 }, { x = -46, d = 70 } } },
			{ k = "verge", n = "Crystal cluster", parts = K.crystals(rng(64), "Crystal", 0, 0, 6, 15, 2.6, { LI, tone(LI, 0.35), Y }, "Glass", "Neon"), pl = { { x = 28, d = 34 }, { x = -27, d = 88 } } },
			{ k = "verge", n = "Star lamp", parts = starLamp("Star lamp"), pl = { { x = 22, d = 66 }, { x = -22, d = 16 } } },
			{ k = "floor", n = "Star tile", parts = K.star("Star tile", 0, 0.12, 0, 9, Y, "Neon", "y", 0.24), pl = { { x = 36, d = 92, alt = true } } },
			{ k = "outside", n = "Ringed planet", parts = planet(rng(65), "Planet"), pl = { { x = 130, d = 30, y = 112, alt = true } } },
			{ k = "outside", n = "Floating island", parts = floatIsland(rng(66), "Island"), pl = { { x = -112, d = 70, y = 70, alt = true } } },
		},
		fx = {
			particles = {
				{ kind = "Star sparkles", cols = { Y, W }, size = { 0.3, 0.7 }, rate = 2, life = 3, speed = 1, dir = "burst", em = { { x = 66, y = 107, d = 50 }, { x = -66, y = 107, d = 50 }, { x = 22, y = 21, d = 66 }, { x = -22, y = 21, d = 16 } } },
				{ kind = "Star dust", cols = { W, LI, IC }, size = { 0.3, 0.5 }, rate = 2, life = 4, speed = 2, dir = "down", em = { { x = 30, y = 108, d = 50 }, { x = -30, y = 108, d = 50 } } },
			},
			lights = {},
			beams = {},
		},
	}

	-- ---------- Zone 7 ----------
	local function marbleTower(n)
		local o = { cyl(n .. " shaft", 16, 104, "y", 0, 52, 0, W, "Marble") }
		for _, y in { 40, 79, 104 } do
			table.insert(o, cyl(n .. " ring", 17.6, 2.4, "y", 0, y, 0, AU, "Foil"))
		end
		for i = 0, 7 do
			local a = (i / 8) * 6.283
			table.insert(o, cyl(n .. " colonnette", 1.6, 10, "y", math.cos(a) * 7, 110, math.sin(a) * 7, W, "Marble"))
		end
		table.insert(o, cyl(n .. " cornice", 18, 2, "y", 0, 116, 0, AU, "Foil"))
		table.insert(o, ball(n .. " dome", 16, 0, 117, 0, AU, "Foil"))
		table.insert(o, cyl(n .. " spire", 1.4, 10, "y", 0, 128, 0, AU, "Foil"))
		table.insert(o, ball(n .. " finial", 3, 0, 133.5, 0, GC, "Foil"))
		return o
	end
	local function goldArch(n)
		local o = K.arc(n, 66, 50, 5, 8, 22, AU, "Foil", 15, 165)
		append(o, K.arc(n .. " trim", 62.8, 50, 1.2, 6, 22, GC, "Neon", 15, 165))
		table.insert(o, box(n .. " keystone", 7, 9, 10, 0, 116.5, 0, AU, "Foil"))
		return o
	end
	local function pilasters(_r, n)
		local o = {}
		for _, z in { 0, 25, 50, 75 } do
			table.insert(o, box(n .. " pilaster", 4, 52, 5, -1.6, 28, z, W, "Marble"))
			table.insert(o, box(n .. " base", 5.2, 3, 6.2, -1.8, 1.5, z, AU, "Foil"))
			-- Design's y 54.5, 0.03 up (Prims.LAYER): the first one straddles the seam, its top met Rainbow Road's top
			-- band (y 56) and flickered (Flicker_Test 2026-10-23).
			table.insert(o, box(n .. " capital", 5.6, 3, 6.6, -2, 54.53, z, AU, "Foil"))
		end
		for _, z in { 12.5, 62.5 } do
			table.insert(o, box(n .. " banner", 0.5, 24, 9, -0.9, 36, z, IC, "Fabric"))
			table.insert(o, box(n .. " tail", 0.5, 4.4, 4.6, -0.9, 22.6, z - 2.3, IC, "Fabric", { r = { 28, 0, 0 } }))
			table.insert(o, box(n .. " tail", 0.5, 4.4, 4.6, -0.9, 22.6, z + 2.3, IC, "Fabric", { r = { -28, 0, 0 } }))
			table.insert(o, box(n .. " rod", 1, 1, 11, -1.2, 48.4, z, AU, "Foil"))
			append(o, K.star(n .. " emblem", -1.3, 38, z, 6, AU, "Foil", "x", 0.4))
		end
		return o
	end
	local function fountain(_r, n)
		local o = {
			cyl(n .. " basin", 16, 2.4, "y", 0, 1.2, 0, W, "Marble"),
			cyl(n .. " water", 14, 0.4, "y", 0, 2.3, 0, IC, "Glass"),
			cyl(n .. " pedestal", 2.6, 8, "y", 0, 6, 0, W, "Marble"),
			cyl(n .. " bowl", 8, 1.6, "y", 0, 10.4, 0, W, "Marble"),
			cyl(n .. " water", 6.8, 0.4, "y", 0, 11.2, 0, IC, "Glass"),
			cyl(n .. " stem", 1.6, 4, "y", 0, 13, 0, W, "Marble"),
			cyl(n .. " cup", 4, 1.2, "y", 0, 15.4, 0, AU, "Foil"),
			ball(n .. " finial", 2.2, 0, 17, 0, AU, "Foil"),
		}
		for i = 0, 7 do
			local a = (i / 8) * 6.283
			table.insert(o, cyl(n .. " stream", 0.6, 8.2, "y", math.cos(a) * 3.9, 6.6, math.sin(a) * 3.9, IC, "Glass"))
		end
		return o
	end
	local function medallion(n)
		local o = {}
		for i = 0, 11 do
			local a = i * 30
			local q = math.rad(a)
			local odd = i % 2 == 1
			table.insert(o, box(n .. " ray", 1, 0.2, if odd then 6 else 9, math.sin(q) * (if odd then 6 else 7.5), 0.1, math.cos(q) * (if odd then 6 else 7.5), AU, "Foil", { r = { 0, a, 0 } }))
		end
		for i = 0, 19 do
			local a = i * 18
			local q = math.rad(a)
			table.insert(o, box(n .. " ring", 1.6, 0.22, 0.8, math.cos(q) * 3.6, 0.11, math.sin(q) * 3.6, AU, "Foil", { r = { 0, -a, 0 } }))
		end
		table.insert(o, cyl(n .. " sun", 4.6, 0.26, "y", 0, 0.13, 0, AU, "Foil"))
		return o
	end
	local function gates(n)
		local o = {}
		for _, x in { -50, 50 } do
			table.insert(o, cyl(n .. " pillar", 20, 150, "y", x, 75, 0, AU, "Foil"))
			table.insert(o, box(n .. " plinth", 26, 8, 26, x, 4, 0, W, "Marble"))
			table.insert(o, ball(n .. " orb", 22, x, 161, 0, GC, "Neon"))
		end
		table.insert(o, box(n .. " lintel", 124, 12, 14, 0, 126, 0, AU, "Foil"))
		table.insert(o, pyr(n .. " pediment", 124, 22, 12, 0, 143, 0, GC, "Foil"))
		table.insert(o, box(n .. " door", 38, 110, 2, -21, 55, 0, W, "Marble"))
		table.insert(o, box(n .. " door", 38, 110, 2, 21, 55, 0, W, "Marble"))
		table.insert(o, box(n .. " light slit", 4, 110, 1, 0, 55, -1.5, W, "Neon"))
		for _, sx in { -1, 1 } do
			for i = 0, 4 do
				table.insert(o, box(n .. " bar", 1.4, 100, 0.8, sx * (8 + i * 7), 55, -1.4, AU, "Foil"))
			end
		end
		return o
	end
	local Z7 = {
		id = 7,
		name = "Divine Heaven",
		from = 6000,
		to = 8500,
		floor = { n = "Marble floor", c = W, m = "Marble", w = 140, th = 2, checker = 10 },
		lane = { c = GC, m = "Marble" },
		rail = { c = AU, m = "Foil" },
		tiers = {
			{ n = "Marble wall", c = W, m = "Marble", y0 = 0, y1 = 56, inset = 0, thick = 10, u = "marble" },
			{ n = "Gold band", c = AU, m = "Foil", y0 = 56, y1 = 58, inset = -1, thick = 11, u = "gold" },
			{ n = "Upper tier", c = W, m = "Marble", y0 = 58, y1 = 76, inset = 3, thick = 7, u = "marble" },
			{ n = "Gold cap", c = AU, m = "Foil", y0 = 76, y1 = 79, inset = 3, thick = 7, over = 1, u = "gold" },
			{ n = "Glow crest", c = GC, m = "Neon", y0 = 79, y1 = 80, inset = 5, thick = 3 },
		},
		strips = { { n = "Water channel", c = IC, m = "Glass", x0 = 50, x1 = 58, y0 = 0, y1 = 0.15, sym = true } },
		outside = { clouds = { c = GC, y = -20, from = 80, size = 80 } },
		arch = { pillar = W, pillarM = "Marble", beam = AU, beamM = "Foil", strip = GC, stripM = "Neon" },
		props = {
			{ k = "tower", n = "Marble tower", parts = marbleTower("Marble tower"), pl = { { x = 68, d = 50 }, { x = -68, d = 50 } } },
			{ k = "arch", n = "Gold arch", parts = goldArch("Gold arch"), pl = { { x = 0, d = 50 } } },
			{ k = "wall", n = "Pilasters and banners", parts = pilasters(rng(71), "Pilaster"), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "wall", n = "Gold cloud spill", spill = true, parts = cloudPuff(rng(72), "Gold cloud", 22, 78, GC), pl = { { x = 64, d = 20, alt = true } } },
			{ k = "verge", n = "Fountain", parts = fountain(rng(73), "Fountain"), pl = { { x = 36, d = 26, alt = true } } },
			{
				k = "verge",
				n = "Gold column",
				parts = (function()
					local o = K.column("Column", 0, 0, 26, 4, AU, "Foil", AU, "Foil")
					table.insert(o, ball("Column orb", 4, 0, 28, 0, GC, "Foil"))
					return o
				end)(),
				pl = { { x = -42, d = 70 }, { x = 44, d = 82 } },
			},
			{ k = "floor", n = "Sun medallion", parts = medallion("Medallion"), pl = { { x = -34, d = 36, alt = true } } },
		},
		once = { { n = "Golden Gates", parts = gates("Gates"), pos = { { x = 0, d = 2500 } } } },
		fx = {
			particles = {
				{ kind = "Gold sparkles", cols = { AU, W }, size = { 0.3, 0.7 }, rate = 2, life = 3, speed = 1, dir = "burst", em = { { x = 68, y = 117, d = 50 }, { x = -68, y = 117, d = 50 } } },
				{ kind = "Petals", cols = { W, GC }, size = { 0.5, 0.9 }, rate = 2, life = 4, speed = 2.5, dir = "down", em = { { x = 30, y = 110, d = 50 }, { x = -30, y = 110, d = 50 } } },
				{ kind = "Shimmer", cols = { GC, W }, size = { 0.3, 0.5 }, rate = 2, life = 3, speed = 1, dir = "burst", em = { { x = 54, y = 2, d = 30 }, { x = -54, y = 2, d = 80 } } },
			},
			lights = { { kind = "SurfaceLight", c = GC, where = "gateSlit", range = 60, brightness = 2 } },
			beams = { { n = "Light stream", c = GC, x = 54, y = 0.8, jag = 3, w = 0.45, sym = true } },
		},
	}
	return { Z6, Z7 }
end
