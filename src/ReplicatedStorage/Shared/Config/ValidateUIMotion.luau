--!strict
-- Config/ValidateUIMotion (Shared). UI FINAL R2's part of Config.validate (plan work/ui/PLAN.md R2, the motion kit;
-- F8 and F9): kept apart so Config/init stays under Roblox's 200,000-character script Source limit (the clone tests
-- and the snapshot restore set Source). Pure: require(script)(h, UI, Audio) returns { motion, pitches }, which add
-- human-readable problems through Config/init's own check helpers `h`.
-- The rules: every Config.UI.curves entry a cubic-bezier (x1, x2 in 0..1) and every curve name known; every loop
-- and the nav wiggle <= 3 Hz; the press squash and the "no" shake swing between extremes no faster than 3 Hz (PR4,
-- PR5); every motion `frames` track from 0 to 1 in order; the press squash leaves every kind above 0; the coin
-- flight's count-up outlasting the jitter; the shines; the design effects' counts whole and >= 1 (the box reveal's
-- rays, rings and burst <= 24 moving frames, §9.15), the star share in 0..1; the UI pitches (Config.Audio.uiPitch,
-- the highest coin ping included) inside [pitchMin, pitchMax].
--   motion(problems)                   F9: the curves, the loops, the swings, the tracks, the bars, toggles and
--                                      shines, the coin flight and the design effects
--   pitches(problems, p, low, high)    F8: the UI pitches inside [low, high] and the silent Button kinds

type Problems = { string }

export type Helpers = {
	add: (problems: Problems, message: string) -> (),
	expect: (problems: Problems, ok: boolean, message: string) -> (),
	expectPositive: (problems: Problems, path: string, value: unknown) -> (),
	expectNonNegative: (problems: Problems, path: string, value: unknown) -> (),
	expectCount: (problems: Problems, path: string, value: unknown, min: number) -> (),
	expectBetween: (problems: Problems, path: string, value: unknown, min: number, max: number) -> (),
	expectBoolean: (problems: Problems, path: string, value: unknown) -> (),
	isNumber: (value: unknown) -> boolean,
	show: (value: unknown) -> string,
	studs: (value: number) -> string,
	sortedKeys: (tbl: any) -> { any },
	maxFlickerHz: number,
	feelSlack: number,
}

export type Checks = {
	motion: (problems: Problems) -> (),
	pitches: (problems: Problems, p: string, low: number, high: number) -> (),
}

