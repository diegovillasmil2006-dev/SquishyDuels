--!strict
-- ReminderService (server only, 2026-10-30, owner: "Yes, build it"). Come-back reminders: one Roblox experience
-- notification Config.Reminders.sendAfterSeconds after a player leaves, unless they come back first.
-- * Leave (playerRemoving; this service is the last layer, so its hook runs first, while the profile is still here):
--   jobFor picks the reminder for the send time: the pen's away Coins (PenMath.awayCoins at PenMath.rate(pen), the
--   same 5% the next load pays) when they reach minPenCoins, else the daily reward when it can be claimed that day,
--   else nothing. The job goes into a MemoryStore sorted map, one key per player (a new leave replaces the old job),
--   sorted by its due time.
-- * Join (playerAdded): the player's job is removed.
-- * start(): every pollSeconds each live server takes the due jobs, claims each one (UpdateAsync, so two servers never
--   both send it), sends it through Roblox's Open Cloud package (ServerScriptService.OpenCloud.V2.UserNotification,
--   from the Creator Store) and removes it, sent or refused (not opted in, under 13, throttled: never retried).
-- Off in Studio, without the package, or while both message ids are empty. Every store and send call is in pcall.
-- Dependencies are injectable (useDeps) for unit tests.
-- shortcut: a reminder needs a live server at its due time; with few players it goes out when the next server starts.
--   Upgrade to an outside scheduler calling the Open Cloud REST API if that matters.

-- Services

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local REMINDERS = require(Shared.Config.Reminders)
local DailyLogic = require(script.Parent.Parent.Logic.DailyLogic)
local DataService = require(script.Parent.DataService)

-- Types

export type Job = {
	messageId: string,
	category: string, -- "pen" | "daily": its row in Creator Hub's notification analytics
	parameters: { [string]: { stringValue: string } },
	claimedBy: string?,
	claimedAt: number?,
}

export type Deps = {
	config: any, -- Config.Reminders
	queue: any?, -- the MemoryStore sorted map; nil = off
	send: ((userId: number, notification: any) -> any)?, -- the package's createUserNotification; nil = off
	profileOf: (player: any) -> any?, -- READY profiles only
	isHere: (userId: number) -> boolean,
	now: () -> number,
	spawn: (fn: () -> ()) -> (),
}

-- Constants

local MAP_NAME = "Reminders_v1"
local BATCH = 20
local CLAIM_SECONDS = 120
local KEEP_SECONDS = 86400 -- a job outlives its due time by this much, for when no server runs
local POLL_JITTER = 5
local STATUS_READY = "ready"
local SERVER_ID = HttpService:GenerateGUID(false)

-- Module table

local ReminderService = {}

-- Private

local log = Log.new("Reminders")

local function keyOf(userId: number): string
	return "u" .. userId
end

local function findSender(): ((userId: number, notification: any) -> any)?
	local node: Instance? = ServerScriptService:FindFirstChild("OpenCloud")
	node = node and node:FindFirstChild("V2")
	node = node and node:FindFirstChild("UserNotification")
	if node == nil or not node:IsA("ModuleScript") then
		log:warn("the Open Cloud package (ServerScriptService.OpenCloud) is missing: reminders are off")
		return nil
	end
	local ok, module = pcall(require, node)
	if not ok or type(module) ~= "table" or type(module.createUserNotification) ~= "function" then
		log:warn(`the Open Cloud package did not load ({tostring(module)}): reminders are off`)
		return nil
	end
	return module.createUserNotification
end

local function defaultDeps(): Deps
	local on = not RunService:IsStudio() and (REMINDERS.penMessageId ~= "" or REMINDERS.dailyMessageId ~= "")
	local queue = nil
	if on then
		local ok, map = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, MAP_NAME)
		queue = if ok then map else nil
	end
	return {
		config = REMINDERS,
		queue = queue,
		send = if on then findSender() else nil,
		profileOf = function(player: any): any?
			return if DataService.getStatus(player) == STATUS_READY then DataService.getProfile(player) else nil
		end,
		isHere = function(userId: number): boolean
			return Players:GetPlayerByUserId(userId) ~= nil
		end,
		now = function(): number
			return os.time()
		end,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
	}
end

local deps: Deps = defaultDeps()

local function active(): boolean
	return deps.queue ~= nil and deps.send ~= nil
end

