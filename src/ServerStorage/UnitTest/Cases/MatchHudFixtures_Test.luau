--!strict
-- MatchHudFixtures_Test: StarterPlayerScripts.Client.Studio.MatchHudFixtures (Match HUD M4, 2026-10-16: the pretend
-- match states of the Studio preview; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.9). Server only
-- (ServerStorage.UnitTest). Pure data through StateController's own parsers (no instances).
-- Contract:
--   * every listed state builds a view, its moments, roster and Result freeze through StateController's parsers
--     (reduceMatch, newMatchMoments, nextMatchRoster, nextMatchResult); unknown states and an FFA storm give nil;
--   * the roster: you (your userId) and pretend players with negative userIds and real Catalog squishies; TDM 6 v 6
--     with you on Red, FFA 12; opts.players 4 gives Diego's 2 v 2 (TDM) and a 4-player FFA;
--   * the moments the screens need: FIRST BLOOD (one K.O., seq 1), your squish, you knocked out with 2 s (knockedOut)
--     or 0.7 s (respawnBar) to your respawn, your three in a row (streak 1, 2, 3), a fall with no attacker (feedBusy);
--   * the endings: endWin / endLose carry the final squish (by you / on you, cause "hit", final) and the pay with your
--     win streak (up / reset); TDM endings are wipes (the losing team has no life, everyone on it out); draw and
--     cancelled have no final squish; every ending is the Result freeze;
--   * the phases: waiting = Positioning (Waiting), countdown = Countdown, overtime = Active (Overtime), storm = TDM with
--     the storm up and your bar at 0.6.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local NOW = 1.8e9
local YOU = 4242

