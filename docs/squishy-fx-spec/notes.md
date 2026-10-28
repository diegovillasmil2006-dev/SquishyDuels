# Squishy Duels — game-feel & VFX timelines

Generated from the `CONFIG` object at the top of each page, so these numbers match the previews exactly. Change a value in a page's CONFIG and regenerate/re-read; the page's on-screen timeline always shows the live values.

**Units** studs · seconds · degrees · studs/s · studs/s². **t** = real seconds from the moment's start (t = 0.00 is the input / impact). Lines that start with a signal name (e.g. `t = land + 0.00 s`) fire relative to that game event. Pairs like `×10 (phone 5)` are [PC, phone].

## How each part maps to Roblox

- **burst** → `ParticleEmitter` (Enabled = false) + `:Emit(Count)`. Texture = kit PNG; Lifetime / Speed = NumberRange; size / transparency keys are NumberSequence (`time:value`, time 0–1 of life); colour = ColorSequence; accel = Acceleration; drag = Drag (speed halves every 1/Drag s); rot / spin = Rotation / RotSpeed; light = LightEmission; Squash and Orientation as named. Shapes: no shape = emitter in an Attachment aimed with EmissionDirection = Top; Box = default box emitter on a Part of that size; Sphere / Cylinder = Shape + ShapeStyle Surface + ShapeInOut Outward (or Inward). **Tints** = one emitter per tint, Count split evenly (Roblox colours every particle of one emitter the same).
- **emitter** → same ParticleEmitter with Rate, Enabled for the listed time (or while the squishy flies).
- **ring** → thin Part (N × 0.05 × N, Transparency 1, CanCollide off) with the ring Decal on Top + Bottom; TweenService on Size and Decal.Transparency with the named EasingStyle/Direction.
- **billboard** → BillboardGui + ImageLabel (kit picture), size tweened through the keys (`seconds:studs`), runs in real time so it reads during hit-stop.
- **trail** → `Trail` between two Attachments `width` apart (FaceCamera on unless noted), Lifetime, Color, Transparency, WidthScale, LightEmission.
- **screen flash / text / splat / speed lines** → ScreenGui Frames / TextLabel / ImageLabels; px values are for a 1080-px-tall screen (scale with the viewport). Flash = BackgroundTransparency 1 − opacity; max 0.1 s at 30 %, never more than 3 per second; the centre is never covered for more than 0.3 s.
- **Highlight** → `Highlight` on the character / squishy, FillTransparency and OutlineTransparency tweened to 1.
- **PointLight** → one per effect, Brightness tweened to 0.
- **camera shake** → RenderStepped: `Camera.CFrame *= CFrame.Angles(pitch, yaw, roll)`, amplitude × (1 − ease(t / Time)) × two-sine noise (weights 0.65 / 0.35, second sine at 1.73 × Frequency), per-axis weights as listed. Max 2° in live fights.
- **FOV kick** → tween `Camera.FieldOfView` by the delta (in / hold / out). Max 8° in live fights.
- **camera punch** → camera-space CFrame offset + rotation on the same in / hold / out envelope.
- **camera dip** → `Humanoid.CameraOffset.Y = −Depth × envelope`.
- **hit-stop** → for Time seconds on each client: `AnimationTrack:AdjustSpeed(0)` on the involved tracks, squishy anchored, live emitters TimeScale 0. The victim's own client anchors its HumanoidRootPart, then applies the knockback when the freeze ends. Max 0.12 s.
- **slow-mo** → only when the round is decided or on your own highway throw: local AnimationTrack speeds, ParticleEmitter.TimeScale and scripted motion × Speed.
- **pose** → an Animation (priority Action) whose keys set `Pose.CFrame = CFrame.Angles(rad X, rad Y, rad Z)` per R15 joint (XYZ order) plus a Root translation (`RootPos`). A key's easing is the curve to the next key. Keys are never ≥ 180° apart, so Roblox's interpolation keeps flips spinning the right way. Joints a track never keys keep playing the game's own animation. The avatar body is never scaled.
- **squash/stretch** → the squishy's visual MeshPart Size = base × (X, Y, Z). Z = travel axis (`CFrame.lookAt(pos, pos + velocity)`), Y = up / contact normal; spin only around Z so it never fights the stretch.
- **sound** → name and time only.

- **LockedToPart / Follow** → `ParticleEmitter.LockedToPart = true` on an emitter in the squishy; rings and billboards marked “follows” are welded / adorned to the squishy.
- **text billboard** → BillboardGui + TextLabel (Fredoka Bold, UIStroke) on the squishy, height in studs.
- **banner / letterbox / HUD counter** → ScreenGui TextLabel / two Frames / TextLabel; positions are fractions of the screen height and always clear of the centre.
- **rainbow band** → 7 Attachments 0.6 studs apart across the squishy, 6 Trails between neighbours (FaceCamera off) = a flat rainbow ribbon.

**Reduce motion**: shake ×0, slow-mo off, FOV kicks ×0.25, punches ×0, dips ×0.35, speed lines ×0.5, flashes ×0.5. **Phone**: second number of every pair; trails last ×0.7.


---

## Part 1 · Move (`move.html`)

Run, jump, short hop, double jump, big fall, dash and power slide. Lobby = 3rd person, duels = 1st person.

**Signals:** `step` — run animation “Footstep” marker (preview: every 0.31 s); `stop` — running stops; `apex` — vertical speed crosses 0 (full jump ≈ 0.27 s); `double` — second jump press; `fall` — feet leave a ledge without jumping; `fastFall` — falling faster than 75 studs/s; `land` + tier `landSoft` / `landNormal` / `landHard` — touchdown; tier from landing speed (< 55 soft, 55–90 normal, ≥ 90 hard). Preview: full jump ≈ 0.49 s at 67 studs/s (normal), short hop ≈ 0.31 s at 48 (soft), double jump ≈ 0.81 s at 95 (hard), 28-stud ledge ≈ 0.62 s at 130 (hard); `dashEnd` — 0.22 s after the dash starts; `slideEnd` — 0.70 s after the slide starts.

**Kept:** walk 20 (lobby) / 22 (duel) studs/s, jump 7.2 studs, dash 18 studs in 0.22 s, 2 s cooldown, slide 40 → 18 studs/s over 0.7 s. **New:** gravity ×1.6 only while falling (rise unchanged, take-off 53.15 studs/s), fall cap 130 studs/s, early release keeps ×0.45 of the upward speed (not before 0.06 s), dash speed 141.6 → 22 studs/s linear (same 18 studs), slide curve Quad Out.



### Run start

_3rd person · lobby · 1st person · duel_ — Kick-off puff and a forward lean layered on top of the run animation (Waist only, so the run cycle keeps playing). Step puffs fire on the run animation’s “Footstep” markers. 1st person: no camera effect, aim stays steady.

- t = 0.00 s: motion: run at walk speed (lobby 20 / duel 22) for 1.1 s
- t = 0.00 s: pose **runLean** → player (2 R15 keys, 0.25 s, fade in 0.04 s, holds last key)
- t = 0.00 s: burst **runKickPuff** @ backFoot → backUp: puff ×5 (phone 3), life 0.3–0.42 s, speed 7–11, spread 25/25°, size 0:0.6 · 0.35:1.3 · 1:0.3, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 6, rot 0–360°, spin -90–90°/s
- t = 0.00 s: sound “run_start_scuff”
- t = step + 0.00 s: burst **stepPuff** @ stepFoot → up: puff ×2 (phone 1), life 0.22–0.32 s, speed 2–4, spread 40/40°, size 0:0.35 · 0.4:0.8 · 1:0.2, colour #FFF4E6, transp 0:0.3 · 1:1, accel (0, 4, 0), drag 5, rot 0–360°, spin -60–60°/s
- t = step + 0.00 s: sound “footstep_soft”
- t = stop + 0.00 s: pose **runSettle** → player (3 R15 keys, 0.24 s, fade in 0.02 s, fade out 0.1 s)

### Jump (held)

_3rd person · lobby · 1st person · duel_ — Full jump, still 7.2 studs high. Extra gravity only on the way down: 0.27 s up, 0.21 s down (was 0.27 s). Landing effects pick a tier from the landing speed.

- t = 0.00 s: motion: jump, button held 0.5 s
- t = 0.00 s: pose **jumpRise** → player (2 R15 keys, 0.14 s, fade in 0.05 s, holds last key)
- t = 0.00 s: burst **takeoffPuff** @ feet → up: puff ×10 (phone 5), life 0.3–0.45 s, speed 10–15, spread 8/8°, Cylinder r 0.7, size 0:0.7 · 0.35:1.5 · 1:0.2, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = 0.00 s: sound “jump_hop”
- t = apex + 0.00 s: pose **jumpFall** → player (1 R15 keys, 0 s, fade in 0.12 s, holds last key)
- t = landSoft + 0.00 s: burst **landPuffSoft** @ feet → up: puff ×6 (phone 3), life 0.25–0.35 s, speed 6–9, spread 8/8°, Cylinder r 0.6, size 0:0.5 · 0.35:1 · 1:0.2, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landSoft + 0.00 s: pose **landSoft** → player (2 R15 keys, 0.1 s, fade in 0.02 s, fade out 0.1 s)
- t = landSoft + 0.00 s: camera dip **landDipSoft**: 0.15 studs, down 0.04 s Sine Out, hold 0 s, up 0.12 s Quad Out
- t = landSoft + 0.00 s: sound “land_soft_tap”
- t = landNormal + 0.00 s: burst **landPuffNormal** @ feet → up: puff ×12 (phone 6), life 0.3–0.45 s, speed 11–16, spread 8/8°, Cylinder r 0.8, size 0:0.8 · 0.35:1.7 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landNormal + 0.00 s: ring **landRingNormal** @ feet facing up: ring #FFFFFF, 1.5 → 6 studs in 0.22 s Quad Out, transparency 0.4 → 1 Quad In
- t = landNormal + 0.00 s: pose **landNormal** → player (3 R15 keys, 0.22 s, fade in 0.02 s, fade out 0.12 s)
- t = landNormal + 0.00 s: camera dip **landDipNormal**: 0.45 studs, down 0.05 s Sine Out, hold 0 s, up 0.2 s Quad Out
- t = landNormal + 0.00 s: sound “land_squish”
- t = landHard + 0.00 s: burst **landPuffHard** @ feet → up: puff ×20 (phone 10), life 0.35–0.55 s, speed 18–28, spread 10/10°, Cylinder r 1, size 0:1.1 · 0.35:2.4 · 1:0.4, colour #FFF4E6, transp 0:0 · 0.7:0.3 · 1:1, accel (0, 14, 0), drag 6, rot 0–360°, spin -120–120°/s
- t = landHard + 0.00 s: burst **landStarsHard** @ feet → up: star ×6 (phone 3), life 0.35–0.5 s, speed 12–20, spread 45/45°, size 0:0.8 · 0.7:0.7 · 1:0, colour #FFD86B, transp 0, accel (0, -70, 0), drag 1, rot 0–360°, spin -300–300°/s, light 0.2
- t = landHard + 0.00 s: ring **landRingHard** @ feet facing up: ring #FFFFFF, 2 → 11 studs in 0.3 s Quad Out, transparency 0.1 → 1 Quad In
- t = landHard + 0.00 s: pose **landHard** → player (3 R15 keys, 0.34 s, fade in 0.02 s, fade out 0.14 s)
- t = landHard + 0.00 s: camera dip **landDipHard**: 1.1 studs, down 0.06 s Quad Out, hold 0.02 s, up 0.3 s Back Out
- t = landHard + 0.00 s: camera shake **landShakeHard**: 0.8°, 0.18 s, 20 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.4/0.3
- t = landHard + 0.00 s: sound “land_heavy_boing”
- t = landHard + 0.00 s: text billboard **boingText** “BOING!” @ feet: #FFD86B with #3B2A35 outline, +(0, 2.5, 0) studs, size (s:studs) 0:0 · 0.08:2.2 · 0.14:1.8 · 0.4:1.9 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(3rd person · lobby only)_

### Short hop (tap)

_3rd person · lobby · 1st person · duel_ — Release early → upward speed × 0.45 (never before 0.06 s). ≈ 3.7-stud hop, soft landing tier.

- t = 0.00 s: motion: jump, released after 0.03 s → cut at 0.06 s
- t = 0.00 s: pose **jumpRise** → player (2 R15 keys, 0.14 s, fade in 0.05 s, holds last key)
- t = 0.00 s: burst **takeoffPuff** @ feet → up: puff ×10 (phone 5), life 0.3–0.45 s, speed 10–15, spread 8/8°, Cylinder r 0.7, size 0:0.7 · 0.35:1.5 · 1:0.2, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = 0.00 s: sound “jump_hop”
- t = apex + 0.00 s: pose **jumpFall** → player (1 R15 keys, 0 s, fade in 0.12 s, holds last key)
- t = landSoft + 0.00 s: burst **landPuffSoft** @ feet → up: puff ×6 (phone 3), life 0.25–0.35 s, speed 6–9, spread 8/8°, Cylinder r 0.6, size 0:0.5 · 0.35:1 · 1:0.2, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landSoft + 0.00 s: pose **landSoft** → player (2 R15 keys, 0.1 s, fade in 0.02 s, fade out 0.1 s)
- t = landSoft + 0.00 s: camera dip **landDipSoft**: 0.15 studs, down 0.04 s Sine Out, hold 0 s, up 0.12 s Quad Out
- t = landSoft + 0.00 s: sound “land_soft_tap”
- t = landNormal + 0.00 s: burst **landPuffNormal** @ feet → up: puff ×12 (phone 6), life 0.3–0.45 s, speed 11–16, spread 8/8°, Cylinder r 0.8, size 0:0.8 · 0.35:1.7 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landNormal + 0.00 s: ring **landRingNormal** @ feet facing up: ring #FFFFFF, 1.5 → 6 studs in 0.22 s Quad Out, transparency 0.4 → 1 Quad In
- t = landNormal + 0.00 s: pose **landNormal** → player (3 R15 keys, 0.22 s, fade in 0.02 s, fade out 0.12 s)
- t = landNormal + 0.00 s: camera dip **landDipNormal**: 0.45 studs, down 0.05 s Sine Out, hold 0 s, up 0.2 s Quad Out
- t = landNormal + 0.00 s: sound “land_squish”
- t = landHard + 0.00 s: burst **landPuffHard** @ feet → up: puff ×20 (phone 10), life 0.35–0.55 s, speed 18–28, spread 10/10°, Cylinder r 1, size 0:1.1 · 0.35:2.4 · 1:0.4, colour #FFF4E6, transp 0:0 · 0.7:0.3 · 1:1, accel (0, 14, 0), drag 6, rot 0–360°, spin -120–120°/s
- t = landHard + 0.00 s: burst **landStarsHard** @ feet → up: star ×6 (phone 3), life 0.35–0.5 s, speed 12–20, spread 45/45°, size 0:0.8 · 0.7:0.7 · 1:0, colour #FFD86B, transp 0, accel (0, -70, 0), drag 1, rot 0–360°, spin -300–300°/s, light 0.2
- t = landHard + 0.00 s: ring **landRingHard** @ feet facing up: ring #FFFFFF, 2 → 11 studs in 0.3 s Quad Out, transparency 0.1 → 1 Quad In
- t = landHard + 0.00 s: pose **landHard** → player (3 R15 keys, 0.34 s, fade in 0.02 s, fade out 0.14 s)
- t = landHard + 0.00 s: camera dip **landDipHard**: 1.1 studs, down 0.06 s Quad Out, hold 0.02 s, up 0.3 s Back Out
- t = landHard + 0.00 s: camera shake **landShakeHard**: 0.8°, 0.18 s, 20 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.4/0.3
- t = landHard + 0.00 s: sound “land_heavy_boing”
- t = landHard + 0.00 s: text billboard **boingText** “BOING!” @ feet: #FFD86B with #3B2A35 outline, +(0, 2.5, 0) studs, size (s:studs) 0:0 · 0.08:2.2 · 0.14:1.8 · 0.4:1.9 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(3rd person · lobby only)_

### Double jump

_3rd person · lobby · 1st person · duel_ — Second press near the top: a fast forward flip on the Root joint (camera never flips in 1st person), star burst downward, ring under the feet.

