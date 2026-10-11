--!strict
-- AbilityService_Test: unit tests for ServerScriptService.Server.Services.AbilityService (pure helpers, and the place
-- check of a request against a fake match). Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never
-- called; nothing is parented into the place.
-- Contract (DESIGN §5.9, §12 #8):
--   * the aim is flattened to horizontal and must keep at least minHorizontalAim of horizontal length;
--   * the lane starts at O = (HRP.X, floorY + laneHeightAboveFloor, HRP.Z) + dir × originForwardStuds, so its sphere
--     spans floor + 0.5 .. floor + 8.5 with the live config (the lane never touches the floor, jumping never avoids it);
--   * the lane end is clamped to the arena Bounds (X and Z; the lane flies at a fixed height);
--   * a duel caster must stand in its own half + zoneToleranceStuds, like a thrower (§5.6 #5, §12 #5): a request from
--     the neutral zone or the opponent's half is ult.context before any other check (a fake match registered with
--     CombatService; cleaned up at the end).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local AbilityService = t.requireServer("Services/AbilityService")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local RUSH = Config.Abilities.dragon_rush
	local boundsVolume = WorldLayout.Arena.zones.Bounds
	local BOUNDS = { cframe = CFrame.new(boundsVolume.position), size = boundsVolume.size }

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-6)
	end

	t.test("flatAim drops the vertical part and normalizes the rest", function()
		near(AbilityService.flatAim(Vector3.new(1, 0.5, 0), RUSH.minHorizontalAim), Vector3.new(1, 0, 0))
		near(AbilityService.flatAim(Vector3.new(3, -2, 4), RUSH.minHorizontalAim), Vector3.new(0.6, 0, 0.8))
	end)

	t.test("flatAim refuses an aim whose horizontal part is shorter than minHorizontalAim", function()
		expect.equal(AbilityService.flatAim(Vector3.new(0.1, 1, 0.1), RUSH.minHorizontalAim), nil)
		expect.equal(AbilityService.flatAim(Vector3.new(0, -1, 0), RUSH.minHorizontalAim), nil)
		expect.equal(AbilityService.flatAim(Vector3.zero, 0), nil)
	end)

	t.test("the lane origin sits above the HRP at the lane height, moved forward along the aim", function()
		local origin = AbilityService.laneOrigin(Vector3.new(10, 3.2, -30), 0, Vector3.new(0, 0, 1), RUSH)
		near(origin, Vector3.new(10, RUSH.laneHeightAboveFloor, -30 + RUSH.originForwardStuds))
		-- The swept sphere stays off the floor and covers a standing (or jumping) capsule.
		expect.truthy(origin.Y - RUSH.radius > 0)
		expect.near(origin.Y - RUSH.radius, 0.5, 1e-9)
		expect.near(origin.Y + RUSH.radius, 8.5, 1e-9)
		local raised = AbilityService.laneOrigin(Vector3.new(0, 50, 0), 20, Vector3.new(1, 0, 0), RUSH)
		expect.near(raised.Y, 20 + RUSH.laneHeightAboveFloor, 1e-9) -- the floor decides the height, not the HRP
	end)

	t.test("clampToBounds stops the lane at the arena Bounds", function()
		expect.near(AbilityService.clampToBounds(Vector3.new(0, 4.5, -40), Vector3.new(0, 0, 1), 110, BOUNDS), 94, 1e-6)
		expect.near(AbilityService.clampToBounds(Vector3.new(30, 4.5, 0), Vector3.new(1, 0, 0), 110, BOUNDS), 8, 1e-6)
		expect.near(
			AbilityService.clampToBounds(Vector3.new(0, 4.5, 0), Vector3.new(0.6, 0, 0.8), 110, BOUNDS),
			38 / 0.6,
			1e-4
		)
	end)

	t.test("clampToBounds keeps a shorter lane and gives 0 from outside the Bounds", function()
		expect.near(AbilityService.clampToBounds(Vector3.new(0, 4.5, 0), Vector3.new(0, 0, 1), 20, BOUNDS), 20, 1e-9)
		expect.equal(AbilityService.clampToBounds(Vector3.new(50, 4.5, 0), Vector3.new(-1, 0, 0), 110, BOUNDS), 0)
	end)

	local function arenaZones(): { [string]: any }
		local zones = {}
		for name, volume in WorldLayout.Arena.zones do
			zones[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		return zones
	end

	t.test("castFromOwnHalf: the caster's own half + zoneToleranceStuds only (the throw rule, §5.6 #5)", function()
		local zones = arenaZones()
		local tolerance = Config.Combat.Throw.zoneToleranceStuds
		expect.truthy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -40), zones, "A"))
		expect.truthy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -8 + tolerance * 0.5), zones, "A"))
		expect.falsy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -8 + tolerance + 0.5), zones, "A")) -- neutral
		expect.falsy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, 30), zones, "A")) -- the opponent's half
		expect.truthy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, 30), zones, "B"))
		expect.falsy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -40), {}, "A"))
	end)

	t.test("UltimateRequest from the neutral zone or the opponent's half is refused before anything else", function()
		local CombatService = t.requireServer("Services/CombatService")
		local Catalog = t.requireShared("Catalog")
		local Workspace = game:GetService("Workspace")
		CombatService.destroy()
		CombatService.useDeps({
			autoStep = false,
			send = function() end,
			reportViolation = function() end,
		})
		local dragonId = nil
		for _, def in Catalog.list() do
			if def.ultimateId == "dragon_rush" then
				dragonId = def.id
			end
		end
		expect.truthy(dragonId ~= nil)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = model
		model.PrimaryPart = root
		local function newFighter(userId: number, side: string, squishyId: string): any
			return CombatService.newFighter({
				userId = userId,
				side = side,
				squishyId = squishyId,
				getRoot = function(): BasePart?
					return root
				end,
				isAlive = function(): boolean
					return true
				end,
			})
		end
		local caster = newFighter(91, "A", dragonId)
		local other = newFighter(92, "B", Catalog.starterId())
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {}
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {}
		local port = {
			matchId = "ult-place-test",
			arena = {
				slot = 1,
				floorY = 0,
				killY = -15,
				zones = arenaZones(),
				geometry = nil,
				raycastParams = params,
				overlapParams = overlap,
			},
			fighters = { caster, other },
			phase = function(): string
				return "Active"
			end,
			cooldownMultiplier = function(): number
				return 1
			end,
			placement = function(): CFrame?
				return nil
			end,
			canBeHit = function(): boolean
				return false
			end,
			applyHits = function(): { [number]: any }
				return {}
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
		}
		CombatService.registerMatch(port)
		AbilityService.attachMatch(port)
		local aim = Vector3.new(0, 0, 1)
		local function request(seq: number, at: Vector3): (boolean, string?)
			root.CFrame = CFrame.new(at)
			return AbilityService.requestUltimate(91, seq, aim, Workspace:GetServerTimeNow())
		end
		local okNeutral, neutral = request(1, Vector3.new(0, 3, -2))
		expect.falsy(okNeutral)
		expect.equal(neutral, "ult.context")
		local okFar, far = request(2, Vector3.new(0, 3, 30))
		expect.falsy(okFar)
		expect.equal(far, "ult.context")
		-- From the own half the place passes: the next check (no charge yet) answers instead.
		local okOwn, own = request(3, Vector3.new(0, 3, -40))
		expect.falsy(okOwn)
		expect.equal(own, "ult.notReady")
		AbilityService.detachMatch("ult-place-test")
		CombatService.destroy()
		CombatService.useDeps(nil)
		model:Destroy()
	end)
end
