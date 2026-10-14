--!strict
-- QuestFormat (client only, pure). DESIGN §6.8 (quests and starter tasks), §11.6 (Quests screen), §11.3 (states), §11.6
-- result panel (quest lines). What the quest board shows, as plain data. The server owns progress, claims and swaps
-- (QuestService); this module only displays the `quests` state (Types.QuestsView: the day's quests + the starter tasks).
--   board(quests, ctx)    the Daily section (one card per active quest) and the Starter section (one card per
--                         QuestDefs starter task), the swaps left, the footer "New quests in {h}h {m}m" and the empty
--                         sentence "No quests right now. Check back in {time}." when the day has no quest
--   dailyCard(entry, ctx, swapsLeft) / starterCards(starter, capsules?)   single cards (see Card)
--   swapsLeft(quests)     Config.Economy.Quests.freeSwapsPerDay - quests.swapsUsed, never below 0
--   footer(now) / emptyText(now)   the two time lines (server time; the next quest day starts at 00:00 UTC)
--   titleOf(entry)        a daily quest's line from QuestDefs.text (goal and squishy name filled in)
--   namer(quests)         (questId) -> the quest's line or nil, for DuelFormat.result's quest lines
--   starterClaimable(quests)   starter tasks done and not claimed (HudController adds them to the Quests badge, which
--                         counts the daily quests through HudFormat.questBadge)
--   bodyHeight(screenH, contentH, chromeH, maxShare, minH)   Part 8 (§11.2): the scrolling sections' height (base
--                         px): the content's, capped so the whole panel (body + chrome: header, footer, paddings)
--                         stays within maxShare of the screen height; never under minH (unit-tested at 667×375,
--                         1280×720, 1920×1080 and the largest text)
--   topWins(view)         Batch 3 (review #10): "Top Wins This Week" from the topWins state (Types.TopWinsView): the
--                         ranked lines "1. Ana · 12 wins", a note ("Checking the board…" before the first read, "The
--                         board is taking a break…" while no read works, the empty week's "No wins yet this week. Be
--                         the first!" alone) and the player's own line (place and wins, their week's wins outside the
--                         read, or how to get on the board)
-- A card: the title, the progress "3/5" (common.progress) with its bar fill, the reward "+1,500 Coins"
-- (common.coinsGain), the state In progress / Claim / Claimed, Swap and the Equip shortcut. Phase 5 (progression spec
-- 2026-10-12 §9): the reward is the quest's squeezes × the squeeze value of ctx.capsules (the player's capsules state;
-- CapsuleMath.rewardCoins, the Coins the server pays at claim time), and Card.reward is those Coins.
-- Readings: Swap shows on every unfinished daily quest while a free swap is left (one swap a day, on any one of them;
-- §11.6 "Swap on one unfinished daily quest per day"); a starter task never swaps. The Equip shortcut shows while
-- the quest is unfinished and its squishy is owned but not equipped. The Starter section hides once every starter task
-- is claimed. A daily entry whose template is unknown (a newer server) is left out. Progress is shown clamped to
-- 0..goal.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local QuestDefs = require(Shared.QuestDefs)
local Strings = require(Shared.Strings)
local TimeUtil = require(Shared.Util.TimeUtil)

-- Types

export type CardKind = "daily" | "starter"
export type CardState = "inProgress" | "claim" | "claimed"

