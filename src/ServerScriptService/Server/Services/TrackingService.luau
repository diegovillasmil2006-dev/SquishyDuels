--!strict
-- TrackingService (server only, 2026-10-30, owner: "Player tracking" / "Yes, build it"). Reports players to Roblox's
-- own analytics (Creator Hub > Analytics) so we can see where new players quit. It only listens: nothing in the game
-- changes. AnalyticsService sends nothing from Studio (expected); events come from published servers, about a day
-- later on the dashboard. Every call is in pcall: tracking never breaks the game.
-- * New players (LogOnboardingFunnelStepEvent): 1 "Joined" when a READY profile loads with the tutorial neither
--   finished nor skipped, 2-7 the Config.Onboarding steps in their order, 8 "Finished" when all of them are done.
--   Forward-only per player and session (Roblox counts only the first time of a step and counts the steps before a
--   logged one as done, so an out-of-order step back-fills the earlier ones). Custom events: "TutorialSkipped"
--   (field 1 = the lowest open step) and "NewPlayer10Min" (still here 10 minutes after "Joined"; a custom event, not a
--   funnel step, so it never back-fills tutorial steps).
-- * Coins (LogEconomyEvent "Coins"): EconomyService.CoinsChanged summed per player, reason and direction, sent every
--   FLUSH_SECONDS and on leave (squeezes fire many times a minute and Roblox rate-limits analytics). Earned = Source,
--   spent = Sink; the reason is the item SKU; the balance is the last one CoinsChanged gave; "debug" is never sent.
-- * Modes (custom event "ModePlayed", field 1 = "duel" or the match modeId): one per real player in each finished duel
--   (DuelService.MatchEnded) or match (MatchService.MatchEnded); cancelled and void ones are not counted.
-- Field values come from small fixed sets only (Roblox caps their combinations). Dependencies are injectable
-- (useDeps) for unit tests.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local DataService = require(script.Parent.DataService)
local DuelService = require(script.Parent.DuelService)
local EconomyService = require(script.Parent.EconomyService)
local MatchService = require(script.Parent.MatchService)
local PreferencesService = require(script.Parent.PreferencesService)

-- Types

export type Deps = {
	analytics: any, -- AnalyticsService (a fake in tests)
	playerByUserId: (userId: number) -> Player?,
	inGame: (player: any) -> boolean,
	delay: (seconds: number, fn: () -> ()) -> (),
}

-- Constants

local FLUSH_SECONDS = 60
local NEW_PLAYER_MINUTES_SECONDS = 600
local CURRENCY = "Coins"
local REASON_DEBUG = "debug"
local STATUS_READY = "ready"
local STEP_JOINED = 1
local STEP_FINISHED = #Config.Onboarding.Steps + 2
local FIELD_1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
-- Coin sources by reason (Enum.AnalyticsEconomyTransactionType names); every other source is "Gameplay", every spend
-- is "Shop" (boxes, shop, gear, food, pen spots, buy-backs).
local SOURCE_TYPE: { [string]: string } = {
	robux = "IAP",
	quest = "TimedReward",
	daily = "TimedReward",
	away = "TimedReward",
	starter = "Onboarding",
}

-- Module table

local TrackingService = {}

-- Private

local log = Log.new("Tracking")
local STEP_NUMBER: { [string]: number } = {}
for index, step in Config.Onboarding.Steps do
	STEP_NUMBER[step.id] = index + 1
end

local highest: { [any]: number } = {} -- last funnel step sent this session, per player (only new players are in it)
local doneSteps: { [any]: { [string]: boolean } } = {}
local pending: { [any]: { [string]: number } } = {} -- "reason|in" / "reason|out" -> summed Coins
local balances: { [any]: number } = {}

local function defaultDeps(): Deps
	return {
		analytics = game:GetService("AnalyticsService"),
		playerByUserId = function(userId: number): Player?
			return Players:GetPlayerByUserId(userId)
		end,
		inGame = function(player: any): boolean
			return player.Parent == Players
		end,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
	}
end

local deps: Deps = defaultDeps()

local function send(method: string, ...: any)
	local ok, err = pcall(deps.analytics[method], deps.analytics, ...)
	if not ok then
		log:warn(`{method} failed: {tostring(err)}`)
	end
end

local function logStep(player: any, step: number, name: string)
	local last = highest[player]
	if last == nil or step <= last then
		return
	end
	highest[player] = step
	send("LogOnboardingFunnelStepEvent", player, step, name)
end

