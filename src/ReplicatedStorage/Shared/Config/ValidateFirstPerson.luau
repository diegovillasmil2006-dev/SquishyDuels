--!strict
-- Config/ValidateFirstPerson (Shared): Config.validate's first-person checks, kept apart so Config/init stays under
-- Roblox's 200,000-character Source limit (audit row 27, 2026-11-12; the clone tests and the snapshot restore set
-- Source). Pure: require(script)(h, FirstPerson) returns check(problems), which adds human-readable problems through
-- Config/init's own check helpers `h`. Moved as it was:
-- First person (spec 2026-10-10 §4.1): the ranges, every spring and the idle drift <= MAX_FLICKER_HZ.
-- Design fidelity (spec 2026-10-11 §3): the light and colours are Color3s; the arm has hand, thumb, forearm, cuff and
-- sleeve once each, every size > 0, exponent >= 1 and colour a colours key; the outline, held toy, pop-in, squeeze,
-- focus, shake, throw extras and Dragon charge in range.

type Problems = { string }
type NumberCheck = (problems: Problems, path: string, value: unknown) -> ()

export type Helpers = {
	expect: (problems: Problems, ok: boolean, message: string) -> (),
	expectPositive: NumberCheck,
	expectNonNegative: NumberCheck,
	expectCount: (problems: Problems, path: string, value: unknown, min: number) -> (),
	expectBetween: (problems: Problems, path: string, value: unknown, min: number, max: number) -> (),
	expectBoolean: NumberCheck,
	expectCalmSpring: (problems: Problems, path: string, k: unknown, c: unknown) -> (),
	eachField: (problems: Problems, path: string, tbl: any, fields: { string }, check: NumberCheck) -> (),
	isNumber: (value: unknown) -> boolean,
	isInteger: (value: unknown) -> boolean,
	show: (value: unknown) -> string,
	sortedKeys: (tbl: any) -> { any },
	maxFlickerHz: number,
}

