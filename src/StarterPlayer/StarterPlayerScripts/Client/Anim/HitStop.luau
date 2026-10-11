--!strict
-- HitStop (client only; clock math only: no instances, no connections, no time scale). DESIGN §18.4.4.
-- A tiny presentation freeze at contact, for the two people involved in a hit (the caller decides who: secondsFor).
-- Nothing global stops: only the effects that read `elapsed` (the impacting projectile, the victim's flinch and
-- flash) hold, and the ones queued with `after` (puffs, ring, vignette, shake, FOV punch, held boing, the elimination
-- sequence) start when the hold ends.
--
--   local start = HitStop.trigger(projId, seconds, os.clock(), Tweens.reducedMotion()) -- nil: no hold
--   local t = HitStop.elapsed(effectStart, os.clock())   -- now - start, minus every hold overlapping [start, now]
--   HitStop.after(function() ... end)                    -- runs now when no hold is running, else when it ends
--   HitStop.runDue(os.clock())                           -- VfxController's step runs the due ones
--
-- Rules (Config.Vfx.HitStop): hit 0.06 s, elimination 0.10 s, practice target 0.04 s. Holds merge and never stack
-- (a trigger inside a running hold only extends it to its own end). At most maxPerWindow (0.12 s) of hold inside any
-- trailing windowSeconds (0.5 s); a trigger with no room left gets no hold. Deduplicated by key (the projId):
-- VfxController and ProjectileRenderer both ask, the first one registers, and every later ask with that key gets the
-- same answer (the same start, or nil). Under ReducedMotion nothing holds (everything plays at once, as before).
-- Reading: a hold refused for the window cap is remembered for its key like a granted one, so both askers agree.
-- The module functions use one shared stopper (os.clock); HitStop.new(clock?) makes a private one (tests).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

type Hold = { from: number, to: number }
type KeyEntry = { start: number?, at: number }

export type Stopper = {
	trigger: (self: Stopper, key: any, seconds: number, now: number, reduced: boolean?) -> number?,
	elapsed: (self: Stopper, start: number, now: number) -> number,
	after: (self: Stopper, fn: () -> (), now: number?) -> (),
	runDue: (self: Stopper, now: number, onError: ((err: any) -> ())?) -> number,
	holding: (self: Stopper, now: number) -> boolean,
	holdEndsAt: (self: Stopper) -> number,
	pending: (self: Stopper) -> number,
	clear: (self: Stopper) -> (),
	_clock: () -> number,
	_holds: { Hold },
	_keys: { [any]: KeyEntry },
	_queue: { () -> () },
}

-- Constants

local HIT_STOP = Config.Vfx.HitStop
-- reading (not in DESIGN): holds and keys older than this are forgotten (every effect that reads `elapsed` lasts
-- less than 3 s).
local KEEP_SECONDS = 5

-- Module table

local StopperClass = {}
StopperClass.__index = StopperClass

local HitStop = {}

-- Private

local defaultStopper: Stopper? = nil

local function prune(self: Stopper, now: number)
	local holds = self._holds
	while #holds > 0 and holds[1].to < now - KEEP_SECONDS do
		table.remove(holds, 1)
	end
	for key, entry in self._keys do
		if entry.at < now - KEEP_SECONDS then
			self._keys[key] = nil
		end
	end
end

-- Seconds of hold already used inside the trailing window that ends at `now`.
local function usedInWindow(self: Stopper, now: number): number
	local from = now - HIT_STOP.windowSeconds
	local used = 0
	for _, hold in self._holds do
		local overlap = hold.to - math.max(hold.from, from)
		if overlap > 0 then
			used += overlap
		end
	end
	return used
end

