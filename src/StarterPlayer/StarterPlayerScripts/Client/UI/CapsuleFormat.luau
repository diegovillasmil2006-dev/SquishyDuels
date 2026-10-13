--!strict
-- CapsuleFormat (client only, pure). Lobby bases spec 2026-10-11 §5.3, §9; progression spec 2026-10-12 §3-§7; build plan
-- Phase 5. What the capsule card (Controllers/CapsuleController) shows, as plain data: every number from CapsuleMath
-- (the server's own maths) through Format.coins, every text from Strings. The server decides every buy and swap.
--   card(input)                      the card of one slot (Card): an open capsule shows its squishy ("Tap to swap" for the
--                                    owner), "{tier} · Lv {level}", the squeeze time now -> next (only when the next level
--                                    is faster: an evolve), Coins/h and Grip/h now -> next (nothing next at the top), and
--                                    one button: Upgrade, or Evolve at a tier's last level (10, 20 .. 90) with the next
--                                    tier's look and its Grip gate; an empty capsule asks for a squishy; a locked slot shows
--                                    "Locked" and "Unlock · {price}". The button's state, the first that applies: the top
--                                    level (max), a capsule remote running (pending), the next level's Grip gate
--                                    (gripLocked) or an earlier slot still locked (notNext), paused (profile loading /
--                                    offline / read-only / a save pending, the server's own pauses), not enough Coins
--                                    (needCoins, the missing amount), else ready. A visitor (own = false) sees the card
--                                    read-only: "Only {name} can upgrade this.", no button, no swap.
--   popTexts(own, squeezes, capsule) the owner's "+N Coins" and "+N Grip" for `squeezes` squeezes of a capsule (Coins =
--                                    capsuleCoins, Grip = power); nil for a visitor (they see the squash and a sparkle),
--                                    an empty capsule or no squeeze
--   swapList(owned, capsules, slot)  the owned squishies for the swap list, the strongest first (power, then name), each
--                                    with its "x{n} power": the one in this capsule marked `here`, one in another capsule
--                                    noted "In capsule N" (a set moves it, spec 2026-10-12 §6)
--   cardWidth(screenX, scale)        the card's width in base px: Config.UI.Capsule.cardWidth, narrower only to keep
--                                    cardMargin to the screen's sides (Layout.modalWidth)
-- Readings: per hour = whole Coins (or Grip) of 3600 / seconds squeezes; seconds with one decimal; the paused reasons
-- are the removed trainer card's (common.loading, reason.data.offline / data.readOnly) with reason.capsule.paused for a
-- pending save; the Grip level of the player defaults to 1 (a new player's) when unknown.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Layout = require(script.Parent.Layout)

-- Types

export type Input = {
	slot: number,
	capsules: any?, -- {slots, list}: the owner's StateController field, or a visitor's read from the base
	own: boolean,
	ownerName: string?, -- the base owner's display name (the visitor line)
	coins: number?,
	gripLevel: number?,
	status: Types.DataStatus?,
	pending: boolean?, -- a capsule remote is running
}

export type CardState = "ready" | "needCoins" | "gripLocked" | "notNext" | "paused" | "pending" | "max" | "visitor"
export type Action = "upgrade" | "evolve" | "unlock"

export type Card = {
	slot: number,
	title: string,
	locked: boolean,
	lockedText: string?,
	squishyId: string?,
	squishyName: string?,
	swapText: string?,
	emptyText: string?,
	tierText: string?,
	evolveText: string?,
	speedText: string?,
	coinsText: string?,
	gripText: string?,
	action: Action?,
	price: number, -- Coins of the action (0 without one)
	buttonText: string?,
	state: CardState,
	reason: string?, -- why the button is disabled (gripLocked, notNext, paused, needCoins)
	missing: number, -- Coins still missing (needCoins; else 0)
	maxText: string?,
	visitorText: string?,
}

export type SwapEntry = { id: string, name: string, power: string, note: string?, here: boolean }

-- Constants

local CAPSULE = Config.Grip.Capsule
local CARD = Config.UI.Capsule
local S: { [string]: any } = Strings.capsule :: any

-- Module table

local CapsuleFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function nameOf(id: string): string
	local def = Catalog.get(id)
	return if def then Strings.resolve(def.nameKey) or id else id
end

local function tierName(level: number): string
	local key = CAPSULE.Tiers[CapsuleMath.tier(level) :: number].key
	return Strings.resolve("capsule.tier." .. key) or key
end

local function seconds(level: number): string
	return string.format("%.1f", CapsuleMath.seconds(level) :: number)
end

-- Whole Coins (or Grip) an hour of `amount` a squeeze at `level`'s speed.
local function perHour(amount: number, level: number): string
	return Format.coins(math.floor(amount * 3600 / (CapsuleMath.seconds(level) :: number)))
end

-- "Now" or "now -> next" (the next value only when there is a next level).
local function nowNext(key: string, field: string, now: string, next: string?): string
	return Strings.format(S[if next then key .. "Next" else key], { [field] = now, next = next })
end

-- Why nothing can be bought right now whatever the Coins (the server pauses the same), or nil.
local function pausedReason(status: Types.DataStatus?): string?
	if type(status) ~= "table" then
		return nil
	elseif status.status == "loading" then
		return Strings.common.loading
	elseif status.status == "offline" then
		return Strings.reasonText("data.offline")
	elseif status.status == "readonly" then
		return Strings.reasonText("data.readOnly")
	elseif status.savePending == true then
		return Strings.reasonText("capsule.paused")
	end
	return nil
end

-- needCoins, paused or ready for an owner's buy of `card.price` (after the gates).
local function spendState(card: Card, input: Input)
	local paused = pausedReason(input.status)
	local coins = if finite(input.coins) then math.max(0, math.floor(input.coins :: number)) else 0
	if paused then
		card.state, card.reason = "paused", paused
	elseif coins < card.price then
		card.missing = card.price - coins
		local needs = Strings.common.needCoins
		card.state = "needCoins"
		card.reason = Strings.format(Strings.plural(card.missing, needs.one, needs.many), {
			missing = Format.coins(card.missing),
		})
	end
end

-- Public

function CapsuleFormat.card(input: Input): Card
	local slot = input.slot
	local capsules = input.capsules
	local list = if type(capsules) == "table" and type(capsules.list) == "table" then capsules.list else {}
	local slots = if type(capsules) == "table" and finite(capsules.slots) then capsules.slots else 1
	local entry = if slot <= slots then list[slot] else nil
	local card: Card = {
		slot = slot,
		title = Strings.format(S.title, { slot = slot }),
		locked = false,
		price = 0,
		state = "ready",
		missing = 0,
		visitorText = if input.own then nil else Strings.format(S.visitor, { name = input.ownerName or "" }),
	}
	local level = if type(entry) == "table" then entry.level else nil
	if CapsuleMath.tier(level) == nil then
		card.locked = true
		card.lockedText = S.locked
		card.price = CapsuleMath.slotPrice(slot) or 0
		if not input.own then
			card.state = "visitor"
			return card
		end
		card.action = "unlock"
		card.buttonText = Strings.format(Strings.base.unlockPrice, { coins = Format.coins(card.price) })
		if input.pending then
			card.state = "pending"
		elseif slot > slots + 1 then
			card.state, card.reason = "notNext", Strings.format(S.unlockFirst, { slot = slots + 1 })
		else
			spendState(card, input)
		end
		return card
	end
	local now = level :: number
	local nextLevel = if now < CAPSULE.maxLevel then now + 1 else nil
	local squishy = if Catalog.isValidId(entry.squishyId) then entry.squishyId :: string else nil
	card.squishyId = squishy
	card.squishyName = if squishy then nameOf(squishy) else nil
	card.swapText = if input.own then S.swap else nil
	card.tierText = Strings.format(S.tierLevel, { tier = tierName(now), level = now })
	local nextSeconds = if nextLevel and seconds(nextLevel) ~= seconds(now) then seconds(nextLevel) else nil
	card.speedText = Strings.format(S[if nextSeconds then "speedNext" else "speed"], {
		seconds = seconds(now),
		next = nextSeconds,
	})
	if squishy then
		local coins = CapsuleMath.capsuleCoins(squishy, now)
		local power = CapsuleMath.power(now) :: number
		local nextCoins = if nextLevel then perHour(CapsuleMath.capsuleCoins(squishy, nextLevel), nextLevel) else nil
		local nextGrip = if nextLevel then perHour(CapsuleMath.power(nextLevel) :: number, nextLevel) else nil
		card.coinsText = nowNext("coinsHour", "coins", perHour(coins, now), nextCoins)
		card.gripText = nowNext("gripHour", "grip", perHour(power, now), nextGrip)
	else
		card.emptyText = S.empty
	end
	if nextLevel == nil then
		card.state, card.maxText = "max", S.max
		return card
	end
	local gate = CapsuleMath.gripLevelFor(nextLevel) :: number
	local evolve = CapsuleMath.tier(nextLevel) ~= CapsuleMath.tier(now)
	if evolve then
		card.evolveText = Strings.format(S.evolveTo, { tier = tierName(nextLevel), level = gate })
	end
	if not input.own then
		card.state = "visitor"
		return card
	end
	card.price = CapsuleMath.price(now) :: number
	local action: Action = if evolve then "evolve" else "upgrade"
	card.action = action
	card.buttonText = Strings.format(S[action], { coins = Format.coins(card.price) })
	if input.pending then
		card.state = "pending"
	elseif (if finite(input.gripLevel) then input.gripLevel :: number else 1) < gate then
		card.state, card.reason = "gripLocked", Strings.format(S.needGrip, { level = gate })
	else
		spendState(card, input)
	end
	return card
end

function CapsuleFormat.popTexts(own: boolean, squeezes: number, capsule: any?): (string?, string?)
	if not own or not finite(squeezes) or squeezes < 1 or type(capsule) ~= "table" then
		return nil, nil
	end
	local coins = CapsuleMath.capsuleCoins(capsule.squishyId, capsule.level)
	if coins <= 0 then
		return nil, nil
	end
	local n = math.floor(squeezes)
	return Strings.format(Strings.common.coinsGain, { coins = Format.coins(n * coins) }),
		Strings.format(Strings.grip.popup, { n = Format.coins(n * (CapsuleMath.power(capsule.level) :: number)) })
end

function CapsuleFormat.swapList(owned: any?, capsules: any?, slot: number): { SwapEntry }
	local inSlot: { [string]: number } = {}
	local list = if type(capsules) == "table" and type(capsules.list) == "table" then capsules.list else {}
	for index, entry in list do
		if type(entry) == "table" and type(entry.squishyId) == "string" then
			inSlot[entry.squishyId] = index
		end
	end
	local entries: { SwapEntry } = {}
	for id in if type(owned) == "table" then owned else {} do
		if Catalog.isValidId(id) then
			local at = inSlot[id]
			table.insert(entries, {
				id = id,
				name = nameOf(id),
				power = Strings.format(S.power, { n = CapsuleMath.squishyPower(id) }),
				note = if at and at ~= slot then Strings.format(S.inCapsule, { slot = at }) else nil,
				here = at == slot,
			})
		end
	end
	table.sort(entries, function(a: SwapEntry, b: SwapEntry): boolean
		local pa, pb = Catalog.getPower(a.id), Catalog.getPower(b.id)
		if pa ~= pb then
			return pa > pb
		end
		return a.name < b.name
	end)
	return entries
end

function CapsuleFormat.cardWidth(screenX: number, scale: number): number
	local width = if finite(screenX) and screenX > 0 then screenX else 1280
	return math.min(CARD.cardWidth, Layout.modalWidth(width, scale, CARD.cardMargin))
end

return table.freeze(CapsuleFormat)
