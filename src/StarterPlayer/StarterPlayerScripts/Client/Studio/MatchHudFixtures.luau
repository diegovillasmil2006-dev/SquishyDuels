--!strict
-- MatchHudFixtures (client only, Studio only: MatchHudController.debugShow, DebugHooks "matchHud", tests). Match HUD M4
-- (2026-10-16; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.9): pretend match states, so one Play session (one
-- client, as the Studio MCP drives) shows every in-match screen of Diego's "Squishy Duels Match HUD.dc.html" (M) with
-- pretend players, and LayoutAudit checks each one. A state is a MatchState payload (Types.MatchStateView with its HUD
-- `events`) built around `now` (server time), made into the client's view by StateController's own parsers
-- (reduceMatch, newMatchMoments, nextMatchRoster, nextMatchResult), exactly as a real MatchState is.
-- * States "<mode>_<moment>", modes tdm (6 v 6: Red = Strawberry with you, Blue = Blueberry) and ffa (12); the
--   moments follow the render index work/matchhud2/shots/INDEX.md: waiting (boot cover + intro card), countdown3,
--   countdownGo, live, firstBlood (FIRST BLOOD feed line), yourSquish (SQUISHED! medal), knockedOut (card + respawn
--   bar, 2 s left), knockedOutFall / knockedOutStorm (tdm only) (Match HUD M7: the same with nobody to blame: the card's
--   fall / storm version), respawnBar (0.7 s left), score (mid match, your TRIPLE), feedBusy (three K.O.s, one a fall with no
--   attacker), overtime, storm (tdm only: the storm up, your bar at 60 %), protected (spawn protection), powerUps (your
--   live power-ups), endWin, endLose (each with its final squish: the replay and the podium use these two), draw
--   (overtime ran out) and cancelled.
-- * Pretend players: you (the local player's userId and display name; -1000 "You" without one) and up to 11 others
--   with negative userIds -1001 ... -1011 (no real person's avatar head loads: pieces fall back to the toy picture,
--   v1 §1.8), named from M:387's NAMES list, each with a Catalog squishy. opts.players (4..12; TDM rounds down to
--   even) shrinks the roster to compare with Diego's renders (TDM 2v2, FFA 6: shots/INDEX.md).
-- * Numbers come from Config.Match (lives, K.O. target, timers); rewards are pretend amounts. Debug data, never shown
--   to players.
-- API: STATES (in order); payload(state, now, opts?) -> Types.MatchStateView?; build(state, now, opts?) -> Fixture?

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StormMath = require(Shared.StormMath)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local StateController = require(Client.Controllers.StateController)

-- Types

export type Options = {
	players: number?, -- roster size (4..12), default 12
	youId: number?, -- default: the local player's userId, else YOU_FALLBACK_ID
	youName: string?,
}

export type Fixture = {
	state: string,
	view: StateController.MatchView,
	moments: { StateController.MatchMoment },
	roster: StateController.MatchRoster?,
	result: StateController.MatchView?,
}

-- Constants

local MATCH = Config.Match
local RED, BLUE = MATCH.teamNames[1], MATCH.teamNames[2]
local MAX_PLAYERS = 12
local MIN_PLAYERS = 4 -- feedBusy needs a teammate and two others
local YOU_FALLBACK_ID = -1000
local YOU_FALLBACK_NAME = "You"
local YOU_SQUISHY = "kitty_bread" -- shots/INDEX.md: "p0 is always You, Kitty Bread"
local OTHER_FIRST_ID = -1001
-- M:387 NAMES (the first 11) and a Catalog squishy each.
local OTHERS = {
	{ "MochiMaster", "toast" },
	{ "xXBobaXx", "banana" },
	{ "SquishQueen", "butter" },
	{ "ToastyBoi", "chocolate" },
	{ "JellyBean_7", "bird" },
	{ "PuddingPop", "donut" },
	{ "NoodleNinja", "dragon" },
	{ "BunBunz", "boba_bear" },
	{ "SprinkleKid", "pancake_pup" },
	{ "CocoaCat", "mochi_fox" },
	{ "WobbleWiz", "strawberry_frog" },
}
local MAPS = {
	tdm = { code = "TBC", name = "ToyBoxClash", x = 6000, footprint = Vector3.new(160, 0, 240) },
	ffa = { code = "JAR", name = "JellyArcade", x = 7500, footprint = Vector3.new(200, 0, 200) },
}
local MOMENTS = {
	"waiting",
	"countdown3",
	"countdownGo",
	"live",
	"firstBlood",
	"yourSquish",
	"knockedOut",
	"knockedOutFall",
	"knockedOutStorm",
	"respawnBar",
	"score",
	"feedBusy",
	"overtime",
	"storm",
	"protected",
	"powerUps",
	"endWin",
	"endLose",
	"draw",
	"cancelled",
}
local TDM_ONLY: { [string]: boolean } = { storm = true, knockedOutStorm = true }
local LIVE_FOR = 20 -- live: seconds since Active began
local SCORE_FOR = 240 -- score: mid match