- t = 0.00 s: motion: jump, second press at 0.24 s
- t = 0.00 s: pose **jumpRise** → player (2 R15 keys, 0.14 s, fade in 0.05 s, holds last key)
- t = 0.00 s: burst **takeoffPuff** @ feet → up: puff ×10 (phone 5), life 0.3–0.45 s, speed 10–15, spread 8/8°, Cylinder r 0.7, size 0:0.7 · 0.35:1.5 · 1:0.2, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = 0.00 s: sound “jump_hop”
- t = apex + 0.00 s: pose **jumpFall** → player (1 R15 keys, 0 s, fade in 0.12 s, holds last key)
- t = double + 0.00 s: pose **doubleFlip** → player (5 R15 keys, 0.26 s, fade in 0.03 s, fade out 0.1 s)
- t = double + 0.00 s: burst **doubleStars** @ feet → down: star ×12 (phone 6), life 0.35–0.55 s, speed 16–26, spread 60/60°, size 0:1 · 0.6:0.8 · 1:0, colour 0:#FFFFFF · 0.25:#FFD86B · 1:#FFD86B, transp 0:0 · 0.75:0 · 1:1, accel (0, -50, 0), drag 3, rot 0–360°, spin -270–270°/s, light 0.2
- t = double + 0.00 s: burst **doublePuff** @ feet → down: puff ×8 (phone 4), life 0.3–0.45 s, speed 10–16, spread 35/35°, size 0:0.9 · 0.3:1.8 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.4 · 1:1, accel (0, 12, 0), drag 6, rot 0–360°, spin -120–120°/s
- t = double + 0.00 s: burst **doubleSparkles** @ chest: sparkle ×10 (phone 5), life 0.25–0.4 s, speed 4–9, spread 180/180°, Sphere r 1.4, size 0:0 · 0.25:1.1 · 1:0, colour #FFFFFF, transp 0, drag 2, rot 0–45°, spin -90–90°/s, light 0.7
- t = double + 0.00 s: ring **doubleRing** @ feet facing up: ring #8CC8FF, 1.5 → 8 studs in 0.28 s Quad Out, transparency 0.05 → 1 Quad In
- t = double + 0.00 s: FOV kick **doubleFov**: +3°, in 0.05 s Quad Out, hold 0 s, out 0.25 s Sine InOut _(1st person · duel only)_
- t = double + 0.00 s: sound “double_jump_pop”
- t = double + 0.00 s: ring **doubleHalo** @ chest facing up (follows): ring #FFD86B, 1.5 → 7 studs in 0.3 s Quad Out, transparency 0 → 1 Quad In
- t = double + 0.00 s: emitter **flipStreak** @ chest for 0.26 s: sparkle ×50 (phone 25)/s, life 0.2–0.3 s, speed 2–4, spread 180/180°, Sphere r 1.6, size 0:0.6 · 1:0, colour #FFFFFF, transp 0, rot 0–45°, spin -90–90°/s, light 0.7
- t = landSoft + 0.00 s: burst **landPuffSoft** @ feet → up: puff ×6 (phone 3), life 0.25–0.35 s, speed 6–9, spread 8/8°, Cylinder r 0.6, size 0:0.5 · 0.35:1 · 1:0.2, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landSoft + 0.00 s: pose **landSoft** → player (2 R15 keys, 0.1 s, fade in 0.02 s, fade out 0.1 s)
- t = landSoft + 0.00 s: camera dip **landDipSoft**: 0.15 studs, down 0.04 s Sine Out, hold 0 s, up 0.12 s Quad Out
- t = landSoft + 0.00 s: sound “land_soft_tap”
- t = landNormal + 0.00 s: burst **landPuffNormal** @ feet → up: puff ×12 (phone 6), life 0.3–0.45 s, speed 11–16, spread 8/8°, Cylinder r 0.8, size 0:0.8 · 0.35:1.7 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landNormal + 0.00 s: ring **landRingNormal** @ feet facing up: ring #FFFFFF, 1.5 → 6 studs in 0.22 s Quad Out, transparency 0.4 → 1 Quad In
- t = landNormal + 0.00 s: pose **landNormal** → player (3 R15 keys, 0.22 s, fade in 0.02 s, fade out 0.12 s)
- t = landNormal + 0.00 s: camera dip **landDipNormal**: 0.45 studs, down 0.05 s Sine Out, hold 0 s, up 0.2 s Quad Out
- t = landNormal + 0.00 s: sound “land_squish”
- t = landHard + 0.00 s: burst **landPuffHard** @ feet → up: puff ×20 (phone 10), life 0.35–0.55 s, speed 18–28, spread 10/10°, Cylinder r 1, size 0:1.1 · 0.35:2.4 · 1:0.4, colour #FFF4E6, transp 0:0 · 0.7:0.3 · 1:1, accel (0, 14, 0), drag 6, rot 0–360°, spin -120–120°/s
- t = landHard + 0.00 s: burst **landStarsHard** @ feet → up: star ×6 (phone 3), life 0.35–0.5 s, speed 12–20, spread 45/45°, size 0:0.8 · 0.7:0.7 · 1:0, colour #FFD86B, transp 0, accel (0, -70, 0), drag 1, rot 0–360°, spin -300–300°/s, light 0.2
- t = landHard + 0.00 s: ring **landRingHard** @ feet facing up: ring #FFFFFF, 2 → 11 studs in 0.3 s Quad Out, transparency 0.1 → 1 Quad In
- t = landHard + 0.00 s: pose **landHard** → player (3 R15 keys, 0.34 s, fade in 0.02 s, fade out 0.14 s)
- t = landHard + 0.00 s: camera dip **landDipHard**: 1.1 studs, down 0.06 s Quad Out, hold 0.02 s, up 0.3 s Back Out
- t = landHard + 0.00 s: camera shake **landShakeHard**: 0.8°, 0.18 s, 20 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.4/0.3
- t = landHard + 0.00 s: sound “land_heavy_boing”
- t = landHard + 0.00 s: text billboard **boingText** “BOING!” @ feet: #FFD86B with #3B2A35 outline, +(0, 2.5, 0) studs, size (s:studs) 0:0 · 0.08:2.2 · 0.14:1.8 · 0.4:1.9 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(3rd person · lobby only)_

### Big fall + hard landing

_3rd person · lobby · 1st person · duel_ — Walk off a 28-stud ledge. Fall speed caps at 130 studs/s; wind streaks from 75 studs/s. Hard tier: big puff ring, stars, deep dip with a springy return.

- t = 0.00 s: motion: walk off the ledge
- t = fall + 0.00 s: pose **fallFlail** → player (3 R15 keys, 0.3 s, fade in 0.1 s, holds last key)
- t = fall + 0.00 s: sound “fall_whistle”
- t = fastFall + 0.00 s: emitter **fallWind** @ chest → up for 0.6 s: speedline ×30 (phone 15)/s, life 0.12–0.2 s, speed 40–60, spread 4/4°, Box 5×6×5, size 0:0.5 · 1:0.4, colour #FFFFFF, transp 0:0.4 · 1:1, light 0.3, VelocityParallel, squash 1.6
- t = fastFall + 0.00 s: speed lines **fallLines**: speedline #FFFFFF ×12 (phone 6) between 62–100 % of the half-diagonal (centre clear), 160–280 px long, 0.3 s, opacity 0.6 _(1st person · duel only)_
- t = land + 0.00 s: stop fallWind
- t = landSoft + 0.00 s: burst **landPuffSoft** @ feet → up: puff ×6 (phone 3), life 0.25–0.35 s, speed 6–9, spread 8/8°, Cylinder r 0.6, size 0:0.5 · 0.35:1 · 1:0.2, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landSoft + 0.00 s: pose **landSoft** → player (2 R15 keys, 0.1 s, fade in 0.02 s, fade out 0.1 s)
- t = landSoft + 0.00 s: camera dip **landDipSoft**: 0.15 studs, down 0.04 s Sine Out, hold 0 s, up 0.12 s Quad Out
- t = landSoft + 0.00 s: sound “land_soft_tap”
- t = landNormal + 0.00 s: burst **landPuffNormal** @ feet → up: puff ×12 (phone 6), life 0.3–0.45 s, speed 11–16, spread 8/8°, Cylinder r 0.8, size 0:0.8 · 0.35:1.7 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = landNormal + 0.00 s: ring **landRingNormal** @ feet facing up: ring #FFFFFF, 1.5 → 6 studs in 0.22 s Quad Out, transparency 0.4 → 1 Quad In
- t = landNormal + 0.00 s: pose **landNormal** → player (3 R15 keys, 0.22 s, fade in 0.02 s, fade out 0.12 s)
- t = landNormal + 0.00 s: camera dip **landDipNormal**: 0.45 studs, down 0.05 s Sine Out, hold 0 s, up 0.2 s Quad Out
- t = landNormal + 0.00 s: sound “land_squish”
- t = landHard + 0.00 s: burst **landPuffHard** @ feet → up: puff ×20 (phone 10), life 0.35–0.55 s, speed 18–28, spread 10/10°, Cylinder r 1, size 0:1.1 · 0.35:2.4 · 1:0.4, colour #FFF4E6, transp 0:0 · 0.7:0.3 · 1:1, accel (0, 14, 0), drag 6, rot 0–360°, spin -120–120°/s
- t = landHard + 0.00 s: burst **landStarsHard** @ feet → up: star ×6 (phone 3), life 0.35–0.5 s, speed 12–20, spread 45/45°, size 0:0.8 · 0.7:0.7 · 1:0, colour #FFD86B, transp 0, accel (0, -70, 0), drag 1, rot 0–360°, spin -300–300°/s, light 0.2
- t = landHard + 0.00 s: ring **landRingHard** @ feet facing up: ring #FFFFFF, 2 → 11 studs in 0.3 s Quad Out, transparency 0.1 → 1 Quad In
- t = landHard + 0.00 s: pose **landHard** → player (3 R15 keys, 0.34 s, fade in 0.02 s, fade out 0.14 s)
- t = landHard + 0.00 s: camera dip **landDipHard**: 1.1 studs, down 0.06 s Quad Out, hold 0.02 s, up 0.3 s Back Out
- t = landHard + 0.00 s: camera shake **landShakeHard**: 0.8°, 0.18 s, 20 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.4/0.3
- t = landHard + 0.00 s: sound “land_heavy_boing”
- t = landHard + 0.00 s: text billboard **boingText** “BOING!” @ feet: #FFD86B with #3B2A35 outline, +(0, 2.5, 0) studs, size (s:studs) 0:0 · 0.08:2.2 · 0.14:1.8 · 0.4:1.9 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(3rd person · lobby only)_

### Dash (duel)

_1st person · duel · 3rd person · lobby · lead-in 0.3 s_ — Same 18 studs in 0.22 s, but front-loaded: 141.6 → 22 studs/s so it pops and blends into the run. 1st person = your view; 3rd person = what the opponent sees (ribbons + afterimages).

- t = 0.00 s: motion: dash 18 studs / 0.22 s
- t = 0.00 s: pose **dashPose** → player (2 R15 keys, 0.2 s, fade in 0.03 s, fade out 0.14 s)
- t = 0.00 s: afterimage **dashAfterimage** → player: ×3 (phone 2) every 0.06 s, #8CC8FF, transparency 0.5 → 1 over 0.24 s Quad In
- t = 0.00 s: trail **dashRibbon** @ leftShoulder for 0.22 s: width 0.9, life 0.28 s, colour 0:#8CC8FF · 1:#B9A6E8, transp 0:0.2 · 1:1, width scale 0:1 · 1:0.15
- t = 0.00 s: trail **dashRibbon** @ rightShoulder for 0.22 s: width 0.9, life 0.28 s, colour 0:#8CC8FF · 1:#B9A6E8, transp 0:0.2 · 1:1, width scale 0:1 · 1:0.15
- t = 0.00 s: burst **dashPuffStart** @ feet → back: puff ×6 (phone 3), life 0.25–0.4 s, speed 8–12, spread 30/30°, size 0:0.7 · 0.35:1.4 · 1:0.2, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 6, 0), drag 6, rot 0–360°, spin -90–90°/s
- t = 0.00 s: FOV kick **dashFov**: +7°, in 0.06 s Quad Out, hold 0.08 s, out 0.3 s Sine InOut _(1st person · duel only)_
- t = 0.00 s: speed lines **dashLines**: speedline #FFFFFF ×14 (phone 7) between 60–100 % of the half-diagonal (centre clear), 150–260 px long, 0.28 s, opacity 0.7 _(1st person · duel only)_
- t = 0.00 s: sound “dash_whoosh”
- t = 0.00 s: ring **dashShock** @ chest facing back: ring #8CC8FF, 2 → 9 studs in 0.25 s Quad Out, transparency 0.05 → 1 Quad In
- t = 0.00 s: emitter **dashSparks** @ chest → back for 0.22 s: speedline ×60 (phone 30)/s, life 0.1–0.16 s, speed 30–45, spread 6/6°, Box 3×5×1, size 0:0.5 · 1:0.4, colour #FFFFFF, transp 0:0.3 · 1:1, light 0.5, VelocityParallel, squash 1.4, **LockedToPart**
- t = dashEnd + 0.00 s: burst **dashPuffEnd** @ feet → up: puff ×5 (phone 3), life 0.25–0.35 s, speed 6–10, spread 8/8°, Cylinder r 0.6, size 0:0.5 · 0.35:1.1 · 1:0.2, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = dashEnd + 0.00 s: sound “dash_stop”

### Power slide (lobby)

_3rd person · lobby · lead-in 0.35 s_ — Lobby only. 40 → 18 studs/s over 0.7 s with a Quad Out curve. Low baseball-slide pose, dust + sprinkle spray from the lead foot, flat streak on the floor, camera drops and widens.

- t = 0.00 s: motion: slide 40 → 18 studs/s, 0.7 s
- t = 0.00 s: pose **slidePose** → player (3 R15 keys, 0.7 s, fade in 0.06 s, fade out 0.14 s)
- t = 0.00 s: burst **slideStartPuff** @ feet → up: puff ×10 (phone 5), life 0.3–0.45 s, speed 10–15, spread 8/8°, Cylinder r 0.8, size 0:0.8 · 0.35:1.6 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = 0.00 s: emitter **slideDust** @ leadFoot → backUp for 0.6 s: puff ×40 (phone 20)/s, life 0.3–0.45 s, speed 3–7, spread 30/30°, size 0:0.6 · 0.35:1.4 · 1:0.3, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 4, rot 0–360°, spin -90–90°/s
- t = 0.00 s: emitter **slideSprinkles** @ leadFoot → backUp for 0.45 s: confetti ×24 (phone 12)/s, life 0.35–0.6 s, speed 10–16, spread 30/30°, size 0.32, tints #FF8FB1 / #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1, rot 0–360°, spin -420–420°/s
- t = 0.00 s: trail **slideStreak** @ slideGround for 0.7 s: width 1, life 0.35 s, colour #FFF4E6, transp 0:0.35 · 1:1, width scale 0:1 · 1:0.5, flat (FaceCamera off)
- t = 0.00 s: FOV kick **slideFov**: +6°, in 0.08 s Quad Out, hold 0.25 s, out 0.4 s Sine InOut
- t = 0.00 s: camera dip **slideCamDrop**: 1.2 studs, down 0.12 s Quad Out, hold 0.4 s, up 0.3 s Quad InOut
- t = 0.00 s: camera shake **slideRumble**: 0.25°, 0.6 s, 26 Hz, decay Linear, axes pitch/yaw/roll 1/0.5/0.2
- t = 0.00 s: sound “slide_start_swish”
- t = 0.00 s: sound “slide_scrape_loop”
- t = slideEnd + 0.00 s: burst **dashPuffEnd** @ feet → up: puff ×5 (phone 3), life 0.25–0.35 s, speed 6–10, spread 8/8°, Cylinder r 0.6, size 0:0.5 · 0.35:1.1 · 1:0.2, colour #FFF4E6, transp 0:0.15 · 0.7:0.45 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = slideEnd + 0.00 s: sound “slide_end_pop”

#### Part 1 · Move — R15 pose keys

Per key: `t (easing to next): Joint X,Y,Z°`. Joints a track keys somewhere but a key omits are 0,0,0. RootPos is a Root translation in studs (character space, −Z = forward).

- **runLean** (fade in 0.04 s)
  - 0.00 s (Cubic Out): Waist -12,0,0
  - 0.25 s: Waist -6,0,0
- **runSettle** (fade in 0.02 s) (fade out 0.1 s)
  - 0.00 s (Cubic Out): Waist -6,0,0
  - 0.12 s (Cubic InOut): Waist 4,0,0
  - 0.24 s: rest (all keyed joints 0,0,0)
- **jumpRise** (fade in 0.05 s)
  - 0.00 s (Cubic Out): Neck 8,0,0 · Waist -4,0,0 · LeftShoulder 150,0,-18 · RightShoulder 150,0,18 · LeftElbow 15,0,0 · RightElbow 15,0,0 · LeftHip 60,0,0 · LeftKnee -85,0,0 · RightHip -12,0,0 · RightKnee -25,0,0 · RightAnkle -20,0,0
  - 0.14 s: LeftShoulder 120,0,-35 · RightShoulder 120,0,35 · LeftElbow 25,0,0 · RightElbow 25,0,0 · LeftHip 50,0,0 · LeftKnee -75,0,0 · RightHip 25,0,0 · RightKnee -55,0,0
- **jumpFall** (fade in 0.12 s)
  - 0.00 s: LeftShoulder 160,0,-45 · RightShoulder 160,0,45 · LeftElbow 20,0,0 · RightElbow 20,0,0 · LeftHip 15,0,0 · RightHip -5,0,0 · LeftKnee -25,0,0 · RightKnee -15,0,0 · Neck -8,0,0
- **landSoft** (fade in 0.02 s) (fade out 0.1 s)
  - 0.00 s (Cubic Out): RootPos 0,-0.16,0.12 · Waist -6,0,0 · LeftHip 25,0,0 · RightHip 25,0,0 · LeftKnee -45,0,0 · RightKnee -45,0,0 · LeftAnkle 20,0,0 · RightAnkle 20,0,0
  - 0.10 s: rest (all keyed joints 0,0,0)
