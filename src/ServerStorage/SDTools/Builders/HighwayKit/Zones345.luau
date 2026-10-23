--!strict
-- HighwayKit.Zones345: zones 3-5 of Claude Design's highway kit v2 (kit-z345.js, ported 1:1). See HighwayKit/init.

return function(K: any, C: any): { any }
	local W, INK = C.W, C.K
	local PK, GR, Y, LV, CR, BR, SB = C.PK, C.GR, C.Y, C.LV, C.CR, C.BR, C.SB
	local TL, AQ, MT, IC, IL, RK, LI = C.TL, C.AQ, C.MT, C.IC, C.IL, C.RK, C.LI
	local SP = "SmoothPlastic"
	local tone, rng, rr, box, ball, cyl, wedge, pyr, poly, blob, turn, add, append =
		K.tone, K.rng, K.rr, K.box, K.ball, K.cyl, K.wedge, K.pyr, K.poly, K.blob, K.turn, K.add, K.append

	-- ---------- Zone 3 ----------
	local function island(r, n, rx, rd, withPalm)
		local o = { poly(n .. " sand", blob(r, rx, rd), 1, 0.5, MT, "Sand") }
		if withPalm then
			append(o, K.palm(r, n .. " palm", 0, 2, 22, 14, CR, GR, CR, 1))
		end
		append(o, K.rocks(r, n .. " rock", rx * 0.45, -rd * 0.4, 3, 2.6, tone(TL, -0.42), "Rock", 1))
		return o
	end
	local function reef(r, n)
		local o = { poly(n .. " sand", blob(r, 7, 9), 0.8, 0.4, MT, "Sand") }
		append(o, K.coral(r, n .. " coral", 0, 0, 14, { PK, Y, tone(TL, 0.35) }, "Plastic", 0.8))
		for k = 0, 4 do
			local a = 90 + k * 72
			local q = math.rad(a)
			table.insert(o, box(n .. " starfish", 1.8, 0.4, 0.8, 4 + math.cos(q) * 0.9, 1, -4 + math.sin(q) * 0.9, Y, "Plastic", { r = { 0, -a, 0 } }))
		end
		return o
	end
	local function tippedCup(r, n)
		local y = 41
		local o = {
			cyl(n .. " cup", 15, 24, "x", 4, y, 0, MT, "Glass", { r = { 0, 0, 8 } }),
			cyl(n .. " tea", 13.4, 20, "x", 5, y - 0.8, 0, tone(MT, -0.18), SP, { r = { 0, 0, 8 } }),
			cyl(n .. " straw", 1.8, 20, "x", 0, y + 4, 2, PK, "Neon", { r = { 0, 0, -16 } }),
			cyl(n .. " lid", 16, 1.4, "y", -14, 0.7, 9, W, SP),
			poly(n .. " spill", blob(r, 5, 7), 0.2, 0.15, tone(MT, -0.1), "Glass"),
		}
		o[#o].at = { -7, 0.15, -2 }
		for i = 0, 8 do
			local x = -1.8 - rr(r, 0, 0.6)
			local d = rr(r, -3, 3)
			table.insert(o, ball(n .. " pearl", 3, x, 36 - i * 3.9, d, INK, SP))
		end
		for _ = 0, 4 do
			local x = -4 - rr(r, 0, 5)
			local d = rr(r, -4, 4)
			table.insert(o, ball(n .. " pearl", 3, x, 1.5, d, INK, SP))
		end
		return o
	end
	local function cupTower(r, n)
		local o = {
			cyl(n .. " cup", 18, 44, "y", 0, 22, 0, MT, "Glass"),
			cyl(n .. " tea", 16.4, 34, "y", 0, 17.2, 0, tone(MT, -0.14), SP),
			cyl(n .. " lid", 19.4, 2, "y", 0, 45, 0, W, SP),
			ball(n .. " dome", 12, 0, 45.4, 0, W, SP),
			cyl(n .. " straw", 2.2, 30, "y", 2, 56, 0, PK, "Neon", { r = { 0, 0, 12 } }),
		}
		for _ = 0, 9 do
			local a = r() * 6.283
			local q = rr(r, 0, 5.5)
			local y = 1.8 + rr(r, 0, 3)
			table.insert(o, ball(n .. " pearl", 3.4, math.cos(a) * q, y, math.sin(a) * q, INK, SP))
		end
		return o
	end
	local function pearls(n)
		local o = {}
		for _, s in { { 0, 0, 0 }, { 3, 0, 0.4 }, { 1.5, 0, 2.6 }, { -1.6, 0, 1.8 }, { 1.5, 2.6, 1 }, { -0.2, 2.6, 0.6 }, { 0.6, 5, 0.9 } } do
			table.insert(o, ball(n, 3.2, s[1], 1.6 + s[2], s[3], INK, SP))
		end
		return o
	end
	local function lilies(r, n)
		local o = {}
		for i = 0, 4 do
			local dia = rr(r, 2.6, 4.2)
			local x = rr(r, -6, 6)
			local d = rr(r, -7, 7)
			table.insert(o, cyl(n .. " pad", dia, 0.25, "y", x, 0.3, d, if i % 2 == 1 then GR else tone(GR, -0.15), "Plastic"))
		end
		for _, off in { { 0.7, 0 }, { -0.7, 0 }, { 0, 0.7 }, { 0, -0.7 } } do
			table.insert(o, box(n .. " bloom", 0.9, 0.5, 0.9, o[1].at[1] + off[1], 0.7, o[1].at[3] + off[2], PK, "Plastic"))
		end
		return o
	end
	local function kelp(r, n, c)
		local o = {}
		for s = 0, 3 do
			local x, y = (s - 1.5) * 2.2, 0
			local h = rr(r, 10, 19)
			local k = 6
			for i = 0, k - 1 do
				local seg = h / k
				local a = (if i % 2 == 1 then 11 else -11) + rr(r, -4, 4)
				local q = math.rad(a)
				table.insert(o, box(n, 1.4, seg * 1.12, 0.6, x - (math.sin(q) * seg) / 2, y + seg / 2, (s % 2) * 1.4, tone(c, (i % 2) * 0.1), "LeafyGrass", { r = { 0, 0, a } }))
				x -= math.sin(q) * seg
				y += seg * 0.97
			end
		end
		return o
	end
	local function waterfall(r, n, h, c, m: string?)
		local mat = m or "Glass"
		local o = {
			box(n .. " sheet", 1.4, h, 12, -0.9, h / 2, 0, c, mat),
			box(n .. " sheet", 0.6, h, 7, -1.9, h / 2, 0.6, tone(c, 0.45), mat),
			box(n .. " lip", 2.4, 1.4, 13, -0.8, h - 0.2, 0, tone(c, 0.3), mat),
		}
		for _ = 0, 8 do
			local dia = rr(r, 2, 3.4)
			local x = -rr(r, 1.5, 5.5)
			local d = rr(r, -6, 6)
			table.insert(o, ball(n .. " foam", dia, x, 0.9, d, W, SP))
		end
		table.insert(o, cyl(n .. " pool", 18, 0.3, "y", -7, 0.15, 0, tone(c, 0.3), mat))
		return o
	end
	local function curtain(r, n, y0, c, m)
		local o = {}
		local z = 1
		while z < 100 do
			local L = rr(r, 3, 14)
			local col = tone(c, rr(r, -0.1, 0.1))
			local rx = rr(r, -6, 6)
			table.insert(o, box(n, 0.8, L, 1.3, -1.6, y0 - L / 2, z, col, m, { r = { rx, 0, 0 } }))
			z += rr(r, 2, 4)
		end
		return o
	end
	local Z3 = {
		id = 3,
		name = "Boba Lagoon",
		from = 800,
		to = 1500,
		floor = { n = "Lagoon water", c = AQ, m = "Glass", w = 136, th = 2 },
		lane = { c = MT, m = "Sand" },
		rail = { c = W, m = SP },
		tiers = {
			{ n = "Reef wall", c = TL, m = "Rock", y0 = 0, y1 = 30, inset = 0, thick = 6 },
			{ n = "Sand cap", c = MT, m = "Sand", y0 = 30, y1 = 33, inset = 0, thick = 6, over = 1 },
		},
		strips = {},
		once = {},
		outside = { ground = { c = tone(AQ, -0.12), m = "Glass", y = -1, from = 66 } },
		arch = { pillar = TL, pillarM = "Rock", beam = MT, beamM = "Sand", strip = PK, stripM = "Neon" },
		props = {
			{ k = "wall", n = "Seaweed curtain", parts = curtain(rng(31), "Seaweed", 30, tone(TL, -0.32), "LeafyGrass"), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "wall", n = "Tipped boba cup", spill = true, parts = tippedCup(rng(32), "Tipped cup"), pl = { { x = 60, d = 52, alt = true } } },
			{ k = "wall", n = "Waterfall", parts = waterfall(rng(33), "Waterfall", 31, AQ), pl = { { x = -60, d = 40, alt = true } } },
			{ k = "verge", n = "Palm island", parts = island(rng(34), "Island", 11, 14, true), pl = { { x = 40, d = 24, alt = true } } },
			{ k = "verge", n = "Coral reef", parts = reef(rng(35), "Reef"), pl = { { x = -36, d = 72, alt = true } } },
			{ k = "verge", n = "Pearl pile", parts = pearls("Pearl"), pl = { { x = 26, d = 12 }, { x = -28, d = 46 } } },
			{ k = "verge", n = "Kelp", parts = kelp(rng(36), "Kelp", tone(TL, -0.3)), pl = { { x = 54, d = 8 }, { x = -54, d = 92 } } },
			{ k = "floor", n = "Lily pads", parts = lilies(rng(37), "Lily"), pl = { { x = 30, d = 86 }, { x = -46, d = 10 } } },
			{ k = "outside", n = "Boba cup tower", parts = cupTower(rng(38), "Cup tower"), pl = { { x = -76, d = 20, alt = true } } },
			{
				k = "outside",
				n = "Far island",
				parts = (function()
					local o = island(rng(39), "Far island", 26, 22, true)
					append(o, K.palm(rng(40), "Far palm", -9, -6, 26, -10, CR, GR, CR, 1))
					return o
				end)(),
				pl = { { x = 150, d = 50, every = 2, alt = true, y = -1 } },
			},
		},
		fx = {
			particles = {
				{ kind = "Bubbles", cols = { W, IL }, size = { 0.6, 1.1 }, rate = 1.5, life = 3, speed = 3, dir = "up", em = { { x = -53, y = 0.5, d = 40, alt = true }, { x = -36, y = 1, d = 72, alt = true } } },
			},
			lights = {},
			beams = {},
		},
	}

	-- ---------- Zone 4 ----------
	local function coneTower(r, n, s1, s2)
		local o = {}
		for i = 0, 5 do
			table.insert(o, cyl(n .. " wafer", 4 + i * 2.3, 9.2, "y", 0, 4.6 + i * 9, 0, BR, "Fabric"))
		end
		table.insert(o, cyl(n .. " rim", 17.6, 2, "y", 0, 55, 0, tone(BR, -0.12), "Fabric"))
		table.insert(o, ball(n .. " scoop", 18, 0, 63, 0, s1, "Snow"))
		table.insert(o, ball(n .. " scoop", 13, 0, 74, 0, s2, "Snow"))
		table.insert(o, ball(n .. " cherry", 3.2, 0, 81.6, 0, LV, SP))
		for i = 0, 6 do
			local a = i * 0.9 + 0.3
			local L = rr(r, 3, 8)
			table.insert(o, box(n .. " drip", 2, L, 2, math.cos(a) * 8.4, 57 - L / 2, math.sin(a) * 8.4, s1, "Snow"))
			table.insert(o, ball(n .. " drip", 2.2, math.cos(a) * 8.4, 57 - L, math.sin(a) * 8.4, s1, "Snow"))
		end
		return o
	end
	local function popsicles(n)
		local o = {
			box(n .. " stick", 1.2, 6, 0.6, 0, 3, 0, SB, "Wood"),
			box(n .. " bar", 5, 11, 2.2, 0, 11, 0, PK, SP),
			box(n .. " stripe", 5.1, 1, 2.3, 0, 9, 0, W, SP),
			box(n .. " stripe", 5.1, 1, 2.3, 0, 13, 0, W, SP),
		}
		local rot, b = { 0, 25, -14 }, { 5.4, 0, 1.5 }
		for _, s in { { " stick", 1.2, 6, 0.6, 3, SB, "Wood" }, { " bar", 4.6, 10, 2.2, 10.6, Y, SP }, { " stripe", 4.7, 1, 2.3, 12.4, PK, SP } } do
			local p = add(b, turn({ 0, s[5], 0 }, rot))
			table.insert(o, box(n .. s[1], s[2], s[3], s[4], p[1], p[2], p[3], s[6], s[7], { r = rot }))
		end
		return o
	end
	local function scoopman(n)
		return {
			ball(n .. " body", 9, 0, 4, 0, W, "Snow"),
			ball(n .. " body", 7, 0, 10.4, 0, GR, "Snow"),
			ball(n .. " head", 5.4, 0, 15.6, 0, PK, "Snow"),
			pyr(n .. " hat", 4.4, 6, 4.4, 0, 20.8, 0, BR, "Fabric"),
			cyl(n .. " scarf", 6.2, 1.3, "y", 0, 13.2, 0, LI, "Fabric"),
			box(n .. " scarf", 1.6, 5, 0.6, 1.6, 11, -3, LI, "Fabric", { r = { 0, 0, -10 } }),
			box(n .. " eye", 0.7, 0.9, 0.4, -1, 16.3, -2.5, INK, SP),
			box(n .. " eye", 0.7, 0.9, 0.4, 1, 16.3, -2.5, INK, SP),
			box(n .. " nose", 0.8, 0.8, 1.8, 0, 15.5, -3, LV, SP),
			box(n .. " arm", 6, 0.6, 0.6, -5.6, 11.6, 0, CR, SP, { r = { 0, 0, -25 } }),
			box(n .. " arm", 6, 0.6, 0.6, 5.6, 11.6, 0, CR, SP, { r = { 0, 0, 25 } }),
		}
	end
	local function igloo(n)
		local o = {}
		local R = 8
		for k = 0, 3 do
			local phi = math.rad(k * 21 + 8)
			local rad = R * math.cos(phi)
			local y = R * math.sin(phi)
			local cnt = math.max(5, math.floor(13 * math.cos(phi) + 0.5))
			for i = 0, cnt - 1 do
				local a = ((i + (k % 2) * 0.5) / cnt) * 360
				if not (k < 2 and a > 245 and a < 295) then
					local q = math.rad(a)
					table.insert(o, box(n .. " block", ((2 * math.pi * rad) / cnt) * 0.94, 3.4, 2.8, math.cos(q) * rad, y + 1.3, math.sin(q) * rad, if (i + k) % 2 == 1 then W else IL, "Ice", { r = { 0, a + 90, 0 } }))
				end
			end
		end
		table.insert(o, ball(n .. " top", 7, 0, 7.4, 0, W, "Ice"))
		table.insert(o, box(n .. " tunnel", 5.6, 5, 5, 0, 2.5, -8.6, IL, "Ice"))
		table.insert(o, box(n .. " door", 3, 3.6, 0.4, 0, 1.9, -11.2, INK, "Ice"))
		return o
	end
	local function drift(r, n)
		local o = { wedge(n, 6, 5, 18, 2, 2.5, 0, W, "Snow") }
		for _ = 0, 4 do
			local dia = rr(r, 4, 8)
			local x = rr(r, -3, 2)
			local y = rr(r, -1.5, 0.5)
			local d = rr(r, -8, 8)
			table.insert(o, ball(n, dia, x, y, d, W, "Snow"))
		end
		return o
	end
	local function meltScoop(r, n)
		local o = { ball(n .. " scoop", 18, -1, 48, 0, PK, "Snow") }
		for i = 0, 4 do
			local L = rr(r, 8, 26)
			local d = -6 + i * 3
			table.insert(o, box(n .. " drip", 2.2, L, 2.2, -5.4, 42 - L / 2, d, PK, "Snow"))
			table.insert(o, ball(n .. " drip", 2.6, -5.4, 42 - L, d, PK, "Snow"))
		end
		return o
	end
	local function icicles(r, n)
		local o = {}
		local z = 1
		while z < 100 do
			local h = rr(r, 2, 9)
			local w = rr(r, 1.2, 2.2)
			table.insert(o, pyr(n, w, h, w, -1.6, 40 - h / 2, z, IL, "Ice", { r = { 180, 0, 0 } }))
			z += rr(r, 2.5, 5)
		end
		return o
	end
	local function frozenPond(r, n)
		local o = { poly(n .. " ice", blob(r, 9, 12), 0.3, 0.16, tone(IC, 0.3), "Ice") }
		for _ = 0, 3 do
			local len = rr(r, 3, 7)
			local x = rr(r, -5, 5)
			local d = rr(r, -6, 6)
			local ry = rr(r, 0, 180)
			table.insert(o, box(n .. " crack", 0.3, 0.1, len, x, 0.34, d, W, "Ice", { r = { 0, ry, 0 } }))
		end
		table.insert(o, box(n .. " block", 3, 2.4, 3, 6, 1.2, 6, IC, "Ice", { r = { 0, 20, 8 } }))
		table.insert(o, box(n .. " block", 2.2, 1.8, 2.2, 7.4, 0.9, 2.6, IL, "Ice", { r = { 0, 40, -6 } }))
		return o
	end
	local function peaks(n)
		local o = {}
		local y = 0
		for i, s in { { 60, 22 }, { 44, 20 }, { 28, 18 }, { 14, 12 } } do
			local w, h = s[1], s[2]
			local k = i - 1
			table.insert(o, box(n .. " step", w, h, w, 0, y + h / 2, 0, if k % 2 == 1 then tone(IC, 0.2) else IC, "Glacier", { r = { 0, k * 15, 0 } }))
			table.insert(o, box(n .. " snow", w * 0.84, 2.2, w * 0.84, 0, y + h + 1.1, 0, W, "Snow", { r = { 0, k * 15 + 7, 0 } }))
			y += h
		end
		return o
	end
	local Z4 = {
		id = 4,
		name = "Frozen Dessert Peaks",
		from = 1500,
		to = 2500,
		floor = { n = "Snow floor", c = W, m = "Snow", w = 140, th = 2, checker = 10 },
		lane = { c = IL, m = "Ice" },
		rail = { c = IC, m = SP },
		tiers = {
			{ n = "Glacier wall", c = IC, m = "Glacier", y0 = 0, y1 = 40, inset = 0, thick = 8 },
			{ n = "Snow cap", c = W, m = "Snow", y0 = 40, y1 = 44, inset = 0, thick = 8, over = 1 },
		},
		strips = {},
		once = {},
		outside = { ground = { c = W, m = "Snow", y = 30, from = 69 }, peaks = { m = "Glacier", c = IC, cap = W } },
		arch = { pillar = IC, pillarM = "Glacier", beam = W, beamM = "Snow", strip = IC, stripM = "Neon" },
		props = {
			{ k = "tower", n = "Cone tower", parts = coneTower(rng(41), "Cone tower", PK, GR), pl = { { x = 64, d = 20, alt = true, altC = { ["Cone tower scoop"] = GR } } } },
			{ k = "wall", n = "Icicles", parts = icicles(rng(42), "Icicle"), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "wall", n = "Melting scoop", spill = true, parts = meltScoop(rng(43), "Melting scoop"), pl = { { x = 64, d = 78, alt = true } } },
			{ k = "verge", n = "Snowy pine", parts = K.pine(rng(44), "Pine", 0, 0, 26, 12, CR, tone(TL, -0.25), W), pl = { { x = 48, d = 58 }, { x = -44, d = 26 } } },
			{
				k = "verge",
				n = "Ice crystals",
				parts = (function()
					local o = K.crystals(rng(45), "Crystal", 0, 0, 6, 13, 2.4, { IC, IL }, "Neon")
					local snow = drift(rng(46), "Crystal snow")
					for i = 2, 4 do
						table.insert(o, snow[i])
					end
					return o
				end)(),
				pl = { { x = 27, d = 40 }, { x = -30, d = 84 } },
			},
			{ k = "verge", n = "Popsicles", parts = popsicles("Popsicle"), pl = { { x = -25, d = 58, alt = true } } },
			{ k = "verge", n = "Scoop-man", parts = scoopman("Scoop-man"), pl = { { x = 34, d = 92, alt = true } } },
			{ k = "verge", n = "Igloo", parts = igloo("Igloo"), pl = { { x = -48, d = 66, alt = true } } },
			{ k = "verge", n = "Snow drift", parts = drift(rng(47), "Drift"), pl = { { x = 56, d = 36 }, { x = -56, d = 4 } } },
			{ k = "floor", n = "Frozen pond", parts = frozenPond(rng(48), "Pond"), pl = { { x = 38, d = 8, alt = true } } },
			{ k = "outside", n = "Snow peak", parts = peaks("Peak"), pl = { { x = 116, d = 50, every = 2, alt = true, y = 30 } } },
			{
				k = "outside",
				n = "Pine grove",
				parts = (function()
					local o = K.pine(rng(49), "Grove pine", 0, 0, 30, 13, CR, tone(TL, -0.25), W)
					append(o, K.pine(rng(50), "Grove pine", 12, 8, 22, 10, CR, tone(TL, -0.15), W))
					append(o, K.pine(rng(51), "Grove pine", 4, -12, 26, 11, CR, tone(TL, -0.3), W))
					return o
				end)(),
				pl = { { x = 86, d = 30, y = 30, alt = true } },
			},
		},
		fx = {
			particles = {
				{ kind = "Snow", cols = { W }, size = { 0.4, 0.8 }, rate = 2, life = 4, speed = 2, dir = "down", em = { { x = 64, y = 62, d = 20, alt = true }, { x = -62, y = 48, d = 60 }, { x = 62, y = 48, d = 90 } } },
				{ kind = "Ice sparkles", cols = { IC, W }, size = { 0.3, 0.6 }, rate = 2, life = 2, speed = 1, dir = "burst", em = { { x = 27, y = 9, d = 40 }, { x = -30, y = 9, d = 84 } } },
			},
			lights = {},
			beams = {},
		},
	}

	-- ---------- Zone 5 ----------
	local function spire(_r, n, h)
		local o = {}
		for i, s in { { 0, 0, 12, h }, { -3.5, 4.5, 8, h * 0.74 }, { 3, -5, 7, h * 0.6 }, { -3, -4.5, 6, h * 0.48 } } do
			local x, d, w, hh = s[1], s[2], s[3], s[4]
			local k = i - 1
			table.insert(o, box(n .. " column", w, hh, w, x, hh / 2, d, if k % 2 == 1 then tone(RK, 0.1) else RK, "Basalt", { r = { 0, 30 * k, 0 } }))
			table.insert(o, pyr(n .. " tip", w, w * 0.8, w, x, hh + w * 0.4, d, RK, "Basalt", { r = { 0, 30 * k, 0 } }))
		end
		local y, d = 8, 0
		for i = 0, 5 do
			local L = h / 7
			local a = if i % 2 == 1 then 22 else -22
			local c = turn({ 0, L / 2, 0 }, { a, 0, 0 })
			table.insert(o, box(n .. " crack", 0.5, L * 1.08, 0.7, -6.2, y + c[2], d + c[3], if i % 2 == 1 then Y else LV, "Neon", { r = { a, 0, 0 } }))
			y += c[2] * 2
			d += c[3] * 2
		end
		table.insert(o, box(n .. " ember tip", 4, 4, 4, 0, h + 6.4, 0, LV, "Neon", { r = { 45, 0, 45 } }))
		return o
	end
	local function lavaPool(r, n)
		local o = { poly(n .. " lava", blob(r, 9, 12), 0.4, 0.2, LV, "Neon") }
		for i = 0, 9 do
			local a = (i / 10) * 6.283
			local w = rr(r, 2.5, 4.5)
			local h = rr(r, 1.2, 2.6)
			local l = rr(r, 3, 5)
			local rx = rr(r, -10, 10)
			local rz = rr(r, -10, 10)
			table.insert(o, box(n .. " rim", w, h, l, math.cos(a) * 9.6, 0.6, math.sin(a) * 12.4, RK, "Basalt", { r = { rx, (-a * 180) / math.pi, rz } }))
		end
		table.insert(o, box(n .. " rock", 3, 1.6, 2.6, 2, 0.6, -2, RK, "Basalt", { r = { 0, 30, 0 } }))
		table.insert(o, box(n .. " rock", 2, 1.2, 2, -3, 0.5, 4, RK, "Basalt", { r = { 0, 60, 0 } }))
		return o
	end
	local function charred(_r, n)
		local o = { box(n .. " trunk", 2.2, 16, 2.2, 0, 8, 0, INK, "Wood", { r = { 0, 0, 4 } }) }
		for i, s in { { 12, 35, 7 }, { 10, -40, 6 }, { 14, 20, 5 }, { 8, -25, 5 } } do
			local y, ang, L = s[1], s[2], s[3]
			local k = i - 1
			local rot = { 0, k * 90, ang }
			local b = { 0, y, 0 }
			local m = add(b, turn({ 0, L / 2, 0 }, rot))
			local t = add(b, turn({ 0, L, 0 }, rot))
			table.insert(o, box(n .. " branch", 1.2, L, 1.2, m[1], m[2], m[3], INK, "Wood", { r = rot }))
			table.insert(o, box(n .. " ember", 1.1, 1.1, 1.1, t[1], t[2], t[3], if k % 2 == 1 then LV else Y, "Neon", { r = { 45, 45, 0 } }))
		end
		return o
	end
	local function brazier(n)
		local o = {}
		for i = 0, 2 do
			local a = (i / 3) * 6.283
			table.insert(o, box(n .. " leg", 0.8, 5, 0.8, math.cos(a) * 1.6, 2.4, math.sin(a) * 1.6, RK, "Basalt", { r = { math.sin(a) * 14, 0, -math.cos(a) * 14 } }))
		end
		table.insert(o, cyl(n .. " bowl", 5.4, 1.8, "y", 0, 5.4, 0, RK, "Basalt"))
		table.insert(o, cyl(n .. " coals", 4.4, 0.4, "y", 0, 6.4, 0, LV, "Neon"))
		append(o, K.flame(n .. " flame", 0, 6.4, 0, 2.6, LV, Y))
		return o
	end
	local function geyser(r, n)
		local o = {}
		for i = 0, 6 do
			local a = (i / 7) * 6.283
			local h = rr(r, 2, 4)
			local rx = rr(r, -15, 15)
			local rz = rr(r, -15, 15)
			table.insert(o, box(n .. " vent", 3, h, 3, math.cos(a) * 3.4, 1.2, math.sin(a) * 3.4, RK, "Basalt", { r = { rx, (-a * 180) / math.pi, rz } }))
		end
		table.insert(o, cyl(n .. " column", 2.8, 30, "y", 0, 15, 0, LV, "Neon"))
		table.insert(o, ball(n .. " splash", 5, 0, 30, 0, Y, "Neon"))
		for _ = 0, 5 do
			local a = r() * 6.283
			local y = rr(r, 22, 30)
			table.insert(o, ball(n .. " drop", 1.4, math.cos(a) * 4, y, math.sin(a) * 4, LV, "Neon"))
		end
		return o
	end
	local function lavaCracks(r, n)
		local o = {}
		for _, z0 in { 12, 46, 80 } do
			local y, d = 1, z0
			for i = 0, 5 do
				local L = rr(r, 4, 7)
				local a = rr(r, -40, 40)
				local c = turn({ 0, L / 2, 0 }, { a, 0, 0 })
				table.insert(o, box(n, 0.4, L, 0.9, -0.15, y + c[2], d + c[3], LV, "Neon", { r = { a, 0, 0 } }))
				if i % 2 == 1 then
					local b = rr(r, 50, 80) * (if a > 0 then -1 else 1)
					local cb = turn({ 0, 2, 0 }, { b, 0, 0 })
					table.insert(o, box(n, 0.4, 4, 0.7, -0.15, y + c[2] * 2 + cb[2], d + c[3] * 2 + cb[3], Y, "Neon", { r = { b, 0, 0 } }))
				end
				y += c[2] * 2
				d += c[3] * 2
			end
		end
		return o
	end
	local function volcano(r, n)
		local o = {}
		local y = 0
		for i, s in { { 160, 60 }, { 104, 50 }, { 60, 36 } } do
			local w, h = s[1], s[2]
			local k = i - 1
			table.insert(o, box(n .. " step", w, h, w, 0, y + h / 2, 0, if k % 2 == 1 then tone(RK, 0.1) else RK, "Basalt", { r = { 0, k * 12, 0 } }))
			y += h
		end
		table.insert(o, box(n .. " crater", 34, 2, 34, 0, 146.5, 0, LV, "Neon"))
		for i, s in { { -30, 120, 6 }, { -52, 85, 8 }, { -80, 30, 9 } } do
			local x, yy, w = s[1], s[2], s[3]
			table.insert(o, box(n .. " lava flow", 2.4, if yy < 60 then 60 elseif yy < 110 then 50 else 36, w, x - 0.6 * i, yy, rr(r, -10, 10), LV, "Neon"))
		end
		return o
	end
	local Z5 = {
		id = 5,
		name = "Lava Volcano",
		from = 2500,
		to = 4000,
		floor = { n = "Basalt floor", c = tone(RK, 0.1), m = "Slate", w = 136, th = 2 },
		lane = { c = LV, m = "CrackedLava" },
		rail = { c = INK, m = "Slate" },
		tiers = {
			{ n = "Basalt wall", c = tone(RK, 0.14), m = "Basalt", y0 = 0, y1 = 32, inset = 0, thick = 8, u = "basalt" },
			{ n = "Lava ledge", c = LV, m = "Neon", y0 = 32, y1 = 32.6, inset = 0.4, thick = 3.6 },
			{ n = "Upper terrace", c = tone(RK, 0.14), m = "Basalt", y0 = 32, y1 = 52, inset = 4, thick = 6, u = "basalt" },
			{ n = "Rock cap", c = tone(RK, 0.08), m = "Slate", y0 = 52, y1 = 54, inset = 4, thick = 6, over = 0.5 },
			{ n = "Lava crest", c = LV, m = "Neon", y0 = 54, y1 = 54.8, inset = 6, thick = 2 },
		},
		strips = {},
		outside = { ground = { c = RK, m = "CrackedLava", y = -2, from = 68 }, spires = { c = RK, glow = LV } },
		arch = { pillar = RK, pillarM = "Basalt", beam = RK, beamM = "Slate", strip = LV, stripM = "Neon" },
		props = {
			{ k = "tower", n = "Basalt spire", parts = spire(rng(51), "Spire", 74), pl = { { x = 66, d = 30 }, { x = -66, d = 80 } } },
			{ k = "wall", n = "Lava cracks", parts = lavaCracks(rng(52), "Crack"), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "wall", n = "Lava fall", parts = waterfall(rng(53), "Lava fall", 32, LV, "Neon"), pl = { { x = -60, d = 52, alt = true } } },
			{ k = "verge", n = "Lava pool", parts = lavaPool(rng(54), "Lava pool"), pl = { { x = 36, d = 58, alt = true } } },
			{
				k = "verge",
				n = "Obsidian crystals",
				parts = (function()
					local o = K.crystals(rng(55), "Obsidian", 0, 0, 6, 13, 2.6, { INK, tone(INK, 0.18) }, "Glass")
					table.insert(o, box("Obsidian vein", 0.5, 0.2, 9, 3, 0.1, 0, LV, "Neon", { r = { 0, 30, 0 } }))
					table.insert(o, box("Obsidian vein", 0.5, 0.2, 7, -3, 0.1, 2, Y, "Neon", { r = { 0, -40, 0 } }))
					return o
				end)(),
				pl = { { x = -30, d = 22, alt = true } },
			},
			{ k = "verge", n = "Charred tree", parts = charred(rng(56), "Charred tree"), pl = { { x = 50, d = 10 }, { x = -48, d = 64 } } },
			{ k = "verge", n = "Fire brazier", parts = brazier("Brazier"), pl = { { x = 24, d = 44 }, { x = -24, d = 94 } } },
			{ k = "verge", n = "Lava geyser", parts = geyser(rng(57), "Geyser"), pl = { { x = 46, d = 86, alt = true } } },
			{ k = "verge", n = "Magma boulders", parts = K.rocks(rng(58), "Magma", 0, 0, 3, 5, RK, "CrackedLava"), pl = { { x = 28, d = 76 }, { x = -40, d = 40 } } },
		},
		once = { { n = "Volcano", parts = volcano(rng(59), "Volcano"), pos = { { x = 240, d = 500 }, { x = -240, d = 1000 } } } },
		fx = {
			particles = {
				{ kind = "Embers", cols = { LV, Y }, size = { 0.3, 0.7 }, rate = 3, life = 3, speed = 4, dir = "up", em = { { x = 66, y = 80, d = 30 }, { x = -66, y = 80, d = 80 }, { x = 24, y = 9, d = 44 }, { x = -24, y = 9, d = 94 }, { x = 46, y = 30, d = 86, alt = true } } },
				{ kind = "Smoke", cols = { C.SMOKE1, C.SMOKE2 }, size = { 1.6, 2.6 }, rate = 1, life = 4, speed = 3, dir = "up", em = { { x = -54, y = 2, d = 52, alt = true }, { x = 46, y = 32, d = 86, alt = true } } },
			},
			lights = { { kind = "PointLight", c = LV, where = "nameArch", range = 40, brightness = 2 } },
			beams = {},
		},
	}
	return { Z3, Z4, Z5 }
end