local function holdEnd(self: Stopper): number
	local holds = self._holds
	local last = holds[#holds]
	return if last then last.to else -math.huge
end

-- Methods

-- Registers a hold of `seconds` starting at `now` for `key` (nil key: no deduplication). Returns the hold's start
-- (now, or the first asker's start for a known key), or nil when nothing holds: ReducedMotion, a non-positive
-- length, or no room left in the window.
function StopperClass.trigger(self: Stopper, key: any, seconds: number, now: number, reduced: boolean?): number?
	if reduced == true or type(seconds) ~= "number" or not (seconds > 0) or type(now) ~= "number" then
		return nil
	end
	prune(self, now)
	if key ~= nil then
		local known = self._keys[key]
		if known then
			return known.start
		end
	end
	local room = HIT_STOP.maxPerWindow - usedInWindow(self, now)
	local length = math.min(seconds, HIT_STOP.maxPerWindow)
	local holds = self._holds
	local last = holds[#holds]
	local start: number? = nil
	if last and now <= last.to then
		-- Merge: the running hold only grows to this one's end (never stacked), within the window room.
		local extension = math.clamp(now + length - last.to, 0, math.max(room, 0))
		last.to += extension
		start = now
	elseif room > 0 then
		table.insert(holds, { from = now, to = now + math.min(length, room) })
		start = now
	end
	if key ~= nil then
		self._keys[key] = { start = start, at = now }
	end
	return start
end

-- now - start, minus every hold that overlaps [start, now] (never below 0).
function StopperClass.elapsed(self: Stopper, start: number, now: number): number
	local total = now - start
	if not (total > 0) then
		return 0
	end
	for _, hold in self._holds do
		local overlap = math.min(now, hold.to) - math.max(start, hold.from)
		if overlap > 0 then
			total -= overlap
		end
	end
	return math.max(total, 0)
end

-- Runs fn now when no hold is running at `now` (default: the stopper's clock), else queues it for the hold's end.
function StopperClass.after(self: Stopper, fn: () -> (), now: number?)
	local at = if now == nil then self._clock() else now
	if at < holdEnd(self) then
		table.insert(self._queue, fn)
		return
	end
	fn()
end

-- Runs, in order, every queued fn once the hold is over. Returns how many ran. An error in one never stops the rest
-- (it goes to onError when given).
function StopperClass.runDue(self: Stopper, now: number, onError: ((err: any) -> ())?): number
	if #self._queue == 0 or now < holdEnd(self) then
		prune(self, now)
		return 0
	end
	local due = self._queue
	self._queue = {}
	for _, fn in due do
		local ok, err = pcall(fn :: () -> ...any)
		if not ok and onError then
			onError(err)
		end
	end
	prune(self, now)
	return #due
end

function StopperClass.holding(self: Stopper, now: number): boolean
	return now < holdEnd(self)
end

-- When the latest hold ends (-math.huge when there is none).
function StopperClass.holdEndsAt(self: Stopper): number
	return holdEnd(self)
end

-- Number of queued fns.
function StopperClass.pending(self: Stopper): number
	return #self._queue
end

-- Drops every hold, key and queued fn (the queued ones never run).
function StopperClass.clear(self: Stopper)
	table.clear(self._holds)
	table.clear(self._keys)
	self._queue = {}
end

-- Public

-- A private stopper on `clock` (default os.clock).
function HitStop.new(clock: (() -> number)?): Stopper
	local self = {
		_clock = clock or os.clock,
		_holds = {},
		_keys = {},
		_queue = {},
	}
	return setmetatable(self, StopperClass) :: any
end

-- The client's shared stopper (VfxController and ProjectileRenderer).
function HitStop.default(): Stopper
	if defaultStopper == nil then
		defaultStopper = HitStop.new(os.clock)
	end
	return defaultStopper :: Stopper
end

-- Pure: the hold for an impact as seen by this client, or nil. Only the two people involved: the local victim of a
-- "player" impact or the local thrower (hit 0.06 s, elimination 0.10 s); on a practice "target", only the thrower
-- (0.04 s). Never for "geometry", "expired" or "fizzle" (walls and floors), never for spectators.
function HitStop.secondsFor(
	kind: string,
	eliminated: boolean?,
	localIsVictim: boolean,
	localIsThrower: boolean
): number?
	if kind == "player" then
		if not (localIsVictim or localIsThrower) then
			return nil
		end
		return if eliminated == true then HIT_STOP.elimination else HIT_STOP.playerHit
	elseif kind == "target" then
		return if localIsThrower then HIT_STOP.practiceTarget else nil
	end
	return nil
end

-- Shortcuts to the shared stopper.
function HitStop.trigger(key: any, seconds: number, now: number, reduced: boolean?): number?
	return HitStop.default():trigger(key, seconds, now, reduced)
end

function HitStop.elapsed(start: number, now: number): number
	return HitStop.default():elapsed(start, now)
end

function HitStop.after(fn: () -> (), now: number?)
	HitStop.default():after(fn, now)
end

function HitStop.runDue(now: number, onError: ((err: any) -> ())?): number
	return HitStop.default():runDue(now, onError)
end

function HitStop.holding(now: number): boolean
	return HitStop.default():holding(now)
end

function HitStop.pending(): number
	return HitStop.default():pending()
end

function HitStop.clear()
	HitStop.default():clear()
end

return HitStop