- **landNormal** (fade in 0.02 s) (fade out 0.12 s)
  - 0.00 s: RootPos 0,-0.5,0.2 · Waist -14,0,0 · Neck 8,0,0 · LeftShoulder 25,0,-20 · RightShoulder 25,0,20 · LeftHip 45,0,0 · RightHip 45,0,0 · LeftKnee -80,0,0 · RightKnee -80,0,0 · LeftAnkle 35,0,0 · RightAnkle 35,0,0
  - 0.06 s (Cubic InOut): RootPos 0,-0.5,0.2 · Waist -14,0,0 · Neck 8,0,0 · LeftShoulder 25,0,-20 · RightShoulder 25,0,20 · LeftHip 45,0,0 · RightHip 45,0,0 · LeftKnee -80,0,0 · RightKnee -80,0,0 · LeftAnkle 35,0,0 · RightAnkle 35,0,0
  - 0.22 s: rest (all keyed joints 0,0,0)
- **landHard** (fade in 0.02 s) (fade out 0.14 s)
  - 0.00 s: RootPos 0,-1,0.33 · Waist -24,0,0 · Neck 14,0,0 · LeftShoulder -20,0,-65 · RightShoulder -20,0,65 · LeftElbow 20,0,0 · RightElbow 20,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -115,0,0 · RightKnee -115,0,0 · LeftAnkle 45,0,0 · RightAnkle 45,0,0
  - 0.10 s (Cubic InOut): RootPos 0,-1,0.33 · Waist -24,0,0 · Neck 14,0,0 · LeftShoulder -20,0,-65 · RightShoulder -20,0,65 · LeftElbow 20,0,0 · RightElbow 20,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -115,0,0 · RightKnee -115,0,0 · LeftAnkle 45,0,0 · RightAnkle 45,0,0
  - 0.34 s: rest (all keyed joints 0,0,0)
- **doubleFlip** (fade in 0.03 s) (fade out 0.1 s)
  - 0.00 s: Root 0,0,0 · Neck -15,0,0 · LeftShoulder 55,0,-15 · RightShoulder 55,0,15 · LeftElbow 75,0,0 · RightElbow 75,0,0 · LeftHip 75,0,0 · RightHip 75,0,0 · LeftKnee -105,0,0 · RightKnee -105,0,0
  - 0.06 s: Root -100,0,0 · Neck -15,0,0 · LeftShoulder 55,0,-15 · RightShoulder 55,0,15 · LeftElbow 75,0,0 · RightElbow 75,0,0 · LeftHip 75,0,0 · RightHip 75,0,0 · LeftKnee -105,0,0 · RightKnee -105,0,0
  - 0.12 s: Root -200,0,0 · Neck -15,0,0 · LeftShoulder 55,0,-15 · RightShoulder 55,0,15 · LeftElbow 75,0,0 · RightElbow 75,0,0 · LeftHip 75,0,0 · RightHip 75,0,0 · LeftKnee -105,0,0 · RightKnee -105,0,0
  - 0.19 s (Cubic Out): Root -295,0,0 · Neck -15,0,0 · LeftShoulder 55,0,-15 · RightShoulder 55,0,15 · LeftElbow 75,0,0 · RightElbow 75,0,0 · LeftHip 75,0,0 · RightHip 75,0,0 · LeftKnee -105,0,0 · RightKnee -105,0,0
  - 0.26 s: Root -360,0,0 · LeftShoulder 150,0,-35 · RightShoulder 150,0,35 · LeftElbow 15,0,0 · RightElbow 15,0,0 · LeftHip 15,0,0 · RightHip -5,0,0 · LeftKnee -25,0,0 · RightKnee -15,0,0
- **fallFlail** (fade in 0.1 s)
  - 0.00 s (Cubic InOut): Neck -12,0,0 · LeftShoulder 165,0,-50 · RightShoulder 150,0,40 · LeftElbow 25,0,0 · RightElbow 10,0,0 · LeftHip 25,0,0 · RightHip -10,0,0 · LeftKnee -40,0,0 · RightKnee -10,0,0
  - 0.15 s (Cubic InOut): Neck -12,0,0 · LeftShoulder 150,0,-40 · RightShoulder 165,0,50 · LeftElbow 10,0,0 · RightElbow 25,0,0 · LeftHip -10,0,0 · RightHip 25,0,0 · LeftKnee -10,0,0 · RightKnee -40,0,0
  - 0.30 s: Neck -12,0,0 · LeftShoulder 165,0,-50 · RightShoulder 150,0,40 · LeftElbow 25,0,0 · RightElbow 10,0,0 · LeftHip 25,0,0 · RightHip -10,0,0 · LeftKnee -40,0,0 · RightKnee -10,0,0
- **dashPose** (fade in 0.03 s) (fade out 0.14 s)
  - 0.00 s: Root -14,0,0 · Waist -10,0,0 · Neck 18,0,0 · LeftShoulder -55,0,-12 · RightShoulder -55,0,12 · LeftElbow 15,0,0 · RightElbow 15,0,0 · LeftHip 40,0,0 · LeftKnee -70,0,0 · RightHip -30,0,0 · RightKnee -35,0,0
  - 0.20 s: Root -14,0,0 · Waist -10,0,0 · Neck 18,0,0 · LeftShoulder -55,0,-12 · RightShoulder -55,0,12 · LeftElbow 15,0,0 · RightElbow 15,0,0 · LeftHip 40,0,0 · LeftKnee -70,0,0 · RightHip -30,0,0 · RightKnee -35,0,0
- **slidePose** (fade in 0.06 s) (fade out 0.14 s)
  - 0.00 s: Root 24,0,0 · RootPos 0,-1.85,0 · Waist -14,0,0 · Neck -12,0,0 · LeftHip 66,0,0 · LeftKnee -4,0,0 · LeftAnkle -10,0,0 · RightHip 36,0,-12 · RightKnee -150,0,0 · LeftShoulder -20,0,-60 · LeftElbow 10,0,0 · RightShoulder 75,0,30 · RightElbow 30,0,0
  - 0.56 s (Cubic InOut): Root 24,0,0 · RootPos 0,-1.85,0 · Waist -14,0,0 · Neck -12,0,0 · LeftHip 66,0,0 · LeftKnee -4,0,0 · LeftAnkle -10,0,0 · RightHip 36,0,-12 · RightKnee -150,0,0 · LeftShoulder -20,0,-60 · LeftElbow 10,0,0 · RightShoulder 75,0,30 · RightElbow 30,0,0
  - 0.70 s: rest (all keyed joints 0,0,0)

---

## Part 2 · Hit (`hit.html`)

What happens when a squishy lands on a player: duel hits (−1 life), charged and ultimate hits, SQUISHED knockouts, falling off the map, and the final knockout.

**Signals:** `land` — victim touches the floor after the knockback (preview ≈ 0.37 s normal, 0.46 s charged, 0.59 s ultimate); `poof` — 0.30 s after impact (SQUISHED knockout); `offEdge` — victim off the arena and 3 studs below the floor (preview ≈ 0.43 s); `killY` — victim below the kill height (preview −45 studs, ≈ 0.81 s).

**Knockback (new):** normal 34 away + 34 up studs/s held 0.12 s; charged 44 + 40 held 0.14 s; ultimate = normal × 1.5. Apply as a LinearVelocity for the hold time, then air drag e^(−1.2·t) on the horizontal part and a 160 studs/s² skid after landing. Today's 8 studs/s up never leaves the ground, so floor friction eats the push — anything under ~25 up will still feel like nothing.



### Hit · normal throw

_Attacker · 1st person · Victim · 1st person · Observer · orbit (preview only) · lead-in 0.3 s_ — Duel: −1 life. 0.06 s freeze on both clients (impact frame), then the victim pops up and back. Attacker gets a tiny zoom-in + shake as hit confirm.

- t = -0.30 s: squishy flies in (lead-in, see Part 3)
- t = -0.30 s: pose **throwFollow** → attacker (2 R15 keys, 0.35 s, fade in 0.05 s, fade out 0.3 s)
- t = -0.30 s: trail **inTrail** @ squishy for 0.3 s: width 1.3, life 0.16 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: hit-stop **hitStopS**: freeze 0.06 s
- t = 0.00 s: squash/stretch **impactSquash** → squishy: 0 s (1.45, 1.45, 0.45) Quad Out → 0.05 s (1.6, 1.6, 0.35)
- t = 0.00 s: billboard **powS** @ hit: pow #FFD86B, tilt -15–15°, size (s:studs) 0:0.6 · 0.05:4.8 · 0.1:4.2 · 0.22:4.4 · 0.3:0, transp 0:0 · 0.22:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: billboard **coreFlash** @ hit: sparkle #FFFFFF, tilt 0–45°, size (s:studs) 0:2 · 0.04:6 · 0.12:0, transp 0, 0.12 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: Highlight **victimGlow** → victim: fill #FFFFFF (transp 0.35 → 1), outline #FFFFFF (transp 0 → 1), 0.2 s Quad Out
- t = 0.00 s: pose **hitRecoil** → victim (3 R15 keys, 0.36 s, holds last key)
- t = 0.00 s: screen flash **flashS**: #FFFFFF at 20 %, in 0.02 s, out 0.06 s _(Victim · 1st person only)_
- t = 0.00 s: screen splat **edgeSplat**: jelly #FF8FB1 ×4 (phone 2) on the bottom edge, 150–230 px @1080p, pop 0.08 s Back Out, hold 0.3 s, drip + fade 0.45 s _(Victim · 1st person only)_
- t = 0.00 s: camera shake **victimShakeS**: 1.2°, 0.25 s, 18 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.7/0.4 _(Victim · 1st person only)_
- t = 0.00 s: FOV kick **victimFovS**: +4°, in 0.04 s Quad Out, hold 0.04 s, out 0.25 s Sine InOut _(Victim · 1st person only)_
- t = 0.00 s: camera punch **victimPunch**: offset (0, 0, 0.6) studs, rotation (4, 0, 0)°, in 0.04 s, hold 0.02 s, out 0.25 s Back Out _(Victim · 1st person only)_
- t = 0.00 s: camera shake **attackerShake**: 0.5°, 0.12 s, 22 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.5/0.2 _(Attacker · 1st person only)_
- t = 0.00 s: FOV kick **attackerFov**: -2°, in 0.04 s Quad Out, hold 0.02 s, out 0.2 s Sine InOut _(Attacker · 1st person only)_
- t = 0.00 s: sound “squish_hit_splat”
- t = 0.00 s: text billboard **squishText** “SQUISH!” @ hit: #FF8FB1 with #3B2A35 outline, +(0, 3.2, 0) studs, size (s:studs) 0:0 · 0.05:2.6 · 0.1:2.2 · 0.24:2.3 · 0.3:0, transp 0:0 · 0.24:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: _Duel: −1 life (existing lives HUD updates here)_
- t = 0.06 s: squishy bursts (hidden)
- t = 0.06 s: motion: knockback · normal
- t = 0.06 s: burst **jellySplat** @ hit → back: jelly ×16 (phone 8), life 0.4–0.7 s, speed 20–36, spread 70/70°, size 0:0.7 · 0.25:0.95 · 1:0.3, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1.5, VelocityParallel, squash 0.3
- t = 0.06 s: burst **hitStars** @ hit: star ×8 (phone 4), life 0.35–0.55 s, speed 14–24, spread 180/180°, size 0:0.9 · 0.7:0.8 · 1:0, colour #FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2
- t = 0.06 s: burst **hitSprinkles** @ hit → back: confetti ×18 (phone 9), life 0.45–0.75 s, speed 18–30, spread 80/80°, size 0.35, tints #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, rot 0–360°, spin -540–540°/s
- t = 0.06 s: ring **hitRing** @ hit facing back: ring #FFFFFF, 1 → 6.5 studs in 0.22 s Quad Out, transparency 0.1 → 1 Quad In
- t = 0.06 s: sound “knockback_whoosh”
- t = 0.06 s: trail **knockTrail** @ victimChest for 0.4 s: width 1.2, life 0.25 s, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = land + 0.00 s: burst **skidPuff** @ victimFeet → up: puff ×8 (phone 4), life 0.3–0.45 s, speed 8–13, spread 8/8°, Cylinder r 0.7, size 0:0.7 · 0.35:1.5 · 1:0.3, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 6, rot 0–360°, spin -90–90°/s
- t = land + 0.00 s: pose **recoverLand** → victim (3 R15 keys, 0.28 s, fade in 0.03 s, fade out 0.18 s)
- t = land + 0.00 s: sound “land_squish”

### Hit · charged throw

_Attacker · 1st person · Victim · 1st person · Observer · orbit (preview only) · lead-in 0.3 s_ — Duel: −1 life. Longer freeze (0.09 s), bigger POW + light, harder knockback with a full backward tumble.

- t = -0.30 s: squishy flies in (lead-in, see Part 3)
- t = -0.30 s: pose **throwFollow** → attacker (2 R15 keys, 0.35 s, fade in 0.05 s, fade out 0.3 s)
- t = -0.30 s: trail **inTrail** @ squishy for 0.3 s: width 1.3, life 0.16 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: hit-stop **hitStopM**: freeze 0.09 s
- t = 0.00 s: squash/stretch **impactSquash** → squishy: 0 s (1.45, 1.45, 0.45) Quad Out → 0.05 s (1.6, 1.6, 0.35)
- t = 0.00 s: billboard **powM** @ hit: pow #FFD86B, tilt -15–15°, size (s:studs) 0:0.8 · 0.05:5.8 · 0.11:5 · 0.24:5.3 · 0.32:0, transp 0:0 · 0.24:0 · 0.32:1, 0.32 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: billboard **coreFlash** @ hit: sparkle #FFFFFF, tilt 0–45°, size (s:studs) 0:2 · 0.04:6 · 0.12:0, transp 0, 0.12 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: PointLight **hitLight** @ hit: #FFD86B, brightness 2.5 → 0, range 12, 0.15 s Quad Out
- t = 0.00 s: Highlight **victimGlow** → victim: fill #FFFFFF (transp 0.35 → 1), outline #FFFFFF (transp 0 → 1), 0.2 s Quad Out
- t = 0.00 s: pose **hitRecoil** → victim (3 R15 keys, 0.36 s, holds last key)
- t = 0.00 s: screen flash **flashM**: #FFFFFF at 25 %, in 0.02 s, out 0.07 s _(Victim · 1st person only)_
- t = 0.00 s: screen splat **edgeSplat**: jelly #FF8FB1 ×4 (phone 2) on the bottom edge, 150–230 px @1080p, pop 0.08 s Back Out, hold 0.3 s, drip + fade 0.45 s _(Victim · 1st person only)_
- t = 0.00 s: camera shake **victimShakeM**: 1.6°, 0.3 s, 18 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.7/0.4 _(Victim · 1st person only)_
- t = 0.00 s: FOV kick **victimFovM**: +6°, in 0.04 s Quad Out, hold 0.06 s, out 0.3 s Sine InOut _(Victim · 1st person only)_
- t = 0.00 s: camera punch **victimPunch**: offset (0, 0, 0.6) studs, rotation (4, 0, 0)°, in 0.04 s, hold 0.02 s, out 0.25 s Back Out _(Victim · 1st person only)_
- t = 0.00 s: camera shake **attackerShake**: 0.5°, 0.12 s, 22 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.5/0.2 _(Attacker · 1st person only)_
- t = 0.00 s: FOV kick **attackerFov**: -2°, in 0.04 s Quad Out, hold 0.02 s, out 0.2 s Sine InOut _(Attacker · 1st person only)_
- t = 0.00 s: sound “squish_hit_big”
- t = 0.00 s: _Duel: −1 life (existing lives HUD updates here)_
- t = 0.00 s: text billboard **splatText** “SPLAT!” @ hit: #FFD86B with #3B2A35 outline, +(0, 3.8, 0) studs, size (s:studs) 0:0 · 0.05:3.3 · 0.1:2.8 · 0.24:2.9 · 0.3:0, transp 0:0 · 0.24:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.09 s: squishy bursts (hidden)
- t = 0.09 s: motion: knockback · charged
- t = 0.09 s: pose **tumble360** → victim (5 R15 keys, 0.34 s, fade in 0.03 s, holds last key)
- t = 0.09 s: burst **jellySplatBig** @ hit → back: jelly ×26 (phone 13), life 0.45–0.8 s, speed 26–46, spread 80/80°, size 0:0.8 · 0.25:1.1 · 1:0.35, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1.5, VelocityParallel, squash 0.3
- t = 0.09 s: burst **hitStarsBig** @ hit: star ×14 (phone 7), life 0.4–0.65 s, speed 18–32, spread 180/180°, size 0:1.1 · 0.7:1 · 1:0, colour #FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2
- t = 0.09 s: burst **hitSprinkles** @ hit → back: confetti ×18 (phone 9), life 0.45–0.75 s, speed 18–30, spread 80/80°, size 0.35, tints #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, rot 0–360°, spin -540–540°/s
- t = 0.09 s: ring **hitRing** @ hit facing back: ring #FFFFFF, 1 → 6.5 studs in 0.22 s Quad Out, transparency 0.1 → 1 Quad In
- t = 0.09 s: sound “knockback_whoosh_big”
- t = 0.09 s: trail **knockTrail** @ victimChest for 0.45 s: width 1.2, life 0.25 s, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.09 s: emitter **dizzyStars** @ victimChest for 0.4 s: star ×24 (phone 12)/s, life 0.3–0.45 s, speed 4–7, spread 180/180°, Sphere r 1.4, size 0:0 · 0.3:0.8 · 1:0, colour #FFD86B, transp 0, drag 2, rot 0–360°, spin -300–300°/s, light 0.3, **LockedToPart** _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = land + 0.00 s: burst **skidPuff** @ victimFeet → up: puff ×8 (phone 4), life 0.3–0.45 s, speed 8–13, spread 8/8°, Cylinder r 0.7, size 0:0.7 · 0.35:1.5 · 1:0.3, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 6, rot 0–360°, spin -90–90°/s
- t = land + 0.00 s: pose **recoverLand** → victim (3 R15 keys, 0.28 s, fade in 0.03 s, fade out 0.18 s)
- t = land + 0.00 s: sound “land_squish”

