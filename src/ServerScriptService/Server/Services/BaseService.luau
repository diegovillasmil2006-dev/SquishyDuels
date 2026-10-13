--!strict
-- BaseService (server only). Lobby bases spec 2026-10-11 §2, §4, §6; build plan Phase 3.
-- The island's 10 plots (WorldLayout.Bases), one per player in the server:
-- * playerAdded: the lowest free plot. It goes to the Player attribute SD_Plot (1..10; clients read it, and the plot's
--   name sign shows the DisplayName of the player whose SD_Plot is that plot: data only until Phase 4 builds the sign).
--   The player spawns on the plot (its SpawnLocation, WorldLayout.Tags.BaseSpawn with the Plot attribute) only once
--   the world has one: Phase 4 builds them, and until then CharacterService's lobby spawn stays (players spawn exactly
--   as today). With no plot free (a player who left is freed on their leave hook, so only briefly, or in a Studio test
--   with more players than plots), it tries again every RETRY_SECONDS for RETRY_FOR_SECONDS while the player waits in
--   the hub; a plot found later is used from their next respawn.
-- * playerRemoving: the plot is free again ("Open plot" in Phase 4). Rejoining gives the lowest free plot again (maybe
--   another one); the capsule levels live in the profile, so they come back wherever the player lands.
-- No remote ever names a plot: CapsuleService asks plotOf(player) for the caller's own plot (the home-tap check).
-- Dependencies are injectable (useDeps) so unit tests run without the world or the task scheduler; a player is only a
-- table key (an Instance also gets the attribute; a Player also gets the spawn). playerAdded / playerRemoving never
-- yield.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local WorldLayout = require(Shared.World.WorldLayout)

local WorldService = require(script.Parent.WorldService)

-- Types

export type Deps = {
	delay: (seconds: number, fn: () -> ()) -> (), -- task.delay
	spawnOf: (plot: number) -> SpawnLocation?, -- the plot's SpawnLocation in the generated world, or nil
}

-- Constants

local PLOT_COUNT = #WorldLayout.Bases.frames
local ATTR_PLOT = "SD_Plot"
local TAG_SPAWN = WorldLayout.Tags.BaseSpawn
local ATTR_SPAWN_PLOT = WorldLayout.Attributes.Plot
local RETRY_FOR_SECONDS = 5 -- lobby spec §6: "it tries again for up to 5 s"
local RETRY_SECONDS = 0.5 -- reading (the spec gives no step)

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
	}
end

local deps: Deps = defaultDeps()

-- Gives the player the lowest free plot (and its spawn, when the world has it). Returns it, or nil when all are taken.
local function assign(player: any): number?
	for plot = 1, PLOT_COUNT do
		if owners[plot] == nil then
			owners[plot] = player
			plots[player] = plot
			if typeof(player) == "Instance" then
				(player :: Instance):SetAttribute(ATTR_PLOT, plot)
				local spawn = deps.spawnOf(plot)
				if spawn and (player :: Instance):IsA("Player") then
					(player :: Player).RespawnLocation = spawn
				end
			end
			return plot
		end
	end
	return nil
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
	end
end

return BaseService
