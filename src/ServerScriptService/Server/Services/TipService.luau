--!strict
-- TipService (server only). DESIGN §6.13, §2.8 (DuelResult.tip), §3.2 (the loss streak is session memory only).
-- The friendly tip after a losing streak. It answers DuelService's `tip` result hook (DuelService.setResultHooks, from
-- init: DuelService is a lower layer and never requires this module), once per real participant of an ended match,
-- before that participant's DuelResult goes out; the answer is DuelResult.tip ("duel.lossTip") or nil. Reading (§2.3
-- says TipService "listens to MatchEnded", but DuelResult carries the tip and goes out before MatchEnded): the tip is
-- decided in that hook, once per participant, and this module does not listen to MatchEnded.
-- Rules (Config.Economy.LossTip, the pure step()):
--   * a completed loss with at least minOwnThrows own accepted throws adds 1 to the streak;
--   * a win resets the streak; a draw leaves it; cancelled and void matches never count;
--   * Reading (DESIGN: "forfeits ... don't count"): a loss whose DuelRules reason is "opponentLeft" is a bail by this
--     player (forfeit, leave, death, going missing, repeated out-of-bounds after EarlyForfeitSeconds) and leaves the
--     streak unchanged, like a loss with too few own throws;
--   * at lossStreak losses the tip is due when fewer than maxPerSession tips were shown this session, at least
--     minSecondsBetween passed since the last one and the player's settings.showTips is on; showing it resets the
--     streak. A tip that is not due (cooldown, cap, tips off) keeps the streak, so it can show after a later loss.
-- The streak, the tip count and the last tip time live in this server's memory only (never saved; forgotten on leave).
-- On leave the entry is cleared at once and again one step later (task.defer): the bootstrap runs playerRemoving in
-- reverse layer order, so this hook runs BEFORE DuelService.playerRemoving, which ends the leaver's match at once and
-- asks this module's result hook for the leaver too (Part 7 review fix: that late answer used to store a new entry
-- for a Player who had left, kept for the life of the server).
-- Clock: os.clock() (a measurement, §2.11). Dependencies are injectable (useDeps) for unit tests.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local DuelService = require(script.Parent.DuelService)
local PreferencesService = require(script.Parent.PreferencesService)

-- Types

export type TipState = {
	lossStreak: number, -- counted losses since the last win or tip
	shown: number, -- tips shown this session
	lastTipAt: number?, -- clock time of the last tip
}

-- One ended match as this player saw it.
export type TipResult = {
	outcome: string, -- the participant's view: "win" | "loss" | "draw" | "cancelled" | "void"
	reason: string, -- the DuelRules outcome reason ("eliminated", "opponentLeft", "timeUp", ...)
	throws: number, -- this player's accepted throws
	showTips: boolean, -- profile settings.showTips
}

export type TipConfig = {
	lossStreak: number,
	minOwnThrows: number,
	minSecondsBetween: number,
	maxPerSession: number,
	textKey: string,
}

export type Deps = {
	clock: () -> number,
	showTips: (player: any) -> boolean,
	defer: (fn: () -> ()) -> (), -- task.defer: the second clear on leave
}

-- Constants

local REASON_BAIL = "opponentLeft" -- DuelRules: the loser bailed after EarlyForfeitSeconds of Active

-- Module table

local TipService = {}

-- Private

local log = Log.new("Tip")
local states: { [any]: TipState } = {}

local function defaultDeps(): Deps
	return {
		clock = os.clock,
		showTips = function(player: any): boolean
			return PreferencesService.getSettings(player).showTips ~= false
		end,
		defer = function(fn: () -> ())
			task.defer(fn)
		end,
	}
end

local deps: Deps = defaultDeps()

local function newState(): TipState
	return { lossStreak = 0, shown = 0, lastTipAt = nil }
end

-- Public: pure (unit-tested) -------------------------------------------------------------------------------------------

-- One ended match: returns the new state (a copy; `state` is not changed) and the tip's Strings key when it is due.
function TipService.step(state: TipState, result: TipResult, now: number, cfg: TipConfig?): (TipState, string?)
	local c: TipConfig = cfg or Config.Economy.LossTip
	local nextState: TipState = { lossStreak = state.lossStreak, shown = state.shown, lastTipAt = state.lastTipAt }
	local outcome = result.outcome
	if outcome == "win" then
		nextState.lossStreak = 0
		return nextState, nil
	elseif outcome ~= "loss" then
		return nextState, nil -- a draw leaves the streak; cancelled and void never count
	end
	if result.reason == REASON_BAIL or result.throws < c.minOwnThrows then
		return nextState, nil -- a forfeit / bail, or too few own throws: not a completed loss
	end
	nextState.lossStreak += 1
	local last = nextState.lastTipAt
	local due = nextState.lossStreak >= c.lossStreak
		and nextState.shown < c.maxPerSession
		and (last == nil or now - last >= c.minSecondsBetween)
		and result.showTips
	if not due then
		return nextState, nil
	end
	nextState.lossStreak = 0
	nextState.shown += 1
	nextState.lastTipAt = now
	return nextState, c.textKey
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- DuelService's `tip` result hook: this participant's tip (DuelResult.tip) or nil.
function TipService.onResult(
	player: any,
	summary: DuelService.ParticipantSummary,
	info: DuelService.ResultInfo
): string?
	local state = states[player] or newState()
	local result: TipResult = {
		outcome = summary.outcome,
		reason = info.reason,
		throws = summary.throws,
		showTips = deps.showTips(player),
	}
	local nextState, tip = TipService.step(state, result, deps.clock())
	states[player] = nextState
	if tip ~= nil then
		log:info(`loss tip shown to user {summary.userId} in match {info.matchId}`)
	end
	return tip
end

-- Studio debug view of one player's session state (a copy).
function TipService.debugState(player: any): TipState
	local state = states[player] or newState()
	return { lossStreak = state.lossStreak, shown = state.shown, lastTipAt = state.lastTipAt }
end

-- Replaces dependencies (fields not given keep their defaults); nil restores every default. Forgets every session.
function TipService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	table.clear(states)
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function TipService.init()
	DuelService.setResultHooks({ tip = TipService.onResult })
end

function TipService.playerRemoving(player: Player)
	states[player] = nil
	-- DuelService.playerRemoving runs after this hook and may end the leaver's match (and call onResult) at once.
	deps.defer(function()
		states[player] = nil
	end)
end

return TipService