-- Module table

local MatchHudFixtures = {}

MatchHudFixtures.STATES = {} :: { string }
for _, mode in { "tdm", "ffa" } do
	for _, moment in MOMENTS do
		if mode == "tdm" or not TDM_ONLY[moment] then
			table.insert(MatchHudFixtures.STATES, mode .. "_" .. moment)
		end
	end
end

-- Private

type Builder = {
	p: any, -- the payload being built
	now: number,
	you: any, -- the own players entry
	ids: { number }, -- every userId, you first
	seq: number,
}

local function entry(p: any, userId: number): any
	for _, player in p.players do
		if player.userId == userId then
			return player
		end
	end
	return nil
end

-- One K.O. moment (MatchRules' ko effect as MatchService records it): the attacker's streak, the victim knocked out
-- and respawning; TDM: the respawn costs the team a life, and with none left the victim is out (no respawn).
local function ko(b: Builder, victimId: number, byId: number?, ago: number, cause: string?, final: boolean?)
	local p = b.p
	local at = b.now - ago
	local victim = entry(p, victimId)
	local by = if byId then entry(p, byId) else nil
	if by then
		by.kos += 1
		by.streak += 1
		by.bestStreak = math.max(by.bestStreak, by.streak)
	end
	victim.knockedOut += 1
	victim.streak = 0
	victim.alive = false
	victim.respawnAt = at + MATCH.respawnSeconds
	if p.teamScore then -- 2026-10-26: the other team scores
		local scorer = if by then by.team else (if victim.team == RED then BLUE else RED)
		p.teamScore[scorer] += 1
	end
	b.seq += 1
	table.insert(p.events, {
		seq = b.seq,
		kind = "ko",
		at = at,
		victim = victimId,
		by = byId,
		cause = cause or "hit",
		final = final == true,
		streak = if by then by.streak else nil,
	})
end

-- Sets kos so the list goes down from `top` (an FFA leader board; TDM a spread).
local function spread(p: any, top: number)
	for index, player in p.players do
		player.kos = math.max(0, top - (index - 1) * 2)
		player.knockedOut = math.max(0, math.floor(top / 2) - index + 3)
	end
end

local function standings(p: any): { Types.MatchStandingView }
	local list = {}
	for index, player in p.players do
		table.insert(list, { player = player, index = index })
	end
	table.sort(list, function(a: any, b: any): boolean
		if a.player.kos ~= b.player.kos then
			return a.player.kos > b.player.kos
		elseif a.player.knockedOut ~= b.player.knockedOut then
			return a.player.knockedOut < b.player.knockedOut
		end
		return a.index < b.index
	end)
	local out: { Types.MatchStandingView } = {}
	for _, item in list do
		local player = item.player
		table.insert(out, {
			userId = player.userId,
			kos = player.kos,
			knockedOut = player.knockedOut,
			bestStreak = player.bestStreak,
			grip = 70 + 15 * player.kos, -- end screens round A: the scoreboard's +Grip (T:212's prototype numbers)
		})
	end
	return out
end

