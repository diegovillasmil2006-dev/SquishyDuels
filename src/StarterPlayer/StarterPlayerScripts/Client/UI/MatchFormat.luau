--!strict
-- MatchFormat (client only, pure). FFA/TDM v1 (2026-10-15; the 12-player Free for All / Team Deathmatch inside the
-- lobby server, SPEC D6, D11, D13): what MatchController shows and sends, as plain data, so it is unit-tested in Edit
-- mode. Views are StateController.MatchView tables; times are server times (workspace:GetServerTimeNow()).
--   commandOf(text) -> (action?, mode?)      a chat message as a match command (D6): "/ffa" and "/tdm" give
--                                            ("join", mode), "/leave" gives ("leave"); its first word only, any
--                                            case; anything else nil. COMMANDS lists the three (aliases: none).
--   readout(view, now, texts?, teamNames?)   the TEST READOUT chip's text until Diego's arena HUD (D13), from the
--                                            Strings under match.readout (texts(); tests pass their own): the mode's
--                                            piece (FFA `ffa` "K.O. {mine}/{target} · 1st {leaderName} {leaderKos} ·
--                                            {time}", TDM `tdm` "RED {redLives} · BLUE {blueLives} · {time}"; `waiting`
--                                            "Get ready…" while players arrive, Positioning), then the pieces that
--                                            apply: `storm` "STORM {pct}%" while the own storm bar is above 0,
--                                            `overtime` in overtime, `backIn` "Back in {seconds}" while knocked out
--                                            (`out` "OUT" in TDM with no team life left), joined with `separator`. A
--                                            missing text leaves its piece out. {time} = the phase timer, "0:00"
--                                            without one.
--   leader(view) -> MatchPlayer?             FFA: the leader (most K.O.s, then fewest times knocked out, then the
--                                            players' order, as the server's MatchRules.standings)
--   timeLeft(view, now) -> string?           the phase timer "m:ss" (TimeUtil.formatCountdown); nil without a timer
--   stormPercent(bar) -> number              the storm bar 0..1 as a whole percent; any bar above 0 shows at least 1
--   respawnSeconds(respawnAt, now) -> number whole seconds until the respawn, at least 1 while waiting
--   stormRadius(view, now, storm) -> number? the storm's safe radius now (StormMath, with the server-synced Active
--                                            time), nil while it is not up: no storm (FFA), not live, before
--                                            stormStartSeconds
--   texts() -> Texts                         the readout's texts from Strings (match.readout.*; "" when missing)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StormMath = require(Shared.StormMath)
local Strings = require(Shared.Strings)
local TimeUtil = require(Shared.Util.TimeUtil)

-- Types

export type Texts = {
	ffa: string, -- "K.O. {mine}/{target} · 1st {leaderName} {leaderKos} · {time}"
	tdm: string, -- "RED {redLives} · BLUE {blueLives} · {time}"
	waiting: string, -- "Get ready…"
	storm: string, -- "STORM {pct}%"
	overtime: string, -- "OVERTIME"
	backIn: string, -- "Back in {seconds}"
	out: string, -- "OUT"
	separator: string, -- " · "
}

-- Constants

local TEXT_KEYS: { [string]: string } = {
	ffa = "match.readout.ffa",
	tdm = "match.readout.tdm",
	waiting = "match.readout.waiting",
	storm = "match.readout.storm",
	overtime = "match.readout.overtime",
	backIn = "match.readout.backIn",
	out = "match.readout.out",
	separator = "match.readout.separator",
}
local LIVE_PHASE = "Active" -- SPEC D1: the live phase's DuelPhase name (overtime too)
local WAITING_PHASE = "Positioning" -- SPEC D1: MatchRules' Waiting (the players are being moved to the map)
local OVERTIME_PHASE = "Overtime" -- the real MatchRules phase (matchPhase)
local EPSILON = 1e-9

-- Module table

local MatchFormat = {}

-- The chat commands (SPEC D6): the message's first word -> (action, mode).
MatchFormat.COMMANDS = table.freeze({
	["/ffa"] = { action = "join", mode = "ffa" },
	["/tdm"] = { action = "join", mode = "tdm" },
	["/leave"] = { action = "leave" },
})