return function(h: Helpers, FirstPerson: any): (problems: Problems) -> ()
	local expect, expectPositive, expectNonNegative = h.expect, h.expectPositive, h.expectNonNegative
	local expectCount, expectBetween, expectBoolean = h.expectCount, h.expectBetween, h.expectBoolean
	local expectCalmSpring, eachField = h.expectCalmSpring, h.eachField
	local isNumber, isInteger, show, sortedKeys = h.isNumber, h.isInteger, h.show, h.sortedKeys
	local MAX_FLICKER_HZ = h.maxFlickerHz

	local function checkFirstPerson(problems: Problems)
		local p = "Config.FirstPerson"
		local fp: any = FirstPerson
		local function expectVector(path: string, value: unknown, positive: boolean?)
			local ok = typeof(value) == "Vector3"
			if ok and positive then
				local v = value :: Vector3
				ok = v.X > 0 and v.Y > 0 and v.Z > 0
			end
			expect(
				problems,
				ok,
				`{path} must be a Vector3{if positive then " with every side > 0" else ""} (got {show(value)})`
			)
		end
		local function expectSpring(path: string, spring: any)
			local k, c =
				if type(spring) == "table" then spring[1] else nil, if type(spring) == "table" then spring[2] else nil
			expectPositive(problems, `{path}[1] (k)`, k)
			expectNonNegative(problems, `{path}[2] (c)`, c)
			expectCalmSpring(problems, path, k, c)
		end

		expectBoolean(problems, `{p}.defaultOn`, fp.defaultOn)
		for _, name in { "gui", "padGui" } do
			local gui = fp[name]
			expect(problems, isInteger(gui.displayOrder), `{p}.{name}.displayOrder must be an integer`)
			expect(problems, typeof(gui.insets) == "EnumItem", `{p}.{name}.insets must be an Enum.ScreenInsets item`)
		end
		expectCount(problems, `{p}.touchGuiFallbackOrder`, fp.touchGuiFallbackOrder, 0)
		local axis = fp.squeezeAxis
		expect(
			problems,
			axis == "X" or axis == "Y" or axis == "Z",
			`{p}.squeezeAxis must be "X", "Y" or "Z" ({show(axis)})`
		)
		eachField(problems, p, fp, { "practiceExitDelaySeconds", "overlayStudsPerDu", "toyLongestDu" }, expectPositive)
		expectBetween(problems, `{p}.fovDeg`, fp.fovDeg, 1, 120)
		expectNonNegative(problems, `{p}.resultHoldSeconds`, fp.resultHoldSeconds)
		expectBetween(problems, `{p}.countdownPitchDeg`, fp.countdownPitchDeg, -90, 90)
		for _, name in { "invulnTransparency", "ownRingScale", "victimImpactScale" } do
			expectBetween(problems, `{p}.{name}`, fp[name], 0, 1)
		end
		for _, name in { "nearFade", "rushFadeIn" } do
			local band = fp[name]
			expect(
				problems,
				isNumber(band.from) and isNumber(band.to) and band.from >= 0 and band.from < band.to,
				`{p}.{name} must satisfy 0 <= from < to`
			)
		end

		-- Poses (du).
		for _, name in { "rest", "shoulder", "equipFrom" } do
			expectVector(`{p}.{name}`, fp[name])
		end

		-- Motion: every spring and wobble <= 3 Hz.
		for _, name in sortedKeys(fp.springs) do
			expectSpring(`{p}.springs.{name}`, fp.springs[name])
		end
		local idle = fp.idle
		eachField(problems, `{p}.idle`, idle, { "x", "y", "breath", "kickY", "kickPitch" }, expectNonNegative)
		expectBetween(problems, `{p}.idle.xHz`, idle.xHz, 0, MAX_FLICKER_HZ)
		expectBetween(problems, `{p}.idle.yHz`, idle.yHz, 0, MAX_FLICKER_HZ)
		expectBetween(problems, `{p}.idle.breathRate`, idle.breathRate, 0, 2 * math.pi * MAX_FLICKER_HZ)
		expect(problems, isNumber(fp.kick.release), `{p}.kick.release must be a number`)

		-- The 3D Lab design port (spec 2026-10-11 §3).
		local function expectColour(path: string, value: unknown)
			expect(problems, typeof(value) == "Color3", `{path} must be a Color3 (got {show(value)})`)
		end
		local light = fp.light
		for _, name in { "sky", "ground", "key", "viewportAmbient", "viewportLight" } do
			expectColour(`{p}.light.{name}`, light[name])
		end
		eachField(problems, `{p}.light`, light, { "hemisphere", "keyIntensity" }, expectNonNegative)
		expect(
			problems,
			typeof(light.keyFrom) == "Vector3" and (light.keyFrom :: Vector3).Magnitude > 0,
			`{p}.light.keyFrom must be a non-zero Vector3`
		)
		for _, name in { "skin", "cuff", "sleeve" } do
			expectColour(`{p}.colours.{name}`, fp.colours[name])
		end
		for _, side in { "A", "B" } do
			expectColour(`{p}.teamSleeves.{side}`, fp.teamSleeves[side])
		end
		-- The arm: hand, thumb, forearm, cuff and sleeve once each.
		local armParts = { hand = true, thumb = true, forearm = true, cuff = true, sleeve = true }
		local arm = fp.arm
		local seen: { [string]: boolean } = {}
		for index, part in arm.parts do
			local path = `{p}.arm.parts[{index}]`
			local known = armParts[part.name] == true
			expect(
				problems,
				known and not seen[part.name],
				`{path}.name {show(part.name)} must be one of hand, thumb, forearm, cuff, sleeve, each once`
			)
			if known then
				seen[part.name] = true
			end
			expectVector(`{path}.size`, part.size, true)
			expect(
				problems,
				isNumber(part.exponent) and part.exponent >= 1,
				`{path}.exponent must be a number >= 1 (got {show(part.exponent)})`
			)
			expect(
				problems,
				type(part.colour) == "string" and fp.colours[part.colour] ~= nil,
				`{path}.colour {show(part.colour)} is not a Config.FirstPerson.colours key`
			)
			expectVector(`{path}.pos`, part.pos)
			expectVector(`{path}.rot`, part.rot)
		end
		for _, name in sortedKeys(armParts) do
			expect(problems, seen[name] == true, `{p}.arm.parts has no {name}`)
		end
		expectCount(problems, `{p}.arm.segments[1]`, arm.segments[1], 3)
		expectCount(problems, `{p}.arm.segments[2]`, arm.segments[2], 2)
		expectVector(`{p}.arm.startPos`, arm.startPos)
		expectNonNegative(problems, `{p}.arm.roll`, arm.roll)
		local outline = fp.outline
		expectColour(`{p}.outline.colour`, outline.colour)
		eachField(problems, `{p}.outline`, outline, { "px", "refHeightPx", "refDepthDu" }, expectPositive)
		-- The player's own arms (Anim/OwnArm).
		local own = fp.ownArms
		expect(problems, type(own) == "table", `{p}.ownArms must be a table`)
		if type(own) == "table" then
			expect(
				problems,
				type(own.enabled) == "boolean",
				`{p}.ownArms.enabled must be a boolean (got {show(own.enabled)})`
			)
			eachField(
				problems,
				`{p}.ownArms`,
				own,
				{ "handWidthDu", "reachDu", "maxWidthDu", "maxHandLengthDu", "minPartStuds", "recheckSeconds" },
				expectPositive
			)
			expect(
				problems,
				isNumber(own.maxStretch) and own.maxStretch >= 1,
				`{p}.ownArms.maxStretch must be a number >= 1 (got {show(own.maxStretch)})`
			)
			expect(
				problems,
				isNumber(own.maxTransparency) and own.maxTransparency > 0 and own.maxTransparency <= 1,
				`{p}.ownArms.maxTransparency must be in (0, 1] (got {show(own.maxTransparency)})`
			)
			expect(problems, isNumber(own.palmRoll), `{p}.ownArms.palmRoll must be a number (got {show(own.palmRoll)})`)
		end
		-- The held toy, pop-in, squeeze, focus, shake, throw extras and Dragon charge.
		local held = fp.held
		expectVector(`{p}.held.pos`, held.pos)
		expectVector(`{p}.held.rot`, held.rot)
		expectNonNegative(problems, `{p}.held.sideGap`, held.sideGap)
		expect(problems, isNumber(held.sideY) and isNumber(held.sideZ), `{p}.held.sideY / sideZ must be numbers`)
		eachField(problems, `{p}.equip`, fp.equip, { "seconds", "backOutC" }, expectPositive)
		expect(
			problems,
			isNumber(fp.equip.minScale) and fp.equip.minScale > 0 and fp.equip.minScale < 1,
			`{p}.equip.minScale must be in (0, 1)`
		)
		local squeeze = fp.squeeze
		expectBetween(problems, `{p}.squeeze.inset`, squeeze.inset, 0, 1)
		expectBetween(problems, `{p}.squeeze.toyTremorShare`, squeeze.toyTremorShare, 0, 1)
		expect(problems, isNumber(squeeze.y) and isNumber(squeeze.z), `{p}.squeeze.y / z must be numbers`)
		eachField(
			problems,
			`{p}.squeeze`,
			squeeze,
			{ "rollPress", "tremorAfterSeconds", "tremor", "shake" },
			expectNonNegative
		)
		eachField(problems, `{p}.squeeze`, squeeze, { "tremorRateL", "tremorRateR", "toyTremorRate" }, expectPositive)
		local focus = fp.focus
		expectVector(`{p}.focus.pos`, focus.pos)
		expectVector(`{p}.focus.rot`, focus.rot)
		expectNonNegative(problems, `{p}.focus.lingerSeconds`, focus.lingerSeconds)
		expect(problems, isNumber(focus.worldFovTarget), `{p}.focus.worldFovTarget must be a number`)
		expectPositive(problems, `{p}.focus.worldFovPerUnit`, focus.worldFovPerUnit)
		expectPositive(problems, `{p}.shake.decayPerSecond`, fp.shake.decayPerSecond)
		expectNonNegative(problems, `{p}.shake.radPerShakeSq`, fp.shake.radPerShakeSq)
		local throwFx = fp.throwFx
		eachField(problems, `{p}.throwFx`, throwFx, {
			"rollCocked",
			"fovKick",
			"shake",
			"shoveJitter",
			"shoveShake",
			"slingShake",
			"slingFrom",
			"dragonRoarShake",
		}, expectNonNegative)
		expect(problems, isNumber(throwFx.rollL), `{p}.throwFx.rollL must be a number`)
		expectPositive(problems, `{p}.throwFx.shoveUntil`, throwFx.shoveUntil)
		expect(
			problems,
			isNumber(throwFx.slingFrom) and isNumber(throwFx.slingUntil) and throwFx.slingFrom < throwFx.slingUntil,
			`{p}.throwFx must satisfy slingFrom < slingUntil`
		)
		-- The squeeze tremor (47-53 rad/s), the Dragon wobble (40) and glow pulse (30) are the design's own and above
		-- MAX_FLICKER_HZ: kept as spec 2026-10-11 §3.4 / §3.6 port them (the tremor is about 1 px and off under
		-- ReducedMotion), so they are not checked against it.
		local ult = fp.ult
		expectVector(`{p}.ult.pos`, ult.pos)
		expect(problems, isNumber(ult.pitch), `{p}.ult.pitch must be a number`)
		eachField(
			problems,
			`{p}.ult`,
			ult,
			{ "wobble", "jitter", "glowPulse", "shake", "fovPullPerSecond", "releaseFovKick", "releaseShake" },
			expectNonNegative
		)
		expect(problems, isNumber(ult.releaseKick), `{p}.ult.releaseKick must be a number`)
		eachField(problems, `{p}.ult`, ult, { "wobbleRate", "glowRadius", "glowPulseRate", "glowFadeRate" }, expectPositive)
		expectBetween(problems, `{p}.ult.squashY`, ult.squashY, 0, 1)
		expectBetween(problems, `{p}.ult.glowOpacity`, ult.glowOpacity, 0, 1)
		expectColour(`{p}.ult.glowColour`, ult.glowColour)
	end

	return checkFirstPerson
end
