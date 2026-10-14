--!strict
-- BaseService (server only). Lobby bases spec 2026-10-11 §2, §4, §6, §8; build plan Phases 3 and 4.
-- The island's 10 plots (WorldLayout.Bases), one per player in the server:
-- * playerAdded: the lowest free plot. It goes to the Player attribute SD_Plot (1..10; clients read it) and the
--   plot's name sign shows the player's DisplayName (the owner view below). The player spawns on the plot (its
--   SpawnLocation, WorldLayout.Tags.BaseSpawn with the Plot attribute) once the world has one (Squish Island, Phase 4);
--   without it CharacterService's lobby spawn stays. With no plot free (a player who left is freed on their leave
--   hook, so only briefly, or in a Studio test with more players than plots), it tries again every RETRY_SECONDS for
--   RETRY_FOR_SECONDS while the player waits in the hub; a plot found later is used from their next respawn.
-- * Batch 3 (friends, review #6): a player who joined from a friend's invite (GetJoinData().ReferredByPlayerId) or
--   followed a friend in (Player.FollowUserId) while that friend has a plot here gets the free plot nearest to the
--   friend's on the ring (min(|i - p|, 10 - |i - p|); a tie takes the lower number) instead of the lowest one.
-- * playerRemoving: the plot is free again ("Open plot", grey, no capsules). Rejoining gives the lowest free plot again
--   (maybe another one); the capsule levels live in the profile, so they come back wherever the player lands.
-- * The owner view (Phase 4, spec §4, §8): render(plot) shows on the plot's generated Model (Tags.Base with that Plot)
--   who owns it. The name sign's live "Owner" label reads the owner's DisplayName, or Strings base.openPlot; every part
--   with SD_BaseTint ("full" / "light") takes the plot's colour (WorldLayout.Bases.colors) while it has an owner and the
--   open grey (Bases.openColors) otherwise; a "Capsules" Folder, replaced on every render, holds per slot 1..4 either
--   the owner's open capsule (a clone of ServerStorage.SD_Templates.Capsules.Capsule_<its tier's look> on the slot's
--   capsule spot, its Level label base.capsuleLevel) with its squishy (Squishy_<id>) on the seat (the template's
--   SD_SeatY), or a locked slot (the Lock, its Price label base.unlockPrice with the slot's price), and capsule 1's
--   squishy as the statue (Statue_<id>) on the back wall's plinth. Each clone carries SD_Template (its template's name);
--   Phase 5: each capsule also SD_Level and SD_Squishy (none when empty), so every client can show its read-only card
--   and play its upgrade burst (Controllers/CapsuleController).
--   A plot renders when it is handed out or freed, when its owner's profile loads (the data port's Loaded) and on
--   refresh(player) after a capsule change (CapsuleService). Until the profile is ready a plot shows its owner's name
--   and colour only; without the generated plot or the templates nothing is drawn and nothing fails.
-- No remote ever names a plot: CapsuleService asks plotOf(player) for the caller's own plot (the home-tap check).
-- Dependencies are injectable (useDeps) so unit tests run without the world or the task scheduler; a player is only a
-- table key (an Instance also gets the attribute; a Player also gets the spawn). playerAdded / playerRemoving never
-- yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Deps = {
	delay: (seconds: number, fn: () -> ()) -> (), -- task.delay
	spawnOf: (plot: number) -> SpawnLocation?, -- the plot's SpawnLocation in the generated world, or nil
	plotModel: (plot: number) -> Instance?, -- the plot's generated Model, or nil
	templates: () -> Instance?, -- ServerStorage.SD_Templates.Capsules (SDTools target "capsules"), or nil
	capsulesOf: (player: any) -> any, -- the capsules ({slots, list}) of the player's READY profile, or nil
	displayNameOf: (player: any) -> string,
	friendOf: (player: any) -> any?, -- Batch 3: the friend in this server who invited the player (or was followed)
}

-- Constants

local PLOT_COUNT = #WorldLayout.Bases.frames
local ATTR_PLOT = "SD_Plot"
local TAG_SPAWN = WorldLayout.Tags.BaseSpawn
local ATTR_SPAWN_PLOT = WorldLayout.Attributes.Plot
local RETRY_FOR_SECONDS = 5 -- lobby spec §6: "it tries again for up to 5 s"
local RETRY_SECONDS = 0.5 -- reading (the spec gives no step)
local TAG_BASE = WorldLayout.Tags.Base
local ATTR_TINT = WorldLayout.Attributes.BaseTint
local TEMPLATES_FOLDER = "SD_Templates"
local CAPSULES_FOLDER = "Capsules" -- the templates' folder, and the runtime folder on each plot
local OWNER_LABEL = "Owner"
local ATTR_SEAT = "SD_SeatY"
local ATTR_TEMPLATE = "SD_Template"
local ATTR_LEVEL = "SD_Level"
local ATTR_SQUISHY = "SD_Squishy"

