--!strict
-- SqueezeFeel_Test: unit tests for StarterPlayerScripts.Client.Controllers.SqueezeFeel, the squeeze glue on the held
-- squishy rig (squishy overhaul spec 2026-10-09 §3.2). Server only (ServerStorage.UnitTest). Edit mode: no held model
-- exists, so play() is not called; the pure helpers are driven with real SquishRig rigs.
-- Contract:
--   * every timing point stays exactly as today: the squish sound at the end of anticipation (70 ms), the puffs at
--     peak compression (the end of the widening phase), the Exclusive steam at the release start and the release
--     sound and pop at the release pop end (390 ms; 430 ms for Uncommon and Epic), all from the rig's events, once
--     each, also across a clamped 1/20 s dt; the hold-to-squeeze rhythm (Grip.Hold.repeatSeconds) is never shorter;
--   * another player's squeeze plays the sounds and its puffs, never the steam or the release pop;
--   * startKind on the rig: an own press before the pop end merges ("interrupt"), from the pop end on it restarts;
--     another player's waits ("busy") until the pop end; interruptFx merges the cut squeeze's release pop and, at most
--     once per release pop, its puffs;
--   * plan: the rarity's puffs and Dragon's steam hook; the old fast extras are gone (no flutter, no Epic jiggle).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FRAME = 1 / 60
local FINE_STEP = 1 / 240

