--!strict
-- QuestService (server only). DESIGN §6.8, §2.8 (QuestClaim, QuestSwap, DuelResult.questProgress), §3.4 (quest and
-- starter claims), §12 #3, #14 (§17.10's starter task starter_jelly went with the giant pads, build plan Phase 6).
-- Daily quests and starter tasks. The rules are the pure Logic/QuestLogic and the data is QuestDefs; this module owns
-- the profile writes (DataService.mutate through the data port), the Coins (EconomyService.grantCoins), the toasts and
-- the saves.
-- * Quests of the day (ensureQuests): on DataService.Loaded (READY profiles only) and every
--   Config.Economy.Quests.rolloverCheckSeconds for every online player, when profile.quests.day ~= today (the UTC day
--   of os.time(); also right before any event or claim, so events count for the day of their server time):
--   QuestLogic.rollover -> every done-but-unclaimed quest of the old day is granted once (claimed = true first, then
--   grantCoins "quest", toast quest.autoCollected {coins}); unfinished ones expire; then QuestLogic.generate (the
--   owned ids, sorted by QuestLogic; the equipped squishy from the profile) for today with swapsUsed = 0.
--   Reading: a stored day AFTER today (another server's clock ran ahead) is kept, never rolled backwards, so the same
--   day can never be generated (and claimed) twice.
-- * Progress comes ONLY from server hooks, after their own validation (no remote ever reports progress):
--     SqueezeService.Squeezed(p, squishyId, coins, tier) -> {kind = "squeeze", squishyId} (daily quests and
--       starter tasks);
--     PracticeService.TargetHit(p, targetId, t, countsForQuest), only when countsForQuest (each target at most once
--       per 2 s) -> {kind = "practiceHit"} (practice_hits and, Reading, starter_practice: the same confirmed hits);
--     CombatService.Hit(info) for the attacker's Player -> {kind = "hit", squishyId = info.attacker.squishyId} (the
--       match snapshot), held per match and applied with the result (Reading: §6.8 "Cancelled, Void ... never count
--       for duel templates", so the hits of a cancelled or void match are dropped, and the "Quest complete!" toast
--       never shows mid-duel);
--     DuelService's questProgress result hook (setResultHooks, from init; Reading, see DuelService's header: DuelResult
--       carries the lines and goes out before MatchEnded, so the duel counts here and never on MatchEnded as well)
--       -> the held hits, then {kind = "duel", outcome = the participant's view, squishyId = its match snapshot,
--       throws = its accepted throws} (duel_finish and starter_duel count a win / loss / draw with >= minOwnThrows
--       own throws; duel_win and duel_win_with count every win, §6.8). It returns DuelResult.questProgress: one
--       {questId, progress, goal, done} line per quest this match moved (Reading: the hits and the result).
--   QuestService never listens to GripService: slow-training ticks, level-ups and profile loads never move a quest or
--   a starter task (§17.7, §17.12: idling alone never earns a starter task's Coins).
--   A quest that becomes done shows quest.complete ("Quest complete! Claim your reward.").
-- * QuestClaim(questId) (claim): profile READY (data.notReady); a starter id or a daily quest of today (else
--   net.invalid); already claimed (also a quest of yesterday the rollover just collected) -> quest.alreadyClaimed
--   (Reading of §3.4's "ok semantics": nothing changes and the code says why; the client treats the quest as
--   claimed); not done -> quest.notReady; else claimed = true and
--   grantCoins(reward, "quest") (a daily quest) or "starter" (a starter task), markDirty("quests") and a "soon" save.
--   Every reward is counted in squeezes (spec 2026-10-12 §9) and pays reward × the squeeze value of the moment it is
--   granted (EconomyService.rewardCoins), the rollover's auto-collected ones included.
-- * QuestSwap(questId) (swap): one free swap per day (Economy.Quests.freeSwapsPerDay) of an unfinished daily quest
--   through QuestLogic.swap (seeded with the swap number): quest.swapUsed once used, net.invalid for anything else
--   (no such quest, done, a starter task); a swap is saved "soon" (Reading: DESIGN names no save; the seed makes a
--   lost swap repeat identically, so this only keeps the list stable). No paid swaps, skips or rerolls, ever.
-- Studio only (RunService:IsStudio() and Config.Debug.debugHooks): debugState(p), debugSetProgress(p, questId,
-- progress), debugRollover(p, day?).
-- Collaborators are injectable (useDeps) for unit tests; init() wires the signals and remotes and never yields;
-- destroy() unwires them (tests, leak checks).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local QuestDefs = require(Shared.QuestDefs)
local TableUtil = require(Shared.Util.TableUtil)
local TimeUtil = require(Shared.Util.TimeUtil)
local Types = require(Shared.Types)
local QuestLogic = require(script.Parent.Parent.Logic.QuestLogic)
local Services = script.Parent
local CombatService = require(Services.CombatService)
local DuelService = require(Services.DuelService)
local EconomyService = require(Services.EconomyService)
local NetService = require(Services.NetService)
local PracticeService = require(Services.PracticeService)
local SqueezeService = require(Services.SqueezeService)
local StateService = require(Services.StateService)

-- Types

type QuestEntry = Types.QuestEntry
type QuestLine = Types.QuestProgressLine
type QuestEvent = QuestLogic.QuestEvent

export type Deps = {
	data: StateService.DataPort,
	markDirty: (player: any, field: string) -> (),
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
	unixNow: () -> number, -- os.time: the UTC day
	userIdOf: (player: any) -> number,
	onlinePlayers: () -> { any }, -- the rollover check
	debugAllowed: () -> boolean,
	-- The seeded generator QuestLogic uses (nil = Random.new(seed)); tests pass FakeRng.new so every runner repeats.
	newRng: QuestLogic.NewRng?,
}

-- What one rollover did (ensureQuests; debugRollover returns it).
-- `claimedIds` = the quests of the old day it granted automatically.
export type RolloverSummary = {
	generated: boolean,
	autoClaimed: number,
	coins: number,
	day: number,
	claimedIds: { string },
}

-- The hits a player landed in one match, applied with its result.
type HeldHits = { matchId: string, squishyIds: { string } }

-- Constants

local FIELD = "quests"
local STATUS_READY = "ready"
local SAVE_SOON = "soon"
local REMOTE_CLAIM = "QuestClaim"
local REMOTE_SWAP = "QuestSwap"
local REASON_QUEST = "quest"
local REASON_STARTER = "starter"
local KIND_STARTER = "starter"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_ALREADY = "quest.alreadyClaimed"
local CODE_QUEST_NOT_READY = "quest.notReady"
local NOTICE_COMPLETE = "quest.complete"
local NOTICE_AUTO = "quest.autoCollected"
local FINISHED: { [string]: boolean } = { win = true, loss = true, draw = true }
-- Reading (DESIGN gives no number): the hits held per match are bounded; a duel ends long before this.
local MAX_HELD_HITS = 100

-- Module table

local QuestService = {}

-- Private

local log = Log.new("Quest")
local heldHits: { [any]: HeldHits } = {}
local cleanup: Cleanup.Cleanup? = nil
local loopThread: thread? = nil

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		grantCoins = function(player: any, amount: number, reason: string): (number, string?)
			return EconomyService.grantCoins(player, amount, reason)
		end,
		unixNow = os.time,
		userIdOf = function(player: any): number
			local ok, id = pcall(function(): any
				return player.UserId
			end)
			return if ok and type(id) == "number" then id else 0
		end,
		onlinePlayers = function(): { any }
			return Players:GetPlayers()
		end,
		debugAllowed = function(): boolean
			return RunService:IsStudio() and Config.Debug.debugHooks == true
		end,
	}
