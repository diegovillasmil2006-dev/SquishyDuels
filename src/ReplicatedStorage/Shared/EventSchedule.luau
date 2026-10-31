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

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local EVENTS = require(Shared.Config.Events)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)

-- Types

export type Kind = string
export type State = { kind: Kind, live: boolean, startsAt: number, endsAt: number, index: number }

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

return EventSchedule
