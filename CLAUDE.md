# Squishy Duels — Claude Code instructions

Roblox game, place ID `98945316226507`. Team Create place with two co-owners who each prompt their own Claude Code
at the same time: VillasmilGaming (GitHub diegovillasmil2006-dev) and jayyyyy2806 (GitHub jjayx2806).

## How we work
- **Studio is the source of truth.** Edit the game directly in Studio with the Roblox Studio MCP tools. No Rojo.
- **This repo is the snapshot history** of the place, shared on GitHub. Never edit `src/` or `world/` by hand:
  every snapshot overwrites them with what is in Studio.
- The other co-owner may be editing the same place right now. Always `script_read` a script right before you edit it
  (never rely on an older read), and stay inside the area the user asked for.

## Snapshots (after every prompt that changed Studio)
A Stop hook (`tools/snapshot/guard.cjs`) will not let you finish a turn that changed Studio until a snapshot is saved.
Mark purely read-only `execute_luau` calls with `-- readonly` as the first line, so they do not count as changes.
To take a snapshot (Studio must be in Edit mode, not Play):
1. Start the helper **in the background** from the repo root:
   `node tools/snapshot/snap.mjs snapshot "<one line: what changed, in plain English>"`
2. Run the snapshot bootstrap below with `execute_luau` (datamodel `Edit`). It returns the result, e.g.
   `SNAPSHOT SAVED 1a2b3c4 and uploaded to GitHub` or `NO CHANGES`. Tell the user the short result.

```lua
-- readonly (snapshot bootstrap)
local H = game:GetService("HttpService")
local was = H.HttpEnabled
H.HttpEnabled = true
local ok, res = pcall(function()
	local tool
	for _ = 1, 40 do
		local got, body = pcall(function() return H:GetAsync("http://127.0.0.1:34901/tool", true) end)
		if got then tool = body break end
		task.wait(0.5)
	end
	assert(tool, "the snapshot helper is not running")
	return loadstring(tool)()("snapshot")
end)
H.HttpEnabled = was
return if ok then res else "SNAPSHOT FAILED: " .. tostring(res)
```
The bootstrap switches "Allow HTTP Requests" on only while it runs (about a second) and always puts it back.
A snapshot saves: every script under the code folders as text in `src/`, and every other top-level object (map, models,
templates, lighting effects, GUIs) as a `.rbxm` file in `world/` (list in `world/index.json`). It does NOT save terrain
or service settings (Lighting/Workspace properties, game settings): Roblox's own Version History covers those.

## Going back ("undo that", "go back to before X")
1. Run `git log --oneline -20` and show the user the recent snapshots in plain words (who, what). Confirm which one.
2. Take a fresh snapshot first, so the current state can be brought back too.
3. Prepare the files:
   - Undo only one snapshot's changes, keeping everything after it (best when the partner kept working):
     `git revert --no-commit <sha>`
   - Put everything back exactly as it was at a snapshot (also undoes the partner's later work, so say so first):
     `git restore --source=<sha> -- src world`
4. Start `node tools/snapshot/snap.mjs restore` in the background, then run the restore bootstrap below.
5. Take a snapshot with a message like `Undo: <what>` and tell the user what came back.

```lua
-- restore bootstrap
local H = game:GetService("HttpService")
local was = H.HttpEnabled
H.HttpEnabled = true
local ok, res = pcall(function()
	local tool
	for _ = 1, 40 do
		local got, body = pcall(function() return H:GetAsync("http://127.0.0.1:34901/tool", true) end)
		if got then tool = body break end
		task.wait(0.5)
	end
	assert(tool, "the snapshot helper is not running")
	return loadstring(tool)()("restore")
end)
H.HttpEnabled = was
return if ok then res else "RESTORE FAILED: " .. tostring(res)
```
If `git revert` reports a conflict, the same lines changed again later: explain it and ask before forcing anything.

## Code folders (saved to `src/`)
| Studio | Folder |
|---|---|
| ReplicatedStorage.Shared | `src/ReplicatedStorage/Shared` |
| ServerScriptService.Server (the only server Script) | `src/ServerScriptService/Server` |
| ServerStorage.UnitTest | `src/ServerStorage/UnitTest` |
| ServerStorage.SDTools | `src/ServerStorage/SDTools` |
| StarterPlayer.StarterPlayerScripts.Client (the only LocalScript) | `src/StarterPlayer/StarterPlayerScripts/Client` |

File names: `Name.luau` = ModuleScript, `Name.server.luau` = Script, `Name.client.luau` = LocalScript; a script with
children is a folder holding `init*.luau`. Script and folder names must be unique among siblings and contain no dots or
slashes, or the snapshot stops and asks for a rename. Most models (lobby, arena, squishies) are built by scripts:
`ServerStorage.SDTools` builders and `ReplicatedStorage.Shared.Art` blueprints.

## Tests
`ServerStorage.UnitTest.RunUnitTest(filter?, timeout?, deps?)` runs the cases in `UnitTest/Cases` in Edit mode
(see the header of `src/ServerStorage/UnitTest/RunUnitTest.luau`). Run it with `execute_luau`.

## Skills
Load the matching skill with the Skill tool before starting work in its area, once per task (not per edit):

| Skill | Load when |
|---|---|
| `roblox-ui` | any HUD, menu, modal, shop, notification or layout work, and any UI overhaul |
| `game-feel` | button press/pop, coin flights, reward pop-ups, counters ticking, screen shake, hit feedback |
| `roblox-audio` | SoundGroups, mixing, ducking, 3D sound, adding or wiring any sound |
| `sound-effects` | generating a new custom SFX (needs `ELEVENLABS_API_KEY`; upload the result to the group, then add its id) |
| `find-skills` | the task needs know-how none of the above covers; suggest the skill to the user before installing |

The project rules here win over a skill when they disagree:
- UI is built in code from `Client/UI` (`Components`, `Theme`, `Layout`, the `*Format` modules) and
  `Shared/Config/UI`. Ignore `roblox-ui`'s advice to author UI as hand-placed Explorer instances; apply the rest
  (responsive layout, safe insets, touch/gamepad focus, states, device checks).
- Colours stay in `Art/Palette`, layout/motion tokens in `Config/UI`, mix values in `Config/Audio`, and sound ids only
  in `AssetTable.luau`. Never hardcode them in screens or controllers.
- Feedback must not cover the player or the play area; keep the UI readable on phone first.

Missing skills (e.g. on the other co-owner's PC): install with
`npx skills add gamedev-skills/awesome-gamedev-agent-skills --skill roblox-ui --skill game-feel -g -a claude-code -y`,
`npx skills add tabooharmony/roblox-brain --skill roblox-audio -g -a claude-code -y`,
`npx skills add elevenlabs/skills --skill sound-effects -g -a claude-code -y`,
`npx skills add vercel-labs/skills --skill find-skills -g -a claude-code -y`, then start a new chat.

## Design docs
The game spec and UI docs are in `C:\Users\diego\Desktop\ROBLOXSTEALAPIZZA\SQUISHY_DUELS_*.md` (VillasmilGaming's PC).