### Hit · ultimate (×1.5)

_Attacker · 1st person · Victim · 1st person · Observer · orbit (preview only) · lead-in 0.3 s_ — Max live-fight values: 0.12 s freeze, 2° shake, +8° FOV. Knockback = normal × 1.5 (51 / 51 studs/s) with a double tumble.

- t = -0.30 s: squishy flies in (lead-in, see Part 3)
- t = -0.30 s: pose **throwFollow** → attacker (2 R15 keys, 0.35 s, fade in 0.05 s, fade out 0.3 s)
- t = -0.30 s: trail **inTrail** @ squishy for 0.3 s: width 1.3, life 0.16 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: hit-stop **hitStopL**: freeze 0.12 s
- t = 0.00 s: squash/stretch **impactSquash** → squishy: 0 s (1.45, 1.45, 0.45) Quad Out → 0.05 s (1.6, 1.6, 0.35)
- t = 0.00 s: billboard **powL** @ hit: pow #FFD25E, tilt -15–15°, size (s:studs) 0:1 · 0.06:7.2 · 0.12:6.2 · 0.26:6.6 · 0.34:0, transp 0:0 · 0.26:0 · 0.34:1, 0.34 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: billboard **coreFlash** @ hit: sparkle #FFFFFF, tilt 0–45°, size (s:studs) 0:2 · 0.04:6 · 0.12:0, transp 0, 0.12 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: PointLight **hitLight** @ hit: #FFD86B, brightness 2.5 → 0, range 12, 0.15 s Quad Out
- t = 0.00 s: Highlight **victimGlow** → victim: fill #FFFFFF (transp 0.35 → 1), outline #FFFFFF (transp 0 → 1), 0.2 s Quad Out
- t = 0.00 s: pose **hitRecoil** → victim (3 R15 keys, 0.36 s, holds last key)
- t = 0.00 s: screen flash **flashL**: #FFF4E6 at 30 %, in 0.02 s, out 0.08 s _(Victim · 1st person only)_
- t = 0.00 s: screen splat **edgeSplat**: jelly #FF8FB1 ×4 (phone 2) on the bottom edge, 150–230 px @1080p, pop 0.08 s Back Out, hold 0.3 s, drip + fade 0.45 s _(Victim · 1st person only)_
- t = 0.00 s: camera shake **victimShakeL**: 2°, 0.35 s, 16 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.7/0.4 _(Victim · 1st person only)_
- t = 0.00 s: FOV kick **victimFovL**: +8°, in 0.05 s Quad Out, hold 0.08 s, out 0.35 s Sine InOut _(Victim · 1st person only)_
- t = 0.00 s: camera punch **victimPunch**: offset (0, 0, 0.6) studs, rotation (4, 0, 0)°, in 0.04 s, hold 0.02 s, out 0.25 s Back Out _(Victim · 1st person only)_
- t = 0.00 s: camera shake **attackerShake**: 0.5°, 0.12 s, 22 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.5/0.2 _(Attacker · 1st person only)_
- t = 0.00 s: FOV kick **attackerFov**: -2°, in 0.04 s Quad Out, hold 0.02 s, out 0.2 s Sine InOut _(Attacker · 1st person only)_
- t = 0.00 s: sound “squish_hit_ultimate”
- t = 0.00 s: text billboard **splatText** “SPLAT!” @ hit: #FFD86B with #3B2A35 outline, +(0, 3.8, 0) studs, size (s:studs) 0:0 · 0.05:3.3 · 0.1:2.8 · 0.24:2.9 · 0.3:0, transp 0:0 · 0.24:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: squishy bursts (hidden)
- t = 0.12 s: motion: knockback · ultimate
- t = 0.12 s: pose **tumble720** → victim (8 R15 keys, 0.44 s, fade in 0.03 s, holds last key)
- t = 0.12 s: burst **jellySplatBig** @ hit → back: jelly ×26 (phone 13), life 0.45–0.8 s, speed 26–46, spread 80/80°, size 0:0.8 · 0.25:1.1 · 1:0.35, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1.5, VelocityParallel, squash 0.3
- t = 0.12 s: burst **hitStarsBig** @ hit: star ×14 (phone 7), life 0.4–0.65 s, speed 18–32, spread 180/180°, size 0:1.1 · 0.7:1 · 1:0, colour #FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2
- t = 0.12 s: burst **hitSprinklesBig** @ hit → back: confetti ×30 (phone 15), life 0.5–0.85 s, speed 22–38, spread 90/90°, size 0.4, tints #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, rot 0–360°, spin -540–540°/s
- t = 0.12 s: ring **hitRingBig** @ hit facing back: ring #FFD86B, 1.5 → 10 studs in 0.3 s Quad Out, transparency 0.05 → 1 Quad In
- t = 0.12 s: sound “knockback_whoosh_big”
- t = 0.12 s: trail **knockTrail** @ victimChest for 0.5 s: width 1.2, life 0.25 s, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.12 s: emitter **dizzyStars** @ victimChest for 0.45 s: star ×24 (phone 12)/s, life 0.3–0.45 s, speed 4–7, spread 180/180°, Sphere r 1.4, size 0:0 · 0.3:0.8 · 1:0, colour #FFD86B, transp 0, drag 2, rot 0–360°, spin -300–300°/s, light 0.3, **LockedToPart** _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.16 s: ring **hitRing** @ hit facing back: ring #FFFFFF, 1 → 6.5 studs in 0.22 s Quad Out, transparency 0.1 → 1 Quad In
- t = land + 0.00 s: burst **skidPuff** @ victimFeet → up: puff ×8 (phone 4), life 0.3–0.45 s, speed 8–13, spread 8/8°, Cylinder r 0.7, size 0:0.7 · 0.35:1.5 · 1:0.3, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 6, rot 0–360°, spin -90–90°/s
- t = land + 0.00 s: pose **recoverLand** → victim (3 R15 keys, 0.28 s, fade in 0.03 s, fade out 0.18 s)
- t = land + 0.00 s: sound “land_squish”

### Knockout · SQUISHED (match)

_Victim · 1st person · Attacker · 1st person · Observer · orbit (preview only) · lead-in 0.3 s_ — Match: one hit = knocked out. Freeze, launch, then the avatar vanishes into a candy puff (no squashing the avatar). SQUISHED! pops in the centre for 0.3 s, then parks at the top until the respawn at 3 s. The victim’s camera leaves the body right after the freeze, so the puff is seen from a few studs away (the big cloud is hidden from that camera).

- t = -0.30 s: squishy flies in (lead-in, see Part 3)
- t = -0.30 s: pose **throwFollow** → attacker (2 R15 keys, 0.35 s, fade in 0.05 s, fade out 0.3 s)
- t = -0.30 s: trail **inTrail** @ squishy for 0.3 s: width 1.3, life 0.16 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: hit-stop **hitStopL**: freeze 0.12 s
- t = 0.00 s: squash/stretch **impactSquash** → squishy: 0 s (1.45, 1.45, 0.45) Quad Out → 0.05 s (1.6, 1.6, 0.35)
- t = 0.00 s: billboard **powL** @ hit: pow #FFD25E, tilt -15–15°, size (s:studs) 0:1 · 0.06:7.2 · 0.12:6.2 · 0.26:6.6 · 0.34:0, transp 0:0 · 0.26:0 · 0.34:1, 0.34 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: billboard **coreFlash** @ hit: sparkle #FFFFFF, tilt 0–45°, size (s:studs) 0:2 · 0.04:6 · 0.12:0, transp 0, 0.12 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: Highlight **victimGlow** → victim: fill #FFFFFF (transp 0.35 → 1), outline #FFFFFF (transp 0 → 1), 0.2 s Quad Out
- t = 0.00 s: pose **hitRecoil** → victim (3 R15 keys, 0.36 s, holds last key)
- t = 0.00 s: screen flash **flashL**: #FFF4E6 at 30 %, in 0.02 s, out 0.08 s _(Victim · 1st person only)_
- t = 0.00 s: screen splat **edgeSplat**: jelly #FF8FB1 ×4 (phone 2) on the bottom edge, 150–230 px @1080p, pop 0.08 s Back Out, hold 0.3 s, drip + fade 0.45 s _(Victim · 1st person only)_
- t = 0.00 s: camera shake **victimShakeL**: 2°, 0.35 s, 16 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.7/0.4 _(Victim · 1st person only)_
- t = 0.00 s: FOV kick **victimFovL**: +8°, in 0.05 s Quad Out, hold 0.08 s, out 0.35 s Sine InOut _(Victim · 1st person only)_
- t = 0.00 s: camera punch **victimPunch**: offset (0, 0, 0.6) studs, rotation (4, 0, 0)°, in 0.04 s, hold 0.02 s, out 0.25 s Back Out _(Victim · 1st person only)_
- t = 0.00 s: camera shake **attackerShake**: 0.5°, 0.12 s, 22 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.5/0.2 _(Attacker · 1st person only)_
- t = 0.00 s: FOV kick **attackerFov**: -2°, in 0.04 s Quad Out, hold 0.02 s, out 0.2 s Sine InOut _(Attacker · 1st person only)_
- t = 0.00 s: sound “squish_hit_big”
- t = 0.00 s: text billboard **splatText** “SPLAT!” @ hit: #FFD86B with #3B2A35 outline, +(0, 3.8, 0) studs, size (s:studs) 0:0 · 0.05:3.3 · 0.1:2.8 · 0.24:2.9 · 0.3:0, transp 0:0 · 0.24:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: squishy bursts (hidden)
- t = 0.12 s: motion: knockback · normal
- t = 0.12 s: pose **tumble360** → victim (5 R15 keys, 0.34 s, fade in 0.03 s, holds last key)
- t = 0.12 s: burst **jellySplat** @ hit → back: jelly ×16 (phone 8), life 0.4–0.7 s, speed 20–36, spread 70/70°, size 0:0.7 · 0.25:0.95 · 1:0.3, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1.5, VelocityParallel, squash 0.3
- t = 0.12 s: burst **hitStars** @ hit: star ×8 (phone 4), life 0.35–0.55 s, speed 14–24, spread 180/180°, size 0:0.9 · 0.7:0.8 · 1:0, colour #FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2
- t = 0.12 s: ring **hitRing** @ hit facing back: ring #FFFFFF, 1 → 6.5 studs in 0.22 s Quad Out, transparency 0.1 → 1 Quad In
- t = 0.12 s: screen text **squished** “SQUISHED!”: #FF8FB1 with 14 px #3B2A35 outline, 150 px @1080p; pops ×1.25 in 0.07 s, settles 0.05 s, holds 0.06 s, moves to 17 % from top at ×0.55 in 0.12 s, stays 2.3 s, fades 0.2 s _(Victim · 1st person only)_
- t = 0.12 s: victim camera detaches and pulls back over the hit spot _(Victim · 1st person only)_
- t = 0.12 s: sound “squished_jingle”
- t = 0.12 s: trail **knockTrail** @ victimChest for 0.18 s: width 1.2, life 0.25 s, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.30 s: poof (signal)
- t = 3.00 s: respawn at spawn point (3 s, unchanged)
- t = 3.00 s: burst **respawnPuff** @ spawnFeet → up: puff ×10 (phone 5), life 0.3–0.45 s, speed 8–12, spread 8/8°, Cylinder r 1, size 0:0.8 · 0.35:1.8 · 1:0.3, colour #FFF4E6, transp 0:0.05 · 0.7:0.35 · 1:1, accel (0, 10, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = 3.00 s: burst **respawnSparkles** @ spawnFeet → up: sparkle ×10 (phone 5), life 0.35–0.6 s, speed 6–10, spread 10/10°, Cylinder r 1.5, size 0:0 · 0.3:1 · 1:0, colour #FFFFFF, transp 0, accel (0, 14, 0), drag 2, rot 0–45°, spin -90–90°/s, light 0.7
- t = 3.00 s: ring **respawnRing** @ spawnFeet facing up: ring #5FD3AE, 1 → 7 studs in 0.3 s Quad Out, transparency 0.1 → 1 Quad In
- t = 3.00 s: Highlight **respawnGlow** → victim: fill #FFFFFF (transp 0.4 → 1), outline #FFFFFF (transp 0 → 1), 0.3 s Quad Out
- t = 3.00 s: pose **respawnPop** → victim (2 R15 keys, 0.25 s, fade out 0.15 s)
- t = 3.00 s: sound “respawn_pop”
- t = poof + 0.00 s: avatar hidden inside the puff
- t = poof + 0.00 s: burst **poofCloud** @ victimChest: puff ×14 (phone 7), life 0.45–0.7 s, speed 6–12, spread 180/180°, Sphere r 1.6, size 0:2 · 0.3:4.2 · 1:1, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0 · 0.6:0.2 · 1:1, accel (0, 6, 0), drag 4, rot 0–360°, spin -60–60°/s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = poof + 0.00 s: burst **poofConfetti** @ victimChest: confetti ×32 (phone 16), life 0.6–1 s, speed 20–34, spread 180/180°, size 0.4, tints #FF8FB1 / #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -90, 0), drag 1.5, rot 0–360°, spin -540–540°/s
- t = poof + 0.00 s: burst **poofSparkles** @ victimChest: sparkle ×12 (phone 6), life 0.4–0.7 s, speed 2–6, spread 180/180°, Sphere r 2.2, size 0:0 · 0.3:1.3 · 1:0, colour #FFFFFF, transp 0, drag 2, rot 0–45°, spin -90–90°/s, light 0.7
- t = poof + 0.00 s: ring **poofRing** @ victimChest facing back: ring #FF8FB1, 2 → 12 studs in 0.35 s Quad Out, transparency 0.05 → 1 Quad In
- t = poof + 0.00 s: sound “poof_squish_pop”

### Fall off the map

_Victim · 1st person · Attacker · 1st person · Observer · orbit (preview only) · lead-in 0.3 s_ — Knocked over the edge. When the avatar is 3 studs below the floor the victim camera stops at the edge and watches the fall; at the kill height the avatar poofs and SQUISHED! shows.

