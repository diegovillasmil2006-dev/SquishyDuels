--!strict
-- AimArcController_Test: unit tests for StarterPlayerScripts.Client.Controllers.AimArcController (its pure helpers and
-- lifecycle) and ThrowController.launchSpeed. Server only (ServerStorage.UnitTest). Edit mode: no LocalPlayer, no
-- charge, so start() draws nothing.
-- Contract (the aim arc, jayyyyy 2026-10-16; design: "Squishy Combat FP v2.html" html:256-294, Config.Vfx.AimArc):
--   * the arc is the server's throw: direction × ThrowController.launchSpeed = ThrowRules' velocity (charge and throw
--     boost); ThrowController.launchFor's solved throw leaves from the release offset and flies through the aim point;
--     path() samples are ProjectileMath.positionAt, the last one exactly at the landing time;
--   * landing(): the first cast hit along the server's sub-steps, at ProjectileMath.impactTime; no hit = tMax and no
--     marker; never more casts than maxSteps;
--   * excluded() (review fix 2026-10-16): the cast leaves out every character but the enemies' (the own one, a TDM
--     teammate, a lobby player in the practice lane), and the client effects folder; botIsEnemy() (batch B
--     2026-10-17): every bot's rig stays in but a TDM teammate's;
--   * layout(): dashes from startStuds + phase · gapStuds, gapStuds apart, at most `dashes`, none past the end, widths
--     and lengths by the design's formula (html:287); isWhite: every 4th (html:288);
--   * fade(): the design's ease in (fadeInRate) and out (fadeOutRate), html:267; reduced motion jumps, and the march
--     and the marker's pulse stop;
--   * axisFrame(): its Z axis is the given one, straight up and down included;
--   * Config.Vfx.AimArc holds sane numbers (checked here: Config/init is at its size limit);
--   * init / start (a private scheduler) / one frame / destroy run cleanly with no charge.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local NOW = 1_800_000_000 -- a realistic GetServerTimeNow() value (as ThrowRules_Test)
-- Kitty Bread's catalog throw (as ThrowRules_Test).
local THROW = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.0, windup = 0.18 }
-- Arena half A and side A's root facing +Z (as ThrowRules_Test).
local HALF_A = { cframe = CFrame.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) }
local DUEL_ROOT = CFrame.new(0, 3, -30) * CFrame.Angles(0, math.rad(180), 0)

