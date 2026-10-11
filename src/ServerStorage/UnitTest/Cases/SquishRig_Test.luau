--!strict
-- SquishRig_Test: unit tests for StarterPlayerScripts.Client.Anim.SquishRig (squishy overhaul spec 2026-10-09 §3.2,
-- §6). Server only (ServerStorage.UnitTest). Pure: the rig makes no instances, so nothing is built here.
-- Contract: the press keeps Config.Anim.squeeze.phases scaled to the toy (c' = 1 - (1 - c)(1 - depth)/(1 - deepest c),
-- w = 1 + (1 - c')·widen) and reaches depth by the release start; one-shot events (squish, peak, releaseStart, popEnd)
-- fire once each, in order, at the Config phase times, also with a clamped 1/20 s dt; the release pop and `recovering`
-- start at popEnd, then the toy's spring (ω = √kRel, ζ = cRel/(2ω)); a tap restarts from the current state without a
-- jump; one `out` table per rig (no table per step); every motion <= 3 Hz; sleep at rest and determinism with a seed;
-- the squish face (in below 0.86, out above 0.90, each state held >= 0.2 s), face priority and the Grip rule; blinks
-- (2-5 s apart, 0.14 s, shut to 0.12); ReducedMotion (SmoothDamp with foamRecoveryT, no jiggle, sections, twist, blink
-- or flight extras); the release kick by rarity and the hit boing peak 0.15; press-and-hold, hold(c), sections, detail
-- levels, flight; reset(); extremes() = Kit.extremes and flightPose() keeps the face leading for every style.
-- First person (spec 2026-10-10 §3.4, §3.5): setAxis and press(axis) switch the squeeze axis only at rest (axis() says
-- the axis it squeezes on now); the shown S never jumps more than 0.02 between steps over random sequences of
-- setAxis, press, hold, tap, endPress and release; press() then endPress() at 10-300 ms gives the same y(t), events,
-- face and twist as tap() for every rarity (also from a squish face); endPress past the release start is release();
-- endPress and release do nothing outside a press; squeezeY() is the squeeze channel (the hold included).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TAU = 2 * math.pi
local FINE = 1 / 240 -- small steps for timing checks
local FRAME = 1 / 60
local F32 = 1e-4 -- Vector3 components are float32

-- Kitty Bread's §4 row (Common, foam).
local KITTY = {
	squeeze = { depth = 0.6, widen = 0.72, kRel = 34, cRel = 8.5 },
	feel = "foam",
	flight = { style = "tumble" },
}
-- Mochi Fox's §4 row (Uncommon, mochi, tumble + pulse).
local MOCHI = {
	squeeze = { depth = 0.55, widen = 0.8, kRel = 26, cRel = 8 },
	feel = "mochi",
	flight = { style = "tumble", pulse = 1.15 },
}
-- A jelly toy (Strawberry Frog's row).
local JELLY = {
	squeeze = { depth = 0.62, widen = 0.66, kRel = 52, cRel = 8 },
	feel = "jelly",
	flight = { style = "hop" },
}

-- Ears and a tail: slot order is the sorted names (EarL, EarR, Tail).
local SECTIONS = {
	EarL = { pivot = Vector3.new(-0.3, 0.4, 0), axis = "Z", amp = 1.6, flap = { deg = 20 } },
	EarR = { pivot = Vector3.new(0.3, 0.4, 0), axis = "Z", amp = 1.6, sign = -1, flap = { deg = 20 } },
	Tail = { pivot = Vector3.new(0, 0, 0.5), axis = "X", amp = 2.0 },
}

return function(t: Context)
	local SquishRig = t.requireClient("Anim/SquishRig")
	local Config = t.requireShared("Config")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local Kit = t.requireShared("Art/SquishyBlueprints/Kit")
	local OrbitCamera = t.requireClient("UI/OrbitCamera")
	local expect = t.expect
	local SQUEEZE = Config.Anim.squeeze
	local RIG = Config.Anim.rig
	local EVENTS = SquishRig.EVENTS

	local function newRig(motion: any, opts: any?): (any, any)
		local options = opts or {}
		if options.blink == nil then
			options.blink = false -- most cases check the squeeze alone
		end
		return SquishRig.new(motion, options), SquishRig.newOut()
	end

	-- Steps `seconds` in steps of `dt`; `each(time, out)` after every step (time = seconds since the call).
	local function run(rig: any, out: any, seconds: number, dt: number, each: ((number, any) -> ())?)
		local time = 0
		local steps = math.max(1, math.floor(seconds / dt + 0.5))
		for _ = 1, steps do
			rig:step(dt, out)
			time += dt
			if each then
				each(time, out)
			end
		end
	end

	-- The scaled keyframe value of one Config phase for a toy (the spec's c').
	local function toyC(motion: any, c: number): number
		local deepest = math.huge
		for _, phase in SQUEEZE.phases do
			deepest = math.min(deepest, phase.c)
		end
		return 1 - (1 - c) * (1 - motion.squeeze.depth) / (1 - deepest)
	end

	local function phaseNamed(name: string): any
		for _, phase in SQUEEZE.phases do
			if phase.name == name then
				return phase
			end
		end
		error(`no phase {name}`)
	end

	local function dampedHz(omega: number, zeta: number): number
		return omega * math.sqrt(math.max(0, 1 - zeta * zeta)) / TAU
	end

	-- Spring --------------------------------------------------------------------------------------------------------

	t.test("ω and ζ of the release spring come from kRel and cRel; every recovery stays under 1 Hz", function()
		local omega, zeta = SquishRig.recoverySpring(KITTY.squeeze)
		expect.near(omega, math.sqrt(34), 1e-9)
		expect.near(zeta, 8.5 / (2 * math.sqrt(34)), 1e-9)
		expect.near(dampedHz(omega, zeta), 0.635, 0.005) -- §4: 0.64 Hz, ζ 0.73
		for id, blueprint in Blueprints do
			local motion = blueprint.motion
			if motion then
				local w, z = SquishRig.recoverySpring(motion.squeeze)
				expect.truthy(dampedHz(w, z) <= 1)
				expect.truthy(z < 1) -- every toy has its own small overshoot
				expect.truthy(id ~= "")
			end
		end

		-- The simulated recovery: from the pop value, overshoot within the §4 bound, then back to exactly 1.
		local rig, out = newRig(KITTY)
		rig:tap()
		local popEnd = rig.timing.popEndMs / 1000
		local popY = toyC(KITTY, phaseNamed("releasePop").c)
		local bound = 1 + (1 - popY) * math.exp(-math.pi * zeta / math.sqrt(1 - zeta * zeta))
		local highest = 0
		run(rig, out, 4, FINE, function(time: number, o: any)
			if time > popEnd + FINE then
				highest = math.max(highest, o.S.Y)
			end
		end)
		expect.truthy(highest > 1.001) -- a soft overshoot (the "recovery wobble")
		expect.truthy(highest <= bound + 0.03) -- + the foam release kick's stretch
		expect.equal(out.S, Vector3.one)
	end)

	-- Press keyframes ----------------------------------------------------------------------------------------------

	t.test("the press follows the Config phases scaled to the toy and reaches depth by the release start", function()
		local rig, out = newRig(KITTY)
		rig:tap()
		local widen = KITTY.squeeze.widen
		local function check(name: string, ms: number)
			local wantY = toyC(KITTY, phaseNamed(name).c)
			-- At the pop end the release kick has already moved the jiggle for the rest of that step.
			local tolerance = if name == "releasePop" then 0.01 else 2e-3
			expect.near(out.S.Y, wantY, tolerance)
			expect.near(out.S.X, 1 + (1 - wantY) * widen, tolerance)
			expect.near(out.S.Z, out.S.X, F32)
			expect.truthy(ms > 0)
		end
		local elapsed = 0
		for _, name in { "anticipation", "compression", "widening", "releasePop" } do
			local phase = phaseNamed(name)
			-- Common: no widening extra. Step to the phase end in 10 ms steps.
			while elapsed + 5 < phase.endMs do
				rig:step(0.01, out)
				elapsed += 10
			end
			check(name, phase.endMs)
		end
		-- At the release start the press sits at depth.
		expect.near(toyC(KITTY, phaseNamed("widening").c), KITTY.squeeze.depth, 1e-9)

		-- Uncommon widens 40 ms longer: at 330 ms it is still pressing toward depth, at 370 ms it is there.
		local slow, slowOut = newRig(KITTY, { rarity = "Uncommon" })
		slow:tap()
		run(slow, slowOut, 0.37, 0.01)
		expect.near(slowOut.S.Y, KITTY.squeeze.depth, 0.01)
		expect.equal(slow.timing.releaseStartMs, phaseNamed("releasePop").startMs + 40)
	end)

	t.test("events fire once each, in order, at the Config phase times (60 fps and a clamped 1/20 s dt)", function()
		local names = { "squish", "peak", "releaseStart", "popEnd" }
		for _, rarity in { "Common", "Uncommon", "Epic", "Exclusive" } do
			local extra = SQUEEZE.flourish[rarity].wideningExtraMs or 0
			local timing = SquishRig.timingFor(rarity)
			expect.equal(timing.anticipationEndMs, phaseNamed("anticipation").endMs)
			expect.equal(timing.peakMs, phaseNamed("widening").endMs + extra)
			expect.equal(timing.releaseStartMs, phaseNamed("releasePop").startMs + extra)
			expect.equal(timing.popEndMs, phaseNamed("releasePop").endMs + extra)
			local at = {
				squish = timing.anticipationEndMs,
				peak = timing.peakMs,
				releaseStart = timing.releaseStartMs,
				popEnd = timing.popEndMs,
			}
			for _, dt in { FRAME, 1 / 20 } do
				local rig, out = newRig(KITTY, { rarity = rarity })
				rig:tap()
				local counts: { [string]: number } = {}
				local firedAt: { [string]: number } = {}
				run(rig, out, 1.5, dt, function(time: number, o: any)
					for _, name in names do
						if bit32.btest(o.events, EVENTS[name]) then
							counts[name] = (counts[name] or 0) + 1
							firedAt[name] = time * 1000
						end
					end
				end)
				local previous = -1
				for _, name in names do
					expect.equal(counts[name], 1)
					local when = firedAt[name]
					expect.truthy(when >= at[name] - 1e-6 and when < at[name] + dt * 1000 + 1e-6)
					expect.truthy(when >= previous)
					previous = when
				end
			end
		end
	end)

	t.test("the release pop and `recovering` both start at popEnd; a tap before popEnd merges", function()
		local rig, out = newRig(KITTY)
		rig:tap()
		local timing = rig.timing
		local lastY = math.huge
		local sawPop = false
		run(rig, out, 0.6, FINE, function(time: number, o: any)
			local ms = time * 1000
			if ms < timing.releaseStartMs - 1e-6 then
				expect.falsy(rig:isRecovering())
			elseif ms < timing.popEndMs - 1e-6 then
				-- The release pop: rising, not recovering yet (a tap now is a merge, not a restart).
				expect.falsy(rig:isRecovering())
				expect.truthy(o.S.Y >= lastY - F32)
				sawPop = true
			elseif bit32.btest(o.events, EVENTS.popEnd) then
				expect.truthy(rig:isRecovering())
				expect.near(o.S.Y, toyC(KITTY, phaseNamed("releasePop").c), 0.01)
			else
				expect.truthy(rig:isRecovering())
			end
			lastY = o.S.Y
		end)
		expect.truthy(sawPop)

		-- A tap inside [releaseStart, popEnd): the controller sees a squeeze that is not recovering yet.
		local merge, mergeOut = newRig(KITTY)
		merge:tap()
		run(merge, mergeOut, (timing.releaseStartMs + 20) / 1000, FINE)
		expect.falsy(merge:isRecovering())
		expect.truthy(merge:elapsedMs() >= timing.releaseStartMs)
		merge:tap()
		expect.near(merge:elapsedMs(), 0, 1e-9)
		expect.falsy(merge:isRecovering())
	end)

	t.test("one out table per rig: step fills it in place and allocates no table of its own", function()
		local rig, out = newRig(KITTY, { sections = SECTIONS, rarity = "Exclusive", blink = true })
		local sections = out.sections
		rig:tap()
		rig:flight()
		for _ = 1, 600 do
			local result = rig:step(FRAME, out)
			expect.equal(result, nil)
		end
		rig:clearFlight()
		rig:kick(0.05)
		run(rig, out, 2, FRAME)
		expect.equal(out.sections, sections)
		expect.equal(#out.sections, 3)
		expect.deepEqual(SquishRig.sectionNames(SECTIONS), { "EarL", "EarR", "Tail" })
	end)

	t.test("every motion is at most 3 Hz: feels, sections, recovery, flight styles and the twist", function()
		local wanted = { foam = 1.71, mochi = 1.54, jelly = 2.73, plush = 1.92 } -- §3.2 table
		for feel, hz in wanted do
			local omega, zeta = SquishRig.feelSpring(feel)
			expect.near(dampedHz(omega, zeta), hz, 0.01)
			expect.truthy(dampedHz(omega, zeta) <= 3)
		end
		local sections = RIG.sections
		local sOmega = math.sqrt(sections.k)
		expect.near(dampedHz(sOmega, sections.c / (2 * sOmega)), 1.77, 0.01)
		for name, style in RIG.flight do
			for _, key in { "wobbleHz", "nodHz", "pulseHz" } do
				local hz = style[key]
				expect.truthy(hz == nil or hz <= 3)
			end
			expect.truthy(style.flapHz == nil or style.flapHz <= 2.5)
			expect.truthy(style.rollDegPerSecond == nil or style.rollDegPerSecond <= 720)
			expect.truthy(type(name) == "string")
		end
		for _, rarity in { "Uncommon", "Epic" } do
			local timing = SquishRig.timingFor(rarity)
			local halfSwingMs = timing.peakMs - timing.anticipationEndMs
			expect.truthy(1000 / (2 * halfSwingMs) <= 3)
		end
	end)

	t.test("a tap restarts from the current state without a jump (scale and twist)", function()
		for _, seconds in { 0.03, 0.1, 0.2, 0.34, 0.36, 0.4, 0.6, 1.0 } do
			local rig, out = newRig(KITTY, { rarity = "Uncommon" })
			rig:tap()
			run(rig, out, seconds, FRAME)
			local before, twist = out.S, out.twist
			rig:tap()
			rig:step(1e-4, out) -- 0.1 ms: the anticipation moves fast (~0.01 per ms), a jump would not shrink
			local delta = out.S - before
			expect.truthy(math.abs(delta.X) < 3e-3 and math.abs(delta.Y) < 3e-3 and math.abs(delta.Z) < 3e-3)
			expect.truthy(math.abs(out.twist - twist) < 3e-3)
		end
	end)

	t.test("it sleeps at rest with exact values, and a seed makes it repeat exactly", function()
		local rig, out = newRig(KITTY, { sections = SECTIONS, rarity = "Epic" })
		rig:tap()
		rig:kick(0.05)
		run(rig, out, 5, FRAME)
		expect.falsy(out.awake)
		expect.equal(out.S, Vector3.one)
		expect.equal(out.twist, 0)
		expect.equal(out.cheek, 1)
		expect.equal(out.blink, 1)
		expect.equal(out.pressAmount, 0)
		expect.equal(out.events, 0)
		expect.equal(out.face, "normal")
		for _, angle in out.sections do
			expect.equal(angle, 0)
		end

		local function script(seed: number): { any }
			local r, o = newRig(MOCHI, { sections = SECTIONS, rarity = "Epic", seed = seed, blink = true })
			local trace = {}
			local time = 0
			for frame = 1, 480 do
				if frame == 1 then
					r:tap()
				elseif frame == 60 then
					r:kick(0.04)
				elseif frame == 120 then
					r:hit()
				elseif frame == 200 then
					r:press()
				elseif frame == 260 then
					r:release()
				elseif frame == 330 then
					r:flight()
				end
				r:step(FRAME, o)
				time += FRAME
				table.insert(trace, { o.S, o.twist, o.face, o.blink, o.cheek, o.sections[1], o.roll, o.events })
			end
			return trace
		end
		expect.deepEqual(script(7), script(7))
	end)

	-- Face -------------------------------------------------------------------------------------------------------

	t.test("the squish face: in below y 0.86, out above 0.90, and each state held at least 0.2 s", function()
		local face = RIG.face
		expect.equal(face.squishBelow, 0.86)
		expect.equal(face.squishAbove, 0.9)
		expect.equal(face.minHoldSeconds, 0.2)
		local rig, out = newRig(KITTY)
		rig:hold(0.87)
		rig:step(0.05, out)
		expect.equal(out.face, "normal")
		rig:hold(0.85)
		rig:step(0.01, out)
		expect.equal(out.face, "squish")
		rig:hold(0.88) -- between the thresholds: stays squished (hysteresis)
		run(rig, out, 0.3, 0.01)
		expect.equal(out.face, "squish")
		rig:hold(0.95)
		rig:step(0.01, out)
		expect.equal(out.face, "normal")
		-- Straight back down: the normal face is held for 0.2 s first.
		rig:hold(0.8)
		rig:step(0.01, out)
		expect.equal(out.face, "normal")
		run(rig, out, 0.15, 0.01)
		expect.equal(out.face, "normal")
		run(rig, out, 0.06, 0.01)
		expect.equal(out.face, "squish")
		-- And up again at once: the squish face is held for 0.2 s too.
		rig:hold(0.99)
		rig:step(0.01, out)
		expect.equal(out.face, "squish")
		run(rig, out, 0.2, 0.01)
		expect.equal(out.face, "normal")
	end)

	t.test(
		"face priority: a squish lock beats all, a squeezing squish beats wow; repeated taps keep the squish",
		function()
			local rig, out = newRig(KITTY)
			rig:setFace("wow", 0.3)
			rig:step(FRAME, out)
			expect.equal(out.face, "wow")
			rig:tap() -- squeezing under a wow lock: the squish face wins once squashed
			local sawSquish = false
			run(rig, out, 0.25, FRAME, function(_time: number, o: any)
				if o.face == "squish" then
					sawSquish = true
				end
			end)
			expect.truthy(sawSquish)
			run(rig, out, 3, FRAME)
			expect.equal(out.face, "normal") -- the wow lock ran out, the recovery passed 0.90

			-- A timed squish lock at rest.
			rig:setFace("squish", 0.5)
			rig:step(FRAME, out)
			expect.equal(out.face, "squish")
			run(rig, out, 0.6, FRAME)
			expect.equal(out.face, "normal")
			-- An open lock lasts until setFace("normal").
			rig:setFace("squish")
			run(rig, out, 3, FRAME)
			expect.equal(out.face, "squish")
			rig:setFace("normal")
			rig:step(FRAME, out)
			expect.equal(out.face, "normal")

			-- Grip hold-to-squeeze: a tap every repeatSeconds keeps the squish face from its first squish to the last
			-- recovery (no flicker back to normal between taps).
			local repeatSeconds = Config.Grip.Hold.repeatSeconds
			local grip, gripOut = newRig(KITTY)
			local first: number? = nil
			local lastNormal = -1
			local time = 0
			local taps = 8
			for tap = 1, taps do
				grip:tap()
				run(grip, gripOut, repeatSeconds, FRAME, function(dt: number, o: any)
					local now = time + dt
					if o.face == "squish" and first == nil then
						first = now
					elseif o.face ~= "squish" and first ~= nil then
						lastNormal = now
					end
				end)
				time += repeatSeconds
				expect.truthy(tap > 0)
			end
			expect.truthy(first ~= nil)
			expect.equal(lastNormal, -1) -- no normal frame between the taps (the last recovery has not passed 0.90 yet)
		end
	)

	t.test("blinks: 2-5 s apart, 0.14 s long, shut to 0.12; none when reduced, switched off or far", function()
		local blink = RIG.blink
		expect.equal(blink.seconds, 0.14)
		expect.equal(blink.closedY, 0.12)
		local rig = SquishRig.new(KITTY, { seed = 3 })
		local out = SquishRig.newOut()
		local starts: { number } = {}
		local ends: { number } = {}
		local lowest = 1
		local was = 1
		run(rig, out, 40, FINE, function(time: number, o: any)
			if o.blink < 1 and was == 1 then
				table.insert(starts, time)
			elseif o.blink == 1 and was < 1 then
				table.insert(ends, time)
			end
			lowest = math.min(lowest, o.blink)
			was = o.blink
		end)
		expect.truthy(#starts >= 7)
		expect.near(lowest, blink.closedY, 1e-9)
		expect.truthy(starts[1] >= blink.minSeconds - FINE and starts[1] <= blink.maxSeconds + FINE)
		for index = 1, #ends do
			expect.near(ends[index] - starts[index], blink.seconds, 2 * FINE)
			local nextStart = starts[index + 1]
			if nextStart then
				local gap = nextStart - ends[index]
				expect.truthy(gap >= blink.minSeconds - 2 * FINE and gap <= blink.maxSeconds + 2 * FINE)
			end
		end

		local function neverBlinks(r: any)
			local o = SquishRig.newOut()
			run(r, o, 12, FRAME, function(_time: number, oo: any)
				expect.equal(oo.blink, 1)
			end)
		end
		neverBlinks(SquishRig.new(KITTY, { seed = 3, reduced = true }))
		local off = SquishRig.new(KITTY, { seed = 3 })
		off:setBlink(false)
		neverBlinks(off)
		local far = SquishRig.new(KITTY, { seed = 3 })
		far:setDetail("far")
		neverBlinks(far)
	end)

	-- ReducedMotion ----------------------------------------------------------------------------------------------

	t.test(
		"ReducedMotion: SmoothDamp with foamRecoveryT, no jiggle, sections, twist, blink or flight extras",
		function()
			local foamT = 0.32
			local rig, out =
				newRig(KITTY, { reduced = true, rarity = "Epic", sections = SECTIONS, foamRecoveryT = foamT })
			rig:tap()
			local timing = rig.timing
			local popY = toyC(KITTY, phaseNamed("releasePop").c)
			local y, velocity = popY, 0
			local recovering = false
			run(rig, out, 3, FRAME, function(time: number, o: any)
				expect.equal(o.twist, 0)
				expect.falsy(o.sectionsOn)
				for _, angle in o.sections do
					expect.equal(angle, 0)
				end
				local ms = time * 1000
				if ms >= timing.popEndMs and not recovering then
					recovering = true
					-- From popEnd: today's critically damped SmoothDamp (no overshoot).
					y, velocity = OrbitCamera.smoothDamp(popY, 1, 0, foamT, (ms - timing.popEndMs) / 1000)
					expect.near(o.S.Y, y, 2e-3)
				elseif recovering then
					y, velocity = OrbitCamera.smoothDamp(y, 1, velocity, foamT, FRAME)
					expect.near(o.S.Y, y, 2e-3)
					expect.truthy(o.S.Y <= 1 + F32)
				end
			end)
			expect.equal(out.S, Vector3.one)
			-- Kicks and hits make no jiggle (the hit still shows the squish face).
			rig:kick(0.06)
			rig:hit()
			rig:step(0.1, out)
			expect.equal(out.S, Vector3.one)
			expect.equal(out.face, "squish")
			-- Flight: roll only, today's Catalog spin for "wobble" / "roll"; no pulse, nod or flaps.
			for _, style in { "tumble", "glide", "wobble", "roll", "spiral" } do
				for _, time in { 0, 0.13, 0.4, 0.91 } do
					local roll, nod, pulse = SquishRig.flightPose(style, time, true, 1, 1.15)
					expect.equal(nod, 0)
					expect.equal(pulse, 1)
					expect.truthy(roll == roll)
				end
			end
			local throw = Config.Anim.throw
			local roll = SquishRig.flightPose("roll", 0.5, true)
			expect.near(roll, math.rad(throw.rollDegPerSecond) * 0.5, 1e-9)
			local wobble = SquishRig.flightPose("wobble", 0.1, true)
			expect.near(wobble, math.rad(throw.wobbleRollDeg) * math.sin(TAU * RIG.flight.wobble.wobbleHz * 0.1), 1e-9)
			rig:flight()
			run(rig, out, 0.5, FRAME)
			expect.equal(out.pulse, 1)
			expect.equal(out.nod, 0)
			for _, angle in out.sections do
				expect.equal(angle, 0)
			end
		end
	)

	-- Kicks ------------------------------------------------------------------------------------------------------

	t.test("the release kick grows with rarity (|j·gain| <= 0.08) and the hit boing peaks at 0.15", function()
		local maxKick = RIG.releaseKickMax
		for _, feel in { "foam", "mochi", "jelly", "plush" } do
			local _, _, gain = SquishRig.feelSpring(feel)
			local common = SquishRig.releaseKick(feel, "Common")
			local epic = SquishRig.releaseKick(feel, "Epic")
			expect.near(common, math.min(RIG.releaseKick * gain, maxKick), 1e-9)
			expect.near(epic, math.min(RIG.releaseKick * 1.5 * gain, maxKick), 1e-9)
			expect.truthy(epic >= common)
			expect.near(SquishRig.releaseKick(feel, "Uncommon"), common, 1e-9)
			expect.near(SquishRig.releaseKick(feel, "Exclusive"), epic, 1e-9)
			expect.truthy(epic <= maxKick + 1e-12)
		end
		-- Simulated: right after the release (the kick's first peak, before the spring's own overshoot) the Epic
		-- stretches further than the Common; the same toy recovers the same way, so only the kick differs.
		local function maxStretch(rarity: string): number
			local rig, out = newRig(KITTY, { rarity = rarity })
			rig:tap()
			local popEnd = rig.timing.popEndMs / 1000
			local most = 0
			run(rig, out, 1.5, FINE, function(time: number, o: any)
				if time >= popEnd and time <= popEnd + 0.15 then
					most = math.max(most, o.S.Y)
				end
			end)
			return most
		end
		expect.truthy(maxStretch("Epic") > maxStretch("Common"))

		-- The hit boing: the squeeze-axis squash peaks at 0.15 whatever the feel, with the squish face for 0.3 s.
		for _, motion in { KITTY, JELLY, MOCHI } do
			local rig, out = newRig(motion)
			rig:hit()
			local lowest = 1
			local squishUntil = 0
			run(rig, out, 3, FINE, function(time: number, o: any)
				lowest = math.min(lowest, o.S.Y)
				if o.face == "squish" then
					squishUntil = time
				end
			end)
			expect.near(1 - lowest, RIG.hitKick, 0.006)
			expect.truthy(squishUntil >= RIG.face.hitSeconds - FINE and squishUntil <= 0.75)
			expect.equal(out.S, Vector3.one)
		end
		-- Movement kicks keep today's cap (Config.Anim.held.motionJiggle.maxJ).
		local rig, out = newRig(JELLY)
		local lowest = 1
		for _ = 1, 10 do
			rig:kick(0.05)
			rig:step(FRAME, out)
			lowest = math.min(lowest, out.S.Y)
		end
		expect.truthy(1 - lowest <= Config.Anim.held.motionJiggle.maxJ + F32)
	end)

	-- Reset, extremes, framing ---------------------------------------------------------------------------------

	t.test("reset() puts every channel back to rest", function()
		local rig, out = newRig(MOCHI, { sections = SECTIONS, rarity = "Epic", blink = true })
		rig:tap()
		rig:kick(0.05)
		rig:setFace("wow")
		rig:flight()
		rig:hold(0.9)
		run(rig, out, 0.25, FRAME)
		rig:reset()
		rig:step(FRAME, out)
		expect.equal(out.S, Vector3.one)
		expect.equal(out.twist, 0)
		expect.equal(out.face, "normal")
		expect.equal(out.blink, 1)
		expect.equal(out.cheek, 1)
		expect.equal(out.roll, 0)
		expect.equal(out.nod, 0)
		expect.equal(out.pulse, 1)
		expect.equal(out.pressAmount, 0)
		expect.equal(out.events, 0)
		expect.falsy(out.awake)
		for _, angle in out.sections do
			expect.equal(angle, 0)
		end
		expect.falsy(rig:isRecovering())
		expect.equal(rig:elapsedMs(), nil)
	end)

	t.test("extremes() is Kit.extremes; Inspect framing is the toy's widest scale + 0.04, never below 1.28", function()
		for _, axis in { "X", "Y", "Z" } do
			expect.deepEqual(SquishRig.extremes(KITTY, axis), Kit.extremes(KITTY, axis))
		end
		local framing = Config.Inspect.Framing
		local function widest(motion: any): number
			local most = 0
			for _, extreme in Kit.extremes(motion, "Y") do
				local S = extreme.S
				most = math.max(most, S.X, S.Y, S.Z)
			end
			return most
		end
		for _, motion in { KITTY, MOCHI, JELLY } do
			expect.near(
				SquishRig.framingWidening(motion, "Y"),
				math.max(framing.squeezeWidening, widest(motion) + framing.widenMargin),
				1e-6
			)
		end
		expect.near(SquishRig.framingWidening(MOCHI, "Y"), 1.4, 1e-3) -- 1 + 0.45 × 0.8 + 0.04
		local shallow = { squeeze = { depth = 0.72, widen = 0.4, kRel = 40, cRel = 9 }, feel = "foam", flight = {} }
		expect.near(SquishRig.framingWidening(shallow, "Y"), framing.squeezeWidening, 1e-9)
	end)

	-- Flight -----------------------------------------------------------------------------------------------------

	t.test("flightPose keeps the face leading for every style, with its configured rates", function()
		local P = Vector3.new(3, 8, -2)
		for _, V in { Vector3.new(0, 0.3, -1), Vector3.new(1, -0.2, 0.4), Vector3.new(-0.5, 0.1, 1) } do
			for name, style in RIG.flight do
				local maxNod = math.rad((style.nodDeg or 0) + 1)
				for step = 0, 200 do
					local time = step * 0.01
					local roll, nod, pulse = SquishRig.flightPose(name, time, false, 1, 1.15)
					local frame = CFrame.lookAt(P, P + V) * CFrame.Angles(0, 0, roll) * CFrame.Angles(nod, 0, 0)
					expect.truthy(frame.LookVector:Dot(V.Unit) >= math.cos(maxNod) - 1e-5)
					expect.truthy(pulse >= 0.85 and pulse <= 1.2)
				end
				local rate = style.rollDegPerSecond
				if rate then
					local r0 = SquishRig.flightPose(name, 0, false)
					local r1 = SquishRig.flightPose(name, 1, false)
					expect.near(r1 - r0, math.rad(rate), 1e-6)
				end
			end
		end
		-- Mochi's pulse rises to 1.15 along travel; the hop swings 0.9-1.1.
		local high, low = 1, 1
		for step = 0, 200 do
			local _, _, pulse = SquishRig.flightPose("tumble", step * 0.005, false, 1, 1.15)
			high, low = math.max(high, pulse), math.min(low, pulse)
		end
		expect.near(high, 1.15, 2e-3)
		expect.near(low, 1, 1e-9)
		high, low = 1, 1
		for step = 0, 200 do
			local _, _, pulse = SquishRig.flightPose("hop", step * 0.005, false)
			high, low = math.max(high, pulse), math.min(low, pulse)
		end
		expect.near(high, 1.1, 2e-3)
		expect.near(low, 0.9, 2e-3)
		-- amp scales the wobble (Butter 0.7).
		local full = SquishRig.flightPose("tumble", 0.1, false, 1)
		local soft = SquishRig.flightPose("tumble", 0.1, false, 0.7)
		expect.near(soft, full * 0.7, 1e-9)
	end)

	t.test(
		"flight: the squish face all the way, flaps per section, the pose from flightPose; clearFlight lets go",
		function()
			local rig, out = newRig(KITTY, { sections = SECTIONS })
			rig:flight()
			local style = RIG.flight.tumble
			local flown = 0
			run(rig, out, 0.6, FRAME, function(time: number, o: any)
				flown = time
				expect.equal(o.face, "squish")
				local roll, nod, pulse, phase = SquishRig.flightPose("tumble", time, false)
				expect.near(o.roll, roll, 1e-9)
				expect.near(o.nod, nod, 1e-9)
				expect.near(o.pulse, pulse, 1e-9)
				-- EarL flaps with its own 20°, EarR mirrored (sign -1), the Tail with the style's flapDeg.
				expect.near(o.sections[1], math.rad(20) * math.sin(phase), 1e-9)
				expect.near(o.sections[2], -math.rad(20) * math.sin(phase), 1e-9)
				expect.near(o.sections[3], math.rad(style.flapDeg) * math.sin(phase), 1e-9)
			end)
			expect.truthy(flown > 0.5)
			rig:clearFlight()
			run(rig, out, 2, FRAME)
			expect.equal(out.face, "normal")
			expect.equal(out.roll, 0)
			expect.equal(out.pulse, 1)
			expect.falsy(out.awake)
		end
	)

	-- Press, hold, sections, detail ------------------------------------------------------------------------------

	t.test(
		"press and hold: depth until release, then the pop and the spring; an early release fires all once",
		function()
			local rig, out = newRig(KITTY)
			rig:press()
			local seen = 0
			run(rig, out, 1, FRAME, function(_time: number, o: any)
				seen = bit32.bor(seen, o.events)
			end)
			expect.near(out.S.Y, KITTY.squeeze.depth, 2e-3)
			expect.equal(seen, bit32.bor(EVENTS.squish, EVENTS.peak))
			expect.near(out.pressAmount, 1, 1e-3)
			rig:release()
			rig:step(FRAME, out)
			expect.equal(out.events, EVENTS.releaseStart)
			local popAt = 0
			run(rig, out, 0.2, FINE, function(time: number, o: any)
				if bit32.btest(o.events, EVENTS.popEnd) and popAt == 0 then
					popAt = time
				end
			end)
			local popMs = phaseNamed("releasePop").endMs - phaseNamed("releasePop").startMs
			expect.near(popAt + FRAME, popMs / 1000, FRAME + FINE)
			expect.truthy(rig:isRecovering())

			-- Early release (still in the anticipation): squish, peak and releaseStart in one step, in that order.
			local early, earlyOut = newRig(KITTY)
			early:press()
			run(early, earlyOut, 0.03, 0.01)
			local releasedY = earlyOut.S.Y
			early:release()
			early:step(0.01, earlyOut)
			expect.equal(earlyOut.events, bit32.bor(EVENTS.squish, EVENTS.peak, EVENTS.releaseStart))
			local count = 0
			run(early, earlyOut, 1, 0.01, function(_time: number, o: any)
				if bit32.btest(o.events, EVENTS.popEnd) then
					count += 1
				end
				expect.truthy(o.S.Y >= math.min(releasedY, 1) - 0.01) -- no pop squeeze after letting go
			end)
			expect.equal(count, 1)

			-- A press on another axis, from rest (the switch takes effect at once).
			local palms, palmsOut = newRig(KITTY)
			palms:press("X")
			run(palms, palmsOut, 0.5, FRAME)
			expect.near(palmsOut.S.X, KITTY.squeeze.depth, 2e-3)
			expect.near(palmsOut.S.Y, 1 + (1 - KITTY.squeeze.depth) * KITTY.squeeze.widen, 2e-3)
		end
	)

	t.test("hold(c) sets the squeeze directly (no spring); arm sync ignores it; clearHold recovers", function()
		local rig, out = newRig(KITTY)
		rig:hold(0.9)
		rig:step(FRAME, out)
		expect.near(out.S.Y, 0.9, F32)
		expect.near(out.S.X, 1 + 0.1 * KITTY.squeeze.widen, F32)
		expect.equal(out.pressAmount, 0)
		expect.near(out.cheek, 1 + RIG.looks.cheekPuff * 0.1 / (1 - KITTY.squeeze.depth), 1e-9)
		rig:hold(0.93)
		rig:step(FRAME, out)
		expect.near(out.S.Y, 0.93, F32)
		rig:clearHold()
		run(rig, out, 3, FRAME)
		expect.equal(out.S, Vector3.one)
		expect.falsy(out.awake)
	end)

	t.test("sections bounce from the rendered squeeze speed, soft-limited, mirrored and settling to 0", function()
		local rig, out = newRig(KITTY, { sections = SECTIONS })
		rig:tap()
		local most = 0
		run(rig, out, 4, FINE, function(_time: number, o: any)
			expect.truthy(o.sectionsOn)
			most = math.max(most, math.abs(o.sections[1]))
			expect.near(o.sections[2], -o.sections[1], 1e-9) -- EarR mirrors EarL (sign -1)
			expect.truthy(math.abs(o.sections[1]) <= math.rad(RIG.sections.maxDeg) * 1.35)
		end)
		expect.truthy(most > math.rad(3))
		for _, angle in out.sections do
			expect.equal(angle, 0)
		end
		-- A movement kick bounces the ears too.
		rig:kick(0.05)
		local moved = 0
		run(rig, out, 0.3, FRAME, function(_time: number, o: any)
			moved = math.max(moved, math.abs(o.sections[1]))
		end)
		expect.truthy(moved > math.rad(0.5))

		-- The Exclusive flare: a kick on its sections at the release start.
		local function flare(rarity: string): number
			local r, o = newRig(KITTY, { sections = SECTIONS, rarity = rarity })
			r:tap()
			local start = r.timing.releaseStartMs / 1000
			local high = 0
			run(r, o, 1.2, FINE, function(time: number, oo: any)
				if time >= start then
					high = math.max(high, math.abs(oo.sections[3]))
				end
			end)
			return high
		end
		expect.truthy(flare("Exclusive") > flare("Common") + math.rad(2))
	end)

	t.test("resting sections stay exactly 0 (their springs are skipped) and bounce like a fresh rig's after", function()
		-- The rig speed-up pass skips a section spring at rest with no pull; the result must be what stepping gives.
		local function trace(restSeconds: number): { any }
			local rig, out = newRig(KITTY, { sections = SECTIONS, rarity = "Exclusive", seed = 3 })
			run(rig, out, restSeconds, FRAME, function(_time: number, o: any)
				for _, angle in o.sections do
					expect.equal(angle, 0)
				end
			end)
			rig:tap()
			rig:kick(0.05)
			local frames = {}
			run(rig, out, 1.5, FRAME, function(_time: number, o: any)
				table.insert(frames, table.clone(o.sections))
			end)
			return frames
		end
		local fresh, rested = trace(FRAME), trace(5)
		expect.deepEqual(rested, fresh)
		expect.truthy(math.abs(fresh[20][1]) > 0)
	end)

	t.test(
		"isAwake: asleep at rest, awake at once on every input (before any step), and what out.awake says",
		function()
			local inputs: { [string]: (any) -> () } = {
				tap = function(r: any)
					r:tap()
				end,
				press = function(r: any)
					r:press()
				end,
				hold = function(r: any)
					r:hold(0.9)
				end,
				kick = function(r: any)
					r:kick(0.05)
				end,
				hit = function(r: any)
					r:hit()
				end,
				squishFace = function(r: any)
					r:setFace("squish", 0.3)
				end,
				wowFace = function(r: any)
					r:setFace("wow")
				end,
				flight = function(r: any)
					r:flight()
				end,
			}
			for name, input in inputs do
				local rig, out = newRig(KITTY, { sections = SECTIONS })
				run(rig, out, 0.2, FRAME)
				expect.falsy(rig:isAwake())
				input(rig)
				if not rig:isAwake() then
					error(`{name} did not wake the rig before its next step`)
				end
				rig:step(FRAME, out)
				expect.truthy(out.awake)
			end
			-- After every step isAwake() is out.awake (a scripted run through every channel, blinks included).
			local rig, out = newRig(MOCHI, { sections = SECTIONS, rarity = "Epic", seed = 5, blink = true })
			local sawAsleep = false
			for frame = 1, 900 do
				if frame == 1 then
					rig:tap()
				elseif frame == 200 then
					rig:kick(0.04)
				elseif frame == 400 then
					rig:hit()
				elseif frame == 600 then
					rig:hold(0.9)
				elseif frame == 640 then
					rig:clearHold()
				end
				rig:step(FRAME, out)
				expect.equal(rig:isAwake(), out.awake)
				sawAsleep = sawAsleep or not out.awake
			end
			expect.truthy(sawAsleep)
		end
	)

	t.test("detail levels: near drops the sections; far also drops faces, blinks and the jiggle", function()
		local rig, out = newRig(KITTY, { sections = SECTIONS })
		rig:setDetail("near")
		rig:tap()
		local squished = false
		run(rig, out, 0.3, FRAME, function(_time: number, o: any)
			expect.falsy(o.sectionsOn)
			for _, angle in o.sections do
				expect.equal(angle, 0)
			end
			squished = squished or o.face == "squish"
		end)
		expect.truthy(squished)
		rig:setDetail("far")
		rig:step(FRAME, out)
		expect.equal(out.face, "normal")
		run(rig, out, 3, FRAME)
		rig:kick(0.05)
		rig:step(FRAME, out)
		expect.equal(out.S, Vector3.one) -- no jiggle
		rig:setDetail("hero")
		rig:tap()
		rig:step(FRAME, out)
		expect.truthy(out.sectionsOn)
	end)

	-- First person (spec 2026-10-10 §3.4, §3.5) ------------------------------------------------------------------------

	t.test("setAxis and press(axis) switch the squeeze axis only at rest; axis() is the axis it squeezes on", function()
		local rig, out = newRig(KITTY, { axis = "Z" })
		expect.equal(rig:axis(), "Z")
		rig:setAxis("Y") -- at rest: at once
		expect.equal(rig:axis(), "Y")
		rig:tap()
		run(rig, out, 0.15, FRAME)
		rig:setAxis("X") -- mid-squeeze: the squeeze carries on along Y
		expect.equal(rig:axis(), "Y")
		run(rig, out, 0.1, FRAME)
		expect.equal(rig:axis(), "Y")
		expect.truthy(out.S.Y < 0.8 and out.S.X > 1.1)
		run(rig, out, 3, FRAME) -- back at rest: the switch happened
		expect.equal(rig:axis(), "X")
		expect.equal(out.S, Vector3.one)
		rig:tap() -- tap uses the default axis, now X
		run(rig, out, 0.25, FRAME)
		expect.truthy(out.S.X < 0.8 and out.S.Y > 1.1)

		-- press(axis) mid-squeeze presses on the current axis; the asked axis waits for rest.
		local other, otherOut = newRig(KITTY)
		other:tap()
		run(other, otherOut, 0.15, FRAME)
		other:press("X")
		run(other, otherOut, 0.5, FRAME)
		expect.equal(other:axis(), "Y")
		expect.near(otherOut.S.Y, KITTY.squeeze.depth, 2e-3)
		other:release()
		run(other, otherOut, 3, FRAME)
		expect.equal(other:axis(), "X")
		-- A hold never switches: it waits for the hold to clear and the toy to rest.
		local held, heldOut = newRig(KITTY)
		held:hold(1)
		held:setAxis("Z")
		run(held, heldOut, 0.5, FRAME)
		expect.equal(held:axis(), "Y")
		held:clearHold()
		run(held, heldOut, 0.5, FRAME)
		expect.equal(held:axis(), "Z")
		-- reset() goes back to the default axis.
		other:setAxis("Z")
		other:tap()
		other:setAxis("Y")
		other:reset()
		expect.equal(other:axis(), "Y")
	end)

	t.test(
		"the shown S never jumps more than 0.02 between steps over random setAxis, press, hold, tap and release",
		function()
			local AXES = { "X", "Y", "Z" }
			local STEP = 0.0005 -- 0.5 ms: the squeeze itself moves at most ~0.008 per step
			for seed = 1, 6 do
				local rng = Random.new(seed)
				local rig, out = newRig(if seed % 2 == 0 then MOCHI else KITTY, {
					rarity = if seed % 3 == 0 then "Epic" else "Common",
					axis = AXES[seed % 3 + 1] :: any,
				})
				rig:step(STEP, out)
				local last = out.S
				local holdLeft, holdFrom = 0, 1
				local worst, worstAt = 0, ""
				for i = 1, 12000 do -- 6 s
					if holdLeft > 0 then
						-- A windup-like hold: from where the toy is to 0.90 over 100 ms, then let go.
						holdLeft -= 1
						local u = 1 - holdLeft / 200
						rig:hold(holdFrom + (0.9 - holdFrom) * u)
						if holdLeft == 0 then
							rig:clearHold()
						end
					elseif i % 40 == 0 then -- an input every 20 ms
						local pick = rng:NextInteger(1, 7)
						if pick == 1 then
							rig:setAxis(AXES[rng:NextInteger(1, 3)] :: any)
						elseif pick == 2 then
							rig:press(if rng:NextInteger(1, 2) == 1 then nil else AXES[rng:NextInteger(1, 3)] :: any)
						elseif pick == 3 then
							holdLeft, holdFrom = 200, rig:squeezeY()
							rig:hold(holdFrom)
						elseif pick == 4 then
							rig:tap()
						elseif pick == 5 then
							rig:endPress()
						elseif pick == 6 then
							rig:release()
						end
					end
					rig:step(STEP, out)
					local d = out.S - last
					local jump = math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z))
					if jump > worst then
						worst, worstAt = jump, `seed {seed} step {i}: {last} -> {out.S}`
					end
					last = out.S
				end
				if worst > 0.02 then
					error(`jump {worst} at {worstAt}`)
				end
			end
		end
	)

	t.test("press() then endPress() before the release start is exactly tap(), for every rarity", function()
		for _, rarity in { "Common", "Uncommon", "Epic", "Exclusive" } do
			for _, endMs in { 10, 50, 100, 200, 300 } do
				for _, fromSquish in { false, true } do
					local opts = { rarity = rarity, seed = 7, sections = SECTIONS }
					local a, aOut = newRig(MOCHI, table.clone(opts))
					local b, bOut = newRig(MOCHI, table.clone(opts))
					if fromSquish then -- start both mid-recovery with the squish face showing (the tap's face rule)
						a:tap()
						b:tap()
						run(a, aOut, 0.42, FINE)
						run(b, bOut, 0.42, FINE)
						expect.equal(aOut.face, "squish")
					end
					a:tap()
					b:press()
					local where = `{rarity} end {endMs} ms{if fromSquish then " from squish" else ""}`
					for step = 1, math.floor(1.6 / FINE) do
						if step == math.floor(endMs / 1000 / FINE + 0.5) then
							b:endPress()
						end
						a:step(FINE, aOut)
						b:step(FINE, bOut)
						local d = aOut.S - bOut.S
						if
							math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) > 1e-6
							or aOut.events ~= bOut.events
							or aOut.face ~= bOut.face
							or math.abs(aOut.twist - bOut.twist) > 1e-9
							or math.abs(aOut.pressAmount - bOut.pressAmount) > 1e-9
						then
							error(`{where}: differs at step {step}: {aOut.S} {aOut.face} vs {bOut.S} {bOut.face}`)
						end
					end
				end
			end
		end
	end)

	t.test("endPress past the release start is release(); endPress and release do nothing outside a press", function()
		local a, aOut = newRig(KITTY, { seed = 2 })
		local b, bOut = newRig(KITTY, { seed = 2 })
		a:press()
		b:press()
		run(a, aOut, 0.5, FRAME)
		run(b, bOut, 0.5, FRAME)
		a:endPress()
		b:release()
		for _ = 1, 120 do
			a:step(FRAME, aOut)
			b:step(FRAME, bOut)
			expect.equal(aOut.S, bOut.S)
			expect.equal(aOut.events, bOut.events)
		end

		-- At rest, in a tap, in a hold and after a merged press: no change at all.
		local function twin(prepare: (any, any) -> ()): (any, any, any, any)
			local x, xOut = newRig(KITTY, { seed = 4 })
			local y, yOut = newRig(KITTY, { seed = 4 })
			prepare(x, xOut)
			prepare(y, yOut)
			return x, xOut, y, yOut
		end
		local cases: { [string]: (any, any) -> () } = {
			rest = function(_r: any, _o: any) end,
			tap = function(r: any, o: any)
				r:tap()
				run(r, o, 0.1, FRAME)
			end,
			hold = function(r: any, o: any)
				r:hold(0.9)
				run(r, o, 0.1, FRAME)
			end,
		}
		for name, prepare in cases do
			local x, xOut, y, yOut = twin(prepare)
			x:endPress()
			x:release()
			for _ = 1, 90 do
				x:step(FRAME, xOut)
				y:step(FRAME, yOut)
				if xOut.S ~= yOut.S or xOut.events ~= yOut.events then
					error(`{name}: endPress or release changed the rig`)
				end
			end
		end
		local idle = newRig(KITTY)
		idle:endPress()
		expect.equal(idle:elapsedMs(), nil)
	end)

	t.test("squeezeY() is the squeeze channel now: 1 at rest, the hold, the press", function()
		local rig, out = newRig(KITTY)
		expect.equal(rig:squeezeY(), 1)
		rig:press()
		run(rig, out, 0.5, FRAME)
		expect.near(rig:squeezeY(), KITTY.squeeze.depth, 2e-3)
		expect.near(out.S.Y, rig:squeezeY(), F32)
		rig:hold(0.9)
		expect.equal(rig:squeezeY(), 0.9)
		rig:clearHold()
		run(rig, out, 3, FRAME)
		expect.equal(rig:squeezeY(), 1)
	end)
end
