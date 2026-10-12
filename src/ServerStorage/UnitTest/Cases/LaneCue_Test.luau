--!strict
-- LaneCue_Test: unit tests for StarterPlayerScripts.Client.UI.LaneCue (final polish 2026-10-11: the "In the lane!"
-- warning under the duel bar during an enemy lane ultimate's telegraph). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * a lane comes only from a telegraph of a lane-kind ultimate (Dragon Rush "lane", Sprinkle Roller "roller"): its
--     segment O -> O + dir·length on the ground plane and its reach = the event's radius + the player capsule's
--     radius (the server's own tests: CombatService's standing capsule for the lane, UltRules.flatEntry for the
--     roller), until telegraphEndsAt; any other kind, phase or a broken event gives none;
--   * inLane: the horizontal distance from the body (HRP) to that segment is within the reach (round ends, as the
--     drawn stadium); the height never matters (jumping never avoids Dragon Rush's lane);
--   * shows: a lane, a body in it, and the telegraph still running;
--   * top: the cue sits `gap` under the duel bar, or under the banner when one shows under the bar.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local LaneCue = t.requireClient("UI/LaneCue")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local CAPSULE = Config.Combat.Hitbox.radius

	local function event(overrides: { [string]: any }?): any
		local e: { [string]: any } = {
			phase = "telegraph",
			casterId = 2,
			ultimateId = nil,
			origin = Vector3.new(0, 4.5, 0),
			dir = Vector3.new(0, 0, -1),
			length = 60,
			radius = 4,
			telegraphEndsAt = 100.9,
			speed = 260,
		}
		local extra: { [string]: any } = overrides or {}
		for key, value in extra do
			e[key] = value
		end
		return e
	end

	t.test("a lane only from a lane-kind ultimate's telegraph: Dragon Rush and Sprinkle Roller", function()
		local rush = LaneCue.laneOf(event(), "lane")
		if rush == nil then
			error("no lane for Dragon Rush")
		end
		expect.near(rush.reach, 4 + CAPSULE)
		expect.equal(rush.endsAt, 100.9)
		expect.truthy((rush.a - Vector3.new(0, 0, 0)).Magnitude < 1e-9) -- on the ground plane
		expect.truthy((rush.b - Vector3.new(0, 0, -60)).Magnitude < 1e-9)
		local roller = LaneCue.laneOf(event({ ultimateId = "sprinkle_roller", radius = 3, length = 45 }), "roller")
		if roller == nil then
			error("no lane for the roller")
		end
		expect.near(roller.reach, 3 + CAPSULE)
		for _, kind in { "volley", "rain", "bubble" } do
			expect.equal(LaneCue.laneOf(event(), kind), nil)
		end
		expect.equal(LaneCue.laneOf(event({ phase = "release" }), "lane"), nil)
		expect.equal(LaneCue.laneOf(event({ phase = "cancel" }), "lane"), nil)
		expect.equal(LaneCue.laneOf(event({ length = 0 / 0 }), "lane"), nil)
		expect.equal(LaneCue.laneOf(event({ dir = Vector3.zero }), "lane"), nil)
		expect.equal(LaneCue.laneOf(nil :: any, "lane"), nil)
	end)

	t.test("inLane: the body's horizontal distance to the segment within the reach; height never counts", function()
		local lane = LaneCue.laneOf(event(), "lane") :: any
		local reach = 4 + CAPSULE
		expect.truthy(LaneCue.inLane(lane, Vector3.new(0, 3, -30))) -- on the centre line
		expect.truthy(LaneCue.inLane(lane, Vector3.new(reach - 0.01, 3, -30))) -- the edge, inside
		expect.falsy(LaneCue.inLane(lane, Vector3.new(reach + 0.01, 3, -30))) -- just outside
		expect.truthy(LaneCue.inLane(lane, Vector3.new(0, 40, -30))) -- high in the air: still in it
		expect.truthy(LaneCue.inLane(lane, Vector3.new(0, 3, -60 - reach + 0.01))) -- the far end's round cap
		expect.falsy(LaneCue.inLane(lane, Vector3.new(0, 3, -60 - reach - 0.01)))
		expect.truthy(LaneCue.inLane(lane, Vector3.new(0, 3, reach - 0.01))) -- behind O, inside its cap
		expect.falsy(LaneCue.inLane(lane, Vector3.new(reach * 0.75, 3, reach * 0.75))) -- the cap is round
	end)

	t.test("shows: a lane, a body in it and the telegraph still running", function()
		local lane = LaneCue.laneOf(event(), "lane")
		local inside, outside = Vector3.new(1, 3, -10), Vector3.new(20, 3, -10)
		expect.truthy(LaneCue.shows(lane, inside, 100))
		expect.falsy(LaneCue.shows(lane, outside, 100))
		expect.falsy(LaneCue.shows(lane, inside, 100.9)) -- the telegraph is over
		expect.falsy(LaneCue.shows(nil, inside, 100))
		expect.falsy(LaneCue.shows(lane, nil, 100)) -- no body
	end)

	t.test("top: gap under the duel bar, or under a banner that shows under the bar", function()
		expect.equal(LaneCue.top(120, nil, nil, 8), 128)
		expect.equal(LaneCue.top(120, 128, 200, 8), 208) -- the banner sits under the bar: under it
		expect.equal(LaneCue.top(120, 40, 100, 8), 128) -- a banner higher up (not under the bar): ignored
	end)
end
