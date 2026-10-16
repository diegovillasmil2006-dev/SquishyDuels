--!strict
-- Config.Combat: hitbox, throw validation tolerances, lag, aim assist, throw stat bands and the power budget
-- (DESIGN §5.5-§5.10), and feature 1's charge throw and catch (Charge, Catch). Shared, data only. All [P]. Duel rules
-- (lives, cooldown clamp, projectile limits, phase timings) are in Config.Duel.Rules; Dragon Rush is in
-- Config.Abilities.

export type AimAssist = { enabled: boolean, coneDeg: number, strength: number }
export type Band = { min: number, max: number }

local Combat = {
	-- One standard capsule per player (§5.5): axis from HRP + (0, bottomOffset, 0) to HRP + (0, topOffset, 0)
	-- along world up (tilt ignored). Covers floor+0 .. floor+6.1, 2.6 studs wide. Also the practice target hitbox.
	Hitbox = {
		bottomOffset = -1.7,
		topOffset = 1.8,
		radius = 1.3,
	},

	-- Throw origin relative to the HRP CFrame: right, up, forward (-Z) (§5.6).
	ReleaseOffset = Vector3.new(1.0, 1.8, -1.5),

	-- Server projectile simulation (§5.7). Live-projectile cap and lifetime are Duel.Rules.
	Projectile = {
		substepsPerSecond = 60, -- n = clamp(ceil((tNow - tPrev) * 60), 1, maxSubsteps)
		maxSubsteps = 6,
		practiceBroadcastStuds = 200, -- practice ThrowStarted / ThrowImpact reach players this close
	},

	-- ThrowRules validation tolerances (§5.6), cheapest check first.
	Throw = {
		seqWindow = 1000, -- seq must be > lastSeq and < lastSeq + seqWindow
		aimMagnitudeMin = 0.95,
		aimMagnitudeMax = 1.05,
		pitchMinDeg = -35, -- also the pitch clamp of ProjectileMath.solveLaunchDir (§5.5)
		pitchMaxDeg = 65,
		noSolutionPitchDeg = 45, -- solveLaunchDir fallback when the target is out of reach
		zoneToleranceStuds = 2, -- HRP inside own half + 2 studs
		practiceConeDeg = 75, -- dot(flat aim, range forward) >= cos 75°
		originBaseStuds = 3, -- originHint accepted within originBaseStuds + originPerPingStuds * min(ping, cap)
		originPerPingStuds = 16,
		originPingCapSeconds = 0.25,
	},

	-- Lag policy (§5.6 #7, §5.7). v1 never rewinds.
	Lag = {
		TargetRewindMs = 0, -- reserved
		maxCompensationSeconds = 0.12, -- lat = clamp(now - clientTime, 0, min(ping/2 + halfPingExtra, max))
		halfPingExtraSeconds = 0.03,
		clientTimeEarlySeconds = 0.05, -- now - clientTime < -0.05 is abnormal: lat = min(ping/2, max)
		clientTimeLateSeconds = 1.0, -- now - clientTime > 1.0 is abnormal
	},

	-- Movement guard (Logic/MovementRules, §5.7).
	MovementGuard = {
		checkHz = 5,
		maxHorizontalSpeed = 30, -- studs/s
		overSpeedSamples = 3, -- consecutive samples above the limit, outside teleport/knockback grace
		hitGraceSeconds = 0.5, -- grace after a hit (knockback)
		-- Reading (DESIGN names the grace, not its length): the same 0.5 s after any server PivotTo (pad,
		-- out-of-bounds return, pivot back), so the teleport itself never counts as speed.
		teleportGraceSeconds = 0.5,
		-- Reading: "inside a Geometry volume" is GetPartBoundsInBox on this small box at the HRP (smaller than the
		-- 2 × 2 × 1 HRP, so standing flush against cover never counts).
		geometryProbeSize = Vector3.new(1, 1, 1),
		-- Reading (§5.4 Countdown "frozen", §5.9 "Caster is rooted"; DESIGN gives no number): a fighter who must stand
		-- still and drifts further than this from its spot (horizontally) is pivoted back. A Dragon Rush root also
		-- allows the stopping distance WalkSpeed × min(ping, Throw.originPingCapSeconds).
		holdToleranceStuds = 1.5,
	},

	-- Client-side aim assist, applied once at throw time (§5.10). Keyed by Enum.PreferredInput item names.
	AimAssist = {
		Gamepad = { enabled = true, coneDeg = 4, strength = 0.5 },
		Touch = { enabled = true, coneDeg = 5, strength = 0.5 },
		KeyboardAndMouse = { enabled = false, coneDeg = 0, strength = 0 },
	} :: { [string]: AimAssist },

	-- Aiming and throw input (§5.10).
	Aim = {
		maxRayStuds = 200, -- mouse ray without a hit aims this far along the ray
		-- A ray hit farther than the miss distance (the opponent's / farthest practice target's) + this many
		-- studs counts as a miss: the throw leaves along the crosshair (user bug 2026-10-15: a crosshair just past
		-- the opponent hit the NEXT arena slot 160-200 studs away; the arc went "to the sky"). Covers the backstop.
		farHitMarginStuds = 10,
		touchShoulderOffsetStuds = 1.75, -- Humanoid.CameraOffset = HRP:VectorToObjectSpace(camRight * 1.75)
		triggerThreshold = 0.5, -- ButtonR2 / ButtonL2 count as pressed above this
	},

	-- Allowed catalog throw stats (§5.8). Arc (gravity) costs 0 points: solveLaunchDir lands on the reticle.
	Bands = {
		speed = { min = 85, max = 115 }, -- studs/s
		radius = { min = 0.8, max = 1.4 }, -- studs
		cooldown = { min = 0.9, max = 1.2 }, -- s
		windup = { min = 0.15, max = 0.22 }, -- s
		gravity = { min = 20, max = 50 }, -- studs/s²
	} :: { [string]: Band },

	-- Per-squishy power budget (Logic/PowerBudget, §5.8).
	-- dodge slack(D) = (windup + D/speed - reaction) * dodgeSpeed - (radius + Hitbox.radius)
	-- Ps = dodgeSpeed*D*(1/base.speed - 1/speed)/studsPerPoint; Pr = (radius - base.radius)/studsPerPoint;
	-- Pw = dodgeSpeed*(base.windup - windup)/studsPerPoint; Pc = (base.cooldown/cooldown - 1)/ratePerPoint.
	-- |Σ + ultimate budgetCost| <= tolerance.
	PowerBudget = {
		referenceDistance = 40, -- D, studs
		dodgeSpeed = 16, -- V, studs/s (= Duel.Rules.Movement.WalkSpeed)
		reactionSeconds = 0.25,
		baseline = { speed = 95, radius = 1.0, cooldown = 1.0, windup = 0.18 }, -- Kitty Bread
		studsPerPoint = 0.4, -- 1 point = 0.4 studs of dodge slack at 40 studs ...
		ratePerPoint = 0.05, -- ... = 5% throw rate
		tolerance = 0.5,
	},

	-- Practice range (§5.11). Practice never pays Coins, never gives ult charge. Target positions and the moving
	-- target's path: Shared/Practice/PracticeTargets (from World/WorldLayout.PracticeRange).
	Practice = {
		targetDownSeconds = 1.0, -- a hit target stays "down" this long
	},

	-- Feature 1 (2026-10-11, the user-approved plan; design: the combat-effects page "Squishy Combat FP v2.html",
	-- "html:<line>" below): the charge throw. Hold Throw to charge c 0 -> 1, release to throw (Duel.Rules.HoldToCharge).
	-- Server-authoritative (Shared/ThrowCharge, Logic/ThrowRules): the client sends ChargeStart(clientTime) when its
	-- charge starts; at the ThrowRequest the server measures c from its own record (each press time lag-compensated as
	-- §5.6 #7, the charge counted only from the moment the throw was ready, clamped 0..1, no record = 0) and throws at
	-- the toy's own speed × (1 + speedGain·c). ThrowStarted carries c as `power`. Looks: Config.FirstPerson.charge,
	-- Config.Vfx.Charge, Config.UI.Reticle; the tone: Config.Audio.charge.
	Charge = {
		seconds = 1.0, -- c rises 0 -> 1 over this long (design: html:323, 499 "charge + dt / 1.0")
		speedGain = 17 / 20, -- design: html:330 (speed 20 + 17c over the uncharged 20)
		walkFactor = 5.2 / 7, -- walk speed × this while charging (design: html:437: 5.2 against 7)
		fovNarrowDeg = 4, -- the world FOV narrows by this × c while charging (design: html:463)
		hitStopSeconds = 0.045, -- the thrower's hit-stop when a full charge is released (design: html:339)
	},

	-- Feature 1 (2026-10-11): the catch (design: html:342-354, 528-570, 614). Server-authoritative (CombatService,
	-- Logic/CatchRules): CatchRequest(clientTime) opens a window at the validated press time; an OPPONENT's normal throw
	-- (never an ultimate) that comes within radiusStuds of the catcher while moving toward them during the window is
	-- caught: it ends without a hit, the catcher crushes it for crushSeconds, then it bursts and the thrower loses 1 life
	-- (user decision 2026-10-11).
	Catch = {
		windowSeconds = 0.42, -- the hands stay open this long after the press (design: html:532)
		-- From the press; a press also cancels a charge (design: html:344). Review quick win 2026-10-14 (NOT IN DESIGN:
		-- html:344 has 0.75): after a missed catch the hands wait 1.3 s, so mashing Catch keeps them open about 32% of
		-- the time (windowSeconds / cooldownSeconds = 0.42 / 1.3), not 56%. A real catch keeps its own wait: the hands
		-- are back handsBackSeconds (1.5) after it, and the first press then always passes this cooldown, even
		-- lag-compensated (Config.validate and CatchRules_Test: cooldownSeconds - cooldownToleranceSeconds <=
		-- handsBackSeconds - Lag.maxCompensationSeconds).
		cooldownSeconds = 1.3,
		radiusStuds = 2.7 / 0.28, -- design: html:614 (d < 2.7 m; 1 stud = 0.28 m, so about 9.64 studs)
		-- build choice 2026-10-11 (NOT IN DESIGN: the design measures from its camera, html:613): the catch is measured
		-- from the catcher's HumanoidRootPart + this (about the eyes of a default avatar, where first person looks from).
		centreAboveRootStuds = 1.5,
		crushSeconds = 1.02, -- the caught toy bursts this long after the catch (design: html:554)
		-- The hands are free again this long after the catch (design: html:567, "t > 1.5"): no throw, catch, dash or
		-- ultimate before (user decision 2026-10-11: none while crushing; build choice: until the hands are back).
		handsBackSeconds = 1.5,
		burstHitStopSeconds = 0.12, -- the catcher's hit-stop at the burst (design: html:560)
		-- user decision 2026-10-11: the thrower loses 1 life at the burst, so it costs the life even inside the thrower's
		-- invulnerability (build choice: it then gives HitInvulnSeconds like any lost life); false = a normal hit.
		burstIgnoresInvuln = true,
		-- build choice 2026-10-11 (NOT IN DESIGN): the server's cooldown check allows this much jitter, as
		-- Duel.Rules.CooldownToleranceSeconds does for throws.
		cooldownToleranceSeconds = 0.05,
	},
}

return Combat
