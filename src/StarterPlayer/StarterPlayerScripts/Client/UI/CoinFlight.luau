--!strict
-- CoinFlight (client only). DESIGN §18.5.2 B2 ("+N" coin flights, §9.14 "flies into the coin pill"), §18.9 (UI juice
-- frames), §18.1 #2 (one frame loop).
--   CoinFlight.play(from, to, amount, onLand, options?) -> boolean
-- `from` is a GuiObject (its centre when the flight starts), a point in GUI space (AbsolutePosition space) or a world
-- point (Camera:WorldToScreenPoint, which already takes the GUI inset into account); `to` is the coin pill
-- (HudController.coinsAnchor()). k = coinCount(amount) CoinIcons (22 px) arc into `to`: each one flies `ms` (Quad In)
-- along a curve that rises arcPx above the higher end, grows startScale -> 1 over scaleInMs, and leaves staggerMs after
-- the one before. onLand(i, k) runs at each landing (the caller bounces the pill, plays ui.coin and starts its
-- count-up at i == 1, which lasts countMs(k) so it ends with the last coin).
-- At most maxCoins icons and one flight: a second play() adds its coins to the running flight (fewer when the icons
-- would go over maxCoins; its onLand then gets the number actually added). One Scheduler render effect runs it all.
-- Returns false (nothing flies) for amounts under minAmount, under ReducedMotion (the caller sets the number at once),
-- or when no icon fits. A UI module: it never requires a controller (HudController owns every flight).
-- Pure: coinCount, path, progress, scaleAt, landingTimes, countMs (unit-tested in Edit mode).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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
}

type Coin = {
	icon: CoinIcon.CoinIcon,
	scale: UIScale,
	from: Vector2, -- GUI space (AbsolutePosition space)
	start: number, -- os.clock()
	i: number,
	k: number,
	onLand: OnLand,
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
local LAYER_NAME = "SD_CoinFlights"

-- Module table

local CoinFlight = {}

-- Private

local log = Log.new("CoinFlight")
local flight: Flight? = nil

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
	local ok, err = pcall(function(): any
		coin.onLand(coin.i, coin.k)
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
			if elapsed >= FLIGHT.ms / MS then
				land(coin)
			else
				alive = true
				local root = coin.icon.root
				root.Visible = elapsed >= 0
				if elapsed >= 0 then
					local at = CoinFlight.path(CoinFlight.progress(elapsed), coin.from, target)
					local localPoint = (at - origin) / current.scale
					root.Position = UDim2.fromOffset(localPoint.X, localPoint.Y)
					coin.scale.Scale = CoinFlight.scaleAt(elapsed)
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

-- How many coins fly for `amount`: clamp(round(amount / coinsPer), minCoins, maxCoins).
function CoinFlight.coinCount(amount: number): number
	if not finite(amount) or amount <= 0 then
		return FLIGHT.minCoins
	end
	return math.clamp(math.floor(amount / FLIGHT.coinsPer + 0.5), FLIGHT.minCoins, FLIGHT.maxCoins)
end

-- The point at flight progress u (0..1) from `from` to `to`, both in GUI space: a quadratic curve whose control point
-- sits arcPx above the higher end, halfway across, so the coin always rises above both ends and drops into the pill.
-- Reading: DESIGN says "arcs 120 px upward"; measuring from the higher end keeps the arc visible when the pill is above
-- the source.
function CoinFlight.path(u: number, from: Vector2, to: Vector2, arcPx: number?): Vector2
	local t = if finite(u) then math.clamp(u, 0, 1) else 1
	local arc = arcPx or FLIGHT.arcPx
	local control = Vector2.new((from.X + to.X) / 2, math.min(from.Y, to.Y) - arc)
	local a, b, c = (1 - t) * (1 - t), 2 * t * (1 - t), t * t
	return from * a + control * b + to * c
end

-- Flight progress `elapsed` seconds after a coin leaves: Quad In over `ms` (0 before, 1 after).
function CoinFlight.progress(elapsed: number): number
	local duration = FLIGHT.ms / MS
	if not finite(elapsed) or elapsed <= 0 then
		return 0
	elseif elapsed >= duration then
		return 1
	end
	return TweenService:GetValue(elapsed / duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

-- A coin's scale `elapsed` seconds after it leaves: startScale -> 1 over scaleInMs (reading: Quad Out).
function CoinFlight.scaleAt(elapsed: number): number
	local duration = FLIGHT.scaleInMs / MS
	if not finite(elapsed) or elapsed <= 0 then
		return FLIGHT.startScale
	elseif elapsed >= duration then
		return 1
	end
	local alpha = TweenService:GetValue(elapsed / duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return FLIGHT.startScale + (1 - FLIGHT.startScale) * alpha
end

-- When each of k coins lands, in seconds after the flight starts: ms, then staggerMs apart.
function CoinFlight.landingTimes(k: number): { number }
	local times = {}
	for i = 1, math.max(0, math.floor(k)) do
		table.insert(times, (FLIGHT.ms + (i - 1) * FLIGHT.staggerMs) / MS)
	end
	return times
end

-- How long the count-up runs (ms) when it starts at the first landing: it ends with the last coin's tail.
function CoinFlight.countMs(k: number): number
	return math.max(0, math.floor(k) - 1) * FLIGHT.staggerMs + FLIGHT.countTailMs
end

-- Public: runtime ---------------------------------------------------------------------------------------------------

-- Starts a flight (or adds to the running one). Returns false when nothing flies (see the header).
function CoinFlight.play(from: Source, to: GuiObject, amount: number, onLand: OnLand, options: Options?): boolean
	if not finite(amount) or amount < FLIGHT.minAmount or Tweens.reducedMotion() then
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
	local k = math.min(CoinFlight.coinCount(amount), room)
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
	for i = 1, k do
		local icon = CoinIcon.new({ name = "Coin" .. i, sizePx = FLIGHT.iconPx, parent = made.layer })
		icon.root.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.root.Visible = false
		local scale: UIScale = Create("UIScale", { Scale = FLIGHT.startScale, Parent = icon.root })
		local coinStart = first + (i - 1) * FLIGHT.staggerMs / MS
		made.lastStart = coinStart
		table.insert(made.coins, {
			icon = icon,
			scale = scale,
			from = start,
			start = coinStart,
			i = i,
			k = k,
			onLand = onLand,
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
