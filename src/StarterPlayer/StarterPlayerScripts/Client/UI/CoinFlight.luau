--!strict
-- CoinFlight (client only). DESIGN §18.5.2 B2 ("+N" coin flights, §9.14 "flies into the coin pill"), §18.9 (UI juice
-- frames), §18.1 #2 (one frame loop).
--   CoinFlight.play(from, to, amount, onLand, options?) -> boolean
-- `from` is a GuiObject (its centre when the flight starts), a point in GUI space (AbsolutePosition space) or a world
-- point (Camera:WorldToScreenPoint, which already takes the GUI inset into account); `to` is the coin pill
-- (HudController.coinsAnchor()). UI FINAL R2 (the design's fly, hud-lib.js lib:269-286, plan work/ui/PLAN.md §2.1;
-- numbers in Config.UI.motion.coinFlight): k = options.count (default coinFlight.count, 8, H:663; a claim passes 10,
-- a paid squeeze 1, plan G2.8) CoinIcons (iconPx, the img.coin picture) leave staggerMs apart, each within
-- startJitterPx of the source; it swings through a point up to arcXPx to either side and arcUpMinPx..arcUpMaxPx above
-- its start (these px x options.scale, as its coins), growing 0 -> midScale and turned up to ±spinDeg there (at midAt
-- of the run eased by coinFlight.curve, cubic-bezier(.25,.7,.35,1)), then drops onto the pill on the second leg's
-- own cubic-bezier(.55,0,.85,.55) (legCurve) shrinking to endScale, over ms + 0..jitterMs. onLand(i, k)
-- runs at each landing with i = the landing's order in its play() (1 for the first coin down; the caller bounces the
-- pill, plays ui.coin and starts its count-up at i == 1, which lasts countMs(k) so it ends after the last coin).
-- At most maxCoins icons and one flight: a second play() adds its coins to the running flight (fewer when the icons
-- would go over maxCoins; its onLand then gets the number actually added). One Scheduler render effect runs it all.
-- Returns false (nothing flies) for an amount under minAmount when no count is given, under ReducedMotion (the caller
-- sets the number at once), or when no icon fits. A UI module: it never requires a controller (HudController owns
-- every flight).
-- Pure: coinCount, startPoint, midPoint, lifeMs, path, progress, scaleAt, spinAt, uAtEased, landingTimes, countMs
-- (unit-tested in Edit mode).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

local UI = script.Parent
local Client = UI.Parent
local CoinIcon = require(UI.Components.CoinIcon)
local Create = require(UI.Create)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Source = GuiObject | Vector2 | Vector3
export type OnLand = (i: number, k: number) -> ()
export type Options = {
	parent: Instance?, -- where the icons are drawn (HudController passes SD_Overlay); default: `to`'s ScreenGui
	scale: number?, -- the UI scale of that parent's offsets (UIController.scale()); default 1
	count: number?, -- UI FINAL R2: the coins to fly (1..maxCoins); default coinFlight.count; no minAmount then
}

-- One play()'s coins: they count their landings together.
type Batch = { k: number, landed: number, onLand: OnLand }

type Coin = {
	icon: CoinIcon.CoinIcon,
	scale: UIScale,
	from: Vector2, -- GUI space (AbsolutePosition space), the jittered start
	mid: Vector2, -- the swing point (GUI space)
	spin: number, -- degrees at the swing point
	life: number, -- seconds in the air
	start: number, -- os.clock()
	batch: Batch,
	landed: boolean,
}

type Flight = {
	layer: Frame,
	to: GuiObject,
	scale: number,
	coins: { Coin },
	lastStart: number,
	handle: Scheduler.Handle?,
}

-- Constants

local FLIGHT = Config.UI.motion.coinFlight
local MS = 1000
local FLY = Tweens.curve(FLIGHT.curve) -- lib:283, the whole run
local LEG = Tweens.curve(FLIGHT.legCurve) -- lib:281, the second leg
local LAYER_NAME = "SD_CoinFlights"

-- Module table

local CoinFlight = {}

-- Private

