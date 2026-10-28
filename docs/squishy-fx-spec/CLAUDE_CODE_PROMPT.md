# Squishy Duels — game-feel & VFX build · master prompt for Claude Code + Roblox Studio

> Paste everything below the line into Claude Code, opened in the repo for the game.
> First, copy this whole spec folder into the repo as `docs/squishy-fx-spec/`: notes.md, the 5 HTML pages, squishy-fx.js, squishy-kit.js and kit/.
> Fill in the **MY PLUGINS** line (Roblox Studio MCP, Rojo, Moon Animator, etc.). If you leave it blank, Claude Code works out what it has.

---

## ROLE
You are a senior Roblox gameplay engineer and technical VFX artist. You ship polished, juicy, cartoon game-feel in Luau, and you work carefully inside an existing game. Exact numbers matter more than vibes: every effect must match the spec to the frame and stay inside the rules.

## GOAL
Implement the complete Squishy Duels game-feel and VFX spec in the live game:
- Part 1 Move: run, jump, short hop, double jump, big fall, dash, power slide.
- Part 2 Hit: normal, charged and ultimate hits, SQUISHED knockout, falling off the map, final knockout.
- Part 3 Duel flight: tap and charged throws, flight, miss bounce and roll, catch.
- Part 4 Highway: wind-up, sound-barrier launch, the 7 zones, impact, exact stop point, fireworks finish.

Then make it even better (see POLISH PASS) without breaking a single rule.

MY PLUGINS: <list them here, e.g. Roblox Studio MCP, Rojo, Moon Animator 2, …>

## SOURCE OF TRUTH
- `docs/squishy-fx-spec/*.html`: each page starts with a `const CONFIG = {…}` object. **That object is the spec.** Every number, colour, easing, particle setting, pose key and timeline event is in it.
  - Ignore the `viewer` and `stage` sections. They are preview-only (stand-in avatar, preview lights, preview props).
- `docs/squishy-fx-spec/notes.md`: the same data as readable timelines, plus how each part maps to Roblox. It is generated from CONFIG; if the two ever disagree, CONFIG wins.
- `squishy-fx.js` is the browser preview engine. Read it to understand exact behaviour (easing, emitter shapes, the trail ribbon, the shake noise, the highway solver), but don't port its rendering.
- Units in CONFIG are already Roblox units: studs, seconds, degrees, studs/s.
- Easing names (`'Quad Out'`) map to `Enum.EasingStyle.Quad` + `Enum.EasingDirection.Out`.

## STEP 0 — TOOLS FIRST (do this before writing any code)
1. List every tool and MCP server you can call. Write a short table: tool → what it can do in Studio (read the Explorer, run Luau, create Instances, read Output, play-test, upload assets, sync files).
2. Pick the workflow:
   - **Studio MCP connected** → work directly in the open place. Prove the connection with a read-only call, e.g. print `game.Name` and the Workspace children count.
   - **Rojo project** → edit files under the Rojo tree and keep the sync running. Never edit synced scripts by hand in Studio.
   - **Animation plugin** (e.g. Moon Animator) → use it only if you need published animations; the default is the procedural pose player below.
   - **Nothing connected** → write the files plus step-by-step instructions for me.
3. Before your first write: save a backup copy of the place, or work on a branch / copy of the place. Tell me where the backup is.

## STEP 1 — AUDIT THE EXISTING GAME (read-only)
Find the code for movement, jump and double jump, dash, slide, throw and charge, squishy projectile, hit detection, lives HUD, catch, knockout and respawn, highway, killcam and zones. Write `docs/fx-audit.md` with:
- Spec signal → where it happens in our code (file, function, event). The spec signals are listed per page in notes.md, e.g. `landHard`, `apex`, `dashEnd`, `offEdge`, `killY`, `bounce1`, `zone`, `stop`.
- Current values for everything the spec marks **KEEP**. They must not change:
  - walk speed 20 lobby / 22 duel; jump height 7.2; dash 18 studs in 0.22 s with a 2 s cooldown; slide 40 → 18 studs/s over 0.7 s;
  - throw speeds, squishy gravity and radius; charge time 1 s; catch burst at 1.02 s; respawn 3 s; highway distance range 70–8,500 and max height 60.
- Spec values that are placeholders in the preview, which you must read from the game instead: highway zone start distances, per-squishy throw speed / gravity / radius / colour, and the double-jump height.
- Existing effects that the spec replaces. Don't delete them; disable them behind a flag.

Stop and show me the audit before Step 2.

