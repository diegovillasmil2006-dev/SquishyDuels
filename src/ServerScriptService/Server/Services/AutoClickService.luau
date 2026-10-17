--!strict
-- AutoClickService (server only). Auto-clicker check (owner 2026-10-16: no earning limits for normal players;
-- robot-fast clicking is handled step by step). Config.Net.AutoClick has every number and why; Logic/AutoClickRules
-- has the rule and the ladder. Never trusts the client: the server times the requests itself.
-- Review fixes (2026-10-16, job autoclick): Config.Net.AutoClick.enforce sets how far a catch goes ("log" = logged
-- only: let through, no penalty, nothing saved; "warn" = every catch the 1st step; "full" = the steps below); the kick
-- text names the ban only when one can follow (autoClick.kick; else autoClick.kickNoBan).
-- * check(player, now) -> a reason code or nil. SqueezeService calls it first for every SqueezeRequest (`now` = the
--   request's os.clock arrival time, before the flood guard, so floods are seen too); a squeeze is the only
--   click-to-earn request (capsule pushes ride on paid squeezes; throws, duels and matches pay per match, practice
--   pays nothing). nil = the squeeze goes on as usual. During a penalty every request is refused with squeeze.tooFast
--   (silent on the client) and nothing is judged (time to switch the auto-clicker off). Otherwise
--   AutoClickRules.observe judges it; a catch is a strike (enforce "full"; "warn" caps the step at 1; "log" only
--   logs the step it would be, keeps it for this visit and lets the request through):
--     step = AutoClickRules.nextStep(this visit's step, profile.autoClick, os.time()), saved as profile.autoClick =
--     {step, at = os.time()} through the data port (mutate + a "soon" save; the leave save after a kick writes it
--     too), so a rejoin within memorySeconds remembers it; a penalty of penaltySeconds starts; the rules start fresh;
--     the strike is logged ([SD][abuse], with the numbers); that request is refused with squeeze.autoClick (the
--     client stops a hold and shows its text once: the short warning). Then by step:
--       1 warn: nothing more;
--       2 kick: Player:Kick(Strings autoClick.kick, which warns of the ban; autoClick.kickNoBan when no ban can
--               follow: Players.BanningEnabled off or a test account);
--       3 ban:  Players:BanAsync({UserIds, Duration = banSeconds, DisplayReason = Strings autoClick.ban, PrivateReason =
--               the numbers, ApplyToUniverse = true, ExcludeAltAccounts = banExcludeAltAccounts, ApplyDeviceBlock =
--               false}) only when Players.BanningEnabled is on (nothing here changes it); a player still in the
--               server after it is kicked with the same text. BanningEnabled off or a test account: a kick with
--               autoClick.kickNoBan; BanAsync failing: the step 2 kick (logged).
--       4 and up (batch B, owner 2026-10-17: a ban is never forgotten, so the next catch after one ends is a longer
--               ban): the same with Duration = AutoClickRules.banSeconds(step) (laterBanSeconds in turn, the last one
--               again) and DisplayReason = Strings autoClick.banLonger (naming the days).
--   Kicks and bans run after the reply (deps.later); every engine call is in pcall and every outcome is logged. In
--   Studio (RunService:IsStudio) nobody is kicked or banned: the log says what would have happened (the warning and
--   the penalty still apply, so the check can be watched).
-- * On only when Config.Net.AutoClick.enabled and Config/ValidateAutoClick finds no problem (init): a bad config never
--   punishes anyone (logged as errors; in Studio Config.Debug.failOnInvalidConfig stops the boot, like Config.validate).
-- Dependencies are injectable (useDeps) for unit tests; players are only table keys handed back to the dependencies.
-- init(), check() and playerRemoving() never yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)
local ValidateAutoClick = require(Shared.Config.ValidateAutoClick)

local Server = script.Parent.Parent
local AutoClickRules = require(Server.Logic.AutoClickRules)

local Services = script.Parent
local StateService = require(Services.StateService)

-- Types

export type Deps = {
	unixNow: () -> number, -- os.time: the saved strike's age
	isStudio: () -> boolean,
	profileOf: (player: any) -> any, -- the profile table in memory (or nil); read only
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any), -- the data port's mutate (READY only)
	requestSave: (player: any, reason: string) -> (),
	banningEnabled: () -> boolean, -- Players.BanningEnabled (read only)
	ban: (config: { [string]: any }) -> (boolean, string?), -- Players:BanAsync in pcall
	kick: (player: any, message: string) -> (boolean, string?), -- Player:Kick in pcall
	inGame: (player: any) -> boolean, -- still in Players
	later: (fn: () -> ()) -> (), -- task.defer: kicks and bans go after the reply
	rules: () -> AutoClickRules.Rules, -- Config.Net.AutoClick
}

