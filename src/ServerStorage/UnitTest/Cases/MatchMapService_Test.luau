--!strict
-- MatchMapService_Test: unit tests for the pure parts of ServerScriptService.Server.Services.MatchMapService (FFA/TDM
-- v1, 2026-10-15, SPEC D14). Edit mode: init() is never called and nothing is parented to the Workspace.
-- Contract: a map's Mode attribute names a Config.Match mode in any case ("TDM" -> "tdm"); pad names are read without
-- case (*_Spawn_Red_* / *_Spawn_Blue_* / *_Spawn_Ffa_*, ".001" copies too, *_PowerUp_Pad_*); the Bounds zone spans the
-- footprint around the centre from floorY + boundsBottomOffset to floorY + boundsTop; acquire picks only a free map of
-- the asked mode (at random) and release frees it; recordFrom reads an unparented Model (pads, power-up pads, the
-- collidable parts, the spawn set) and refuses a map without the pads its mode needs; the box queries (OverlapParams)
-- leave out meshes without Box collision fidelity (critic fix 2026-10-15). Config tables are passed in.

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
	local MatchMapService = t.requireServer("Services/MatchMapService")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local CFG = deepCopy(Config.Match)
	CFG.Maps = {
		footprint = { TDM = Vector3.new(160, 0, 240), FFA = Vector3.new(200, 0, 200) },
		boundsBottomOffset = -15,
		boundsTop = 100,
	}
	CFG.Spawns = { spotsPerPad = { tdm = 6, ffa = 2 }, edgeStuds = 4, occupiedStuds = 4, raycastUpStuds = 40 }

	t.test("the Mode attribute names a mode in any case; anything else is no map", function()
		expect.equal(MatchMapService.modeOf("TDM", CFG), "tdm")
		expect.equal(MatchMapService.modeOf("FFA", CFG), "ffa")
		expect.equal(MatchMapService.modeOf("ffa", CFG), "ffa")
		expect.equal(MatchMapService.modeOf("Duel", CFG), nil)
		expect.equal(MatchMapService.modeOf(nil, CFG), nil)
		expect.equal(MatchMapService.modeOf(5, CFG), nil)
	end)

	t.test("pad names: Red, Blue and FFA spawn pads (copies too) and power-up pads, without case", function()
		expect.equal(MatchMapService.padKind("TBC_Spawn_Red_01"), "Red")
		expect.equal(MatchMapService.padKind("SPF_Spawn_Blue_2"), "Blue")
		expect.equal(MatchMapService.padKind("JAR_Spawn_Ffa_03.001"), "Ffa")
		expect.equal(MatchMapService.padKind("jar_spawn_FFA_4"), "Ffa")
		expect.equal(MatchMapService.padKind("Spawn_Red_1"), "Red")
		expect.equal(MatchMapService.padKind("SDP_PowerUp_Pad_05"), "PowerUp")
		expect.equal(MatchMapService.padKind("SDP_Floor_COL"), nil)
		expect.equal(MatchMapService.padKind("RedWall"), nil)
	end)

	t.test("Bounds: the footprint around the centre, from the kill line up to boundsTop", function()
		local zone = MatchMapService.boundsFor(Vector3.new(6000, 0, 0), 0, CFG.Maps.footprint.TDM, CFG)
		expect.near((zone.cframe.Position - Vector3.new(6000, 42.5, 0)).Magnitude, 0, 1e-6)
		expect.near((zone.size - Vector3.new(160, 115, 240)).Magnitude, 0, 1e-6)
		local function inside(point: Vector3): boolean
			local p = zone.cframe:PointToObjectSpace(point)
			local half = zone.size / 2
			return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
		end
		expect.truthy(inside(Vector3.new(6000, 29, 110))) -- a platform top near the far wall
		expect.truthy(inside(Vector3.new(6079, -14.9, 0)))
		expect.falsy(inside(Vector3.new(6000, -15.1, 0)))
		expect.falsy(inside(Vector3.new(6081, 3, 0)))
		expect.falsy(inside(Vector3.new(6000, 100.1, 0)))
		-- Raised floors move the whole box.
		local raised = MatchMapService.boundsFor(Vector3.new(0, 10, 0), 10, CFG.Maps.footprint.FFA, CFG)
		expect.near(raised.cframe.Position.Y, 52.5, 1e-6)
	end)

	t.test("acquire: only a free map of the asked mode, at random; release frees it", function()
		local maps: { any } = {
			{ name = "TBC", modeId = "tdm", inUse = false },
			{ name = "JAR", modeId = "ffa", inUse = true },
			{ name = "SDP", modeId = "ffa", inUse = false },
			{ name = "PFP", modeId = "ffa", inUse = false },
		}
		expect.equal(MatchMapService.pickFree(maps, "ffa", 0).name, "SDP")
		expect.equal(MatchMapService.pickFree(maps, "ffa", 0.99).name, "PFP")
		expect.equal(MatchMapService.pickFree(maps, "tdm", 0.5).name, "TBC")
		MatchMapService.useMaps(maps :: any)
		expect.truthy(MatchMapService.hasMode("ffa"))
		expect.falsy(MatchMapService.hasMode("duel"))
		local held = MatchMapService.acquire("tdm", "match:a", 0)
		expect.equal(held and held.name, "TBC")
		expect.equal(maps[1].matchId, "match:a")
		expect.equal(MatchMapService.acquire("tdm", "match:b", 0), nil) -- the only TDM map is in use
		MatchMapService.release(held)
		expect.falsy(maps[1].inUse)
		expect.equal(MatchMapService.acquire("tdm", "match:c", 0), maps[1])
		MatchMapService.useMaps({})
	end)

	t.test("recordFrom reads an unparented map: pads, power-up pads, collidable parts and the spawn set", function()
		local model = Instance.new("Model")
		model.Name = "TBC"
		model:SetAttribute("Mode", "TDM")
		model:SetAttribute("MapCode", "TBC")
		model.WorldPivot = CFrame.new(6000, 0, 0)
		local function part(name: string, position: Vector3, size: Vector3, collide: boolean): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanCollide = collide
			p.Size = size
			p.CFrame = CFrame.new(position)
			p.Parent = model
			return p
		end
		part("TBC_Floor_COL", Vector3.new(6000, -0.5, 0), Vector3.new(160, 1, 240), true)
		part("TBC_Spawn_Red_01", Vector3.new(6000, 0.25, -100), Vector3.new(30, 0.5, 20), true)
		part("TBC_Spawn_Blue_01", Vector3.new(6000, 0.25, 100), Vector3.new(30, 0.5, 20), true)
		part("TBC_PowerUp_Pad_01", Vector3.new(6020, 0.25, 0), Vector3.new(6, 0.5, 6), true)
		part("TBC_Decor", Vector3.new(6050, 5, 0), Vector3.new(2, 2, 2), false)
		local record, why = MatchMapService.recordFrom(model, CFG)
		expect.equal(why, nil)
		assert(record ~= nil, "no record")
		expect.equal(record.modeId, "tdm")
		expect.equal(record.code, "TBC")
		expect.equal(record.floorY, 0)
		expect.equal(#record.pads, 2)
		expect.equal(#record.powerUpPads, 1)
		expect.equal(#record.raycastParams.FilterDescendantsInstances, 4) -- the decor does not collide
		expect.equal(#record.overlapParams.FilterDescendantsInstances, 4) -- Parts: the box queries see them all
		local red = 0
		for _, p in record.pads do
			if p.team == "Red" then
				red += 1
			end
		end
		expect.equal(red, 1)
		expect.equal(#record.spawns.spotsOf[1], 6)
		expect.near(record.startRadius, math.sqrt(160 * 160 + 240 * 240) / 2, 1e-6)
		expect.falsy(record.inUse)

		-- A TDM map without its Blue pad can't host a match.
		model:FindFirstChild("TBC_Spawn_Blue_01"):Destroy()
		local missing, reason = MatchMapService.recordFrom(model, CFG)
		expect.equal(missing, nil)
		expect.truthy(reason ~= nil)
		model:SetAttribute("Mode", "Duel")
		expect.equal((MatchMapService.recordFrom(model, CFG)), nil)
		model:Destroy()
	end)

	-- Critic fix (2026-10-15): a box query (OverlapParams) never sees a mesh without Box collision fidelity (Diego's Hull
	-- ramps and stairs: their box covers the slope, so every throw from a ramp fizzled); the casts (RaycastParams) do.
	t.test("box queries see Parts and Box meshes only; casts see every collidable part", function()
		local part = Instance.new("Part")
		-- Stand-ins for meshes (the fidelity is a plugin-security write, so real ones can't be set in every runner).
		local function fakeMesh(className: string, fidelity: EnumItem): any
			return {
				CollisionFidelity = fidelity,
				IsA = function(_self: any, name: string): boolean
					return name == className or name == "BasePart"
				end,
			}
		end
		local hull = fakeMesh("MeshPart", Enum.CollisionFidelity.Hull)
		local precise = fakeMesh("MeshPart", Enum.CollisionFidelity.PreciseConvexDecomposition)
		local default = fakeMesh("MeshPart", Enum.CollisionFidelity.Default)
		local box = fakeMesh("MeshPart", Enum.CollisionFidelity.Box)
		local union = fakeMesh("PartOperation", Enum.CollisionFidelity.Hull)
		local kept = MatchMapService.boxQueryParts({ part, hull, precise, default, box, union } :: any)
		expect.equal(#kept, 2)
		expect.equal(kept[1], part)
		expect.equal(kept[2], box)
		local made, mesh = pcall(function(): any
			return Instance.new("MeshPart")
		end)
		if made and mesh then
			local okRead, fidelity = pcall(function(): any
				return mesh.CollisionFidelity
			end)
			if okRead and fidelity ~= Enum.CollisionFidelity.Box then
				expect.equal(#MatchMapService.boxQueryParts({ part, mesh }), 1) -- a new MeshPart is Default
			end
			mesh:Destroy()

			-- recordFrom: the mesh stays in the cast list and out of the box list.
			local model = Instance.new("Model")
			model:SetAttribute("Mode", "FFA")
			model.WorldPivot = CFrame.new(7500, 0, 0)
			local pad = Instance.new("Part")
			pad.Name = "JAR_Spawn_Ffa_01"
			pad.Anchored = true
			pad.CanCollide = false
			pad.Size = Vector3.new(20, 0.5, 20)
			pad.CFrame = CFrame.new(7500, 0.25, -60)
			pad.Parent = model
			local floor = Instance.new("Part")
			floor.Anchored = true
			floor.Size = Vector3.new(200, 1, 200)
			floor.CFrame = CFrame.new(7500, -0.5, 0)
			floor.Parent = model
			local ramp = Instance.new("MeshPart")
			ramp.Anchored = true
			ramp.CanCollide = true
			ramp.Parent = model
			local okRamp, rampFidelity = pcall(function(): any
				return ramp.CollisionFidelity
			end)
			local record = MatchMapService.recordFrom(model, CFG)
			assert(record ~= nil, "no record")
			expect.equal(#record.raycastParams.FilterDescendantsInstances, 2)
			if okRamp and rampFidelity ~= Enum.CollisionFidelity.Box then
				expect.equal(#record.overlapParams.FilterDescendantsInstances, 1) -- the floor only
			end
			model:Destroy()
		end
		part:Destroy()
	end)

	t.test(
		"a rescan keeps a map a running match holds in use; releasing the match's record frees the new one",
		function()
			local folder = Instance.new("Folder")
			local model = Instance.new("Model")
			model.Name = "JAR"
			model:SetAttribute("Mode", "FFA")
			model:SetAttribute("MapCode", "JAR")
			model.WorldPivot = CFrame.new(7500, 0, 0)
			local pad = Instance.new("Part")
			pad.Name = "JAR_Spawn_Ffa_01"
			pad.Anchored = true
			pad.Size = Vector3.new(20, 0.5, 20)
			pad.CFrame = CFrame.new(7500, 0.25, -60)
			pad.Parent = model
			model.Parent = folder
			expect.equal(MatchMapService.scan(folder, CFG), 1)
			local held = MatchMapService.acquire("ffa", "match:a", 0)
			assert(held ~= nil, "no map")
			expect.equal(MatchMapService.scan(folder, CFG), 1)
			expect.equal(MatchMapService.acquire("ffa", "match:b", 0), nil) -- still one match per map
			expect.equal(MatchMapService.list()[1].matchId, "match:a")
			MatchMapService.release(held) -- the running match holds the record from before the rescan
			expect.falsy(MatchMapService.list()[1].inUse)
			expect.equal(MatchMapService.acquire("ffa", "match:c", 0), MatchMapService.list()[1])
			MatchMapService.useMaps({})
			folder:Destroy()
		end
	)
end
