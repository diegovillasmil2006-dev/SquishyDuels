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
			T3 = { first = { 0.362993, 0.009462 }, posts = 26, bunting = 2, sparkle = { 104.849491, 25.874601 }, splat = { 3.485895, 133.490006, 69.119619 }, sky = { 259.787246, 34.527984, 10.366445, 0.00998 }, amb = { 121.596926, 18.377737, -0.469589 } },
			F2 = { first = { 0.598853, 0.791054 }, posts = 40, bunting = 0, sparkle = { 10.919978, 33.332849 }, splat = { 2.952883, 171.308086, 25.898703 }, sky = { 381.145459, 11.333607, 17.825358, 0.163726 }, amb = { 17.369277, 181.507565, -1.6559 } },
			D1 = { first = { 0.00882, 0.706941 }, posts = 16, bunting = 2, sparkle = { 58.46523, 7.697615 }, splat = { 1.599376, 71.917176, 68.022805 }, sky = { 186.44586, -26.297431, -22.104437, -0.008698 }, amb = { 100.552967, 20.876671, -1.757112 } },
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
