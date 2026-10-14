--!strict
-- QuestLogic (server only, pure): daily quest generation, swap, progress, starter tasks and the day rollover
-- (DESIGN §6.8, §17.10). No instances, no yields, no remotes: QuestService feeds it server-confirmed events and owns the
-- profile writes, Coins and saves. Randomness comes only from a seeded Random (or an injected factory in tests), so the
-- same player and day always get the same quests (a crash gives no free reroll).
--
-- API:
--   QuestLogic.seed(userId, day, swapNumber?) -> userId * 100000 + day % 100000 + 7919 * (swapNumber or 0)
--   QuestLogic.generate(ctx, newRng?) -> { QuestEntry }: Config.Economy.Quests.perDay quests for ctx.day.
--       ctx = {userId, day, owned = { squishyId }, equipped}. Slot 1 = a squeeze template, slot 2 = a duel template,
--       slots 3.. = any template not already chosen; per slot (with Random.new(seed(userId, day))): the template, then
--       the variant, then (needsSquishy) the squishy: the equipped one with equippedPickChance if it is owned, else
--       uniform over the sorted owned list. Ids "q<day>_<slot>"; progress 0, done/claimed false.
--   QuestLogic.swap(entries, questId, ctx, newRng?) -> (entries?, reason?): replaces one unfinished daily quest with a
--       template not in the list, preferring another category (Random.new(seed(userId, day, swapNumber))); the new
--       quest keeps the id (slot). ctx = {userId, day, swapNumber, owned, equipped}; swapNumber = quests.swapsUsed + 1.
--       Reasons: "net.invalid" (no such quest, not a daily quest, already done or claimed, nothing to swap to),
--       "quest.swapUsed" (swapNumber above Economy.Quests.freeSwapsPerDay). Returns a new list (the input is unchanged).
--   QuestLogic.apply(entries, event) -> { QuestProgressLine }: advances the daily quests the event counts for (in place,
--       capped at the goal; done = progress >= goal) and returns one line per quest it changed.
--   QuestLogic.applyStarter(starter, event) -> { starterId }: the same for profile.starter (progress map, in place);
--       claimed tasks never move.
--   QuestLogic.starterView(starter) -> { StarterTaskView } {id, progress, goal, reward, done, claimed} in table order
--   QuestLogic.rollover(quests, today) -> {autoClaim = { QuestEntry }, regenerate}: when quests.day ~= today, the
--       done-but-unclaimed entries (the same tables: QuestService sets claimed and grants each once, toast
--       quest.autoCollected) and regenerate = true; unfinished quests expire with no reward. Same day: nothing.
--
-- Events (from server hooks only, after validation; no remote ever reports progress):
--   {kind = "squeeze", squishyId}              an accepted squeeze (paid or not)
--   {kind = "duel", outcome, squishyId, throws} a match result for one real participant; outcome win/loss/draw/
--                                               cancelled/void, squishyId = the match snapshot's, throws = own accepted
--   {kind = "hit", squishyId}                  a server-confirmed hit on the duel opponent
--   {kind = "practiceHit"}                     a server-confirmed practice target hit (each target <= once per 2 s)
--
-- Readings:
--   * A finished duel (duel_finish, starter_duel) = win, loss or draw with >= Config.Economy.DuelRewards.minOwnThrows
--     own throws; cancelled and void never count. duel_win / duel_win_with count every "win" outcome with no throw
--     minimum (§6.8 "wins (incl. forfeit wins after 20 s)"; a bail before EarlyForfeitSeconds is Cancelled, never a
--     win). Part 7 review fix: they used to need the 3 own throws as well.
--   * `owned` is filtered to Catalog ids and sorted here as well (callers may pass profile order); an empty list falls
--     back to the starter (ProfileSchema.sanitize keeps it owned), so a quest never names an unowned squishy.
--   * swap refuses a done quest with net.invalid (the UI never offers Swap on one, and §2.10 has no closer code).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local QuestDefs = require(Shared.QuestDefs)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)

-- Types

export type QuestEntry = Types.QuestEntry
export type QuestProgressLine = Types.QuestProgressLine
export type StarterState = Types.StarterState
export type QuestsState = Types.QuestsState
export type QuestDef = QuestDefs.QuestDef

export type NewRng = (seed: number) -> Random

export type GenerateContext = { userId: number, day: number, owned: { string }, equipped: string? }
export type SwapContext = { userId: number, day: number, swapNumber: number, owned: { string }, equipped: string? }

