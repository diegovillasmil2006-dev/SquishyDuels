--!strict
-- LobbyFxController (client only). Diego's FULL FINAL lobby zip (owner 2026-10-30, "Yes, start step 2"): starts his
-- HubFX on this client, as his HubFX.client.luau does (zip src/client/HubFX.client.luau:1-4): the hub props, the three
-- portals, the practice arena's targets and dummies, and the candy dome move with BulkMoveTo, timed by
-- workspace:GetServerTimeNow() so every client shows the same pose; plus his sparkles, lights, beams, fountain jets and
-- black outlines. Shared/SquishyLobby/HubFX and HubFXSpec are his files as delivered. Nothing here touches the server.
-- The place streams (StreamingEnabled), so the three models HubFX moves are Persistent (his README: Hub, PracticeArena,
-- Enclosure): each arrives whole and never streams out; start waits for them, since HubFX reads their parts once.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local HubFX = require(ReplicatedStorage.Shared.SquishyLobby.HubFX)

-- Constants

local LOBBY_NAME = "SquishyDuelsLobby"
local MOVED_MODELS = { "Hub", "Enclosure", "PracticeArena" } -- Persistent in the place

-- Module table

local LobbyFxController = {}

-- Public

function LobbyFxController.start()
	local lobby = Workspace:WaitForChild(LOBBY_NAME)
	for _, name in MOVED_MODELS do
		lobby:WaitForChild(name)
	end
	HubFX.start(lobby)
end

return LobbyFxController
