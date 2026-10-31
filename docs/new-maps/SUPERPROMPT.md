# Superprompt: Squishy Duels map replacement (for Claude Opus 5.5)

Copy everything below the line into Claude, and attach this whole `export/` folder.

---

You are a senior Roblox engineer working in Luau on my game **Squishy Duels**, a cute, blocky, first-person throwing shooter. Your job is to **replace every old map in the game** with the 11 new maps described in this package and wire them into the existing game flow **without breaking anything**. Work carefully, logically and defensively. Ship zero bugs.

## What is in this package
- `maps.json`: the source of truth. All 11 maps, fully expanded (symmetry already applied), in studs:
  - `modes.tdm`: T1 Cookie Counter, T2 Fluff Cycle, T3 Crayon Canyon, T4 Shelf Life (6v6, pink team `spawnA` vs blue team `spawnB`)
  - `modes.ffa`: F1 Teatime Terrace, F2 Cupcake Carousel, F3 Puzzle Plaza, F4 Dollhouse Drop (12 players, 12 `spawn` pads)
  - `modes.duel`: D1 Pencil Case, D2 Piano Keys, D3 Lunchbox (1v1, `spawnA` vs `spawnB`)
  - each map has: `size {W,H}`, `theme` colors, `deco` (sky prop kind, ambient particle kind, palette), `elements[]`, `botRoutes[]`
  - `constants`: deck height, wall height, cover height, outline color/thickness, player physics, pad and spawn colors, sky gradient
- `reference-demos/`: the playable browser demos (open the `.dc.html` files next to `support.js` in a browser). **They are the visual and gameplay reference. Match them.** `shots/thumbs/` holds real screenshots.
- `roblox-assets/outline-meshes/`: the inverted-hull meshes (`HullBox`, `HullCylinder`, `HullSphere`) used for the thick black outlines.
- `roblox-assets/old-reference/`: an older builder and FX script for the first TDM pass. Reuse its patterns (outline hulls, anchoring, folders, FX loop) but **do not trust its geometry or colors**; `maps.json` overrides it.

## Element spec (`maps.json` → `elements[]`)
Coordinates: `x` = west→east, `z` = north→south, `w` = size on X, `d` = size on Z. Floor top is local Y = 0. Every element is a rectangle; `round: true` means a cylinder of diameter `w`.
- `zone`: a flat colored floor decal/plate (no collision), color `theme.zone`.
- `spawn` / `spawnA` / `spawnB`: spawn plate. FFA uses `spawn` (12 per map). TDM and Duel use `spawnA` (pink) and `spawnB` (blue).
- `wall`: height `height` or `WALL_H` (16). Color `theme.wall`, plus a cap on top (1.4 tall, 0.25 overhang, color `theme.cap`). Round walls are cylinders with the cute face (eyes, blush, mouth) facing the nearest side, as in the demo.
- `cover`: height `COVER_H` (4), color `theme.cover`.
- `deck`: L2 platform whose top is at `DECK_H` (10).
  - `solid: true` → a full block from 0 to 10.
  - Otherwise a 1.6-thick slab at 8.4–10 on square posts around the edge (post size min(3, 30% of side), one post every ~26 studs). Players can walk underneath.
  - `round: true` → a cylinder deck. `spin: true` (F2 carousel) rotates slowly; players standing on it must ride it smoothly.
- `stair`: 6 steps rising from 0 to `DECK_H`. `stairUp` is the direction it climbs toward (`n` = toward −Z, `s` = +Z, `e` = +X, `w` = −X). Add an invisible smooth wedge collider under the steps so movement never snags.
- `level: 2`: the element sits on top of a deck (base Y = 10).
- `pad`: power pickup, cylinder r = 3. `power` is `MegaMochi` (pink, always on L2) or `SugarRush` (yellow, ground). It has a floating gem, a light beam and a ring. Hide the gem and beam while the pad recharges.
- `botRoutes`: ordered waypoints at ground level for bots/NPCs. Store them as invisible parts `Route_<n>_<i>`.