return function(t: Context)
	local expect = t.expect
	local Fixtures = t.requireClient("Studio/MatchHudFixtures")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local MATCH = Config.Match
	local RED, BLUE = MATCH.teamNames[1], MATCH.teamNames[2]

	local function build(state: string, players: number?): any
		local fixture = Fixtures.build(state, NOW, { youId = YOU, youName = "Tester", players = players })
		assert(fixture ~= nil, "no fixture for " .. state)
		return fixture
	end

	local function player(view: any, userId: number): any
		for _, p in view.players do
			if p.userId == userId then
				return p
			end
		end
		return nil
	end

	local function teamCount(view: any, team: string): number
		local n = 0
		for _, p in view.players do
			if p.team == team then
				n += 1
			end
		end
		return n
	end

	t.test("every state builds through StateController's parsers; unknown states give nil", function()
		expect.truthy(#Fixtures.STATES >= 30)
		for _, state in Fixtures.STATES do
			local fixture = build(state)
			local mode = string.match(state, "^(%a+)_")
			expect.equal(fixture.view.mode, mode)
			expect.equal(fixture.view.you.userId, YOU)
			expect.truthy(fixture.roster ~= nil and fixture.roster.matchId == fixture.view.matchId)
		end
		expect.equal(Fixtures.build("tdm_nope", NOW), nil)
		expect.equal(Fixtures.build("ffa_storm", NOW), nil) -- no storm in FFA
		expect.equal(Fixtures.payload("nope", NOW), nil)
		expect.equal(table.find(Fixtures.STATES, "ffa_storm"), nil)
	end)

	t.test("roster: you plus pretend players with negative ids and Catalog squishies; 6 v 6, 12, or 2 v 2", function()
		local tdm = build("tdm_live").view
		expect.equal(#tdm.players, 12)
		expect.equal(teamCount(tdm, RED), 6)
		expect.equal(teamCount(tdm, BLUE), 6)
		expect.equal(tdm.you.team, RED)
		expect.equal(tdm.you.displayName, "Tester")
		for _, p in tdm.players do
			expect.truthy(p.userId == YOU or p.userId < 0)
			expect.truthy(Catalog.isValidId(p.squishyId))
		end
		local ffa = build("ffa_live").view
		expect.equal(#ffa.players, 12)
		expect.equal(ffa.koTarget, MATCH.Modes.ffa.koTarget)
		local small = build("tdm_live", 4).view
		expect.equal(teamCount(small, RED), 2)
		expect.equal(teamCount(small, BLUE), 2)
		expect.equal(#build("ffa_feedBusy", 4).view.players, 4)
	end)

	t.test("moments: FIRST BLOOD, your squish, your three in a row, a fall with no attacker", function()
		local first = build("tdm_firstBlood").moments
		expect.equal(#first, 1)
		expect.equal(first[1].seq, 1)
		expect.equal(first[1].kind, "ko")
		expect.truthy(first[1].by ~= nil and first[1].by ~= YOU)
		local mine = build("ffa_yourSquish").moments
		expect.equal(mine[#mine].by, YOU)
		local score = build("tdm_score").moments
		expect.deepEqual({ score[1].streak, score[2].streak, score[3].streak }, { 1, 2, 3 })
		local busy = build("tdm_feedBusy").moments
		expect.equal(#busy, 3)
		expect.equal(busy[3].cause, "outOfBounds")
		expect.equal(busy[3].by, nil)
		-- TDM: K.O.s cost the victim's team a life (livesLeft), never a teammate's squish.
		local view = build("tdm_feedBusy").view
		for _, moment in busy do
			if moment.by then
				expect.truthy(player(view, moment.by).team ~= player(view, moment.victim).team)
			end
			expect.truthy(moment.livesLeft ~= nil)
		end
	end)

	t.test("knocked out: you are down with 2 s (knockedOut) or 0.7 s (respawnBar) to your respawn", function()
		local down = build("tdm_knockedOut")
		expect.equal(down.view.you.alive, false)
		expect.near(down.view.you.respawnAt - NOW, MATCH.respawnSeconds - 1, 1e-6)
		expect.equal(down.moments[1].victim, YOU)
		local bar = build("ffa_respawnBar").view
		expect.near(bar.you.respawnAt - NOW, MATCH.respawnSeconds - 2.3, 1e-6)
	end)

	t.test("endings: the final squish, the pay and the Result freeze", function()
		for _, mode in { "tdm", "ffa" } do
			local win = build(mode .. "_endWin")
			local outcome = win.view.outcome
			expect.equal(win.view.phase, "Result")
			expect.equal(outcome.kind, "win")
			expect.equal(outcome.finalKo.by, YOU)
			expect.equal(outcome.finalKo.cause, "hit")
			expect.equal(outcome.finalKo.final, true)
			expect.truthy(table.find(outcome.winners, YOU) ~= nil)
			expect.truthy(outcome.mine.streakAfter > outcome.mine.streakBefore)
			expect.equal(win.result, win.view)
			expect.truthy(#outcome.standings == #win.view.players)
			local lose = build(mode .. "_endLose")
			expect.equal(lose.view.outcome.finalKo.victim, YOU)
			expect.equal(table.find(lose.view.outcome.winners, YOU), nil)
			expect.equal(lose.view.outcome.mine.streakAfter, 0)
			for _, state in { mode .. "_draw", mode .. "_cancelled" } do
				local other = build(state)
				expect.equal(other.view.outcome.finalKo, nil)
				expect.equal(other.result, other.view)
			end
		end
		expect.equal(build("ffa_endWin").view.outcome.winnerUserId, YOU)
		expect.equal(build("tdm_endWin").view.outcome.winnerTeam, RED)
		expect.equal(build("tdm_cancelled").view.outcome.mine, nil)
	end)

	t.test("TDM endings are wipes: the losing team has no life and everyone on it is out", function()
		local win = build("tdm_endWin").view
		expect.equal(win.teamLives[BLUE], 0)
		expect.equal(win.outcome.reason, "wiped")
		for _, p in win.players do
			if p.team == BLUE then
				expect.equal(p.out, true)
			end
		end
		local lose = build("tdm_endLose").view
		expect.equal(lose.teamLives[RED], 0)
		expect.equal(lose.you.out, true)
		expect.equal(lose.outcome.winnerTeam, BLUE)
	end)

	t.test("phases: waiting, countdown, overtime and the storm", function()
		local waiting = build("ffa_waiting").view
		expect.equal(waiting.phase, "Positioning")
		expect.equal(waiting.matchPhase, "Waiting")
		local count = build("tdm_countdown3").view
		expect.equal(count.phase, "Countdown")
		expect.near(count.phaseEndsAt - NOW, MATCH.countdownSeconds, 1e-6)
		local overtime = build("tdm_overtime").view
		expect.equal(overtime.phase, "Active")
		expect.equal(overtime.matchPhase, "Overtime")
		local storm = build("tdm_storm").view
		expect.truthy(storm.storm ~= nil)
		expect.near(storm.you.stormBar, 0.6, 1e-6)
		expect.truthy(NOW - storm.activeStartedAt > MATCH.Storm.stormStartSeconds)
		local powered = build("ffa_powerUps").view
		expect.truthy(next(powered.you.buffs) ~= nil)
	end)
end
