--!strict
-- MatchSpawns_Test: unit tests for ServerScriptService.Server.Logic.MatchSpawns (FFA/TDM v1, 2026-10-15, SPEC D12).
-- Contract: spotsPerPad points on each pad's top face, at least edgeStuds inside its edges (a pad too small for the
-- margin puts them on its centre line), each facing the map centre; first placement: TDM the own team's spots in order
-- (round again past the last), FFA round robin over the pads; respawn: TDM a random free spot of the own team (not
-- the last spot while another is free; any spot when all are taken), FFA the pad farthest from the standing enemies,
-- then a free spot on it; a respawn spot in the storm moves to the safe circle (radius - respawnInsetStuds toward the
-- own / chosen pad, on the floor, raised onto geometry by the raycast); placement adds the stand height and faces
-- along the spot. Config tables are passed in (the place's Config may be an older copy).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

return function(t: Context)
	local MatchSpawns = t.requireServer("Logic/MatchSpawns")
	local Config = t.requireShared("Config")
	local expect = t.expect

	-- Config.Match with fixed spawn and storm numbers, so the cases never depend on tuning.
	local CFG = deepCopy(Config.Match)
	CFG.Spawns = { spotsPerPad = { tdm = 6, ffa = 2 }, edgeStuds = 4, occupiedStuds = 4, raycastUpStuds = 40 }
	CFG.Storm.respawnInsetStuds = 6

	local CENTRE = Vector3.new(1000, 0, 0)

	local function pad(x: number, z: number, team: string?): any
		return { cframe = CFrame.new(1000 + x, -1, z), size = Vector3.new(30, 2, 20), team = team }
	end

	local TDM_PADS = { pad(0, -100, "Red"), pad(0, 100, "Blue") }
	local FFA_PADS = { pad(-80, -80), pad(80, -80), pad(80, 80), pad(-80, 80) }

	local function flat(a: Vector3, b: Vector3): number
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	t.test("grid points sit on the pad's top face, at least edgeStuds inside its edges, all different", function()
		local p = pad(0, 0)
		local points = MatchSpawns.gridPoints(p, 6, 4)
		expect.equal(#points, 6)
		for i, point in points do
			local localPoint = p.cframe:PointToObjectSpace(point)
			expect.near(point.Y, 0, 1e-6) -- top face: -1 + 2 / 2
			expect.truthy(math.abs(localPoint.X) <= 15 - 4 + 1e-6)
			expect.truthy(math.abs(localPoint.Z) <= 10 - 4 + 1e-6)
			for j = i + 1, #points do
				expect.truthy(flat(point, points[j]) > 1)
			end
		end
		-- A pad smaller than twice the margin: the points sit on its centre.
		local small = { cframe = CFrame.new(0, 0, 0), size = Vector3.new(6, 1, 6) }
		for _, point in MatchSpawns.gridPoints(small, 2, 4) do
			expect.near(flat(point, Vector3.zero), 0, 1e-6)
		end
	end)

	t.test("build: spotsPerPad spots per pad by mode, each facing the map centre", function()
		local tdm = MatchSpawns.build(TDM_PADS, CENTRE, 0, "tdm", CFG)
		expect.equal(#tdm.spotsOf[1], 6)
		expect.equal(#tdm.spotsOf[2], 6)
		local ffa = MatchSpawns.build(FFA_PADS, CENTRE, 0, "ffa", CFG)
		expect.equal(#ffa.spotsOf[3], 2)
		for _, spot in ffa.spotsOf[3] do
			local toward = Vector3.new(CENTRE.X - spot.position.X, 0, CENTRE.Z - spot.position.Z).Unit
			expect.near(spot.facing:Dot(toward), 1, 1e-6)
			expect.equal(spot.pad, 3)
		end
	end)

	t.test("first placement: TDM fills the own team's spots in order and wraps; FFA spreads round robin", function()
		local tdm = MatchSpawns.build(TDM_PADS, CENTRE, 0, "tdm", CFG)
		local entrants = {}
		for i = 1, 7 do
			table.insert(entrants, { userId = i, team = "Red" })
		end
		table.insert(entrants, { userId = 20, team = "Blue" })
		local spots = MatchSpawns.firstSpots(tdm, entrants)
		for i = 1, 6 do
			expect.equal(spots[i], tdm.spotsOf[1][i])
		end
		expect.equal(spots[7], tdm.spotsOf[1][1]) -- the 7th wraps around
		expect.equal(spots[20], tdm.spotsOf[2][1])

		local ffa = MatchSpawns.build(FFA_PADS, CENTRE, 0, "ffa", CFG)
		local players = {}
		for i = 1, 6 do
			table.insert(players, { userId = i })
		end
		local placed = MatchSpawns.firstSpots(ffa, players)
		for i = 1, 4 do
			expect.equal(placed[i], ffa.spotsOf[i][1])
		end
		expect.equal(placed[5], ffa.spotsOf[1][2])
		expect.equal(placed[6], ffa.spotsOf[2][2])
	end)

	t.test("TDM respawn: a free spot of the own team, not the last one; any own spot when all are taken", function()
		local set = MatchSpawns.build(TDM_PADS, CENTRE, 0, "tdm", CFG)
		local red = set.spotsOf[1]
		local occupied = {}
		for i = 2, 6 do
			table.insert(occupied, red[i].position + Vector3.new(0, 3, 0)) -- a standing player's root over the spot
		end
		for _, r in { 0, 0.5, 0.99 } do
			local spot = MatchSpawns.respawnSpot(set, { team = "Red", enemies = {}, occupied = occupied, r = r }, CFG)
			expect.equal(spot, red[1])
		end
		-- Two free spots: the last one is avoided.
		table.remove(occupied, 1) -- red[2] is free again
		for _, r in { 0, 0.99 } do
			local args = { team = "Red", enemies = {}, occupied = occupied, last = red[1], r = r }
			expect.equal(MatchSpawns.respawnSpot(set, args, CFG), red[2])
		end
		-- Everything taken: still one of the team's own spots.
		local all = {}
		for _, spot in red do
			table.insert(all, spot.position)
		end
		local spot = MatchSpawns.respawnSpot(set, { team = "Red", enemies = {}, occupied = all, r = 0.3 }, CFG)
		expect.equal(spot.pad, 1)
	end)

	t.test("FFA respawn: the pad farthest from the standing enemies, then a free spot on it", function()
		local set = MatchSpawns.build(FFA_PADS, CENTRE, 0, "ffa", CFG)
		-- Enemies around pads 1, 2 and 4: pad 3 (+80, +80) is the farthest.
		local enemies = {
			Vector3.new(1000 - 80, 3, -80),
			Vector3.new(1000 + 80, 3, -80),
			Vector3.new(1000 - 80, 3, 80),
		}
		for _, r in { 0, 0.5, 0.99 } do
			local spot = MatchSpawns.respawnSpot(set, { enemies = enemies, occupied = enemies, r = r }, CFG)
			expect.equal(spot.pad, 3)
		end
		-- One spot of pad 3 taken: the other one.
		local taken = set.spotsOf[3][1].position
		local occupied = table.clone(enemies)
		table.insert(occupied, taken)
		local spot = MatchSpawns.respawnSpot(set, { enemies = enemies, occupied = occupied, r = 0 }, CFG)
		expect.equal(spot, set.spotsOf[3][2])
		-- No enemy at all: every pad ties and r picks one.
		local first = MatchSpawns.respawnSpot(set, { enemies = {}, occupied = {}, r = 0 }, CFG)
		local last = MatchSpawns.respawnSpot(set, { enemies = {}, occupied = {}, r = 0.99 }, CFG)
		expect.equal(first.pad, 1)
		expect.equal(last.pad, 4)
	end)

	t.test("a respawn in the storm moves onto the safe circle toward the pad, raised onto geometry", function()
		local set = MatchSpawns.build(TDM_PADS, CENTRE, 0, "tdm", CFG)
		local storm = { centre = Vector3.new(CENTRE.X, 0, CENTRE.Z), radius = 30 } -- the Red pad (z -100) is outside
		local rays = {}
		local function raycast(origin: Vector3, direction: Vector3): Vector3?
			table.insert(rays, { origin = origin, direction = direction })
			return Vector3.new(origin.X, 5, origin.Z) -- a crate top 5 studs up
		end
		local spot = MatchSpawns.respawnSpot(
			set,
			{ team = "Red", enemies = {}, occupied = {}, r = 0, storm = storm, raycast = raycast },
			CFG
		)
		expect.equal(spot.pad, 0)
		expect.near(flat(spot.position, storm.centre), 30 - 6, 1e-4)
		expect.truthy(spot.position.Z < 0) -- toward the Red pad
		expect.near(spot.position.Y, 5, 1e-6)
		expect.equal(#rays, 1)
		expect.near(rays[1].origin.Y, 40, 1e-6)
		expect.truthy(rays[1].direction.Y < -40)
		expect.near(spot.facing.Z, 1, 1e-6) -- facing the centre
		-- No hit: on the floor. Inside the circle: the pad spot itself.
		local floorSpot = MatchSpawns.safeSpot(set, Vector3.new(CENTRE.X, 0, -100), storm, function(): Vector3?
			return nil
		end, CFG)
		expect.near(floorSpot.position.Y, 0, 1e-6)
		local wide = { centre = storm.centre, radius = 500 }
		local inside =
			MatchSpawns.respawnSpot(set, { team = "Red", enemies = {}, occupied = {}, r = 0, storm = wide }, CFG)
		expect.equal(inside, set.spotsOf[1][1])
	end)

	t.test("placement stands the character on the spot, facing along it", function()
		local spot = { position = Vector3.new(10, 2, 20), facing = Vector3.new(1, 0, 0), pad = 1 }
		local cf = MatchSpawns.placement(spot, 3)
		expect.near((cf.Position - Vector3.new(10, 5, 20)).Magnitude, 0, 1e-6)
		expect.near(cf.LookVector:Dot(Vector3.new(1, 0, 0)), 1, 1e-6)
	end)

	t.test("a map with no pad for a team, or no pad at all, still gives a spot", function()
		local onlyRed = MatchSpawns.build({ pad(0, -100, "Red") }, CENTRE, 0, "tdm", CFG)
		expect.equal(#MatchSpawns.spotsFor(onlyRed, "Blue"), 6) -- every spot instead
		local empty = MatchSpawns.build({}, CENTRE, 0, "ffa", CFG)
		local spots = MatchSpawns.firstSpots(empty, { { userId = 1 } })
		expect.near(flat(spots[1].position, CENTRE), 0, 1e-6)
		local spot = MatchSpawns.respawnSpot(empty, { enemies = {}, occupied = {}, r = 0 }, CFG)
		expect.near(flat(spot.position, CENTRE), 0, 1e-6)
	end)
end