local function base(mode: string, now: number, opts: Options?): Builder
	local o: Options = opts or {}
	local isTdm = mode == "tdm"
	local count = math.clamp(math.floor(o.players or MAX_PLAYERS), MIN_PLAYERS, MAX_PLAYERS)
	if isTdm then
		count -= count % 2
	end
	local localPlayer = Players.LocalPlayer
	local youId = o.youId or (if localPlayer then localPlayer.UserId else YOU_FALLBACK_ID)
	local youName = o.youName or (if localPlayer then localPlayer.DisplayName else YOU_FALLBACK_NAME)
	local players = {}
	local ids = {}
	for index = 1, count do
		local isYou = index == 1
		local other = if isYou then nil else OTHERS[index - 1]
		local userId = if isYou then youId else OTHER_FIRST_ID - (index - 2)
		table.insert(ids, userId)
		table.insert(players, {
			userId = userId,
			displayName = if other then other[1] else youName,
			squishyId = if other then other[2] else YOU_SQUISHY,
			team = if isTdm then (if index <= count / 2 then RED else BLUE) else nil,
			kos = 0,
			knockedOut = 0,
			alive = true,
			ultReady = false,
			respawnAt = nil,
			out = false,
			protectUntil = 0,
			streak = 0,
			bestStreak = 0,
			arrived = true, -- round 1 of the match screens: "waiting" holds some back
			level = 1 + ((index * 17) % 60), -- pretend Grip levels, spread like Diego's roster
		})
	end
	local modeRules = MATCH.Modes[mode]
	local map = MAPS[mode]
	local centre = Vector3.new(map.x, 0, 0)
	local p = {
		matchId = "match:preview-" .. mode,
		mode = mode,
		mapCode = map.code,
		mapName = map.name,
		phase = "Active",
		matchPhase = "Active",
		phaseEndsAt = now + modeRules.matchSeconds - LIVE_FOR,
		activeStartedAt = now - LIVE_FOR,
		you = {
			userId = youId,
			team = players[1].team,
			alive = true,
			respawnAt = nil,
			protectUntil = 0,
			stormBar = 0,
			out = false,
			buffs = {},
		},
		players = players,
		teamScore = if isTdm then { [RED] = 0, [BLUE] = 0 } else nil,
		koTarget = modeRules.koTarget,
		arena = {
			floorY = 0,
			bounds = { cframe = CFrame.new(centre), size = map.footprint + Vector3.new(0, 100, 0) },
			centre = centre,
		},
		storm = if isTdm then { startRadius = StormMath.startRadius(map.footprint) } else nil,
		outcome = nil,
		pads = {},
		events = {},
	}
	return { p = p, now = now, you = players[1], ids = ids, seq = 0 }
end

-- Syncs `you` with the own players entry (alive, respawn) after the moments changed it.
local function syncYou(b: Builder)
	local you, own = b.p.you, b.you
	you.alive = own.alive
	you.respawnAt = own.respawnAt
	you.out = own.out
	you.protectUntil = own.protectUntil
end

-- The userIds of a TDM team (in roster order).
local function teamIds(b: Builder, team: string?): { number }
	local out = {}
	for _, player in b.p.players do
		if player.team == team then
			table.insert(out, player.userId)
		end
	end
	return out
end

-- Someone who may squish `id`, never you when someone else can: TDM the first player of the other team; FFA the first
-- player who is neither `id` nor you.
local function foe(b: Builder, id: number): number
	local p = b.p
	if p.mode == "tdm" then
		local side = teamIds(b, if entry(p, id).team == RED then BLUE else RED)
		for _, other in side do
			if other ~= b.ids[1] then
				return other
			end
		end
		return side[1]
	end
	for _, other in b.ids do
		if other ~= id and other ~= b.ids[1] then
			return other
		end
	end
	return b.ids[1]
end

-- Your enemies in roster order (TDM: the Blue team; FFA: everyone else).
local function enemies(b: Builder): { number }
	if b.p.mode == "tdm" then
		return teamIds(b, BLUE)
	end
	return { table.unpack(b.ids, 2) }
end