export type Card = {
	id: string, -- the questId: "q<day>_<slot>" or "starter_<name>"
	kind: CardKind,
	title: string,
	progress: number, -- clamped to 0..goal
	goal: number,
	fraction: number, -- 0..1, the progress bar fill
	progressText: string, -- "3/5"
	reward: number, -- Coins (the quest's squeezes × the squeeze value)
	rewardText: string, -- "+1,500 Coins"
	state: CardState,
	stateText: string, -- quest.inProgress / common.claim / common.claimed
	canSwap: boolean,
	equipSquishy: string?, -- the Equip shortcut's squishy (owned, not equipped), or nil
}

export type Context = {
	owned: { [string]: any }?, -- profile.owned (squishyId -> entry)
	equipped: string?,
	now: number, -- server time (workspace:GetServerTimeNow())
	capsules: any?, -- the `capsules` state field (the squeeze value of the rewards); nil = a new player's
}

export type Board = {
	daily: { Card },
	starter: { Card },
	starterVisible: boolean, -- false once every starter task is claimed
	swapsLeft: number,
	footer: string,
	empty: string?, -- the empty sentence when the day has no quest
}

-- Batch 3: what the Quests screen's "Top Wins This Week" section shows.
export type TopWins = { lines: { string }, note: string?, you: string? }

-- Constants

local QUESTS = Config.Economy.Quests
local DAILY_KIND: CardKind = "daily"
local STARTER_KIND: CardKind = "starter"

-- Module table

local QuestFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function whole(n: unknown, fallback: number): number
	return if finite(n) then math.floor(n :: number) else fallback
end

local function squishyName(id: unknown): string?
	if type(id) ~= "string" then
		return nil
	end
	local def = Catalog.get(id)
	if def == nil then
		return nil
	end
	return Strings.resolve(def.nameKey) or def.id
end

local function stateOf(done: boolean, claimed: boolean): CardState
	if claimed then
		return "claimed"
	elseif done then
		return "claim"
	end
	return "inProgress"
end

local function stateTextOf(state: CardState): string
	if state == "claimed" then
		return Strings.common.claimed
	elseif state == "claim" then
		return Strings.common.claim
	end
	return Strings.quest.inProgress
end

local function card(
	id: string,
	kind: CardKind,
	title: string,
	progress: number,
	goal: number,
	reward: number,
	done: boolean,
	claimed: boolean
): Card
	local safeGoal = math.max(1, goal)
	local shown = math.clamp(progress, 0, safeGoal)
	local state: CardState = stateOf(done, claimed)
	return {
		id = id,
		kind = kind,
		title = title,
		progress = shown,
		goal = safeGoal,
		fraction = shown / safeGoal,
		progressText = Strings.format(Strings.common.progress, { progress = shown, goal = safeGoal }),
		reward = reward,
		rewardText = Strings.format(Strings.common.coinsGain, { coins = Format.coins(reward) }),
		state = state,
		stateText = stateTextOf(state),
		canSwap = false,
		equipSquishy = nil,
	}
end

local function untilNextDay(now: number): number
	return if finite(now) then TimeUtil.secondsUntilNextUtcDay(now) else 0
end

-- Public

function QuestFormat.swapsLeft(quests: unknown): number
	local used = if type(quests) == "table" then whole((quests :: any).swapsUsed, 0) else 0
	return math.max(0, QUESTS.freeSwapsPerDay - math.max(0, used))
end

-- "New quests in {h}h {m}m" until the next 00:00 UTC.
function QuestFormat.footer(now: number): string
	local hours, minutes = TimeUtil.splitDuration(untilNextDay(now))
	return Strings.format(Strings.quest.footer, { h = hours, m = minutes })
end

-- "No quests right now. Check back in {time}." ({time} = the countdown to the next 00:00 UTC).
function QuestFormat.emptyText(now: number): string
	return Strings.format(Strings.quest.empty, { time = TimeUtil.formatCountdown(untilNextDay(now)) })
end

-- A daily quest's line ("Squeeze Toast 60 times"), or nil for an unknown template.
function QuestFormat.titleOf(entry: unknown): string?
	if type(entry) ~= "table" then
		return nil
	end
	local e = entry :: any
	if QuestDefs.get(e.def) == nil or not finite(e.goal) then
		return nil
	end
	local text = QuestDefs.text(e.def, math.floor(e.goal), squishyName(e.squishy))
	return if text ~= "" then text else nil
end

function QuestFormat.dailyCard(entry: unknown, ctx: Context, swapsLeft: number): Card?
	if type(entry) ~= "table" then
		return nil
	end
	local e = entry :: any
	local title = QuestFormat.titleOf(e)
	if title == nil or type(e.id) ~= "string" then
		return nil
	end
	local claimed = e.claimed == true
	local done = e.done == true or claimed
	local reward = CapsuleMath.rewardCoins(whole(e.reward, 0), CapsuleMath.squeezeValue(ctx.capsules))
	local result = card(e.id, DAILY_KIND, title, whole(e.progress, 0), whole(e.goal, 1), reward, done, claimed)
	result.canSwap = not done and swapsLeft > 0
	local id = e.squishy
	if not done and type(id) == "string" and ctx.owned and ctx.owned[id] ~= nil and ctx.equipped ~= id then
		result.equipSquishy = id
	end
	return result
end

-- One card per QuestDefs starter task, from profile.starter {progress, claimed}; rewards at `capsules`' squeeze value.
function QuestFormat.starterCards(starter: unknown, capsules: any?): { Card }
	local value = CapsuleMath.squeezeValue(capsules)
	local progressMap = if type(starter) == "table" and type((starter :: any).progress) == "table"
		then (starter :: any).progress
		else {}
	local claimedMap = if type(starter) == "table" and type((starter :: any).claimed) == "table"
		then (starter :: any).claimed
		else {}
	local cards: { Card } = {}
	for _, def in QuestDefs.starter() do
		local variant = def.variants[1]
		if variant then
			local progress = whole(progressMap[def.id], 0)
			local claimed = claimedMap[def.id] == true
			local done = claimed or progress >= variant.goal
			local title = QuestDefs.text(def.id, variant.goal)
			local reward = CapsuleMath.rewardCoins(variant.reward, value)
			table.insert(cards, card(def.id, STARTER_KIND, title, progress, variant.goal, reward, done, claimed))
		end
	end
	return cards
end

-- Starter tasks ready to claim (done, not claimed).
function QuestFormat.starterClaimable(quests: unknown): number
	local n = 0
	for _, c in QuestFormat.starterCards(if type(quests) == "table" then (quests :: any).starter else nil) do
		if c.state == "claim" then
			n += 1
		end
	end
	return n
end

function QuestFormat.board(quests: unknown, ctx: Context): Board
	local swaps = QuestFormat.swapsLeft(quests)
	local daily: { Card } = {}
	local active = if type(quests) == "table" then (quests :: any).active else nil
	if type(active) == "table" then
		for _, entry in active do
			local made = QuestFormat.dailyCard(entry, ctx, swaps)
			if made then
				table.insert(daily, made)
			end
		end
	end
	local starter =
		QuestFormat.starterCards(if type(quests) == "table" then (quests :: any).starter else nil, ctx.capsules)
	local starterVisible = false
	for _, c in starter do
		if c.state ~= "claimed" then
			starterVisible = true
			break
		end
	end
	return {
		daily = daily,
		starter = starter,
		starterVisible = starterVisible,
		swapsLeft = swaps,
		footer = QuestFormat.footer(ctx.now),
		empty = if #daily == 0 then QuestFormat.emptyText(ctx.now) else nil,
	}
end

-- The Quests panel's scrolling body (Part 8): its content's height, capped so the panel stays within `maxShare` of
-- the screen; `chromeHeight` is the rest of the panel (header, footer, gaps, paddings), measured by the caller.
function QuestFormat.bodyHeight(
	screenHeight: number,
	contentHeight: number,
	chromeHeight: number,
	maxShare: number,
	minHeight: number
): number
	local room = (if finite(screenHeight) then screenHeight else 0) * maxShare
		- (if finite(chromeHeight) then chromeHeight else 0)
	local content = if finite(contentHeight) then math.max(0, contentHeight) else 0
	return math.max(minHeight, math.min(content, room))
end

-- For DuelFormat.result: the line of a daily quest (from the quests state) or a starter task, else nil.
function QuestFormat.namer(quests: unknown): (questId: string) -> string?
	local active = if type(quests) == "table" and type((quests :: any).active) == "table"
		then (quests :: any).active
		else {}
	return function(questId: string): string?
		if type(questId) ~= "string" then
			return nil
		end
		for _, entry in active do
			if type(entry) == "table" and entry.id == questId then
				return QuestFormat.titleOf(entry)
			end
		end
		local def = QuestDefs.get(questId)
		if def and def.kind == STARTER_KIND and def.variants[1] then
			local text = QuestDefs.text(def.id, def.variants[1].goal)
			return if text ~= "" then text else nil
		end
		return nil
	end
end

-- Batch 3: the "Top Wins This Week" section from the topWins state (see the header). A broken entry is left out.
function QuestFormat.topWins(view: unknown): TopWins
	local v: any = view
	if type(v) ~= "table" or v.loaded ~= true or type(v.top) ~= "table" then
		return { lines = {}, note = Strings.board.loading }
	end
	local board = Strings.board
	if v.unavailable == true then
		return { lines = {}, note = board.unavailable }
	end
	local lines: { string } = {}
	for _, entry in v.top do
		if type(entry) == "table" and type(entry.name) == "string" and type(entry.wins) == "number" then
			local args = { rank = #lines + 1, name = entry.name, wins = Format.coins(entry.wins) }
			table.insert(lines, Strings.format(Strings.plural(entry.wins, board.line.one, board.line.many), args))
		end
	end
	local wins = if type(v.wins) == "number" then v.wins else 0
	if #lines == 0 and wins == 0 then
		return { lines = lines, note = board.empty } -- the empty week's note says it all
	end
	local you: string
	if type(v.place) == "number" then
		local text = Strings.plural(wins, board.you.one, board.you.many)
		you = Strings.format(text, { rank = v.place, n = Format.coins(wins) })
	elseif wins > 0 then
		you = Strings.format(
			Strings.plural(wins, board.youUnranked.one, board.youUnranked.many),
			{ n = Format.coins(wins) }
		)
	else
		you = board.youNone
	end
	return { lines = lines, note = if #lines == 0 then board.empty else nil, you = you }
end

return QuestFormat