type Session = {
	state: AutoClickRules.State,
	step: number, -- this visit's last strike (0 = none)
	penaltyUntil: number, -- os.clock: squeezes pay nothing before it
}

-- Constants

local REASON_AUTO_CLICK = "squeeze.autoClick"
local REASON_TOO_FAST = "squeeze.tooFast"
local TEXT_KICK = "autoClick.kick"
local TEXT_KICK_NO_BAN = "autoClick.kickNoBan"
local TEXT_BAN = "autoClick.ban"
local TEXT_BAN_LONGER = "autoClick.banLonger"
local SAVE_SOON = "soon"
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400
local DISPLAY_REASON_MAX = 400 -- BanAsync limits
local PRIVATE_REASON_MAX = 1000

-- Module table

local AutoClickService = {}

-- Private

local log = Log.new("AutoClick")
local abuseLog = Log.new("abuse")

local sessions: { [any]: Session } = {}
local offReason: string? = nil -- set by init when the config is invalid

local function defaultDeps(): Deps
	return {
		unixNow = os.time,
		isStudio = function(): boolean
			return RunService:IsStudio()
		end,
		profileOf = function(player: any): any
			return StateService.dataPort().getProfile(player)
		end,
		mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
			return StateService.dataPort().mutate(player, fn)
		end,
		requestSave = function(player: any, reason: string)
			StateService.dataPort().requestSave(player, reason)
		end,
		banningEnabled = function(): boolean
			local ok, on = pcall(function(): any
				return (Players :: any).BanningEnabled
			end)
			return ok and on == true
		end,
		ban = function(config: { [string]: any }): (boolean, string?)
			local ok, err = pcall(function()
				(Players :: any):BanAsync(config)
			end)
			return ok, if ok then nil else tostring(err)
		end,
		kick = function(player: any, message: string): (boolean, string?)
			local ok, err = pcall(function()
				(player :: Player):Kick(message)
			end)
			return ok, if ok then nil else tostring(err)
		end,
		inGame = function(player: any): boolean
			return typeof(player) == "Instance" and (player :: Instance).Parent == Players
		end,
		later = function(fn: () -> ())
			task.defer(fn)
		end,
		rules = function(): AutoClickRules.Rules
			return (Config :: any).Net.AutoClick
		end,
	}
end

local deps: Deps = defaultDeps()

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

