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
--   cardText(item) -> {name, rate, level}: a card's name, "+N/s" (Strings pen.rate) and "Lv N" (pen.screen.level).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

-- Types

export type ActionId = "place" | "putAway" | "move" | "swap" | "lock" | "unlock" | "cancel"
export type Action = { id: ActionId, text: string, kind: "primary" | "secondary" | "cancel", reason: string? }
export type Spot = { slot: number, item: Types.PenItem? }
export type View = {
	spots: { Spot },
	toys: { Types.PenItem },
	status: string,
	hint: string?,
	selected: Types.PenItem?,
	picking: boolean,
	actions: { Action },
}
export type CardText = { name: string, rate: string, level: string }

-- Constants

local PEN = Config.Economy.Pen
local SCREEN = Strings.pen.screen

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
	return {
		name = name,
		rate = Strings.format(Strings.pen.rate, { coins = Format.coins(math.floor(PenMath.itemRate(item))) }),
		level = Strings.format(SCREEN.level, { level = item.level }),
	}
end

function PenFormat.view(pen: any, selectedId: number?, picking: boolean): View
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
	}
	if selected ~= nil then
		view.actions = actionsFor(pen, selected, isPlaced, pickingNow)
		if pickingNow then
			view.status = Strings.format(SCREEN.pickHint, { name = PenFormat.cardText(selected).name })
		end
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
