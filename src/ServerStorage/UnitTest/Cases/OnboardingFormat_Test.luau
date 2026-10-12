--!strict
-- OnboardingFormat_Test: StarterPlayerScripts.Client.UI.OnboardingFormat (the onboarding tip card). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §11.8, §6.10):
--   * the card shows the lowest incomplete Config.Onboarding step; steps complete in any order;
--   * shown only for a ready profile that has not skipped and has a step left;
--   * the welcome card has [Got it] and names the starter; the others have one "Skip tutorial" link;
--   * the squeeze hint follows the input kind; the firstBox step reads {coins}/{goal}: the Snack Box cost for eligible
--     players, the cheapest shop price (with the Shop text and a Shop waypoint) for restricted, unknown or checking;
--   * guidance: waypoints "giftBox" or "shop" / "duel", the "squishies" pulse (equip and inspect); the squeeze step
--     has no waypoint (spec 2026-10-11 §5: its text says squeeze anywhere, so it sends no one to a mat);
--   * replay mode ignores the saved flags (done and skipped) and uses its own local set;
--   * a step whose screen is not registered yet (Inspect before Part 6) is passed over (reading).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local OnboardingFormat = t.requireClient("UI/OnboardingFormat")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Format = t.requireShared("Util/Format")
	local Strings = t.requireShared("Strings")
	local STEPS = Config.Onboarding.Steps

	local function cheapest(): number
		local best = math.huge
		for _, def in Catalog.list() do
			if type(def.shopPrice) == "number" and not def.robuxOnly then
				best = math.min(best, def.shopPrice)
			end
		end
		return best
	end

	-- Every step id before `id` (in Config order) done.
	local function doneBefore(id: string): { [string]: boolean }
		local done = {}
		for _, step in STEPS do
			if step.id == id then
				break
			end
			done[step.id] = true
		end
		return done
	end

	local function allDone(): { [string]: boolean }
		local done = {}
		for _, step in STEPS do
			done[step.id] = true
		end
		return done
	end

	local function ctx(done: { [string]: boolean }, extra: { [string]: any }?): any
		local c: { [string]: any } = {
			onboarding = { v = 1, done = done, skipped = false },
			ready = true,
			policy = "eligible",
			coins = 0,
			input = "keyboard",
		}
		if extra then
			for key, value in extra do
				c[key] = value
			end
		end
		return c
	end

	t.test("the lowest incomplete step, in any completion order", function()
		expect.equal(OnboardingFormat.currentStep({}).id, STEPS[1].id)
		expect.equal(OnboardingFormat.currentStep(nil).id, STEPS[1].id)
		-- Later steps done first: the lowest missing one still shows.
		local done = { [STEPS[1].id] = true, [STEPS[3].id] = true, [STEPS[4].id] = true }
		expect.equal(OnboardingFormat.currentStep(done).id, STEPS[2].id)
		expect.equal(OnboardingFormat.model(ctx(done)).stepId, STEPS[2].id)
		expect.equal(OnboardingFormat.currentStep(allDone()), nil)
		expect.equal(OnboardingFormat.isComplete(allDone()), true)
		expect.equal(OnboardingFormat.isComplete(doneBefore("duel")), false)
	end)

	t.test("welcome: Got it and the starter's name; the others: one skip link", function()
		local model = OnboardingFormat.model(ctx({}))
		expect.equal(model.stepId, "welcome")
		expect.equal(model.gotIt, true)
		expect.equal(model.skip, false)
		local starter = Catalog.get(Catalog.starterId())
		expect.equal(
			model.text,
			Strings.format(Strings.onboarding.welcome, { starterName = Strings.resolve(starter.nameKey) })
		)
		local squeeze = OnboardingFormat.model(ctx(doneBefore("squeeze")))
		expect.equal(squeeze.stepId, "squeeze")
		expect.equal(squeeze.gotIt, false)
		expect.equal(squeeze.skip, true)
	end)

	t.test("squeeze hint follows the input kind; no mat waypoint (squeeze anywhere)", function()
		expect.truthy(string.find(Strings.onboarding.squeeze, "anywhere", 1, true) ~= nil)
		for _, input in { "keyboard", "touch", "gamepad" } do
			local model = OnboardingFormat.model(ctx(doneBefore("squeeze"), { input = input }))
			local hint = (Strings.onboarding.squeezeHint :: any)[input]
			expect.equal(OnboardingFormat.squeezeHint(input), hint)
			expect.equal(model.text, Strings.format(Strings.onboarding.squeeze, { squeezeHint = hint }))
			expect.equal(model.waypoint, nil)
			expect.equal(model.pulse, nil)
		end
	end)

	t.test("firstBox: the Snack Box goal when eligible, the Shop text and price otherwise", function()
		local snack = Boxes.get("snack").cost
		expect.equal(OnboardingFormat.goal("eligible"), snack)
		local eligible = OnboardingFormat.model(ctx(doneBefore("firstBox"), { coins = 150 }))
		expect.equal(eligible.stepId, "firstBox")
		expect.equal(
			eligible.text,
			Strings.format(Strings.onboarding.firstBox, { coins = Format.coins(150), goal = Format.coins(snack) })
		)
		expect.equal(eligible.waypoint, "giftBox")
		for _, policy in { "restricted", "unknown", "checking" } do
			expect.equal(OnboardingFormat.goal(policy), cheapest())
			local model = OnboardingFormat.model(ctx(doneBefore("firstBox"), { policy = policy, coins = 150 }))
			expect.equal(
				model.text,
				Strings.format(
					Strings.onboarding.firstBoxShop,
					{ coins = Format.coins(150), goal = Format.coins(cheapest()) }
				)
			)
			expect.equal(model.waypoint, "shop")
		end
		-- {coins} is capped at the goal.
		local rich = OnboardingFormat.model(ctx(doneBefore("firstBox"), { coins = 999_999 })) -- above the 150K Snack Box
		expect.equal(
			rich.text,
			Strings.format(Strings.onboarding.firstBox, { coins = Format.coins(snack), goal = Format.coins(snack) })
		)
	end)

	t.test("guidance: the Squishies tile pulses for equip and inspect, a waypoint to the duel podium", function()
		expect.equal(OnboardingFormat.model(ctx(doneBefore("equip"))).pulse, "squishies")
		expect.equal(OnboardingFormat.model(ctx(doneBefore("equip"))).waypoint, nil)
		-- Lobby HUD (spec 2026-10-11): no dock, so Inspect is reached through the Squishies tile (its list's Inspect).
		expect.equal(OnboardingFormat.model(ctx(doneBefore("inspect"))).pulse, "squishies")
		local duel = OnboardingFormat.model(ctx(doneBefore("duel")))
		expect.equal(duel.waypoint, "duel")
		expect.equal(duel.text, Strings.onboarding.duel)
	end)

	t.test("a step whose screen is not there yet is passed over", function()
		local skipInspect = { inspect = true }
		local equipDone = doneBefore("inspect")
		expect.equal(OnboardingFormat.currentStep(equipDone).id, "inspect")
		expect.equal(OnboardingFormat.currentStep(equipDone, skipInspect).id, "duel")
		expect.equal(OnboardingFormat.model(ctx(equipDone, { unavailable = skipInspect })).stepId, "duel")
		-- Everything else done: complete while Inspect is unavailable, not once it exists.
		local allButInspect: { [string]: boolean } = {}
		for id in allDone() do
			if id ~= "inspect" then
				allButInspect[id] = true
			end
		end
		expect.equal(OnboardingFormat.isComplete(allButInspect, skipInspect), true)
		expect.equal(OnboardingFormat.model(ctx(allButInspect, { unavailable = skipInspect })), nil)
		expect.equal(OnboardingFormat.isComplete(allButInspect), false)
		expect.equal(OnboardingFormat.model(ctx(allButInspect)).stepId, "inspect")
	end)

	t.test("hidden: not ready, skipped, complete, or a wrong-shaped state shows the first step", function()
		expect.equal(OnboardingFormat.model(ctx({}, { ready = false })), nil)
		expect.equal(OnboardingFormat.visible(ctx({}, { ready = false })), false)
		local skippedCtx = ctx({})
		skippedCtx.onboarding.skipped = true
		expect.equal(OnboardingFormat.model(skippedCtx), nil)
		expect.equal(OnboardingFormat.model(ctx(allDone())), nil)
		expect.equal(OnboardingFormat.visible(ctx(allDone())), false)
		-- A wrong shape counts as nothing done and not skipped.
		expect.equal(OnboardingFormat.model(ctx({}, { onboarding = "x" })).stepId, "welcome")
		expect.deepEqual(OnboardingFormat.done({ done = { welcome = true, squeeze = "yes" } }), { welcome = true })
	end)

	t.test("replay ignores the saved flags and uses its own local set", function()
		-- Complete and skipped on the server: a replay starts again at the first step.
		local saved = ctx(allDone())
		saved.onboarding.skipped = true
		expect.equal(OnboardingFormat.model(saved), nil)
		saved.replay = {}
		local first = OnboardingFormat.model(saved)
		expect.equal(first.stepId, "welcome")
		saved.replay = { welcome = true }
		expect.equal(OnboardingFormat.model(saved).stepId, STEPS[2].id)
		saved.replay = allDone()
		expect.equal(OnboardingFormat.model(saved), nil)
		-- The saved state itself was never touched.
		expect.equal(saved.onboarding.skipped, true)
		expect.deepEqual(OnboardingFormat.done(saved.onboarding), allDone())
		-- Still needs a ready profile.
		local notReady = ctx({}, { ready = false, replay = {} })
		expect.equal(OnboardingFormat.model(notReady), nil)
	end)
end
