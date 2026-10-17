--!strict
-- PenFormat (client only, pure). Pens3 phase 6 (work/pens3/PLAN.md "PHASE 6"): what the stand-in pen screen shows and
-- what a tap on it does, from StateController's `pen` (Types.PenState; every squishy has a slot, 0 = the Toy Box, and a
-- lock). No instances; the server decides every move (PenPlace / PenLock), this only picks what to ask for.
--   view(pen, selectedId, picking) -> View: one card per open spot (its squishy or none, PenMath.placed), the Toy Box
--     best first (PenMath.better), the count line (pen.screen.count) or, while picking, the hint with the squishy's
--     name (pickHint), the line under it (selectHint with nothing selected, toyEmpty for an empty Toy Box), the
--     selected squishy (nil once it is gone: picking stops) and its actions: a pen squishy PUT AWAY (with
--     reason.inventory.full while the Toy Box holds toyBoxMax: the server refuses it then), MOVE, LOCK or UNLOCK; a Toy
--     Box one PLACE while a spot is free (PenMath.freeSlot), else SWAP, and LOCK or UNLOCK; picking only CANCEL.
--   tap(view, slot?, itemId?) -> ("place", itemId, slot) | ("select", itemId) | ("none"): a card's tap (a pen spot
--     card passes its slot and its squishy's id, a Toy Box card its id): while picking, a pen spot asks for the move
--     (an occupied spot swaps, on the server); otherwise a squishy's card selects it; an empty spot does nothing.
--   pickFor(pen, kind) -> id?: the squishy of `kind` the screen opens on from the Squishies window: the best placed
--     one, else the Toy Box's best.
--   walkerItem(pen, index, look) -> id?: the pen squishy a tapped walker shows. PenController's walkers follow
--     BaseService's SD_Pen (PenMath.encode of the placed items, in slot order), so placed[index] when its look matches,
--     else the first placed squishy with that look (copies look the same), else nil.
--   cardText(item) -> {name, rate, level}: a card's name, "+N/s" (Strings pen.rate) and "Lv N" (pen.screen.level;
--     pens3 phase 8: "Golden · Lv N" / "Rainbow · Lv N", pen.screen.formLevel: the stand-in form tag).
-- Pens3 phases 7-8 (selling, the 10-minute buy-back, fusion; the server decides, SellItems / SellAll / BuyBack / Fuse):
--   view(pen, selectedId, picking, extra?) also takes Extra {buyBack (StateController's), now (the server's os.time),
--     coins, soldId (a selected sold card), confirm ("sell" | "sellAll" | "buyBack" | "fuse": the confirm step open)}:
--     - sold: the live buy-back entries (PenMath.liveBuyBack) as cards, newest first, with their price and the minutes
--       left as a plain number (pen.screen.soldTime; no countdown); soldHeading while there is one;
--     - actions: nothing selected -> SELL ALL (reason.pen.nothingToSell when PenMath.sellAllIds is empty); a squishy ->
--       its phase 6 actions, then SELL (the server's refusal as its reason: Kitty Bread, locked, the last copy), then
--       FUSE while fuseSet finds 3; a sold card -> BUY BACK (reason.inventory.full when there is no room, the missing
--       Coins when short); picking stays CANCEL only;
--     - a confirm: the count line asks (confirmSell / confirmSellAll / confirmBuyBack / confirmFuse with the result's
--       name), the hint says the rest (the buy-back minutes; what Sell All keeps; the balance after; the result's level
--       and +N/s, and coatNote when an input is coated), sellIds / fuseIds say what to send (marked: the fuse inputs),
--       and the actions are the confirm (SELL / HOLD TO SELL / SELL ALL / BUY BACK / FUSE; hold = true when a squishy
--       sold needs a hold) and CANCEL. A confirm that cannot open (nothing to sell, no 3 to fuse) is left out.
--   needsHold(item) -> boolean: D1:222's hold-to-confirm (Config.Economy.Pen.sellHold: the form, level or rarity).
--   fuseSet(pen, id) -> {id, a, b}?: the squishy and the two unlocked others of its kind and form worth least (better),
--     nil when it is locked, Rainbow, or there are not 3.
--   holdFraction(startedAt, now) -> 0..1 over Config.UI.Pen.screen.holdSeconds.
--   formName(item) -> string: "Golden Toast" / "Rainbow Toast" (pen.screen.formName), a plain one its name.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local PenMath = require(Shared.PenMath)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

-- Types

export type ActionId =
	"place"
	| "putAway"
	| "move"
	| "swap"
	| "lock"
	| "unlock"
	| "cancel"
	| "sell"
	| "sellAll"
	| "buyBack"
	| "fuse"
	| "confirm"
export type Action = {
	id: ActionId,
	text: string,
	kind: "primary" | "secondary" | "cancel",
	reason: string?,
	hold: boolean?, -- pens3 phase 7: the press must be held (Config.UI.Pen.screen.holdSeconds)
}
export type Spot = { slot: number, item: Types.PenItem? }
export type ConfirmKind = "sell" | "sellAll" | "buyBack" | "fuse"
export type SoldCard = { id: number, item: Types.PenItem, price: number, time: string }
export type Extra = { buyBack: any?, now: number?, coins: number?, soldId: number?, confirm: ConfirmKind? }
export type View = {
	spots: { Spot },
	toys: { Types.PenItem },
	status: string,
	hint: string?,
	selected: Types.PenItem?,
	picking: boolean,
	actions: { Action },
	-- Pens3 phases 7-8.
	sold: { SoldCard },
	soldHeading: string?,
	soldSelected: SoldCard?,
	confirm: ConfirmKind?,
	sellIds: { number }?,
	fuseIds: { number }?,
	marked: { [number]: boolean },
}
export type CardText = { name: string, rate: string, level: string }

-- Constants

local PEN = Config.Economy.Pen
local SCREEN = Strings.pen.screen
local SCREEN_UI = Config.UI.Pen.screen -- pens3 phase 7
local HOLD = PEN.sellHold

-- Module table

local PenFormat = {}

-- Private

local function sameLook(item: any, look: any): boolean
	return item.kind == look.kind and item.form == look.form and item.coat == look.coat
end

local function lockAction(item: Types.PenItem): Action
	if item.locked == true then
		return { id = "unlock", text = SCREEN.unlock, kind = "secondary" }
	end
	return { id = "lock", text = SCREEN.lock, kind = "secondary" }
end

local function actionsFor(pen: any, item: Types.PenItem, placed: boolean, picking: boolean): { Action }
	if picking then
		return { { id = "cancel", text = Strings.common.cancel, kind = "cancel" } }
	end
	if placed then
		local full = #PenMath.toyBox(pen) >= PEN.toyBoxMax
		return {
			{
				id = "putAway",
				text = SCREEN.putAway,
				kind = "primary",
				reason = if full then Strings.reasonText("inventory.full") else nil,
			},
			{ id = "move", text = SCREEN.move, kind = "secondary" },
			lockAction(item),
		}
	end
	if PenMath.freeSlot(pen) > 0 then
		return { { id = "place", text = SCREEN.place, kind = "primary" }, lockAction(item) }
	end
	return { { id = "swap", text = SCREEN.swap, kind = "primary" }, lockAction(item) }
end

-- Public

function PenFormat.cardText(item: Types.PenItem): CardText
	local def = Catalog.get(item.kind)
	local name = if def then Strings.resolve(def.nameKey) or item.kind else item.kind
	local form = SCREEN.forms[item.form] -- pens3 phase 8: Golden / Rainbow
	return {
		name = name,
		rate = Strings.format(Strings.pen.rate, { coins = Format.coins(math.floor(PenMath.itemRate(item))) }),
		level = if form
			then Strings.format(SCREEN.formLevel, { form = form, level = item.level })
			else Strings.format(SCREEN.level, { level = item.level }),
	}
end

-- Pens3 phases 7-8: selling, the buy-back and fusion ----------------------------------------------------------------

function PenFormat.needsHold(item: Types.PenItem): boolean
	local def = Catalog.get(item.kind)
	return item.form >= HOLD.form
		or item.level >= HOLD.level
		or (def ~= nil and Rarity.compare(def.rarity, HOLD.rarity) >= 0)
end

function PenFormat.fuseSet(pen: any, id: number): { number }?
	local chosen = PenMath.find(pen, id)
	if chosen == nil or chosen.locked == true or chosen.form >= #PEN.formMult - 1 then
		return nil
	end
	local others: { Types.PenItem } = {}
	for _, item in (pen :: any).items do
		local same = item ~= chosen and item.kind == chosen.kind and item.form == chosen.form
		if same and item.locked ~= true and PenMath.find(pen, item.id) == item then
			table.insert(others, item)
		end
	end
	if #others < 2 then
		return nil
	end
	table.sort(others, PenMath.better)
	return { chosen.id, others[#others - 1].id, others[#others].id } -- the two worth least go with it
end

function PenFormat.holdFraction(startedAt: number, now: number): number
	return math.clamp((now - startedAt) / SCREEN_UI.holdSeconds, 0, 1)
end

-- The name of a look with its form ("Golden Toast"; a plain one its own name).
function PenFormat.formName(item: any): string
	local name = PenFormat.cardText(item).name
	local form = SCREEN.forms[item.form]
	return if form then Strings.format(SCREEN.formName, { form = form, name = name }) else name
end

-- The live buy-back entries as sold cards, newest first.
local function soldCards(list: any, now: number): { SoldCard }
	local cards: { SoldCard } = {}
	for _, entry in PenMath.liveBuyBack(list, now) do
		local minutes = math.max(1, math.ceil((entry.at + PEN.buyBackSeconds - now) / 60))
		table.insert(cards, 1, {
			id = entry.item.id,
			item = entry.item,
			price = entry.price,
			time = Strings.format(SCREEN.soldTime, { minutes = minutes }),
		})
	end
	return cards
end

local function needCoins(missing: number): string
	local need = Strings.common.needCoins
	return Strings.format(Strings.plural(missing, need.one, need.many), { missing = Format.coins(missing) })
end

-- The confirm step (see the header): its question, note, ids and actions; false when it cannot open.
local function confirmView(view: View, pen: any, extra: Extra, coins: number): boolean
	local kind = extra.confirm
	local minutes = math.ceil(PEN.buyBackSeconds / 60)
	local text, hold = "", false
	if kind == "sell" or kind == "sellAll" then
		local ids = if kind == "sellAll"
			then PenMath.sellAllIds(pen)
			elseif view.selected then { view.selected.id }
			else {}
		local sale = if #ids > 0 then PenMath.sellDecision(pen, ids) else nil
		if sale == nil then
			return false
		end
		for _, item in sale.items do
			hold = hold or PenFormat.needsHold(item)
		end
		view.sellIds = ids
		if kind == "sell" then
			view.status = Strings.format(
				SCREEN.confirmSell,
				{ name = PenFormat.cardText(sale.items[1]).name, coins = Format.coins(sale.coins) }
			)
			view.hint = Strings.format(SCREEN.sellNote, { minutes = minutes })
		else
			local all = SCREEN.confirmSellAll
			view.status =
				Strings.format(Strings.plural(#ids, all.one, all.many), { n = #ids, coins = Format.coins(sale.coins) })
			view.hint = Strings.format(SCREEN.sellAllNote, { minutes = minutes })
		end
		text = if hold then SCREEN.holdSell elseif kind == "sellAll" then SCREEN.sellAll else SCREEN.sell
	elseif kind == "buyBack" then
		local card = view.soldSelected
		if card == nil then
			return false
		end
		view.status = Strings.format(
			SCREEN.confirmBuyBack,
			{ name = PenFormat.cardText(card.item).name, coins = Format.coins(card.price) }
		)
		view.hint =
			Strings.format(Strings.spend.balanceAfter, { balance = Format.coins(math.max(0, coins - card.price)) })
		text = SCREEN.buyBack
	elseif kind == "fuse" then
		local ids = if view.selected then PenFormat.fuseSet(pen, view.selected.id) else nil
		local fusion = if ids then PenMath.fuseDecision(pen, ids) else nil
		if ids == nil or fusion == nil then
			return false
		end
		local result = table.clone(fusion.keeper)
		result.form, result.coat = fusion.form, 0
		view.fuseIds = ids
		for _, id in ids do
			view.marked[id] = true
		end
		view.status = Strings.format(
			SCREEN.confirmFuse,
			{ name = PenFormat.cardText(result).name, result = PenFormat.formName(result) }
		)
		view.hint = Strings.format(SCREEN.fuseNote, { level = fusion.level, rate = PenFormat.cardText(result).rate })
			.. (if #fusion.coats > 0 then " " .. SCREEN.coatNote else "")
		text = SCREEN.fuse
	else
		return false
	end
	view.confirm = extra.confirm
	view.actions = {
		{ id = "confirm", text = text, kind = "primary", hold = if hold then true else nil },
		{ id = "cancel", text = Strings.common.cancel, kind = "cancel" },
	}
	return true
end

function PenFormat.view(pen: any, selectedId: number?, picking: boolean, extra: Extra?): View
	local more: Extra = extra or {}
	local placed = PenMath.placed(pen)
	local toys = PenMath.toyBox(pen)
	table.sort(toys, PenMath.better)
	local bySlot: { [number]: Types.PenItem } = {}
	for _, item in placed do
		bySlot[item.slot] = item
	end
	local spots: { Spot } = {}
	-- A pen that is not broken has a placed squishy or a free spot (both PenMath fail closed on a broken one).
	local open = if #placed > 0 or PenMath.freeSlot(pen) > 0 then pen.spots else 0
	for slot = 1, open do
		table.insert(spots, { slot = slot, item = bySlot[slot] })
	end
	local selected = if selectedId ~= nil then PenMath.find(pen, selectedId) else nil
	local isPlaced = selected ~= nil and bySlot[selected.slot] == selected
	local isToy = selected ~= nil and table.find(toys, selected) ~= nil
	if not (isPlaced or isToy) then
		selected = nil -- gone, or nowhere the screen shows
	end
	local pickingNow = picking and selected ~= nil
	local view: View = {
		spots = spots,
		toys = toys,
		status = Strings.format(SCREEN.count, { placed = #placed, spots = open, toys = #toys, max = PEN.toyBoxMax }),
		hint = if #toys == 0 and open > 0 then SCREEN.toyEmpty elseif selected == nil then SCREEN.selectHint else nil,
		selected = selected,
		picking = pickingNow,
		actions = {},
		sold = soldCards(more.buyBack, more.now or 0),
		marked = {},
	}
	view.soldHeading = if #view.sold > 0 then SCREEN.soldHeading else nil
	for _, card in view.sold do
		if selected == nil and card.id == more.soldId then
			view.soldSelected = card
		end
	end
	local coins = more.coins or 0
	if selected ~= nil then
		view.actions = actionsFor(pen, selected, isPlaced, pickingNow)
		if pickingNow then
			view.status = Strings.format(SCREEN.pickHint, { name = PenFormat.cardText(selected).name })
		else
			local _, refused = PenMath.sellDecision(pen, { selected.id })
			local reason = if refused then Strings.reasonText(refused) else nil
			table.insert(view.actions, { id = "sell", text = SCREEN.sell, kind = "secondary", reason = reason })
			if PenFormat.fuseSet(pen, selected.id) then
				table.insert(view.actions, { id = "fuse", text = SCREEN.fuse, kind = "secondary" })
			end
		end
	elseif view.soldSelected ~= nil then
		local price = view.soldSelected.price
		local reason = if PenMath.room(pen) <= 0
			then Strings.reasonText("inventory.full")
			elseif coins < price then needCoins(price - coins)
			else nil
		view.actions = { { id = "buyBack", text = SCREEN.buyBack, kind = "primary", reason = reason } }
	else
		local none = #PenMath.sellAllIds(pen) == 0
		view.actions = {
			{
				id = "sellAll",
				text = SCREEN.sellAll,
				kind = "secondary",
				reason = if none then Strings.reasonText("pen.nothingToSell") else nil,
			},
		}
	end
	if more.confirm ~= nil and not pickingNow then
		confirmView(view, pen, more, coins)
	end
	return view
end

function PenFormat.tap(view: View, slot: number?, itemId: number?): (string, number?, number?)
	local selected = view.selected
	if view.picking and selected ~= nil and slot ~= nil then
		return "place", selected.id, slot
	end
	if itemId ~= nil then
		return "select", itemId
	end
	return "none"
end

function PenFormat.pickFor(pen: any, kind: string): number?
	local best: Types.PenItem? = nil
	for _, item in PenMath.placed(pen) do
		if item.kind == kind and (best == nil or PenMath.better(item, best)) then
			best = item
		end
	end
	if best == nil then
		for _, item in PenMath.toyBox(pen) do
			if item.kind == kind and (best == nil or PenMath.better(item, best)) then
				best = item
			end
		end
	end
	return if best then best.id else nil
end

function PenFormat.walkerItem(pen: any, index: number, look: any): number?
	local placed = PenMath.placed(pen)
	local at = placed[index]
	if at ~= nil and sameLook(at, look) then
		return at.id
	end
	for _, item in placed do
		if sameLook(item, look) then
			return item.id
		end
	end
	return nil
end

return table.freeze(PenFormat)