end

local deps: Deps = defaultDeps()

local function isReady(player: any): boolean
	return deps.data.status(player) == STATUS_READY
end

local function today(): number
	return TimeUtil.utcDay(deps.unixNow())
end

local function whole(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return math.floor(n)
end

-- profile.quests when it has the stored shape, else nil (a malformed record is replaced by the next rollover).
local function questsOf(profile: any): Types.QuestsState?
	local quests = if type(profile) == "table" then profile.quests else nil
	if type(quests) ~= "table" or type(quests.day) ~= "number" or type(quests.active) ~= "table" then
		return nil
	end
	return quests :: Types.QuestsState
end

-- profile.starter with both maps, created inside a mutate when missing (only call it on the live profile in mutate).
local function liveStarter(profile: any): Types.StarterState
	local starter = profile.starter
	if type(starter) ~= "table" then
		starter = {}
		profile.starter = starter
	end
	if type(starter.progress) ~= "table" then
		starter.progress = {}
	end
	if type(starter.claimed) ~= "table" then
		starter.claimed = {}
	end
	return starter :: Types.StarterState
end

-- A read-only starter view of a profile (empty maps when missing).
local function readStarter(profile: any): Types.StarterState
	local starter = if type(profile) == "table" then profile.starter else nil
	if type(starter) ~= "table" then
		return { progress = {}, claimed = {} }
	end
	return {
		progress = if type(starter.progress) == "table" then starter.progress else {},
		claimed = if type(starter.claimed) == "table" then starter.claimed else {},
	}
end

local function starterRow(starter: Types.StarterState, id: string): QuestLogic.StarterTaskView?
	for _, row in QuestLogic.starterView(starter) do
		if row.id == id then
			return row
		end
	end
	return nil
end

local function findEntry(list: { QuestEntry }, id: string): QuestEntry?
	for _, entry in list do
		if type(entry) == "table" and entry.id == id then
			return entry
		end
	end
	return nil
end

-- The owned squishy ids of a profile (QuestLogic filters and sorts them).
local function ownedOf(profile: any): { string }
	local list: { string } = {}
	if type(profile) == "table" and type(profile.owned) == "table" then
		for id in profile.owned do
			if type(id) == "string" then
				table.insert(list, id)
			end
		end
	end
	table.sort(list)
	return list
end

local function equippedOf(profile: any): string?
	local equipped = if type(profile) == "table" then profile.equipped else nil
	return if type(equipped) == "string" then equipped else nil
end

-- Marks a daily entry claimed (in the live profile) and pays its reward once. The claim is written first, then the
-- Coins (nothing yields in between): a quest can never pay twice. The reward is counted in squeezes and paid at the
-- squeeze value of that moment (EconomyService.rewardCoins, spec 2026-10-12 §9). Returns the Coins added, or nil when
-- the entry was already claimed or the session takes no changes.
local function claimDaily(player: any, questId: string): number?
	local reward = 0
	local ok, marked = deps.data.mutate(player, function(profile: any): boolean
		local quests = questsOf(profile)
		local entry = if quests then findEntry(quests.active, questId) else nil
		if entry == nil or entry.claimed == true then
			return false
		end
		entry.claimed = true
		reward = whole(entry.reward)
		return true
	end)
	if not ok or marked ~= true then
		return nil
	end
	local added = 0
	if reward > 0 then
		local amount = EconomyService.rewardCoins(deps.data.getProfile(player), reward)
		local coins, failure = deps.grantCoins(player, amount, REASON_QUEST)
		added = coins
		if failure ~= nil then
			log:error(`user {deps.userIdOf(player)}: quest {questId} was claimed but its Coins failed ({failure})`)
		end
	end
	return added
end

-- The same for a starter task (reward from QuestDefs).
local function claimStarter(player: any, id: string): number?
	local def = QuestDefs.get(id)
	if def == nil or def.kind ~= KIND_STARTER then
		return nil
	end
	local ok, marked = deps.data.mutate(player, function(profile: any): boolean
		local starter = liveStarter(profile)
		if starter.claimed[id] == true then
			return false
		end
		starter.claimed[id] = true
		return true
	end)
	if not ok or marked ~= true then
		return nil
	end
	local reward = whole(def.variants[1].reward)
	local added = 0
	if reward > 0 then
		local amount = EconomyService.rewardCoins(deps.data.getProfile(player), reward)
		local coins, failure = deps.grantCoins(player, amount, REASON_STARTER)
		added = coins
		if failure ~= nil then
			log:error(`user {deps.userIdOf(player)}: starter task {id} was claimed but its Coins failed ({failure})`)
		end
	end
	return added
end

-- The day's quests (see the header). Returns what happened; nothing for a profile that is not READY.
local function rollover(player: any, day: number): RolloverSummary
	local summary: RolloverSummary = { generated = false, autoClaimed = 0, coins = 0, day = day, claimedIds = {} }
	if not isReady(player) then
		return summary
	end
	local profile = deps.data.getProfile(player)
	if type(profile) ~= "table" then
		return summary
	end
	local quests = questsOf(profile)
	if quests ~= nil and quests.day >= day then
		return summary -- today's quests (or a day from a clock that ran ahead: kept)
	end
	-- 1. Done-but-unclaimed quests of the old day are granted once.
	if quests ~= nil then
		local roll = QuestLogic.rollover(quests, day)
		local ids: { string } = {}
		for _, entry in roll.autoClaim do
			table.insert(ids, entry.id)
		end
		for _, id in ids do
			local added = claimDaily(player, id)
			if added ~= nil then
				summary.autoClaimed += 1
				table.insert(summary.claimedIds, id)
				summary.coins += added
				local args: Types.NotifyArgs = { coins = added }
				deps.notify(player, NOTICE_AUTO, args, "success")
			end
		end
	end
	-- 2. Today's quests.
	local fresh = QuestLogic.generate({
		userId = deps.userIdOf(player),
		day = day,
		owned = ownedOf(profile),
		equipped = equippedOf(profile),
	}, deps.newRng)
	local ok = deps.data.mutate(player, function(live: any): boolean
		live.quests = { day = day, swapsUsed = 0, active = fresh }
		return true
	end)
	summary.generated = ok
	if ok then
		deps.markDirty(player, FIELD)
	end
	return summary
end

-- Applies server-confirmed events to the daily quests and the starter tasks in one write. Returns one line per quest
-- or task the events moved (the last state of each), and toasts the ones that became done.
local function applyEvents(player: any, events: { QuestEvent }): { QuestLine }
	if #events == 0 or not isReady(player) then
		return {}
	end
	rollover(player, today()) -- events count for the day of their server time
	local order: { string } = {}
	local byId: { [string]: QuestLine } = {}
	local completed: { string } = {}
	local function record(line: QuestLine)
		if byId[line.questId] == nil then
			table.insert(order, line.questId)
		end
		byId[line.questId] = line
	end
	local ok = deps.data.mutate(player, function(profile: any): boolean
		local quests = questsOf(profile)
		local starter = liveStarter(profile)
		for _, event in events do
			if quests ~= nil then
				for _, line in QuestLogic.apply(quests.active, event) do
					record(line)
					if line.done then
						table.insert(completed, line.questId) -- apply skips done quests: this one just finished
					end
				end
			end
			local changed = QuestLogic.applyStarter(starter, event)
			if #changed > 0 then
				for _, row in QuestLogic.starterView(starter) do
					if table.find(changed, row.id) ~= nil then
						record({ questId = row.id, progress = row.progress, goal = row.goal, done = row.done })
						if row.done then
							table.insert(completed, row.id) -- applyStarter moves unfinished tasks only
						end
					end
				end
			end
		end
		return true
	end)
	if not ok then
		return {}
	end
	local lines: { QuestLine } = {}
	for _, id in order do
		table.insert(lines, byId[id])
	end
	if #lines > 0 then
		deps.markDirty(player, FIELD)
	end
	for _ = 1, #completed do
		deps.notify(player, NOTICE_COMPLETE, nil, "success")
	end
	return lines
end

-- Public: progress hooks -----------------------------------------------------------------------------------------------

-- SqueezeService.Squeezed: an accepted squeeze (paid or not). Its coins and tier are not needed here.
function QuestService.onSqueezed(player: any, squishyId: string)
	applyEvents(player, { { kind = "squeeze", squishyId = squishyId } })
end

-- PracticeService.TargetHit: a confirmed practice target hit; only `countsForQuest` hits count.
function QuestService.onTargetHit(player: any, _targetId: string, _hitTime: number, countsForQuest: boolean)
	if countsForQuest == true then
		applyEvents(player, { { kind = "practiceHit" } })
	end
end

-- CombatService.Hit: a server-confirmed duel hit. Held for the attacker's Player until the match result.
function QuestService.onHit(info: any)
	local attacker = if type(info) == "table" then info.attacker else nil
	local player = if type(attacker) == "table" then attacker.player else nil
	if player == nil or attacker.isTestDummy == true or type(info.matchId) ~= "string" then
		return
	end
	local held = heldHits[player]
	if held == nil or held.matchId ~= info.matchId then
		held = { matchId = info.matchId, squishyIds = {} }
		heldHits[player] = held
	end
	if #held.squishyIds < MAX_HELD_HITS and type(attacker.squishyId) == "string" then
		table.insert(held.squishyIds, attacker.squishyId)
	end
end

-- DuelService's questProgress result hook: the held hits and the result of one real participant. Returns
-- DuelResult.questProgress.
function QuestService.onDuelResult(
	player: any,
	summary: DuelService.ParticipantSummary,
	info: DuelService.ResultInfo
): { QuestLine }
	local held = heldHits[player]
	heldHits[player] = nil
	if not FINISHED[summary.outcome] then
		return {} -- cancelled and void never count, nor do their hits (§6.8)
	end
	local events: { QuestEvent } = {}
	if held ~= nil and held.matchId == info.matchId then
		for _, squishyId in held.squishyIds do
			table.insert(events, { kind = "hit", squishyId = squishyId })
		end
	end
	local outcome: string = summary.outcome
	local duel: QuestEvent = {
		kind = "duel",
		outcome = outcome,
		squishyId = summary.squishyId,
		throws = summary.throws,
	}
	table.insert(events, duel)
	return applyEvents(player, events)
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Makes sure a READY profile holds today's quests (rollover with auto-claims, then generation). Returns true when new
-- quests were generated. Never yields.
function QuestService.ensureQuests(player: any): boolean
	return rollover(player, today()).generated
end

-- The QuestClaim RF (see the header). Returns NetService.ok() or NetService.err(reason).
function QuestService.claim(player: any, questId: unknown): any
	if type(questId) ~= "string" then
		return NetService.err(CODE_INVALID)
	end
	if not isReady(player) then
		return NetService.err(CODE_NOT_READY)
	end
	-- Reading: a claim of yesterday's quest that arrives just after midnight finds it collected by the rollover
	-- (quest.autoCollected), so it answers quest.alreadyClaimed instead of net.invalid.
	if table.find(rollover(player, today()).claimedIds, questId) ~= nil then
		return NetService.err(CODE_ALREADY)
	end
	local profile = deps.data.getProfile(player)
	local def = QuestDefs.get(questId)
	local added: number?
	if def ~= nil and def.kind == KIND_STARTER then
		local row = starterRow(readStarter(profile), questId)
		if row == nil then
			return NetService.err(CODE_INVALID)
		elseif row.claimed then
			return NetService.err(CODE_ALREADY)
		elseif not row.done then
			return NetService.err(CODE_QUEST_NOT_READY)
		end
		added = claimStarter(player, questId)
	else
		local quests = questsOf(profile)
		local entry = if quests then findEntry(quests.active, questId) else nil
		if entry == nil then
			return NetService.err(CODE_INVALID)
		elseif entry.claimed == true then
			return NetService.err(CODE_ALREADY)
		elseif entry.done ~= true then
			return NetService.err(CODE_QUEST_NOT_READY)
		end
		added = claimDaily(player, questId)
	end
	if added == nil then
		return NetService.err(CODE_NOT_READY) -- the session stopped taking changes (its final save started)
	end
	deps.markDirty(player, FIELD)
	deps.data.requestSave(player, SAVE_SOON)
	return NetService.ok(nil)
end

-- The QuestSwap RF (see the header). Returns NetService.ok() or NetService.err(reason).
function QuestService.swap(player: any, questId: unknown): any
	if type(questId) ~= "string" then
		return NetService.err(CODE_INVALID)
	end
	if not isReady(player) then
		return NetService.err(CODE_NOT_READY)
	end
	rollover(player, today())
	local profile = deps.data.getProfile(player)
	local quests = questsOf(profile)
	if quests == nil then
		return NetService.err(CODE_INVALID)
	end
	local swapNumber = whole(quests.swapsUsed) + 1
	local swapped, reason = QuestLogic.swap(quests.active, questId, {
		userId = deps.userIdOf(player),
		day = quests.day,
		swapNumber = swapNumber,
		owned = ownedOf(profile),
		equipped = equippedOf(profile),
	}, deps.newRng)
	if swapped == nil then
		return NetService.err(reason or CODE_INVALID)
	end
	local day = quests.day
	local ok, written = deps.data.mutate(player, function(live: any): boolean
		local current = questsOf(live)
		if current == nil or current.day ~= day or whole(current.swapsUsed) + 1 ~= swapNumber then
			return false
		end
		current.active = swapped
		current.swapsUsed = swapNumber
		return true
	end)
	if not ok or written ~= true then
		return NetService.err(CODE_NOT_READY)
	end
	deps.markDirty(player, FIELD)
	deps.data.requestSave(player, SAVE_SOON)
	return NetService.ok(nil)
end

-- Public: Studio debug -------------------------------------------------------------------------------------------------

-- The player's quests, starter tasks and held hits (copies).
function QuestService.debugState(player: any): { [string]: any }
	local profile = deps.data.getProfile(player)
	local quests = questsOf(profile)
	local held = heldHits[player]
	return {
		status = deps.data.status(player),
		today = today(),
		day = if quests then quests.day else nil,
		swapsUsed = if quests then quests.swapsUsed else nil,
		active = if quests then TableUtil.deepCopy(quests.active) else {},
		starter = QuestLogic.starterView(readStarter(profile)),
		heldHits = if held then #held.squishyIds else 0,
	}
end

-- Studio only: sets the progress of a daily quest or a starter task (clamped to 0..goal; done follows), e.g. to test a
-- claim or the rollover auto-claim. Never pays and never toasts.
function QuestService.debugSetProgress(player: any, questId: unknown, progress: unknown): (boolean, string?)
	if not deps.debugAllowed() then
		return false, "Studio only"
	end
	if type(questId) ~= "string" or type(progress) ~= "number" or progress ~= progress then
		return false, "questId must be a string and progress a number"
	end
	local def = QuestDefs.get(questId)
	local ok, found = deps.data.mutate(player, function(profile: any): boolean
		if def ~= nil and def.kind == KIND_STARTER then
			local starter = liveStarter(profile)
			starter.progress[questId] = math.clamp(whole(progress), 0, def.variants[1].goal)
			return true
		end
		local quests = questsOf(profile)
		local entry = if quests then findEntry(quests.active, questId) else nil
		if entry == nil then
			return false
		end
		entry.progress = math.clamp(whole(progress), 0, whole(entry.goal))
		entry.done = entry.progress >= entry.goal
		return true
	end)
	if not ok then
		return false, "profile not ready"
	elseif found ~= true then
		return false, "no such quest today"
	end
	deps.markDirty(player, FIELD)
	return true, nil
end

-- Studio only: runs the day rollover now, as if the stored quests were from `day` (default yesterday): done-but-
-- unclaimed quests are auto-collected, then today's quests are generated. Returns the summary.
function QuestService.debugRollover(player: any, day: unknown): (RolloverSummary?, string?)
	if not deps.debugAllowed() then
		return nil, "Studio only"
	end
	local now = today()
	local from = if day == nil then now - 1 else day
	if type(from) ~= "number" or from ~= from or math.floor(from) ~= from or from >= now then
		return nil, "day must be a whole day index before today"
	end
	local ok = deps.data.mutate(player, function(profile: any): boolean
		local quests = questsOf(profile)
		if quests == nil then
			return false
		end
		quests.day = from
		return true
	end)
	if not ok then
		return nil, "profile not ready"
	end
	return rollover(player, now), nil
end

-- Public: tests --------------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults); nil restores every default. Forgets the held hits.
function QuestService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	table.clear(heldHits)
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function QuestService.init()
	local c = Cleanup.new()
	cleanup = c
	-- The data port's signals cannot be disconnected one by one, so destroy() switches this handler off instead.
	local active = true
	c:add(function()
		active = false
	end)
	deps.data.onLoaded(function(player: any)
		if active then
			QuestService.ensureQuests(player)
		end
	end)
	c:add(SqueezeService.Squeezed:connect(QuestService.onSqueezed))
	c:add(PracticeService.TargetHit:connect(QuestService.onTargetHit))
	c:add(CombatService.Hit:connect(QuestService.onHit))
	DuelService.setResultHooks({ questProgress = QuestService.onDuelResult })
	c:add(function()
		DuelService.setResultHooks({
			questProgress = function(): { QuestLine }
				return {}
			end,
		})
	end)
	c:add(NetService.onInvoke(REMOTE_CLAIM, function(player: Player, questId: any): any
		return QuestService.claim(player, questId)
	end))
	c:add(NetService.onInvoke(REMOTE_SWAP, function(player: Player, questId: any): any
		return QuestService.swap(player, questId)
	end))
end

-- The rollover check: every rolloverCheckSeconds, every online player whose quests are not today's.
function QuestService.start()
	if loopThread ~= nil then
		return
	end
	loopThread = task.spawn(function()
		while true do
			task.wait(Config.Economy.Quests.rolloverCheckSeconds)
			local day = today()
			for _, player in deps.onlinePlayers() do
				local ok, err = pcall(rollover, player, day)
				if not ok then
					log:error(`quest rollover failed for user {deps.userIdOf(player)}:`, err)
				end
			end
		end
	end)
end

function QuestService.playerAdded(player: Player)
	QuestService.ensureQuests(player) -- a profile that finished loading before this hook ran
end

function QuestService.playerRemoving(player: Player)
	heldHits[player] = nil
end

-- Not called by the bootstrap; unwires the signals, remotes and hook and stops the loop (tests, leak checks).
function QuestService.destroy()
	local thread = loopThread
	loopThread = nil
	if thread and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
	local c = cleanup
	cleanup = nil
	if c then
		c:clean()
	end
	table.clear(heldHits)
end

return QuestService
