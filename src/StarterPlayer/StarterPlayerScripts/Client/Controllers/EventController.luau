--!strict
-- EventController (client only). 2026-10-31 (owner: candy rain, "Small pill under DUEL", "Yes, build it"): the client
-- side of the timed events (Shared/EventSchedule, Server/Services/EventService).
-- * The pill (Event_Pill): Daily's timer pill (UI/Components/WellPill, Config.UI.Daily.timer, the clock picture) right
--   under the DUEL area (HudController.layoutRects().cta), under the queue pill while that shows; "Candy rain in 8:12",
--   then "CANDY RAIN! 3:41" (EventSchedule.pillText on the server clock, Workspace:GetServerTimeNow()). Only while the
--   HUD and its DUEL area show. Stand-in look until Diego draws one (his to-do).
-- * While candy rain is live and the HUD shows: the waypoint (UI/Waypoint) to the dragon Monument.
-- * The candies (Workspace.SD_Candies): each drops from dropHeight onto its spot until its SD_LandAt (falling faster
--   as it goes), then turns slowly and bobs (still under reduced motion). Local CFrames only: the server's never move.
-- * CandyGrab (the grabber only): the coins fly from the candy's spot into the coin disc (HudController.flyCoins).
-- * The Friend Boost pill (Friend_Pill, 2026-10-31, owner: "Small pill"): the same pill right under the event pill,
--   "Friends +20%" from the local player's SD_FriendBoost (whole percent, FriendsService); only while that is above 0
--   and the event pill shows. 2026-11-01 (restyle part 2): its picture is the Friends icon drawn in Diego's hud-icons
--   style (img.icon.friends), no longer the star.
-- * The group pill (Group_Pill, big job item 4, 2026-11-10) and the Plus pill (Plus_Pill, item 5): the same pill in
--   the same place, "Group +10%" from SD_GroupBoost (PerkService: a member of the game's owner group; the star
--   picture) and "Plus +10%" from SD_PlusBoost (a Roblox Plus subscriber; the bolt picture). Only ONE boost pill shows
--   at a time (three under each other reached the character's head at phone size, seen 2026-11-10): a lone boost's own
--   pill, or Boost_Pill "Boosts +40%" with their sum while two or more are on.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local EVENTS = require(Shared.Config.Events)
local EventSchedule = require(Shared.EventSchedule)
local UpdateClock = require(Shared.UpdateClock)
local Seasons = require(Shared.Seasons) -- big job item 11
local AssetTable = require(Shared.AssetTable)
local SNOW = require(Shared.Config.Christmas).snow
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local MeshQuality = require(Client.Anim.MeshQuality)
local Tweens = require(Client.Anim.Tweens)
local WellPill = require(Client.UI.Components.WellPill)
local Waypoint = require(Client.UI.Waypoint)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local UIController = require(script.Parent.UIController)

-- Constants

local CANDY = EVENTS.CandyRain
local HUD_GUI = "SD_Hud"
local PILL_GAP = 8 -- base px under the DUEL area (or the queue pill)
local PILL_SECONDS = 0.25
local FOLDER_NAME = "SD_Candies"
local ATTR_LAND = "SD_LandAt"
local SPIN_DEG_PER_SECOND = 90
local BOB_STUDS = 0.3
local BOB_SECONDS = 1.6
-- The pen boosts a player can have: the pill's name, the Player attribute with its whole percent, its picture and its
-- text (a Strings.social key with {percent}). TOTAL_PILL is the pill of their sum (see the header).
local BOOSTS: { { name: string, attr: string, icon: string, text: string } } = {
	{ name = "Friend_Pill", attr = "SD_FriendBoost", icon = "img.icon.friends", text = "friendBoost" },
	{ name = "Group_Pill", attr = "SD_GroupBoost", icon = "img.icon.star", text = "groupBoost" },
	{ name = "Plus_Pill", attr = "SD_PlusBoost", icon = "img.icon.bolt", text = "plusBoost" },
}
local TOTAL_PILL = { name = "Boost_Pill", icon = "img.icon.bolt" }

-- Module table

local EventController = {}

-- Private

type Drop = { model: Model, landing: CFrame?, landAt: number }
type Boost = { pill: WellPill.WellPill, attr: string, text: string, percent: number }

local cleanup: Cleanup.Cleanup? = nil
local pill: WellPill.WellPill? = nil
local boosts: { Boost } = {}
local boostPills: { WellPill.WellPill } = {} -- every boost pill and the sum's
local totalPill: WellPill.WellPill? = nil
local shownBoost: WellPill.WellPill? = nil -- the one boost pill to show (nil: no boost is on)
local waypoint: Waypoint.Handle? = nil
local drops: { [Model]: Drop } = {}

local function placePill()
	local current = pill
	if current == nil then
		return
	end
	local rects = HudController.layoutRects()
	local cta = rects.cta
	local root = current.root
	root.Visible = HudController.isShown() and cta ~= nil
	for _, boostPill in boostPills do
		boostPill.root.Visible = root.Visible and boostPill == shownBoost
	end
	if not root.Visible or cta == nil then
		return
	end
	local y = cta.y + cta.h + PILL_GAP
	local gui = UIController.screenGui(HUD_GUI)
	local scale = UIController.scale()
	local queuePill = gui:FindFirstChild("QueuePill", true)
	if queuePill and queuePill:IsA("GuiObject") and queuePill.Visible and scale > 0 then
		local bottom = (queuePill.AbsolutePosition.Y + queuePill.AbsoluteSize.Y - gui.AbsolutePosition.Y) / scale
		y = math.max(y, bottom + PILL_GAP)
	end
	root.Position = UDim2.fromOffset(math.floor(cta.x + cta.w / 2 + 0.5), math.floor(y + 0.5))
	-- The one boost pill right under it.
	local shown = shownBoost
	if shown then
		local below = y + Config.UI.Daily.timer.height + PILL_GAP
		shown.root.Position = UDim2.fromOffset(math.floor(cta.x + cta.w / 2 + 0.5), math.floor(below + 0.5))
	end
end

-- A boost attribute changed (or on start): which boost pill shows and its text (a lone boost's own, or the sum's),
-- then its place and visibility.
local function refreshBoosts()
	local on, sum = 0, 0
	local lone: Boost? = nil
	for _, boost in boosts do
		local value = Players.LocalPlayer:GetAttribute(boost.attr)
		boost.percent = if type(value) == "number" then value else 0
		if boost.percent > 0 then
			on += 1
			sum += boost.percent
			lone = boost
		end
	end
	local total = totalPill
	if on == 1 and lone then
		lone.pill:setText(Strings.format((Strings.social :: any)[lone.text], { percent = lone.percent }))
		shownBoost = lone.pill
	elseif on >= 2 and total then
		total:setText(Strings.format(Strings.social.boostTotal, { percent = sum }))
		shownBoost = total
	else
		shownBoost = nil
	end
	placePill()
end

-- Big job item 11: snow while the Christmas event is on (Config/Christmas.snow): one emitter that follows the camera.
local snow: Part? = nil

local function refreshSnow(t: number)
	local camera = Workspace.CurrentCamera
	local wanted = camera ~= nil
		and Seasons.isOn(Workspace:GetAttribute(Seasons.ATTRIBUTE), t)
		and HudController.isShown()
		and not Tweens.reducedMotion()
		and MeshQuality.forCamera(camera) ~= "Low"
	if wanted and snow == nil then
		local part = Instance.new("Part")
		part.Name = "SD_Snow"
		part.Anchored = true
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.Transparency = 1
		part.Size = Vector3.new(SNOW.areaStuds, 1, SNOW.areaStuds)
		local flakes = Instance.new("ParticleEmitter")
		flakes.Name = "Flakes"
		flakes.Texture = AssetTable.image("img.kit.puff") or ""
		flakes.EmissionDirection = Enum.NormalId.Bottom
		flakes.Rate = SNOW.rate
		flakes.Lifetime = NumberRange.new(SNOW.lifetime[1], SNOW.lifetime[2])
		flakes.Speed = NumberRange.new(SNOW.speed[1], SNOW.speed[2])
		flakes.SpreadAngle = Vector2.new(SNOW.spreadDeg, SNOW.spreadDeg)
		flakes.Acceleration = SNOW.drift
		flakes.Size = NumberSequence.new(SNOW.sizeStuds[1], SNOW.sizeStuds[2])
		flakes.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.1, 0.1),
			NumberSequenceKeypoint.new(0.85, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		flakes.Rotation = NumberRange.new(0, 360)
		flakes.RotSpeed = NumberRange.new(-40, 40)
		flakes.LightInfluence = 0
		flakes.Parent = part
		part.Parent = camera
		snow = part
	elseif not wanted and snow ~= nil then
		snow:Destroy()
		snow = nil
	end
end

local function refresh()
	local current = pill
	local t = Workspace:GetServerTimeNow()
	local state = EventSchedule.at(t)
	if current then
		-- Big job item 8 (2026-11-10): while an update date is set (Workspace SD_NextUpdateAt, from the experience config
		-- next_update) and no event is live, "Update in 2d 05h" takes turns with the event's line (UpdateClock.pill).
		local nextUpdate = Workspace:GetAttribute(UpdateClock.ATTRIBUTE)
		local text = UpdateClock.pill(EventSchedule.pillText(t), state.live, nextUpdate, t)
		-- Big job item 11: while the Christmas event is on, its line takes a few seconds of every turn too.
		current:setText(Seasons.pill(text, state.live, Workspace:GetAttribute(Seasons.ATTRIBUTE), t))
		placePill()
	end
	refreshSnow(t) -- big job item 11
	local wanted = state.live and state.kind == "candyRain" and HudController.isShown()
	if wanted and waypoint == nil then
		waypoint = Waypoint.show(CANDY.centre)
	elseif not wanted and waypoint then
		(waypoint :: Waypoint.Handle):destroy()
		waypoint = nil
	end
end

local function addCandy(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local landAt = child:GetAttribute(ATTR_LAND)
	-- The landing is read once its parts are here (animate): a model can arrive before them (seen on join).
	drops[child] = { model = child, landing = nil, landAt = if type(landAt) == "number" then landAt else 0 }
end

local function animate()
	local t = Workspace:GetServerTimeNow()
	local still = Tweens.reducedMotion()
	local camera = Workspace.CurrentCamera
	if snow and camera then
		snow.Position = camera.CFrame.Position + Vector3.new(0, SNOW.heightStuds, 0)
	end
	for model, drop in drops do
		if model.Parent == nil then
			drops[model] = nil
			continue
		end
		if drop.landing == nil then
			if model.PrimaryPart == nil then
				continue
			end
			drop.landing = model:GetPivot()
		end
		local landing = drop.landing :: CFrame
		local left = drop.landAt - t
		if left > 0 then
			-- Falls faster as it goes: the height left is dropHeight x (1 - progress^2).
			local progress = 1 - math.clamp(left / CANDY.fallSeconds, 0, 1)
			model:PivotTo(landing + Vector3.new(0, CANDY.dropHeight * (1 - progress * progress), 0))
		elseif still then
			model:PivotTo(landing)
		else
			local bob = BOB_STUDS * math.sin(t * 2 * math.pi / BOB_SECONDS)
			model:PivotTo(landing * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.rad(t * SPIN_DEG_PER_SECOND), 0))
		end
	end
end

local function onGrab(raw: unknown)
	if type(raw) ~= "table" then
		return
	end
	local grab = raw :: { [string]: any }
	if type(grab.coins) == "number" and typeof(grab.position) == "Vector3" then
		HudController.flyCoins(grab.position, grab.coins, 1)
	end
end

-- Lifecycle

function EventController.init()
	local c = Cleanup.new()
	cleanup = c
	local made = WellPill.new({
		name = "Event_Pill",
		look = Config.UI.Daily.timer,
		icon = "img.icon.clock",
		parent = UIController.screenGui(HUD_GUI),
	})
	made.root.AnchorPoint = Vector2.new(0.5, 0)
	made.root.Visible = false
	c:add(made)
	pill = made
	local function boostPill(name: string, icon: string): WellPill.WellPill
		local one = WellPill.new({
			name = name,
			look = Config.UI.Daily.timer,
			icon = icon,
			parent = UIController.screenGui(HUD_GUI),
		})
		one.root.AnchorPoint = Vector2.new(0.5, 0)
		one.root.Visible = false
		c:add(one)
		table.insert(boostPills, one)
		return one
	end
	for _, spec in BOOSTS do
		table.insert(boosts, { pill = boostPill(spec.name, spec.icon), attr = spec.attr, text = spec.text, percent = 0 })
		c:add(Players.LocalPlayer:GetAttributeChangedSignal(spec.attr):Connect(refreshBoosts))
	end
	totalPill = boostPill(TOTAL_PILL.name, TOTAL_PILL.icon)
	refreshBoosts()
	c:add(NetController.on("CandyGrab", onGrab))
	c:add(HudController.LayoutChanged:connect(placePill))
	c:add(HudController.VisibilityChanged:connect(refresh))
	local waited = 0
	c:add(RunService.Heartbeat:Connect(function(dt: number)
		waited += dt
		if waited >= PILL_SECONDS then
			waited = 0
			refresh()
		end
	end))
	c:add(RunService.RenderStepped:Connect(animate))
	c:add(function()
		if waypoint then
			waypoint:destroy()
			waypoint = nil
		end
		table.clear(drops)
		if snow then
			snow:Destroy()
			snow = nil
		end
		pill = nil
		table.clear(boosts)
		table.clear(boostPills)
		totalPill, shownBoost = nil, nil
	end)
	task.spawn(function()
		local folder = Workspace:WaitForChild(FOLDER_NAME, 30)
		if folder == nil or cleanup ~= c then
			return
		end
		for _, child in folder:GetChildren() do
			addCandy(child)
		end
		c:add(folder.ChildAdded:Connect(addCandy))
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function EventController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return EventController
