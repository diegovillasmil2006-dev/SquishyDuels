--!strict
-- DashController_Test: unit tests for StarterPlayerScripts.Client.Controllers.DashController's pure helpers (spec
-- phase 5 §3.3). Server only (ServerStorage.UnitTest). Edit mode: init() is never called; no instances.
-- Contract:
--   * the client gate mirrors the server's rules (Logic/DashRules), so an honest press is never refused: a duel in
--     Active or SuddenDeath with the HRP in the own half, or the practice range; alive; not already dashing; not
--     rooted by an ultimate, not in a throw windup or an ultimate's cast; on the ground; cooldownSeconds since the
--     last dash (no tolerance: the client is the stricter side);
--   * the design's feet: the push-off puff from the right foot for an L dash, else the left; the plant puff from the
--     right foot for an R dash, else the left (fp.js:516-517);
--   * the held arm's offset fades in over 0.9 frames and out over the last 3 (avatar.js:160-162);
--   * the ribbons take the dasher's team tint: side A Strawberry, side B Mint, practice Strawberry;
--   * a DashStarted payload is used only when every field has its type and dir is a flat unit vector.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DashController = t.requireClient("Controllers/DashController")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local DASH = Config.Duel.Rules.Dash

	local function gate(overrides: { [string]: any }?): any
		local facts: { [string]: any } = {
			context = "duel",
			phase = "Active",
			dashing = false,
			now = 100,
			lastDashAt = -math.huge,
			rooted = false,
			windup = false,
			ultBusy = false,
			grounded = true,
			alive = true,
			inZone = true,
		}
		local extra: { [string]: any } = overrides or {}
		for key, value in extra do
			facts[key] = value
		end
		return facts
	end

	t.test("the gate: a duel in Active / SuddenDeath or the practice range, ready and on the ground", function()
		expect.equal(DashController.gate(gate()), nil)
		expect.equal(DashController.gate(gate({ phase = "SuddenDeath" })), nil)
		local practice = gate({ context = "practice" })
		practice.phase = nil -- (a nil in the overrides table would never be copied)
		expect.equal(DashController.gate(practice), nil)
		expect.equal(DashController.gate(gate({ phase = "Countdown" })), "dash.context")
		local nowhere = gate()
		nowhere.context = nil
		expect.equal(DashController.gate(nowhere), "dash.context")
		expect.equal(DashController.gate(gate({ alive = false })), "dash.context")
		expect.equal(DashController.gate(gate({ inZone = false })), "dash.context")
		practice.inZone = false -- the own half is a duel rule only
		expect.equal(DashController.gate(practice), nil)
		expect.equal(DashController.gate(gate({ dashing = true })), "dash.busy")
		expect.equal(DashController.gate(gate({ rooted = true })), "dash.busy")
		expect.equal(DashController.gate(gate({ windup = true })), "dash.busy")
		expect.equal(DashController.gate(gate({ ultBusy = true })), "dash.busy")
		expect.equal(DashController.gate(gate({ grounded = false })), "dash.airborne")
		expect.equal(DashController.gate(gate({ lastDashAt = 100 - DASH.cooldownSeconds + 0.1 })), "dash.cooldown")
		expect.equal(DashController.gate(gate({ lastDashAt = 100 - DASH.cooldownSeconds })), nil)
	end)

	t.test(
		"the design's feet: push-off from the right foot for L, else the left; plant from the right for R",
		function()
			expect.equal(DashController.pushoffFoot("L"), "Right")
			for _, key in { "F", "B", "R" } do
				expect.equal(DashController.pushoffFoot(key), "Left")
			end
			expect.equal(DashController.plantFoot("R"), "Right")
			for _, key in { "F", "B", "L" } do
				expect.equal(DashController.plantFoot(key), "Left")
			end
		end
	)

	t.test("the held arm's offset fades in over 0.9 frames and out over the last 3 (avatar.js:160-162)", function()
		expect.near(DashController.holdWeight(0), 0, 1e-9)
		expect.near(DashController.holdWeight(0.45), 0.5, 1e-9)
		expect.near(DashController.holdWeight(5), 1, 1e-9)
		expect.near(DashController.holdWeight(10.5), 0.5, 1e-9)
		expect.near(DashController.holdWeight(12), 0, 1e-9)
	end)

	t.test("the ribbons take the team tint: A Strawberry, B Mint, practice Strawberry", function()
		expect.equal(DashController.tintFor("A"), Palette.DashRibbonStrawberry)
		expect.equal(DashController.tintFor("B"), Palette.DashRibbonMint)
		expect.equal(DashController.tintFor(nil), Palette.DashRibbonStrawberry)
	end)

	t.test("a DashStarted payload needs every field typed and a flat unit dir", function()
		local good = {
			userId = 7,
			dir = Vector3.new(0, 0, -1),
			from = Vector3.new(1, 3, 2),
			to = Vector3.new(1, 3, -12),
			startAt = 50,
		}
		local parsed = DashController.parseDashStarted(good)
		expect.truthy(parsed)
		expect.equal(parsed.userId, 7)
		expect.equal(parsed.to, good.to)
		expect.equal(DashController.parseDashStarted(nil), nil)
		expect.equal(DashController.parseDashStarted("dash"), nil)
		local broken: { [string]: any } =
			{ userId = "7", dir = Vector3.new(0, 1, 0), from = 3, to = false, startAt = 0 / 0 }
		for field, bad in broken do
			local copy = table.clone(good) :: { [string]: any }
			copy[field] = bad
			expect.equal(DashController.parseDashStarted(copy), nil)
		end
	end)
end