export type EventKind = "squeeze" | "duel" | "hit" | "practiceHit"
export type QuestEvent = {
	kind: EventKind,
	squishyId: string?, -- squeeze, duel, hit
	outcome: string?, -- duel: "win" | "loss" | "draw" | "cancelled" | "void"
	throws: number?, -- duel
}

export type StarterTaskView = {
	id: string,
	progress: number,
	goal: number,
	reward: number,
	done: boolean,
	claimed: boolean,
}

export type Rollover = { autoClaim: { QuestEntry }, regenerate: boolean }

-- Constants

local SEED_USER_STEP = 100000
local SEED_DAY_MODULUS = 100000
local SEED_SWAP_STEP = 7919
local SLOT_CATEGORY: { [number]: string } = { "squeeze", "duel" } -- slot 3 and later: any category
local FINISHED_OUTCOMES = { win = true, loss = true, draw = true }

-- Module table

local QuestLogic = {}

-- Private

local function whole(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return math.floor(n)
end

local function makeRng(newRng: NewRng?, seed: number): Random
	if newRng ~= nil then
		return newRng(seed)
	end
	return Random.new(seed)
end

-- The owned squishies a quest may name: Catalog ids only, no duplicates, sorted.
local function ownedList(owned: { string }): { string }
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	if type(owned) == "table" then
		for _, id in owned do
			if type(id) == "string" and not seen[id] and Catalog.isValidId(id) then
				seen[id] = true
				table.insert(list, id)
			end
		end
	end
	table.sort(list)
	if #list == 0 then
		list = { Catalog.starterId() }
	end
	return list
end

local function pickSquishy(rng: Random, owned: { string }, equipped: string?): string
	if equipped ~= nil and table.find(owned, equipped) ~= nil then
		if rng:NextNumber() < Config.Economy.Quests.equippedPickChance then
			return equipped
		end
	end
	return owned[rng:NextInteger(1, #owned)]
end

local function newEntry(rng: Random, def: QuestDef, id: string, owned: { string }, equipped: string?): QuestEntry
	local variant = def.variants[rng:NextInteger(1, #def.variants)]
	local squishy = if def.needsSquishy then pickSquishy(rng, owned, equipped) else nil
	return {
		id = id,
		def = def.id,
		squishy = squishy,
		progress = 0,
		goal = variant.goal,
		reward = variant.reward,
		done = false,
		claimed = false,
	}
end

local function questId(day: number, slot: number): string
	return string.format("q%d_%d", day, slot)
end

local function finishedDuel(event: QuestEvent): boolean
	return event.kind == "duel"
		and type(event.outcome) == "string"
		and FINISHED_OUTCOMES[event.outcome] == true
		and whole(event.throws) >= Config.Economy.DuelRewards.minOwnThrows
end

-- True when `event` advances a quest of this def (`squishy` = the quest's squishy, nil for starter tasks).
local function counts(def: QuestDef, squishy: string?, event: QuestEvent): boolean
	local rule = def.counts
	local sameSquishy = squishy ~= nil and event.squishyId == squishy
	if rule == "squeeze" then
		return event.kind == "squeeze"
	elseif rule == "squeezeWith" then
		return event.kind == "squeeze" and sameSquishy
	elseif rule == "duelFinish" then
		return finishedDuel(event)
	elseif rule == "duelWin" then
		return event.kind == "duel" and event.outcome == "win"
	elseif rule == "duelWinWith" then
		return event.kind == "duel" and event.outcome == "win" and sameSquishy
	elseif rule == "hitsWith" then
		return event.kind == "hit" and sameSquishy
	elseif rule == "practiceHit" then
		return event.kind == "practiceHit"
	end
	return false
end

-- Public

function QuestLogic.seed(userId: number, day: number, swapNumber: number?): number
	return userId * SEED_USER_STEP + day % SEED_DAY_MODULUS + SEED_SWAP_STEP * (swapNumber or 0)
end

function QuestLogic.generate(ctx: GenerateContext, newRng: NewRng?): { QuestEntry }
	local rng = makeRng(newRng, QuestLogic.seed(ctx.userId, ctx.day))
	local owned = ownedList(ctx.owned)
	local templates = QuestDefs.daily()
	local chosen: { [string]: boolean } = {}
	local entries: { QuestEntry } = {}
	for slot = 1, Config.Economy.Quests.perDay do
		local category = SLOT_CATEGORY[slot]
		local candidates: { QuestDef } = {}
		for _, def in templates do
			if not chosen[def.id] and (category == nil or def.category == category) then
				table.insert(candidates, def)
			end
		end
		if #candidates == 0 then
			break -- (only with fewer templates than slots; Config.validate prevents it)
		end
		local def = candidates[rng:NextInteger(1, #candidates)]
		chosen[def.id] = true
		table.insert(entries, newEntry(rng, def, questId(ctx.day, slot), owned, ctx.equipped))
	end
	return entries
end

function QuestLogic.swap(
	entries: { QuestEntry },
	id: string,
	ctx: SwapContext,
	newRng: NewRng?
): ({ QuestEntry }?, string?)
	local index: number? = nil
	for i, entry in entries do
		if entry.id == id then
			index = i
			break
		end
	end
	if index == nil then
		return nil, "net.invalid"
	end
	local target = entries[index]
	local def = QuestDefs.get(target.def)
	if def == nil or def.kind ~= "daily" or target.done or target.claimed then
		return nil, "net.invalid"
	end
	local swapNumber = ctx.swapNumber
	if whole(swapNumber) ~= swapNumber or swapNumber < 1 or swapNumber > Config.Economy.Quests.freeSwapsPerDay then
		return nil, "quest.swapUsed"
	end

	local inList: { [string]: boolean } = {}
	for _, entry in entries do
		inList[entry.def] = true
	end
	local otherCategory: { QuestDef } = {}
	local sameCategory: { QuestDef } = {}
	for _, candidate in QuestDefs.daily() do
		if not inList[candidate.id] then
			if candidate.category ~= def.category then
				table.insert(otherCategory, candidate)
			else
				table.insert(sameCategory, candidate)
			end
		end
	end
	local pool = if #otherCategory > 0 then otherCategory else sameCategory
	if #pool == 0 then
		return nil, "net.invalid"
	end

	local rng = makeRng(newRng, QuestLogic.seed(ctx.userId, ctx.day, swapNumber))
	local picked = pool[rng:NextInteger(1, #pool)]
	local result: { QuestEntry } = TableUtil.deepCopy(entries)
	result[index] = newEntry(rng, picked, target.id, ownedList(ctx.owned), ctx.equipped)
	return result, nil
end

function QuestLogic.apply(entries: { QuestEntry }, event: QuestEvent): { QuestProgressLine }
	local lines: { QuestProgressLine } = {}
	for _, entry in entries do
		local def = QuestDefs.get(entry.def)
		if def ~= nil and def.kind == "daily" and not entry.done and not entry.claimed then
			if counts(def, entry.squishy, event) then
				local progress = math.min(entry.goal, whole(entry.progress) + 1)
				local done = progress >= entry.goal
				entry.progress = progress
				entry.done = done
				table.insert(lines, { questId = entry.id, progress = progress, goal = entry.goal, done = done })
			end
		end
	end
	return lines
end

function QuestLogic.applyStarter(starter: StarterState, event: QuestEvent): { string }
	local changed: { string } = {}
	for _, def in QuestDefs.starter() do
		local goal = def.variants[1].goal
		local progress = whole(starter.progress[def.id])
		if starter.claimed[def.id] ~= true and progress < goal and counts(def, nil, event) then
			starter.progress[def.id] = progress + 1
			table.insert(changed, def.id)
		end
	end
	return changed
end

function QuestLogic.starterView(starter: StarterState): { StarterTaskView }
	local rows: { StarterTaskView } = {}
	for _, def in QuestDefs.starter() do
		local variant = def.variants[1]
		local progress = math.min(variant.goal, whole(starter.progress[def.id]))
		table.insert(rows, {
			id = def.id,
			progress = progress,
			goal = variant.goal,
			reward = variant.reward,
			done = progress >= variant.goal,
			claimed = starter.claimed[def.id] == true,
		})
	end
	return rows
end

function QuestLogic.rollover(quests: QuestsState, today: number): Rollover
	if quests.day == today then
		return { autoClaim = {}, regenerate = false }
	end
	local autoClaim: { QuestEntry } = {}
	for _, entry in quests.active do
		if entry.done and not entry.claimed then
			table.insert(autoClaim, entry)
		end
	end
	return { autoClaim = autoClaim, regenerate = true }
end

return table.freeze(QuestLogic)