-- Private

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function ownEntry(view: any): any
	for _, player in view.players do
		if player.userId == view.you.userId then
			return player
		end
	end
	return nil
end

local function add(parts: { string }, text: string?)
	if text ~= nil and text ~= "" then
		table.insert(parts, text)
	end
end

local function fill(template: string, args: { [string]: any }): string?
	if template == "" then
		return nil
	end
	return Strings.format(template, args)
end

-- Public

function MatchFormat.commandOf(text: unknown): (string?, string?)
	if type(text) ~= "string" then
		return nil, nil
	end
	local word = string.match(text, "^%s*(%S+)")
	local command = if word then (MatchFormat.COMMANDS :: any)[string.lower(word)] else nil
	if command == nil then
		return nil, nil
	end
	return command.action, command.mode
end

function MatchFormat.texts(): Texts
	local texts: { [string]: string } = {}
	for name, key in TEXT_KEYS do
		texts[name] = Strings.resolve(key) or ""
	end
	return texts :: any
end

function MatchFormat.leader(view: any): any
	local best: any = nil
	for _, player in view.players do
		if best == nil or player.kos > best.kos or (player.kos == best.kos and player.knockedOut < best.knockedOut) then
			best = player
		end
	end
	return best
end

function MatchFormat.timeLeft(view: any, now: number): string?
	local endsAt = view.phaseEndsAt
	if not finite(endsAt) or endsAt <= 0 then
		return nil
	end
	return TimeUtil.formatCountdown(math.max(0, endsAt - now))
end

function MatchFormat.stormPercent(bar: number): number
	if not finite(bar) or bar <= 0 then
		return 0
	end
	return math.clamp(math.ceil(bar * 100 - EPSILON), 1, 100)
end

function MatchFormat.respawnSeconds(respawnAt: number, now: number): number
	if not finite(respawnAt) then
		return 1
	end
	return math.max(1, math.ceil(respawnAt - now - EPSILON))
end

function MatchFormat.stormRadius(view: any, now: number, storm: any): number?
	local spec = view.storm
	local startedAt = view.activeStartedAt
	if spec == nil or not finite(startedAt) or view.phase ~= LIVE_PHASE then
		return nil
	end
	local t = now - startedAt
	if not StormMath.shown(storm, t) then
		return nil
	end
	return StormMath.radiusAt(storm, spec.startRadius, t)
end

function MatchFormat.readout(view: any, now: number, texts: Texts?, teamNames: { string }?): string
	local t: Texts = texts or MatchFormat.texts()
	local parts: { string } = {}
	local time = MatchFormat.timeLeft(view, now) or TimeUtil.formatCountdown(0)
	if view.phase == WAITING_PHASE and t.waiting ~= "" then
		add(parts, t.waiting)
	elseif view.mode == "tdm" then
		local names = teamNames or Config.Match.teamNames
		local lives = view.teamLives or {}
		add(parts, fill(t.tdm, { redLives = lives[names[1]] or 0, blueLives = lives[names[2]] or 0, time = time }))
	else
		local mine = ownEntry(view)
		local leader = MatchFormat.leader(view)
		add(
			parts,
			fill(t.ffa, {
				mine = if mine then mine.kos else 0,
				target = view.koTarget or 0,
				leaderName = if leader then leader.displayName else "",
				leaderKos = if leader then leader.kos else 0,
				time = time,
			})
		)
	end
	local you = view.you
	if you.stormBar > 0 then
		add(parts, fill(t.storm, { pct = MatchFormat.stormPercent(you.stormBar) }))
	end
	if view.matchPhase == OVERTIME_PHASE then
		add(parts, fill(t.overtime, {}))
	end
	if you.out then
		add(parts, fill(t.out, {}))
	elseif not you.alive and you.respawnAt ~= nil then
		add(parts, fill(t.backIn, { seconds = MatchFormat.respawnSeconds(you.respawnAt, now) }))
	end
	return table.concat(parts, t.separator)
end

return MatchFormat
