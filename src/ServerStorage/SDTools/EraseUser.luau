--!strict
-- EraseUser (audit row 26, 2026-11-12): one player's saved data, deleted when Roblox's daily right-to-erasure message
-- names them (the whole procedure, and the Creator Hub templates that do the save by themselves: vault page "Data
-- deletion steps"). Server only, Studio Edit mode only (ServerStorage.SDTools), in the published place with Game
-- Settings > Security > "Enable Studio Access to API Services" on. Run it with execute_luau (or the command bar):
--   require(game.ServerStorage.SDTools.EraseUser).run(userId)        -- a dry run: what it finds, nothing deleted
--   require(game.ServerStorage.SDTools.EraseUser).run(userId, true)  -- deletes it
-- What it covers (EraseUser.plan): the save, Config.Data.storeName key keyPrefix .. userId (no scope; Roblox keeps its
-- old versions for about 30 days, then they go), and the weekly wins board, Config.Social.Board.storeName key
-- tostring(userId) in scope "w<week>" for every week from FIRST_WEEK_TIME's week to now (an ordered store per week
-- scope: the Creator Hub templates cannot match a scope that changes every week). Memory stores (the queue, the
-- reminders) expire by themselves. Not reachable: the user's id inside OTHER players' saves (duelLog `opp`, the
-- samePair keys, both trimmed as those players play on); see the vault page.

-- Services

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Types

export type Target = { store: string, ordered: boolean, scope: string?, key: string }

-- Constants

local SECONDS_PER_WEEK = 7 * 86400
-- 2026-10-01 00:00 UTC: before the weekly board's first live week (ShowOffService, 2026-10-13), so every live scope
-- is covered; a scope with no entry for the user costs one read or remove and changes nothing.
local FIRST_WEEK_TIME = 1_790_812_800

-- Module table

local EraseUser = {}

EraseUser.FIRST_WEEK_TIME = FIRST_WEEK_TIME

-- The board week of a Unix time (ShowOffService.weekIndex's rule: weeks start on Monday 00:00 UTC).
local function weekIndex(t: number, offset: number): number
	return math.floor((t - offset) / SECONDS_PER_WEEK)
end

-- Everything to read or delete for `userId` at Unix time `now`, from a Config (the live one, or a test's copy).
-- Errors for a userId that is not a whole number above 0.
function EraseUser.plan(userId: number, now: number, config: any): { Target }
	assert(type(userId) == "number" and userId > 0 and math.floor(userId) == userId, "userId: a whole number above 0")
	local id = string.format("%d", userId)
	local data, board = config.Data, config.Social.Board
	local targets: { Target } = {
		{ store = data.storeName, ordered = false, scope = nil, key = data.keyPrefix .. id },
	}
	for week = weekIndex(FIRST_WEEK_TIME, board.weekOffsetSeconds), weekIndex(now, board.weekOffsetSeconds) do
		table.insert(targets, { store = board.storeName, ordered = true, scope = "w" .. week, key = id })
	end
	return targets
end

-- Reads (dry run) or removes (really = true) every target of the plan; one line per target.
function EraseUser.run(userId: number, really: boolean?): string
	assert(RunService:IsStudio() and not RunService:IsRunning(), "EraseUser runs in Studio's Edit mode only")
	local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any
	local lines: { string } = {}
	local found = 0
	for _, target in EraseUser.plan(userId, os.time(), Config) do
		local store: any = if target.ordered
			then DataStoreService:GetOrderedDataStore(target.store, target.scope)
			else DataStoreService:GetDataStore(target.store)
		local ok, value = pcall(function(): any
			return if really then store:RemoveAsync(target.key) else store:GetAsync(target.key)
		end)
		local where = `{target.store}{if target.scope then "/" .. target.scope else ""} {target.key}`
		if not ok then
			table.insert(lines, `FAILED {where}: {tostring(value)}`)
		elseif value ~= nil then
			found += 1
			table.insert(lines, `{if really then "DELETED" else "found"} {where}`)
		end
		task.wait(0.1) -- stay well under the data store request budget
	end
	table.insert(lines, 1, `{if really then "ERASED" else "DRY RUN for"} user {userId}: {found} entries`)
	return table.concat(lines, "\n")
end

return EraseUser