## STEP 2 — ARCHITECTURE
```
ReplicatedStorage/SquishyFX/
  Config/            Move, Hit, DuelFlight, Highway, Rules, ReduceMotion, Textures, Sounds
                     (1:1 Luau ports of the CONFIG objects: same names, same numbers, same nesting)
  Shared/            Easing.lua (Roblox easing + NumberSequence/ColorSequence builders), HighwaySolver.lua (exact port of solve()/sample())
  Client/            Sequencer, Particles, Rings, Billboards, Trails, ScreenFX, CameraFX, TimeFX, PosePlayer, SquashStretch, Afterimage, Sound
ReplicatedStorage/Remotes/SquishyFX (RemoteEvent)
StarterPlayerScripts/SquishyFXClient.client.lua
ServerScriptService/SquishyFXServer.server.lua   (thin hooks called from the existing gameplay code)
```
- **Sequencer** — plays a moment exactly like the preview.
  - Events with `t` run from the moment's start.
  - Events with `on: '<signal>'` are queued when the gameplay code fires that signal; `t` is then the offset from the signal.
  - Supports `views` filters (which player's camera sees it), `include` blocks, `group` stops and the `[PC, phone]` count pairs.
- **Server** decides what happened and fires the Remote with: moment id, actors, positions, seed and extra data (e.g. highway distance D). Every client plays the visuals locally. Never replicate particles from the server.

## STEP 3 — ROBLOX IMPLEMENTATION RULES (match the preview behaviour)
- **Particles:**
  - `ParticleEmitter` (Enabled = false) + `:Emit(n)` for bursts; `Rate` for emitters.
  - Build the property values from the CONFIG keys: Lifetime / Speed / Rotation / RotSpeed → NumberRange; Size / Transparency / Squash → NumberSequence; Color → ColorSequence; plus Acceleration, Drag, LightEmission, Orientation, SpreadAngle and Shape / ShapeStyle / ShapeInOut.
  - `Tints` = one emitter per tint, with the count split evenly.
  - `LockedToPart: true` → `LockedToPart = true` on an emitter parented to the moving part.
  - Pool emitters per effect; never `Instance.new` in a hot loop.
- **Rings:** a thin Part (CanCollide/CanQuery/CanTouch off, Transparency 1) with the ring Decal on Top and Bottom. Tween Size and Decal.Transparency. `Follow: true` → weld it to, or CFrame it every frame onto, the anchor.
- **Billboards:** BillboardGui + ImageLabel (kit picture) or TextLabel (FredokaOne, UIStroke in the Stroke colour). Size in studs from the keys. These run in real time, so they keep playing during hit-stop.
- **Trails:** `Trail` between two Attachments whose separation equals `Width`. The rainbow band is 7 attachments 0.6 studs apart across the squishy's local X, with 6 trails between neighbours (FaceCamera off).
- **Screen FX:** one ScreenGui (IgnoreGuiInset, ResetOnSpawn false). Flash, EdgeSplat, SpeedLines, Vignette, SquishedText, Banner, Letterbox, Counter.
  - px values are for a 1080-px-tall screen; scale by `viewport.Y / 1080`.
  - Never cover the screen centre for more than 0.3 s.
- **Highlight** for glows: Roblox renders at most 31 at once, so reuse them and destroy each one when its tween ends.
- **PointLight:** at most one per effect.
- **CameraFX:** `RunService:BindToRenderStep("SquishyFX", Enum.RenderPriority.Camera.Value + 1, …)`, applied on top of the normal camera.
  - Shake = two sines, weights 0.65 / 0.35, second sine at ×1.73 frequency, per-axis weights from CONFIG.
  - FOV kick, punch and dip (`Humanoid.CameraOffset.Y`) all use the in / hold / out envelope.
  - The highway chase / hero camera is Scriptable during the throw, then hands back control.
  - All of it respects Reduce Motion.
- **TimeFX:**
  - Hit-stop runs per client: `AnimationTrack:AdjustSpeed(0)`, anchor the squishy visual, emitter `TimeScale = 0`, then restore. Max 0.12 s.
  - Slow-mo is local and only where `slowMoAllowed` (round decided, or your own highway throw): scale AnimationTracks, emitter TimeScale and scripted motion.
- **PosePlayer (procedural, no uploads):**
  - Every pose in CONFIG is a list of keys `{ t, Easing, Joint = {X,Y,Z}°, RootPos = {x,y,z} }`.
  - Each frame in `RunService.PreSimulation` (after the Animator has written), set `Motor6D.Transform = CFrame.new(RootPos) * CFrame.Angles(rad X, rad Y, rad Z)` for keyed joints only.
  - Blend in/out using FadeIn / FadeOut. Ease with `TweenService:GetValue`, because `Enum.PoseEasingStyle` has no Quad / Sine / Back.
  - Joints a track never keys keep playing the game's own animation. The avatar is never scaled.
- **SquashStretch:** the squishy's visual MeshPart Size = base × (X, Y, Z). Z is the travel axis (`CFrame.lookAt(pos, pos + velocity)`). Spin only around Z.
- **Physics changes** (only these change, all from Part 1 / 2 CONFIG):
  - Fall gravity ×1.6 only while falling: VectorForce on the HumanoidRootPart, mass × gravity × 0.6 downward, only while velocity Y < 0.
  - Fall-speed cap 130.
  - Jump cut: on release, if 0.06 s or more since take-off and still rising, multiply upward velocity by 0.45.
  - Dash speed: front-loaded linear ramp 141.6 → 22 (same 18 studs).
  - Slide: Quad Out curve.
  - Knockback: LinearVelocity on the victim's client for the hold time, then air drag e^(−1.2·t) and a 160 studs/s² ground skid.
- **Highway:** the server sends D. Every client runs the same `HighwaySolver`, so the squishy stops **exactly** at D. Print the stop error; it must be under 0.01 studs.
- **Phone:** use the second number of each pair when `UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled`. Trails last ×0.7.
- **Reduce Motion:** an in-game setting stored as a player attribute. Apply the multipliers from the `reduceMotion` CONFIG.
- **Assets:**
  - Upload the 8 PNGs in `kit/png/` (Asset Manager bulk import, or your upload tool if you have one). Record the ids in `Config/Textures`; effects reference pictures by name.
  - Sounds in the spec are names only. Create `Config/Sounds` with an empty id per name, and list any you couldn't find in our existing sounds.

## HARD RULES (fail any one = not done)
- Particles: ≤ 60 per effect on PC and ≤ 30 on phone.
- Every effect is over within 1.5 s; persistent HUD like the highway counter is the only exception.
- Flash: ≤ 0.1 s at ≤ 30 %, never more than 3 per second.
- The screen centre is never covered for more than 0.3 s.
- In live fights: hit-stop ≤ 0.12 s, shake ≤ 2°, FOV kick ≤ 8°.
- One PointLight per effect.
- No slow-mo in live fights.
- Never block or delay input. The throw leaves on the click.
- Don't change KEEP values. Don't redesign the killcam or lives HUD. Don't scale avatars.

Build `Rules.validate()` in Luau, mirroring the preview's Rules check panel, and run it at startup in Studio.

## STEP 4 — BUILD ORDER & VERIFICATION
Work in this order: Move → Hit → Duel flight → Highway. Commit after each part.
1. **FX Lab:** build a test area or debug ScreenGui that replays every moment from the spec pages on demand, like the preview's moment buttons. Include toggles for Phone, Reduce Motion and 0.25× time.
2. **Measure and print** for every moment, and compare to notes.md:
   - jump height and rise / fall time; dash and slide distance; landing tier and speed;
   - knockback air time and distance; flight bounces and roll;
   - highway plan (flight + bounces + roll) and stop error.
3. **Play-test** in Studio: Play Solo, then a Local Server with 2 players for duels (attacker, victim, observer views). Check the Output for errors.
4. **Performance:** MicroProfiler label `SquishyFX` under 1 ms per frame on the client with 8 players. Check the mobile emulator too.
5. After each part, report: what changed, measured numbers vs spec, any deviation and why, and screenshots if your tools can take them.

## POLISH PASS ("make it way better")
Once everything matches the spec:
1. Write `docs/fx-ideas.md` with up to 10 improvements, each with expected impact. Ideas to consider:
   - per-squishy colour on every jelly, trail and ring;
   - team colours on hits;
   - sound pitch variation (±5 %) on repeated sounds;
   - haptics on phone (HapticService) for hits, landings and catches;
   - a combo-feel pass on consecutive hits;
   - richer zone ambience on the highway.
2. Implement the best ones behind `Config.Flags`, so I can A/B them in the FX Lab.
3. Run `Rules.validate()` again. Nothing may break a hard rule.

## WORKING STYLE
- Small, reviewable changes; one part per commit or PR.
- Ask before deleting anything. Prefer flags over removal.
- Comment only where it isn't obvious. Keep the Config modules the single place for numbers, as in the spec.
- If the spec is ambiguous or conflicts with the existing game, stop and ask. Show me both options with numbers.