local function last(b: Builder): number
	return b.ids[#b.ids]
end

local function finish(b: Builder, kind: string, reason: string, winners: { number }, mine: any?)
	local p = b.p
	p.phase = "Result"
	p.matchPhase = "Result"
	p.phaseEndsAt = b.now + MATCH.resultSeconds
	local finalKo = nil
	for _, event in p.events do
		if event.final then
			finalKo = table.clone(event)
		end
	end
	p.outcome = {
		kind = kind,
		reason = reason,
		winnerUserId = if p.mode == "ffa" and kind == "win" then winners[1] else nil,
		winnerTeam = if p.mode == "tdm" and kind == "win" then entry(p, winners[1]).team else nil,
		winners = winners,
		finalKo = finalKo,
		standings = if kind == "win" or kind == "draw" then standings(p) else {},
		mine = mine,
	}
end

-- TDM endings (2026-10-26, first to koTarget): `winner` stands one short of it (the other team at 24: Diego's 30-24);
-- `killer` squishes `victim` for the last point (the final K.O., the outcome reason "koTarget").
local function lastPoint(b: Builder, winner: string, victim: number, killer: number)
	local p = b.p
	spread(p, 9)
	p.teamScore[winner] = (MATCH.Modes.tdm.koTarget :: number) - 1
	p.teamScore[if winner == RED then BLUE else RED] = 24
	ko(b, victim, killer, 0.5, "hit", true)
	syncYou(b)
end

local WIN_PAY = { coins = 1200, grip = 45000, streakBefore = 2, streakAfter = 3 }
local LOSE_PAY = { coins = 360, grip = 12000, streakBefore = 3, streakAfter = 0 }
local DRAW_PAY = { coins = 600, grip = 20000, streakBefore = 3, streakAfter = 0 }

local STEPS: { [string]: (b: Builder) -> () } = {
	waiting = function(b)
		b.p.phase = "Positioning"
		b.p.matchPhase = "Waiting"
		b.p.phaseEndsAt = b.now + MATCH.waitSeconds
		b.p.activeStartedAt = nil
		-- Round 1 of the match screens: the intro's cards, every third player still loading (you are in).
		for index, player in b.p.players do
			player.arrived = index % 3 ~= 0
		end
	end,
	countdown3 = function(b)
		b.p.phase = "Countdown"
		b.p.matchPhase = "Countdown"
		b.p.phaseEndsAt = b.now + MATCH.countdownSeconds
		b.p.activeStartedAt = nil
	end,
	countdownGo = function(b)
		b.p.phase = "Countdown"
		b.p.matchPhase = "Countdown"
		b.p.phaseEndsAt = b.now + 0.15
		b.p.activeStartedAt = nil
	end,
	live = function(_b) end,
	firstBlood = function(b)
		ko(b, last(b), foe(b, last(b)), 0.7)
	end,
	yourSquish = function(b)
		ko(b, last(b), foe(b, last(b)), 6)
		ko(b, enemies(b)[1], b.ids[1], 0.65)
	end,
	knockedOut = function(b)
		ko(b, b.ids[1], foe(b, b.ids[1]), 1)
		syncYou(b)
	end,
	-- Match HUD M7: squished with nobody to blame (owner 2026-10-16: a card and a feed line for these too).
	knockedOutFall = function(b)
		ko(b, b.ids[1], nil, 1, "outOfBounds")
		syncYou(b)
	end,
	knockedOutStorm = function(b)
		local p = b.p
		local since = MATCH.Storm.stormStartSeconds + 60
		p.activeStartedAt = b.now - since
		p.phaseEndsAt = b.now + MATCH.Modes[p.mode].matchSeconds - since
		ko(b, b.ids[1], nil, 1, "storm")
		syncYou(b)
	end,
	respawnBar = function(b)
		ko(b, b.ids[1], foe(b, b.ids[1]), 2.3)
		syncYou(b)
	end,
	score = function(b)
		local p = b.p
		p.activeStartedAt = b.now - SCORE_FOR
		p.phaseEndsAt = b.now + MATCH.Modes[p.mode].matchSeconds - SCORE_FOR
		spread(p, if p.mode == "ffa" then 18 else 6)
		if p.teamScore then
			p.teamScore[RED], p.teamScore[BLUE] = 17, 14 -- Diego's review score (uploads/tdm-hud.js)
		end
		local victims = enemies(b)
		for i, ago in { 2.6, 1.4, 0.6 } do -- three in a row: DOUBLE!, TRIPLE! (M:521-526)
			ko(b, victims[(i - 1) % #victims + 1], b.ids[1], ago)
		end
	end,
	feedBusy = function(b)
		local mate, other = b.ids[2], last(b) -- TDM: your teammate and a Blue
		ko(b, other, foe(b, other), 1.2)
		ko(b, mate, foe(b, mate), 0.8)
		ko(b, foe(b, mate), nil, 0.3, "outOfBounds") -- no attacker: no feed row and no card (v1 §1.11)
	end,
	overtime = function(b)
		local p = b.p
		local seconds = MATCH.Modes[p.mode].matchSeconds
		p.matchPhase = "Overtime"
		p.activeStartedAt = b.now - seconds - 10
		p.phaseEndsAt = b.now + MATCH.overtimeMaxSeconds - 10
		spread(p, 12)
		if p.teamScore then
			p.teamScore[RED], p.teamScore[BLUE] = 22, 22
		else
			p.players[2].kos = p.players[1].kos -- a tie at the top
		end
	end,
	storm = function(b)
		local p = b.p
		local since = MATCH.Storm.stormStartSeconds + 60
		p.activeStartedAt = b.now - since
		p.phaseEndsAt = b.now + MATCH.Modes[p.mode].matchSeconds - since
		p.you.stormBar = 0.6
	end,
	protected = function(b)
		b.you.protectUntil = b.now + MATCH.spawnProtectSeconds - 0.3
		b.p.players[2].protectUntil = b.now + 1
		syncYou(b)
	end,
	powerUps = function(b)
		for _, power in MATCH.PowerUps.order do
			local kind = MATCH.PowerUps.kinds[power]
			if kind and kind.seconds then
				b.p.you.buffs[power] = b.now + kind.seconds * 0.7
			end
		end
	end,
	endWin = function(b)
		local victim = enemies(b)[1]
		if b.p.mode == "tdm" then
			lastPoint(b, RED, victim, b.ids[1])
			finish(b, "win", "koTarget", teamIds(b, RED), WIN_PAY)
		else
			spread(b.p, 23)
			b.you.kos = (MATCH.Modes.ffa.koTarget :: number) - 1
			ko(b, victim, b.ids[1], 0.5, "hit", true)
			finish(b, "win", "koTarget", { b.ids[1] }, WIN_PAY)
		end
	end,
	endLose = function(b)
		local killer = foe(b, b.ids[1])
		if b.p.mode == "tdm" then
			lastPoint(b, BLUE, b.ids[1], killer)
			finish(b, "win", "koTarget", teamIds(b, BLUE), LOSE_PAY)
		else
			spread(b.p, 23)
			entry(b.p, killer).kos = (MATCH.Modes.ffa.koTarget :: number) - 1
			ko(b, b.ids[1], killer, 0.5, "hit", true)
			syncYou(b)
			finish(b, "win", "koTarget", { killer }, LOSE_PAY)
		end
	end,
	draw = function(b)
		local p = b.p
		spread(p, 12)
		if p.teamScore then
			p.teamScore[RED], p.teamScore[BLUE] = 22, 22
		else
			p.players[2].kos = p.players[1].kos
		end
		finish(b, "draw", "overtimeTimeout", {}, DRAW_PAY)
	end,
	cancelled = function(b)
		finish(b, "cancelled", "notEnoughPlayers", {}, nil)
	end,
}

-- Public

-- The MatchState payload of `state` around server time `now` (nil for an unknown state).
function MatchHudFixtures.payload(state: string, now: number, opts: Options?): Types.MatchStateView?
	local mode, moment = string.match(state, "^(%a+)_(%w+)$")
	if mode == nil or moment == nil or MAPS[mode] == nil or (mode ~= "tdm" and TDM_ONLY[moment]) then
		return nil
	end
	local step = STEPS[moment]
	if step == nil then
		return nil
	end
	local b = base(mode, now, opts)
	step(b)
	return b.p :: any
end

-- The client's view of `state`, its moments (in seq order), its roster and its Result freeze, all from
-- StateController's own parsers; nil for an unknown state (or a payload the parser refuses).
function MatchHudFixtures.build(state: string, now: number, opts: Options?): Fixture?
	local payload = MatchHudFixtures.payload(state, now, opts)
	if payload == nil then
		return nil
	end
	local view = StateController.reduceMatch(nil, { kind = "state", state = payload, now = os.clock() })
	if view == nil then
		return nil
	end
	local moments = StateController.newMatchMoments(0, payload.events)
	return {
		state = state,
		view = view,
		moments = moments,
		roster = StateController.nextMatchRoster(nil, view),
		result = StateController.nextMatchResult(nil, view),
	}
end

return MatchHudFixtures