## Art direction (must match the demos)
- **Blocky Roblox look with black outlines.** Every structure is a box with a stud texture: a 4×4-stud two-tone checker (white / #d4d4d4 tinted by the part color) with an inset square per stud. Use the `HullBox`/`HullCylinder`/`HullSphere` meshes for thick #1c1530 outlines (0.32 studs). If a hull is missing, fall back to `Highlight` with OutlineColor #1c1530 and FillTransparency 1.
- Floors: `theme.floor` with a 4-stud checker in `theme.grid`, a stud inset per stud, and a thick ink border. Make it a SurfaceAppearance/Texture or tiled Decal, not thousands of parts.
- Keep the **exact theme colors** in `maps.json`. Do not recolor the maps.
- Animations must stay smooth and never shake collision. Only decorative pieces animate: round props squish gently, pads bob and spin, rim bulbs twinkle, flags wave, sky props float, ambient particles drift. Walls, cover, decks and stairs are static and anchored.
- No cloud bed under the platforms. The floating sky clouds stay.

## Sky arenas (required)
- Every map floats **high in the sky** (platform floor at Y ≈ 300 or higher), surrounded by the animated skybox from the demo:
  - a blue gradient sky (top #2f8fe6, horizon #8fcdf7, low #dff1ff)
  - ~34 drifting blocky white clouds at varied heights around and below the arena
  - the themed floating sky props from `deco.sky` (cookie, bubble, crayon, book), slowly floating and rotating
  - ambient particles from `deco.amb` (sprinkles, bubbles, confetti, paper)
  - the rim fence with string lights. TDM and Duel also get team bunting behind each spawn.
- Add 120-stud-tall invisible walls at the platform edge, plus a kill/respawn volume below the platform in case anyone falls.

## Server flow: one map per server (required)
- Each map runs in **its own server**. Whenever a player goes to a different map (map vote, queue, "play again" on another map, mode switch), **teleport them to a new server** for that map with `TeleportService`.
  - Preferred: one match place. The lobby calls `TeleportService:ReserveServer` for each new match and then `TeleportAsync` with `TeleportOptions` (`ReservedServerAccessCode`) and `TeleportData = { mode = "tdm"|"ffa"|"duel", mapId = "T1"…, matchId }`.
  - The match server reads the data with `player:GetJoinData().TeleportData` (validate it on the server and never trust the client). It builds or clones only that map from ServerStorage, then starts the round.
  - Party/queue members must land in the same reserved server. Wrap teleports in retries with `TeleportInitFailed` handling and a fallback back to the lobby.
  - When a match ends, return players to the lobby or a fresh reserved server. Never load two maps in one server.
- Remove every old map, old map references, old spawn logic and old vote entries. Update the map vote and selection lists to exactly these 11 maps, grouped by mode, using the names and subtitles in `maps.json`.

## HUD and existing systems
- **Use the game's current HUDs and UI exactly as they are.** Do not redesign them, rename them or create duplicate UI. Hook the new maps into the existing scoreboard, kill feed, timer, health bar, ability cooldowns (Q / E dash / Space jump), power-pad indicators, map vote and end screen.
- Score limits: TDM and FFA keep their current settings. Duel is 1v1, first to 10 by default.
- Spawns: TDM and Duel pick a random free spawn of the player's team. FFA picks the `spawn` pad farthest from living enemies, with brief spawn protection.
- Power pads must work with the existing power-up code via the `PowerType` attribute (`MegaMochi` / `SugarRush`).

## Engineering rules
1. Read the existing codebase first and list every place maps are referenced (spawning, vote, teleport, round manager, bots, analytics, saved data). Plan the change before editing.
2. Build the maps with one data-driven builder module (`MapBuilder`) that reads a Luau copy of `maps.json` (`MapData` ModuleScript). Never hand-place geometry. Output one Model per map with the folders `Floor`, `Structures`, `Colliders`, `InvisibleWalls`, `Spawns`, `Pads`, `Routes`, `Decor`, `Sky`, `Ambient`.
3. Do all structural work on the server. Run purely visual animation in one client LocalScript (`MapFX`) that picks up whatever map is present. Use `RunService.RenderStepped` with delta time, no `while wait()` loops.
4. Anchor everything static. Set `CanCollide`, `CanQuery` and `CanTouch` deliberately; decor never collides. Use `CollisionFidelity = Box` for boxes, and make sure no two colliders overlap so nothing shakes.
5. Performance: use instancing and tiled textures over part spam, and stream decor where sensible. Keep each map under ~2,500 parts and verify 60 fps on mid-range mobile.
6. Validate after building. Assert that every map has the right spawn count (TDM 6+6 plates, FFA 12, Duel 1+1), that every stair top meets its deck edge, that every route waypoint is reachable, and that no element is out of bounds. Print a clear report.
7. Test every map in a local multi-client server (Studio → Test → 2–12 players): spawning, teleport in and out, pads, stairs, spinning deck, falling off the edge, the end screen and returning to the lobby.
8. Deliver: the new/changed scripts with file paths, a short migration note listing what was removed, and step-by-step publish instructions (places, permissions, `TeleportService` settings).

If anything in the existing code conflicts with these instructions, stop and ask me before changing it, rather than guessing.
