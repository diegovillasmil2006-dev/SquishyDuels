-- Portal links + cinematic timings. Shared by the server (teleport) and the client (camera).
local Portal = {}

-- false: the practice arena is part of this place (instant, no loading screen).
-- true: teleport to a separate Roblox place. Put PracticeArena in that place and set the ids.
Portal.USE_SEPARATE_PLACE = false
Portal.PRACTICE_PLACE_ID = 0
Portal.LOBBY_PLACE_ID = 0

-- Highway portal. By default the highway is in this place: add an anchored Part named HighwaySpawn where players
-- should land (its LookVector = the way they face). Or set HIGHWAY_PLACE_ID to teleport to a separate highway place.
Portal.HIGHWAY_SPAWN = "HighwaySpawn"
Portal.HIGHWAY_PLACE_ID = 0
-- Any part with this CollectionService tag (e.g. a portal you build on the highway) sends players back to the lobby.
Portal.RETURN_TAG = "SquishyLobbyReturn"

Portal.PullTime = 1.5   -- seconds of "pull-in" camera before the server moves the player (client enter = 0.4 + 1.05 s)
Portal.Cooldown = 4     -- seconds before the same player can use a portal again

-- Sound effects, played only during a portal trip. Paste Roblox audio ids ("rbxassetid://123..."); empty = silent.
-- Keep them soft, quiet and warm: no slide whistles, no squeals, nothing harsh or high-pitched. Creator Store search terms:
--   Start "soft pop" / "bubble soft", Windup "kalimba rise" / "soft pluck arpeggio", Suck "soft whoosh rising" / "airy swoosh",
--   Poof "soft poof" / "gentle sparkle", Spit "soft whoosh pop", Land "soft bounce" / "cute plop", Chime "kalimba chime soft".
-- Every sound is multiplied by SfxVolume. Trim long clips; each one-shot should be under ~1.2 s.
Portal.SfxVolume = 0.35
Portal.Sfx = {
	Start = "", Windup = "", Suck = "", Poof = "", Spit = "", Land = "", Chime = "",
}

Portal.Links = {
	Portal = {
		from = { "Hub", "Portal" }, to = { "PracticeArena", "ReturnPortal" },
		title = "TARGET PRACTICE", subtitle = "Hit the targets!",
		color = Color3.fromHex("c64dff"), placeId = function() return Portal.PRACTICE_PLACE_ID end,
	},
	ReturnPortal = {
		from = { "PracticeArena", "ReturnPortal" }, to = { "Hub", "Portal" },
		title = "SQUISH SQUARE", subtitle = "Welcome back",
		color = Color3.fromHex("3fd8ff"), placeId = function() return Portal.LOBBY_PLACE_ID end,
	},
	HighwayPortal = {
		from = { "Hub", "HighwayPortal" }, spawn = function() return Portal.HIGHWAY_SPAWN end,
		title = "HIGHWAY", subtitle = "Hit the road!",
		color = Color3.fromHex("ff9a3c"), placeId = function() return Portal.HIGHWAY_PLACE_ID end,
	},
	HighwayReturn = { -- no "from": triggered by any part tagged RETURN_TAG
		to = { "Hub", "HighwayPortal" },
		title = "SQUISH SQUARE", subtitle = "Welcome back",
		color = Color3.fromHex("ff9a3c"), placeId = function() return 0 end,
	},
}

return Portal