-- Marks a due job as this server's; nil when it is gone or another server claimed it within CLAIM_SECONDS.
local function claim(key: string, now: number): Job?
	local queue = deps.queue
	local ok, stored = pcall(queue.UpdateAsync, queue, key, function(old: any, sortKey: any): (any, any)
		if type(old) ~= "table" then
			return nil, nil
		end
		if type(old.claimedAt) == "number" and now - old.claimedAt < CLAIM_SECONDS then
			return nil, nil
		end
		old.claimedBy = SERVER_ID
		old.claimedAt = now
		return old, sortKey
	end, KEEP_SECONDS)
	if ok and type(stored) == "table" and stored.claimedBy == SERVER_ID then
		return stored
	end
	return nil
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- The reminder for a player who leaves at `now` (see the header) and its due time.
function ReminderService.jobFor(profile: any, now: number, cfg: any?): (Job?, number)
	local c = cfg or deps.config
	local dueAt = now + c.sendAfterSeconds
	if type(profile) ~= "table" then
		return nil, dueAt
	end
	if c.penMessageId ~= "" then
		local coins = PenMath.awayCoins(PenMath.rate(profile.pen), now, now, dueAt)
		if coins >= c.minPenCoins then
			local job: Job = {
				messageId = c.penMessageId,
				category = "pen",
				parameters = { coins = { stringValue = Format.coins(coins) } },
			}
			return job, dueAt
		end
	end
	local daily = profile.daily
	if c.dailyMessageId ~= "" and type(daily) == "table" then
		local day = DailyLogic.dayIndex(dueAt)
		if DailyLogic.canClaim(daily, day) then
			local job: Job = {
				messageId = c.dailyMessageId,
				category = "daily",
				parameters = { day = { stringValue = tostring(DailyLogic.nextStreak(daily, day)) } },
			}
			return job, dueAt
		end
	end
	return nil, dueAt
end

-- Sends the due jobs (see the header). Yields.
function ReminderService.sendDue()
	if not active() then
		return
	end
	local queue, send = deps.queue, deps.send :: any
	local now = deps.now()
	local ok, items = pcall(queue.GetRangeAsync, queue, Enum.SortDirection.Ascending, BATCH, nil, { sortKey = now + 1 })
	if not ok or type(items) ~= "table" then
		log:warn(`reading due reminders failed: {tostring(items)}`)
		return
	end
	for _, item in items do
		local userId = tonumber(string.match(tostring(item.key), "^u(%d+)$"))
		local job = if userId then claim(item.key, now) else nil
		if userId == nil or job == nil then
			continue
		end
		if not deps.isHere(userId) then
			local sent, result = pcall(send, userId, {
				payload = {
					messageId = job.messageId,
					type = "MOMENT",
					parameters = job.parameters,
					analyticsData = { category = job.category },
				},
			})
			if not sent then
				log:warn(`sending a reminder failed: {tostring(result)}`)
			elseif type(result) == "table" and result.statusCode ~= 200 then
				local err = if type(result.error) == "table" then result.error else {}
				log:info(`reminder not sent ({tostring(result.statusCode)} {tostring(err.code)} {tostring(err.message)})`)
			end
		end
		pcall(queue.RemoveAsync, queue, item.key)
	end
end

-- Replaces dependencies (fields not given keep their defaults); nil restores every default.
function ReminderService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function ReminderService.start()
	if not active() then
		return
	end
	while true do
		task.wait(deps.config.pollSeconds + math.random() * POLL_JITTER)
		ReminderService.sendDue()
	end
end

function ReminderService.playerAdded(player: Player)
	if not active() then
		return
	end
	local queue, key = deps.queue, keyOf(player.UserId)
	deps.spawn(function()
		pcall(queue.RemoveAsync, queue, key)
	end)
end

function ReminderService.playerRemoving(player: Player)
	if not active() then
		return
	end
	local job, dueAt = ReminderService.jobFor(deps.profileOf(player), deps.now())
	if job == nil then
		return
	end
	local queue, key = deps.queue, keyOf(player.UserId)
	local expiration = deps.config.sendAfterSeconds + KEEP_SECONDS
	deps.spawn(function()
		local ok, err = pcall(queue.SetAsync, queue, key, job, expiration, dueAt)
		if not ok then
			log:warn(`saving a reminder failed: {tostring(err)}`)
		end
	end)
end

return ReminderService
