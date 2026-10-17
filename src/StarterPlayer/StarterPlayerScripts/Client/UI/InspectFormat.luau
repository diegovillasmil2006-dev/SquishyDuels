--!strict
-- InspectFormat (client only, pure). DESIGN §10.1 (one state machine Closed → Opening → Open → Closing; a match closes
-- Inspect with "Opponent found!"), §10.4 (the open guard), §10.7 (squeeze preview: ≤ 8 per second, 2D dots), §10.8
-- (the info panel, all data from Catalog, Config and Boxes), §10.9 (owned and unowned). What InspectController and
-- UI/InspectPanel show, as plain data; nothing is typed here:
--   view(id, ctx)                      the whole panel for one squishy (see View); nil for an unknown id
--   equipState(id, ctx)                the Equip button: equip / equipped / notOwned / locked / loading
--                                      (InventoryFormat.equipState, the Squishies screen's rule)
--   openAction(phase, currentId, newId) §10.4 guard: Closed -> "open"; otherwise same id -> "none", other -> "select"
--   previewAllowed(recent, now, max?)  the squeeze preview's rate limit: at most Preview.maxPerSecond in any 1 s
--   closeToastKey(reason)              "matched" -> queue.opponentFound (§10.1), else nil
--   dotCount(rarity, reduced)          the 2D dots of one preview squeeze (Anim.squeeze.inspectDotsMin..Max)
--   dotSample(t, angle, speed, cfg?)   one dot at t seconds: (offset px, transparency, scale, done)
-- Readings (DESIGN silent; Part 6):
--   * "How to get" (§10.8 #8) lists every box from Boxes.containing, the free Treat Box included, with its exact
--     percent text, in every policy state (§6.10 shows the odds in all four), then "Shop: {price} Coins" when the
--     squishy has a shopPrice. "View in Shop" needs the shop screen (ctx.shopAvailable) and an unowned squishy.
--   * Elimination (§10.8 #7): the Strings text of the def's eliminationEffectId under `elimination.`; an effect with no
--     text there (epic_pending) shows Standard, as §9.9 says until the Epic effect ships.
--   * The trail (§10.8 #5) is "Trail: {name}" (trail.label) with the gradient of RarityStyle.trailColorSequence and
--     the def's accent; no trail (Commons) = "No trail" and no colours.
--   * The dot count goes linearly from inspectDotsMin (Common) to inspectDotsMax (Exclusive) by rarity order, rounded;
--     ReducedMotion multiplies it by Config.Vfx.reducedParticleMultiplier (floored, like Anim/FxPool), at least 1.
--     A dot flies from the model centre at `speed` px/s, slowing linearly to a stop at dotLifeSeconds, while it
--     fades (transparency 0 -> 1) and shrinks (scale 1 -> 0).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local UI = script.Parent
local BoxFormat = require(UI.BoxFormat)
local InventoryFormat = require(UI.InventoryFormat)

-- Types

export type Phase = "Closed" | "Opening" | "Open" | "Closing"
export type OpenAction = "open" | "select" | "none"
export type EquipState = InventoryFormat.EquipState

export type HowToGetLine = {
	kind: "box" | "shop",
	text: string, -- "Snack Box: 3.00%" / "Shop: 7,500 Coins"
	boxId: string?, -- the box of a "box" line
}

export type Trail = {
	text: string, -- "Trail: Ribbon" / "No trail"
	colors: ColorSequence?, -- the 2D swatch; nil = no trail
}

export type StatLine = {
	stat: string, -- speed / size / reload / windup / arc (§10.8 order)
	label: string, -- "Speed"
	valueText: string, -- "95 studs/s"
	fraction: number, -- 0..1 inside the §5.8 band
}

export type View = {
	id: string,
	blueprintId: string,
	name: string,
	rarity: string,
	rarityName: string, -- "Epic"
	rarityLabel: string, -- "EPIC"
	pips: number,
	owned: boolean,
	equipped: boolean, -- only when owned
	badgeKey: string, -- common.equipped / common.owned / common.notOwned
	badgeText: string,
	previewBadge: string?, -- "Preview · Not owned" when not owned (§10.9)
	caption: string, -- inspect.preview (§10.7)
	coinsText: string, -- the capsule power, "x16 power"
	coinsSub: string,
	stats: { StatLine },
	statsCaption: string,
	trail: Trail,
	ultimate: string?, -- Dragon: "Ultimate: Dragon Rush. ..." (Config.Abilities)
	elimination: string, -- "Elimination: Standard"
	howToGetTitle: string,
	howToGet: { HowToGetLine }, -- empty when owned
	shopPrice: number?,
	canViewInShop: boolean,
	yaw: number, -- Catalog `inspect` default view
	pitch: number,
}

export type ViewContext = {
	owned: boolean,
	equipped: boolean, -- this squishy is the equipped one
	shopAvailable: boolean?, -- the shop screen is registered (View in Shop)
}

export type EquipContext = {
	owned: boolean,
	equipped: boolean,
	locked: boolean, -- lobby lock (Matched through Returning)
	pending: string?, -- the id an Equip request is running for
	confirmed: string?, -- the id the server just accepted
}

export type DotConfig = {
	dotLifeSeconds: number,
}

-- Constants

local PREVIEW = Config.Inspect.Preview
local ORBIT = Config.Inspect.Orbit
local SQUEEZE_ANIM = Config.Anim.squeeze
local ABILITIES = Config.Abilities
local REDUCED_MULTIPLIER = Config.Vfx.reducedParticleMultiplier
local WINDOW_SECONDS = 1 -- §10.7: "≤ 8 per second"
local MATCHED_REASON = "matched"
local MATCHED_TOAST_KEY = "queue.opponentFound"
local ELIMINATION_PREFIX = "elimination."

-- Module table

local InspectFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function textOf(key: string, fallback: string): string
	return Strings.resolve(key) or fallback
end

local function badgeKeyOf(owned: boolean, equipped: boolean): string
	if owned and equipped then
		return "common.equipped"
	elseif owned then
		return "common.owned"
	end
	return "common.notOwned"
end

local function statLines(def: Types.SquishyDef): { StatLine }
	local lines: { StatLine } = {}
	for _, bar in InventoryFormat.statBars(def) do
		table.insert(lines, {
			stat = bar.stat,
			label = textOf(bar.labelKey, bar.stat),
			valueText = Strings.format(
				Strings.inspect.statValue,
				{ value = bar.value, unit = textOf(bar.unitKey, "") }
			),
			fraction = bar.fraction,
		})
	end
	return lines
end

local function trailOf(def: Types.SquishyDef): Trail
	local kind = def.visuals.trail
	local style = RarityStyle.trail(kind)
	if style == nil then
		return { text = Strings.trail.none, colors = nil }
	end
	local ok, accent = pcall(Color3.fromHex, def.visuals.accent)
	local colors = if ok then RarityStyle.trailColorSequence(kind, accent) else nil
	return {
		text = Strings.format(Strings.trail.label, { name = textOf(style.nameKey, kind :: string) }),
		colors = colors,
	}
end

local function ultimateOf(def: Types.SquishyDef): string?
	local id = def.ultimateId
	local ability = if id then (ABILITIES :: any)[id] else nil
	if ability == nil then
		return nil
	end
	return Strings.format(Strings.inspect.ultimate, {
		name = textOf(ability.nameKey, id :: string),
		description = Strings.format(textOf(ability.descriptionKey, ""), { seconds = ability.telegraphSeconds }),
	})
end

local function eliminationOf(def: Types.SquishyDef): string
	local name = Strings.resolve(ELIMINATION_PREFIX .. def.eliminationEffectId) or Strings.elimination.standard
	return Strings.format(Strings.inspect.elimination, { name = name })
end

local function howToGetOf(def: Types.SquishyDef): { HowToGetLine }
	local lines: { HowToGetLine } = {}
	for _, row in Boxes.containing(def.id) do
		table.insert(lines, {
			kind = "box",
			text = Strings.format(
				Strings.inspect.boxChance,
				{ box = BoxFormat.boxName(row.boxId), percent = row.text }
			),
			boxId = row.boxId,
		})
	end
	local price = def.shopPrice
	if price ~= nil then
		table.insert(lines, {
			kind = "shop",
			text = Strings.format(Strings.inspect.shopPrice, { price = Format.coins(price) }),
			boxId = nil,
		})
	end
	return lines
end

-- Public

-- The whole info panel for one squishy (§10.8, §10.9); nil for an unknown id.
function InspectFormat.view(id: string, ctx: ViewContext): View?
	local def = Catalog.get(id)
	if def == nil then
		return nil
	end
	local owned = ctx.owned == true
	local equipped = owned and ctx.equipped == true
	local rarity: string = def.rarity
	local info = Rarity.get(rarity)
	local badgeKey = badgeKeyOf(owned, equipped)
	local price = def.shopPrice
	local howToGet: { HowToGetLine } = if owned then {} else howToGetOf(def)
	local view: View = {
		id = def.id,
		blueprintId = def.blueprintId,
		name = textOf(def.nameKey, def.id),
		rarity = rarity,
		rarityName = if info then textOf(info.nameKey, rarity) else rarity,
		rarityLabel = if info then textOf(info.labelKey, rarity) else rarity,
		pips = if info then info.pips else 0,
		owned = owned,
		equipped = equipped,
		badgeKey = badgeKey,
		badgeText = textOf(badgeKey, badgeKey),
		previewBadge = if owned then nil else Strings.inspect.previewNotOwned,
		caption = Strings.inspect.preview,
		-- Phase 5 (progression spec 2026-10-12 §3, §6): what the squishy multiplies in the pen ("x16 power").
		coinsText = Strings.format(Strings.squishy.power, { n = Catalog.getPower(def.id) }),
		coinsSub = Strings.squishy.powerNote,
		stats = statLines(def),
		statsCaption = Strings.inspect.statsCaption,
		trail = trailOf(def),
		ultimate = ultimateOf(def),
		elimination = eliminationOf(def),
		howToGetTitle = Strings.inspect.howToGet,
		howToGet = howToGet,
		shopPrice = price,
		canViewInShop = not owned and price ~= nil and ctx.shopAvailable == true,
		yaw = if finite(def.inspect.yaw) then def.inspect.yaw else ORBIT.defaultYawDeg,
		pitch = if finite(def.inspect.pitch) then def.inspect.pitch else ORBIT.defaultPitchDeg,
	}
	return view
end

-- The Equip button (§10.9): the Squishies screen's rule (InventoryFormat.equipState). An unknown id is "notOwned".
function InspectFormat.equipState(id: string, ctx: EquipContext): EquipState
	local def = Catalog.get(id)
	if def == nil then
		return "notOwned"
	end
	local owned = ctx.owned == true
	local entry: InventoryFormat.Entry = {
		id = def.id,
		def = def,
		name = def.id,
		rarity = def.rarity,
		owned = owned,
		equipped = owned and ctx.equipped == true,
		isNew = false,
	}
	return InventoryFormat.equipState(
		entry,
		{ locked = ctx.locked == true, pending = ctx.pending, confirmed = ctx.confirmed }
	)
end

-- §10.4 guard: Closed opens; otherwise the same id does nothing and another id swaps the model (select).
function InspectFormat.openAction(phase: Phase, currentId: string?, newId: string): OpenAction
	if phase == "Closed" then
		return "open"
	end
	if currentId == newId then
		return "none"
	end
	return "select"
end

-- §10.7 rate limit: a preview squeeze at `now` (seconds) is allowed while fewer than `maxPerSecond` (default
-- Preview.maxPerSecond) were allowed in the last second. Returns (allowed, the new list of recent times); the input
-- list is never changed. Only allowed squeezes are recorded.
function InspectFormat.previewAllowed(recent: { number }, now: number, maxPerSecond: number?): (boolean, { number })
	local limit = if finite(maxPerSecond) then maxPerSecond :: number else PREVIEW.maxPerSecond
	local kept: { number } = {}
	for _, at in recent do
		if finite(at) and now - at < WINDOW_SECONDS and at <= now then
			table.insert(kept, at)
		end
	end
	if not finite(now) or #kept >= limit then
		return false, kept
	end
	table.insert(kept, now)
	return true, kept
end

-- The toast to show when Inspect closes for `reason` (§10.1: a found match says "Opponent found!"); nil = none.
function InspectFormat.closeToastKey(reason: string?): string?
	if reason == MATCHED_REASON then
		return MATCHED_TOAST_KEY
	end
	return nil
end

-- The number of 2D dots of one preview squeeze (see the header's reading).
function InspectFormat.dotCount(rarity: string, reduced: boolean): number
	local low, high = SQUEEZE_ANIM.inspectDotsMin, SQUEEZE_ANIM.inspectDotsMax
	local index = Rarity.index(rarity) or 1
	local steps = math.max(#Rarity.ORDER - 1, 1)
	local count = math.floor(low + (high - low) * (index - 1) / steps + 0.5)
	if reduced then
		count = math.floor(count * REDUCED_MULTIPLIER)
	end
	return math.max(1, count)
end

-- One dot `t` seconds after the squeeze, flying along `angleRad` (0 = right, π/2 = down: screen axes) at `speedPx`
-- px/s, slowing linearly to a stop at dotLifeSeconds: (offset from the start in px, transparency 0..1, scale 1..0,
-- done). Once t >= dotLifeSeconds it is done (transparency 1, scale 0).
function InspectFormat.dotSample(
	t: number,
	angleRad: number,
	speedPx: number,
	cfg: DotConfig?
): (Vector2, number, number, boolean)
	local life = (cfg or PREVIEW).dotLifeSeconds
	local time = if finite(t) then math.max(t, 0) else life
	local u = if life > 0 then math.min(time / life, 1) else 1
	local angle = if finite(angleRad) then angleRad else 0
	local speed = if finite(speedPx) then speedPx else 0
	local elapsed = math.min(time, life)
	local distance = speed * elapsed * (1 - u / 2)
	local offset = Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance)
	if u >= 1 then
		return offset, 1, 0, true
	end
	return offset, u, 1 - u, false
end

return InspectFormat