-- Module table

local BaseService = {}

-- Private

local log = Log.new("Base")
local owners: { [number]: any } = {} -- plot -> player
local plots: { [any]: number } = {} -- player -> plot
local waiting: { [any]: boolean } = {} -- players with no plot yet, still retrying

local function defaultDeps(): Deps
	return {
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		spawnOf = function(plot: number): SpawnLocation?
			for _, instance in WorldService.stations(TAG_SPAWN) do
				if instance:IsA("SpawnLocation") and instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		plotModel = function(plot: number): Instance?
			for _, instance in WorldService.stations(TAG_BASE) do
				if instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		templates = function(): Instance?
			local holder = ServerStorage:FindFirstChild(TEMPLATES_FOLDER)
			return if holder then holder:FindFirstChild(CAPSULES_FOLDER) else nil
		end,
		capsulesOf = function(player: any): any
			local port = StateService.dataPort()
			if port.status(player) ~= "ready" then
				return nil
			end
			local profile = port.getProfile(player)
			return if type(profile) == "table" then profile.capsules else nil
		end,
		displayNameOf = function(player: any): string
			local ok, name = pcall(function(): any
				return player.DisplayName
			end)
			return if ok and type(name) == "string" then name else tostring(player)
		end,
		friendOf = function(player: any): any?
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return nil
			end
			local ok, data = pcall(player.GetJoinData, player) -- never yields
			local id = if ok and type(data) == "table" then (data :: any).ReferredByPlayerId else nil
			if type(id) ~= "number" or id <= 0 then
				id = player.FollowUserId
			end
			return if type(id) == "number" and id > 0 then Players:GetPlayerByUserId(id) else nil
		end,
	}
end

local deps: Deps = defaultDeps()

-- A clone of the template `name` (a Model under `templates`) pivoted to `cframe` in `parent`, named `as`; nil when the
-- template is missing.
local function place(templates: Instance, name: string, parent: Instance, as: string, cframe: CFrame): Model?
	local template = templates:FindFirstChild(name)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local copy = template:Clone()
	copy.Name = as
	copy:SetAttribute(ATTR_TEMPLATE, name)
	copy:PivotTo(cframe)
	copy.Parent = parent
	return copy
end

-- Writes `text` into the TextLabel `name` somewhere under `model`.
local function setLabel(model: Instance, name: string, text: string)
	local label = model:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- The owner's capsules on the plot (see the header): a fresh "Capsules" Folder, or none.
local function drawCapsules(model: Instance, plot: number, capsules: any, templates: Instance)
	local folder = Instance.new("Folder")
	folder.Name = CAPSULES_FOLDER
	local frame = WorldLayout.plotFrame(plot) :: CFrame
	local slots = if type(capsules.slots) == "number" then capsules.slots else 1
	local list = if type(capsules.list) == "table" then capsules.list else {}
	for slot, spot in WorldLayout.Bases.capsuleSpots do
		local at = frame * spot
		local capsule = if slot <= slots then list[slot] else nil
		local tier = if type(capsule) == "table" then CapsuleMath.tier(capsule.level) else nil
		if tier ~= nil then
			local look = Config.Grip.Capsule.Tiers[tier].key
			local shown = place(templates, "Capsule_" .. look, folder, "Capsule" .. slot, at)
			if shown then
				local level = Strings.format(Strings.resolve("base.capsuleLevel") or "", { level = capsule.level })
				setLabel(shown, "Level", level)
				shown:SetAttribute(ATTR_LEVEL, capsule.level)
				if Catalog.isValidId(capsule.squishyId) then
					shown:SetAttribute(ATTR_SQUISHY, capsule.squishyId)
					local seat = shown:GetAttribute(ATTR_SEAT)
					local lift = if type(seat) == "number" then seat else 0
					place(
						templates,
						"Squishy_" .. capsule.squishyId,
						folder,
						"Squishy" .. slot,
						at * CFrame.new(0, lift, 0)
					)
				end
			end
		else
			local lock = place(templates, "Lock", folder, "Lock" .. slot, at)
			local price = CapsuleMath.slotPrice(slot)
			if lock and price then
				setLabel(
					lock,
					"Price",
					Strings.format(Strings.resolve("base.unlockPrice") or "", { coins = Format.coins(price) })
				)
			end
		end
	end
	local first = list[1]
	if type(first) == "table" and Catalog.isValidId(first.squishyId) then
		place(templates, "Statue_" .. first.squishyId, folder, "Statue", frame * WorldLayout.Bases.statue)
	end
	folder.Parent = model