- t = -0.30 s: squishy flies in (lead-in, see Part 3)
- t = -0.30 s: pose **throwFollow** → attacker (2 R15 keys, 0.35 s, fade in 0.05 s, fade out 0.3 s)
- t = -0.30 s: trail **inTrail** @ squishy for 0.3 s: width 1.3, life 0.16 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: hit-stop **hitStopS**: freeze 0.06 s
- t = 0.00 s: squash/stretch **impactSquash** → squishy: 0 s (1.45, 1.45, 0.45) Quad Out → 0.05 s (1.6, 1.6, 0.35)
- t = 0.00 s: billboard **powS** @ hit: pow #FFD86B, tilt -15–15°, size (s:studs) 0:0.6 · 0.05:4.8 · 0.1:4.2 · 0.22:4.4 · 0.3:0, transp 0:0 · 0.22:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: billboard **coreFlash** @ hit: sparkle #FFFFFF, tilt 0–45°, size (s:studs) 0:2 · 0.04:6 · 0.12:0, transp 0, 0.12 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: Highlight **victimGlow** → victim: fill #FFFFFF (transp 0.35 → 1), outline #FFFFFF (transp 0 → 1), 0.2 s Quad Out
- t = 0.00 s: pose **hitRecoil** → victim (3 R15 keys, 0.36 s, holds last key)
- t = 0.00 s: screen flash **flashS**: #FFFFFF at 20 %, in 0.02 s, out 0.06 s _(Victim · 1st person only)_
- t = 0.00 s: screen splat **edgeSplat**: jelly #FF8FB1 ×4 (phone 2) on the bottom edge, 150–230 px @1080p, pop 0.08 s Back Out, hold 0.3 s, drip + fade 0.45 s _(Victim · 1st person only)_
- t = 0.00 s: camera shake **victimShakeS**: 1.2°, 0.25 s, 18 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.7/0.4 _(Victim · 1st person only)_
- t = 0.00 s: FOV kick **victimFovS**: +4°, in 0.04 s Quad Out, hold 0.04 s, out 0.25 s Sine InOut _(Victim · 1st person only)_
- t = 0.00 s: camera punch **victimPunch**: offset (0, 0, 0.6) studs, rotation (4, 0, 0)°, in 0.04 s, hold 0.02 s, out 0.25 s Back Out _(Victim · 1st person only)_
- t = 0.00 s: camera shake **attackerShake**: 0.5°, 0.12 s, 22 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.5/0.2 _(Attacker · 1st person only)_
- t = 0.00 s: FOV kick **attackerFov**: -2°, in 0.04 s Quad Out, hold 0.02 s, out 0.2 s Sine InOut _(Attacker · 1st person only)_
- t = 0.00 s: sound “squish_hit_splat”
- t = 0.00 s: text billboard **squishText** “SQUISH!” @ hit: #FF8FB1 with #3B2A35 outline, +(0, 3.2, 0) studs, size (s:studs) 0:0 · 0.05:2.6 · 0.1:2.2 · 0.24:2.3 · 0.3:0, transp 0:0 · 0.24:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.06 s: squishy bursts (hidden)
- t = 0.06 s: motion: knockback · normal
- t = 0.06 s: burst **jellySplat** @ hit → back: jelly ×16 (phone 8), life 0.4–0.7 s, speed 20–36, spread 70/70°, size 0:0.7 · 0.25:0.95 · 1:0.3, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1.5, VelocityParallel, squash 0.3
- t = 0.06 s: burst **hitStars** @ hit: star ×8 (phone 4), life 0.35–0.55 s, speed 14–24, spread 180/180°, size 0:0.9 · 0.7:0.8 · 1:0, colour #FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2
- t = 0.06 s: burst **hitSprinkles** @ hit → back: confetti ×18 (phone 9), life 0.45–0.75 s, speed 18–30, spread 80/80°, size 0.35, tints #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, rot 0–360°, spin -540–540°/s
- t = 0.06 s: ring **hitRing** @ hit facing back: ring #FFFFFF, 1 → 6.5 studs in 0.22 s Quad Out, transparency 0.1 → 1 Quad In
- t = 0.06 s: sound “knockback_whoosh”
- t = 0.06 s: trail **knockTrail** @ victimChest for 0.4 s: width 1.2, life 0.25 s, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = offEdge + 0.00 s: victim camera stops at the edge, looks down _(Victim · 1st person only)_
- t = offEdge + 0.00 s: emitter **fallWindKO** @ victimChest → up for 0.9 s: speedline ×30 (phone 15)/s, life 0.12–0.2 s, speed 40–60, spread 4/4°, Box 5×6×5, size 0:0.5 · 1:0.4, colour #FFFFFF, transp 0:0.4 · 1:1, light 0.3, VelocityParallel, squash 1.6
- t = offEdge + 0.00 s: sound “fall_whistle_long”
- t = killY + 0.00 s: stop fallWindKO
- t = killY + 0.00 s: avatar hidden
- t = killY + 0.00 s: burst **fallPoof** @ victimChest: puff ×12 (phone 6), life 0.4–0.6 s, speed 8–14, spread 180/180°, Sphere r 1.4, size 0:1.6 · 0.3:3.4 · 1:0.8, colour 0:#FFFFFF · 1:#B9A6E8, transp 0:0 · 0.6:0.25 · 1:1, accel (0, 10, 0), drag 4, rot 0–360°, spin -60–60°/s
- t = killY + 0.00 s: burst **poofSparkles** @ victimChest: sparkle ×12 (phone 6), life 0.4–0.7 s, speed 2–6, spread 180/180°, Sphere r 2.2, size 0:0 · 0.3:1.3 · 1:0, colour #FFFFFF, transp 0, drag 2, rot 0–45°, spin -90–90°/s, light 0.7
- t = killY + 0.00 s: screen text **squished** “SQUISHED!”: #FF8FB1 with 14 px #3B2A35 outline, 150 px @1080p; pops ×1.25 in 0.07 s, settles 0.05 s, holds 0.06 s, moves to 17 % from top at ×0.55 in 0.12 s, stays 2.3 s, fades 0.2 s _(Victim · 1st person only)_
- t = killY + 0.00 s: sound “fall_out_poof”

### Final knockout (round decided)

_Attacker · 1st person · Victim · 1st person · Observer · orbit (preview only) · lead-in 0.3 s · slow-mo allowed_ — The round is already won, so slow motion is allowed: ×0.3 for 0.5 s right after the freeze. Every client plays it locally. The victim’s own view gets the flash, edge splat and text only (no slow-mo burst in front of the eyes). Then the existing killcam takes over (not redesigned).

- t = -0.30 s: squishy flies in (lead-in, see Part 3)
- t = -0.30 s: pose **throwFollow** → attacker (2 R15 keys, 0.35 s, fade in 0.05 s, fade out 0.3 s)
- t = -0.30 s: trail **inTrail** @ squishy for 0.3 s: width 1.3, life 0.16 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: hit-stop **hitStopL**: freeze 0.12 s
- t = 0.00 s: squash/stretch **impactSquash** → squishy: 0 s (1.45, 1.45, 0.45) Quad Out → 0.05 s (1.6, 1.6, 0.35)
- t = 0.00 s: billboard **powL** @ hit: pow #FFD25E, tilt -15–15°, size (s:studs) 0:1 · 0.06:7.2 · 0.12:6.2 · 0.26:6.6 · 0.34:0, transp 0:0 · 0.26:0 · 0.34:1, 0.34 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: billboard **coreFlash** @ hit: sparkle #FFFFFF, tilt 0–45°, size (s:studs) 0:2 · 0.04:6 · 0.12:0, transp 0, 0.12 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.00 s: PointLight **hitLight** @ hit: #FFD86B, brightness 2.5 → 0, range 12, 0.15 s Quad Out
- t = 0.00 s: Highlight **victimGlow** → victim: fill #FFFFFF (transp 0.35 → 1), outline #FFFFFF (transp 0 → 1), 0.2 s Quad Out
- t = 0.00 s: pose **hitRecoil** → victim (3 R15 keys, 0.36 s, holds last key)
- t = 0.00 s: screen flash **flashL**: #FFF4E6 at 30 %, in 0.02 s, out 0.08 s _(Victim · 1st person only)_
- t = 0.00 s: screen splat **edgeSplat**: jelly #FF8FB1 ×4 (phone 2) on the bottom edge, 150–230 px @1080p, pop 0.08 s Back Out, hold 0.3 s, drip + fade 0.45 s _(Victim · 1st person only)_
- t = 0.00 s: camera shake **finalShake**: 1.5°, 0.4 s, 14 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.7/0.4
- t = 0.00 s: sound “final_hit_boom”
- t = 0.00 s: text billboard **splatText** “SPLAT!” @ hit: #FFD86B with #3B2A35 outline, +(0, 3.8, 0) studs, size (s:studs) 0:0 · 0.05:3.3 · 0.1:2.8 · 0.24:2.9 · 0.3:0, transp 0:0 · 0.24:0 · 0.3:1, 0.3 s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: slow-mo **finalSlow**: ×0.3, in 0.06 s, hold 0.5 s, out 0.3 s Sine InOut
- t = 0.12 s: FOV kick **finalFov**: -6°, in 0.12 s Quad Out, hold 0.45 s, out 0.3 s Sine InOut
- t = 0.12 s: squishy bursts (hidden)
- t = 0.12 s: motion: knockback · ultimate
- t = 0.12 s: pose **tumble720** → victim (8 R15 keys, 0.44 s, fade in 0.03 s, holds last key)
- t = 0.12 s: burst **jellySplatBig** @ hit → back: jelly ×26 (phone 13), life 0.45–0.8 s, speed 26–46, spread 80/80°, size 0:0.8 · 0.25:1.1 · 1:0.35, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1.5, VelocityParallel, squash 0.3 _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: burst **finalConfetti** @ hit: confetti ×40 (phone 20), life 0.7–1.2 s, speed 24–40, spread 180/180°, size 0.45, tints #FF8FB1 / #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -80, 0), drag 1.5, rot 0–360°, spin -540–540°/s _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: burst **hitStarsBig** @ hit: star ×14 (phone 7), life 0.4–0.65 s, speed 18–32, spread 180/180°, size 0:1.1 · 0.7:1 · 1:0, colour #FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2 _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: ring **hitRingBig** @ hit facing back: ring #FFD86B, 1.5 → 10 studs in 0.3 s Quad Out, transparency 0.05 → 1 Quad In _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.12 s: screen text **squished** “SQUISHED!”: #FF8FB1 with 14 px #3B2A35 outline, 150 px @1080p; pops ×1.25 in 0.07 s, settles 0.05 s, holds 0.06 s, moves to 17 % from top at ×0.55 in 0.12 s, stays 2.3 s, fades 0.2 s _(Victim · 1st person only)_
- t = 0.12 s: sound “slowmo_whoomp”
- t = 0.12 s: letterbox **koBars**: #3B2A35 bars, 10 % of the screen each, in 0.15 s, hold 0.9 s, out 0.3 s
- t = 0.12 s: trail **knockTrail** @ victimChest for 0.6 s: width 1.2, life 0.25 s, colour 0:#FFFFFF · 1:#FFC7DA, transp 0:0.3 · 1:1, width scale 0:1 · 1:0
- t = 0.20 s: ring **hitRing** @ hit facing back: ring #FFFFFF, 1 → 6.5 studs in 0.22 s Quad Out, transparency 0.1 → 1 Quad In _(Attacker · 1st person / Observer · orbit (preview only) only)_
- t = 0.95 s: sound “slowmo_release”
- t = 1.30 s: _→ existing killcam replay starts here (not redesigned)_

#### Part 2 · Hit — R15 pose keys

Per key: `t (easing to next): Joint X,Y,Z°`. Joints a track keys somewhere but a key omits are 0,0,0. RootPos is a Root translation in studs (character space, −Z = forward).

- **throwFollow** (fade in 0.05 s) (fade out 0.3 s)
  - 0.00 s (Cubic Out): Waist -10,25,0 · RightShoulder 100,0,15 · RightElbow 10,0,0 · LeftShoulder 20,0,-25 · LeftElbow 30,0,0 · RightHip 25,0,0 · RightKnee -30,0,0 · LeftHip -15,0,0
  - 0.35 s: Waist -6,15,0 · RightShoulder 70,0,10 · RightElbow 20,0,0 · LeftShoulder 10,0,-15 · LeftElbow 20,0,0 · RightHip 10,0,0 · RightKnee -15,0,0 · LeftHip -5,0,0
- **hitRecoil**
  - 0.00 s (Cubic Out): Neck 25,0,0 · Waist 22,0,0 · LeftShoulder 70,0,-70 · RightShoulder 70,0,70 · LeftElbow 45,0,0 · RightElbow 45,0,0 · LeftHip 35,0,0 · RightHip 50,0,0 · LeftKnee -45,0,0 · RightKnee -65,0,0
  - 0.20 s (Cubic InOut): Root 30,0,0 · Neck 15,0,0 · Waist 15,0,0 · LeftShoulder 120,0,-50 · RightShoulder 120,0,50 · LeftElbow 30,0,0 · RightElbow 30,0,0 · LeftHip 40,0,0 · RightHip 55,0,0 · LeftKnee -50,0,0 · RightKnee -70,0,0
  - 0.36 s: Root 12,0,0 · Neck 8,0,0 · Waist 8,0,0 · LeftShoulder 140,0,-40 · RightShoulder 140,0,40 · LeftElbow 20,0,0 · RightElbow 20,0,0 · LeftHip 30,0,0 · RightHip 40,0,0 · LeftKnee -40,0,0 · RightKnee -55,0,0
- **recoverLand** (fade in 0.03 s) (fade out 0.18 s)
  - 0.00 s: RootPos 0,-0.6,0.2 · Waist -16,0,0 · Neck 10,0,0 · LeftShoulder 20,0,-35 · RightShoulder 20,0,35 · LeftHip 50,0,0 · RightHip 50,0,0 · LeftKnee -85,0,0 · RightKnee -85,0,0 · LeftAnkle 35,0,0 · RightAnkle 35,0,0
  - 0.10 s (Cubic InOut): RootPos 0,-0.6,0.2 · Waist -16,0,0 · Neck 10,0,0 · LeftShoulder 20,0,-35 · RightShoulder 20,0,35 · LeftHip 50,0,0 · RightHip 50,0,0 · LeftKnee -85,0,0 · RightKnee -85,0,0 · LeftAnkle 35,0,0 · RightAnkle 35,0,0
  - 0.28 s: rest (all keyed joints 0,0,0)
- **tumble360** (fade in 0.03 s)
  - 0.00 s: Root 20,0,0 · Neck -10,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.08 s: Root 110,0,0 · Neck -10,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.16 s: Root 200,0,0 · Neck -10,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.25 s (Cubic Out): Root 290,0,0 · Neck -10,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.34 s: Root 360,0,0 · LeftShoulder 140,0,-40 · RightShoulder 140,0,40 · LeftElbow 20,0,0 · RightElbow 20,0,0 · LeftHip 30,0,0 · RightHip 40,0,0 · LeftKnee -40,0,0 · RightKnee -55,0,0
- **tumble720** (fade in 0.03 s)
  - 0.00 s: Root 20,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.06 s: Root 120,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.12 s: Root 230,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.18 s: Root 340,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.24 s: Root 450,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.30 s: Root 560,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.37 s (Cubic Out): Root 660,0,0 · LeftShoulder 50,0,-30 · RightShoulder 50,0,30 · LeftElbow 60,0,0 · RightElbow 60,0,0 · LeftHip 70,0,0 · RightHip 70,0,0 · LeftKnee -100,0,0 · RightKnee -100,0,0
  - 0.44 s: Root 720,0,0 · LeftShoulder 140,0,-40 · RightShoulder 140,0,40 · LeftElbow 20,0,0 · RightElbow 20,0,0 · LeftHip 30,0,0 · RightHip 40,0,0 · LeftKnee -40,0,0 · RightKnee -55,0,0
- **respawnPop** (fade out 0.15 s)
  - 0.00 s (Cubic Out): Neck 10,0,0 · LeftShoulder 150,0,-30 · RightShoulder 150,0,30
  - 0.25 s: rest (all keyed joints 0,0,0)

---

## Part 3 · Duel flight (`duelflight.html`)

The squishy from hand to target in duels and matches: tap throw, charged throw, flight, missing (bounce + roll) and catching.

**Signals:** `bounce` — any floor contact after a miss; `bounceBig` / `bounceSmall` — contact at ≥ / < 18 studs/s downward; `roll` — outgoing bounce speed below 9 studs/s, the squishy starts rolling; `rest` — roll speed reaches 0.

**Kept:** throw speed (preview 100 tap / 115 charged), squishy gravity 35, radius 1.1, charge 1 s, catch burst at 1.02 s. **New (visual):** barrel spin 540 / 900 °/s. **New (miss bounce):** gravity 120 after the first contact, restitution 0.45 + 0.12 × forward speed, keep 0.6 of forward speed per bounce, roll below 9 studs/s with 90 studs/s² slow-down, big squash from 18 studs/s. **1st-person held squishy:** drawn in camera space at (1.0, −1.25, −2.6) studs (right, down, ahead) at ×0.5 scale, growing to world size 0.12 s after release, so the charge reads in the lower-right without covering the centre; the thrower’s own arms are hidden in 1st person (use the game’s viewmodel).



### Throw (tap)

_Thrower · 1st person · Side · orbit (preview only) · Target · 1st person_ — The squishy leaves on the click (no wind-up delay); the arm catches up in 0.06 s. Release stretch along the travel axis, barrel spin, short trail. It misses here, so it ends in bounces and a roll.