return function(h: Helpers, UI: any, Audio: any): Checks
	local add, expect, expectPositive, expectNonNegative = h.add, h.expect, h.expectPositive, h.expectNonNegative
	local expectCount, expectBetween, expectBoolean = h.expectCount, h.expectBetween, h.expectBoolean
	local isNumber, show, studs, sortedKeys = h.isNumber, h.show, h.studs, h.sortedKeys
	local MAX_FLICKER_HZ, FEEL_SLACK = h.maxFlickerHz, h.feelSlack

	-- UI FINAL R2: §9.15's box reveal budget, every animated UI frame of it (BoxController :60): the rays picture, the
	-- burst's rings and its pieces.
	local REVEAL_FRAME_MAX = 24
	-- UI FINAL R2: the pose fields of a motion `frames` track (Anim/Tweens.Pose).
	local POSE_FIELDS = { "x", "y", "sx", "sy", "scale", "rot", "alpha" }

	-- UI FINAL R2: a motion `frames` track (Anim/Tweens.keyframes): at least two frames, from at = 0 to at = 1 in
	-- order, every pose field a number.
	local function checkTrack(problems: Problems, path: string, frames: unknown)
		if type(frames) ~= "table" or #(frames :: { any }) < 2 then
			add(problems, `{path} must list at least two frames`)
			return
		end
		local list = frames :: { any }
		expect(
			problems,
			list[1].at == 0 and list[#list].at == 1,
			`{path} must run from 0 to 1 (got {show(list[1].at)} .. {show(list[#list].at)})`
		)
		for index = 2, #list do
			expect(
				problems,
				isNumber(list[index].at) and isNumber(list[index - 1].at) and list[index].at > list[index - 1].at,
				`{path}[{index}].at must be in order (after {show(list[index - 1].at)})`
			)
		end
		for index, frame in list do
			for _, field in POSE_FIELDS do
				if frame[field] ~= nil then
					expect(problems, isNumber(frame[field]), `{path}[{index}].{field} must be a number`)
				end
			end
		end
	end

	-- UI FINAL R2: a design burst's numbers (Config.UI.Fx.sparks or an event's sparks): a whole count >= 1, positive
	-- spreads, sizes and times, the star share in 0..1.
	local function checkSparks(problems: Problems, path: string, sparks: any)
		if sparks.n ~= nil then
			expectCount(problems, `{path}.n`, sparks.n, 1)
		end
		for _, field in { "spread", "size", "ms" } do
			if sparks[field] ~= nil then
				expectPositive(problems, `{path}.{field}`, sparks[field])
			end
		end
		if sparks.stars ~= nil then
			expectBetween(problems, `{path}.stars`, sparks.stars, 0, 1)
		end
	end

	-- UI FINAL R2: a loop of `periodS` (alternate: it swings once a period) at most MAX_FLICKER_HZ (§9.12).
	local function checkLoop(problems: Problems, path: string, periodS: unknown, alternate: boolean?)
		expectPositive(problems, `{path}.periodS`, periodS)
		if isNumber(periodS) and (periodS :: number) > 0 then
			local hz = 1 / ((periodS :: number) * (if alternate then 2 else 1))
			expect(
				problems,
				hz <= MAX_FLICKER_HZ + FEEL_SLACK,
				`{path} loops at {studs(hz)} Hz, above {MAX_FLICKER_HZ} Hz (§9.12)`
			)
		end
	end

	-- UI FINAL R2 (PR4, PR5): the extremes of a one-shot swing (its frame times `ats` but the first and the last, over
	-- `ms`) are at least 1000 / (2 · MAX_FLICKER_HZ) ms apart (no swing between two extremes faster than 3 Hz, §9.12).
	local function checkSwing(problems: Problems, path: string, ms: unknown, ats: { number })
		if not (isNumber(ms) and (ms :: number) > 0) then
			return
		end
		for index = 2, #ats - 2 do
			local gapMs = (ats[index + 1] - ats[index]) * (ms :: number)
			local hz = if gapMs > 0 then 1000 / (2 * gapMs) else math.huge
			expect(
				problems,
				hz <= MAX_FLICKER_HZ + FEEL_SLACK,
				`{path} swings between two extremes {studs(gapMs)} ms apart ({studs(hz)} Hz), above `
					.. `{MAX_FLICKER_HZ} Hz (§9.12)`
			)
		end
	end

	-- UI FINAL R2: every `curve` (and *Curve) string under `tbl` names a Config.UI.curves entry.
	local function checkCurveNames(problems: Problems, path: string, tbl: any, depth: number)
		if type(tbl) ~= "table" or depth > 6 then
			return
		end
		for _, key in sortedKeys(tbl) do
			local value = tbl[key]
			if type(key) == "string" and (key == "curve" or string.sub(key, -5) == "Curve") then
				expect(
					problems,
					type(value) == "string" and UI.curves[value] ~= nil,
					`{path}.{key} = {show(value)} is not a Config.UI.curves name`
				)
			elseif type(value) == "table" then
				checkCurveNames(problems, `{path}.{tostring(key)}`, value, depth + 1)
			end
		end
	end

	-- UI FINAL R2 (the motion kit): every curve four finite numbers with x1 and x2 in 0..1 (a cubic-bezier) and
	-- every curve name known; the idle loops, the other loops and the nav wiggle <= 3 Hz; the press squash and the
	-- "no" shake swing no faster than 3 Hz (PR4, PR5) and the squash leaves every kind above 0; every `frames`
	-- track from 0 to 1 in order; the bars, toggles and shines; the coin flight; the design effects' counts whole
	-- and >= 1 (the box reveal's rays, rings and burst <= 24 moving frames, §9.15) and the star share in 0..1.
	local function checkUIMotionR2(problems: Problems)
		local motion = UI.motion :: any
		local p = "F9: Config.UI.motion"
		for _, name in sortedKeys(UI.curves) do
			local curve = UI.curves[name]
			local path = `F9: Config.UI.curves.{name}`
			local ok = type(curve) == "table" and #curve == 4
			if ok then
				for index = 1, 4 do
					ok = ok and isNumber(curve[index])
				end
			end
			expect(problems, ok, `{path} must be four numbers (a cubic-bezier)`)
			if ok then
				expect(
					problems,
					curve[1] >= 0 and curve[1] <= 1 and curve[3] >= 0 and curve[3] <= 1,
					`{path}: x1 and x2 must be in 0..1 (got {show(curve[1])}, {show(curve[3])})`
				)
			end
		end
		checkCurveNames(problems, p, motion, 0)
		checkCurveNames(problems, "F9: Config.UI.Sticker", UI.Sticker, 0)
		checkCurveNames(problems, "F9: Config.UI.Fx", UI.Fx, 0)

		for _, kind in sortedKeys(motion.idle) do
			checkLoop(problems, `{p}.idle.{kind}`, motion.idle[kind].periodS)
		end
		checkTrack(problems, `{p}.idle.badge.frames`, motion.idle.badge.frames)
		for _, name in sortedKeys(motion.loops) do
			local loop = motion.loops[name]
			checkLoop(problems, `{p}.loops.{name}`, loop.periodS, loop.alternate)
			checkTrack(problems, `{p}.loops.{name}.frames`, loop.frames)
		end
		for _, name in sortedKeys(motion) do
			local entry = motion[name]
			if type(entry) == "table" and entry.frames ~= nil then
				checkTrack(problems, `{p}.{name}.frames`, entry.frames)
			end
		end
		local nav = motion.navWiggle
		expectPositive(problems, `{p}.navWiggle.ms`, nav.ms)
		if isNumber(nav.ms) and nav.ms > 0 then
			-- (n - 1) swings between n angles, two to a cycle.
			local hz = (#nav.angles - 1) * 1000 / (2 * nav.ms)
			expect(
				problems,
				hz <= MAX_FLICKER_HZ + FEEL_SLACK,
				`{p}.navWiggle swings at {studs(hz)} Hz ((angles - 1) · 1000 / (2 · ms)), above {MAX_FLICKER_HZ} Hz `
					.. "(§9.12)"
			)
		end
		expectPositive(problems, `{p}.buttonHover.ms`, motion.buttonHover.ms)
		expectNonNegative(problems, `{p}.buttonHover.filterMs`, motion.buttonHover.filterMs)
		expectPositive(problems, `{p}.buttonHover.brightness`, motion.buttonHover.brightness)
		expectPositive(problems, `{p}.buttonHover.saturate`, motion.buttonHover.saturate)
		for _, kind in sortedKeys(motion.hover) do
			local hover = motion.hover[kind]
			if hover.scale ~= nil then
				expectPositive(problems, `{p}.hover.{kind}.scale`, hover.scale)
			end
		end
		-- The press squash (PR4): its swings and the deepest squash (the largest amount, the most negative
		-- coefficient).
		local press = motion.buttonPress
		local pressAts: { number } = {}
		local lowest = 0
		for _, frame in press.frames do
			table.insert(pressAts, frame.at)
			lowest = math.min(lowest, frame.sx or 0, frame.sy or 0)
		end
		checkSwing(problems, `{p}.buttonPress`, press.ms, pressAts)
		local most = press.amount or 0
		for _, kind in sortedKeys(press.amountByKind) do
			expectPositive(problems, `{p}.buttonPress.amountByKind.{kind}`, press.amountByKind[kind])
			most = math.max(most, (press.amount or 0) * press.amountByKind[kind])
		end
		expect(
			problems,
			isNumber(press.amount) and press.amount > 0 and 1 + most * lowest > 0,
			`{p}.buttonPress.amount ({show(press.amount)}) must be > 0 and leave every kind's squash above 0`
		)
		expect(
			problems,
			press.decoratedAxis == "sx" or press.decoratedAxis == "sy",
			`{p}.buttonPress.decoratedAxis ({show(press.decoratedAxis)}) must be "sx" or "sy"`
		)
		-- The "no" shake (PR5): its steps are evenly spaced over ms.
		local shake = motion.buttonShake
		local shakeAts: { number } = {}
		for index = 1, #shake.steps do
			table.insert(shakeAts, (index - 1) / math.max(1, #shake.steps - 1))
		end
		expect(problems, #shake.steps >= 3, `{p}.buttonShake.steps must list at least 3 steps`)
		checkSwing(problems, `{p}.buttonShake`, shake.ms, shakeAts)
		expectPositive(problems, `{p}.buttonShake.px`, shake.px)
		expectPositive(problems, `{p}.buttonShake.pillPx`, shake.pillPx)

		for _, field in { "ms", "jitterMs", "midScale", "endScale" } do
			expectPositive(problems, `{p}.coinFlight.{field}`, motion.coinFlight[field])
		end
		local flight = motion.coinFlight
		expectBetween(problems, `{p}.coinFlight.midAt`, flight.midAt, 0.01, 0.99)
		expect(
			problems,
			isNumber(flight.arcUpMinPx) and isNumber(flight.arcUpMaxPx) and flight.arcUpMinPx <= flight.arcUpMaxPx,
			`{p}.coinFlight.arcUpMinPx must be <= arcUpMaxPx`
		)
		expect(
			problems,
			isNumber(flight.countTailMs) and isNumber(flight.jitterMs) and flight.countTailMs >= flight.jitterMs,
			`{p}.coinFlight.countTailMs must be >= jitterMs (the count-up must outlast the last coin)`
		)

		-- The sticker motion (bars, toggles, shines): the bars name a known shine; each shine a whole px wide, alpha in
		-- 0..1, at most 3 Hz.
		local sticker = UI.Sticker :: any
		for _, name in sortedKeys(sticker.barShines) do
			local shine = sticker.barShines[name]
			expect(
				problems,
				sticker.bars[name] ~= nil and sticker.shines[shine] ~= nil,
				`F9: Config.UI.Sticker.barShines.{name} must name a bar and a Sticker.shines entry`
			)
		end
		for _, name in sortedKeys(sticker.shines) do
			local shine = sticker.shines[name]
			local path = `F9: Config.UI.Sticker.shines.{name}`
			expectCount(problems, `{path}.px`, shine.px, 1)
			expectBetween(problems, `{path}.alpha`, shine.alpha, 0, 1)
			expectCount(problems, `{path}.overhangPx`, shine.overhangPx, 0)
			checkLoop(problems, path, shine.periodS)
		end

		-- The design effects (Config.UI.Fx): whole counts >= 1, the star share in 0..1, the reveal's frame budget.
		local fx = UI.Fx :: any
		local f = "F9: Config.UI.Fx"
		expectCount(problems, `{f}.jolt.frames`, fx.jolt.frames, 1)
		expectPositive(problems, `{f}.jolt.ms`, fx.jolt.ms)
		checkSparks(problems, `{f}.sparks`, fx.sparks)
		for _, field in { "n", "sizeMin", "sizeSpan", "tall", "ms" } do
			expectPositive(problems, `{f}.rain.{field}`, fx.rain[field])
		end
		expectCount(problems, `{f}.rain.n`, fx.rain.n, 1)
		expectPositive(problems, `{f}.ring.ms`, fx.ring.ms)
		expectPositive(problems, `{f}.ring.size`, fx.ring.size)
		expectPositive(problems, `{f}.float.ms`, fx.float.ms)
		checkTrack(problems, `{f}.float.frames`, fx.float.frames)
		for _, name in sortedKeys(fx.events) do
			local event = fx.events[name]
			local path = `{f}.events.{name}`
			if event.sparks ~= nil then
				checkSparks(problems, `{path}.sparks`, event.sparks)
			end
			for index, ring in event.rings or {} do
				expectPositive(problems, `{path}.rings[{index}].size`, ring.size)
			end
			if event.rain ~= nil then
				expectCount(problems, `{path}.rain`, event.rain, 1)
			end
			if event.coins ~= nil then
				expect(
					problems,
					isNumber(event.coins) and event.coins >= 1 and event.coins <= flight.maxCoins,
					`{path}.coins ({show(event.coins)}) must be 1..coinFlight.maxCoins`
				)
			end
			if event.jolt ~= nil then
				expectPositive(problems, `{path}.jolt`, event.jolt)
			end
		end
		local burst = fx.events.boxBurst
		-- PR18: the rain after the burst (H:830).
		local rain = burst.rarityRain
		expectCount(problems, `{f}.events.boxBurst.rarityRain.n`, rain and rain.n, 1)
		expectCount(problems, `{f}.events.boxBurst.rarityRain.perRarity`, rain and rain.perRarity, 0)
		expectCount(problems, `{f}.events.boxBurst.rarityRain.fromRarity`, rain and rain.fromRarity, 0)
		expect(
			problems,
			rain ~= nil and type(rain.colors) == "table" and #rain.colors >= 1,
			`{f}.events.boxBurst.rarityRain.colors must list at least 1 colour`
		)
		local frames = if isNumber(burst.maxPieces) then 1 + #(burst.rings or {}) + burst.maxPieces else nil
		expect(
			problems,
			frames ~= nil and burst.maxPieces >= 1 and frames <= REVEAL_FRAME_MAX,
			`{f}.events.boxBurst: 1 rays picture + {#(burst.rings or {})} rings + maxPieces ({show(burst.maxPieces)}) `
				.. `= {show(frames)} moving frames, must be <= {REVEAL_FRAME_MAX} (§9.15) with maxPieces >= 1`
		)

		-- UI FINAL R4 (the lobby HUD): Config.UI.Sticker.hud's numbers finite, its alphas, midAt and gradient stops in
		-- 0..1, the compact CTA scale and the toast top positive, and its loops (bob, pulse, float) <= 3 Hz.
		local hud = sticker.hud
		local h4 = "F9: Config.UI.Sticker.hud"
		if type(hud) ~= "table" then
			add(problems, `{h4} is missing`)
			return
		end
		for _, group in sortedKeys(hud) do
			local entry = hud[group]
			if type(entry) == "table" then
				for _, field in sortedKeys(entry) do
					local value = entry[field]
					local path = `{h4}.{group}.{tostring(field)}`
					if type(field) == "string" and (string.sub(field, -5) == "Alpha" or field == "midAt") then
						expectBetween(problems, path, value, 0, 1)
					elseif type(value) == "table" then
						for index, share in value do
							expectBetween(problems, `{path}[{tostring(index)}]`, share, 0, 1) -- gradient stops
						end
					else
						expect(problems, isNumber(value), `{path} must be a finite number (got {show(value)})`)
					end
				end
			else
				expectPositive(problems, `{h4}.{group}`, entry)
			end
		end
		expectPositive(problems, `{h4}.cta.compactScale`, hud.cta and hud.cta.compactScale)
		local loops = {
			{ "nav.bobS", hud.nav and hud.nav.bobS },
			{ "cta.emblemBobS", hud.cta and hud.cta.emblemBobS },
			{ "search.emblemPulseS", hud.search and hud.search.emblemPulseS },
			{ "found.iconPulseS", hud.found and hud.found.iconPulseS },
			{ "grip.boltPulseS", hud.grip and hud.grip.boltPulseS },
			{ "gripFloat.periodS", hud.gripFloat and hud.gripFloat.periodS },
		}
		for _, loop in loops do
			checkLoop(problems, `{h4}.{loop[1]}`, loop[2])
		end
	end

	-- F8: the UI pitches (Config.Audio.uiPitch, plan §2.2); the coin pings top out at 2^((coinSteps - 1) / 12).
	local function checkPitches(problems: Problems, p: string, low: number, high: number)
		local ui = Audio.uiPitch :: any
		for _, kind in sortedKeys(ui.hover) do
			expectBetween(problems, `{p}.uiPitch.hover.{kind}`, ui.hover[kind], low, high)
		end
		for _, name in { "tab", "card", "toggleOn", "toggleOff", "slideFrom" } do
			expectBetween(problems, `{p}.uiPitch.{name}`, ui[name], low, high)
		end
		if isNumber(ui.slideFrom) and isNumber(ui.slideSpan) then
			expectBetween(problems, `{p}.uiPitch.slideFrom + slideSpan`, ui.slideFrom + ui.slideSpan, low, high)
		end
		expectBetween(problems, `{p}.uiPitch.slideStepShare`, ui.slideStepShare, 0, 1)
		expectCount(problems, `{p}.uiPitch.coinSteps`, ui.coinSteps, 1)
		expectPositive(problems, `{p}.uiPitch.slot.semitone`, ui.slot.semitone)
		expectBetween(problems, `{p}.uiPitch.tick.lo`, ui.tick.lo, low, high)
		for _, kind in sortedKeys(Audio.buttonSilentKinds) do
			expectBoolean(problems, `{p}.buttonSilentKinds.{kind}`, Audio.buttonSilentKinds[kind])
		end
		if isNumber(ui.coinSteps) then
			expect(
				problems,
				2 ^ ((ui.coinSteps - 1) / 12) <= high,
				`{p}.uiPitch.coinSteps ({show(ui.coinSteps)}) lifts the last coin ping above pitchMax ({show(high)})`
			)
		end
	end

	return { motion = checkUIMotionR2, pitches = checkPitches }
end