end

-- Shows the plot's owner on its generated Model, or an open plot (see the header). Never throws.
local function render(plot: number)
	local ok, err = pcall(function(): any
		local model = deps.plotModel(plot)
		if model == nil then
			return nil
		end
		local owner = owners[plot]
		local colors = if owner ~= nil then WorldLayout.Bases.colors[plot] else WorldLayout.Bases.openColors
		for _, part in model:GetDescendants() do
			local which = part:GetAttribute(ATTR_TINT)
			if part:IsA("BasePart") and (which == "full" or which == "light") then
				part.Color = Palette[colors[which]]
			end
		end
		local name = if owner ~= nil then deps.displayNameOf(owner) else Strings.resolve("base.openPlot") or ""
		setLabel(model, OWNER_LABEL, name)
		local old = model:FindFirstChild(CAPSULES_FOLDER)
		if old then
			old:Destroy()
		end
		local capsules = if owner ~= nil then deps.capsulesOf(owner) else nil
		local templates = deps.templates()
		if type(capsules) == "table" and templates ~= nil then
			drawCapsules(model, plot, capsules, templates)
		end
		return nil
	end)
	if not ok then
		log:warn(`could not draw plot {plot}:`, err)
	end
end

-- The free plot for the player: the one nearest their friend's plot on the ring (Batch 3; a tie takes the lower
-- number), else the lowest free one; nil when all are taken.
local function freePlot(player: any): number?
	local friend = deps.friendOf(player)
	local near = if friend ~= nil then plots[friend] else nil
	local best, bestGap = nil, math.huge
	for plot = 1, PLOT_COUNT do
		if owners[plot] == nil then
			if near == nil then
				return plot
			end
			local gap = math.abs(plot - near)
			gap = math.min(gap, PLOT_COUNT - gap)
			if gap < bestGap then
				best, bestGap = plot, gap
			end
		end
	end
	return best
end

-- Gives the player a free plot (freePlot, and its spawn, when the world has it). Returns it, or nil when all are taken.
local function assign(player: any): number?
	local plot = freePlot(player)
	if plot == nil then
		return nil
	end
	owners[plot] = player
	plots[player] = plot
	if typeof(player) == "Instance" then
		(player :: Instance):SetAttribute(ATTR_PLOT, plot)
		local spawn = deps.spawnOf(plot)
		if spawn and (player :: Instance):IsA("Player") then
			(player :: Player).RespawnLocation = spawn
		end
	end
	render(plot)
	return plot
end

-- Public

-- The player's plot (1..10), or nil while they have none.
function BaseService.plotOf(player: any): number?
	return plots[player]
end

-- The player on plot `plot`, or nil for an open plot.
function BaseService.ownerOf(plot: number): any?
	return owners[plot]
end

-- Redraws the player's plot (their profile loaded, or their capsules changed). Nothing for a player without a plot.
function BaseService.refresh(player: any)
	local plot = plots[player]
	if plot ~= nil then
		render(plot)
	end
end

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function BaseService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Frees every plot and stops every retry (tests; not called by the bootstrap).
function BaseService.reset()
	table.clear(owners)
	table.clear(plots)
	table.clear(waiting)
end

-- Lifecycle

function BaseService.init()
	StateService.dataPort().onLoaded(function(player: any)
		BaseService.refresh(player)
	end)
end

function BaseService.playerAdded(player: Player)
	if plots[player] ~= nil or assign(player) ~= nil then
		return
	end
	waiting[player] = true
	local triesLeft = math.floor(RETRY_FOR_SECONDS / RETRY_SECONDS)
	local function retry()
		if not waiting[player] then
			return -- left (or reset) meanwhile
		end
		triesLeft -= 1
		if assign(player) ~= nil then
			waiting[player] = nil
		elseif triesLeft <= 0 then
			waiting[player] = nil
			log:warn(`no free plot for {tostring(player)} after {RETRY_FOR_SECONDS} s; they stay in the hub`)
		else
			deps.delay(RETRY_SECONDS, retry)
		end
	end
	deps.delay(RETRY_SECONDS, retry)
end

function BaseService.playerRemoving(player: Player)
	waiting[player] = nil
	local plot = plots[player]
	if plot ~= nil then
		plots[player] = nil
		owners[plot] = nil
		render(plot)
	end
end

return BaseService