return function(t: Context)
	local AimArc = t.requireClient("Controllers/AimArcController")
	local ThrowController = t.requireClient("Controllers/ThrowController")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local ThrowRules = t.requireServer("Logic/ThrowRules")
	local ProjectileMath = t.requireShared("ProjectileMath")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local ARC = Config.Vfx.AimArc

	local function nearVector(a: Vector3, b: Vector3, tolerance: number)
		expect.near((a - b).Magnitude, 0, tolerance)
	end

	-- A floor at y = 0 for a sphere: the fraction of `delta` at which its centre reaches y = radius.
	local function floorCast(from: Vector3, radius: number, delta: Vector3): (number?, Vector3?, Vector3?)
		if delta.Y >= 0 or from.Y + delta.Y > radius then
			return nil, nil, nil
		end
		local f = math.clamp((from.Y - radius) / -delta.Y, 0, 1)
		local centre = from + delta * f
		return f, Vector3.new(centre.X, 0, centre.Z), Vector3.yAxis
	end

	t.test("the launch is the server's: direction × launchSpeed = ThrowRules' velocity", function()
		local dir = Vector3.new(0, math.sin(math.rad(10)), math.cos(math.rad(10)))
		local cases: { { start: number?, boost: number? } } = {
			{ start = nil, boost = nil }, -- no ChargeStart: c = 0
			{ start = NOW - 0.55, boost = nil }, -- c = 0.5
			{ start = NOW - 5, boost = nil }, -- full
			{ start = NOW - 0.55, boost = 1.4 }, -- the throw boost
			{ start = NOW - 5, boost = 1.4 },
		}
		for _, case in cases do
			local state: any = {
				lastSeq = 0,
				nextThrowAt = NOW - 10,
				activeProjectiles = 0,
				matchPhase = "Active",
				alive = true,
				rootCFrame = DUEL_ROOT,
				rooted = false,
				ownHalf = HALF_A,
				ping = 0.1,
				throw = THROW,
				chargeStartAt = case.start,
				speedMultiplier = case.boost,
			}
			local request = {
				seq = 1,
				aimDir = dir,
				originHint = DUEL_ROOT * Config.Combat.ReleaseOffset,
				clientTime = NOW - 0.05,
			}
			local decision = ThrowRules.validate(request, state, nil, NOW)
			expect.truthy(decision.ok)
			local arc = decision.direction * ThrowController.launchSpeed(THROW, decision.charge, case.boost)
			nearVector(arc, decision.velocity, 1e-6)
		end
	end)

	t.test("launchFor × launchSpeed: from the release offset, through the aim point", function()
		local Catalog = t.requireShared("Catalog")
		local def = Catalog.get(Catalog.starterId())
		local root = Instance.new("Part")
		root.CFrame = CFrame.new(10, 3, -5) * CFrame.Angles(0, math.rad(180), 0) -- facing +Z
		local ctx = { kind = "match", def = def, cooldownMultiplier = 1, speedMultiplier = 1.4 }
		for _, case in { { c = 0, point = Vector3.new(14, 4, 40) }, { c = 0.6, point = Vector3.new(4, 1, 70) } } do
			local origin, dir, reason = ThrowController.launchFor(ctx, root, case.point, nil, case.c, false)
			expect.equal(reason, nil)
			nearVector(origin :: Vector3, (root.CFrame * CFrame.new(Config.Combat.ReleaseOffset)).Position, 1e-6)
			local v = (dir :: Vector3) * ThrowController.launchSpeed(def.throw, case.c, 1.4)
			local flat = Vector3.new(case.point.X - (origin :: Vector3).X, 0, case.point.Z - (origin :: Vector3).Z)
			local arrive = flat.Magnitude / Vector3.new(v.X, 0, v.Z).Magnitude
			nearVector(ProjectileMath.positionAt(origin :: Vector3, v, def.throw.gravity, arrive), case.point, 1e-3)
		end
		root:Destroy()
	end)

	t.test("path: the samples are ProjectileMath.positionAt, the last exactly at the end time", function()
		local o, v, g = Vector3.new(2, 5, -1), Vector3.new(30, 20, 4), 35
		local points, dists = {}, {}
		local n = AimArc.path(o, v, g, 1.234, 1 / 90, points, dists)
		expect.equal(n, math.ceil(1.234 * 90) + 1)
		nearVector(points[1], o, 1e-9)
		for _, i in { 2, 10, 57, n - 1 } do
			nearVector(points[i], ProjectileMath.positionAt(o, v, g, (i - 1) / 90), 1e-6)
		end
		nearVector(points[n], ProjectileMath.positionAt(o, v, g, 1.234), 1e-6)
		expect.equal(dists[1], 0)
		for i = 2, n do
			expect.near(dists[i] - dists[i - 1], (points[i] - points[i - 1]).Magnitude, 1e-9)
		end
		local m = AimArc.path(o, v, g, 0, 1 / 90, points, dists)
		expect.equal(m, 2)
		expect.equal(dists[2], 0)
	end)

	t.test("landing: the first hit along the sub-steps, at impactTime; on the surface, with its normal", function()
		local o, v, g = Vector3.new(0, 5, 0), Vector3.new(30, 20, 0), 35
		local endTime, hit, normal = AimArc.landing(o, v, g, 1, 3, 10, 30, floorCast)
		-- The sphere's centre reaches y = 1: 5 + 20t - 17.5t² = 1.
		local exact = (20 + math.sqrt(20 * 20 + 4 * 17.5 * 4)) / 35
		expect.near(endTime, exact, 0.01)
		expect.truthy(hit ~= nil and normal ~= nil)
		expect.near((hit :: Vector3).Y, 0, 1e-9)
		expect.near((hit :: Vector3).X, 30 * endTime, 0.05)
		nearVector(normal :: Vector3, Vector3.yAxis, 1e-9)
		-- A wall at x = 10 comes first (the centre reaches x = 9 at t = 0.3).
		local function wallOrFloor(from: Vector3, radius: number, delta: Vector3): (number?, Vector3?, Vector3?)
			if from.X < 10 - radius and from.X + delta.X >= 10 - radius then
				local f = (10 - radius - from.X) / delta.X
				return f, from + delta * f + Vector3.new(radius, 0, 0), -Vector3.xAxis
			end
			return floorCast(from, radius, delta)
		end
		local wallTime, _, wallNormal = AimArc.landing(o, v, g, 1, 3, 10, 30, wallOrFloor)
		expect.near(wallTime, 0.3, 1e-6)
		nearVector(wallNormal :: Vector3, -Vector3.xAxis, 1e-9)
	end)

	t.test("landing: no hit = the whole lifetime and no marker; never more casts than maxSteps", function()
		local calls = 0
		local function miss(): (number?, Vector3?, Vector3?)
			calls += 1
			return nil, nil, nil
		end
		local endTime, hit, normal = AimArc.landing(Vector3.zero, Vector3.new(100, 50, 0), 35, 1, 3, 10, 30, miss)
		expect.equal(endTime, 3)
		expect.equal(hit, nil)
		expect.equal(normal, nil)
		expect.equal(calls, 30)
		calls = 0
		AimArc.landing(Vector3.zero, Vector3.new(100, 50, 0), 35, 1, 3, 10, 12, miss)
		expect.equal(calls, 12)
	end)

	-- Review fix (2026-10-16, job aimarc): the server's throw meets players only as enemy capsules, so the cast leaves
	-- every other character out.
	t.test(
		"excluded: the own character, a teammate and a bystander in the lane are left out; an enemy is not",
		function()
			-- Typed as Instance (small1 merge, 2026-10-16): one list holds the Models and the Folder (strict mode).
			local own: Instance, mate: Instance, bystander: Instance, enemy: Instance =
				Instance.new("Model"), Instance.new("Model"), Instance.new("Model"), Instance.new("Model")
			local fx: Instance = Instance.new("Folder")
			local out = { Instance.new("Model") } -- stale content is cleared
			local list = AimArc.excluded({ own, mate, enemy, bystander }, { enemy }, fx, out)
			expect.equal(list, out)
			expect.deepEqual(list, { own, mate, bystander, fx })
			expect.equal(table.find(list, enemy), nil)
			-- Practice (no enemy): every character is left out; without the effects folder only the characters.
			expect.deepEqual(AimArc.excluded({ own, bystander }, {}, nil, {}), { own, bystander })
			-- An enemy that is not a player character (the duel's Studio dummy) changes nothing.
			expect.deepEqual(AimArc.excluded({ own }, { enemy }, fx, {}), { own, fx })
			for _, instance in { own, mate, bystander, enemy, fx } do
				instance:Destroy()
			end
		end
	)

	-- Batch B (2026-10-17): a bot's rig is an enemy body unless it is the local player's TDM teammate (same SD_Team).
	t.test("botIsEnemy: every bot but a TDM teammate", function()
		expect.truthy(AimArc.botIsEnemy(nil, nil)) -- a duel's practice bot, an FFA bot
		expect.truthy(AimArc.botIsEnemy(nil, "Red")) -- not in a team: every bot
		expect.truthy(AimArc.botIsEnemy("Red", "Blue"))
		expect.truthy(AimArc.botIsEnemy("Red", nil))
		expect.falsy(AimArc.botIsEnemy("Red", "Red"))
	end)

	t.test("layout: from startStuds + phase · gap, gapStuds apart, the design's sizes", function()
		local points, dists, out = {}, {}, {}
		local o = Vector3.new(0, 3, 0)
		local n = AimArc.path(o, Vector3.new(10, 0, 0), 0, 5, 1 / 90, points, dists) -- a straight 50-stud path
		local total = dists[n]
		expect.near(total, 50, 1e-4) -- Vector3 is float32
		local k = AimArc.layout(points, dists, n, 0.5, 1, 0, out)
		expect.equal(k, math.floor((total - ARC.startStuds) / ARC.gapStuds) + 1)
		for i = 1, k do
			local s = ARC.startStuds + (i - 1) * ARC.gapStuds
			local dash = out[i]
			expect.truthy(s < total)
			nearVector(dash.position, o + Vector3.new(s, 0, 0), 1e-4)
			nearVector(dash.direction, Vector3.xAxis, 1e-9)
			local fade = 1 - ARC.farFade * s / total
			local ramp = ARC.widthFrom + (1 - ARC.widthFrom) * math.min(1, s / ARC.widthRampStuds)
			expect.near(dash.width, (ARC.widthStuds + ARC.widthChargeStuds * 0.5) * ramp * fade, 1e-9)
			expect.near(dash.length, ARC.dashLengthStuds * fade, 1e-9)
		end
		AimArc.layout(points, dists, n, 0.5, 1, 0.5, out)
		nearVector(out[1].position, o + Vector3.new(ARC.startStuds + 0.5 * ARC.gapStuds, 0, 0), 1e-4)
		AimArc.layout(points, dists, n, 0.5, 0, 0, out)
		expect.equal(out[1].width, 0) -- faded out: no width, the same length
		expect.truthy(out[1].length > 0)
	end)

	t.test("layout: at most `dashes`; nothing on a path shorter than startStuds; isWhite every 4th", function()
		local points, dists, out = {}, {}, {}
		local n = AimArc.path(Vector3.zero, Vector3.new(100, 0, 0), 0, 3, 1 / 90, points, dists) -- 300 studs
		expect.equal(AimArc.layout(points, dists, n, 1, 1, 0.3, out), ARC.dashes)
		local m = AimArc.path(Vector3.zero, Vector3.new(1, 0, 0), 0, ARC.startStuds * 0.9, 1 / 90, points, dists)
		expect.equal(AimArc.layout(points, dists, m, 1, 1, 0, out), 0)
		for k = 1, 12 do
			expect.equal(AimArc.isWhite(k), k % 4 == 0)
		end
	end)

	t.test("fade: eases in at fadeInRate and out at fadeOutRate; reduced motion jumps", function()
		local dt = 1 / 60
		expect.near(AimArc.fade(0, true, dt, false), math.min(1, dt * ARC.fadeInRate), 1e-9)
		expect.near(AimArc.fade(1, false, dt, false), 1 - math.min(1, dt * ARC.fadeOutRate), 1e-9)
		expect.near(AimArc.fade(0.4, true, 1, false), 1, 1e-9)
		expect.equal(AimArc.fade(0, true, dt, true), 1)
		expect.equal(AimArc.fade(1, false, dt, true), 0)
		expect.equal(AimArc.fade(0.5, true, -1, false), 0.5)
	end)

	t.test("marchPhase and markerRadius: the design's march and pulse, none under reduced motion", function()
		expect.near(AimArc.marchPhase(0.5, false), (0.5 * ARC.marchRate) % 1, 1e-9)
		expect.equal(AimArc.marchPhase(0.5, true), 0)
		local base = ARC.markerStuds + ARC.markerChargeStuds * 0.5
		expect.near(AimArc.markerRadius(0.5, 0, 1, false), base, 1e-9)
		local peak = math.pi / (2 * ARC.markerPulseRate) -- sin = 1
		expect.near(AimArc.markerRadius(0.5, peak, 1, false), base * (1 + ARC.markerPulse), 1e-9)
		expect.near(AimArc.markerRadius(0.5, peak, 1, true), base, 1e-9)
		expect.near(AimArc.markerRadius(0.5, peak, 0.5, true), base * 0.5, 1e-9)
	end)

	t.test("axisFrame: the Z axis is the given axis, straight up and down included", function()
		for _, axis in
			{ Vector3.yAxis, -Vector3.yAxis, Vector3.xAxis, Vector3.new(0.3, -0.8, 0.5), Vector3.new(0, 0.97, 0.2) }
		do
			local frame = AimArc.axisFrame(Vector3.new(1, 2, 3), axis)
			nearVector(frame.ZVector, axis.Unit, 1e-6)
			nearVector(frame.Position, Vector3.new(1, 2, 3), 1e-9)
			expect.near(frame.XVector:Dot(frame.YVector), 0, 1e-6)
			expect.near(frame.XVector:Dot(frame.ZVector), 0, 1e-6)
			expect.near(frame.YVector.Magnitude, 1, 1e-6)
		end
	end)

	t.test("Config.Vfx.AimArc: sane numbers", function()
		expect.truthy(ARC.dashes == math.floor(ARC.dashes) and ARC.dashes >= 1 and ARC.dashes <= 64)
		expect.truthy(ARC.whiteEvery == math.floor(ARC.whiteEvery) and ARC.whiteEvery >= 1)
		for _, key in
			{
				"fadeInRate",
				"fadeOutRate",
				"stepSeconds",
				"startStuds",
				"gapStuds",
				"dashLengthStuds",
				"widthStuds",
				"widthRampStuds",
				"markerStuds",
				"markerLiftStuds",
				"markerHeightStuds",
				"castChordSeconds",
				"maxCasts",
			}
		do
			expect.truthy(type(ARC[key]) == "number" and ARC[key] > 0)
		end
		for _, key in { "showFromCharge", "hideBelow", "widthFrom", "farFade", "opacity", "markerOpacity" } do
			expect.truthy(ARC[key] >= 0 and ARC[key] <= 1)
		end
		expect.truthy(ARC.markerDot < ARC.markerInner and ARC.markerInner < 1)
		expect.truthy(ARC.markerHeightStuds < 2 * ARC.markerLiftStuds) -- the ring never sinks into the surface
		-- the casts cover the whole flight a projectile lives
		expect.truthy(ARC.maxCasts * ARC.castChordSeconds >= Config.Duel.Rules.ProjectileMaxLifetime - 1e-9)
	end)

	t.test("init / start / a frame / destroy run cleanly with no charge (private scheduler)", function()
		local scheduler = Scheduler.new(false)
		AimArc.init()
		AimArc.start(scheduler)
		expect.equal(scheduler:count("render"), 1)
		scheduler:tick("render", 1 / 60)
		expect.equal(scheduler:count("render"), 1)
		AimArc.destroy()
		expect.equal(scheduler:count("render"), 0)
		expect.equal(ThrowController.chargePreview(), nil)
	end)
end
