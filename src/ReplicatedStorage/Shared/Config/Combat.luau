--!strict
-- Config.Combat: hitbox, throw validation tolerances, lag, aim assist, throw stat bands and the power budget
-- (DESIGN §5.5-§5.10). Shared, data only. All [P]. Duel rules (lives, cooldown clamp, projectile limits, phase
-- timings) are in Config.Duel.Rules; Dragon Rush is in Config.Abilities.

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
}

return Combat
