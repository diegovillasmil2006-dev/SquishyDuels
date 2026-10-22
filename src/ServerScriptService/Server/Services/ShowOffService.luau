--!strict
-- ShowOffService (server only). Batch 3 (friends, review #10; user decisions 2026-10-14): what players see of each
-- other's play. Nothing here ranks or rewards spending or inviting, and no client can write any of it.
-- * Player list: a server-made Folder "leaderstats" on each player with two IntValues, in this order: Wins
--   (Strings.social.statWins) and Grip Lv (statLevel). Wins is re-read from the profile's stats.duelsWon (never + 1:
--   a result that wrote no stats never shows) on load and after every duel; Grip Lv is GripService's level, on load
--   and on LevelChanged. qb1 (owner 2026-10-15 "yes for everything"): a third column Coins/s (statIncome, a
--   StringValue so the number is short: Format.coins of PenMath.rate(profile.pen), the pen's Coins a second), set on
--   load and refreshed every INCOME_REFRESH_SECONDS (refreshIncome), so a pen change shows within a second.
-- * "Top Wins This Week" (Q3 B: a section of the Quests screen, UI/QuestFormat.topWins): an OrderedDataStore
--   (Config.Social.Board) written by this server only, scope "w" .. weekIndex(os.time()) (weeks start on Monday 00:00
--   UTC), + 1 (IncrementAsync, in its own thread) for each fully paid win (eligible, x1, Coins paid) of a real player
--   over a real player (countsForBoard: never the Studio test dummy or a bot, which have no Player; never a userId
--   <= 0 on a live server; Studio's own local test players, -1, -2, ..., count in Studio so a Local Server test shows
--   the board). Every Board.refreshSeconds one GetSortedAsync reads the week's first Board.readSize entries; each
--   player gets the session field topWins (Types.TopWinsView): the top Board.size with display names (a player in
--   the server, else UserService, cached; "A player" when it fails), their own place within the read and their week's
--   wins (read once at join, then from each increment). Every DataStore call runs in pcall, a write or a read after
--   its request budget check (liveStore): a failure is logged (a read once until one works again) and keeps the last
--   board; while no read has worked yet, each refresh sends every player `unavailable` (the Quests screen: "The board
--   is taking a break").
--   Studio uses a memory store unless Config.Data.studioMode is "datastore" (then Board.studioStoreName, which must end
--   in "_STUDIO", the DataStoreAdapter rule).
-- * Badges (Q4 A; Config.Social.Badges, Logic/BadgeRules): every Badges.checkSeconds each player with a ready
--   profile is checked; each earned badge with an id joins one server-wide queue, handled one at a time:
--   UserHasBadgeAsync, then AwardBadgeAsync when not owned yet, both in pcall. Success or "already owned" counts for
--   the session; an error is tried again on a later check, at most Badges.maxTries times. Never awarded: a badge
--   without an id (one log line), in Studio (a "would award" debug line) or for a userId <= 0. The session flag
--   duelBuddies comes from a finished duel (win or draw) between two real players that FriendDuelService started (the
--   pads or Rematch).
-- Dependencies are injectable (useDeps) so unit tests run with fake players, profiles, stores and badges. init() and
-- the player hooks never yield; the DataStore, UserService and BadgeService calls run in their own threads.

-- Services

local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Services = script.Parent
local DuelService = require(Services.DuelService)
local FriendDuelService = require(Services.FriendDuelService)
local GripService = require(Services.GripService)
local StateService = require(Services.StateService)
local DataStoreAdapter = require(Services.Parent.Data.DataStoreAdapter)
local BadgeRules = require(Services.Parent.Logic.BadgeRules)

-- Types

export type Entry = { key: string, value: number }

-- One week's board (an OrderedDataStore scope, or memory). Every function may yield or error.
export type WeekStore = {
	increment: (key: string, delta: number) -> number,
	get: (key: string) -> number?,
	top: (count: number) -> { Entry },
}

export type Logger = {
	info: (self: any, ...any) -> (),
	warn: (self: any, ...any) -> (),
	debug: (self: any, ...any) -> (),
}

export type Deps = {
	now: () -> number, -- os.time(): the week clock
	isStudio: () -> boolean,
	players: () -> { any },
	profileOf: (player: any) -> any?, -- a READY profile, else nil
	levelOf: (player: any) -> number, -- the Grip level
	store: (week: number) -> WeekStore,
	nameOf: (userId: number) -> string?, -- may yield or error
	hasBadge: (userId: number, badgeId: number) -> boolean, -- may yield or error
	awardBadge: (userId: number, badgeId: number) -> boolean, -- may yield or error
	badges: () -> { any }, -- Config.Social.Badges.list
	setTopWins: (player: any, view: Types.TopWinsView) -> (),
	isFriendMatch: (matchId: string) -> boolean,
	spawn: (fn: () -> ()) -> (),
	log: Logger,
}

type Stats = { folder: Folder, wins: IntValue, level: IntValue, income: StringValue }
type BadgeState = { done: { [string]: boolean }, tries: { [string]: number }, queued: { [string]: boolean } }
type Award = { player: any, key: string, id: number }
type Board = { week: number, entries: { Entry }, top: { Types.TopWinsLine } }

-- Constants

local BOARD = Config.Social.Board
local BADGES = Config.Social.Badges
local SECONDS_PER_WEEK = 7 * 86400
local FOLDER_NAME = "leaderstats" -- the name Roblox's player list reads
local FLAG_BUDDIES = "duelBuddies"
local FINISHED: { [string]: boolean } = { win = true, draw = true }
local INCOME_REFRESH_SECONDS = 1 -- qb1: the Coins/s column follows the pen within a second

-- Module table

local ShowOffService = {}

-- Private

local stats: { [any]: Stats } = {}
local badgeState: { [any]: BadgeState } = {}
local flags: { [any]: { [string]: boolean } } = {}
local awards: { Award } = {}
local mine: { [number]: { week: number, wins: number } } = {} -- userId -> this week's wins as last known
local names: { [number]: string } = {}
local lastBoard: Board? = nil
local readFailing = false
local noIdLogged: { [string]: boolean } = {}

-- Public: pure helpers ---------------------------------------------------------------------------------------------

-- The board week of a Unix time: weeks start on Monday 00:00 UTC (Board.weekOffsetSeconds after the epoch).
function ShowOffService.weekIndex(t: number): number
	return math.floor((t - BOARD.weekOffsetSeconds) / SECONDS_PER_WEEK)
end

-- The store a server uses: BOARD.storeName live; in Studio nil (memory) unless studioMode is "datastore".
function ShowOffService.storeNameFor(isStudio: boolean, studioMode: string): string?
	if not isStudio then
		return BOARD.storeName
	end
	return if studioMode == "datastore" then BOARD.studioStoreName else nil
end

-- A participant of a MatchEnded summary that is a player: a Player behind it (the test dummy and a bot have none),
-- never the test dummy, and a userId > 0 except in Studio (local test players are -1, -2, ...).
local function isRealPart(part: any, isStudio: boolean): boolean
	if type(part) ~= "table" or part.isTestDummy == true or type(part.userId) ~= "number" then
		return false
	end
	if part.userId <= 0 and not isStudio then
		return false
	end
	local player = part.player
	local ok, yes = pcall(function(): boolean
		return player ~= nil and player:IsA("Player")
	end)
	return ok and yes == true
end

local function bothReal(summary: any, isStudio: boolean): boolean
	local parts = summary.participants
	return type(parts) == "table" and #parts == 2 and isRealPart(parts[1], isStudio) and isRealPart(parts[2], isStudio)
end

-- True when `part`'s result counts on the weekly board: a fully paid win (eligible, x1, Coins paid) in a duel between
-- two real players.
function ShowOffService.countsForBoard(summary: any, part: any, isStudio: boolean): boolean
	local reward = if type(part) == "table" then part.reward else nil
	return type(summary) == "table"
		and type(reward) == "table"
		and part.outcome == "win"
		and reward.eligible == true
		and reward.multiplier == 1
		and type(part.coinsGranted) == "number"
		and part.coinsGranted > 0
		and bothReal(summary, isStudio)
end

-- A board kept in memory (Studio): one table per week.
function ShowOffService.memoryStore(): (week: number) -> WeekStore
	local weeks: { [number]: { [string]: number } } = {}
	return function(week: number): WeekStore
		local values: { [string]: number } = weeks[week] or {}
		weeks[week] = values
		return {
			increment = function(key: string, delta: number): number
				values[key] = (values[key] or 0) + delta
				return values[key]
			end,
			get = function(key: string): number?
				return values[key]
			end,
			top = function(count: number): { Entry }
				local list: { Entry } = {}
				for key, value in values do
					table.insert(list, { key = key, value = value })
				end
				table.sort(list, function(a: Entry, b: Entry): boolean
					if a.value ~= b.value then
						return a.value > b.value
					end
					return a.key < b.key
				end)
				return { table.unpack(list, 1, math.min(count, #list)) }
			end,
		}
	end
end

-- The OrderedDataStore board `name` (one scope per week; `service` = DataStoreService unless a test passes a fake).
-- IncrementAsync and GetAsync check the ordered stores' own budget first (OrderedWrite / OrderedRead, the current
-- request types), so profile saves (StandardWrite) and the board never starve each other. GetSortedAsync is not
-- checked: the docs (Enum.DataStoreRequestType, 2026-10-13) say GetRequestBudgetForRequestType(OrderedList) always
-- returns 0, and one list a minute per server is far under its limit; a throttled list errors into the caller's pcall.
function ShowOffService.liveStore(name: string, service: any?): (week: number) -> WeekStore
	DataStoreAdapter.assertSafeName(name, RunService:IsStudio())
	local stores: any = service or DataStoreService
	local cache: { [number]: WeekStore } = {}
	local function spend(kind: Enum.DataStoreRequestType)
		if stores:GetRequestBudgetForRequestType(kind) <= 0 then
			error("no DataStore budget left right now", 0)
		end
	end
	return function(week: number): WeekStore
		local cached = cache[week]
		if cached then
			return cached
		end
		local ordered = stores:GetOrderedDataStore(name, "w" .. week)
		local store: WeekStore = {
			increment = function(key: string, delta: number): number
				spend(Enum.DataStoreRequestType.OrderedWrite)
				return ordered:IncrementAsync(key, delta)
			end,
			get = function(key: string): number?
				spend(Enum.DataStoreRequestType.OrderedRead)
				return ordered:GetAsync(key)
			end,
			top = function(count: number): { Entry }
				local list: { Entry } = {}
				for _, entry in ordered:GetSortedAsync(false, count):GetCurrentPage() do
					table.insert(list, { key = entry.key, value = entry.value })
				end
				return list
			end,
		}
		cache[week] = store
		return store
	end
end

-- Private ----------------------------------------------------------------------------------------------------------

local function defaultDeps(): Deps
	local isStudio = RunService:IsStudio()
	local name = ShowOffService.storeNameFor(isStudio, Config.Data.studioMode)
	local log: any = Log.new("ShowOff")
	return {
		now = function(): number
			return os.time()
		end,
		isStudio = function(): boolean
			return isStudio
		end,
		players = function(): { any }
			return Players:GetPlayers()
		end,
		profileOf = function(player: any): any?
			local port = StateService.dataPort()
			return if port.status(player) == "ready" then port.getProfile(player) else nil
		end,
		levelOf = GripService.levelOf,
		store = if name then ShowOffService.liveStore(name) else ShowOffService.memoryStore(),
		nameOf = function(userId: number): string?
			local info = UserService:GetUserInfosByUserIdsAsync({ userId })[1]
			return if info then info.DisplayName else nil
		end,
		hasBadge = function(userId: number, badgeId: number): boolean
			return BadgeService:UserHasBadgeAsync(userId, badgeId)
		end,
		awardBadge = function(userId: number, badgeId: number): boolean
			return BadgeService:AwardBadgeAsync(userId, badgeId)
		end,
		badges = function(): { any }
			return BADGES.list
		end,
		setTopWins = function(player: any, view: Types.TopWinsView)
			StateService.setSessionField(player, "topWins", view)
		end,
		isFriendMatch = FriendDuelService.isFriendMatch,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
		log = log,
	}
end

local deps: Deps = defaultDeps()

local function refreshStats(player: any)
	local s = stats[player]
	if s == nil then
		return
	end
	local profile = deps.profileOf(player)
	local won = if type(profile) == "table" and type(profile.stats) == "table" then profile.stats.duelsWon else nil
	if type(won) == "number" then
		s.wins.Value = won
	end
	s.level.Value = deps.levelOf(player)
	if type(profile) == "table" then
		s.income.Value = Format.coins(PenMath.rate(profile.pen)) -- qb1: a broken or missing pen earns 0
	end
end

-- The player's own line next to the last board read (nothing before the first one).
local function sendView(player: any)
	local board = lastBoard
	if board == nil or stats[player] == nil then
		return
	end
	local key = tostring(player.UserId)
	local own = mine[player.UserId]
	local wins = if own and own.week == board.week then own.wins else 0
	local place: number? = nil
	for index, entry in board.entries do
		if entry.key == key then
			place = index
			wins = math.max(wins, entry.value)
			break
		end
	end
	deps.setTopWins(player, { loaded = true, top = board.top, place = place, wins = wins })
end

local function nameFor(userId: number?): string
	if userId == nil then
		return Strings.board.someone
	end
	for _, player in deps.players() do
		if player.UserId == userId then
			return player.DisplayName
		end
	end
	local known = names[userId]
	if known then
		return known
	end
	local ok, name = pcall(deps.nameOf, userId)
	if ok and type(name) == "string" and name ~= "" then
		names[userId] = name
		return name
	end
	return Strings.board.someone
end

-- The player may be on the board: a userId > 0, or any local test player in Studio.
local function onBoard(player: any): boolean
	return player.UserId > 0 or deps.isStudio()
end

local function addWin(player: any)
	local userId = player.UserId
	deps.spawn(function()
		local week = ShowOffService.weekIndex(deps.now())
		-- shortcut: a failed increment is lost (no retry); add a retry queue if the board matters more
		local ok, total = pcall(function(): number
			return deps.store(week).increment(tostring(userId), 1)
		end)
		if not ok then
			deps.log:warn(`board: the win of user {userId} was not counted:`, total)
		elseif type(total) == "number" then
			mine[userId] = { week = week, wins = total }
			sendView(player)
		end
	end)
end

-- Public -------------------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults; nil restores every default) and forgets every board,
-- badge and player state (the leaderstats folders are destroyed).
function ShowOffService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	local given: { [string]: any } = overrides or {}
	for key, value in given do
		fresh[key] = value
	end
	deps = fresh
	for _, s in stats do
		s.folder:Destroy()
	end
	stats, badgeState, flags, awards, mine, names = {}, {}, {}, {}, {}, {}
	lastBoard, readFailing, noIdLogged = nil, false, {}
end

-- The player's leaderstats folder (tests).
function ShowOffService.leaderstatsOf(player: any): Folder?
	local s = stats[player]
	return if s then s.folder else nil
end

-- DataService Loaded: both columns from the profile.
function ShowOffService.profileLoaded(player: any)
	refreshStats(player)
end

-- GripService.LevelChanged(player, old, new, silent).
function ShowOffService.levelChanged(player: any, _old: number, new: number)
	local s = stats[player]
	if s then
		s.level.Value = new
	end
end

-- DuelService.MatchEnded: Wins re-read for the participants, a board point per counted win, and Duel Buddies for a
-- finished duel the pads or Rematch started.
function ShowOffService.handleMatchEnded(summary: any)
	if type(summary) ~= "table" or type(summary.participants) ~= "table" then
		return
	end
	local isStudio = deps.isStudio()
	local buddies = type(summary.matchId) == "string"
		and FINISHED[summary.outcome] == true
		and bothReal(summary, isStudio)
		and deps.isFriendMatch(summary.matchId)
	for _, part in summary.participants do
		local player = if type(part) == "table" then part.player else nil
		if player ~= nil and stats[player] ~= nil then
			refreshStats(player)
			if buddies then
				flags[player][FLAG_BUDDIES] = true
			end
			if ShowOffService.countsForBoard(summary, part, isStudio) then
				addWin(player)
			end
		end
	end
end

-- qb1: the Coins/s column of every player with a ready profile (the pen's rate now).
function ShowOffService.refreshIncome()
	for player, s in stats do
		local profile = deps.profileOf(player)
		if type(profile) == "table" then
			s.income.Value = Format.coins(PenMath.rate(profile.pen))
		end
	end
end

-- One board read: the week's top entries; then every player's view. A failure keeps the last board.
function ShowOffService.refreshBoard()
	local week = ShowOffService.weekIndex(deps.now())
	local ok, entries = pcall(function(): { Entry }
		return deps.store(week).top(BOARD.readSize)
	end)
	if not ok then
		if not readFailing then
			readFailing = true
			deps.log:warn("board: the weekly wins could not be read (keeping the last board):", entries)
		end
		if lastBoard == nil then
			-- No board yet (no API access, an outage, no budget): say so instead of "Checking the board…" forever.
			for _, player in deps.players() do
				local own = mine[player.UserId]
				local wins = if own and own.week == week then own.wins else 0
				deps.setTopWins(player, { loaded = true, unavailable = true, top = {}, wins = wins })
			end
		end
		return
	end
	readFailing = false
	local top: { Types.TopWinsLine } = {}
	for index = 1, math.min(BOARD.size, #entries) do
		local entry = entries[index]
		table.insert(top, { name = nameFor(tonumber(entry.key)), wins = entry.value })
	end
	lastBoard = { week = week, entries = entries, top = top }
	for _, player in deps.players() do
		sendView(player)
	end
end

-- Queues every earned badge that has an id and is not done this session (see the header for what is never awarded).
function ShowOffService.sweepBadges()
	local isStudio = deps.isStudio()
	local list = deps.badges()
	for _, player in deps.players() do
		local state = badgeState[player]
		local profile = deps.profileOf(player)
		if state == nil or profile == nil then
			continue
		end
		local earned = BadgeRules.earned(profile, deps.levelOf(player), flags[player], list)
		for _, badge in list do
			local key = badge.key
			if not earned[key] or state.done[key] or state.queued[key] then
				continue
			end
			if badge.id == nil then
				state.done[key] = true
				if not noIdLogged[key] then
					noIdLogged[key] = true
					deps.log:info(`badge {key} was earned but has no id yet (Config.Social.Badges): not awarded`)
				end
			elseif isStudio or player.UserId <= 0 then
				state.done[key] = true
				deps.log:debug(`would award {key} to user {player.UserId} (never in Studio or to a test player)`)
			else
				state.queued[key] = true
				table.insert(awards, { player = player, key = key, id = badge.id })
			end
		end
	end
end

-- Handles the queued awards one at a time (each BadgeService call yields).
function ShowOffService.processBadges()
	while #awards > 0 do
		local award = table.remove(awards, 1) :: Award
		local state = badgeState[award.player]
		if state == nil then
			continue -- left meanwhile
		end
		state.queued[award.key] = nil
		local userId = award.player.UserId
		local ok, err = pcall(function()
			if not deps.hasBadge(userId, award.id) then
				deps.awardBadge(userId, award.id)
			end
		end)
		local tries = if ok then 0 else (state.tries[award.key] or 0) + 1
		state.tries[award.key] = tries
		if ok or tries >= BADGES.maxTries then
			state.done[award.key] = true
		end
		if not ok and tries >= BADGES.maxTries then
			deps.log:warn(`badge {award.key} for user {userId} failed {tries} times; not tried again:`, err)
		end
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function ShowOffService.init()
	StateService.dataPort().onLoaded(ShowOffService.profileLoaded)
	GripService.LevelChanged:connect(ShowOffService.levelChanged)
	DuelService.MatchEnded:connect(ShowOffService.handleMatchEnded)
end

function ShowOffService.start()
	task.spawn(function()
		while true do
			local ok, err = pcall(function(): any
				ShowOffService.refreshIncome()
				return nil
			end)
			if not ok then
				deps.log:warn("Coins/s refresh failed:", err)
			end
			task.wait(INCOME_REFRESH_SECONDS)
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				ShowOffService.sweepBadges()
				ShowOffService.processBadges()
			end)
			if not ok then
				deps.log:warn("badge check failed:", err)
			end
			task.wait(BADGES.checkSeconds)
		end
	end)
	while true do
		local ok, err = pcall(function(): any
			ShowOffService.refreshBoard()
			return nil
		end)
		if not ok then
			deps.log:warn("board refresh failed:", err)
		end
		task.wait(BOARD.refreshSeconds)
	end
end

function ShowOffService.playerAdded(player: Player)
	if stats[player] ~= nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local wins = Instance.new("IntValue")
	wins.Name = Strings.social.statWins
	wins.Parent = folder
	local level = Instance.new("IntValue")
	level.Name = Strings.social.statLevel
	level.Parent = folder
	local income = Instance.new("StringValue")
	income.Name = Strings.social.statIncome
	income.Value = Format.coins(0)
	income.Parent = folder
	stats[player] = { folder = folder, wins = wins, level = level, income = income }
	badgeState[player] = { done = {}, tries = {}, queued = {} }
	flags[player] = {}
	refreshStats(player)
	if typeof(player) == "Instance" then
		folder.Parent = player
	end
	if onBoard(player) then
		local userId = player.UserId
		deps.spawn(function()
			local week = ShowOffService.weekIndex(deps.now())
			local ok, value = pcall(function(): number?
				return deps.store(week).get(tostring(userId))
			end)
			if ok and stats[player] ~= nil then
				mine[userId] = { week = week, wins = if type(value) == "number" then value else 0 }
				sendView(player)
			end
		end)
	end
end

function ShowOffService.playerRemoving(player: Player)
	local s = stats[player]
	if s then
		s.folder:Destroy()
	end
	stats[player], badgeState[player], flags[player] = nil, nil, nil
	mine[player.UserId] = nil
end

return ShowOffService
