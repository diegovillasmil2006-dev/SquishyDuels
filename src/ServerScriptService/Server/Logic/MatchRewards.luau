--!strict
-- MatchRewards: the pay and the win streak of one player at the end of a Free for All / Team Deathmatch match (Match
-- HUD M2, 2026-10-16: owner answers Q3 / Q4, matchhud2 PLAN v2 §4 M2 and §12; Diego's results pills M:361-363, the
-- WIN STREAK box M:186-189 and the podium chip M:353). Server only, pure: no instances, no yields, no Coins or Grip
-- change here. MatchService calls forPlayer once per player present at the match's single end (MatchRules `ended`)
-- while Config.Match.Rewards.enabled, then pays it through EconomyService.grantMatchResult (Coins and the win streak,
-- one profile step) and GripService.addFromMatch (Grip); left() is the pay of a player who leaves a live match.
--
-- Rules (owner Q3 2026-10-16: "same as a duel, no hourly limit"; every amount and limit is Config.Economy.DuelRewards',
-- all [P]):
--   * result: FFA: the winner (outcome.winnerUserId) "win", everyone else "loss"; TDM: the winning team "win", the
--     other one "loss"; a draw is "draw", except in an FFA draw (overtime ran out with a tie) where only the tied
--     leaders (outcome.winners) draw and the others lose. Cancelled and void: nil (nothing paid, the streak untouched).
--     nil too for a player not present at the end (left, or never arrived) and for a bot.
--   * paid like a duel: at least minOwnThrows (3) server-accepted throws of their own, and outcome.activeSeconds
--     (Active and Overtime) at least winMinActiveSeconds (20) for a win, lossMinActiveSeconds (45) for a loss, nothing
--     more for a draw. No same-pair or hourly cap (owner Q3: no fullPerHour / reducedMultiplier, no record for one).
--   * amount: DuelRewards[result] squeezes (win 600, loss 180, draw 300), paid as Coins AND Grip (owner Q3: "sized like
--     a 1v1 duel win or loss, so both grow as players level up"): squeezes × the Coins of one squeeze and squeezes ×
--     the Grip of one squeeze, both from squeezeWorth at the moment they are paid.
--   * win streak (owner Q4, §12 binding: "+1 team win or FFA 1st; loss, draw or leaving early -> 0"): +1 for every
--     win of a player present at the end (a team win or FFA 1st, paid or not: the pay rules above decide the pay
--     only); a loss or a draw -> 0; leaving a live match (Countdown, Active, Overtime) -> 0 (left()). Cancelled / void
--     and 1v1 duels never touch it.
-- Readings: a draw needs only the player's own throws (a duel's "both players threw 3 times" has no 12-player form);
-- an FFA draw's non-leaders lose (they did not tie for first). Review fix (2026-10-16): a win that pays nothing (too
-- few throws or too little Active time) still counts +1 (the plan's older "a win that did not pay -> 0" is not in the
-- owner's §12 answer; it also let a quitter wipe the winner's streak).
--
-- squeezeWorth is the ONE place that knows what a squeeze is worth for match pay: today the capsules' squeeze value
-- (CapsuleMath.squeezeValue, the Coins a duel reward pays per squeeze too) and the Grip of an own squeeze
-- (CapsuleMath.squeezeGrip). Capsules are being removed (owner 2026-10-15: a pen of walking squishies replaces them):
-- the pen economy swaps this one function.
--
-- API:
--   MatchRewards.forPlayer(outcome, player, cfg?) -> Pay?   (outcome = MatchRules' outcome; player = PlayerInput)
--   MatchRewards.left()                           -> Pay    (leaving a live match: nothing paid, the streak -> 0)
--   MatchRewards.streakOf(value)                  -> number (a saved streak as a whole number >= 0; anything else 0)
--   MatchRewards.nextStreak(before, pay)          -> number (the streak after a pay: before + 1 or 0)
--   MatchRewards.squeezeWorth(profile)            -> (coins, grip) of ONE squeeze for this profile now
--   MatchRewards.maxSqueezes(cfg?)                -> the largest pay in squeezes (the grants' guard)
-- cfg = a table with Config's Economy section (a test's copy); nil = the live Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Config = require(Shared.Config)

-- Types

export type Result = "win" | "loss" | "draw" | "left"

-- The parts of MatchRules' Outcome read here (restated, so EconomyService and GripService need not load MatchRules).
export type Outcome = {
	kind: string, -- "win" | "draw" | "cancelled" | "void"
	winnerUserId: number?,
	winnerTeam: string?,
	winners: { number }?,
	activeSeconds: number?,
}

-- What forPlayer reads of one player (MatchService fills it from its Participant and the MatchRules record).
export type PlayerInput = {
	userId: number,
	team: string?, -- TDM: the team name; nil in FFA
	present: boolean, -- MatchRules: arrived and not left
	isBot: boolean,
	throws: number, -- server-accepted throws this match
}

export type Pay = {
	result: Result,
	eligible: boolean, -- paid (the duel's throw and Active-time rules met)
	squeezes: number, -- the pay counted in squeezes, as Coins AND as Grip (0 when not eligible)
	streakUp: boolean, -- true (every "win", paid or not): the win streak + 1; false: back to 0
}

export type RewardConfig = { Economy: any }

-- Constants

local MAX_STREAK = 2 ^ 53 -- ProfileSchema's counter cap

-- Module table

local MatchRewards = {}

-- Private

local function config(cfg: RewardConfig?): RewardConfig
	return if cfg ~= nil then cfg else Config
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function resultOf(outcome: Outcome, player: PlayerInput): Result
	if outcome.kind == "draw" then
		local winners = outcome.winners
		if player.team == nil and type(winners) == "table" and #winners > 0 then
			return if table.find(winners, player.userId) ~= nil then "draw" else "loss"
		end
		return "draw"
	end
	if outcome.winnerTeam ~= nil then
		return if player.team == outcome.winnerTeam then "win" else "loss"
	end
	return if outcome.winnerUserId == player.userId then "win" else "loss"
end

-- Public

function MatchRewards.forPlayer(outcome: Outcome?, player: PlayerInput, cfg: RewardConfig?): Pay?
	if outcome == nil or (outcome.kind ~= "win" and outcome.kind ~= "draw") then
		return nil -- cancelled / void: nothing paid, the streak untouched
	end
	if not player.present or player.isBot then
		return nil
	end
	local rules = config(cfg).Economy.DuelRewards
	local result: Result = resultOf(outcome, player)
	local minActive = if result == "win"
		then rules.winMinActiveSeconds
		elseif result == "loss" then rules.lossMinActiveSeconds
		else 0
	local activeSeconds = if finite(outcome.activeSeconds) then outcome.activeSeconds else 0
	local throws = if finite(player.throws) then player.throws else 0
	local eligible = throws >= rules.minOwnThrows and activeSeconds >= minActive
	local pay: Pay = {
		result = result,
		eligible = eligible,
		squeezes = if eligible then rules[result] else 0,
		streakUp = result == "win", -- owner Q4: any team win / FFA 1st, paid or not
	}
	return pay
end

function MatchRewards.left(): Pay
	return { result = "left", eligible = false, squeezes = 0, streakUp = false }
end

function MatchRewards.streakOf(value: unknown): number
	if not finite(value) or (value :: number) < 0 then
		return 0
	end
	return math.min(math.floor(value :: number), MAX_STREAK)
end

function MatchRewards.nextStreak(before: unknown, pay: Pay): number
	return if pay.streakUp then math.min(MatchRewards.streakOf(before) + 1, MAX_STREAK) else 0
end

function MatchRewards.squeezeWorth(profile: unknown): (number, number)
	local capsules = if type(profile) == "table" then (profile :: any).capsules else nil
	return CapsuleMath.squeezeValue(capsules), CapsuleMath.squeezeGrip(capsules)
end

function MatchRewards.maxSqueezes(cfg: RewardConfig?): number
	local rules = config(cfg).Economy.DuelRewards
	return math.max(rules.win, rules.loss, rules.draw)
end

return table.freeze(MatchRewards)