local log = Log.new("CoinFlight")
local flight: Flight? = nil
local rng = Random.new()

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function centreOf(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

-- The source as a point in GUI space, or nil when it can't be placed (a world point behind the camera).
local function sourcePoint(from: Source): Vector2?
	if typeof(from) == "Vector2" then
		return from :: Vector2
	elseif typeof(from) == "Vector3" then
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return nil
		end
		local point, onScreen = camera:WorldToScreenPoint(from :: Vector3)
		if not onScreen then
			return nil
		end
		return Vector2.new(point.X, point.Y)
	elseif typeof(from) == "Instance" and (from :: Instance):IsA("GuiObject") then
		return centreOf(from :: GuiObject)
	end
	return nil
end

-- The eased time of a coin u (0..1) into its flight: the design's whole-run cubic-bezier(.25,.7,.35,1) (lib:283).
local function eased(u: number): number
	return FLY(if finite(u) then math.clamp(u, 0, 1) else 1)
end

-- The two legs of a flight at eased time e (Web Animations keyframes, lib:279-282): (0..1 on the leg, true on the
-- second leg); the first leg is linear, the second eased by its own cubic-bezier(.55,0,.85,.55) (lib:281).
local function leg(e: number): (number, boolean)
	if e <= FLIGHT.midAt then
		return e / FLIGHT.midAt, false
	end
	return LEG((e - FLIGHT.midAt) / (1 - FLIGHT.midAt)), true
end

local function finish(current: Flight)
	if flight == current then
		flight = nil
	end
	local handle = current.handle
	current.handle = nil
	if handle then
		handle:disconnect()
	end
	for _, coin in current.coins do
		coin.icon:destroy()
	end
	table.clear(current.coins)
	current.layer:Destroy()
end

local function liveCoins(current: Flight): number
	local n = 0
	for _, coin in current.coins do
		if not coin.landed then
			n += 1
		end
	end
	return n
end

local function land(coin: Coin)
	coin.landed = true
	coin.icon:destroy()
	local batch = coin.batch
	batch.landed += 1
	local order = batch.landed
	local ok, err = pcall(function(): any
		batch.onLand(order, batch.k)
		return nil
	end)
	if not ok then
		log:error("onLand failed:", err)
	end
end

local function step(current: Flight, now: number): boolean
	if current.to.Parent == nil or current.layer.Parent == nil then
		finish(current)
		return false
	end
	local origin = current.layer.AbsolutePosition
	local target = centreOf(current.to)
	local alive = false
	-- A numeric loop over the count at the start: an onLand may add coins (a second flight) or clear the flight.
	for index = 1, #current.coins do
		local coin = current.coins[index]
		if coin == nil or flight ~= current then
			return false
		end
		if not coin.landed then
			local elapsed = now - coin.start
			if elapsed >= coin.life then
				land(coin)
			else
				alive = true
				local root = coin.icon.root
				root.Visible = elapsed >= 0
				if elapsed >= 0 then
					local u = CoinFlight.progress(elapsed, coin.life)
					local at = CoinFlight.path(u, coin.from, coin.mid, target)
					local localPoint = (at - origin) / current.scale
					root.Position = UDim2.fromOffset(localPoint.X, localPoint.Y)
					root.Rotation = CoinFlight.spinAt(u, coin.spin)
					coin.scale.Scale = CoinFlight.scaleAt(u)
				end
			end
		end
	end
	if flight ~= current then
		return false
	end
	-- Coins an onLand added during this step are still waiting: keep going.
	if not alive and liveCoins(current) == 0 then
		finish(current)
		return false
	end
	return true
end

local function newFlight(to: GuiObject, options: Options?): Flight?
	local parent: Instance? = if options and options.parent
		then options.parent
		else to:FindFirstAncestorOfClass("ScreenGui")
	if parent == nil then
		return nil
	end
	local scale = if options
			and finite(options.scale)
			and (options.scale :: number) > 0
		then options.scale :: number
		else 1
	local layer: Frame = Create("Frame", {
		Name = LAYER_NAME,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 5,
		Parent = parent,
	})
	local made: Flight = { layer = layer, to = to, scale = scale, coins = {}, lastStart = -math.huge, handle = nil }
	made.handle = Scheduler.add(function(_dt: number, now: number): boolean
		return step(made, now)
	end, "render")
	return made
end

-- Public: pure ------------------------------------------------------------------------------------------------------

-- UI FINAL R2 (G2.8): how many coins fly: `count` (whole, 1..maxCoins), else coinFlight.count (the design's 8 a gain,
-- H:663).
function CoinFlight.coinCount(count: number?): number
	if not finite(count) then
		return FLIGHT.count
	end
	return math.clamp(math.floor(count :: number), 1, FLIGHT.maxCoins)
end

-- Where a coin leaves: within startJitterPx x scale (the flight's UI scale, default 1; the design's k) of the source
-- on each axis (lib:277).
function CoinFlight.startPoint(from: Vector2, random: Random, scale: number?): Vector2
	local jitter = FLIGHT.startJitterPx * (scale or 1)
	return from + Vector2.new(random:NextNumber(-jitter, jitter), random:NextNumber(-jitter, jitter))
end

-- The swing point of a coin leaving `from`: up to arcXPx to either side, arcUpMinPx..arcUpMaxPx above, each x scale
-- (the flight's UI scale, default 1; the design's k, lib:278).
function CoinFlight.midPoint(from: Vector2, random: Random, scale: number?): Vector2
	local k = scale or 1
	local x = random:NextNumber(-FLIGHT.arcXPx, FLIGHT.arcXPx) * k
	return from + Vector2.new(x, -random:NextNumber(FLIGHT.arcUpMinPx, FLIGHT.arcUpMaxPx) * k)
end

-- A coin's time in the air (ms): ms + 0..jitterMs (lib:283).
function CoinFlight.lifeMs(random: Random): number
	return FLIGHT.ms + random:NextNumber(0, FLIGHT.jitterMs)
end

-- The point at flight progress u (0..1) from `from` through the swing point `mid` to `to`, all in GUI space: the
-- first leg straight to the swing point by midAt of the eased time, the second accelerating onto the pill
-- (lib:279-282).
function CoinFlight.path(u: number, from: Vector2, mid: Vector2, to: Vector2): Vector2
	local k, second = leg(eased(u))
	if second then
		return mid:Lerp(to, k)
	end
	return from:Lerp(mid, k)
end

-- Flight progress `elapsed` seconds into a `duration`-second flight (0 before, 1 after).
function CoinFlight.progress(elapsed: number, duration: number): number
	if not finite(elapsed) or elapsed <= 0 or not (duration > 0) then
		return if finite(elapsed) and elapsed > 0 then 1 else 0
	end
	return math.min(elapsed / duration, 1)
end

-- The flight progress whose eased time is e (the whole-run curve inverted by bisection; tests find the swing point
-- with it).
function CoinFlight.uAtEased(e: number): number
	local target = math.clamp(e, 0, 1)
	local low, high = 0, 1
	for _ = 1, 50 do
		local mid = (low + high) / 2
		if FLY(mid) < target then
			low = mid
		else
			high = mid
		end
	end
	return (low + high) / 2
end

-- A coin's scale at progress u: 0 -> midScale on the first leg, -> endScale on the second (lib:280-282).
function CoinFlight.scaleAt(u: number): number
	local k, second = leg(eased(u))
	if second then
		return FLIGHT.midScale + (FLIGHT.endScale - FLIGHT.midScale) * k
	end
	return FLIGHT.midScale * k
end

-- A coin's rotation (degrees) at progress u: 0 -> spin at the swing point -> 0 on the pill (lib:281-282).
function CoinFlight.spinAt(u: number, spin: number): number
	local k, second = leg(eased(u))
	return if second then spin * (1 - k) else spin * k
end

-- When each of k coins lands at the shortest flight (no jitter), in seconds after the flight starts: ms, then
-- staggerMs apart.
function CoinFlight.landingTimes(k: number): { number }
	local times = {}
	for i = 1, math.max(0, math.floor(k)) do
		table.insert(times, (FLIGHT.ms + (i - 1) * FLIGHT.staggerMs) / MS)
	end
	return times
end

-- How long the count-up runs (ms) when it starts at the first landing: past the last coin's landing even when it
-- takes jitterMs longer (Config: countTailMs >= jitterMs).
function CoinFlight.countMs(k: number): number
	return math.max(0, math.floor(k) - 1) * FLIGHT.staggerMs + FLIGHT.countTailMs
end

-- Public: runtime ---------------------------------------------------------------------------------------------------

-- Starts a flight (or adds to the running one). Returns false when nothing flies (see the header).
function CoinFlight.play(from: Source, to: GuiObject, amount: number, onLand: OnLand, options: Options?): boolean
	local given = if options then options.count else nil
	if not finite(amount) or (given == nil and amount < FLIGHT.minAmount) or Tweens.reducedMotion() then
		return false
	end
	if typeof(to) ~= "Instance" or not to:IsA("GuiObject") or to.Parent == nil then
		return false
	end
	local start = sourcePoint(from)
	if start == nil then
		return false
	end
	local current = flight
	if current and (current.to ~= to or current.layer.Parent == nil) then
		finish(current)
		current = nil
	end
	local room = if current then FLIGHT.maxCoins - liveCoins(current) else FLIGHT.maxCoins
	local k = math.min(CoinFlight.coinCount(given), room)
	if k <= 0 then
		return false
	end
	if current == nil then
		current = newFlight(to, options)
		if current == nil then
			return false
		end
		flight = current
	end
	local made = current :: Flight
	local now = os.clock()
	local first = math.max(now, made.lastStart + FLIGHT.staggerMs / MS)
	local batch: Batch = { k = k, landed = 0, onLand = onLand }
	for i = 1, k do
		local icon = CoinIcon.new({ name = "Coin" .. i, sizePx = FLIGHT.iconPx, parent = made.layer })
		icon.root.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.root.Visible = false
		local scale: UIScale = Create("UIScale", { Scale = 0, Parent = icon.root })
		local coinStart = first + (i - 1) * FLIGHT.staggerMs / MS
		made.lastStart = coinStart
		local leave = CoinFlight.startPoint(start, rng, made.scale)
		table.insert(made.coins, {
			icon = icon,
			scale = scale,
			from = leave,
			mid = CoinFlight.midPoint(leave, rng, made.scale),
			spin = rng:NextNumber(-FLIGHT.spinDeg, FLIGHT.spinDeg),
			life = CoinFlight.lifeMs(rng) / MS,
			start = coinStart,
			batch = batch,
			landed = false,
		})
	end
	return true
end

-- True while a flight is in the air.
function CoinFlight.isFlying(): boolean
	return flight ~= nil
end

-- Coins in the air (debug and leak checks).
function CoinFlight.liveCount(): number
	local current = flight
	return if current then liveCoins(current) else 0
end

-- Drops the running flight without landing it (leak-check reset; no onLand calls).
function CoinFlight.clear()
	local current = flight
	if current then
		finish(current)
	end
end

return CoinFlight
