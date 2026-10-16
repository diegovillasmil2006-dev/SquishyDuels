--!strict
-- Config/ValidateMatch (Shared). The Config.Match part of Config.validate (Free for All / Team Deathmatch, jayyyyy
-- 2026-10-15; FFA/TDM v1), kept apart so Config/init stays under Roblox's 200,000-character script Source limit (the
-- clone tests and the snapshot restore set Source), like Config/ValidateUIMotion. Pure: require(script)(h, Match, Duel,
-- loadPalette) returns check(problems), which adds human-readable problems through Config/init's own check helpers
-- `h`; loadPalette() returns Art/Palette or nil (the wall colour check is skipped without it).
-- The rules: positive timings, two different team names,
-- each mode's win numbers, the storm's steps in time order (from stormStartSeconds, never overlapping, radius
-- fractions falling inside (0, 1)) and done before a storm mode's time-up, and every power-up in the order with one
-- known effect (seconds > 0, ultFraction in (0, 1], or the teams-only team life). FFA/TDM v1 (2026-10-15): a positive
-- gatherSeconds and readoutHz, whole rewardCoins >= 0, a boolean outOfBoundsIsKo, a footprint (X, Z > 0) and a spot
-- count for every mode, Bounds that reach down to the kill line, a positive ground probe length, the spawn distances,
-- the storm's sampleHz and inset, and its test wall (transparency in [0, 1], a height, an Art/Palette colour token).
-- Power-ups v1.1 (2026-10-16): a positive pickupRadiusStuds and pickupHeightStuds, and each timed power-up's number
-- when the kind is listed: speed walkMultiplier >= 1 (the movement guard widens its limit by it), superJump
-- jumpMultiplier >= 1 with the super jump plus the double jump under Maps.boundsTop (a player above the Bounds can't be
-- hit), rapidThrow cooldownMultiplier in [0, 1], throwBoost speedMultiplier >= 1.
-- UI FINAL R4: the DUEL picker's testers (whole userIds) and a boolean pickerForEveryone.

type Problems = { string }

export type Helpers = {
	add: (problems: Problems, message: string) -> (),
	expect: (problems: Problems, ok: boolean, message: string) -> (),
	expectPositive: (problems: Problems, path: string, value: unknown) -> (),
	expectNonNegative: (problems: Problems, path: string, value: unknown) -> (),
	expectCount: (problems: Problems, path: string, value: unknown, min: number) -> (),
	expectBetween: (problems: Problems, path: string, value: unknown, min: number, max: number) -> (),
	expectBoolean: (problems: Problems, path: string, value: unknown) -> (),
	expectText: (problems: Problems, path: string, value: unknown) -> (),
	expectCoins: (problems: Problems, path: string, value: unknown) -> (),
	isNumber: (value: unknown) -> boolean,
	show: (value: unknown) -> string,
	sortedKeys: (tbl: any) -> { any },
}