return function(t: Context)
	local SqueezeFeel = t.requireClient("Controllers/SqueezeFeel")
	local SquishRig = t.requireClient("Anim/SquishRig")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local expect = t.expect
	local squeeze = Config.Anim.squeeze

	-- Today's phase windows (Config.Anim.squeeze.phases).
	local window: { [string]: { number } } = {}
	for _, phase in squeeze.phases do
		window[phase.name] = { phase.startMs, phase.endMs }
	end

	local function rigFor(def: any): any
		local blueprint = Blueprints[def.blueprintId]
		return SquishRig.new(blueprint.motion, {
			axis = def.anim.squeezeAxis,
			rarity = def.rarity,
			sections = blueprint.sections,
			foamRecoveryT = def.anim.foamRecoveryT,
			seed = 7,
		})
	end

	-- Steps one tap on `def`'s rig with `dt` and records when each effect played (ms from the tap), and how often.
	local function trace(def: any, dt: number, other: boolean): { [string]: { number } }
		local rig = rigFor(def)
		local out = SquishRig.newOut()
		local seen: { [string]: { number } } =
			{ squishSound = {}, puffs = {}, steam = {}, releaseSound = {}, releasePop = {} }
		rig:tap()
		local tMs = 0
		for _ = 1, math.ceil(1.5 / dt) do
			rig:step(dt, out)
			tMs += dt * 1000
			local squish, puffs, steam, release, pop = SqueezeFeel.effects(out.events, other)
			local played: { [string]: boolean } =
				{ squishSound = squish, puffs = puffs, steam = steam, releaseSound = release, releasePop = pop }
			for name, on in played do
				if on then
					table.insert(seen[name], tMs)
				end
			end
		end
		return seen
	end

	t.test("every timing point stays exactly as today, per rarity", function()
		expect.equal(squeeze.squishSoundAtMs, window.compression[1])
		for _, def in Catalog.list() do
			local extra = squeeze.flourish[def.rarity].wideningExtraMs or 0
			local timing = SqueezeFeel.timing(def)
			expect.equal(timing.anticipationEndMs, squeeze.squishSoundAtMs)
			expect.equal(timing.peakMs, window.widening[2] + extra)
			expect.equal(timing.releaseStartMs, window.releasePop[1] + extra)
			expect.equal(timing.popEndMs, window.releasePop[2] + extra)
			-- Hold-to-squeeze repeats one full squeeze: never before the release pop end.
			expect.truthy(Config.Grip.Hold.repeatSeconds * 1000 >= timing.popEndMs)
		end
		expect.equal(SqueezeFeel.timing(Catalog.get("kitty_bread")).popEndMs, 390)
		expect.equal(SqueezeFeel.timing(Catalog.get("butter")).popEndMs, 430)
		expect.equal(SqueezeFeel.timing(Catalog.get("bird")).popEndMs, 430)
		expect.equal(SqueezeFeel.timing(Catalog.get("dragon")).popEndMs, 390)
	end)

	t.test("one tap: each effect once, at its timing point, from the rig's events (60 fps and 1/20 s)", function()
		for _, id in { "kitty_bread", "mochi_fox", "cloud_bunny", "dragon" } do
			local def = Catalog.get(id)
			local timing = SqueezeFeel.timing(def)
			for _, dt in { FRAME, Config.Anim.Scheduler.maxDt } do
				local seen = trace(def, dt, false)
				local label = `{id} at dt {dt}`
				local points: { [string]: number } = {
					squishSound = timing.anticipationEndMs,
					puffs = timing.peakMs,
					steam = timing.releaseStartMs,
					releaseSound = timing.popEndMs,
					releasePop = timing.popEndMs,
				}
				for name, at in points do
					-- (steam is the release start crossed; the glue emits it only when plan(def).steam has a hook)
					local times = seen[name]
					if #times ~= 1 then
						error(`{label}: {name} played {#times} times`)
					end
					-- Played on the first step that reaches its point.
					if not (times[1] >= at - 1e-6 and times[1] < at + dt * 1000 + 1e-6) then
						error(`{label}: {name} at {times[1]} ms, its point is {at} ms`)
					end
				end
			end
		end
	end)

	t.test("another player's squeeze plays the sounds and its puffs, never the steam or the release pop", function()
		local seen = trace(Catalog.get("dragon"), FRAME, true)
		expect.equal(#seen.squishSound, 1)
		expect.equal(#seen.puffs, 1)
		expect.equal(#seen.releaseSound, 1)
		expect.equal(#seen.steam, 0)
		expect.equal(#seen.releasePop, 0)
	end)

	t.test("startKind on the rig: an own press before the pop end merges; from the pop end on it restarts", function()
		local def = Catalog.get("butter") -- Uncommon: pop end 430 ms
		local rig = rigFor(def)
		local out = SquishRig.newOut()
		local popEnd = rig.timing.popEndMs
		local function kindNow(own: boolean): string
			return SqueezeFeel.startKind(rig:elapsedMs(), popEnd, own, rig:isRecovering())
		end
		expect.equal(kindNow(true), "start") -- nothing plays
		rig:tap()
		local tMs = 0
		while tMs < popEnd - 20 do
			rig:step(FINE_STEP, out)
			tMs += FINE_STEP * 1000
			expect.equal(kindNow(true), "interrupt")
			expect.equal(kindNow(false), "busy")
		end
		-- In [releaseStart, popEnd) too: still a merge, never a second pop.
		expect.truthy(tMs >= rig.timing.releaseStartMs)
		while not rig:isRecovering() do
			rig:step(FINE_STEP, out)
			tMs += FINE_STEP * 1000
		end
		expect.truthy(tMs >= popEnd - 1e-6)
		expect.equal(kindNow(true), "restart")
		expect.equal(kindNow(false), "restart")
		-- Settled: nothing plays any more.
		for _ = 1, 600 do
			rig:step(FRAME, out)
		end
		expect.equal(rig:elapsedMs(), nil)
		expect.equal(kindNow(false), "start")
	end)

	t.test("startKind: an own press mid-squeeze restarts at once; another player's waits for the pop end", function()
		local endMs = 390
		expect.equal(SqueezeFeel.startKind(nil, endMs, true, false), "start")
		expect.equal(SqueezeFeel.startKind(nil, endMs, false, false), "start")
		for _, tMs in { 0, 50, 200, endMs - 1 } do
			expect.equal(SqueezeFeel.startKind(tMs, endMs, true, false), "interrupt")
			expect.equal(SqueezeFeel.startKind(tMs, endMs, false, false), "busy")
		end
		for _, tMs in { endMs, endMs + 300 } do
			expect.equal(SqueezeFeel.startKind(tMs, endMs, true, true), "restart")
			expect.equal(SqueezeFeel.startKind(tMs, endMs, false, true), "restart")
		end
		-- An own squeeze past endMs whose step has not played its pop yet still merges it (the 8th's big pop too).
		for _, tMs in { endMs, endMs + 5, endMs + 16 } do
			expect.equal(SqueezeFeel.startKind(tMs, endMs, true, false), "interrupt")
			expect.equal(SqueezeFeel.startKind(tMs, endMs, false, false), "restart")
		end
	end)

	t.test("interruptFx: a cut squeeze merges its release pop and, once per release pop, its puffs", function()
		local small = { streak = 3, pitch = 1.06, variance = 0.01, bigPop = false, sparkles = 2 }
		local big = { streak = 8, pitch = 1.03, variance = 0.01, bigPop = true, sparkles = 4 }
		local gap = 0.39
		expect.deepEqual(SqueezeFeel.interruptFx(small, false, 6, 1, gap), { sparkles = 2, bigPop = false, puffs = 6 })
		-- The 8th squeeze's big pop still comes when the 9th press cuts it short.
		expect.deepEqual(SqueezeFeel.interruptFx(big, false, 6, 0.1, gap), { sparkles = 4, bigPop = true, puffs = 0 })
		-- Puffs already out at peak compression, or a burst less than one release pop ago: none now.
		expect.equal(SqueezeFeel.interruptFx(small, true, 6, 1, gap).puffs, 0)
		expect.equal(SqueezeFeel.interruptFx(small, false, 6, gap - 0.01, gap).puffs, 0)
		expect.equal(SqueezeFeel.interruptFx(small, false, 6, gap, gap).puffs, 6)
		-- Not an own squeeze (no beat): nothing.
		expect.deepEqual(SqueezeFeel.interruptFx(nil, false, 6, 1, gap), { sparkles = 0, bigPop = false, puffs = 0 })
	end)

	t.test("plan: the rarity's puffs and Dragon's steam hook; no flutter and no Epic jiggle any more", function()
		for _, def in Catalog.list() do
			local flourish = squeeze.flourish[def.rarity]
			local plan = SqueezeFeel.plan(def)
			expect.equal(plan.particles, flourish.particles)
			local hook = if flourish.useSqueezeFx and def.anim.squeezeFx
				then squeeze.squeezeFx[def.anim.squeezeFx]
				else nil
			expect.equal(plan.steam, hook)
			if def.rarity == "Exclusive" and hook == nil then
				error(`{def.id}: an Exclusive without its squeezeFx hook`)
			end
		end
		expect.equal(SqueezeFeel.plan(Catalog.get("dragon")).steam, squeeze.squeezeFx.dragon_steam)
		for _, fx in squeeze.squeezeFx do
			expect.equal((fx :: any).flutterAmplitude, nil)
			expect.equal((fx :: any).flutterHz, nil)
			expect.truthy(fx.steamPuffs >= 0 and fx.rigidity >= 0)
		end
		for _, flourish in squeeze.flourish do
			expect.equal((flourish :: any).jiggle, nil)
		end
	end)
end