local function lowestOpenStep(player: any): string
	local done = doneSteps[player] or {}
	for _, step in Config.Onboarding.Steps do
		if not done[step.id] then
			return step.id
		end
	end
	return "none"
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- DataService.Loaded: a READY profile with the tutorial neither finished nor skipped joins the new-player funnel.
function TrackingService.onLoaded(player: any, profile: any, status: string)
	if status ~= STATUS_READY or type(profile) ~= "table" then
		return
	end
	local onboarding = if type(profile.onboarding) == "table" then profile.onboarding else {}
	if onboarding.skipped == true then
		return
	end
	local done: { [string]: boolean } = {}
	if type(onboarding.done) == "table" then
		for id, value in onboarding.done do
			done[id] = value == true
		end
	end
	doneSteps[player] = done
	if lowestOpenStep(player) == "none" then
		doneSteps[player] = nil
		return
	end
	highest[player] = 0
	logStep(player, STEP_JOINED, "Joined")
	deps.delay(NEW_PLAYER_MINUTES_SECONDS, function()
		if deps.inGame(player) and highest[player] ~= nil then
			send("LogCustomEvent", player, "NewPlayer10Min", 1)
		end
	end)
end

-- PreferencesService.StepDone: a tutorial step newly done, or Config.Onboarding.skipStepId when the tutorial is skipped.
function TrackingService.onStepDone(player: any, stepId: string)
	local done = doneSteps[player]
	if done == nil then
		return -- not a new player this session
	end
	if stepId == Config.Onboarding.skipStepId then
		send("LogCustomEvent", player, "TutorialSkipped", 1, { [FIELD_1] = lowestOpenStep(player) })
		highest[player] = nil
		doneSteps[player] = nil
		return
	end
	local number = STEP_NUMBER[stepId]
	if number == nil then
		return
	end
	done[stepId] = true
	logStep(player, number, stepId)
	if lowestOpenStep(player) == "none" then
		logStep(player, STEP_FINISHED, "Finished")
	end
end

-- EconomyService.CoinsChanged: summed until the next flush.
function TrackingService.onCoinsChanged(player: any, coins: number, delta: number, reason: string)
	if reason == REASON_DEBUG or delta == 0 then
		return
	end
	local sums = pending[player]
	if sums == nil then
		sums = {}
		pending[player] = sums
	end
	local key = reason .. (if delta > 0 then "|in" else "|out")
	sums[key] = (sums[key] or 0) + math.abs(delta)
	balances[player] = coins
end

-- Sends one player's summed Coins (one economy event per reason and direction) and clears them.
function TrackingService.flush(player: any)
	local sums = pending[player]
	pending[player] = nil
	if sums == nil then
		return
	end
	local balance = balances[player] or 0
	for key, amount in sums do
		local reason, direction = string.match(key, "^(.+)|(%a+)$")
		if reason == nil then
			continue
		end
		if direction == "in" then
			send(
				"LogEconomyEvent",
				player,
				Enum.AnalyticsEconomyFlowType.Source,
				CURRENCY,
				amount,
				balance,
				SOURCE_TYPE[reason] or "Gameplay",
				reason
			)
		else
			send(
				"LogEconomyEvent",
				player,
				Enum.AnalyticsEconomyFlowType.Sink,
				CURRENCY,
				amount,
				balance,
				"Shop",
				reason
			)
		end
	end
end

function TrackingService.flushAll()
	for player in pending do
		TrackingService.flush(player)
	end
end

-- DuelService.MatchEnded: "duel" for every real player of a finished duel (test dummies and bots have no Player).
function TrackingService.onDuelEnded(summary: any)
	if summary.outcome == "cancelled" or summary.outcome == "void" then
		return
	end
	for _, participant in summary.participants do
		if participant.player ~= nil and not participant.isTestDummy then
			send("LogCustomEvent", participant.player, "ModePlayed", 1, { [FIELD_1] = "duel" })
		end
	end
end

-- MatchService.MatchEnded: the match's modeId for every real player still in this server (bots have no Player).
function TrackingService.onMatchEnded(summary: any)
	if summary.outcome == "cancelled" or summary.outcome == "void" then
		return
	end
	for _, participant in summary.participants do
		local player = deps.playerByUserId(participant.userId)
		if player ~= nil then
			send("LogCustomEvent", player, "ModePlayed", 1, { [FIELD_1] = tostring(summary.modeId) })
		end
	end
end

-- Replaces dependencies (fields not given keep their defaults); nil restores every default. Forgets every player.
function TrackingService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	table.clear(highest)
	table.clear(doneSteps)
	table.clear(pending)
	table.clear(balances)
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function TrackingService.init()
	DataService.Loaded:connect(TrackingService.onLoaded)
	PreferencesService.StepDone:connect(TrackingService.onStepDone)
	EconomyService.CoinsChanged:connect(TrackingService.onCoinsChanged)
	DuelService.MatchEnded:connect(TrackingService.onDuelEnded)
	MatchService.MatchEnded:connect(TrackingService.onMatchEnded)
end

function TrackingService.start()
	while true do
		task.wait(FLUSH_SECONDS)
		TrackingService.flushAll()
	end
end

function TrackingService.playerRemoving(player: Player)
	local function forget()
		TrackingService.flush(player)
		highest[player] = nil
		doneSteps[player] = nil
		balances[player] = nil
	end
	forget()
	-- This hook runs first on leave (reverse layer order); the services below may still pay the leaver (a duel it bails
	-- from), so send and forget once more one step later.
	deps.delay(0, forget)
end

return TrackingService
