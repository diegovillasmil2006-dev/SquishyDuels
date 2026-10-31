--!strict
-- EventSchedule (shared, pure). 2026-10-31 (owner: candy rain, "Yes, build it"): the timed events' clock and rules,
-- used by Server/Services/EventService and Client/Controllers/EventController. Times are unix seconds from
-- Workspace:GetServerTimeNow(), so every lobby server and client agrees (LihFolk "Live Ops Events and Updates": derive
-- schedules from UTC, never from the server's start or the client's clock).
--   at(t)                         the event running at t, or the next one: { kind, live, startsAt, endsAt, index }
--   pillText(t)                   "Candy rain in 8:12" while waiting, "CANDY RAIN! 3:41" while live
--   candyCoins(penRate)           one candy's Coins: penSeconds of the pen's Coins a second, at least minCoins
--   candiesDue(players, elapsed, spawned)   how many more candies to drop now, so perPlayer x players fall evenly
--                                 over the event
--   ringPoint(u, v)               a spot (x, z) in the candy ring from two numbers in [0, 1)
--   grabber(position, roots, radius)   the key of the root nearest `position` within `radius`, or nil
--   boxForm(t, roll)              a box squishy's form at t, roll() giving a number in [0, 1) (called only while
--                                 golden luck is live): 2 (Rainbow)
--                                 under rainbowChance, 1 (Golden) under rainbowChance + goldenChance; else 0
--   goldenOddsText(t)             the Boxes window's odds line while golden luck is live, else nil
--   coinMult(t, reason)           DoubleCoins.mult while double coins is live and `reason` is one of its reasons, else 1
--   restockAt(t)                  the live shop restock's index, else nil
--   nextStart(t, kind)            when the next `kind` event starts (its start, if it is live at t)
--   restockOffers(index)          that restock's offers { squishy, form, price, stock, deal }: the Golden ones (the
--                                 first Rainbow on rainbowChance), then the rare ones at a discount; picked by a Random
--                                 seeded with the index, so every server and client gets the same
--   stockText(index, left)        the stock as one string "index:3,2,1,3" (ShopService's Workspace attribute)
--   stockLeft(text, index, offers) what stockText says is left of each offer, the full stock when it is about another
--                                 restock or broken

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local EVENTS = require(Shared.Config.Events)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

-- Types

export type Kind = string
export type State = { kind: Kind, live: boolean, startsAt: number, endsAt: number, index: number }
export type Deal = "golden" | "rainbow" | "rare"
export type Offer = { squishy: string, form: number, price: number, stock: number, deal: Deal }

-- Constants

local CANDY = EVENTS.CandyRain

-- Module table

local EventSchedule = {}

-- Public

function EventSchedule.at(t: number): State
	local index = t // EVENTS.loopSeconds
	local startsAt = index * EVENTS.loopSeconds
	local live = t < startsAt + EVENTS.liveSeconds
	if not live then
		index += 1
		startsAt += EVENTS.loopSeconds
	end
	return {
		kind = EVENTS.kinds[index % #EVENTS.kinds + 1],
		live = live,
		startsAt = startsAt,
		endsAt = startsAt + EVENTS.liveSeconds,
		index = index,
	}
end

function EventSchedule.pillText(t: number): string
	local state = EventSchedule.at(t)
	local name = Strings.event[state.kind] or state.kind
	if state.live then
		return Strings.format(Strings.event.pillLive, { event = string.upper(name), time = Format.clock(state.endsAt - t) })
	end
	return Strings.format(Strings.event.pillNext, { event = name, time = Format.clock(state.startsAt - t) })
end

function EventSchedule.candyCoins(penRate: number): number
	local rate = if penRate == penRate and penRate > 0 then penRate else 0
	return math.max(CANDY.minCoins, math.floor(rate * CANDY.penSeconds))
end

function EventSchedule.candiesDue(players: number, elapsed: number, spawned: number): number
	local share = math.clamp(elapsed / EVENTS.liveSeconds, 0, 1)
	return math.max(0, math.floor(CANDY.perPlayer * players * share) - spawned)
end

function EventSchedule.ringPoint(u: number, v: number): (number, number)
	-- sqrt keeps the candy evenly spread over the ring's area, not bunched at its inner edge
	local inner, outer = CANDY.innerRadius, CANDY.outerRadius
	local radius = math.sqrt(inner * inner + v * (outer * outer - inner * inner))
	local angle = u * 2 * math.pi
	return CANDY.centre.X + radius * math.cos(angle), CANDY.centre.Z + radius * math.sin(angle)
end

function EventSchedule.grabber<K>(position: Vector3, roots: { [K]: Vector3 }, radius: number): K?
	local best, bestDistance = nil, radius
	for key, root in roots do
		local distance = (root - position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = key, distance
		end
	end
	return best
end

function EventSchedule.boxForm(t: number, roll: () -> number): number
	local state = EventSchedule.at(t)
	if not (state.live and state.kind == "goldenLuck") then
		return 0 -- no roll taken: outside golden luck the box draws stay exactly as before
	end
	local luck = EVENTS.GoldenLuck
	local r = roll()
	if r < luck.rainbowChance then
		return 2
	elseif r < luck.rainbowChance + luck.goldenChance then
		return 1
	end
	return 0
end

-- The Boxes window's odds line while golden luck is live ("Golden luck: 10% Golden, 1% Rainbow"), else nil.
function EventSchedule.goldenOddsText(t: number): string?
	local state = EventSchedule.at(t)
	if not (state.live and state.kind == "goldenLuck") then
		return nil
	end
	local luck = EVENTS.GoldenLuck
	return Strings.format(Strings.event.goldenOdds, {
		golden = math.round(luck.goldenChance * 100),
		rainbow = math.round(luck.rainbowChance * 100),
	})
end

function EventSchedule.coinMult(t: number, reason: string): number
	local state = EventSchedule.at(t)
	local double = EVENTS.DoubleCoins
	if state.live and state.kind == "doubleCoins" and table.find(double.reasons, reason) then
		return double.mult
	end
	return 1
end

function EventSchedule.restockAt(t: number): number?
	local state = EventSchedule.at(t)
	return if state.live and state.kind == "shopRestock" then state.index else nil
end

function EventSchedule.nextStart(t: number, kind: Kind): number
	local loop = EVENTS.loopSeconds
	local index = t // loop
	for k = 0, #EVENTS.kinds do
		local startsAt = (index + k) * loop
		if EVENTS.kinds[(index + k) % #EVENTS.kinds + 1] == kind and t < startsAt + EVENTS.liveSeconds then
			return startsAt
		end
	end
	return math.huge -- not a kind in the turn order
end

function EventSchedule.restockOffers(index: number): { Offer }
	local cfg = EVENTS.ShopRestock
	local rng = Random.new(index)
	local function pick(rarities: { string }, count: number): { Types.SquishyDef }
		local pool = {}
		for _, def in Catalog.list() do
			if def.shopPrice ~= nil and table.find(rarities, def.rarity) then
				table.insert(pool, def)
			end
		end
		local picked = {}
		for _ = 1, math.min(count, #pool) do
			table.insert(picked, table.remove(pool, rng:NextInteger(1, #pool)) :: Types.SquishyDef)
		end
		return picked
	end
	local rainbow = rng:NextNumber() < cfg.rainbowChance
	local offers: { Offer } = {}
	for i, def in pick(cfg.goldenRarities, cfg.goldenOffers) do
		local isRainbow = rainbow and i == 1
		table.insert(offers, {
			squishy = def.id,
			form = if isRainbow then 2 else 1,
			price = (def.shopPrice :: number) * (if isRainbow then cfg.rainbowPriceMult else cfg.goldenPriceMult),
			stock = if isRainbow then cfg.rainbowStock else cfg.stock,
			deal = if isRainbow then "rainbow" else "golden",
		})
	end
	for _, def in pick(cfg.rareRarities, cfg.rareOffers) do
		table.insert(offers, {
			squishy = def.id,
			form = 0,
			price = math.floor((def.shopPrice :: number) * (1 - cfg.rareDiscount)),
			stock = cfg.stock,
			deal = "rare",
		})
	end
	return offers
end

function EventSchedule.stockText(index: number, left: { number }): string
	return `{index}:{table.concat(left, ",")}`
end

function EventSchedule.stockLeft(text: unknown, index: number, offers: { Offer }): { number }
	local left = {}
	for i, offer in offers do
		left[i] = offer.stock
	end
	local head, rest = string.match(if type(text) == "string" then text else "", "^(%d+):([%d,]*)$")
	if head == nil or tonumber(head) ~= index then
		return left
	end
	local i = 0
	for n in string.gmatch(rest :: string, "%d+") do
		i += 1
		if left[i] ~= nil then
			left[i] = math.min(left[i], tonumber(n) :: number)
		end
	end
	return left
end

return EventSchedule
