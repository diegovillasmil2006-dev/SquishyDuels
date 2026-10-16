--!strict
-- MatchFormat_Test: StarterPlayerScripts.Client.UI.MatchFormat (FFA/TDM v1, 2026-10-15: the 12-player match's chat
-- commands, test readout and storm radius). Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (SPEC D6, D11, D13):
--   * the chat commands: "/ffa" and "/tdm" join that mode, "/leave" leaves; the first word only, any case; nothing
--     else is a command;
--   * the readout (Strings match.readout.*): FFA "K.O. {mine}/{target} · 1st {leaderName} {leaderKos} · {time}" (the
--     leader: most K.O.s, then fewest times knocked out, then the players' order), TDM "RED {redLives} · BLUE
--     {blueLives} · {time}" ({time} "0:00" without a timer), "Get ready…" while players arrive (Positioning); then
--     "STORM {pct}%" while the own storm bar is above 0 (any bar shows at least 1%), "OVERTIME" in overtime, "Back in
--     {seconds}" while knocked out ("OUT" in TDM with no team life left); a piece without a text is left out;
--   * the storm wall's radius: none in FFA, outside the live phase or before stormStartSeconds; StormMath's radius from
--     the Active start otherwise;
--   * power-ups v1.1 (2026-10-16, SPEC P4): the own live power-ups in the kinds' order with whole seconds left (at
--     least 1), listed in the readout as "{name} {seconds}s" after overtime (a kind without a name, or no powerUp
--     text, is left out); a pad's refill plays only when its readyAt rose above the one last played and lies ahead.
--     Review fix (2026-10-16): no power-up pieces outside the live phase (Result, Returning); the refill handed to
--     Diego's Collect ends a head start early, and one shorter than his pop is not played.
--   * music job (2026-10-16): the local player's result of a finished match is the server's MatchRewards result (FFA
--     winner / TDM winning team "win", the others "loss"; a draw "draw", in FFA only for the tied leaders), nil for a
--     cancelled or void match or without an outcome; each result's jingle (DuelFormat) is a sound slot (its id comes
--     from the owner's pick in the sound picker; review fix 2026-10-16).
-- The texts and team names are passed in (the place's Strings may not have the match.readout keys yet).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local MatchFormat = t.requireClient("UI/MatchFormat")
	local StormMath = t.requireShared("StormMath")

	-- As Shared/Strings match.readout (FFA/TDM v1).
	local TEXTS = {
		ffa = "K.O. {mine}/{target} · 1st {leaderName} {leaderKos} · {time}",
		tdm = "RED {redLives} · BLUE {blueLives} · {time}",
		waiting = "Get ready…",
		storm = "STORM {pct}%",
		overtime = "OVERTIME",
		backIn = "Back in {seconds}",
		out = "OUT",
		separator = " · ",
	}
	local TEAMS = { "Red", "Blue" }
	-- A Config.Match.Storm-shaped table (passed in, as MatchRules_Test does).
	local STORM = {
		stormStartSeconds = 300,
		warnSeconds = 30,
		steps = {
			{ shrinkAt = 300, shrinkSeconds = 60, radiusFraction = 0.6 },
			{ shrinkAt = 400, shrinkSeconds = 60, radiusFraction = 0.3 },
		},
		barFillSeconds = 3,
		barDrainSeconds = 9,
	}

	local function player(userId: number, name: string, kos: number, knockedOut: number, team: string?): any
		return {
			userId = userId,
			displayName = name,
			squishyId = "kitty_bread",
			team = team,
			kos = kos,
			knockedOut = knockedOut,
			alive = true,
			ultReady = false,
		}
	end

	local function view(overrides: { [string]: any }?): any
		local v: { [string]: any } = {
			matchId = "match:a",
			mode = "ffa",
			phase = "Active",
			matchPhase = "Active",
			phaseEndsAt = 1000 + 125,
			activeStartedAt = 1000,
			you = {
				userId = 1,
				displayName = "Me",
				squishyId = "kitty_bread",
				alive = true,
				respawnAt = nil,
				protectUntil = 0,
				stormBar = 0,
				out = false,
			},
			players = { player(1, "Me", 3, 2), player(2, "Ana", 7, 4), player(3, "Bo", 7, 1) },
			koTarget = 25,
			arena = { floorY = 0, centre = Vector3.new(6000, 0, 0) },
		}
		local extra: { [string]: any } = overrides or {}
		for key, value in extra do
			v[key] = value
		end
		return v
	end

	t.test("chat commands: /ffa and /tdm join, /leave leaves; the first word only, any case", function()
		local action, mode = MatchFormat.commandOf("/ffa")
		expect.equal(action, "join")
		expect.equal(mode, "ffa")
		action, mode = MatchFormat.commandOf("  /TDM please")
		expect.equal(action, "join")
		expect.equal(mode, "tdm")
		action, mode = MatchFormat.commandOf("/leave")
		expect.equal(action, "leave")
		expect.equal(mode, nil)
		for _, text in { "ffa", "/ffaa", "hello /ffa", "", "/" } do
			expect.equal((MatchFormat.commandOf(text)), nil)
		end
		expect.equal((MatchFormat.commandOf(nil)), nil)
		local count = 0
		for _ in MatchFormat.COMMANDS do
			count += 1
		end
		expect.equal(count, 3)
	end)

	t.test("the FFA readout: own K.O.s of the target, the leader, the timer", function()
		-- Ana and Bo both have 7; Bo was knocked out fewer times, so Bo leads.
		expect.equal(MatchFormat.leader(view()).displayName, "Bo")
		expect.equal(MatchFormat.readout(view(), 1000, TEXTS, TEAMS), "K.O. 3/25 · 1st Bo 7 · 2:05")
		-- An exact tie keeps the players' order.
		local tie = view({ players = { player(1, "Me", 2, 1), player(2, "Ana", 2, 1) } })
		expect.equal(MatchFormat.leader(tie).displayName, "Me")
		-- No timer (phaseEndsAt 0): 0:00.
		expect.equal(
			MatchFormat.readout(view({ phaseEndsAt = 0 }), 1000, TEXTS, TEAMS),
			"K.O. 3/25 · 1st Bo 7 · 0:00"
		)
		-- While the players are moved to the map (Positioning): "Get ready…" instead of the scores.
		expect.equal(MatchFormat.readout(view({ phase = "Positioning" }), 1000, TEXTS, TEAMS), "Get ready…")
	end)

	t.test("the TDM readout: both teams' lives, the storm bar, overtime and the respawn wait", function()
		local tdm = view({
			mode = "tdm",
			koTarget = nil,
			teamLives = { Red = 38, Blue = 40 },
			matchPhase = "Overtime",
		})
		tdm.you.stormBar = 0.004
		expect.equal(MatchFormat.readout(tdm, 1000, TEXTS, TEAMS), "RED 38 · BLUE 40 · 2:05 · STORM 1% · OVERTIME")
		tdm.you.stormBar = 0
		tdm.you.alive = false
		tdm.you.respawnAt = 1002.2
		expect.equal(MatchFormat.readout(tdm, 1000, TEXTS, TEAMS), "RED 38 · BLUE 40 · 2:05 · OVERTIME · Back in 3")
		tdm.you.out = true
		expect.equal(MatchFormat.readout(tdm, 1000, TEXTS, TEAMS), "RED 38 · BLUE 40 · 2:05 · OVERTIME · OUT")
		-- No lives table yet: 0 and 0.
		expect.equal(
			MatchFormat.readout(view({ mode = "tdm", phaseEndsAt = 0 }), 1000, TEXTS, TEAMS),
			"RED 0 · BLUE 0 · 0:00"
		)
	end)

	t.test("readout pieces: a missing text is left out; percent and seconds round up", function()
		local blank = table.clone(TEXTS)
		blank.storm = ""
		blank.waiting = ""
		local stormy = view()
		stormy.you.stormBar = 0.5
		expect.equal(MatchFormat.readout(stormy, 1000, blank, TEAMS), "K.O. 3/25 · 1st Bo 7 · 2:05")
		-- No waiting text: the scores show in Positioning too.
		expect.equal(
			MatchFormat.readout(view({ phase = "Positioning" }), 1000, blank, TEAMS),
			"K.O. 3/25 · 1st Bo 7 · 2:05"
		)
		expect.equal(MatchFormat.stormPercent(0), 0)
		expect.equal(MatchFormat.stormPercent(0.001), 1)
		expect.equal(MatchFormat.stormPercent(0.5), 50)
		expect.equal(MatchFormat.stormPercent(1), 100)
		expect.equal(MatchFormat.stormPercent(0 / 0), 0)
		expect.equal(MatchFormat.respawnSeconds(1003, 1000), 3)
		expect.equal(MatchFormat.respawnSeconds(1000.1, 1000), 1)
		expect.equal(MatchFormat.respawnSeconds(999, 1000), 1) -- waiting for the server's respawn: still 1
		expect.equal(MatchFormat.timeLeft(view({ phaseEndsAt = 990 }), 1000), "0:00")
		expect.equal(MatchFormat.timeLeft(view({ phaseEndsAt = math.huge }), 1000), nil)
	end)

	t.test("the storm wall: only in a live TDM match from stormStartSeconds, at StormMath's radius", function()
		local start = 144
		local tdm = view({ mode = "tdm", storm = { startRadius = start } })
		expect.equal(MatchFormat.stormRadius(tdm, 1000 + 299, STORM), nil) -- before the storm starts
		expect.near(MatchFormat.stormRadius(tdm, 1000 + 300, STORM), start, 1e-9)
		expect.near(MatchFormat.stormRadius(tdm, 1000 + 330, STORM), StormMath.radiusAt(STORM, start, 330), 1e-9)
		expect.near(MatchFormat.stormRadius(tdm, 1000 + 999, STORM), start * 0.3, 1e-9)
		expect.equal(MatchFormat.stormRadius(view(), 1000 + 330, STORM), nil) -- FFA: no storm
		local result = view({ mode = "tdm", storm = { startRadius = start }, phase = "Result" })
		expect.equal(MatchFormat.stormRadius(result, 1000 + 330, STORM), nil) -- not live
		local noStart = view({ mode = "tdm", storm = { startRadius = start }, activeStartedAt = nil })
		noStart.activeStartedAt = nil
		expect.equal(MatchFormat.stormRadius(noStart, 1000 + 330, STORM), nil)
	end)

	-- Power-ups v1.1 (2026-10-16) ---------------------------------------------------------------------------------

	-- As Config.Match.PowerUps.order (passed in).
	local ORDER = { "shield", "speed", "throwBoost", "ultCharge", "dashBoost", "rapidThrow", "superJump", "teamLife" }

	t.test("power-ups: the live ones in order with seconds left, listed in the readout after overtime", function()
		local texts: any = table.clone(TEXTS)
		texts.powerUp = "{name} {seconds}s"
		texts.powerUpNames = { speed = "SPEED", throwBoost = "THROW BOOST", rapidThrow = "RAPID THROW" }
		local v = view({ matchPhase = "Overtime" })
		v.you.buffs = { rapidThrow = 1000.2, speed = 1003.5, throwBoost = 999, superJump = 1004 }
		expect.deepEqual(MatchFormat.powerUpsLeft(v, 1000, ORDER), {
			{ power = "speed", seconds = 4 },
			{ power = "rapidThrow", seconds = 1 },
			{ power = "superJump", seconds = 4 },
		})
		-- superJump has no name here: left out. The ended throw boost is not listed.
		expect.equal(
			MatchFormat.readout(v, 1000, texts, TEAMS, ORDER),
			"K.O. 3/25 · 1st Bo 7 · 2:05 · OVERTIME · SPEED 4s · RAPID THROW 1s"
		)
		-- No powerUp text (Strings without it): no power-up pieces.
		expect.equal(MatchFormat.readout(v, 1000, TEXTS, TEAMS, ORDER), "K.O. 3/25 · 1st Bo 7 · 2:05 · OVERTIME")
		-- No buffs table (a view from before power-ups): none.
		expect.deepEqual(MatchFormat.powerUpsLeft(view(), 1000, ORDER), {})
		-- Review fix: once the match is over (Result, Returning) the readout lists none, though the view still has them.
		local over = view({ phase = "Result", matchPhase = "Result" })
		over.you.buffs = { speed = 1003.5 }
		expect.equal(MatchFormat.readout(over, 1000, texts, TEAMS, ORDER), "K.O. 3/25 · 1st Bo 7 · 2:05")
		over.phase = "Returning"
		expect.equal(MatchFormat.readout(over, 1000, texts, TEAMS, ORDER), "K.O. 3/25 · 1st Bo 7 · 2:05")
	end)

	t.test("power-ups: a pad's refill plays once per pickup, only while it lies ahead", function()
		expect.near(MatchFormat.padCollectSeconds(1020, nil, 1000), 20, 1e-9)
		expect.near(MatchFormat.padCollectSeconds(1040, 1020, 1021), 19, 1e-9) -- the next pickup of that pad
		expect.equal(MatchFormat.padCollectSeconds(1020, 1020, 1001), nil) -- already played
		expect.equal(MatchFormat.padCollectSeconds(0, nil, 1000), nil) -- ready
		expect.equal(MatchFormat.padCollectSeconds(1000, nil, 1000), nil) -- refilled just now
		expect.equal(MatchFormat.padCollectSeconds(-math.huge, nil, 1000), nil)
		expect.equal(MatchFormat.padCollectSeconds(0 / 0, nil, 1000), nil)
	end)

	t.test(
		"power-ups review fix: Diego's refill ends a head start early; one shorter than his pop is not played",
		function()
			-- One pickup sample (5 Hz) early, so his Collect is ready again before the server can report the next pickup.
			expect.near(MatchFormat.collectRefill(20, 0.2, 0.4) :: number, 19.8, 1e-9)
			expect.near(MatchFormat.collectRefill(20, 0, 0.4) :: number, 20, 1e-9) -- no head start
			expect.near(MatchFormat.collectRefill(20, 0 / 0, 0.4) :: number, 20, 1e-9) -- a bad head start counts as none
			expect.near(MatchFormat.collectRefill(20, -1, 0.4) :: number, 20, 1e-9) -- never later than the server
			expect.equal(MatchFormat.collectRefill(0.5, 0.2, 0.4), nil) -- 0.3 s: shorter than his pop
			expect.near(MatchFormat.collectRefill(0.7, 0.2, 0.4) :: number, 0.5, 1e-9) -- longer than the pop: played
			expect.equal(MatchFormat.collectRefill(0 / 0, 0.2, 0.4), nil)
		end
	)

	-- Music job (2026-10-16): the local player's result of a finished match (MatchController's result sting).
	local function ended(you: any, outcome: any): any
		return { you = you, outcome = outcome }
	end

	t.test("resultOf: FFA and TDM wins and losses, draws; nothing for cancelled, void or no outcome", function()
		local me = { userId = 1 } -- FFA: no team
		expect.equal(MatchFormat.resultOf(ended(me, { kind = "win", winnerUserId = 1, winners = { 1 } })), "win")
		expect.equal(MatchFormat.resultOf(ended(me, { kind = "win", winnerUserId = 2, winners = { 2 } })), "loss")
		local red = { userId = 1, team = "Red" }
		expect.equal(MatchFormat.resultOf(ended(red, { kind = "win", winnerTeam = "Red", winners = { 1, 3 } })), "win")
		expect.equal(MatchFormat.resultOf(ended(red, { kind = "win", winnerTeam = "Blue", winners = { 2 } })), "loss")
		-- TDM: both teams wiped at once is a draw for everyone.
		expect.equal(MatchFormat.resultOf(ended(red, { kind = "draw", winners = {} })), "draw")
		-- FFA: overtime ran out tied: the tied leaders draw, the others lose; no leaders listed: a draw.
		local tie = { kind = "draw", winners = { 1, 4 } }
		expect.equal(MatchFormat.resultOf(ended(me, tie)), "draw")
		expect.equal(MatchFormat.resultOf(ended({ userId = 9 }, tie)), "loss")
		expect.equal(MatchFormat.resultOf(ended(me, { kind = "draw", winners = {} })), "draw")
		-- Nothing to sting.
		expect.equal(MatchFormat.resultOf(ended(me, nil)), nil)
		expect.equal(MatchFormat.resultOf(ended(me, { kind = "cancelled", winners = {} })), nil)
		expect.equal(MatchFormat.resultOf(ended(me, { kind = "void", winners = {} })), nil)
		expect.equal(MatchFormat.resultOf(nil), nil)
		-- A view without `you` (malformed) never wins.
		expect.equal(MatchFormat.resultOf({ outcome = { kind = "win", winnerUserId = 1, winners = { 1 } } }), "loss")
	end)

	t.test("resultOf agrees with the server's MatchRewards (the win streak), and each result has its jingle", function()
		local MatchRewards = t.requireServer("Logic/MatchRewards")
		local DuelFormat = t.requireClient("UI/DuelFormat")
		local AssetTable = t.requireShared("AssetTable")
		local outcomes: { any } = {
			{ kind = "win", winnerUserId = 1, winners = { 1 } },
			{ kind = "win", winnerUserId = 2, winners = { 2 } },
			{ kind = "win", winnerTeam = "Red", winners = { 1 } },
			{ kind = "win", winnerTeam = "Blue", winners = { 2 } },
			{ kind = "draw", winners = {} },
			{ kind = "draw", winners = { 1, 2 } },
			{ kind = "draw", winners = { 2, 3 } },
			{ kind = "cancelled", winners = {} },
			{ kind = "void", winners = {} },
		}
		local jingles = { win = "duel.win", loss = "duel.lose", draw = "duel.draw" }
		-- Review fix (2026-10-16): each jingle is a sound slot; its id comes from the owner's pick (the sound picker).
		local soundKeys: { [string]: boolean } = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" then
				soundKeys[slot.key] = true
			end
		end
		for _, outcome in outcomes do
			for _, team in { "Red", "Blue", "" } do -- "" = FFA (no team)
				local you = { userId = 1, team = if team ~= "" then team else nil }
				local pay = MatchRewards.forPlayer(outcome, {
					userId = 1,
					team = you.team,
					present = true,
					isBot = false,
					throws = 3,
				})
				local result = MatchFormat.resultOf(ended(you, outcome))
				expect.equal(result, if pay then pay.result else nil)
				if result ~= nil then
					local jingle = DuelFormat.resultStyle(result).jingle
					expect.equal(jingle, jingles[result])
					expect.truthy(soundKeys[jingle] == true)
				end
			end
		end
	end)
end