- t = 0.00 s: motion: release · tap speed, aimed 4° up
- t = 0.00 s: pose **throwOverhand** → thrower (3 R15 keys, 0.3 s, fade out 0.2 s)
- t = 0.00 s: squash/stretch **releaseStretch** → squishy: 0 s (0.8, 0.8, 1.45) Quad Out → 0.06 s (1.1, 1.1, 0.88) Quad InOut → 0.12 s (0.96, 0.96, 1.1) Sine InOut → 0.2 s (1, 1, 1.05), holds last key
- t = 0.00 s: wobble **flightJiggle** → squishy: ±6 % at 7 Hz, decay e^(−2.5·t), up to 1.2 s
- t = 0.00 s: trail **flightTrail** @ squishy: width 1.4, life 0.18 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.25 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: burst **releasePuff** @ hand → forward: puff ×4 (phone 2), life 0.18–0.28 s, speed 6–10, spread 35/35°, size 0:0.5 · 0.4:1 · 1:0.2, colour #FFF4E6, transp 0:0.2 · 1:1, drag 6, rot 0–360°, spin -90–90°/s
- t = 0.00 s: camera punch **releaseKick**: rotation (0.6, 0, 0)°, in 0.03 s, hold 0 s, out 0.12 s Quad Out _(Thrower · 1st person only)_
- t = 0.00 s: sound “throw_whoosh”
- t = rest + 0.00 s: stop flightTrail
- t = rest + 0.00 s: stop rollDust
- t = rest + 0.00 s: wobble **restJiggle** → squishy: ±9 % at 5 Hz, decay e^(−4·t), up to 1 s
- t = rest + 0.00 s: sound “squishy_settle”
- t = bounceBig + 0.00 s: squash/stretch **bounceSquashBig** → squishy: 0 s (1.45, 0.55, 1.45) Quad Out → 0.05 s (0.85, 1.2, 0.85) Quad InOut → 0.11 s (1.06, 0.94, 1.06) Sine InOut → 0.18 s (1, 1, 1)
- t = bounceBig + 0.00 s: burst **bouncePuff** @ floor → up: puff ×8 (phone 4), life 0.25–0.4 s, speed 8–12, spread 8/8°, Cylinder r 0.8, size 0:0.6 · 0.35:1.3 · 1:0.2, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceBig + 0.00 s: burst **bounceDrops** @ floor → up: jelly ×6 (phone 3), life 0.25–0.4 s, speed 10–16, spread 50/50°, size 0:0.45 · 1:0.15, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, VelocityParallel, squash 0.3
- t = bounceBig + 0.00 s: sound “squishy_boing”
- t = bounceBig + 0.00 s: text billboard **boingText** “BOING!” @ floor: #FF8FB1 with #3B2A35 outline, +(0, 2.6, 0) studs, size (s:studs) 0:0 · 0.08:2.6 · 0.14:2.1 · 0.4:2.2 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(Thrower · 1st person / Side · orbit (preview only) only)_
- t = bounceSmall + 0.00 s: squash/stretch **bounceSquashSmall** → squishy: 0 s (1.22, 0.76, 1.22) Quad Out → 0.05 s (0.93, 1.08, 0.93) Sine InOut → 0.12 s (1, 1, 1)
- t = bounceSmall + 0.00 s: burst **bouncePuffSmall** @ floor → up: puff ×4 (phone 2), life 0.2–0.3 s, speed 5–8, spread 8/8°, Cylinder r 0.6, size 0:0.4 · 0.35:0.9 · 1:0.2, colour #FFF4E6, transp 0:0.2 · 0.7:0.5 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceSmall + 0.00 s: sound “squishy_boing_small”
- t = roll + 0.00 s: emitter **rollDust** @ floor → back for the whole flight: puff ×14 (phone 7)/s, life 0.2–0.32 s, speed 1–3, spread 40/40°, size 0:0.3 · 0.4:0.7 · 1:0.1, colour #FFF4E6, transp 0:0.3 · 1:1, accel (0, 4, 0), drag 4, rot 0–360°, spin -60–60°/s
- t = roll + 0.00 s: sound “squishy_roll_loop”

### Charge (hold 1 s) + throw

_Thrower · 1st person · Side · orbit (preview only) · Target · 1st person_ — Hold: the squishy inflates 18 % and jiggles, sparkles get sucked in, FOV narrows 3°. Full at 1.00 s: ding + ring + glow. Release: bigger stretch, faster spin, gold trail with sparkles, small camera kick.

- t = 0.00 s: pose **chargeHold** → thrower (2 R15 keys, 1 s, fade in 0.1 s, holds last key)
- t = 0.00 s: squash/stretch **chargeGrow** → squishy: 0 s (1, 1, 1) Quad Out → 1 s (1.18, 1.18, 1.18), holds last key
- t = 0.00 s: wobble **chargeJiggle** → squishy: ±5 % at 6 Hz, decay e^(−0·t), up to 1 s
- t = 0.00 s: emitter **chargeSparksA** @ squishy for 0.5 s: sparkle ×12 (phone 6)/s, life 0.25–0.4 s, speed 4–7, spread 0/0°, Sphere r 1.6 Inward, size 0:0 · 0.4:0.6 · 1:0, colour #FFD86B, transp 0, rot 0–45°, spin -90–90°/s, light 0.7
- t = 0.00 s: FOV kick **chargeFocus**: -3°, in 1 s Sine InOut, hold 0 s, out 0.15 s Quad Out _(Thrower · 1st person only)_
- t = 0.00 s: sound “charge_loop”
- t = 0.50 s: emitter **chargeSparksB** @ squishy for 0.5 s: sparkle ×30 (phone 15)/s, life 0.2–0.35 s, speed 5–8, spread 0/0°, Sphere r 1.6 Inward, size 0:0 · 0.4:0.7 · 1:0, colour #FFFFFF, transp 0, rot 0–45°, spin -90–90°/s, light 0.7
- t = 1.00 s: Highlight **chargeReadyGlow** → squishy: fill #FFFFFF (transp 0.3 → 1), outline #FFD86B (transp 0 → 1), 0.18 s Quad Out
- t = 1.00 s: ring **chargeReadyRing** @ squishy facing forward: ring #FFD86B, 0.8 → 3.6 studs in 0.2 s Quad Out, transparency 0 → 1 Quad In
- t = 1.00 s: burst **chargeReadyPop** @ squishy: sparkle ×10 (phone 5), life 0.2–0.35 s, speed 6–10, spread 180/180°, size 0:0.8 · 1:0, colour #FFFFFF, transp 0, drag 3, rot 0–45°, spin -180–180°/s, light 0.7
- t = 1.00 s: sound “charge_ready_ding”
- t = 1.00 s: text billboard **readyText** “MAX!” @ squishy: #FFD86B with #3B2A35 outline, follows, +(0, 2.2, 0) studs, size (s:studs) 0:0 · 0.08:1.4 · 0.14:1.1 · 0.35:1.1 · 0.45:0, transp 0:0 · 0.35:0 · 0.45:1, 0.45 s
- t = 1.05 s: motion: release · charged speed, aimed 4° up
- t = 1.05 s: pose **throwOverhand** → thrower (3 R15 keys, 0.3 s, fade out 0.2 s)
- t = 1.05 s: squash/stretch **releaseStretchBig** → squishy: 0 s (0.72, 0.72, 1.6) Quad Out → 0.07 s (1.15, 1.15, 0.85) Quad InOut → 0.14 s (0.94, 0.94, 1.14) Sine InOut → 0.22 s (0.97, 0.97, 1.08), holds last key
- t = 1.05 s: wobble **flightJiggle** → squishy: ±6 % at 7 Hz, decay e^(−2.5·t), up to 1.2 s
- t = 1.05 s: trail **flightTrailCharged** @ squishy: width 1.9, life 0.24 s, colour 0:#FFD86B · 0.4:#FF8FB1 · 1:#FFF4E6, transp 0:0.15 · 1:1, width scale 0:1 · 1:0
- t = 1.05 s: emitter **chargedSparkTrail** @ squishy for the whole flight: sparkle ×40 (phone 20)/s, life 0.2–0.35 s, speed 1–3, spread 180/180°, size 0:0.6 · 1:0, colour #FFD86B, transp 0, drag 2, rot 0–45°, spin -180–180°/s, light 0.7
- t = 1.05 s: burst **releasePuff** @ hand → forward: puff ×4 (phone 2), life 0.18–0.28 s, speed 6–10, spread 35/35°, size 0:0.5 · 0.4:1 · 1:0.2, colour #FFF4E6, transp 0:0.2 · 1:1, drag 6, rot 0–360°, spin -90–90°/s
- t = 1.05 s: camera punch **releaseKickBig**: rotation (1.5, 0, 0.6)°, in 0.03 s, hold 0 s, out 0.18 s Back Out _(Thrower · 1st person only)_
- t = 1.05 s: FOV kick **releaseFovCharged**: +4°, in 0.04 s Quad Out, hold 0.03 s, out 0.25 s Sine InOut _(Thrower · 1st person only)_
- t = 1.05 s: sound “throw_charged_whoosh”
- t = 1.05 s: emitter **chargedAura** @ squishy for the whole flight: sparkle ×40 (phone 20)/s, life 0.2–0.3 s, speed 2–5, spread 180/180°, Sphere r 1.5, size 0:0.7 · 1:0, colour #FFD86B, transp 0, rot 0–45°, spin -180–180°/s, light 0.8, **LockedToPart**
- t = bounce + 0.00 s: stop chargedSparkTrail
- t = bounce + 0.00 s: stop chargedAura
- t = rest + 0.00 s: stop flightTrailCharged
- t = rest + 0.00 s: stop rollDust
- t = rest + 0.00 s: wobble **restJiggle** → squishy: ±9 % at 5 Hz, decay e^(−4·t), up to 1 s
- t = rest + 0.00 s: sound “squishy_settle”
- t = bounceBig + 0.00 s: squash/stretch **bounceSquashBig** → squishy: 0 s (1.45, 0.55, 1.45) Quad Out → 0.05 s (0.85, 1.2, 0.85) Quad InOut → 0.11 s (1.06, 0.94, 1.06) Sine InOut → 0.18 s (1, 1, 1)
- t = bounceBig + 0.00 s: burst **bouncePuff** @ floor → up: puff ×8 (phone 4), life 0.25–0.4 s, speed 8–12, spread 8/8°, Cylinder r 0.8, size 0:0.6 · 0.35:1.3 · 1:0.2, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceBig + 0.00 s: burst **bounceDrops** @ floor → up: jelly ×6 (phone 3), life 0.25–0.4 s, speed 10–16, spread 50/50°, size 0:0.45 · 1:0.15, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, VelocityParallel, squash 0.3
- t = bounceBig + 0.00 s: sound “squishy_boing”
- t = bounceBig + 0.00 s: text billboard **boingText** “BOING!” @ floor: #FF8FB1 with #3B2A35 outline, +(0, 2.6, 0) studs, size (s:studs) 0:0 · 0.08:2.6 · 0.14:2.1 · 0.4:2.2 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(Thrower · 1st person / Side · orbit (preview only) only)_
- t = bounceSmall + 0.00 s: squash/stretch **bounceSquashSmall** → squishy: 0 s (1.22, 0.76, 1.22) Quad Out → 0.05 s (0.93, 1.08, 0.93) Sine InOut → 0.12 s (1, 1, 1)
- t = bounceSmall + 0.00 s: burst **bouncePuffSmall** @ floor → up: puff ×4 (phone 2), life 0.2–0.3 s, speed 5–8, spread 8/8°, Cylinder r 0.6, size 0:0.4 · 0.35:0.9 · 1:0.2, colour #FFF4E6, transp 0:0.2 · 0.7:0.5 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceSmall + 0.00 s: sound “squishy_boing_small”
- t = roll + 0.00 s: emitter **rollDust** @ floor → back for the whole flight: puff ×14 (phone 7)/s, life 0.2–0.32 s, speed 1–3, spread 40/40°, size 0:0.3 · 0.4:0.7 · 1:0.1, colour #FFF4E6, transp 0:0.3 · 1:1, accel (0, 4, 0), drag 4, rot 0–360°, spin -60–60°/s
- t = roll + 0.00 s: sound “squishy_roll_loop”

### Miss · bounce + roll

_Side · orbit (preview only) · Thrower · 1st person · Target · 1st person_ — First floor hit switches to bounce gravity 120. Each bounce keeps 45 % of the vertical speed plus a hop from the forward speed, so fast misses skip like candy. Below 9 studs/s it rolls (spin = distance ÷ radius) and settles with a jiggle.

- t = 0.00 s: motion: release · tap speed, aimed 6° down
- t = 0.00 s: pose **throwOverhand** → thrower (3 R15 keys, 0.3 s, fade out 0.2 s)
- t = 0.00 s: squash/stretch **releaseStretch** → squishy: 0 s (0.8, 0.8, 1.45) Quad Out → 0.06 s (1.1, 1.1, 0.88) Quad InOut → 0.12 s (0.96, 0.96, 1.1) Sine InOut → 0.2 s (1, 1, 1.05), holds last key
- t = 0.00 s: wobble **flightJiggle** → squishy: ±6 % at 7 Hz, decay e^(−2.5·t), up to 1.2 s
- t = 0.00 s: trail **flightTrail** @ squishy: width 1.4, life 0.18 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.25 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: sound “throw_whoosh”
- t = rest + 0.00 s: stop flightTrail
- t = rest + 0.00 s: stop rollDust
- t = rest + 0.00 s: wobble **restJiggle** → squishy: ±9 % at 5 Hz, decay e^(−4·t), up to 1 s
- t = rest + 0.00 s: sound “squishy_settle”
- t = bounceBig + 0.00 s: squash/stretch **bounceSquashBig** → squishy: 0 s (1.45, 0.55, 1.45) Quad Out → 0.05 s (0.85, 1.2, 0.85) Quad InOut → 0.11 s (1.06, 0.94, 1.06) Sine InOut → 0.18 s (1, 1, 1)
- t = bounceBig + 0.00 s: burst **bouncePuff** @ floor → up: puff ×8 (phone 4), life 0.25–0.4 s, speed 8–12, spread 8/8°, Cylinder r 0.8, size 0:0.6 · 0.35:1.3 · 1:0.2, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceBig + 0.00 s: burst **bounceDrops** @ floor → up: jelly ×6 (phone 3), life 0.25–0.4 s, speed 10–16, spread 50/50°, size 0:0.45 · 1:0.15, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, VelocityParallel, squash 0.3
- t = bounceBig + 0.00 s: sound “squishy_boing”
- t = bounceBig + 0.00 s: text billboard **boingText** “BOING!” @ floor: #FF8FB1 with #3B2A35 outline, +(0, 2.6, 0) studs, size (s:studs) 0:0 · 0.08:2.6 · 0.14:2.1 · 0.4:2.2 · 0.55:0, transp 0:0 · 0.4:0 · 0.55:1, 0.55 s _(Thrower · 1st person / Side · orbit (preview only) only)_
- t = bounceSmall + 0.00 s: squash/stretch **bounceSquashSmall** → squishy: 0 s (1.22, 0.76, 1.22) Quad Out → 0.05 s (0.93, 1.08, 0.93) Sine InOut → 0.12 s (1, 1, 1)
- t = bounceSmall + 0.00 s: burst **bouncePuffSmall** @ floor → up: puff ×4 (phone 2), life 0.2–0.3 s, speed 5–8, spread 8/8°, Cylinder r 0.6, size 0:0.4 · 0.35:0.9 · 1:0.2, colour #FFF4E6, transp 0:0.2 · 0.7:0.5 · 1:1, accel (0, 6, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceSmall + 0.00 s: sound “squishy_boing_small”
- t = roll + 0.00 s: emitter **rollDust** @ floor → back for the whole flight: puff ×14 (phone 7)/s, life 0.2–0.32 s, speed 1–3, spread 40/40°, size 0:0.3 · 0.4:0.7 · 1:0.1, colour #FFF4E6, transp 0:0.3 · 1:1, accel (0, 4, 0), drag 4, rot 0–360°, spin -60–60°/s
- t = roll + 0.00 s: sound “squishy_roll_loop”

### Catch (crush → burst at 1.02 s)

_Target · 1st person · Side · orbit (preview only) · Thrower · 1st person · lead-in 0.34 s_ — Catcher’s hands clamp it from the sides; the squishy is squeezed in steps with a jiggle, leaking jelly drops, then bursts at 1.02 s. In 1st person the hands hold it low in front of the chest, so it stays in the bottom fifth of the screen; it bulges forward, not up, and every burst sprays down/out, so the centre stays clear.

