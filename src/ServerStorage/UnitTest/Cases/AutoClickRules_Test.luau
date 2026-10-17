--!strict
-- AutoClickRules_Test: unit tests for ServerScriptService.Server.Logic.AutoClickRules (auto-clicker check, 2026-10-16).
-- Pure: every case passes its own copy of Config.Net.AutoClick and its own arrival times (os.clock seconds).
-- Contract:
--   * review fix (2026-10-16, job autoclick): speed alone is never a catch (no rule A any more): a window as fast as
--     maxPerSecond or faster is the client ceiling's rhythm and is never judged, however steady (17.5-25 a second, and
--     a 1000-a-second macro held at the ceiling); people mashing 17-25 a second (one finger, or F + E + a click at
--     once) through the client's 18-a-second ceiling for 10 minutes never are; just under maxPerSecond (16.5 a second)
--     a machine still is;
--   * rule B ("regular"): a window of windowIntervals gaps of one burst with a mean gap <= maxMeanGapSeconds is judged
--     once (tumbling windows); a perfectly regular stream is caught at its first full window, also when its times are
--     rounded to 60 Hz server frames; human-like tapping (12% timing noise, a slowly drifting tempo) for 20 minutes
--     never is; a pause over burstGapSeconds starts the window again; a slower stream (a held squeeze's 0.45 s) is
--     never judged however regular;
--   * reset forgets everything;
--   * the ladder: memoryStep reads a saved warning or kick only while it is younger than memorySeconds, a ban forever
--     (batch B, owner 2026-10-17; anything malformed -> 0), nextStep is one past the higher of this visit's step and
--     the remembered one (at most the ladder's last step, MAX_STEP 5), actionFor names the steps warn / kick / ban (3
--     and up); banSeconds: 1 day for the 1st ban, then 7 days, then 30 days, then 30 days again.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local T0 = 1000.25 -- os.clock seconds, mid-second on purpose
local NOW = 1_800_000_000 -- os.time

return function(t: Context)
	local expect = t.expect
	local AutoClickRules = t.requireServer("Logic/AutoClickRules")
	local Config = t.requireShared("Config")

	local function rules(overrides: { [string]: any }?): any
		local copy = table.clone(Config.Net.AutoClick)
		if overrides then
			for key, value in overrides do
				copy[key] = value
			end
		end
		return copy
	end

	-- Feeds `times` (ascending) to a fresh State; returns the first verdict and the index of its request (or nil).
	local function firstVerdict(cfg: any, times: { number }): (any, number?)
		local state = AutoClickRules.newState(cfg)
		for i, at in times do
			local verdict = AutoClickRules.observe(state, at, cfg)
			if verdict then
				return verdict, i
			end
		end
		return nil, nil
	end

	-- `count` arrival times `gap` seconds apart from T0, each passed through `shape` (rounding, noise) when given.
	local function steady(count: number, gap: number, shape: ((at: number, i: number) -> number)?): { number }
		local times = table.create(count)
		for i = 1, count do
			local at = T0 + (i - 1) * gap
			times[i] = if shape then shape(at, i) else at
		end
		return times
	end

	-- Rounds a time up to the next 60 Hz server frame (Roblox runs a remote's handler on a frame step).
	local function onFrame(at: number): number
		return math.ceil(at * 60) / 60
	end

	-- A deterministic Park-Miller generator in [0, 1) (no math.random: the cases never depend on the run).
	local function generator(seed: number): () -> number
		local s = seed
		return function(): number
			s = (s * 16807) % 2147483647
			return s / 2147483647
		end
	end

	-- A person tapping `perSecond` a second for `seconds`: each gap has about `cv` timing noise (a sum of uniforms) around
	-- a tempo that wanders slowly (mean-reverting, about 3%, ~20 taps of memory), rounded to 60 Hz frames.
	local function person(perSecond: number, cv: number, seconds: number, seed: number): { number }
		local rand = generator(seed)
		local times = {}
		local at, drift = T0, 0
		local base = 1 / perSecond
		while at < T0 + seconds do
			drift += -drift / 20 + (rand() + rand() + rand() - 1.5) * 0.03 * 0.5
			local mu = base * (1 + drift)
			local noise = (rand() + rand() + rand() + rand() - 2) * math.sqrt(3) -- about unit variance
			at += math.max(0.02, mu * (1 + cv * noise))
			table.insert(times, onFrame(at))
		end
		return times
	end

	-- The client ceiling (review fix 2026-10-16) ------------------------------------------------------------------------

	-- SqueezeController's ceiling on presses over the paid cap: a press (already on a frame) goes when fewer than
	-- `capacity` sends fall inside the last second (underCap with a 1 s window), else it only squishes on screen.
	local function throughCeiling(presses: { number }, capacity: number): { number }
		local sent = {}
		for _, at in presses do
			local inside = 0
			for i = #sent, 1, -1 do
				if sent[i] > at - 1 then
					inside += 1
				else
					break
				end
			end
			if inside < capacity then
				table.insert(sent, at)
			end
		end
		return sent
	end

	-- `sources` people pressing at once (F, E, a click), each `perSecond` with `cv` noise, merged in time order.
	local function mashing(sources: number, perSecond: number, cv: number, seconds: number, seed: number): { number }
		local all = {}
		for s = 1, sources do
			for _, at in person(perSecond, cv, seconds, seed + s) do
				table.insert(all, at)
			end
		end
		table.sort(all)
		return all
	end

	t.test(
		"speed alone is never a catch: the ceiling's rhythm (17.5-25 a second, a held-back macro) is not judged",
		function()
			local cfg = rules()
			for _, perSecond in { 17.5, 18, 19, 25 } do
				if firstVerdict(cfg, steady(math.floor(perSecond * 600), 1 / perSecond)) ~= nil then
					error(`a perfectly steady {perSecond}/s was caught`) -- 10 minutes
				end
			end
			-- A 1000-a-second macro, held at the client's ceiling: its sends have the ceiling's rhythm, not its own.
			local macro = throughCeiling(steady(1000 * 120, 0.001, onFrame), cfg.clientPressesPerSecond)
			expect.truthy(#macro >= 120 * (cfg.clientPressesPerSecond - 1))
			expect.equal((firstVerdict(cfg, macro)), nil)
			-- Just under maxPerSecond a machine is still judged and caught.
			local verdict = firstVerdict(cfg, steady(2000, 1 / 16.5))
			expect.truthy(verdict ~= nil)
			expect.equal(verdict.rule, "regular")
			expect.truthy(verdict.meanGap > 1 / cfg.maxPerSecond)
		end
	)

	t.test(
		"people mashing 17-25 a second (one finger, or F + E + a click) through the ceiling are never caught",
		function()
			local cfg = rules()
			local cases = {
				{ sources = 1, perSecond = 17.5, cv = 0.08 },
				{ sources = 1, perSecond = 20, cv = 0.12 },
				{ sources = 1, perSecond = 25, cv = 0.2 },
				{ sources = 2, perSecond = 10, cv = 0.08 }, -- F + E
				{ sources = 2, perSecond = 12, cv = 0.12 },
				{ sources = 3, perSecond = 7, cv = 0.12 }, -- F + E + a click
				{ sources = 3, perSecond = 8.3, cv = 0.2 },
			}
			for i, case in cases do
				local presses = mashing(case.sources, case.perSecond, case.cv, 600, 2000 + 10 * i)
				local verdict = firstVerdict(cfg, throughCeiling(presses, cfg.clientPressesPerSecond))
				if verdict ~= nil then
					error(`{case.sources} x {case.perSecond}/s (cv {case.cv}) was caught: spread {verdict.value}`)
				end
			end
		end
	)

	-- Rule B ------------------------------------------------------------------------------------------------------------

	t.test("rule B: a perfectly regular 10 a second is caught as machine-regular at its first full window", function()
		local cfg = rules()
		local verdict, index = firstVerdict(cfg, steady(2000, 0.1))
		expect.truthy(verdict ~= nil)
		expect.equal(verdict.rule, "regular")
		expect.equal(index, cfg.windowIntervals + 1)
		expect.truthy(verdict.value <= cfg.maxBlockSpreadSeconds)
		expect.equal(verdict.limit, cfg.maxBlockSpreadSeconds)
		expect.equal(verdict.count, cfg.windowIntervals)
		expect.near(verdict.meanGap, 0.1, 1e-6)
		expect.near(verdict.seconds, cfg.windowIntervals * 0.1, 1e-6)
	end)

	t.test("rule B: an auto-clicker on 60 Hz server frames (a 93.7 ms period) is still caught", function()
		local cfg = rules()
		local verdict = firstVerdict(cfg, steady(3 * cfg.windowIntervals + 1, 0.0937, onFrame))
		expect.truthy(verdict ~= nil)
		expect.equal(verdict.rule, "regular")
	end)

	t.test("rule B: people tapping 6-14 a second with 12% noise for 20 minutes are never caught", function()
		local cfg = rules()
		for i, perSecond in { 6, 8, 10, 12, 14 } do
			local verdict = firstVerdict(cfg, person(perSecond, 0.12, 1200, 1000 + i))
			if verdict ~= nil then
				error(`{perSecond}/s was caught: {verdict.rule} {verdict.value}`)
			end
		end
	end)

	t.test("rule B: a pause over burstGapSeconds starts the window again", function()
		local cfg = rules()
		local gaps = cfg.windowIntervals
		local times = steady(gaps, 0.1) -- gaps - 1 gaps: one short of a window
		local resume = times[#times] + cfg.burstGapSeconds + 0.5
		for i = 1, gaps do
			table.insert(times, resume + (i - 1) * 0.1)
		end
		expect.equal((firstVerdict(cfg, times)), nil) -- neither run fills a window
		table.insert(times, resume + gaps * 0.1)
		local verdict, index = firstVerdict(cfg, times)
		expect.truthy(verdict ~= nil)
		expect.equal(index, #times)
	end)

	t.test("rule B: a held squeeze's rhythm (0.45 s) is never judged, however regular", function()
		local cfg = rules()
		expect.truthy(cfg.maxMeanGapSeconds < Config.Grip.Hold.repeatSeconds)
		expect.equal((firstVerdict(cfg, steady(math.floor(1800 / 0.45), Config.Grip.Hold.repeatSeconds))), nil)
		expect.equal((firstVerdict(cfg, steady(4000, cfg.maxMeanGapSeconds + 0.01))), nil)
	end)

	t.test("reset forgets the window", function()
		local cfg = rules()
		local state = AutoClickRules.newState(cfg)
		local times = steady(cfg.windowIntervals, 0.1)
		for _, at in times do
			expect.equal(AutoClickRules.observe(state, at, cfg), nil)
		end
		AutoClickRules.reset(state, cfg)
		expect.equal(#state.window, 0)
		-- One request later there is no window to judge (it would have been caught without the reset).
		expect.equal(AutoClickRules.observe(state, times[#times] + 0.1, cfg), nil)
	end)

	-- The ladder --------------------------------------------------------------------------------------------------------

	t.test("memoryStep: a saved strike counts while younger than memorySeconds; anything malformed is 0", function()
		local cfg = rules()
		local memory = cfg.memorySeconds
		expect.equal(AutoClickRules.memoryStep(nil, NOW, cfg), 0)
		expect.equal(AutoClickRules.memoryStep("garbage", NOW, cfg), 0)
		expect.equal(AutoClickRules.memoryStep({ step = 0, at = 0 }, NOW, cfg), 0) -- the default: no strike
		expect.equal(AutoClickRules.memoryStep({ step = 2, at = NOW - 100 }, NOW, cfg), 2)
		expect.equal(AutoClickRules.memoryStep({ step = 2, at = NOW - memory + 1 }, NOW, cfg), 2)
		expect.equal(AutoClickRules.memoryStep({ step = 2, at = NOW - memory }, NOW, cfg), 0) -- a day on: forgotten
		expect.equal(AutoClickRules.memoryStep({ step = 9, at = NOW }, NOW, cfg), AutoClickRules.MAX_STEP)
		-- Batch B (owner 2026-10-17): a ban is never forgotten, however old (its next catch is a longer ban).
		expect.equal(AutoClickRules.memoryStep({ step = 3, at = NOW - memory }, NOW, cfg), 3)
		expect.equal(AutoClickRules.memoryStep({ step = 4, at = NOW - 365 * 86400 }, NOW, cfg), 4)
		expect.equal(AutoClickRules.memoryStep({ step = 3, at = 0 / 0 }, NOW, cfg), 0) -- still never on a broken one
		expect.equal(AutoClickRules.memoryStep({ step = 1.5, at = NOW }, NOW, cfg), 0)
		expect.equal(AutoClickRules.memoryStep({ step = 1, at = 0 / 0 }, NOW, cfg), 0)
		expect.equal(AutoClickRules.memoryStep({ step = "2", at = NOW }, NOW, cfg), 0)
		expect.equal(AutoClickRules.memoryStep({ step = 1, at = NOW + 60 }, NOW, cfg), 1) -- another server's clock
	end)

	t.test(
		"nextStep: one past the higher of this visit and the saved strike, at most MAX_STEP; actionFor names them",
		function()
			local cfg = rules()
			local recent = function(step: number): any
				return { step = step, at = NOW - 60 }
			end
			local old = { step = 2, at = NOW - cfg.memorySeconds - 1 }
			expect.equal(AutoClickRules.nextStep(0, nil, NOW, cfg), 1) -- first catch: warn
			expect.equal(AutoClickRules.nextStep(1, nil, NOW, cfg), 2) -- again in the same visit: kick
			expect.equal(AutoClickRules.nextStep(0, recent(1), NOW, cfg), 2) -- warned, rejoined within a day: kick
			expect.equal(AutoClickRules.nextStep(0, recent(2), NOW, cfg), 3) -- kicked, rejoined within a day: ban
			expect.equal(AutoClickRules.nextStep(1, recent(2), NOW, cfg), 3)
			expect.equal(AutoClickRules.nextStep(2, recent(1), NOW, cfg), 3)
			expect.equal(AutoClickRules.nextStep(0, old, NOW, cfg), 1) -- more than a day ago: back to a warning
			-- Batch B (owner 2026-10-17): after a ban the next catch is the next, longer ban, even a year later; the
			-- ladder's last ban repeats.
			local banned = function(step: number): any
				return { step = step, at = NOW - 365 * 86400 }
			end
			expect.equal(AutoClickRules.nextStep(0, banned(3), NOW, cfg), 4)
			expect.equal(AutoClickRules.nextStep(0, banned(4), NOW, cfg), 5)
			expect.equal(AutoClickRules.nextStep(0, banned(5), NOW, cfg), 5)
			expect.equal(AutoClickRules.nextStep(3, recent(3), NOW, cfg), 4)
			expect.equal(AutoClickRules.MAX_STEP, AutoClickRules.BAN_STEP + #cfg.laterBanSeconds)
			expect.equal(AutoClickRules.MAX_STEP, 5)
			expect.equal(AutoClickRules.actionFor(1), "warn")
			expect.equal(AutoClickRules.actionFor(2), "kick")
			expect.equal(AutoClickRules.actionFor(3), "ban")
			expect.equal(AutoClickRules.actionFor(5), "ban")
			-- Without longer bans the 1st ban repeats.
			local flat = rules({ laterBanSeconds = {} })
			expect.equal(AutoClickRules.nextStep(0, banned(3), NOW, flat), 3)
		end
	)

	-- Batch B (owner 2026-10-17, e.g. 1 day, then 7 days, then 30 days [P]).
	t.test("banSeconds: the 1st ban banSeconds, then laterBanSeconds in turn, the last one again", function()
		local cfg = rules()
		expect.equal(cfg.banSeconds, 86400)
		expect.deepEqual(cfg.laterBanSeconds, { 604800, 2592000 })
		expect.equal(AutoClickRules.banSeconds(3, cfg), 86400)
		expect.equal(AutoClickRules.banSeconds(4, cfg), 604800)
		expect.equal(AutoClickRules.banSeconds(5, cfg), 2592000)
		expect.equal(AutoClickRules.banSeconds(9, cfg), 2592000)
		expect.equal(AutoClickRules.banSeconds(4, rules({ laterBanSeconds = {} })), 86400)
		expect.equal(AutoClickRules.banSeconds(4, rules({ laterBanSeconds = "garbage" })), 86400)
		expect.equal(AutoClickRules.banSeconds(5), 2592000) -- the live config
	end)
end
