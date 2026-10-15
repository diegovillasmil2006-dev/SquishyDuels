--!strict
-- Config.Anim: procedural animation timings, poses and limits (DESIGN §9.1-§9.7, §9.9, §9.11, §9.14), plus
-- the feel pass (§18.3, §18.5, §18.8): jellyRipple, squeeze.rhythm, held.lobbyIdle / motionJiggle / equipPopPuffs
-- and the duel countdown bubble, "Throw!", result and 2D confetti values.
-- Shared (read by client Anim code and the Inspect/box-reveal presentation), data only. All [P].
-- No AnimationIds: v1 is procedural only. VFX budgets and hit feedback are in Config.Vfx.

export type Phase = {
	name: string,
	startMs: number,
	endMs: number,
	c: number, -- scale target on the squeeze axis
	w: number, -- scale target on the other two axes
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type Flourish = {
	particles: number,
	twistDeg: number?, -- whole-model twist about the squeeze axis during compression
	wideningExtraMs: number?,
	useSqueezeFx: boolean?, -- run the Catalog `anim.squeezeFx` hook
	releaseKick: number?, -- SquishRig: the release kick's rarity factor (default 1)
	sectionFlareDeg: number?, -- SquishRig: a kick on the bouncing sections at the release start (Exclusive)
}

-- SquishRig (squishy overhaul spec 2026-10-09 §3.2): one material feel (the jiggle spring k, c and its gain) and one
-- flight style (all optional: a roll spin, a roll wobble, a nod, a stretch pulse along travel, section flaps).
export type RigFeel = { k: number, c: number, gain: number }
export type FlightStyle = {
	rollDegPerSecond: number?,
	wobbleDeg: number?,
	wobbleHz: number?,
	nodDeg: number?,
	nodHz: number?,
	pulseAmp: number?, -- a symmetric pulse 1 ± pulseAmp (hop); a toy's motion.flight.pulse peak uses pulseHz too
	pulseHz: number?,
	flapDeg: number?, -- default flap size of a section without its own flap.deg
	flapHz: number?,
}

-- A Catalog `anim.squeezeFx` hook (Exclusive flourish): steam puffs (the horns stay rigid).
export type SqueezeFx = {
	rigidity: number, -- the horns' rigidity (0-1)
	steamPuffs: number,
	steamSpeedMin: number,
	steamSpeedMax: number,
}

-- Joint rotation in degrees (x, y, z) in joint space, per logical joint name (see `joints`).
export type PoseAngles = { [string]: Vector3 }
export type Pose = {
	mode: "override" | "additive",
	priority: number?, -- override layers: higher wins
	R15: PoseAngles,
	R6: PoseAngles,
	sway: { joint: string, axis: "X" | "Y" | "Z", amplitudeDeg: number, hz: number }?,
	spring: { omega: number, zeta: number }?, -- spring-impulse poses (flinch)
}

local Anim = {
	-- Runtime core (§9.1, §9.2).
	Scheduler = {
		maxDt = 1 / 20, -- dt clamped to this
		springSubstep = 1 / 120, -- springs substep when dt > springSubstepAbove
		springSubstepAbove = 1 / 60,
	},

	-- Mesh deformer (§9.3). Volume-preserving squash: c = 1 - a, w = 1/sqrt(c).
	deform = {
		maxSquash = 0.35, -- a <= maxSquash
		scaleMin = 0.5, -- S clamped per axis
		scaleMax = 1.6,
		restEpsilon = 0.002, -- |S - 1| below this on every axis = rest (write base values once, then sleep)
		twistEpsilon = 0.001,
		-- Rig speed-up pass: a deformed value (mesh Scale as rendered size, mesh Offset, Size) is rewritten only once it
		-- moved this many studs on some axis from the value last written (under 0.2 px even 1.5 studs from the camera on
		-- a 1440p screen); rest values are always written exactly.
		writeEpsilon = 2.5e-4,
		maxOverlapTiltDeg = 50, -- authoring guide for tilted overlapping parts
	},

	-- Character joint layer (§9.4). Joints found by name: { parent part, joint name } per logical name.
	joints = {
		waitSeconds = 10, -- wait for Humanoid and joints, else one warning and the layer is disabled
		duelEndBlendMs = 150, -- every layer weight blends to 0 at duel end
		cullStuds = 150, -- layers run only within this distance of the camera
		-- reading (not in DESIGN, provisional): a spring-kicked layer (flinch) is removed once both its weight and its
		-- speed are below this.
		springSettleEpsilon = 1e-3,
		R15 = {
			RightShoulder = { "RightUpperArm", "RightShoulder" },
			RightElbow = { "RightLowerArm", "RightElbow" },
			RightWrist = { "RightHand", "RightWrist" },
			LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
			LeftElbow = { "LeftLowerArm", "LeftElbow" },
			Waist = { "UpperTorso", "Waist" },
			Neck = { "Head", "Neck" },
			Root = { "LowerTorso", "Root" },
		} :: { [string]: { string } },
		R6 = {
			RightShoulder = { "Torso", "Right Shoulder" },
			LeftShoulder = { "Torso", "Left Shoulder" },
			Neck = { "Torso", "Neck" },
			Root = { "HumanoidRootPart", "RootJoint" },
		} :: { [string]: { string } },
	},

	-- Poses (§9.4), degrees in joint space. Signs are confirmed once in Play via SD_DebugClient.pose(name, weight).
	-- DESIGN writes paired shoulders as "Z±n": the right joint takes +n and the left joint -n here.
	poses = {
		-- Spec 2026-10-11 §4: the design's HOLD (design: avatar.js:111, 185), a full override every frame while
		-- holding, under the throw / ult / cheer poses (priority 2): the holding arm never swings and a squeeze moves
		-- no arm. The design avatar faces +Z with its right arm on -X, ours faces -Z with it on +X: a 180° turn about Y
		-- flips the X and Z angles (Y = 0, so its XYZ order and our YXZ agree; as in the poses below, +X raises an arm
		-- forward and +Z takes the right arm out).
		hold = {
			mode = "override",
			priority = 1,
			R15 = {
				RightShoulder = Vector3.new(30, 0, 6), -- design: avatar.js:111 rShoulder [-30, 0, -6]
				RightElbow = Vector3.new(75, 0, 0), -- design: avatar.js:111 rElbow [-75, 0, 0]
				RightWrist = Vector3.new(0, 0, 0), -- design: avatar.js:111 rWrist [0, 0, 0]
			},
			-- R6 has one arm joint (spec §4: the closest single-joint equivalent): the arm aims at the design's grip
			-- point under HOLD (design: avatar.js:35, 37, 59, 111: 75.4° forward, 4.2° out), as YXZ angles in the R6
			-- Right Shoulder's joint space, to 0.1°.
			R6 = { RightShoulder = Vector3.new(0, -4.4, 75.5) },
		},
		throwWindup = {
			mode = "override",
			priority = 2,
			R15 = {
				RightShoulder = Vector3.new(155, 0, -15),
				RightElbow = Vector3.new(100, 0, 0),
				RightWrist = Vector3.new(20, 0, 0),
				Waist = Vector3.new(0, -18, 0),
			},
			R6 = { RightShoulder = Vector3.new(0, 0, 150) },
		},
		throwRelease = {
			mode = "override",
			priority = 2,
			R15 = {
				RightShoulder = Vector3.new(95, 0, 0),
				RightElbow = Vector3.new(15, 0, 0),
				Waist = Vector3.new(0, 6, 0),
			},
			R6 = { RightShoulder = Vector3.new(0, 0, 95) },
		},
		throwFollow = {
			mode = "override",
			priority = 2,
			R15 = {
				RightShoulder = Vector3.new(35, 25, 0),
				RightElbow = Vector3.new(25, 0, 0),
				Waist = Vector3.new(0, 12, 0),
			},
			R6 = { RightShoulder = Vector3.new(0, 0, 30) },
		},
		ultCharge = {
			mode = "override",
			priority = 2,
			R15 = {
				RightShoulder = Vector3.new(150, 0, 0),
				LeftShoulder = Vector3.new(150, 0, 0),
				RightElbow = Vector3.new(30, 0, 0),
				LeftElbow = Vector3.new(30, 0, 0),
				Waist = Vector3.new(-10, 0, 0),
			},
			R6 = { RightShoulder = Vector3.new(0, 0, 150), LeftShoulder = Vector3.new(0, 0, -150) },
		},
		-- Dragon Rush recovery hunch (§9.10). DESIGN gives no R6 angles.
		rushRecovery = {
			mode = "override",
			priority = 2,
			R15 = { Waist = Vector3.new(8, 0, 0) },
			R6 = {},
		},
		cheer = {
			mode = "override",
			priority = 2,
			R15 = { RightShoulder = Vector3.new(165, 0, 20), LeftShoulder = Vector3.new(165, 0, -20) },
			R6 = { RightShoulder = Vector3.new(0, 0, 165), LeftShoulder = Vector3.new(0, 0, -165) },
		},
		shrug = { -- draw
			mode = "override",
			priority = 2,
			R15 = {
				RightShoulder = Vector3.new(20, 0, 0),
				LeftShoulder = Vector3.new(20, 0, 0),
				RightElbow = Vector3.new(90, 0, 0),
				LeftElbow = Vector3.new(90, 0, 0),
			},
			R6 = { RightShoulder = Vector3.new(0, 0, 20), LeftShoulder = Vector3.new(0, 0, -20) },
		},
		dizzy = {
			mode = "additive",
			R15 = {
				RightShoulder = Vector3.new(0, 0, 70),
				LeftShoulder = Vector3.new(0, 0, -70),
				Neck = Vector3.new(0, 0, 15),
			},
			R6 = { RightShoulder = Vector3.new(0, 0, 70), LeftShoulder = Vector3.new(0, 0, -70) },
			sway = { joint = "Root", axis = "Z", amplitudeDeg = 6, hz = 1.2 },
		},
		flinch = {
			mode = "additive", -- spring impulse, settles in ≈ 350 ms
			R15 = {
				Waist = Vector3.new(-12, 0, 0),
				Neck = Vector3.new(-10, 0, 0),
				RightShoulder = Vector3.new(-15, 0, 0),
				LeftShoulder = Vector3.new(-15, 0, 0),
			},
			R6 = { Neck = Vector3.new(-10, 0, 0) },
			spring = { omega = 20, zeta = 0.45 },
		},
	} :: { [string]: Pose },

	-- Held squishy and idle (§9.5).
	held = {
		buildStuds = 150, -- held models are built for characters this close ...
		destroyStuds = 180, -- ... and destroyed beyond this
		idlePeriodSeconds = 2.4, -- random phase per model
		idleAmpY = 0.025, -- S.Y = 1 + 0.025 sin φ
		idleAmpXZ = 0.0125, -- S.X = S.Z = 1 - 0.0125 sin φ
		bobStuds = 0.03, -- Weld.C1 offset at phase + π/2
		popInFrom = 0.6, -- scale 0.6 -> 1 when the cooldown ends
		popInOmega = 16,
		popInZeta = 0.55,
		-- reading (not in DESIGN, provisional): how often the build/destroy distances and the deformation budget
		-- (Config.Vfx.Budgets.deformingRigs) are re-checked; not every frame.
		rangeCheckSeconds = 0.25,
		-- Lobby idle (§18.5.1 A6; the holder's SD_DuelPhase == ""): duels keep the idle values above; a crossfade when
		-- the phase changes.
		lobbyIdle = { periodSeconds = 2.8, ampY = 0.035, ampXZ = 0.0175, bobStuds = 0.05, crossfadeSeconds = 0.5 },
		-- Movement jiggle (§18.5.1 A6): spring on j, S.Y = 1 - j, S.XZ = 1 + j/2, |j| <= maxJ. A horizontal speed change
		-- kicks clamp(|Δv_h| · perSpeed, 0, maxImpulse); a landing (vy from <= landingFromVy to >= landingToVy) kicks
		-- landingImpulse.
		motionJiggle = {
			omega = 14,
			zeta = 0.35,
			perSpeed = 1 / 60,
			maxImpulse = 0.05,
			landingFromVy = -15,
			landingToVy = -1,
			landingImpulse = 0.06,
			maxJ = 0.08,
		},
		-- Equip pop (§18.5.1 A7): the rebuild after SD_Equipped changes pops on popInFrom / popInOmega / popInZeta, plus
		-- this many puffs.
		equipPopPuffs = 6,
	},

	-- Squeeze (§9.6). Base timeline (Common); foam recovery from the last phase's end: SmoothDamp to (1, 1, 1)
	-- with T = Catalog anim.foamRecoveryT. Every click pays (2026-10-06): an own squeeze restarts this timeline from the
	-- top on every press (from the current scale, SqueezeController); Config.validate(): Grip.Hold.repeatSeconds (the
	-- hold-to-squeeze rhythm) >= the release pop end of every rarity (0.39 s + the largest wideningExtraMs).
	squeeze = {
		phases = {
			{
				name = "anticipation",
				startMs = 0,
				endMs = 70,
				c = 1.06,
				w = 0.96,
				style = Enum.EasingStyle.Sine,
				direction = Enum.EasingDirection.Out,
			},
			{
				name = "compression",
				startMs = 70,
				endMs = 190,
				c = 0.7,
				w = 1.22,
				style = Enum.EasingStyle.Quart,
				direction = Enum.EasingDirection.Out,
			},
			{
				name = "widening", -- controlled widening
				startMs = 190,
				endMs = 330,
				c = 0.66,
				w = 1.28,
				style = Enum.EasingStyle.Sine,
				direction = Enum.EasingDirection.InOut,
			},
			{
				name = "releasePop",
				startMs = 330,
				endMs = 390,
				c = 0.8,
				w = 1.17,
				style = Enum.EasingStyle.Quad,
				direction = Enum.EasingDirection.Out,
			},
		} :: { Phase },
		foamRecoveryMin = 0.26, -- allowed range for Catalog anim.foamRecoveryT (seconds)
		foamRecoveryMax = 0.42,
		squishSoundAtMs = 70, -- sfx.squish at the end of anticipation; sfx.squeezeRelease at recovery start
		-- Squeeze rhythm (§18.5.1 A1-A2; local player only, never affects sending). A streak continues while own
		-- squeezes are <= streakSeconds apart (its own value, the old cycle 1.5 s + 0.6 s gap: it no longer depends on
		-- Squeeze.cycleSeconds, so fast clicking keeps one streak). Sound pitch follows pitchPattern (with the random
		-- variance cut to ±pitchVariance once the streak is >= 2); every popEvery-th squeeze a big pop (bigPopSparkles +
		-- sfx.pop) replaces the release pop (popSparkles).
		rhythm = {
			streakSeconds = 2.1,
			pitchPattern = { 1, 1.03, 1.06, 1.03 },
			pitchVariance = 0.01,
			popEvery = 8,
			popSparkles = 2,
			bigPopSparkles = 4,
		},
		-- One pooled emitter, Emit(n) at peak compression (smoke texture, Config.Vfx.Textures.smoke).
		particles = {
			lifetimeMin = 0.35,
			lifetimeMax = 0.5,
			sizeFrom = 0.15,
			sizeTo = 0,
			speedMin = 3,
			speedMax = 5,
			spreadDeg = 180, -- reading (not in DESIGN, provisional): ParticleEmitter.SpreadAngle on both axes
		},
		-- Inspect preview uses 2D UI dots instead (particles don't render in a ViewportFrame).
		inspectDotsMin = 6,
		inspectDotsMax = 10,
		-- Rarity flourishes, cosmetic only. Squishy overhaul (spec 2026-10-09 §3.2, Q38; every motion <= 3 Hz): the
		-- twist is one half-swing of twistDeg over the press (SquishRig), Epic adds a releaseKick × 1.5 on the feel
		-- jiggle, Exclusive a 1.5 × release kick and a section flare (reading, provisional: a kick on its wings and tail
		-- sized to peak at sectionFlareDeg). The old fast extras (the 8.3 Hz twist, the Epic jiggle and the 14 Hz horn
		-- and wing flutter) are gone.
		flourish = {
			Common = { particles = 6 },
			Uncommon = { particles = 8, twistDeg = 6, wideningExtraMs = 40 },
			Epic = { particles = 10, twistDeg = 6, wideningExtraMs = 40, releaseKick = 1.5 },
			Exclusive = { particles = 12, useSqueezeFx = true, releaseKick = 1.5, sectionFlareDeg = 12 },
		} :: { [string]: Flourish },
		-- Catalog anim.squeezeFx hooks (Config.validate checks that every catalog hook name is listed here).
		squeezeFx = {
			-- 2 nostril steam puffs at the release start (§9.6; the horns stay rigid, the wings and tail flare as
			-- sections, spec §3.2). Only rigidity and steamPuffs are DESIGN numbers; the steam puff speed (studs/s) is a
			-- reading (provisional).
			dragon_steam = {
				rigidity = 0.6,
				steamPuffs = 2,
				steamSpeedMin = 1,
				steamSpeedMax = 2,
			},
		} :: { [string]: SqueezeFx },
	},

	-- SquishRig (squishy overhaul spec 2026-10-09 §3.2; client Anim/SquishRig, written by Anim/SquishDeformer). The
	-- press keeps squeeze.phases (scaled per toy); the recovery spring and flight style come from each blueprint's
	-- `motion`. Every motion here is <= 3 Hz (§9.12; Config.validate checks it).
	rig = {
		-- Feel jiggle after the release and on kicks (the design's squish.js FEELS): x'' = -k x - c x', shown × gain on
		-- the squeeze axis (1 - j) and half of it on the other two (1 + j/2).
		feels = {
			foam = { k = 140, c = 10, gain = 0.55 }, -- 1.71 Hz
			mochi = { k = 110, c = 8, gain = 0.85 }, -- 1.54 Hz
			jelly = { k = 300, c = 4.5, gain = 1.3 }, -- 2.73 Hz
			plush = { k = 170, c = 10, gain = 0.6 }, -- 1.92 Hz
		} :: { [string]: RigFeel },
		-- The release kick: a stretch at the pop end, releaseKick × gain × the flourish's releaseKick, at most
		-- releaseKickMax. Movement and landing kicks are capped at held.motionJiggle.maxJ; the hit boing peaks at
		-- hitKick whatever the gain (cap: Art/SquishyBlueprints/Kit.JIGGLE_CAP).
		releaseKick = 0.06,
		releaseKickMax = 0.08,
		hitKick = 0.15,
		-- Face states: squish below squishBelow, back above squishAbove (y on the squeeze axis), each state held at
		-- least minHoldSeconds (<= 2.5 toggles a second); a hit shows the squish face hitSeconds; wowSeconds is the usual
		-- wow (owners pass their own, e.g. the box reveal's 0.4).
		face = { squishBelow = 0.86, squishAbove = 0.9, minHoldSeconds = 0.2, hitSeconds = 0.3, wowSeconds = 0.3 },
		-- Blink: every minSeconds-maxSeconds (random per model, after the last blink), eye Y = max(closedY,
		-- |1 - b / (seconds / 2)|) for b < seconds; the shine hides while the eye is below shineHideBelow.
		blink = { minSeconds = 2, maxSeconds = 5, seconds = 0.14, closedY = 0.12, shineHideBelow = 0.5 },
		-- Look multipliers on mesh Scale (X, Y in the face plane): cheeks puff 1 + cheekPuff·s in every state (s = the
		-- press amount); wow eyes; the open mouth in the squish and wow faces; the squish mouth's round "o" in wow.
		looks = {
			cheekPuff = 0.45,
			wowEye = 1.3,
			squishMouthOpen = Vector3.new(1.2, 1.5, 1),
			wowMouthOpen = Vector3.new(0.8, 0.8, 1),
			wowSquishMouth = Vector3.new(0.6, 1, 1),
		},
		-- Bouncing sections (ears, wings, tails, gills; the design's sec()): spring k, c (1.77 Hz) toward
		-- maxDeg·tanh(-v·amp·gain / maxDeg), v = d/dt of the shown squeeze-axis scale; maxDeg is a section's default.
		sections = { k = 140, c = 8, gain = 0.12, maxDeg = 30 },
		-- Flight styles (§3.2 table; the face always leads: roll about the travel line, a small nod). wobble and roll
		-- are today's Catalog flightSpin (throw.wobbleRollDeg at 2 Hz, throw.rollDegPerSecond), also the ReducedMotion
		-- fallback. Readings (provisional): tumble flaps 15° at 1.6 Hz, the hop's calyx flap 20° at 2 Hz.
		flight = {
			tumble = {
				wobbleDeg = 14,
				wobbleHz = 1.6,
				nodDeg = 10,
				nodHz = 1.6,
				pulseHz = 1.4,
				flapDeg = 15,
				flapHz = 1.6,
			},
			frisbee = { rollDegPerSecond = 540, flapDeg = 25, flapHz = 2 },
			spiral = { rollDegPerSecond = 720 },
			wheel = { rollDegPerSecond = 540 },
			glide = { wobbleDeg = 9, wobbleHz = 1.5, flapDeg = 25, flapHz = 2.5 },
			face = { wobbleDeg = 6, wobbleHz = 1.5, flapDeg = 20, flapHz = 2 },
			hop = { pulseAmp = 0.1, pulseHz = 2, flapDeg = 20, flapHz = 2 },
			upright = { wobbleDeg = 6, wobbleHz = 1.2 },
			float = { wobbleDeg = 11, wobbleHz = 1, flapDeg = 20, flapHz = 1.2 },
			sway = { wobbleDeg = 16, wobbleHz = 2, flapDeg = 20, flapHz = 2.5 },
			wobble = { wobbleDeg = 8, wobbleHz = 2 },
			roll = { rollDegPerSecond = 360 },
		} :: { [string]: FlightStyle },
	},

	-- Throw (§9.7). W = Catalog throw.windup, the same number the server uses.
	throw = {
		windupReachFraction = 0.6, -- throwWindup weight 0 -> 1 (Quad Out) by 0.6 W, then held "cocked"
		anticipationC = 0.9, -- squishy squash during the windup
		anticipationW = 1.08,
		releaseSnapMs = 70, -- to throwRelease (Quint Out)
		followEndMs = 250, -- W + 70 -> W + 250 ms to throwFollow (Quad Out)
		returnEndMs = 450, -- W + 250 -> W + 450 ms weight 1 -> 0 (Sine InOut)
		timeWarpMin = 0.5, -- remaining windup time-warped onto releaseAt, rate clamped
		timeWarpMax = 3.0,
		cockedHoldMaxMs = 600, -- no ThrowStarted by then = cancel
		cancelBlendMs = 120,
		pathSettleTau = 0.04, -- P(t) = positionAt(...) + offset · e^(-τ/0.04)
		pathSettleMs = 160,
		speedStretch = Vector3.new(0.94, 0.94, 1.12), -- along travel
		wobbleRollDeg = 8, -- flightSpin "wobble": ±8° roll about the travel axis
		rollDegPerSecond = 360, -- flightSpin "roll"
	},

	-- The dash's pose clip (spec phase 5 §1.2; design: avatar.js:77-100), sampled by Shared/DashMath.sampleKeys on the
	-- R15 joints this layer has: Root, Waist, Neck, LeftShoulder and LeftElbow (the design's hips, knees, ankles and its
	-- pelvis offset of up to 0.32 studs have no joint here, spec §0.7, so they are not ported), plus the held arm: `hold`
	-- degrees added to the design's rShoulder X (avatar.js:126, 185), so -hold on our RightShoulder X. Degrees in joint
	-- space: the design's angles with X and Z negated (the 180° turn of the hold pose, poses.hold above; every dash key
	-- has Y = 0). Keys at frames 0, 2, 4, 7, 12 (30 fps, Config.Duel.Rules.Dash); frame 12 is the design's READY
	-- (avatar.js:77). R = the design's mirror(L) (avatar.js:69-76, 100), worked out key by key. No R6 dash pose
	-- (NOT IN DESIGN).
	dash = {
		-- "Locomotion: Movement · Dash/Jump: Action · Throw: Action2 (upper mask)" (design: main.js:313): over the hold
		-- (1), under the throw and ultimate poses (2).
		priority = 1.5,
		-- The held arm's `hold` offset fades in over this many frames and out over the clip's last 3 (design:
		-- avatar.js:160, DashController.holdWeight); the body pose's weight is DashMath.weightAt.
		holdFadeInFrames = 0.9,
		keys = {
			F = { -- design: avatar.js:79-85
				{
					f = 0,
					hold = 0,
					angles = {
						Root = Vector3.new(-10, 0, 0),
						Waist = Vector3.new(-8, 0, 0),
						Neck = Vector3.new(14, 0, 0),
						LeftShoulder = Vector3.new(-20, 0, -12),
						LeftElbow = Vector3.new(35, 0, 0),
					},
				},
				{
					f = 2, -- push-off
					hold = 8,
					angles = {
						Root = Vector3.new(-24, 0, 0),
						Waist = Vector3.new(-10, 0, 0),
						Neck = Vector3.new(28, 0, 0),
						LeftShoulder = Vector3.new(-48, 0, -12),
						LeftElbow = Vector3.new(40, 0, 0),
					},
				},
				{
					f = 4,
					hold = 14,
					angles = {
						Root = Vector3.new(-30, 0, 0),
						Waist = Vector3.new(-8, 0, 0),
						Neck = Vector3.new(34, 0, 0),
						LeftShoulder = Vector3.new(-60, 0, -14),
						LeftElbow = Vector3.new(30, 0, 0),
					},
				},
				{
					f = 7, -- plant
					hold = -10,
					angles = {
						Root = Vector3.new(-4, 0, 0),
						Waist = Vector3.new(10, 0, 0),
						Neck = Vector3.new(-4, 0, 0),
						LeftShoulder = Vector3.new(25, 0, -20),
						LeftElbow = Vector3.new(55, 0, 0),
					},
				},
				{
					f = 12, -- READY (design: avatar.js:77)
					hold = 0,
					angles = {
						Root = Vector3.new(-3, 0, 0),
						Waist = Vector3.new(0, 0, 0),
						Neck = Vector3.new(0, 0, 0),
						LeftShoulder = Vector3.new(-5, 0, -9),
						LeftElbow = Vector3.new(14, 0, 0),
					},
				},
			},
			B = { -- design: avatar.js:86-92
				{
					f = 0,
					hold = 0,
					angles = {
						Root = Vector3.new(6, 0, 0),
						Waist = Vector3.new(4, 0, 0),
						Neck = Vector3.new(-10, 0, 0),
						LeftShoulder = Vector3.new(10, 0, -14),
						LeftElbow = Vector3.new(40, 0, 0),
					},
				},
				{
					f = 2,
					hold = -8,
					angles = {
						Root = Vector3.new(16, 0, 0),
						Waist = Vector3.new(6, 0, 0),
						Neck = Vector3.new(-22, 0, 0),
						LeftShoulder = Vector3.new(30, 0, -18),
						LeftElbow = Vector3.new(45, 0, 0),
					},
				},
				{
					f = 4,
					hold = -12,
					angles = {
						Root = Vector3.new(20, 0, 0),
						Waist = Vector3.new(6, 0, 0),
						Neck = Vector3.new(-26, 0, 0),
						LeftShoulder = Vector3.new(40, 0, -20),
						LeftElbow = Vector3.new(50, 0, 0),
					},
				},
				{
					f = 7,
					hold = 8,
					angles = {
						Root = Vector3.new(-8, 0, 0),
						Waist = Vector3.new(-4, 0, 0),
						Neck = Vector3.new(12, 0, 0),
						LeftShoulder = Vector3.new(-15, 0, -16),
						LeftElbow = Vector3.new(40, 0, 0),
					},
				},
				{
					f = 12,
					hold = 0,
					angles = {
						Root = Vector3.new(-3, 0, 0),
						Waist = Vector3.new(0, 0, 0),
						Neck = Vector3.new(0, 0, 0),
						LeftShoulder = Vector3.new(-5, 0, -9),
						LeftElbow = Vector3.new(14, 0, 0),
					},
				},
			},
			L = { -- design: avatar.js:93-99
				{
					f = 0,
					hold = 0,
					angles = {
						Root = Vector3.new(-4, 0, -8),
						Waist = Vector3.new(-4, 0, -4),
						Neck = Vector3.new(8, 0, 12),
						LeftShoulder = Vector3.new(-10, 0, -20),
						LeftElbow = Vector3.new(30, 0, 0),
					},
				},
				{
					f = 2,
					hold = 4,
					angles = {
						Root = Vector3.new(-6, 0, 20),
						Waist = Vector3.new(-2, 0, 6),
						Neck = Vector3.new(8, 0, -26),
						LeftShoulder = Vector3.new(0, 0, -55),
						LeftElbow = Vector3.new(20, 0, 0),
					},
				},
				{
					f = 4,
					hold = 8,
					angles = {
						Root = Vector3.new(-6, 0, 28),
						Waist = Vector3.new(0, 0, 6),
						Neck = Vector3.new(6, 0, -34),
						LeftShoulder = Vector3.new(0, 0, -70),
						LeftElbow = Vector3.new(15, 0, 0),
					},
				},
				{
					f = 7,
					hold = -6,
					angles = {
						Root = Vector3.new(-4, 0, 6),
						Waist = Vector3.new(0, 0, -4),
						Neck = Vector3.new(4, 0, -2),
						LeftShoulder = Vector3.new(0, 0, -30),
						LeftElbow = Vector3.new(30, 0, 0),
					},
				},
				{
					f = 12,
					hold = 0,
					angles = {
						Root = Vector3.new(-3, 0, 0),
						Waist = Vector3.new(0, 0, 0),
						Neck = Vector3.new(0, 0, 0),
						LeftShoulder = Vector3.new(-5, 0, -9),
						LeftElbow = Vector3.new(14, 0, 0),
					},
				},
			},
			R = { -- design: avatar.js:100, mirror(DASH_L) (rule avatar.js:69-76)
				{
					f = 0,
					hold = 0,
					angles = {
						Root = Vector3.new(-4, 0, 8),
						Waist = Vector3.new(-4, 0, 4),
						Neck = Vector3.new(8, 0, -12),
						LeftShoulder = Vector3.new(-6, 0, -10),
						LeftElbow = Vector3.new(30, 0, 0),
					},
				},
				{
					f = 2,
					hold = 4,
					angles = {
						Root = Vector3.new(-6, 0, -20),
						Waist = Vector3.new(-2, 0, -6),
						Neck = Vector3.new(8, 0, 26),
						LeftShoulder = Vector3.new(0, 0, -10),
						LeftElbow = Vector3.new(20, 0, 0),
					},
				},
				{
					f = 4,
					hold = 8,
					angles = {
						Root = Vector3.new(-6, 0, -28),
						Waist = Vector3.new(0, 0, -6),
						Neck = Vector3.new(6, 0, 34),
						LeftShoulder = Vector3.new(0, 0, -10),
						LeftElbow = Vector3.new(20, 0, 0),
					},
				},
				{
					f = 7,
					hold = -6,
					angles = {
						Root = Vector3.new(-4, 0, -6),
						Waist = Vector3.new(0, 0, 4),
						Neck = Vector3.new(4, 0, 2),
						LeftShoulder = Vector3.new(0, 0, -10),
						LeftElbow = Vector3.new(30, 0, 0),
					},
				},
				{
					f = 12,
					hold = 0,
					angles = {
						Root = Vector3.new(-3, 0, 0),
						Waist = Vector3.new(0, 0, 0),
						Neck = Vector3.new(0, 0, 0),
						LeftShoulder = Vector3.new(-3, 0, -10),
						LeftElbow = Vector3.new(20, 0, 0),
					},
				},
			},
		},
	},

	-- Elimination (§9.9). The body is never faded.
	elimination = {
		epicEnabled = false, -- "epic_pending" plays the standard effect until approved
		flinchEndMs = 150, -- big flinch + "OUT!" billboard
		dizzyEndMs = 700,
		endMs = 1100, -- foam-confetti puff and the held squishy shrinks to 0
		confettiParticles = 18, -- §18.9: 24 -> 18, room for the 10 confetti parts (Config.Vfx.Confetti)
		sparkles = 12,
	},

	-- Box reveal (§9.11), uses the Inspect viewport stage.
	boxReveal = {
		anticipationEndMs = 900, -- 3 accelerating wobbles with small hops, neutral glow
		anticipationWobbles = 3,
		wobbleCMin = 0.92,
		wobbleCMax = 1.06,
		popEndMs = 1150, -- lid pops
		popConfettiDots = 16,
		revealEndMs = 1750, -- squishy rises, scale 0.3 -> 1 on a spring
		revealScaleFrom = 0.3,
		revealOmega = 14,
		revealZeta = 0.5,
		highlightEndMs = 2350, -- rarity colour, label + pips
		glowMaxOpacity = 0.45, -- never a white flash
		lightRayFrames = 8,
		turntableDegPerSecond = 20,
		skipTapAfterMs = 250, -- a tap/click after this jumps to the final state
		-- The result buttons (Equip, Inspect, Open another, Close) ignore presses for this long after they appear: they
		-- take Skip's place, so the click or tap that skipped (or a quick second tap) would otherwise press one of them
		-- (Part 8 acceptance: a real Skip click pressed Open another and the result vanished unseen).
		resultInputGuardMs = 350,
		reducedMotionAnticipationMs = 300, -- no hops; the reveal is a crossfade
	},

	-- Duel start and end presentation (§9.14).
	duel = {
		countdownPopFrom = 1.3, -- "3", "2", "1" pop 1.3 -> 1.0 (Back Out)
		countdownPopMs = 250,
		resultBannerMs = 300, -- Back Out
		cheerBounces = 2,
		rewardLineStaggerMs = 150,
		fadeMs = 250, -- returning: fade to #2B2440, reposition, fade back
		-- Countdown bubbles (§18.5.2 B6): a round px bubble behind each number pops popFrom -> 1 (Back Out,
		-- countdownPopMs); the old one bursts to burstScale and fades in burstMs; tilt ±tiltDeg -> 0 (alternating).
		-- Overlays fix (2026-10-09): transparency 0 (was 0.2): a solid foam disc, the avatar no longer shows through.
		countdownBubble = { px = 150, popFrom = 0.6, transparency = 0, burstScale = 1.25, burstMs = 120, tiltDeg = 6 },
		-- "Throw!" (§18.5.2 B6): pops popFrom -> 1 (Back Out, popMs), holds holdMs, then UIScale 1 -> outScale while
		-- fading over outMs.
		go = { popFrom = 1.6, popMs = 300, holdMs = 500, outMs = 250, outScale = 1.15 },
		-- Result panel (§18.5.2 B7): lines fade in and slide up lineSlidePx over lineMs; the reward counts up over
		-- rewardCountMs, then pulses 1 -> rewardPulseScale -> 1 over rewardPulseMs; the title tilts -titleTiltDeg -> 0;
		-- DEFEAT pops from defeatPopFrom.
		result = {
			lineSlidePx = 10,
			lineMs = 120,
			rewardCountMs = 600,
			rewardPulseScale = 1.12,
			rewardPulseMs = 200,
			titleTiltDeg = 4,
			defeatPopFrom = 1.15,
		},
		-- 2D confetti on the result panel (§18.5.2 B7, UI/Confetti2D): pieces on a win, drawPieces on a draw, none on a
		-- defeat; w × h px; vx ±vxPx, vy -vyMinPx..-vyMaxPx (px/s), gravityPx px/s², spin ±spinDeg °/s; fades over the
		-- last fadeSeconds of lifetime.
		confetti = {
			pieces = 18,
			drawPieces = 6,
			w = 8,
			h = 14,
			vxPx = 220,
			vyMinPx = 380,
			vyMaxPx = 520,
			gravityPx = 900,
			spinDeg = 360,
			lifetime = 1.2,
			fadeSeconds = 0.3,
		},
	},

	-- Jelly ripple on arena cover and the practice backstop (§18.3, §18.8). Path A: an EditableMesh skin swapped in on
	-- a hit ("onHit") or kept up ("always"), with one PadDent per face; path B: a whole-piece SpecialMesh squash wobble
	-- (gumdrops always, the fallback everywhere); rings on the floor, rails, caps and edges. Presentation only.
	jellyRipple = {
		pathA = true,
		vertexColors = true,
		skinMode = "onHit", -- "onHit" | "always" (§18.3.4)
		waveStudsPerSecond = 7, -- PadDent waveSpeed = 2 × this (its coupling is ¼ of the Laplacian)
		springOmega = 11,
		-- Strength (user test 2026-10-07: "you almost can't see it, the game has to be satisfying"): the first values
		-- (zeta 0.22, impulse 5.5, radius 1.8·r in [1.4, 2.5], clamps 0.5 / 0.25, 1.6 s) dented ~0.27 studs, invisible
		-- from the court. Second user test ("too weak, need more animation like 10x"): a ~6x deeper (1.7 studs), wide
		-- (R0 4·r in [3.2, 5]) dent with a ~1 stud jelly rebound, the strongest that keeps every vertex <= 3 Hz (§9.12;
		-- harder pushes saturate the clamps at corner hits and snap back faster) and settles before faceSeconds.
		-- ReducedMotion keeps a gentle 0.3x dent. The rest of the "10x" comes from the whole-piece jiggle (`jiggle`).
		springZeta = 0.17,
		impulseSpeed = 26, -- studs/s inward × clamp(r / 1.0, impulseScaleMin, impulseScaleMax)
		impulseScaleMin = 0.85,
		impulseScaleMax = 1.2,
		impulseRadiusPerStud = 4.0, -- R0 = clamp(impulseRadiusPerStud · r, impulseRadiusMin, impulseRadiusMax)
		impulseRadiusMin = 3.2,
		impulseRadiusMax = 5.0,
		rushImpulseSpeed = 50,
		rushImpulseRadius = 5.5,
		rushProbeMarginStuds = 2, -- probe from E for lane radius + this
		clampIn = 2.4, -- heights along the outward normal clamped to [-clampIn, clampOut]
		clampOut = 1.4,
		substep = 1 / 120,
		sleepEpsilon = 0.004,
		activeMargin = 1.5,
		faceSeconds = 3.2, -- a face snaps to rest this long after its last impulse
		rushFaceSeconds = 3.6,
		reducedImpulseScale = 0.3, -- ReducedMotion: no wave (c = 0), zeta = 1
		edgeNormalMinDot = 0.8,
		floorNormalMinY = 0.8,
		mismatchStuds = 0.02,
		gridHigh = {
			wallCols = 13,
			wallSideCols = 6,
			wallRowStuds = 0.5,
			wallTopCols = 7,
			wallTopRows = 4,
			blockCols = 12,
			blockRows = 13,
		},
		gridLow = {
			wallCols = 7,
			wallSideCols = 3,
			wallRowStuds = 0.5,
			wallTopCols = 0,
			wallTopRows = 0,
			blockCols = 7,
			blockRows = 9,
		},
		maxVerticesHigh = 5600,
		maxTrianglesHigh = 9400,
		maxVerticesLow = 2600,
		maxTrianglesLow = 3800,
		boundsMargin = 0.6,
		writesPerFrame = 400,
		maxActiveFaces = 6,
		buildMsPerFrame = 2,
		presencePollSeconds = 0.25,
		backstop = { colsHigh = 35, rowsHigh = 13, colsLow = 24, rowsLow = 9, createStuds = 90, destroyStuds = 130 },
		-- Whole-piece jiggle on path A (user test 2026-10-07, "too weak, need more animation like 10x"; the dent alone
		-- cannot go deeper): every hit that ripples a cover piece or the backstop also squashes and stretches the whole
		-- piece like a jelly cube about its Body's bottom centre (it never lifts off or sinks), along the hit axis by
		-- c = 1 + x and bulging c^-verticalShare up and c^-(1 - verticalShare) across (a block keeps its height: its
		-- Cap stays a real part). One spring per arena axis: omega 14, zeta 0.14 = 2.2 Hz (<= 2.5), visibly wobbling
		-- about 1.2-1.6 s and at rest by about 2.7 s, inside faceSeconds. The first swing peaks at amount × the throw's
		-- radius scale (impulseScaleMin..Max: 0.15-0.22), rushAmount for a Dragon Rush; hits add, |x| <= maxAmount.
		-- The 34-stud practice backstop uses backstopAmount (0.06: the whole wall breathes about 0.7 studs at its ends
		-- and 0.3 at its top instead of 2 and 1; its dent already gives the local response) and a cap of maxAmount ×
		-- backstopAmount / amount. At most maxPieces jiggle at once (a new one stops the oldest); their whole-piece
		-- vertex writes (SetPosition only), and the one write at rest after a jiggle ends, share writesPerFrame per
		-- frame at High (a wall is 712 vertices, a block 624: two fit) and writesPerFrameLow at Low (phones; a wall is
		-- 364, a block 252: two fit); a piece left out keeps its last shape one more frame. While a piece moves only its
		-- first hit face dents; hits on its other faces kick the jiggle (§9.12: a second dent would beat with it).
		-- ReducedMotion: no jiggle (path B keeps its gentle rise and fall).
		jiggle = {
			amount = 0.18,
			rushAmount = 0.28,
			maxAmount = 0.3,
			backstopAmount = 0.06,
			omega = 14,
			zeta = 0.14,
			verticalShare = 0.4,
			maxPieces = 4,
			writesPerFrame = 1500,
			writesPerFrameLow = 800,
		},
		-- Path B (gumdrops, failures, a refused mesh quota): the same feel as the jiggle since the user test of
		-- 2026-10-07 (was amount 0.06, roundAmount 0.08, rushScale 1.6, zeta 0.3, maxAmount 0.1): the squash's first
		-- swing peaks at amount (or roundAmount) × the throw's radius scale, × rushScale (about 0.28) for a Dragon
		-- Rush, |x| <= maxAmount; the same spring and bulge split as the jiggle. ReducedMotion: × reducedScale
		-- (about the old gentle 0.02 rise and fall) with zeta = 1.
		pathB = {
			amount = 0.18,
			roundAmount = 0.2,
			rushScale = 1.55,
			omega = 14,
			zeta = 0.14,
			maxAmount = 0.3,
			reducedScale = 0.1,
			maxPieces = 6,
		},
		rings = {
			coverDiameter = 2.5,
			coverSeconds = 0.3,
			floorDiameters = { 3.0, 1.8 },
			floorDelay = 0.1,
			floorSeconds = 0.35,
			transparencyFrom = 0.45,
		},
	},
}

return Anim