- t = -0.34 s: squishy flies in (lead-in)
- t = -0.34 s: pose **catchReady** → catcher (1 R15 keys, 0 s, fade in 0.08 s, holds last key)
- t = -0.34 s: trail **flightTrail** @ squishy for 0.34 s: width 1.4, life 0.18 s, colour 0:#FF8FB1 · 1:#FFF4E6, transp 0:0.25 · 1:1, width scale 0:1 · 1:0
- t = 0.00 s: caught: squishy held between the hands
- t = 0.00 s: pose **catchClamp** → catcher (3 R15 keys, 1.02 s, fade in 0 s, holds last key)
- t = 0.00 s: squash/stretch **catchCrush** → squishy: 0 s (0.72, 1.12, 1.3) Quad Out → 0.08 s (1.1, 0.95, 0.95) Sine InOut → 0.18 s (0.82, 1.08, 1.2) Sine InOut → 0.35 s (0.76, 1.1, 1.3) Sine InOut → 0.6 s (0.62, 1.14, 1.45) Sine InOut → 0.85 s (0.5, 1.18, 1.65) Quad In → 1.02 s (0.36, 1.2, 1.9), holds last key
- t = 0.00 s: burst **catchPuff** @ hands → down: puff ×6 (phone 3), life 0.18–0.28 s, speed 5–8, spread 70/70°, size 0:0.4 · 0.4:0.9 · 1:0.2, colour #FFFFFF, transp 0:0.2 · 1:1, drag 6, rot 0–360°, spin -90–90°/s
- t = 0.00 s: ring **catchRing** @ hands facing up: ring #FFFFFF, 0.8 → 3.2 studs in 0.16 s Quad Out, transparency 0.2 → 1 Quad In
- t = 0.00 s: camera punch **catchAbsorb**: offset (0, 0, 0.25) studs, rotation (-1.2, 0, 0)°, in 0.04 s, hold 0 s, out 0.22 s Quad Out _(Target · 1st person only)_
- t = 0.00 s: FOV kick **catchFocus**: -2°, in 0.3 s Sine InOut, hold 0.6 s, out 0.15 s Quad Out _(Target · 1st person only)_
- t = 0.00 s: sound “catch_smack”
- t = 0.00 s: screen banner **caughtBanner** “CAUGHT!”: #8EDFC4, 84 px @1080p with 12 px #3B2A35 outline; drops from 8 % to 22 % from the top in 0.18 s Back Out, holds 0.7 s, leaves 0.25 s _(Target · 1st person only)_
- t = 0.05 s: sound “squish_squeeze_loop”
- t = 0.05 s: emitter **catchLeak** @ hands → down for 0.95 s: jelly ×14 (phone 7)/s, life 0.25–0.4 s, speed 4–8, spread 55/55°, size 0:0.3 · 1:0.1, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -60, 0), drag 1, VelocityParallel, squash 0.3
- t = 1.02 s: squishy bursts (hidden)
- t = 1.02 s: burst **catchBurstJelly** @ hands → down: jelly ×18 (phone 9), life 0.3–0.5 s, speed 18–30, spread 80/80°, size 0:0.55 · 0.3:0.7 · 1:0.2, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1.5, VelocityParallel, squash 0.3
- t = 1.02 s: burst **catchBurstConfetti** @ hands → down: confetti ×16 (phone 8), life 0.4–0.65 s, speed 16–26, spread 80/80°, size 0.3, tints #8EDFC4 / #FFD86B (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -110, 0), drag 1, rot 0–360°, spin -540–540°/s
- t = 1.02 s: burst **catchBurstPuff** @ hands → down: puff ×6 (phone 3), life 0.2–0.3 s, speed 6–10, spread 70/70°, size 0:0.6 · 0.4:1.6 · 1:0.3, colour #FFC7DA, transp 0:0.1 · 1:1, drag 6, rot 0–360°, spin -90–90°/s
- t = 1.02 s: ring **catchBurstRing** @ hands facing up: ring #FF8FB1, 1 → 6 studs in 0.2 s Quad Out, transparency 0.1 → 1 Quad In
- t = 1.02 s: pose **catchRelease** → catcher (2 R15 keys, 0.25 s, fade out 0.25 s)
- t = 1.02 s: camera shake **catchShake**: 0.6°, 0.15 s, 22 Hz, decay Quad Out, axes pitch/yaw/roll 1/0.6/0.3 _(Target · 1st person only)_
- t = 1.02 s: sound “catch_burst_pop”
- t = 1.02 s: burst **catchBurstStars** @ hands → down: star ×10 (phone 5), life 0.3–0.5 s, speed 14–22, spread 70/70°, size 0:0.8 · 1:0, colour #FFD86B, transp 0, accel (0, -60, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2

#### Part 3 · Duel flight — R15 pose keys

Per key: `t (easing to next): Joint X,Y,Z°`. Joints a track keys somewhere but a key omits are 0,0,0. RootPos is a Root translation in studs (character space, −Z = forward).

- **throwOverhand** (fade out 0.2 s)
  - 0.00 s (Quad Out): Waist -6,-25,0 · RightShoulder 165,0,20 · RightElbow 90,0,0 · LeftShoulder 70,0,-15 · LeftElbow 20,0,0
  - 0.06 s (Cubic Out): Waist -12,20,0 · RightShoulder 85,0,10 · RightElbow 10,0,0 · LeftShoulder 20,0,-30 · LeftElbow 30,0,0 · LeftHip -10,0,0 · RightHip 20,0,0 · RightKnee -25,0,0
  - 0.30 s: Waist -6,10,0 · RightShoulder 55,0,8 · RightElbow 20,0,0 · LeftShoulder 10,0,-15 · LeftElbow 20,0,0
- **chargeHold** (fade in 0.1 s)
  - 0.00 s (Cubic Out): Waist -4,-12,0 · RightShoulder 55,0,25 · RightElbow 60,0,0 · LeftShoulder 75,0,10 · LeftElbow 10,0,0
  - 1.00 s: Waist -6,-22,0 · RightShoulder 62,0,30 · RightElbow 72,0,0 · LeftShoulder 80,0,8 · LeftElbow 8,0,0
- **catchReady** (fade in 0.08 s)
  - 0.00 s: Neck -8,0,0 · LeftShoulder 45,0,22 · RightShoulder 45,0,-22 · LeftElbow 25,0,0 · RightElbow 25,0,0
- **catchClamp** (fade in 0 s)
  - 0.00 s (Cubic Out): Root 6,0,0 · RootPos 0,-0.2,0.15 · Waist -8,0,0 · Neck -10,0,0 · LeftShoulder 38,0,30 · RightShoulder 38,0,-30 · LeftElbow 30,0,0 · RightElbow 30,0,0
  - 0.12 s (Sine InOut): Root 0,0,0 · RootPos 0,-0.1,0.05 · Waist -6,0,0 · Neck -10,0,0 · LeftShoulder 38,0,28 · RightShoulder 38,0,-28 · LeftElbow 28,0,0 · RightElbow 28,0,0
  - 1.02 s: Waist -10,0,0 · Neck -12,0,0 · LeftShoulder 40,0,36 · RightShoulder 40,0,-36 · LeftElbow 36,0,0 · RightElbow 36,0,0
- **catchRelease** (fade out 0.25 s)
  - 0.00 s (Cubic Out): Neck 10,0,0 · LeftShoulder 60,0,-40 · RightShoulder 60,0,40 · LeftElbow 20,0,0 · RightElbow 20,0,0
  - 0.25 s: Neck 0,0,0 · LeftShoulder 20,0,-20 · RightShoulder 20,0,20 · LeftElbow 15,0,0 · RightElbow 15,0,0

---

## Part 4 · Highway (`highway.html`)

Your highway throw: charged wind-up, sound-barrier launch, a themed blast through each of the 7 zones, a crater landing and a fireworks finish exactly on the game’s stop point.

**Signals:** `sonic` — release when D ≥ 2000; `fast` — every 0.22 s above 400 studs/s; `apex` — top of the arc (`apexLong` too when D ≥ 2000); `zoneExit` → `zone` → `zone_<id>` — in that order when the squishy crosses a zone start (ids: meadow, bakery, lagoon, frozen, lava, rainbow, heaven); `bounce1` (+ `impactBig` when D ≥ 2000), `bounceN`, `lastBounce`, `roll`, `stop` — exactly on D.

**Stop-point solver.** Bounces: 1 below 300, 2 below 2000, else 3. First bounce = D × 0.06 clamped 3–220, each next × 0.45; first bounce height = apex × 0.22 clamped 1.2–14, each next × 0.4 (bounce time 2·√(2h/196.2)). Roll = D × 0.035 clamped 2.5–60, constant slow-down from 0.85 × the last bounce speed to 0. **Flight = D − bounces − roll**, so the stop is always exactly D. Apex = flight × 0.18 (min 6, never above 60), flight time = 1 + 0.075·√flight clamped 1.2–7.5 s, forward progress 60 % linear + 40 % Quad Out.

| D | flight | bounces | roll | flight time | apex | path time |
|---|---|---|---|---|---|---|
| 70 | 63.3 | 4.2 | 2.5 | 1.60 s | 14.3 | 2.36 s |
| 1,200 | 1053.6 | 72.0 + 32.4 | 42.0 | 3.43 s | 58.3 | 5.95 s |
| 4,000 | 3576.4 | 220.0 + 99.0 + 44.6 | 60.0 | 5.49 s | 58.3 | 7.81 s |
| 8,500 | 8076.4 | 220.0 + 99.0 + 44.6 | 60.0 | 7.50 s | 58.3 | 9.83 s |

_Game time from release with a 4.6-stud release height; the slow-mos stretch it in real time._

**Why LockedToPart:** at 1,000 studs/s the chase camera passes a world-space particle in ~0.03 s, so anything meant to be seen in flight rides the squishy (ParticleEmitter.LockedToPart, rings/billboards welded to it). Ground effects stay in the world; the impact freeze + slow-mo give them screen time.

**Camera:** wind-up push-in (Back 10, Up 4.2, FOV 64), chase from Launch (13/5.5, 70°) to Fast (30/12, 80°) by speed 120–1200 studs/s, offsets smoothed at 6/s, bank roll ±3° × speed factor at 0.16 Hz (off with reduce motion), hero shot after the stop. **Zones** (preview starts, replace with the real ones): Candy Meadow 0 #8EDFC4, Bakery Town 400 #FFD25E, Boba Lagoon 1100 #8CC8FF, Frozen Dessert Peaks 2000 #B9A6E8, Lava Volcano 3200 #F2687F, Rainbow Road 4800 #B892F0, Divine Heaven 6800 #FFD86B.

### Highway throw (all distances)

_Short · 70 studs · Medium · 1,200 studs · Long · 4,000 studs · Max · 8,500 studs · Custom distance (slider) · lead-in 0.5 s · slow-mo allowed_