-- A text naming a ban of `seconds` (default: the 1st ban, banSeconds) in hours and days.
local function textOf(key: string, c: AutoClickRules.Rules, seconds: number?): string
	local length = seconds or c.banSeconds
	return Strings.format(
		Strings.resolve(key) or "",
		{ hours = length // SECONDS_PER_HOUR, days = length // SECONDS_PER_DAY }
	)
end

-- The numbers of a catch, for the logs and the ban's PrivateReason.
local function describe(verdict: AutoClickRules.Verdict): string
	return string.format(
		"machine-regular: block spread %.2f ms (limit %.2f ms) over %d gaps, mean gap %.1f ms, %.1f s",
		verdict.value * 1000,
		verdict.limit * 1000,
		verdict.count,
		verdict.meanGap * 1000,
		verdict.seconds
	)
end

-- Review fix (2026-10-16): the kick text warns of the ban only when one can follow (bans on, a real account).
local function kickText(player: any, c: AutoClickRules.Rules): string
	local banPossible = userIdOf(player) > 0 and deps.banningEnabled()
	return textOf(if banPossible then TEXT_KICK else TEXT_KICK_NO_BAN, c)
end

local function kickNow(player: any, message: string, why: string)
	local id = userIdOf(player)
	if deps.isStudio() then
		abuseLog:warn(`Studio: would kick user {id} ({why}); nobody is kicked in Studio`)
		return
	end
	local ok, err = deps.kick(player, message)
	if ok then
		abuseLog:warn(`kicked user {id} ({why})`)
	else
		abuseLog:warn(`kick of user {id} failed ({why}): {tostring(err)}`)
	end
end

local function banNow(player: any, step: number, detail: string, c: AutoClickRules.Rules)
	local id = userIdOf(player)
	local seconds = AutoClickRules.banSeconds(step, c)
	if deps.isStudio() then
		abuseLog:warn(`Studio: would ban user {id} for {seconds} s ({detail}); nobody is banned in Studio`)
		return
	end
	if id <= 0 then
		abuseLog:warn(`ban of user {id} not applied (not a real account); kicked instead`)
		kickNow(player, textOf(TEXT_KICK_NO_BAN, c), `strike {step}, no account to ban`)
		return
	end
	if not deps.banningEnabled() then
		abuseLog:warn(
			`ban of user {id} not applied: Players.BanningEnabled is off (Studio: Players > BanningEnabled); kicked instead`
		)
		kickNow(player, textOf(TEXT_KICK_NO_BAN, c), `strike {step}, bans off`)
		return
	end
	local display = textOf(if step > AutoClickRules.BAN_STEP then TEXT_BAN_LONGER else TEXT_BAN, c, seconds)
	local ok, err = deps.ban({
		UserIds = { id },
		ApplyToUniverse = true,
		Duration = seconds,
		DisplayReason = string.sub(display, 1, DISPLAY_REASON_MAX),
		PrivateReason = string.sub(`SD auto-click strike {step} (ban {seconds} s): {detail}`, 1, PRIVATE_REASON_MAX),
		ExcludeAltAccounts = c.banExcludeAltAccounts,
		ApplyDeviceBlock = false,
	})
	if not ok then
		abuseLog:warn(`ban of user {id} failed ({tostring(err)}); kicked instead`)
		kickNow(player, textOf(TEXT_KICK, c), `strike {step}, ban failed`)
		return
	end
	abuseLog:warn(`banned user {id} for {seconds} s ({detail})`)
	if deps.inGame(player) then
		kickNow(player, display, "banned")
	end
end

local function sessionOf(player: any, c: AutoClickRules.Rules): Session
	local session = sessions[player]
	if session == nil then
		session = { state = AutoClickRules.newState(c), step = 0, penaltyUntil = -math.huge }
		sessions[player] = session
	end
	return session
end

local function memoryOf(player: any): any
	local profile = deps.profileOf(player)
	return if type(profile) == "table" then profile.autoClick else nil
end

-- One catch. Returns the reason the request is refused with (nil under enforce "log": it goes on).
local function strike(
	player: any,
	session: Session,
	verdict: AutoClickRules.Verdict,
	now: number,
	c: AutoClickRules.Rules
): string?
	local unixNow = deps.unixNow()
	local full = AutoClickRules.nextStep(session.step, memoryOf(player), unixNow, c)
	AutoClickRules.reset(session.state, c)
	if c.enforce == "log" then
		-- Review fix (2026-10-16): watch only. The visit keeps the step, so the log shows how far it would go.
		session.step = full
		abuseLog:warn(
			`user {userIdOf(player)} auto-click strike {full} (log only: would {AutoClickRules.actionFor(full)}): {describe(
				verdict
			)}`
		)
		return nil
	end
	local step = if c.enforce == "full" then full else 1 -- "warn": every catch is the first step
	session.step = step
	session.penaltyUntil = now + c.penaltySeconds
	local saved = deps.mutate(player, function(live: any): boolean
		live.autoClick = { step = step, at = unixNow }
		return true
	end)
	if saved then
		deps.requestSave(player, SAVE_SOON)
	end
	local action = AutoClickRules.actionFor(step)
	local detail = describe(verdict)
	local note = if saved then "" else "; not saved (profile not ready)"
	abuseLog:warn(`user {userIdOf(player)} auto-click strike {step} ({action}): {detail}{note}`)
	if action == "kick" then
		deps.later(function()
			kickNow(player, kickText(player, c), `strike 2: {detail}`)
		end)
	elseif action == "ban" then
		deps.later(function()
			banNow(player, step, detail, c)
		end)
	end
	return REASON_AUTO_CLICK
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- One SqueezeRequest arrived at `now` (os.clock). Returns nil when it may go on, else the reason it is refused with.
function AutoClickService.check(player: any, now: number): string?
	local c = deps.rules()
	if offReason ~= nil or not c.enabled then
		return nil
	end
	local session = sessionOf(player, c)
	if now < session.penaltyUntil then
		return REASON_TOO_FAST
	end
	local verdict = AutoClickRules.observe(session.state, now, c)
	if verdict == nil then
		return nil
	end
	return strike(player, session, verdict, now, c)
end

-- Public: tests ----------------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function AutoClickService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session and the init verdict (tests; not called by the bootstrap).
function AutoClickService.reset()
	table.clear(sessions)
	offReason = nil
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function AutoClickService.init()
	local rules = deps.rules()
	local live: any = Config
	local problems = ValidateAutoClick({
		Net = { AutoClick = rules, Remotes = live.Net.Remotes },
		Squeeze = live.Squeeze,
		Grip = live.Grip,
	}, Strings)
	if #problems == 0 then
		if not rules.enabled then
			log:info("auto-click check is off (Config.Net.AutoClick.enabled = false)")
		end
		return
	end
	offReason = "invalid config"
	for _, problem in problems do
		log:error(problem)
	end
	log:error("auto-click check OFF: Config.Net.AutoClick is invalid (nobody is warned, kicked or banned)")
	if Config.Debug.failOnInvalidConfig then
		error("[SD] Config invalid (Config.Net.AutoClick)")
	end
end

function AutoClickService.playerRemoving(player: Player)
	sessions[player] = nil
end

return AutoClickService
