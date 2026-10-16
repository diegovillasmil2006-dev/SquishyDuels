--!strict
-- MatchFormat (client only, pure). FFA/TDM v1 (2026-10-15; the 12-player Free for All / Team Deathmatch inside the
-- lobby server, SPEC D6, D11, D13): what MatchController shows and sends, as plain data, so it is unit-tested in Edit
-- mode. Views are StateController.MatchView tables; times are server times (workspace:GetServerTimeNow()).
--   commandOf(text) -> (action?, mode?)      a chat message as a match command (D6): "/ffa" and "/tdm" give
--                                            ("join", mode), "/leave" gives ("leave"); its first word only, any
--                                            case; anything else nil. COMMANDS lists the three (aliases: none).
--   readout(view, now, texts?, teamNames?, order?)
--                                            the TEST READOUT chip's text until Diego's arena HUD (D13), from the
--                                            Strings under match.readout (texts(); tests pass their own): the mode's
--                                            piece (FFA `ffa` "K.O. {mine}/{target} · 1st {leaderName} {leaderKos} ·
--                                            {time}", TDM `tdm` "RED {redLives} · BLUE {blueLives} · {time}"; `waiting`
--                                            "Get ready…" while players arrive, Positioning), then the pieces that
--                                            apply: `storm` "STORM {pct}%" while the own storm bar is above 0,
--                                            `overtime` in overtime, the live power-ups (below), `backIn` "Back in
--                                            {seconds}" while knocked out (`out` "OUT" in TDM with no team life
--                                            left), joined with `separator`. A missing text leaves its piece out.
--                                            {time} = the phase timer, "0:00" without one.
--   leader(view) -> MatchPlayer?             FFA: the leader (most K.O.s, then fewest times knocked out, then the
--                                            players' order, as the server's MatchRules.standings)
--   timeLeft(view, now) -> string?           the phase timer "m:ss" (TimeUtil.formatCountdown); nil without a timer
--   stormPercent(bar) -> number              the storm bar 0..1 as a whole percent; any bar above 0 shows at least 1
--   respawnSeconds(respawnAt, now) -> number whole seconds until the respawn, at least 1 while waiting
--   stormRadius(view, now, storm) -> number? the storm's safe radius now (StormMath, with the server-synced Active
--                                            time), nil while it is not up: no storm (FFA), not live, before
--                                            stormStartSeconds
--   texts() -> Texts                         the readout's texts from Strings (match.readout.*; "" when missing)
-- Power-ups v1.1 (2026-10-16, SPEC P4):
--   powerUpsLeft(view, now, order?)          the own live power-ups (you.buffs) in Config.Match.PowerUps.order (or
--     -> { {power, seconds} }                `order`), each with its whole seconds left (at least 1)
--   padCollectSeconds(readyAt, shownAt, now) the refill seconds to hand Diego's MapAnimations.Collect for a pad whose
--     -> number?                             readyAt rose above the one last played (`shownAt`, nil = none) and still
--                                            lies ahead; nil = nothing to play
--   collectRefill(seconds, headStart,        review fix: what MatchController hands Collect: `seconds` minus
--     shortest) -> number?                   `headStart` (Diego's refill timer ends that much early, so it is over
--                                            before the server can report the pad taken again: his Collect ignores a
--                                            pad still refilling), nil when that is shorter than `shortest` (his pop
--                                            would end after the refill: the pad is ready at once, nothing to play)
--   The readout lists every live power-up after the overtime piece: `powerUp` "{name} {seconds}s" (e.g. "SPEED 4s"),
--   {name} = match.readout.powerUpName.<kind> (Texts.powerUpNames); a kind without a name is left out. Review fix: only
--   in the live phase (Active, overtime too); at Result and Returning nothing can be thrown or dashed any more.

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
	powerUp: string?, -- power-ups v1.1: "{name} {seconds}s"
	powerUpNames: { [string]: string }?, -- power-ups v1.1: kind -> short name ("SPEED")
}

-- Power-ups v1.1: one live power-up of the readout.
export type PowerUpLeft = { power: string, seconds: number }

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
	powerUp = "match.readout.powerUp", -- power-ups v1.1
}
local POWER_UP_NAME_PREFIX = "match.readout.powerUpName." -- power-ups v1.1: + the Config.Match.PowerUps kind
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
	local texts: { [string]: any } = {}
	for name, key in TEXT_KEYS do
		texts[name] = Strings.resolve(key) or ""
	end
	-- Power-ups v1.1: the short names of every kind (a missing one is left out).
	local names: { [string]: string } = {}
	for _, kind in Config.Match.PowerUps.order do
		local name = Strings.resolve(POWER_UP_NAME_PREFIX .. kind)
		if name ~= nil then
			names[kind] = name
		end
	end
	texts.powerUpNames = names
	return texts :: any
end

function MatchFormat.powerUpsLeft(view: any, now: number, order: { string }?): { PowerUpLeft }
	local list: { PowerUpLeft } = {}
	local buffs = view.you.buffs
	if type(buffs) ~= "table" then
		return list
	end
	for _, power in order or Config.Match.PowerUps.order do
		local untilAt = buffs[power]
		if finite(untilAt) and now < untilAt then
			table.insert(list, { power = power, seconds = math.max(1, math.ceil(untilAt - now - EPSILON)) })
		end
	end
	return list
end

function MatchFormat.padCollectSeconds(readyAt: number, shownAt: number?, now: number): number?
	if not finite(readyAt) or readyAt <= now or (shownAt ~= nil and readyAt <= shownAt) then
		return nil
	end
	return readyAt - now
end

function MatchFormat.collectRefill(seconds: number, headStart: number, shortest: number): number?
	local refill = seconds - math.max(if finite(headStart) then headStart else 0, 0)
	if not finite(refill) or refill < shortest then
		return nil
	end
	return refill
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

function MatchFormat.readout(view: any, now: number, texts: Texts?, teamNames: { string }?, order: { string }?): string
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
	-- Power-ups v1.1: every live power-up with its seconds left (review fix: only while the match is live; the server
	-- keeps them in the view at Result).
	local names = t.powerUpNames or {}
	if view.phase == LIVE_PHASE then
		for _, left in MatchFormat.powerUpsLeft(view, now, order) do
			local name = names[left.power]
			if name ~= nil and name ~= "" then
				add(parts, fill(t.powerUp or "", { name = name, seconds = left.seconds }))
			end
		end
	end
	if you.out then
		add(parts, fill(t.out, {}))
	elseif not you.alive and you.respawnAt ~= nil then
		add(parts, fill(t.backIn, { seconds = MatchFormat.respawnSeconds(you.respawnAt, now) }))
	end
	return table.concat(parts, t.separator)
end

return MatchFormat