- t = -0.50 s: pose **windup** → thrower (2 R15 keys, 0.5 s)
- t = -0.50 s: squash/stretch **windupSquish** → squishy: 0 s (1, 1, 1) Sine InOut → 0.5 s (1.14, 0.86, 1.14), holds last key
- t = -0.50 s: emitter **windupSparks** @ squishy for 0.45 s: sparkle ×60 (phone 30)/s, life 0.22–0.32 s, speed 9–12, spread 0/0°, Sphere r 3 Inward, size 0:0 · 0.4:0.7 · 1:0, colour #FFD86B, transp 0, rot 0–45°, spin -90–90°/s, light 0.7, **LockedToPart**
- t = -0.50 s: ring **chargeInRing** @ feet facing up: ring #FFD86B, 14 → 2.5 studs in 0.45 s Quad In, transparency 1 → 0.2 Quad Out
- t = -0.50 s: sound “windup_charge_rise”
- t = -0.40 s: letterbox **cineBars**: #3B2A35 bars, 9 % of the screen each, in 0.2 s, hold 0.75 s, out 0.3 s
- t = 0.00 s: motion: release · path solved so it stops exactly at D
- t = 0.00 s: pose **throwBig** → thrower (2 R15 keys, 0.45 s)
- t = 0.00 s: squash/stretch **launchStretch** → squishy: 0 s (0.7, 0.7, 1.7) Quad Out → 0.1 s (1.12, 1.12, 0.86) Quad InOut → 0.2 s (0.95, 0.95, 1.12) Sine InOut → 0.32 s (0.97, 0.97, 1.08), holds last key
- t = 0.00 s: wobble **flightWobble** → squishy: ±5 % at 6 Hz, decay e^(−0.8·t)
- t = 0.00 s: slow-mo **releaseSlow**: ×0.3, in 0.04 s, hold 0.3 s, out 0.35 s Sine InOut
- t = 0.00 s: FOV kick **launchFov**: +8°, in 0.08 s, hold 0.3 s, out 0.6 s Sine InOut
- t = 0.00 s: camera shake **launchShake**: 0.8°, 0.25 s, 18 Hz, decay Quad Out, axes 1/0.6/0.4
- t = 0.00 s: burst **launchStars** @ squishy → back: star ×16 (phone 8), life 0.4–0.7 s, speed 20–34, spread 50/50°, size 0:1 · 0.7:0.9 · 1:0, colour 0:#FFFFFF · 0.2:#FFD86B · 1:#FFD86B, transp 0, accel (0, -40, 0), drag 2, rot 0–360°, spin -300–300°/s, light 0.2
- t = 0.00 s: burst **launchSparkles** @ squishy: sparkle ×12 (phone 6), life 0.3–0.5 s, speed 3–7, spread 180/180°, Sphere r 1.5, size 0:0 · 0.3:1.1 · 1:0, colour #FFFFFF, transp 0, drag 2, rot 0–45°, spin -90–90°/s, light 0.7
- t = 0.00 s: burst **launchPuff** @ squishy → forward: puff ×8 (phone 4), life 0.25–0.4 s, speed 8–12, spread 40/40°, size 0:0.7 · 0.35:1.6 · 1:0.3, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, drag 6, rot 0–360°, spin -90–90°/s
- t = 0.00 s: ring **launchRing** @ squishy facing forward: ring #FFFFFF, 1 → 9 studs in 0.3 s Quad Out, transparency 0.05 → 1 Quad In
- t = 0.00 s: ring **launchShock** @ feet facing up: ring #FFFFFF, 2 → 22 studs in 0.4 s Quad Out, transparency 0 → 1 Quad In
- t = 0.00 s: burst **launchDust** @ feet → up: puff ×18 (phone 9), life 0.35–0.55 s, speed 18–28, spread 10/10°, Cylinder r 1.5, size 0:1 · 0.35:2.4 · 1:0.4, colour #FFF4E6, transp 0:0 · 0.7:0.3 · 1:1, accel (0, 12, 0), drag 5, rot 0–360°, spin -120–120°/s
- t = 0.00 s: PointLight **launchLight** @ squishy: #FFF4E6, brightness 4 → 0, range 24, 0.35 s Quad Out
- t = 0.00 s: HUD counter **distanceCounter**: distance travelled + “studs”, 76 px @1080p, 9 % from the top, #FFFFFF → #FFD86B and ×1.4 Back Out pop at the stop
- t = 0.00 s: trail in the current zone colour
- t = 0.00 s: emitter **meadowConfetti** @ squishy → back [group zoneAmbient] for until stopped: confetti ×40 (phone 20)/s, life 0.35–0.55 s, speed 16–26, spread 35/35°, size 0.4, tints #FF8FB1 / #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -20, 0), drag 2, rot 0–360°, spin -540–540°/s, **LockedToPart**
- t = 0.00 s: sound “highway_launch_whoomp”
- t = sonic + 0.05 s: ring **sonicRing** @ squishy facing forward: ring #FFFFFF, 3 → 16 studs in 0.4 s Quad Out, transparency 0.1 → 1 Quad In
- t = sonic + 0.05 s: speed lines **sonicLines**: speedline #FFFFFF ×22 (phone 11) between 50–100 % of the half-diagonal, 220–380 px, 0.35 s, opacity 0.85
- t = sonic + 0.05 s: sound “sonic_boom”
- t = sonic + 0.11 s: ring **sonicRing** @ squishy facing forward: ring #FFFFFF, 3 → 16 studs in 0.4 s Quad Out, transparency 0.1 → 1 Quad In
- t = sonic + 0.17 s: ring **sonicRing** @ squishy facing forward: ring #FFFFFF, 3 → 16 studs in 0.4 s Quad Out, transparency 0.1 → 1 Quad In
- t = fast + 0.00 s: speed lines **speedLines**: speedline #FFFFFF ×10 (phone 5) between 62–100 % of the half-diagonal, 160–300 px, 0.3 s, opacity 0.55
- t = apex + 0.00 s: sound “apex_whistle”
- t = apexLong + 0.00 s: slow-mo **apexHang**: ×0.6, in 0.15 s, hold 0.25 s, out 0.35 s Sine InOut
- t = apexLong + 0.00 s: burst **apexTwinkle** @ squishy: sparkle ×16 (phone 8), life 0.3–0.5 s, speed 8–14, spread 180/180°, size 0:0 · 0.3:1 · 1:0, colour #FFFFFF, transp 0, drag 3, rot 0–45°, spin -120–120°/s, light 0.7, **LockedToPart**
- t = zoneExit + 0.00 s: stop zoneAmbient
- t = zone + 0.00 s: zoneRing (follows) + zoneSparkles in the zone colour, trail colour swaps
- t = zone + 0.00 s: screen banner **zoneBanner**: zone name in the zone colour, 84 px @1080p with 12 px #3B2A35 outline; drops from 6 % to 20 % from the top (×0.6 → 1) in 0.2 s Back Out, holds 0.8 s, leaves 0.25 s; a new gate replaces it
- t = zone + 0.00 s: speed lines **zoneWarp**: speedline zone colour ×18 (phone 9) between 55–100 % of the half-diagonal, 200–360 px, 0.35 s, opacity 0.75
- t = zone + 0.00 s: sound “zone_chime”
- t = zone_bakery + 0.00 s: burst **sprinkleBurst** @ squishy: confetti ×40 (phone 20), life 0.45–0.7 s, speed 24–36, spread 180/180°, size 0.4, tints #FF8FB1 / #8CC8FF / #FFF4E6 / #8EDFC4 (1 emitter each), transp 0:0 · 0.8:0 · 1:1, drag 2.5, rot 0–360°, spin -540–540°/s, **LockedToPart**
- t = zone_bakery + 0.00 s: emitter **bakerySprinkles** @ squishy → back [group zoneAmbient] for until stopped: confetti ×40 (phone 20)/s, life 0.35–0.55 s, speed 16–26, spread 35/35°, size 0.32, tints #FF8FB1 / #8CC8FF / #FFF4E6 / #8EDFC4 (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -20, 0), drag 2, rot 0–360°, spin -540–540°/s, **LockedToPart**
- t = zone_lagoon + 0.00 s: burst **splashBurst** @ squishy: jelly ×28 (phone 14), life 0.35–0.55 s, speed 20–32, spread 180/180°, size 0:0.7 · 1:0.2, colour #8CC8FF, transp 0:0 · 0.8:0 · 1:1, accel (0, -60, 0), drag 2, VelocityParallel, squash 0.3, **LockedToPart**
- t = zone_lagoon + 0.00 s: emitter **lagoonBubbles** @ squishy → back [group zoneAmbient] for until stopped: ring ×30 (phone 15)/s, life 0.4–0.7 s, speed 6–12, spread 50/50°, Sphere r 1.4, size 0:0.2 · 0.5:0.7 · 1:0.9, colour #FFFFFF, transp 0:0.1 · 0.85:0.3 · 1:1, accel (0, 18, 0), drag 2, light 0.3, **LockedToPart**
- t = zone_lagoon + 0.00 s: sound “splash_bloop”
- t = zone_frozen + 0.00 s: burst **frostBurst** @ squishy: sparkle ×30 (phone 15), life 0.35–0.55 s, speed 22–34, spread 180/180°, size 0:0 · 0.25:1.2 · 1:0, colour 0:#FFFFFF · 1:#CFE0FF, transp 0, drag 3, rot 0–45°, spin -180–180°/s, light 0.7, **LockedToPart**
- t = zone_frozen + 0.00 s: screen vignette **frostVignette**: #CFE0FF at 55 %, clear centre 50 %, in 0.12 s, hold 0.35 s, out 0.6 s
- t = zone_frozen + 0.00 s: emitter **snowSparkles** @ squishy → back [group zoneAmbient] for until stopped: sparkle ×40 (phone 20)/s, life 0.35–0.6 s, speed 10–18, spread 45/45°, Sphere r 1.2, size 0:0 · 0.3:0.75 · 1:0, colour 0:#FFFFFF · 1:#CFE0FF, transp 0, accel (0, -12, 0), drag 2, rot 0–45°, spin -120–120°/s, light 0.7, **LockedToPart**
- t = zone_frozen + 0.00 s: sound “frost_crackle”
- t = zone_lava + 0.00 s: burst **lavaBurst** @ squishy: star ×28 (phone 14), life 0.35–0.6 s, speed 22–36, spread 180/180°, size 0:1 · 1:0, colour 0:#FFE36B · 0.5:#FF9A5C · 1:#F2687F, transp 0, accel (0, 30, 0), drag 3, rot 0–360°, spin -300–300°/s, light 0.4, **LockedToPart**
- t = zone_lava + 0.00 s: screen vignette **heatVignette**: #FF8A5C at 40 %, clear centre 50 %, in 0.12 s, hold 0.3 s, out 0.6 s
- t = zone_lava + 0.00 s: camera shake **heatRumble**: 0.5°, 0.35 s, 12 Hz, decay Quad Out, axes 1/0.5/0.3
- t = zone_lava + 0.00 s: emitter **lavaEmbers** @ squishy → back [group zoneAmbient] for until stopped: sparkle ×50 (phone 25)/s, life 0.35–0.6 s, speed 12–22, spread 40/40°, Sphere r 1.2, size 0:0.7 · 1:0, colour 0:#FFE36B · 0.5:#FF9A5C · 1:#F2687F, transp 0, accel (0, 26, 0), drag 2, rot 0–45°, spin -180–180°/s, light 0.8, **LockedToPart**
- t = zone_lava + 0.00 s: sound “lava_whoosh”
- t = zone_rainbow + 0.00 s: burst **rainbowBurst** @ squishy: confetti ×48 (phone 24), life 0.45–0.7 s, speed 24–36, spread 180/180°, size 0.42, tints #FF6B8B / #FFB36B / #FFE36B / #8EDFC4 / #8CC8FF / #B892F0 (1 emitter each), transp 0:0 · 0.8:0 · 1:1, drag 2.5, rot 0–360°, spin -540–540°/s, **LockedToPart**
- t = zone_rainbow + 0.00 s: trail **bandRed** @ band + X -1.5 [group zoneAmbient]: width 0.6, life 0.45 s, colour #FF6B8B, transp 0:0.1 · 1:1, width scale 0:1 · 1:0.6, flat (FaceCamera off)
- t = zone_rainbow + 0.00 s: trail **bandOrange** @ band + X -0.9 [group zoneAmbient]: width 0.6, life 0.45 s, colour #FFB36B, transp 0:0.1 · 1:1, width scale 0:1 · 1:0.6, flat (FaceCamera off)
- t = zone_rainbow + 0.00 s: trail **bandYellow** @ band + X -0.3 [group zoneAmbient]: width 0.6, life 0.45 s, colour #FFE36B, transp 0:0.1 · 1:1, width scale 0:1 · 1:0.6, flat (FaceCamera off)
- t = zone_rainbow + 0.00 s: trail **bandMint** @ band + X 0.3 [group zoneAmbient]: width 0.6, life 0.45 s, colour #8EDFC4, transp 0:0.1 · 1:1, width scale 0:1 · 1:0.6, flat (FaceCamera off)
- t = zone_rainbow + 0.00 s: trail **bandSky** @ band + X 0.9 [group zoneAmbient]: width 0.6, life 0.45 s, colour #8CC8FF, transp 0:0.1 · 1:1, width scale 0:1 · 1:0.6, flat (FaceCamera off)
- t = zone_rainbow + 0.00 s: trail **bandViolet** @ band + X 1.5 [group zoneAmbient]: width 0.6, life 0.45 s, colour #B892F0, transp 0:0.1 · 1:1, width scale 0:1 · 1:0.6, flat (FaceCamera off)
- t = zone_rainbow + 0.00 s: sound “rainbow_shimmer”
- t = zone_heaven + 0.00 s: burst **heavenBurst** @ squishy: star ×30 (phone 15), life 0.4–0.65 s, speed 20–32, spread 180/180°, size 0:1 · 0.7:0.8 · 1:0, colour 0:#FFFFFF · 0.3:#FFE7A3 · 1:#FFD86B, transp 0, drag 3, rot 0–360°, spin -240–240°/s, light 0.5, **LockedToPart**
- t = zone_heaven + 0.00 s: ring **haloRing** @ squishy facing up (follows the squishy): ring #FFD86B, 3 → 16 studs in 0.45 s Quad Out, transparency 0 → 1 Quad In
- t = zone_heaven + 0.00 s: Highlight **heavenGlow** → squishy: fill #FFE7A3 (transp 0.3 → 1), outline #FFD86B, 0.5 s Quad Out
- t = zone_heaven + 0.00 s: screen vignette **heavenVignette**: #FFF6D6 at 60 %, clear centre 50 %, in 0.15 s, hold 0.35 s, out 0.7 s
- t = zone_heaven + 0.00 s: emitter **heavenSparkles** @ squishy → back [group zoneAmbient] for until stopped: star ×36 (phone 18)/s, life 0.4–0.65 s, speed 8–14, spread 60/60°, Sphere r 1.6, size 0:0 · 0.3:0.8 · 1:0, colour 0:#FFFFFF · 0.4:#FFE7A3 · 1:#FFD86B, transp 0, drag 2, rot 0–360°, spin -200–200°/s, light 0.6, **LockedToPart**
- t = zone_heaven + 0.00 s: sound “choir_hit”
- t = bounce1 + 0.00 s: stop zoneAmbient
- t = bounce1 + 0.00 s: squash/stretch **bounceSquashBig** → squishy: 0 s (1.6, 0.45, 1.6) Quad Out → 0.06 s (0.82, 1.25, 0.82) Quad InOut → 0.13 s (1.08, 0.92, 1.08) Sine InOut → 0.22 s (1, 1, 1)
- t = bounce1 + 0.00 s: burst **landPuffBig** @ floor → up: puff ×20 (phone 10), life 0.35–0.55 s, speed 20–32, spread 10/10°, Cylinder r 1.5, size 0:1.2 · 0.35:2.8 · 1:0.5, colour #FFF4E6, transp 0:0 · 0.7:0.3 · 1:1, accel (0, 14, 0), drag 6, rot 0–360°, spin -120–120°/s
- t = bounce1 + 0.00 s: burst **landDrops** @ floor → up: jelly ×10 (phone 5), life 0.35–0.55 s, speed 14–24, spread 50/50°, size 0:0.6 · 1:0.2, colour #FF8FB1, transp 0:0 · 0.8:0 · 1:1, accel (0, -120, 0), drag 1, VelocityParallel, squash 0.3
- t = bounce1 + 0.00 s: burst **impactStars** @ floor → up: star ×14 (phone 7), life 0.4–0.6 s, speed 18–30, spread 55/55°, size 0:1 · 0.7:0.8 · 1:0, colour #FFD86B, transp 0, accel (0, -70, 0), drag 1, rot 0–360°, spin -300–300°/s, light 0.2
- t = bounce1 + 0.00 s: ring **landRing** @ floor facing up: ring #FFF4E6, 2 → 14 studs in 0.35 s Quad Out, transparency 0.05 → 1 Quad In
- t = bounce1 + 0.00 s: camera shake **landShake**: 1.2°, 0.3 s, 16 Hz, decay Quad Out, axes 1/0.6/0.4
- t = bounce1 + 0.00 s: sound “land_boing_big”
- t = bounce1 + 0.05 s: ring **craterRing** @ floor facing up: ring #FFFFFF, 4 → 26 studs in 0.45 s Quad Out, transparency 0.1 → 1 Quad In
- t = impactBig + 0.00 s: hit-stop **impactFreeze**: freeze 0.06 s
- t = impactBig + 0.00 s: slow-mo **impactSlow**: ×0.35, in 0.02 s, hold 0.2 s, out 0.3 s Sine InOut
- t = bounceN + 0.00 s: squash/stretch **bounceSquashSmall** → squishy: 0 s (1.3, 0.7, 1.3) Quad Out → 0.06 s (0.9, 1.12, 0.9) Sine InOut → 0.14 s (1, 1, 1)
- t = bounceN + 0.00 s: burst **bouncePuff** @ floor → up: puff ×8 (phone 4), life 0.25–0.4 s, speed 8–12, spread 8/8°, Cylinder r 0.9, size 0:0.6 · 0.35:1.4 · 1:0.2, colour #FFF4E6, transp 0:0.1 · 0.7:0.4 · 1:1, accel (0, 8, 0), drag 7, rot 0–360°, spin -90–90°/s
- t = bounceN + 0.00 s: sound “land_boing_small”
- t = lastBounce + 0.00 s: slow-mo **finalSlow**: ×0.5, in 0.08 s, hold 0.35 s, out 0.3 s Sine InOut
- t = roll + 0.00 s: squash/stretch **bounceSquashSmall** → squishy: 0 s (1.3, 0.7, 1.3) Quad Out → 0.06 s (0.9, 1.12, 0.9) Sine InOut → 0.14 s (1, 1, 1)
- t = roll + 0.00 s: emitter **rollDust** @ floor → back for until stopped: puff ×16 (phone 8)/s, life 0.2–0.35 s, speed 1–3, spread 40/40°, size 0:0.35 · 0.4:0.8 · 1:0.1, colour #FFF4E6, transp 0:0.3 · 1:1, accel (0, 4, 0), drag 4, rot 0–360°, spin -60–60°/s
- t = roll + 0.00 s: sound “roll_squish_loop”
- t = stop + 0.00 s: stop rollDust
- t = stop + 0.00 s: trail off
- t = stop + 0.00 s: squash/stretch **stopSquash** → squishy: 0 s (1.3, 0.7, 1.3) Quad Out → 0.1 s (0.88, 1.18, 0.88) Sine InOut → 0.22 s (1.05, 0.95, 1.05) Sine InOut → 0.34 s (1, 1, 1)
- t = stop + 0.00 s: burst **stopConfetti** @ floor → up: confetti ×40 (phone 20), life 0.8–1.2 s, speed 22–36, spread 35/35°, size 0.45, tints #FF8FB1 / #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.8:0 · 1:1, accel (0, -70, 0), drag 1.2, rot 0–360°, spin -540–540°/s
- t = stop + 0.00 s: burst **stopSparkles** @ squishy: sparkle ×14 (phone 7), life 0.4–0.7 s, speed 3–7, spread 180/180°, Sphere r 2, size 0:0 · 0.3:1.3 · 1:0, colour #FFFFFF, transp 0, drag 2, rot 0–45°, spin -90–90°/s, light 0.7
- t = stop + 0.00 s: ring **stopRing** @ floor facing up: ring #FFD86B, 2 → 14 studs in 0.4 s Quad Out, transparency 0 → 1 Quad In
- t = stop + 0.00 s: Highlight **stopGlow** → squishy: fill #FFFFFF (transp 0.35 → 1), outline #FFD86B, 0.35 s Quad Out
- t = stop + 0.00 s: PointLight **stopLight** @ squishy: #FFD86B, brightness 3 → 0, range 22, 1.2 s Quad Out
- t = stop + 0.00 s: text billboard **distancePop** @ squishy: distance text, #FFD86B with #3B2A35 outline, follows +(0, 5.5, 0) studs, height (s:studs) 0:0 · 0.18:3.6 · 0.3:3 · 1.2:3 · 1.45:0, transp 0:0 · 1.2:0 · 1.45:1, 1.45 s
- t = stop + 0.00 s: letterbox **cineBarsHero**: #3B2A35 bars, 9 % of the screen each, in 0.3 s, hold 0.85 s, out 0.3 s
- t = stop + 0.00 s: camera swings to the hero shot
- t = stop + 0.00 s: sound “highway_stop_fanfare”
- t = stop + 0.10 s: emitter **confettiRain** @ squishy + (0, 18, 6) → down for 0.5 s: confetti ×50 (phone 25)/s, life 0.9–1 s, speed 2–6, spread 20/20°, Box 24×1×24, size 0.45, tints #FF8FB1 / #8EDFC4 / #FFD86B / #8CC8FF (1 emitter each), transp 0:0 · 0.85:0 · 1:1, accel (0, -36, 0), drag 0.5, rot 0–360°, spin -540–540°/s
- t = stop + 0.30 s: burst **fireworkA** @ squishy + (-7, 10, 14): star ×36 (phone 18), life 0.6–0.9 s, speed 12–18, spread 180/180°, size 0:0.9 · 0.7:0.7 · 1:0, tints #FF8FB1 / #FFD86B (1 emitter each), transp 0:0 · 0.75:0 · 1:1, accel (0, -14, 0), drag 3, rot 0–360°, spin -240–240°/s, light 0.4
- t = stop + 0.30 s: billboard **fireworkFlash** @ squishy + (-7, 10, 14): sparkle #FFFFFF, height (s:studs) 0:1 · 0.06:7 · 0.2:0, transp 0, 0.2 s
- t = stop + 0.30 s: sound “firework_pop”
- t = stop + 0.55 s: burst **fireworkB** @ squishy + (5, 13, 20): star ×36 (phone 18), life 0.6–0.9 s, speed 12–18, spread 180/180°, size 0:0.9 · 0.7:0.7 · 1:0, tints #8EDFC4 / #8CC8FF (1 emitter each), transp 0:0 · 0.75:0 · 1:1, accel (0, -14, 0), drag 3, rot 0–360°, spin -240–240°/s, light 0.4
- t = stop + 0.55 s: billboard **fireworkFlash** @ squishy + (5, 13, 20): sparkle #FFFFFF, height (s:studs) 0:1 · 0.06:7 · 0.2:0, transp 0, 0.2 s
- t = stop + 0.55 s: sound “firework_pop”
- t = stop + 0.80 s: burst **fireworkC** @ squishy + (-1, 8.5, 26): star ×36 (phone 18), life 0.6–0.9 s, speed 12–18, spread 180/180°, size 0:0.9 · 0.7:0.7 · 1:0, tints #B9A6E8 / #FFFFFF (1 emitter each), transp 0:0 · 0.75:0 · 1:1, accel (0, -14, 0), drag 3, rot 0–360°, spin -240–240°/s, light 0.4
- t = stop + 0.80 s: billboard **fireworkFlash** @ squishy + (-1, 8.5, 26): sparkle #FFFFFF, height (s:studs) 0:1 · 0.06:7 · 0.2:0, transp 0, 0.2 s
- t = stop + 0.80 s: sound “firework_pop”

#### Part 4 · Highway — R15 pose keys

- **windup** (fade in 0.12 s)
  - 0.00 s (Cubic InOut): Root 5,0,0 · Waist 8,-35,0 · RightShoulder 150,0,35 · RightElbow 100,0,0 · LeftShoulder 85,0,-10 · LeftElbow 10,0,0 · LeftHip 30,0,0 · LeftKnee -30,0,0 · RightHip -20,0,0
  - 0.50 s: Root 6,0,0 · Waist 12,-45,0 · RightShoulder 165,0,40 · RightElbow 110,0,0 · LeftShoulder 90,0,-10 · LeftElbow 5,0,0 · LeftHip 35,0,0 · LeftKnee -35,0,0 · RightHip -25,0,0
- **throwBig** (fade out 0.3 s)
  - 0.00 s (Cubic Out): Root -10,0,0 · Waist -18,30,0 · RightShoulder 95,0,10 · RightElbow 5,0,0 · LeftShoulder 10,0,-35 · LeftElbow 30,0,0 · LeftHip 40,0,0 · LeftKnee -20,0,0 · RightHip -30,0,0 · RightKnee -40,0,0
  - 0.45 s: Root -4,0,0 · Waist -8,20,0 · RightShoulder 50,0,8 · RightElbow 20,0,0 · LeftShoulder 10,0,-20 · LeftElbow 20,0,0 · LeftHip 15,0,0 · RightHip -10,0,0 · RightKnee -15,0,0