return function(h: Helpers, Match: any, Duel: any, loadPalette: () -> any): (problems: Problems) -> ()
	local add, expect, expectPositive, expectNonNegative = h.add, h.expect, h.expectPositive, h.expectNonNegative
	local expectCount, expectBetween, expectBoolean, expectText =
		h.expectCount, h.expectBetween, h.expectBoolean, h.expectText
	local expectCoins, isNumber, show, sortedKeys = h.expectCoins, h.isNumber, h.show, h.sortedKeys

	return function(problems: Problems)
		local p = "Config.Match"
		local m: any = Match
		for _, name in { "waitSeconds", "countdownSeconds", "respawnSeconds", "overtimeMaxSeconds", "resultSeconds" } do
			expectPositive(problems, `{p}.{name}`, m[name])
		end
		expectNonNegative(problems, `{p}.spawnProtectSeconds`, m.spawnProtectSeconds)
		expectCount(problems, `{p}.minPlayers`, m.minPlayers, 2)
		local teams = m.teamNames
		expect(
			problems,
			type(teams) == "table" and #teams == 2 and type(teams[1]) == "string" and teams[1] ~= teams[2],
			`{p}.teamNames must be two different names`
		)
		local storm = m.Storm
		local steps = storm.steps
		for _, modeId in sortedKeys(m.Modes) do
			local mode = m.Modes[modeId]
			local q = `{p}.Modes.{modeId}`
			expectBoolean(problems, `{q}.teams`, mode.teams)
			expectBoolean(problems, `{q}.storm`, mode.storm)
			expectCount(problems, `{q}.maxPlayers`, mode.maxPlayers, m.minPlayers)
			expectPositive(problems, `{q}.matchSeconds`, mode.matchSeconds)
			if mode.teams then
				expectCount(problems, `{q}.teamLives`, mode.teamLives, 0)
			else
				expectCount(problems, `{q}.koTarget`, mode.koTarget, 1)
			end
			local last = steps[#steps]
			expect(
				problems,
				not mode.storm or (last ~= nil and last.shrinkAt + last.shrinkSeconds <= mode.matchSeconds),
				`{q}: the storm must reach its last circle by matchSeconds`
			)
		end
		local s = `{p}.Storm`
		expectNonNegative(problems, `{s}.stormStartSeconds`, storm.stormStartSeconds)
		for _, name in { "warnSeconds", "barFillSeconds", "barDrainSeconds" } do
			expectPositive(problems, `{s}.{name}`, storm[name])
		end
		expectCount(problems, `#{s}.steps`, #steps, 1)
		local prevEnd, prevFraction = storm.stormStartSeconds, 1
		for index, step in steps do
			local q = `{s}.steps[{index}]`
			expectPositive(problems, `{q}.shrinkSeconds`, step.shrinkSeconds)
			expect(
				problems,
				isNumber(step.shrinkAt) and step.shrinkAt >= prevEnd,
				`{q}.shrinkAt must be at or after stormStartSeconds and the previous step's end`
			)
			expect(
				problems,
				isNumber(step.radiusFraction) and step.radiusFraction > 0 and step.radiusFraction < prevFraction,
				`{q}.radiusFraction must be > 0 and below the previous step's`
			)
			prevEnd = (tonumber(step.shrinkAt) or 0) + (tonumber(step.shrinkSeconds) or 0)
			prevFraction = tonumber(step.radiusFraction) or 0
		end
		local pu = m.PowerUps
		expectPositive(problems, `{p}.PowerUps.padRefillSeconds`, pu.padRefillSeconds)
		local listed: { [string]: boolean } = {}
		for _, kind in pu.order do
			listed[kind] = true
			local row = pu.kinds[kind]
			local q = `{p}.PowerUps.kinds.{kind}`
			if row == nil then
				add(problems, `{q} is missing (it is in PowerUps.order)`)
			elseif row.seconds ~= nil then
				expectPositive(problems, `{q}.seconds`, row.seconds)
			elseif row.ultFraction ~= nil then
				expect(
					problems,
					isNumber(row.ultFraction) and row.ultFraction > 0 and row.ultFraction <= 1,
					`{q}.ultFraction must be in (0, 1]`
				)
			else
				expect(problems, kind == "teamLife" and row.teamsOnly == true, `{q} has no effect`)
			end
		end
		for _, kind in sortedKeys(pu.kinds) do
			expect(problems, listed[kind] == true, `{p}.PowerUps.kinds.{kind} is not in PowerUps.order`)
		end

		-- FFA/TDM v1 (2026-10-15): the in-server queue, the maps, the spawn spots, the storm's sampling and test wall.
		expectPositive(problems, `{p}.gatherSeconds`, m.gatherSeconds)
		expectCoins(problems, `{p}.rewardCoins`, m.rewardCoins)
		expectBoolean(problems, `{p}.outOfBoundsIsKo`, m.outOfBoundsIsKo)
		expectPositive(problems, `{p}.readoutHz`, m.readoutHz)
		expectNonNegative(problems, `{p}.returnSpreadStuds`, m.returnSpreadStuds)
		local maps = m.Maps
		local spawns = m.Spawns
		for _, modeId in sortedKeys(m.Modes) do
			local key = string.upper(modeId)
			local footprint = maps.footprint[key]
			expect(
				problems,
				typeof(footprint) == "Vector3" and footprint.X > 0 and footprint.Z > 0,
				`{p}.Maps.footprint.{key} must be a Vector3 with X and Z > 0 (got {show(footprint)})`
			)
			expectCount(problems, `{p}.Spawns.spotsPerPad.{modeId}`, spawns.spotsPerPad[modeId], 1)
		end
		local killY = Duel.Rules.OutOfBounds.KillYOffset
		expect(
			problems,
			isNumber(maps.boundsBottomOffset) and maps.boundsBottomOffset <= killY,
			`{p}.Maps.boundsBottomOffset must reach the kill line (<= Config.Duel.Rules.OutOfBounds.KillYOffset, {killY})`
		)
		expectPositive(problems, `{p}.Maps.boundsTop`, maps.boundsTop)
		expectPositive(problems, `{p}.Maps.groundProbeStuds`, maps.groundProbeStuds)
		expectNonNegative(problems, `{p}.Spawns.edgeStuds`, spawns.edgeStuds)
		expectNonNegative(problems, `{p}.Spawns.occupiedStuds`, spawns.occupiedStuds)
		expectPositive(problems, `{p}.Spawns.raycastUpStuds`, spawns.raycastUpStuds)
		expectPositive(problems, `{s}.sampleHz`, storm.sampleHz)
		expectNonNegative(problems, `{s}.respawnInsetStuds`, storm.respawnInsetStuds)
		local wall = storm.wall
		expectBetween(problems, `{s}.wall.transparency`, wall.transparency, 0, 1)
		expectPositive(problems, `{s}.wall.heightStuds`, wall.heightStuds)
		expectText(problems, `{s}.wall.color`, wall.color)
		local Palette = loadPalette()
		if Palette ~= nil and type(wall.color) == "string" then
			expect(
				problems,
				typeof(Palette[wall.color]) == "Color3",
				`{s}.wall.color {show(wall.color)} must be an Art/Palette colour token`
			)
		end

		-- Power-ups v1.1 (2026-10-16): the pickup reach and the timed power-ups' numbers (a kind that is not listed is
		-- skipped: the order / kinds checks above already report it).
		local k = `{p}.PowerUps.kinds`
		expectPositive(problems, `{p}.PowerUps.pickupRadiusStuds`, pu.pickupRadiusStuds)
		expectPositive(problems, `{p}.PowerUps.pickupHeightStuds`, pu.pickupHeightStuds)
		local function atLeastOne(path: string, value: unknown)
			expect(
				problems,
				isNumber(value) and (value :: number) >= 1,
				`{path} must be a number >= 1 (got {show(value)})`
			)
		end
		if pu.kinds.speed then
			atLeastOne(`{k}.speed.walkMultiplier`, pu.kinds.speed.walkMultiplier)
		end
		local superJump = pu.kinds.superJump
		if superJump then
			atLeastOne(`{k}.superJump.jumpMultiplier`, superJump.jumpMultiplier)
			local doubleJump = Duel.Rules.DoubleJump
			local extra = if doubleJump and isNumber(doubleJump.heightStuds) then doubleJump.heightStuds else 0
			local rise = Duel.Rules.Movement.JumpHeight * (tonumber(superJump.jumpMultiplier) or 1) + extra
			expect(
				problems,
				not isNumber(maps.boundsTop) or rise < maps.boundsTop,
				`{k}.superJump.jumpMultiplier: the super jump + double jump ({show(rise)} studs) must stay under Maps.boundsTop`
			)
		end
		if pu.kinds.rapidThrow then
			expectBetween(problems, `{k}.rapidThrow.cooldownMultiplier`, pu.kinds.rapidThrow.cooldownMultiplier, 0, 1)
		end
		if pu.kinds.throwBoost then
			atLeastOne(`{k}.throwBoost.speedMultiplier`, pu.kinds.throwBoost.speedMultiplier)
		end
		-- UI FINAL R4: the DUEL picker's testers (whole userIds >= 1) and its switch for everyone.
		local testers = m.pickerTesters
		expect(problems, type(testers) == "table", `{p}.pickerTesters must be a list of userIds`)
		if type(testers) == "table" then
			for index, id in testers do
				expectCount(problems, `{p}.pickerTesters[{index}]`, id, 1)
			end
		end
		expectBoolean(problems, `{p}.pickerForEveryone`, m.pickerForEveryone)
	end
end
