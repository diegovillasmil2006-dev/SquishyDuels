--!strict
-- MapLayout_Test: Shared.Maps.MapData (Diego's 11 sky maps, NEW MAPS FINALS zip) and Shared.Maps.MapLayout (his demos'
-- seeded layout). Pure, Edit mode.
-- Contract: MapLayout gives the numbers his demo's layout(m) gives (values printed by tools/maps/make_mapdata.mjs);
-- the data meets his SUPERPROMPT checks: the spawns each mode needs (TDM and 1v1 one pink + one blue area, FFA 12
-- pads), every element inside the map, every stair's top on a deck.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local MapData = t.requireShared("Maps/MapData")
	local MapLayout = t.requireShared("Maps/MapLayout")
	local expect = t.expect

	t.test("srng and layout match Diego's demo (T3 doodle draws, F2 no bunting, D1)", function()
		local cases = {
			-- his layout(m) on the 1.5x maps (owner 2026-11-01), printed by tools/maps/make_mapdata.mjs
			T3 = { first = { 0.362993, 0.009462 }, posts = 38, bunting = 2, sparkle = { 157.490709, 37.529101 }, splat = { 3.485895, 199.583684, 103.888901 }, sky = { 361.917391, 34.527984, 24.75437, 0.00998 }, amb = { 182.979938, 26.038007, -0.469589 } },
			F2 = { first = { 0.598853, 0.791054 }, posts = 60, bunting = 0, sparkle = { 14.494346, 48.484114 }, splat = { 2.952883, 256.102382, 36.349703 }, sky = { 525.184053, 11.333607, 46.208534, 0.163726 }, amb = { 24.274895, 273.195356, -1.6559 } },
			D1 = { first = { 0.00882, 0.706941 }, posts = 24, bunting = 2, sparkle = { 87.643032, 9.763929 }, splat = { 1.599376, 105.61541, 104.848846 }, sky = { 248.517558, -26.297431, -18.349312, -0.008698 }, amb = { 152.277771, 30.307752, -1.757112 } },
		}
		for id, want in cases do
			local sr = MapLayout.srng(id)
			expect.near(sr(), want.first[1], 1e-5)
			expect.near(sr(), want.first[2], 1e-5)
			local L = MapLayout.build(MapData.maps[id])
			expect.equal(#L.posts, want.posts)
			expect.equal(#L.bulbs, want.posts * 5)
			expect.equal(#L.bunting, want.bunting)
			expect.near(L.sparkles[1].x, want.sparkle[1], 1e-4)
			expect.near(L.sparkles[1].z, want.sparkle[2], 1e-4)
			expect.near(L.splats[4].r, want.splat[1], 1e-4)
			expect.near(L.splats[4].x, want.splat[2], 1e-4)
			expect.near(L.splats[4].z, want.splat[3], 1e-4)
			expect.near(L.sky[14].x, want.sky[1], 1e-4)
			expect.near(L.sky[14].y, want.sky[2], 1e-4)
			expect.near(L.sky[14].z, want.sky[3], 1e-4)
			expect.near(L.sky[14].rs, want.sky[4], 1e-4)
			expect.near(L.amb[46].x, want.amb[1], 1e-4)
			expect.near(L.amb[46].z, want.amb[2], 1e-4)
			expect.near(L.amb[46].ry, want.amb[3], 1e-4)
		end
	end)

	t.test("every map is 1.5x Diego's, floor and heights (owner 2026-11-01: more room to run and jump)", function()
		local C = MapData.constants
		expect.equal(C.SCALE, 1.5)
		expect.equal(MapData.maps.D1.W, 180) -- Pencil Case: his 120 x 76
		expect.equal(MapData.maps.D1.H, 114)
		expect.equal(MapData.maps.F3.W, 405) -- Puzzle Plaza: his 270
		expect.equal(C.DECK_H, 17) -- his 10 x 1.5, + 2 (owner 2026-11-01 "raise them")
		expect.equal(C.DECK_SLAB, 2.4)
		-- under a platform: a tall avatar's 2x3x1 collider (top ~6.3 over the floor) plus a full held jump (~7.4) fits
		expect.truthy(C.DECK_H - C.DECK_SLAB >= 14.5)
		expect.equal(C.WALL_H, 24)
		expect.equal(C.COVER_H, 6)
		expect.equal(C.CAP_H, 2.1)
		local first = MapData.maps.D1.elements[1]
		local route = MapData.maps.D1.botRoutes[1].points[1]
		expect.truthy(first.x % 1.5 == 0 and first.w % 1.5 == 0 and route[1] % 1.5 == 0) -- his whole studs, scaled
	end)

	-- 40: the two Fluff Cycle stairs with no floor to grow into climb 39 degrees to the raised platforms (were 59 max)
	t.test("gentler stairs (owner 2026-11-01): none steeper than 40 degrees, the 1v1 ones lengthened", function()
		local C = MapData.constants
		for _, id in MapData.order do
			for _, e in MapData.maps[id].elements do
				if e.type == "stair" then
					local run = if e.stairUp == "n" or e.stairUp == "s" then e.d else e.w
					local deg = math.deg(math.atan(C.DECK_H / run))
					if deg > 40 then
						error(`{id}: the stair at {e.x},{e.z} climbs {math.floor(deg)} degrees`)
					end
				end
			end
		end
		local function runs(id: string): { number }
			local out = {}
			for _, e in MapData.maps[id].elements do
				if e.type == "stair" then
					table.insert(out, if e.stairUp == "n" or e.stairUp == "s" then e.d else e.w)
				end
			end
			return out
		end
		expect.deepEqual(runs("D3"), { 27, 27 }) -- Lunchbox: his 6 (59 degrees) -> 18, x 1.5
		expect.deepEqual(runs("D1"), { 24, 24 }) -- Pencil Case: his 10 -> 16, his 6 of floor left below
	end)

	t.test("11 maps: 4 Team, 4 Free for All, 3 1v1, each with the spawns its mode needs", function()
		expect.equal(#MapData.order, 11)
		expect.equal(#MapData.ofMode("tdm"), 4)
		expect.equal(#MapData.ofMode("ffa"), 4)
		expect.equal(#MapData.ofMode("duel"), 3)
		for _, id in MapData.order do
			local map = MapData.maps[id]
			local count: { [string]: number } = {}
			for _, e in map.elements do
				count[e.type] = (count[e.type] or 0) + 1
			end
			if map.mode == "ffa" then
				expect.equal(count.spawn, 12)
				expect.equal(count.spawnA, nil)
			else
				expect.equal(count.spawnA, 1)
				expect.equal(count.spawnB, 1)
				expect.equal(count.spawn, nil)
			end
		end
	end)

	t.test("every element lies inside its map and every stair top meets a deck", function()
		local function inside(e: any, px: number, pz: number): boolean
			if e.round then
				local r = e.w / 2
				return (px - (e.x + r)) ^ 2 + (pz - (e.z + r)) ^ 2 <= r * r
			end
			return px >= e.x and px <= e.x + e.w and pz >= e.z and pz <= e.z + e.d
		end
		local STEP = { n = { 0, -1 }, s = { 0, 1 }, e = { 1, 0 }, w = { -1, 0 } }
		for _, id in MapData.order do
			local map = MapData.maps[id]
			for _, e in map.elements do
				expect.truthy(e.x >= 0 and e.z >= 0 and e.x + e.w <= map.W and e.z + e.d <= map.H)
				if e.type == "stair" then
					local dir = STEP[e.stairUp]
					expect.truthy(dir ~= nil)
					local cx, cz = e.x + e.w / 2, e.z + e.d / 2
					-- the point half a stud past the stair's top edge
					local px = cx + dir[1] * (e.w / 2 + 0.5)
					local pz = cz + dir[2] * (e.d / 2 + 0.5)
					local onDeck = false
					for _, other in map.elements do
						if other.type == "deck" and (other.level or 1) == 1 and inside(other, px, pz) then
							onDeck = true
						end
					end
					if not onDeck then
						error(`{id}: the stair at {e.x},{e.z} climbing {e.stairUp} does not reach a deck`)
					end
				end
			end
		end
	end)
end
