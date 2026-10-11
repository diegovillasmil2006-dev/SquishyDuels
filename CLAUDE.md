# Squishy Duels — Claude Code instructions

Roblox game, place ID `98945316226507`. Team Create place (collaborators: jayyyyy2806, v1bz).
Code is synced into Roblox Studio with **Rojo 7.7.0** (the Studio plugin is the same version).

## How the sync works
- The files in `src/` are the source of truth for code. Edit the files; Rojo pushes every save into Studio.
- Do NOT edit scripts in Studio while Rojo is connected: the next file save overwrites them.
- Start the server from this folder: `rojo serve` (uses port **34873**, set in `default.project.json`).
  Port 34872 belongs to the Steal a Pizza project, so the plugin must be set to 34873 for this game.
- `servePlaceIds` locks the server to this place: Rojo refuses to connect from any other game.

## What Rojo manages
| Studio | Folder |
|---|---|
| ReplicatedStorage.Shared | `src/ReplicatedStorage/Shared` |
| ServerScriptService.Server (the only server Script) | `src/ServerScriptService/Server` |
| ServerStorage.UnitTest | `src/ServerStorage/UnitTest` |
| ServerStorage.SDTools | `src/ServerStorage/SDTools` |
| StarterPlayer.StarterPlayerScripts.Client (the only LocalScript) | `src/StarterPlayer/StarterPlayerScripts/Client` |

Everything else lives only in Studio and is NOT in Rojo: `Workspace` (SD_Lobby), `ServerStorage.SD_Templates`,
`ReplicatedStorage.SD_ShapeLibrary`, Lighting, game settings. Change those through the Roblox Studio MCP tools.

## File naming (Rojo)
- `Name.luau` = ModuleScript, `Name.server.luau` = Script, `Name.client.luau` = LocalScript.
- A script with children is a folder holding `init.luau` / `init.server.luau` / `init.client.luau`.
- A plain folder becomes a Folder. Inside a mapped folder, anything in Studio that has no file gets deleted on sync.

## Tests
`ServerStorage.UnitTest.RunUnitTest(filter?, timeout?, deps?)` runs the cases in `UnitTest/Cases` in Edit mode
(see the header of `src/ServerStorage/UnitTest/RunUnitTest.luau`). Run it with the MCP `execute_luau` tool.

## Design docs
The game spec and UI docs are in `C:\Users\diego\Desktop\ROBLOXSTEALAPIZZA\SQUISHY_DUELS_*.md`.
