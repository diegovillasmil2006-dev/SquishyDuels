--!strict
-- HighwayKit.Zones12: zones 1-2 of Claude Design's highway kit v2 (kit-z12.js, ported 1:1). Called with the Core
-- helpers and the colour table C (hex strings from Art/Palette, HighwayKit/init). Asset parts are in the asset frame
-- (+x outward); placement x is signed (- = left side, mirrored). See HighwayKit/init for the zone fields.

return function(K: any, C: any): { any }
	local W, INK = C.W, C.K
	local PK, LN, GR, Y, AQ, LV = C.PK, C.LN, C.GR, C.Y, C.AQ, C.LV
	local BR, SB, CR, IC = C.BR, C.SB, C.CR, C.IC
	local SP = "SmoothPlastic"
	local tone, rng, rr, box, ball, cyl, wedge, pyr, poly, blob, append =
		K.tone, K.rng, K.rr, K.box, K.ball, K.cyl, K.wedge, K.pyr, K.poly, K.blob, K.append

	local function lollipop(n, s, c1, c2)
		local o = { cyl(n .. " stick", 1.4 * s, 16 * s, "y", 0, 8 * s, 0, W, SP) }
		for i, spec in { { 13, c1 }, { 10.4, c2 }, { 7.8, c1 }, { 5.2, c2 }, { 2.6, c1 } } do
			table.insert(o, cyl(n .. " swirl", spec[1] * s, (1.4 + (i - 1) * 0.25) * s, "z", 0, 21 * s, 0, spec[2], SP))
		end
		table.insert(o, ball(n .. " knot", 1.8 * s, 0, 15.6 * s, 0, c1, SP))
		table.insert(o, box(n .. " ribbon", 3 * s, 0.9 * s, 0.5 * s, -1.4 * s, 15.2 * s, -0.4 * s, c1, SP, { r = { 0, 0, -30 } }))
		table.insert(o, box(n .. " ribbon", 3 * s, 0.9 * s, 0.5 * s, 1.4 * s, 15.2 * s, -0.4 * s, c1, SP, { r = { 0, 0, 30 } }))
		return o
	end
	local function cane(n, h)
		local o = {}
		local i = 0
		while i * 1.6 < h do
			table.insert(o, cyl(n, 1.6, 1.7, "y", 0, 0.8 + i * 1.6, 0, if i % 2 == 1 then W else PK, SP))
			i += 1
		end
		local R = 2.4
		for k = 0, 4 do
			local t = 162 - k * 36
			local q = math.rad(t)
			table.insert(o, cyl(n, 1.6, 1.8, "y", R + R * math.cos(q), h + R * math.sin(q), 0, if k % 2 == 1 then PK else W, SP, { r = { 0, 0, t } }))
		end
		table.insert(o, cyl(n, 1.6, 1.7, "y", 2 * R, h - 0.8, 0, W, SP))
		return o
	end
	local function gumdrops(r, n)
		local o = K.canopy(r, n .. " bush", 0, 2.8, 0, 5.6, { GR, tone(GR, -0.16) }, "LeafyGrass", 5)
		table.insert(o, ball(n .. " gumdrop", 4.2, -3.4, 1.6, -2.4, PK, "Sand"))
		table.insert(o, ball(n .. " gumdrop", 3.4, 2.8, 1.3, -3.2, W, "Sand"))
		table.insert(o, ball(n .. " gumdrop", 3, -0.6, 1.1, -4.6, Y, "Sand"))
		return o
	end
	local function shrooms(r, n)
		local o = {}
		for _, spec in { { 0, 0, 7, 1 }, { 4.6, 2.6, 4.6, 0.7 }, { -3.8, 3.2, 3.6, 0.55 } } do
			local x, d, cap, k = spec[1], spec[2], spec[3], spec[4]
			local h = 7 * k
			table.insert(o, cyl(n .. " stem", 2.3 * k, h, "y", x, h / 2, d, W, SP))
			table.insert(o, cyl(n .. " cap", cap, 1.6 * k, "y", x, h + 0.6 * k, d, PK, SP))
			table.insert(o, cyl(n .. " cap", cap * 0.72, 1.4 * k, "y", x, h + 1.9 * k, d, PK, SP))
			table.insert(o, cyl(n .. " cap", cap * 0.4, 1 * k, "y", x, h + 2.9 * k, d, PK, SP))
			for i = 0, 5 do
				local a = i * 1.05 + r()
				table.insert(o, box(n .. " dot", 0.9 * k, 0.3, 0.9 * k, x + math.cos(a) * cap * 0.43, h + 1.45 * k, d + math.sin(a) * cap * 0.43, W, SP))
			end
		end
		return o
	end
	local function pond(r, n)
		local o = { poly(n .. " water", blob(r, 8, 11), 0.3, 0.16, AQ, "Glass") }
		for _, spec in { { -3, -4, 3.8 }, { 2.6, 3, 3.2 }, { 4, -4, 2.4 }, { -2, 5, 2.8 } } do
			table.insert(o, cyl(n .. " lily pad", spec[3], 0.25, "y", spec[1], 0.42, spec[2], GR, "Plastic"))
		end
		for _, off in { { 0.7, 0 }, { -0.7, 0 }, { 0, 0.7 }, { 0, -0.7 } } do
			table.insert(o, box(n .. " bloom", 0.9, 0.5, 0.9, -3 + off[1], 0.8, -4 + off[2], PK, "Plastic"))
		end
		table.insert(o, box(n .. " bloom", 0.6, 0.7, 0.6, -3, 0.9, -4, Y, "Plastic"))
		return o
	end

	local Z1 = {
		id = 1,
		name = "Candy Meadow",
		from = 0,
		to = 300,
		floor = { n = "Meadow floor", c = GR, m = "Grass", w = 140, th = 2, checker = 10 },
		lane = { c = LN, m = "Pavement" },
		rail = { c = W, m = SP },
		tiers = {
			{ n = "Sugar bank", c = PK, m = "Sand", y0 = 0, y1 = 12, inset = 0, thick = 6, slope = 8, u = "bank" },
			{ n = "Frosting cap", c = W, m = SP, y0 = 12, y1 = 13.5, inset = 7, thick = 8 },
		},
		strips = {},
		once = {},
		outside = {
			ground = { c = GR, m = "Grass", y = 12, from = 74 },
			hills = { c = tone(GR, -0.08), m = "Grass", every = 70, size = 60 },
		},
		arch = nil,
		props = {
			{ k = "wall", n = "Frosting drips", parts = K.drips(rng(11), "Drip", 7, 12.2, 100, W, SP), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "verge", n = "Lollipop tree", parts = lollipop("Lollipop", 1, PK, W), pl = { { x = 34, d = 18 }, { x = -40, d = 66, c = { ["Lollipop swirl"] = Y } } } },
			{ k = "verge", n = "Candy cane", parts = cane("Cane", 13), pl = { { x = 26, d = 52 }, { x = -27, d = 10 } } },
			{ k = "verge", n = "Gumdrop bush", parts = gumdrops(rng(12), "Gumdrop"), pl = { { x = 50, d = 36 }, { x = -46, d = 88 } } },
			{ k = "verge", n = "Flower patch", parts = K.flowers(rng(13), "Flower", 0, 0, 7, 4.5, { PK, W, LN }, Y, tone(GR, -0.3)), pl = { { x = 25, d = 80 }, { x = -25, d = 40 }, { x = 44, d = 94 } } },
			{ k = "verge", n = "Mushroom ring", parts = shrooms(rng(14), "Mushroom"), pl = { { x = -52, d = 22 } } },
			{ k = "verge", n = "Rock candy", parts = K.crystals(rng(15), "Rock candy", 0, 0, 7, 9, 1.9, { PK, W, LN }, "Ice"), pl = { { x = 54, d = 70 } } },
			{ k = "verge", n = "Picket fence", parts = K.fence("Fence", 0, 0, 30, W, "Wood"), pl = { { x = 57, d = 2 }, { x = -57, d = 52 } } },
			{ k = "floor", n = "Candy pond", parts = pond(rng(16), "Pond"), pl = { { x = 38, d = 60, alt = true } } },
			{ k = "outside", n = "Cotton-candy tree", parts = K.tree(rng(17), "Cotton tree", 0, 0, 14, 13, W, "Wood", { PK, tone(PK, 0.4), W }, "LeafyGrass"), pl = { { x = 92, d = 30, y = 12, alt = true }, { x = -104, d = 80, y = 12, alt = true }, { x = 128, d = 74, y = 12 } } },
			{ k = "outside", n = "Giant lollipop", parts = lollipop("Giant lollipop", 2.4, PK, W), pl = { { x = 140, d = 50, y = 12, alt = true } } },
		},
		fx = { particles = {}, lights = {}, beams = {} },
	}

	local function house(_r, n)
		local w, h, l = 14, 13, 15
		local o = { box(n .. " walls", w, h, l, 0, h / 2, 0, BR, "Brick") }
		table.insert(o, wedge(n .. " roof", 8, 7, l + 2, -4, h + 3.5, 0, CR, "WoodPlanks"))
		table.insert(o, wedge(n .. " roof", 8, 7, l + 2, 4, h + 3.5, 0, CR, "WoodPlanks", { r = { 0, 180, 0 } }))
		table.insert(o, box(n .. " icing", 1.3, 1.3, l + 2.6, 0, h + 7, 0, W, SP))
		table.insert(o, box(n .. " icing", 10.8, 0.9, 0.9, -4, h + 3.5, -(l / 2 + 1.1), W, SP, { r = { 0, 0, 41 } }))
		table.insert(o, box(n .. " icing", 10.8, 0.9, 0.9, 4, h + 3.5, -(l / 2 + 1.1), W, SP, { r = { 0, 0, -41 } }))
		local z = -7.5
		while z <= 7.5 do
			for _, sx in { -1, 1 } do
				table.insert(o, ball(n .. " icing", 1.3, sx * 8.2, h - 0.2, z, W, SP))
			end
			z += 2.5
		end
		table.insert(o, box(n .. " window", 3, 3.4, 0.3, -4, 9, -l / 2 - 0.15, IC, "Glass"))
		table.insert(o, box(n .. " window", 3, 3.4, 0.3, 4, 9, -l / 2 - 0.15, IC, "Glass"))
		table.insert(o, box(n .. " window", 0.3, 3.4, 3, -w / 2 - 0.15, 8.4, -3.5, IC, "Glass"))
		table.insert(o, box(n .. " window", 0.3, 3.4, 3, -w / 2 - 0.15, 8.4, 3.5, IC, "Glass"))
		table.insert(o, box(n .. " flower box", 3.6, 0.9, 0.9, -4, 6.9, -l / 2 - 0.5, PK, SP))
		table.insert(o, box(n .. " flower box", 3.6, 0.9, 0.9, 4, 6.9, -l / 2 - 0.5, PK, SP))
		table.insert(o, box(n .. " door", 3.6, 6.4, 0.4, 0, 3.2, -l / 2 - 0.2, CR, "WoodPlanks"))
		table.insert(o, ball(n .. " knob", 0.6, 1.1, 3.2, -l / 2 - 0.5, Y, SP))
		table.insert(o, box(n .. " chimney", 2.6, 6, 2.6, 3.4, h + 6, 3, tone(BR, -0.15), "Brick"))
		for i = 0, 4 do
			table.insert(o, ball(n .. " button", 1, -2.2 + i * 1.1, 6.9, -l / 2 - 0.25, if i % 2 == 1 then W else PK, SP))
		end
		return o
	end
	local function cupcake(r, n, s, wrap, frost)
		local o = {
			cyl(n .. " wrapper", 7 * s, 5 * s, "y", 0, 2.5 * s, 0, wrap, "Fabric"),
			cyl(n .. " rim", 7.6 * s, 0.8 * s, "y", 0, 5.2 * s, 0, wrap, "Fabric"),
			ball(n .. " frosting", 7.6 * s, 0, 6.6 * s, 0, frost, SP),
			ball(n .. " frosting", 5.8 * s, 0, 9.2 * s, 0, frost, SP),
			ball(n .. " frosting", 3.8 * s, 0, 11.2 * s, 0, frost, SP),
			ball(n .. " cherry", 2 * s, 0, 13.2 * s, 0, LV, SP),
		}
		local sprinkles = { Y, IC, GR, PK, W }
		for i = 0, 11 do
			local a = r() * 6.283
			local e = rr(r, 0.2, 1.1)
			local ry = r() * 180
			table.insert(o, box(n .. " sprinkle", 0.3 * s, 0.3 * s, 1 * s, math.cos(a) * math.cos(e) * 3.8 * s, 6.6 * s + math.sin(e) * 3.8 * s, math.sin(a) * math.cos(e) * 3.8 * s, sprinkles[i % 5 + 1], SP, { r = { 0, ry, 0 } }))
		end
		return o
	end
	local function donut(r, n)
		local o = {}
		local R, cy = 4.2, 6
		for i = 0, 13 do
			local a = (i / 14) * 6.283
			table.insert(o, ball(n .. " dough", 3.6, R * math.cos(a), cy + R * math.sin(a), 0, BR, "Sand"))
		end
		for i = 0, 8 do
			local a = (i / 8) * math.pi * 1.1 - 0.05
			table.insert(o, ball(n .. " icing", 3.7, R * math.cos(a), cy + R * math.sin(a), -0.5, PK, SP))
		end
		local sprinkles = { Y, W, IC, GR }
		for i = 0, 9 do
			local a = rr(r, 0.1, 3.1)
			local q = R + rr(r, -1, 1)
			local rz = r() * 180
			table.insert(o, box(n .. " sprinkle", 0.3, 0.3, 1, q * math.cos(a), cy + q * math.sin(a), -2.3, sprinkles[i % 4 + 1], SP, { r = { 0, 0, rz } }))
		end
		return o
	end
	local function loaves(_r, n)
		local o = {}
		for _, spec in { { 0, 0, 0, 0 }, { 5.2, 0, 0.6, 10 }, { 2.6, 2.6, 0.2, -6 } } do
			local x, y, d, ry = spec[1], spec[2], spec[3], spec[4]
			table.insert(o, box(n, 4.6, 2.4, 7, x, y + 1.2, d, BR, "Sand", { r = { 0, ry, 0 } }))
			table.insert(o, cyl(n .. " crust", 4.6, 7, "z", x, y + 2.3, d, tone(BR, -0.1), "Sand", { r = { 0, ry, 0 } }))
		end
		return o
	end
	local function stall(r, n)
		local o = {
			box(n .. " counter", 6, 4, 11, 0, 2, 0, CR, "WoodPlanks"),
			box(n .. " top", 6.6, 0.6, 11.6, 0, 4.3, 0, tone(CR, 0.18), "WoodPlanks"),
		}
		for _, spec in { { -2.8, -5.4 }, { 2.8, -5.4 }, { -2.8, 5.4 }, { 2.8, 5.4 } } do
			table.insert(o, box(n .. " post", 0.7, 10, 0.7, spec[1], 5, spec[2], CR, "WoodPlanks"))
		end
		for i = 0, 5 do
			table.insert(o, box(n .. " awning", 8, 0.5, 2, -0.6, 10.2, -5 + i * 2, if i % 2 == 1 then W else PK, "Fabric", { r = { 0, 0, 14 } }))
		end
		for i = 0, 5 do
			table.insert(o, box(n .. " valance", 0.3, 1.4, 1.9, -4.5, 8.7, -5 + i * 2, if i % 2 == 1 then PK else W, "Fabric"))
		end
		for i = 0, 3 do
			table.insert(o, ball(n .. " bun", 2.2, rr(r, -1.5, 1.5), 5.4, -3.6 + i * 2.4, BR, "Sand"))
		end
		return o
	end
	local function barrels(r, n)
		local o = {}
		for _, spec in { { 0, 0 }, { 3.8, 1.2 } } do
			local x, d = spec[1], spec[2]
			table.insert(o, cyl(n .. " barrel", 3.6, 4.4, "y", x, 2.2, d, CR, "WoodPlanks"))
			table.insert(o, cyl(n .. " hoop", 3.8, 0.4, "y", x, 1, d, tone(CR, -0.4), "WoodPlanks"))
			table.insert(o, cyl(n .. " hoop", 3.8, 0.4, "y", x, 3.4, d, tone(CR, -0.4), "WoodPlanks"))
		end
		for _, spec in { { 1, 4.4, 0, 3.2 }, { 4.6, 5, 0, 2.6 }, { 1.2, 4.4, 3.2, 2.4 } } do
			local x, d, y, s = spec[1], spec[2], spec[3], spec[4]
			table.insert(o, box(n .. " crate", s, s, s, x, y + s / 2, d, BR, "WoodPlanks", { r = { 0, rr(r, 0, 40), 0 } }))
		end
		return o
	end
	local function lamp(n, h, pc, pm, gc, gm)
		return {
			box(n .. " base", 1.8, 1, 1.8, 0, 0.5, 0, pc, pm),
			cyl(n .. " post", 0.8, h, "y", 0, h / 2, 0, pc, pm),
			box(n .. " arm", 2.6, 0.4, 0.4, -1.1, h - 0.4, 0, pc, pm),
			box(n .. " lantern", 1.8, 2.4, 1.8, -2.2, h - 2, 0, gc, gm),
			pyr(n .. " cap", 2.2, 1.2, 2.2, -2.2, h - 0.2, 0, pc, pm),
		}
	end
	local function timber(r, n, h)
		local o = {}
		local z, k = 6.25, 0
		while z < 100 do
			table.insert(o, box(n .. " post", 1, h, 1.4, -0.5, h / 2, z, CR, "WoodPlanks"))
			if z < 93 then
				local rx = (if k % 2 == 1 then 1 else -1) * (math.atan2(h * 0.42, 12.5) * 180) / math.pi
				table.insert(o, box(n .. " brace", 0.8, 0.9, math.sqrt(12.5 * 12.5 + (h * 0.42) ^ 2), -0.45, h * 0.27, z + 6.25, CR, "WoodPlanks", { r = { rx, 0, 0 } }))
			end
			if k % 2 == 1 and z < 93 then
				table.insert(o, box(n .. " window", 0.3, 5, 6, -0.3, h * 0.72, z + 6.25, IC, "Glass"))
				table.insert(o, box(n .. " sill", 1.2, 0.6, 7, -0.6, h * 0.72 - 2.8, z + 6.25, W, SP))
			end
			z += 12.5
			k += 1
		end
		table.insert(o, box(n .. " beam", 1, 1.2, 100, -0.5, h * 0.52, 50, CR, "WoodPlanks"))
		append(o, K.drips(r, n .. " icing", -0.7, h + 0.1, 100, W, SP, 3))
		return o
	end
	local function windmill(_r, n)
		local o = {
			box(n .. " tower", 14, 14, 14, 0, 7, 0, BR, "Brick"),
			box(n .. " tower", 11, 12, 11, 0, 20, 0, BR, "Brick"),
			box(n .. " tower", 8.4, 10, 8.4, 0, 31, 0, BR, "Brick"),
			wedge(n .. " roof", 5, 6, 10, -2.5, 39, 0, CR, "WoodPlanks"),
			wedge(n .. " roof", 5, 6, 10, 2.5, 39, 0, CR, "WoodPlanks", { r = { 0, 180, 0 } }),
			cyl(n .. " hub", 3, 3, "z", 0, 36, -5.4, CR, "WoodPlanks"),
			box(n .. " door", 4, 6, 0.4, 0, 3, -7.2, CR, "WoodPlanks"),
		}
		for k = 0, 3 do
			local a = 45 + k * 90
			local m = K.turn({ 0, 9, 0 }, { 0, 0, a })
			local s = K.turn({ 2.6, 10, 0 }, { 0, 0, a })
			table.insert(o, box(n .. " arm", 1, 18, 0.6, m[1], 36 + m[2], -6.6, CR, "WoodPlanks", { r = { 0, 0, a } }))
			table.insert(o, box(n .. " sail", 4.2, 13, 0.3, s[1], 36 + s[2], -6.3, W, "Fabric", { r = { 0, 0, a } }))
		end
		return o
	end
	local function rooftops(_r, n)
		local o = {}
		for i, spec in { { 0, 0, 26, 16 }, { -2, 20, 32, 14 }, { 6, 40, 24, 18 } } do
			local x, d, h, w = spec[1], spec[2], spec[3], spec[4]
			table.insert(o, box(n .. " house", w, h, w, x, h / 2, d, if (i - 1) % 2 == 1 then BR else tone(BR, 0.2), "Brick"))
			table.insert(o, wedge(n .. " roof", w / 2 + 1, 6, w + 1, x - (w / 2 + 1) / 2, h + 3, d, CR, "WoodPlanks"))
			table.insert(o, wedge(n .. " roof", w / 2 + 1, 6, w + 1, x + (w / 2 + 1) / 2, h + 3, d, CR, "WoodPlanks", { r = { 0, 180, 0 } }))
			table.insert(o, box(n .. " chimney", 2.4, 6, 2.4, x + 3, h + 5, d + 2, tone(BR, -0.15), "Brick"))
		end
		return o
	end
	local function cake(r, n)
		local o = {}
		local y = 0
		for _, spec in { { 22, 10, PK }, { 16, 9, W }, { 10, 8, PK } } do
			local dia, h, c = spec[1], spec[2], spec[3]
			local trim = if c == PK then W else PK
			table.insert(o, cyl(n .. " tier", dia, h, "y", 0, y + h / 2, 0, c, SP))
			table.insert(o, cyl(n .. " icing", dia + 1, 1, "y", 0, y + h, 0, trim, SP))
			for i = 0, 9 do
				local a = (i / 10) * 6.283
				local L = rr(r, 1.5, 4)
				table.insert(o, box(n .. " drip", 1.4, L, 1.4, math.cos(a) * (dia / 2 + 0.2), y + h - L / 2, math.sin(a) * (dia / 2 + 0.2), trim, SP))
			end
			y += h
		end
		for i = 0, 2 do
			local a = i * 2.1
			table.insert(o, ball(n .. " cherry", 2.4, math.cos(a) * 3, y + 1.2, math.sin(a) * 3, LV, SP))
			table.insert(o, cyl(n .. " candle", 0.8, 4, "y", math.cos(a + 1) * 2.5, y + 2, math.sin(a + 1) * 2.5, Y, SP))
		end
		return o
	end

	local Z2 = {
		id = 2,
		name = "Bakery Town",
		from = 300,
		to = 800,
		floor = { n = "Shortbread floor", c = SB, m = "Sand", w = 136, th = 2, checker = 10 },
		lane = { c = CR, m = "Cobblestone" },
		rail = { c = W, m = SP },
		tiers = {
			{ n = "Brick wall", c = BR, m = "Brick", y0 = 0, y1 = 20, inset = 0, thick = 6 },
			{ n = "Icing cap", c = W, m = SP, y0 = 20, y1 = 22, inset = 0, thick = 6, over = 1 },
		},
		strips = {},
		once = {},
		outside = { ground = { c = SB, m = "Ground", y = 0, from = 66 } },
		arch = { pillar = BR, pillarM = "Brick", beam = CR, beamM = "WoodPlanks", strip = W, stripM = SP },
		props = {
			{ k = "wall", n = "Timber frame", parts = timber(rng(21), "Timber", 20), pl = { { x = 60, d = 0 }, { x = -60, d = 0 } } },
			{ k = "verge", n = "Gingerbread house", parts = house(rng(22), "House"), pl = { { x = 47, d = 30, alt = true } } },
			{ k = "verge", n = "Cupcake", parts = cupcake(rng(23), "Cupcake", 1, PK, W), pl = { { x = 28, d = 62 }, { x = -32, d = 14, c = { ["Cupcake wrapper"] = IC, ["Cupcake rim"] = IC } } } },
			{ k = "verge", n = "Donut", parts = donut(rng(24), "Donut"), pl = { { x = 38, d = 86, alt = true } } },
			{ k = "verge", n = "Bread loaves", parts = loaves(rng(25), "Loaf"), pl = { { x = -50, d = 52 } } },
			{ k = "verge", n = "Market stall", parts = stall(rng(26), "Stall"), pl = { { x = 51, d = 72, alt = true } } },
			{ k = "verge", n = "Barrels and crates", parts = barrels(rng(27), "Barrel"), pl = { { x = -24, d = 72 }, { x = 26, d = 6 } } },
			{ k = "verge", n = "Lamp post", parts = lamp("Lamp", 12, INK, "Metal", Y, "Glass"), pl = { { x = 22, d = 40 }, { x = -22, d = 92 } } },
			{ k = "outside", n = "Windmill", parts = windmill(rng(28), "Windmill"), pl = { { x = 108, d = 50, every = 2, alt = true } } },
			{ k = "outside", n = "Rooftops", parts = rooftops(rng(29), "Rooftops"), pl = { { x = 84, d = 10, alt = true } } },
			{ k = "outside", n = "Cake tower", parts = cake(rng(30), "Cake"), pl = { { x = -96, d = 74, alt = true } } },
		},
		fx = { particles = {}, lights = {}, beams = {} },
	}
	return { Z1, Z2 }
end
