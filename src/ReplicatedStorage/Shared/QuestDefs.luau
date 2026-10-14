--!strict
-- QuestDefs: the 7 daily quest templates and the 3 starter tasks (DESIGN §6.8). Shared (server
-- Logic/QuestLogic and QuestService, client QuestController / UI/QuestFormat, DataService's stored-quest check). Data
-- only plus pure lookups; no instances, no yields. All numbers are [P].
--
-- Fields:
--   id            daily template id (`squeeze_any`, ...; a QuestEntry's `def`) or starter task id (`starter_<name>`,
--                 the key of profile.starter.progress / claimed and the QuestClaim questId)
--   kind          "daily" | "starter"
--   category      "squeeze" | "duel" | "practice": slot 1 of the day is a squeeze template, slot 2 a duel template,
--                 slot 3 any template not already chosen; a swap prefers another category (§6.8)
--   counts        what advances it (Logic/QuestLogic): "squeeze" accepted squeezes (paid or not); "squeezeWith" the
--                 same with the quest's squishy equipped; "duelFinish" a match reaching Result (win, loss or draw) with
--                 >= Economy.DuelRewards.minOwnThrows own throws; "duelWin" / "duelWinWith" such a match won (with the
--                 quest's squishy); "hitsWith" a server-confirmed hit on the opponent with the quest's squishy;
--                 "practiceHit" a server-confirmed practice target hit (each target at most once per 2 s). Cancelled,
--                 Void and practice never count for duel templates.
--   needsSquishy  the quest names a squishy ({squishy} in its text): equipped with Economy.Quests.equippedPickChance
--                 if owned, else uniform from the sorted owned list
--   variants      { {goal, reward} }: one is drawn per quest (a starter task has exactly one). The reward is counted
--                 in squeezes (spec 2026-10-12 §9: the same numbers); QuestService pays reward × the player's squeeze
--                 value Coins (CapsuleMath.rewardCoins) when it is claimed.
--   textPair      Strings path of a { one, many } pair (`quest.template.squeezeAny`, `quest.starterTask.duel`)
-- Build plan Phase 6 removed starter_jelly (squeezes on the Jelly Pad, gone with the giant pads) and its `minTier`; an
-- old save's starter.progress / claimed entry for it is an unknown task nothing reads.
--
-- API:
--   QuestDefs.get(defId)                     -> QuestDef? (daily template or starter task)
--   QuestDefs.list()                         -> { QuestDef }: the daily templates, then the starter tasks
--   QuestDefs.daily()                        -> { QuestDef }: the daily templates in table order
--   QuestDefs.starter()                      -> { QuestDef }: the starter tasks in table order
--   QuestDefs.text(defId, goal, squishyName?) -> the quest line: Strings.plural(goal, one, many) formatted with
--                                               {n} = goal and {squishy} = squishyName ("" for an unknown defId)
--
-- Readings:
--   * The plural pair is named by `textPair`, not by a "...Key" field: Config.validate resolves every "...Key" field
--     to a plain string, and a pair is a table. Config.validate checks `.one` and `.many` resolve instead.

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Strings = require(script.Parent.Strings)

-- Types

export type Kind = "daily" | "starter"
export type Category = "squeeze" | "duel" | "practice"
export type Counts = "squeeze" | "squeezeWith" | "duelFinish" | "duelWin" | "duelWinWith" | "hitsWith" | "practiceHit"
export type Variant = { goal: number, reward: number }

export type QuestDef = {
	id: string,
	kind: Kind,
	category: Category,
	counts: Counts,
	needsSquishy: boolean,
	variants: { Variant },
	textPair: string,
}

-- Constants

local function v(goal: number, reward: number): Variant
	return { goal = goal, reward = reward }
end

-- §6.8 daily templates, in table order.
local DAILY: { QuestDef } = {
	{
		id = "squeeze_any",
		kind = "daily",
		category = "squeeze",
		counts = "squeeze",
		needsSquishy = false,
		variants = { v(100, 150), v(150, 200) },
		textPair = "quest.template.squeezeAny",
	},
	{
		id = "squeeze_with",
		kind = "daily",
		category = "squeeze",
		counts = "squeezeWith",
		needsSquishy = true,
		variants = { v(60, 200) },
		textPair = "quest.template.squeezeWith",
	},
	{
		id = "duel_finish",
		kind = "daily",
		category = "duel",
		counts = "duelFinish",
		needsSquishy = false,
		variants = { v(2, 200), v(3, 300) },
		textPair = "quest.template.duelFinish",
	},
	{
		id = "duel_win",
		kind = "daily",
		category = "duel",
		counts = "duelWin",
		needsSquishy = false,
		variants = { v(1, 250), v(2, 400) },
		textPair = "quest.template.duelWin",
	},
	{
		id = "duel_win_with",
		kind = "daily",
		category = "duel",
		counts = "duelWinWith",
		needsSquishy = true,
		variants = { v(1, 300), v(2, 450) },
		textPair = "quest.template.duelWinWith",
	},
	{
		id = "hits_with",
		kind = "daily",
		category = "duel",
		counts = "hitsWith",
		needsSquishy = true,
		variants = { v(8, 250), v(12, 300) },
		textPair = "quest.template.hitsWith",
	},
	{
		id = "practice_hits",
		kind = "daily",
		category = "practice",
		counts = "practiceHit",
		needsSquishy = false,
		variants = { v(20, 100) },
		textPair = "quest.template.practiceHits",
	},
}

-- §6.8 starter tasks (once per account).
local STARTER: { QuestDef } = {
	{
		id = "starter_squeeze",
		kind = "starter",
		category = "squeeze",
		counts = "squeeze",
		needsSquishy = false,
		variants = { v(20, 100) },
		textPair = "quest.starterTask.squeeze",
	},
	{
		id = "starter_practice",
		kind = "starter",
		category = "practice",
		counts = "practiceHit",
		needsSquishy = false,
		variants = { v(5, 50) },
		textPair = "quest.starterTask.practice",
	},
	{
		id = "starter_duel",
		kind = "starter",
		category = "duel",
		counts = "duelFinish",
		needsSquishy = false,
		variants = { v(1, 150) },
		textPair = "quest.starterTask.duel",
	},
}

local BY_ID: { [string]: QuestDef } = {}
for _, list in { DAILY, STARTER } do
	for _, def in list do
		BY_ID[def.id] = def
		for _, variant in def.variants do
			table.freeze(variant)
		end
		table.freeze(def.variants)
		table.freeze(def)
	end
	table.freeze(list)
end
table.freeze(BY_ID)

-- Module table

local QuestDefs = {}

-- Public

function QuestDefs.get(defId: unknown): QuestDef?
	if type(defId) ~= "string" then
		return nil
	end
	return BY_ID[defId]
end

function QuestDefs.list(): { QuestDef }
	local all = table.clone(DAILY)
	for _, def in STARTER do
		table.insert(all, def)
	end
	return all
end

function QuestDefs.daily(): { QuestDef }
	return table.clone(DAILY)
end

function QuestDefs.starter(): { QuestDef }
	return table.clone(STARTER)
end

function QuestDefs.text(defId: string, goal: number, squishyName: string?): string
	local def = QuestDefs.get(defId)
	if def == nil then
		return ""
	end
	local one = Strings.resolve(def.textPair .. ".one")
	local many = Strings.resolve(def.textPair .. ".many")
	if one == nil or many == nil then
		return ""
	end
	return Strings.format(Strings.plural(goal, one, many), { n = goal, squishy = squishyName })
end

return table.freeze(QuestDefs)
