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
-- * The Friend Boost pill (Friend_Pill, 2026-10-31, owner: "Small pill"): the same pill with the star picture right
--   under the event pill, "Friends +20%" from the local player's SD_FriendBoost (whole percent, FriendsService); only
--   while that is above 0 and the event pill shows. Stand-in look until Diego draws one (his to-do).

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
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
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
local ATTR_FRIEND_BOOST = "SD_FriendBoost"

-- Module table

local EventController = {}

-- Private

type Drop = { model: Model, landing: CFrame?, landAt: number }

local cleanup: Cleanup.Cleanup? = nil
local pill: WellPill.WellPill? = nil
local friendPill: WellPill.WellPill? = nil
local friendPercent = 0
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
	local friends = friendPill
	if friends then
		friends.root.Visible = root.Visible and friendPercent > 0
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
	if friends then
		local below = y + Config.UI.Daily.timer.height + PILL_GAP
		friends.root.Position = UDim2.fromOffset(math.floor(cta.x + cta.w / 2 + 0.5), math.floor(below + 0.5))
	end
end

-- SD_FriendBoost changed (or on start): the Friend Boost pill's text, then its place and visibility.
local function refreshFriends()
	local value = Players.LocalPlayer:GetAttribute(ATTR_FRIEND_BOOST)
	friendPercent = if type(value) == "number" then value else 0
	local friends = friendPill
	if friends and friendPercent > 0 then
		friends:setText(Strings.format(Strings.social.friendBoost, { percent = friendPercent }))
	end
	placePill()
end

local function refresh()
	local current = pill
	local t = Workspace:GetServerTimeNow()
	if current then
		current:setText(EventSchedule.pillText(t))
		placePill()
	end
	local state = EventSchedule.at(t)
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
	local friends = WellPill.new({
		name = "Friend_Pill",
		look = Config.UI.Daily.timer,
		icon = "img.icon.star",
		parent = UIController.screenGui(HUD_GUI),
	})
	friends.root.AnchorPoint = Vector2.new(0.5, 0)
	friends.root.Visible = false
	c:add(friends)
	friendPill = friends
	c:add(Players.LocalPlayer:GetAttributeChangedSignal(ATTR_FRIEND_BOOST):Connect(refreshFriends))
	refreshFriends()
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
		pill = nil
		friendPill = nil
		friendPercent = 0
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
