--!strict
-- Config.MoveFx (2026-10-28, the physics upgrade's part 1: movement; owner: "Yes, build it"). Shared, data only. A 1:1
-- port of the co-owner's Claude Design page docs/squishy-fx-spec/move.html (CONFIG.feel, CONFIG.fx, CONFIG.moments,
-- CONFIG.stage; the readable copy is notes.md "Part 1 · Move"), plus the owner's 8 extras (`extras`, NOT IN DESIGN).
-- Units: studs, seconds, degrees, studs/s. Easing names are "<EasingStyle> <EasingDirection>" ("Linear" alone).
-- Particles and trails are VFX Studio templates (ReplicatedStorage.SD_MoveVfx.Feel, made by
-- ServerStorage.SDTools.Builders.FeelVfxBuilder: VFX Studio is their editor); `burst`, `emit` and `trail` events name
-- them. Everything else (poses, rings, camera, text, screen lines, afterimages, sounds) lives here and is played by
-- Client/Anim/FeelFx; Client/Controllers/MoveFxController runs the own character's run, jump, fall and landing.
--
-- Poses: keys { t, easing?, joints, rootPos? }; a key's easing is the curve to the NEXT key (the design's rule; FeelFx
-- turns it around for Anim/Timeline-style evaluation). Joints are R15 joint-space degrees, applied as
-- CFrame.Angles(X, Y, Z) (the design's XYZ order); a joint the track keys somewhere and a key leaves out is 0, 0, 0.
-- `hold` = the last key stays until another pose replaces it; else the pose fades out over fadeOut after its last key.
-- Timelines: events { t, on?, <kind> = name, at?, aim?, face?, ["for"]?, views? } as the design's moments; `on` = a
-- signal the gameplay code sends (FeelFx Run:signal), `t` then counts from it. views "1P" / "3P": only the own camera
-- in that view sees it (other players are always 3P).

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local MoveFx = {
	-- The switch (the design's handoff: "Existing effects that the spec replaces. Don't delete them; disable them
	-- behind a flag"): false = the old dash, double jump, slide and landing effects and poses, and none of the new run,
	-- jump and fall feel (the faster fall, the short hop). The dash's speed curve (Shared/DashMath) is the design's
	-- either way.
	enabled = true,
	-- CONFIG.feel (move.html:46-62). KEEP values are the game's own (Config.Duel.Rules, Config.LobbyMove).
	feel = {
		fallGravityMultiplier = 1.6, -- x gravity only while falling (vy < 0): the rise is untouched, the jump stays 7.2
		maxFallSpeed = 130,
		fastFallFrom = 75, -- falling this fast starts the wind streaks
		jumpCutMinHold = 0.06, -- an early release never cuts before this
		jumpCutKeep = 0.45, -- x upward speed kept on an early release (a ~3.7-stud hop)
		landSoftBelow = 55, -- landing speed below this = the soft tier
		landHardFrom = 90, -- from this = the hard tier (between = normal)
	},
	-- CONFIG.stage's anchor numbers (move.html stage; the preview's own layout is not ported).
	stage = { feetLift = 0.06, groundLift = 0.04, chestHeight = 3.6, backUpAngle = 35 },
	-- The pose layer's priority (JointLayer): over the hold (1) and the old dash / slide layers, under the throw (2).
	posePriority = 1.7,
	-- While a squishy is held these joints keep the hold pose (the held arm, as the dash and flips always did).
	heldArmJoints = { "RightShoulder", "RightElbow", "RightWrist" },

	-- CONFIG.fx: poses (notes.md "Part 1 · Move — R15 pose keys").
	poses = {
		runLean = {
			fadeIn = 0.04,
			hold = true,
			keys = {
				{ t = 0, easing = "Cubic Out", joints = { Waist = v(-12, 0, 0) } },
				{ t = 0.25, joints = { Waist = v(-6, 0, 0) } },
			},
		},
		runSettle = {
			fadeIn = 0.02,
			fadeOut = 0.1,
			keys = {
				{ t = 0, easing = "Cubic Out", joints = { Waist = v(-6, 0, 0) } },
				{ t = 0.12, easing = "Cubic InOut", joints = { Waist = v(4, 0, 0) } },
				{ t = 0.24, joints = {} },
			},
		},
		jumpRise = {
			fadeIn = 0.05,
			hold = true,
			keys = {
				{
					t = 0,
					easing = "Cubic Out",
					joints = {
						Neck = v(8, 0, 0),
						Waist = v(-4, 0, 0),
						LeftShoulder = v(150, 0, -18),
						RightShoulder = v(150, 0, 18),
						LeftElbow = v(15, 0, 0),
						RightElbow = v(15, 0, 0),
						LeftHip = v(60, 0, 0),
						LeftKnee = v(-85, 0, 0),
						RightHip = v(-12, 0, 0),
						RightKnee = v(-25, 0, 0),
						RightAnkle = v(-20, 0, 0),
					},
				},
				{
					t = 0.14,
					joints = {
						LeftShoulder = v(120, 0, -35),
						RightShoulder = v(120, 0, 35),
						LeftElbow = v(25, 0, 0),
						RightElbow = v(25, 0, 0),
						LeftHip = v(50, 0, 0),
						LeftKnee = v(-75, 0, 0),
						RightHip = v(25, 0, 0),
						RightKnee = v(-55, 0, 0),
					},
				},
			},
		},
		jumpFall = {
			fadeIn = 0.12,
			hold = true,
			keys = {
				{
					t = 0,
					joints = {
						LeftShoulder = v(160, 0, -45),
						RightShoulder = v(160, 0, 45),
						LeftElbow = v(20, 0, 0),
						RightElbow = v(20, 0, 0),
						LeftHip = v(15, 0, 0),
						RightHip = v(-5, 0, 0),
						LeftKnee = v(-25, 0, 0),
						RightKnee = v(-15, 0, 0),
						Neck = v(-8, 0, 0),
					},
				},
			},
		},
		landSoft = {
			fadeIn = 0.02,
			fadeOut = 0.1,
			keys = {
				{
					t = 0,
					easing = "Cubic Out",
					rootPos = v(0, -0.16, 0.12),
					joints = {
						Waist = v(-6, 0, 0),
						LeftHip = v(25, 0, 0),
						RightHip = v(25, 0, 0),
						LeftKnee = v(-45, 0, 0),
						RightKnee = v(-45, 0, 0),
						LeftAnkle = v(20, 0, 0),
						RightAnkle = v(20, 0, 0),
					},
				},
				{ t = 0.1, joints = {} },
			},
		},
		landNormal = {
			fadeIn = 0.02,
			fadeOut = 0.12,
			keys = {
				{
					t = 0,
					rootPos = v(0, -0.5, 0.2),
					joints = {
						Waist = v(-14, 0, 0),
						Neck = v(8, 0, 0),
						LeftShoulder = v(25, 0, -20),
						RightShoulder = v(25, 0, 20),
						LeftHip = v(45, 0, 0),
						RightHip = v(45, 0, 0),
						LeftKnee = v(-80, 0, 0),
						RightKnee = v(-80, 0, 0),
						LeftAnkle = v(35, 0, 0),
						RightAnkle = v(35, 0, 0),
					},
				},
				{
					t = 0.06,
					rootPos = v(0, -0.5, 0.2),
					joints = {
						Waist = v(-14, 0, 0),
						Neck = v(8, 0, 0),
						LeftShoulder = v(25, 0, -20),
						RightShoulder = v(25, 0, 20),
						LeftHip = v(45, 0, 0),
						RightHip = v(45, 0, 0),
						LeftKnee = v(-80, 0, 0),
						RightKnee = v(-80, 0, 0),
						LeftAnkle = v(35, 0, 0),
						RightAnkle = v(35, 0, 0),
					},
				},
				-- Eclipse pass (2026-10-28): the design's Cubic InOut rise baked at 30 fps with the Root raised so a
				-- standard R15's feet never dip into the floor (it sank 0.13 studs); the joints are the design's.
				{ t = 0.0933, rootPos = v(0, -0.42, 0.19), joints = { LeftAnkle = v(33.73, 0, 0), LeftHip = v(43.37, 0, 0), LeftKnee = v(-77.11, 0, 0), LeftShoulder = v(24.1, 0, -19.28), Neck = v(7.71, 0, 0), RightAnkle = v(33.73, 0, 0), RightHip = v(43.37, 0, 0), RightKnee = v(-77.11, 0, 0), RightShoulder = v(24.1, 0, 19.28), Waist = v(-13.49, 0, 0) } },
				{ t = 0.1267, rootPos = v(0, -0.23, 0.14), joints = { LeftAnkle = v(24.87, 0, 0), LeftHip = v(31.98, 0, 0), LeftKnee = v(-56.85, 0, 0), LeftShoulder = v(17.77, 0, -14.21), Neck = v(5.69, 0, 0), RightAnkle = v(24.87, 0, 0), RightHip = v(31.98, 0, 0), RightKnee = v(-56.85, 0, 0), RightShoulder = v(17.77, 0, 14.21), Waist = v(-9.95, 0, 0) } },
				{ t = 0.16, rootPos = v(0, -0.02, 0.04), joints = { LeftAnkle = v(7.38, 0, 0), LeftHip = v(9.49, 0, 0), LeftKnee = v(-16.88, 0, 0), LeftShoulder = v(5.27, 0, -4.22), Neck = v(1.69, 0, 0), RightAnkle = v(7.38, 0, 0), RightHip = v(9.49, 0, 0), RightKnee = v(-16.88, 0, 0), RightShoulder = v(5.27, 0, 4.22), Waist = v(-2.95, 0, 0) } },
				{ t = 0.1933, rootPos = v(0, 0, 0), joints = { LeftAnkle = v(0.65, 0, 0), LeftHip = v(0.83, 0, 0), LeftKnee = v(-1.48, 0, 0), LeftShoulder = v(0.46, 0, -0.37), Neck = v(0.15, 0, 0), RightAnkle = v(0.65, 0, 0), RightHip = v(0.83, 0, 0), RightKnee = v(-1.48, 0, 0), RightShoulder = v(0.46, 0, 0.37), Waist = v(-0.26, 0, 0) } },
				{ t = 0.22, joints = {} },
			},
		},
		landHard = {
			fadeIn = 0.02,
			fadeOut = 0.14,
			keys = {
				{
					t = 0,
					rootPos = v(0, -1, 0.33),
					joints = {
						Waist = v(-24, 0, 0),
						Neck = v(14, 0, 0),
						LeftShoulder = v(-20, 0, -65),
						RightShoulder = v(-20, 0, 65),
						LeftElbow = v(20, 0, 0),
						RightElbow = v(20, 0, 0),
						LeftHip = v(70, 0, 0),
						RightHip = v(70, 0, 0),
						LeftKnee = v(-115, 0, 0),
						RightKnee = v(-115, 0, 0),
						LeftAnkle = v(45, 0, 0),
						RightAnkle = v(45, 0, 0),
					},
				},
				{
					t = 0.1,
					rootPos = v(0, -1, 0.33),
					joints = {
						Waist = v(-24, 0, 0),
						Neck = v(14, 0, 0),
						LeftShoulder = v(-20, 0, -65),
						RightShoulder = v(-20, 0, 65),
						LeftElbow = v(20, 0, 0),
						RightElbow = v(20, 0, 0),
						LeftHip = v(70, 0, 0),
						RightHip = v(70, 0, 0),
						LeftKnee = v(-115, 0, 0),
						RightKnee = v(-115, 0, 0),
						LeftAnkle = v(45, 0, 0),
						RightAnkle = v(45, 0, 0),
					},
				},
				-- Eclipse pass (2026-10-28): the design's Cubic InOut rise baked at 30 fps, Root raised so the feet stay
				-- on the floor (it sank 0.26 studs on a standard R15); the joints are the design's.
				{ t = 0.1333, rootPos = v(0, -0.88, 0.33), joints = { LeftAnkle = v(44.52, 0, 0), LeftElbow = v(19.79, 0, 0), LeftHip = v(69.25, 0, 0), LeftKnee = v(-113.77, 0, 0), LeftShoulder = v(-19.79, 0, -64.3), Neck = v(13.85, 0, 0), RightAnkle = v(44.52, 0, 0), RightElbow = v(19.79, 0, 0), RightHip = v(69.25, 0, 0), RightKnee = v(-113.77, 0, 0), RightShoulder = v(-19.79, 0, 64.3), Waist = v(-23.74, 0, 0) } },
				{ t = 0.1667, rootPos = v(0, -0.77, 0.3), joints = { LeftAnkle = v(41.14, 0, 0), LeftElbow = v(18.29, 0, 0), LeftHip = v(64, 0, 0), LeftKnee = v(-105.14, 0, 0), LeftShoulder = v(-18.29, 0, -59.43), Neck = v(12.8, 0, 0), RightAnkle = v(41.14, 0, 0), RightElbow = v(18.29, 0, 0), RightHip = v(64, 0, 0), RightKnee = v(-105.14, 0, 0), RightShoulder = v(-18.29, 0, 59.43), Waist = v(-21.94, 0, 0) } },
				{ t = 0.2, rootPos = v(0, -0.48, 0.23), joints = { LeftAnkle = v(31.98, 0, 0), LeftElbow = v(14.21, 0, 0), LeftHip = v(49.75, 0, 0), LeftKnee = v(-81.72, 0, 0), LeftShoulder = v(-14.21, 0, -46.19), Neck = v(9.95, 0, 0), RightAnkle = v(31.98, 0, 0), RightElbow = v(14.21, 0, 0), RightHip = v(49.75, 0, 0), RightKnee = v(-81.72, 0, 0), RightShoulder = v(-14.21, 0, 46.19), Waist = v(-17.06, 0, 0) } },
				{ t = 0.2333, rootPos = v(0, -0.12, 0.12), joints = { LeftAnkle = v(15.8, 0, 0), LeftElbow = v(7.02, 0, 0), LeftHip = v(24.58, 0, 0), LeftKnee = v(-40.38, 0, 0), LeftShoulder = v(-7.02, 0, -22.83), Neck = v(4.92, 0, 0), RightAnkle = v(15.8, 0, 0), RightElbow = v(7.02, 0, 0), RightHip = v(24.58, 0, 0), RightKnee = v(-40.38, 0, 0), RightShoulder = v(-7.02, 0, 22.83), Waist = v(-8.43, 0, 0) } },
				{ t = 0.2667, rootPos = v(0, -0.01, 0.04), joints = { LeftAnkle = v(5.14, 0, 0), LeftElbow = v(2.28, 0, 0), LeftHip = v(7.99, 0, 0), LeftKnee = v(-13.12, 0, 0), LeftShoulder = v(-2.28, 0, -7.42), Neck = v(1.6, 0, 0), RightAnkle = v(5.14, 0, 0), RightElbow = v(2.28, 0, 0), RightHip = v(7.99, 0, 0), RightKnee = v(-13.12, 0, 0), RightShoulder = v(-2.28, 0, 7.42), Waist = v(-2.74, 0, 0) } },
				{ t = 0.3, rootPos = v(0, 0, 0.01), joints = { LeftAnkle = v(0.83, 0, 0), LeftElbow = v(0.37, 0, 0), LeftHip = v(1.3, 0, 0), LeftKnee = v(-2.13, 0, 0), LeftShoulder = v(-0.37, 0, -1.2), Neck = v(0.26, 0, 0), RightAnkle = v(0.83, 0, 0), RightElbow = v(0.37, 0, 0), RightHip = v(1.3, 0, 0), RightKnee = v(-2.13, 0, 0), RightShoulder = v(-0.37, 0, 1.2), Waist = v(-0.44, 0, 0) } },
				{ t = 0.34, joints = {} },
			},
		},
		-- The forward flip on the Root joint (keys < 120 deg apart); FeelFx.flipVariant turns it for the extras.
		doubleFlip = {
			fadeIn = 0.03,
			fadeOut = 0.1,
			keys = {
				{
					t = 0,
					joints = {
						Root = v(0, 0, 0),
						Neck = v(-15, 0, 0),
						LeftShoulder = v(55, 0, -15),
						RightShoulder = v(55, 0, 15),
						LeftElbow = v(75, 0, 0),
						RightElbow = v(75, 0, 0),
						LeftHip = v(75, 0, 0),
						RightHip = v(75, 0, 0),
						LeftKnee = v(-105, 0, 0),
						RightKnee = v(-105, 0, 0),
					},
				},
				{
					t = 0.06,
					joints = {
						Root = v(-100, 0, 0),
						Neck = v(-15, 0, 0),
						LeftShoulder = v(55, 0, -15),
						RightShoulder = v(55, 0, 15),
						LeftElbow = v(75, 0, 0),
						RightElbow = v(75, 0, 0),
						LeftHip = v(75, 0, 0),
						RightHip = v(75, 0, 0),
						LeftKnee = v(-105, 0, 0),
						RightKnee = v(-105, 0, 0),
					},
				},
				{
					t = 0.12,
					joints = {
						Root = v(-200, 0, 0),
						Neck = v(-15, 0, 0),
						LeftShoulder = v(55, 0, -15),
						RightShoulder = v(55, 0, 15),
						LeftElbow = v(75, 0, 0),
						RightElbow = v(75, 0, 0),
						LeftHip = v(75, 0, 0),
						RightHip = v(75, 0, 0),
						LeftKnee = v(-105, 0, 0),
						RightKnee = v(-105, 0, 0),
					},
				},
				{
					t = 0.19,
					easing = "Cubic Out",
					joints = {
						Root = v(-295, 0, 0),
						Neck = v(-15, 0, 0),
						LeftShoulder = v(55, 0, -15),
						RightShoulder = v(55, 0, 15),
						LeftElbow = v(75, 0, 0),
						RightElbow = v(75, 0, 0),
						LeftHip = v(75, 0, 0),
						RightHip = v(75, 0, 0),
						LeftKnee = v(-105, 0, 0),
						RightKnee = v(-105, 0, 0),
					},
				},
				{
					t = 0.26,
					joints = {
						Root = v(-360, 0, 0),
						LeftShoulder = v(150, 0, -35),
						RightShoulder = v(150, 0, 35),
						LeftElbow = v(15, 0, 0),
						RightElbow = v(15, 0, 0),
						LeftHip = v(15, 0, 0),
						RightHip = v(-5, 0, 0),
						LeftKnee = v(-25, 0, 0),
						RightKnee = v(-15, 0, 0),
					},
				},
			},
		},
		fallFlail = {
			fadeIn = 0.1,
			hold = true,
			keys = {
				{
					t = 0,
					easing = "Cubic InOut",
					joints = {
						Neck = v(-12, 0, 0),
						LeftShoulder = v(165, 0, -50),
						RightShoulder = v(150, 0, 40),
						LeftElbow = v(25, 0, 0),
						RightElbow = v(10, 0, 0),
						LeftHip = v(25, 0, 0),
						RightHip = v(-10, 0, 0),
						LeftKnee = v(-40, 0, 0),
						RightKnee = v(-10, 0, 0),
					},
				},
				{
					t = 0.15,
					easing = "Cubic InOut",
					joints = {
						Neck = v(-12, 0, 0),
						LeftShoulder = v(150, 0, -40),
						RightShoulder = v(165, 0, 50),
						LeftElbow = v(10, 0, 0),
						RightElbow = v(25, 0, 0),
						LeftHip = v(-10, 0, 0),
						RightHip = v(25, 0, 0),
						LeftKnee = v(-10, 0, 0),
						RightKnee = v(-40, 0, 0),
					},
				},
				{
					t = 0.3,
					joints = {
						Neck = v(-12, 0, 0),
						LeftShoulder = v(165, 0, -50),
						RightShoulder = v(150, 0, 40),
						LeftElbow = v(25, 0, 0),
						RightElbow = v(10, 0, 0),
						LeftHip = v(25, 0, 0),
						RightHip = v(-10, 0, 0),
						LeftKnee = v(-40, 0, 0),
						RightKnee = v(-10, 0, 0),
					},
				},
			},
		},
		dashPose = {
			fadeIn = 0.03,
			fadeOut = 0.14,
			keys = {
				{
					t = 0,
					joints = {
						Root = v(-14, 0, 0),
						Waist = v(-10, 0, 0),
						Neck = v(18, 0, 0),
						LeftShoulder = v(-55, 0, -12),
						RightShoulder = v(-55, 0, 12),
						LeftElbow = v(15, 0, 0),
						RightElbow = v(15, 0, 0),
						LeftHip = v(40, 0, 0),
						LeftKnee = v(-70, 0, 0),
						RightHip = v(-30, 0, 0),
						RightKnee = v(-35, 0, 0),
					},
				},
				{
					t = 0.2,
					joints = {
						Root = v(-14, 0, 0),
						Waist = v(-10, 0, 0),
						Neck = v(18, 0, 0),
						LeftShoulder = v(-55, 0, -12),
						RightShoulder = v(-55, 0, 12),
						LeftElbow = v(15, 0, 0),
						RightElbow = v(15, 0, 0),
						LeftHip = v(40, 0, 0),
						LeftKnee = v(-70, 0, 0),
						RightHip = v(-30, 0, 0),
						RightKnee = v(-35, 0, 0),
					},
				},
			},
		},
		-- Eclipse pass (2026-10-28): the held keys' Root drop is -1.18 (the design's -1.85 put a standard R15's lead
		-- foot 0.67 studs into the floor: the preview rig's legs are shorter); now that foot rests on the floor.
		slidePose = {
			fadeIn = 0.06,
			fadeOut = 0.14,
			keys = {
				{
					t = 0,
					rootPos = v(0, -1.18, 0),
					joints = {
						Root = v(24, 0, 0),
						Waist = v(-14, 0, 0),
						Neck = v(-12, 0, 0),
						LeftHip = v(66, 0, 0),
						LeftKnee = v(-4, 0, 0),
						LeftAnkle = v(-10, 0, 0),
						RightHip = v(36, 0, -12),
						RightKnee = v(-150, 0, 0),
						LeftShoulder = v(-20, 0, -60),
						LeftElbow = v(10, 0, 0),
						RightShoulder = v(75, 0, 30),
						RightElbow = v(30, 0, 0),
					},
				},
				{
					t = 0.56,
					rootPos = v(0, -1.18, 0),
					joints = {
						Root = v(24, 0, 0),
						Waist = v(-14, 0, 0),
						Neck = v(-12, 0, 0),
						LeftHip = v(66, 0, 0),
						LeftKnee = v(-4, 0, 0),
						LeftAnkle = v(-10, 0, 0),
						RightHip = v(36, 0, -12),
						RightKnee = v(-150, 0, 0),
						LeftShoulder = v(-20, 0, -60),
						LeftElbow = v(10, 0, 0),
						RightShoulder = v(75, 0, 30),
						RightElbow = v(30, 0, 0),
					},
				},
				-- Eclipse pass (2026-10-28): the design's Cubic InOut get-up baked at 30 fps, Root raised so the lead foot
				-- never cuts into the floor (it sank 0.85 studs on a standard R15); the joints are the design's.
				{ t = 0.5933, rootPos = v(0, -1.03, 0), joints = { LeftAnkle = v(-9.46, 0, 0), LeftElbow = v(9.46, 0, 0), LeftHip = v(62.44, 0, 0), LeftKnee = v(-3.78, 0, 0), LeftShoulder = v(-18.92, 0, -56.76), Neck = v(-11.35, 0, 0), RightElbow = v(28.38, 0, 0), RightHip = v(34.06, 0, -11.35), RightKnee = v(-141.9, 0, 0), RightShoulder = v(70.95, 0, 28.38), Root = v(22.7, 0, 0), Waist = v(-13.24, 0, 0) } },
				{ t = 0.6267, rootPos = v(0, -0.2, 0), joints = { LeftAnkle = v(-5.68, 0, 0), LeftElbow = v(5.68, 0, 0), LeftHip = v(37.49, 0, 0), LeftKnee = v(-2.27, 0, 0), LeftShoulder = v(-11.36, 0, -34.08), Neck = v(-6.82, 0, 0), RightElbow = v(17.04, 0, 0), RightHip = v(20.45, 0, -6.82), RightKnee = v(-85.21, 0, 0), RightShoulder = v(42.61, 0, 17.04), Root = v(13.63, 0, 0), Waist = v(-7.95, 0, 0) } },
				{ t = 0.66, rootPos = v(0, 0.06, 0), joints = { LeftAnkle = v(-0.93, 0, 0), LeftElbow = v(0.93, 0, 0), LeftHip = v(6.16, 0, 0), LeftKnee = v(-0.37, 0, 0), LeftShoulder = v(-1.87, 0, -5.6), Neck = v(-1.12, 0, 0), RightElbow = v(2.8, 0, 0), RightHip = v(3.36, 0, -1.12), RightKnee = v(-13.99, 0, 0), RightShoulder = v(7, 0, 2.8), Root = v(2.24, 0, 0), Waist = v(-1.31, 0, 0) } },
				{ t = 0.7, joints = {} },
			},
		},
	},

	-- Rings: a flat Part with the kit ring on both faces, Size and Transparency tweened (notes.md "ring"). `tinted` =
	-- takes the held squishy's colour (extra 1).
	rings = {
		landRingNormal = {
			color = Color3.fromHex("#FFFFFF"),
			sizeStart = 1.5,
			sizeEnd = 6,
			time = 0.22,
			easing = "Quad Out",
			transparencyStart = 0.4,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
		},
		landRingHard = {
			color = Color3.fromHex("#FFFFFF"),
			sizeStart = 2,
			sizeEnd = 11,
			time = 0.3,
			easing = "Quad Out",
			transparencyStart = 0.1,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
		},
		doubleRing = {
			color = Color3.fromHex("#8CC8FF"),
			sizeStart = 1.5,
			sizeEnd = 8,
			time = 0.28,
			easing = "Quad Out",
			transparencyStart = 0.05,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
			tinted = true,
		},
		doubleHalo = {
			color = Color3.fromHex("#FFD86B"),
			sizeStart = 1.5,
			sizeEnd = 7,
			time = 0.3,
			easing = "Quad Out",
			transparencyStart = 0,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
			lightEmission = 0.6,
			follow = true,
			tinted = true,
		},
		dashShock = {
			color = Color3.fromHex("#8CC8FF"),
			sizeStart = 2,
			sizeEnd = 9,
			time = 0.25,
			easing = "Quad Out",
			transparencyStart = 0.05,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
			tinted = true,
		},
		-- Extra 4 (NOT IN DESIGN): the mega landing's bigger ring, the hard ring's look.
		megaRing = {
			color = Color3.fromHex("#FFFFFF"),
			sizeStart = 2,
			sizeEnd = 16,
			time = 0.38,
			easing = "Quad Out",
			transparencyStart = 0.05,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
			tinted = true,
		},
	},

	-- Camera dips: the camera drops Depth studs (Down, Hold, Up envelope).
	dips = {
		landDipSoft = { depth = 0.15, down = 0.04, downEasing = "Sine Out", hold = 0, up = 0.12, upEasing = "Quad Out" },
		landDipNormal = { depth = 0.45, down = 0.05, downEasing = "Sine Out", hold = 0, up = 0.2, upEasing = "Quad Out" },
		landDipHard = { depth = 1.1, down = 0.06, downEasing = "Quad Out", hold = 0.02, up = 0.3, upEasing = "Back Out" },
		slideCamDrop = { depth = 1.2, down = 0.12, downEasing = "Quad Out", hold = 0.4, up = 0.3, upEasing = "Quad InOut" },
	},
	-- Camera shakes: amplitude (deg) x (1 - ease(t / time)) x the two-sine noise, per-axis weights pitch / yaw / roll.
	shakes = {
		landShakeHard = { amplitude = 0.8, time = 0.18, frequency = 20, easing = "Quad Out", axes = v(1, 0.4, 0.3) },
		slideRumble = { amplitude = 0.25, time = 0.6, frequency = 26, easing = "Linear", axes = v(1, 0.5, 0.2) },
	},
	-- The two-sine noise (CONFIG.viewer.shakeNoise): weights and the second sine's frequency ratio.
	shakeNoise = { 0.65, 0.35, 1.73 },
	-- FOV kicks: + delta degrees (attack, hold, release envelope).
	fovs = {
		doubleFov = { delta = 3, attack = 0.05, attackEasing = "Quad Out", hold = 0, release = 0.25, releaseEasing = "Sine InOut" },
		dashFov = { delta = 7, attack = 0.06, attackEasing = "Quad Out", hold = 0.08, release = 0.3, releaseEasing = "Sine InOut" },
		slideFov = { delta = 6, attack = 0.08, attackEasing = "Quad Out", hold = 0.25, release = 0.4, releaseEasing = "Sine InOut" },
	},
	-- Text billboards: height in studs over time (s:studs keys), transparency keys; width = height x aspect.
	texts = {
		boingText = {
			text = "BOING!",
			color = Color3.fromHex("#FFD86B"),
			stroke = Color3.fromHex("#3B2A35"),
			offset = v(0, 2.5, 0),
			size = { { 0, 0 }, { 0.08, 2.2 }, { 0.14, 1.8 }, { 0.4, 1.9 }, { 0.55, 0 } },
			transparency = { { 0, 0 }, { 0.4, 0 }, { 0.55, 1 } },
			time = 0.55,
		},
		-- Extra 4 (NOT IN DESIGN): the mega landing's text, the BOING look 1.35 x bigger.
		megaText = {
			text = "SUPER BOING!",
			color = Color3.fromHex("#FFD86B"),
			stroke = Color3.fromHex("#3B2A35"),
			offset = v(0, 3, 0),
			size = { { 0, 0 }, { 0.08, 3 }, { 0.14, 2.45 }, { 0.45, 2.55 }, { 0.62, 0 } },
			transparency = { { 0, 0 }, { 0.45, 0 }, { 0.62, 1 } },
			time = 0.62,
		},
	},
	-- The design's text canvas (CONFIG.viewer.textBillboard): 1024 x 256 with a 150 px font and a 22 px stroke.
	textCanvas = { aspect = 4, fontShare = 150 / 256, strokeShare = 22 / 150 },
	-- Screen speed lines: kit speedline ImageLabels between inner and outer x the half-diagonal (the centre stays
	-- clear), px at a 1080-px-tall screen.
	lines = {
		fallLines = {
			color = Color3.fromHex("#FFFFFF"),
			count = 12,
			inner = 0.62,
			outer = 1,
			lengthPx = { 160, 280 },
			widthPx = { 10, 16 },
			jitter = 10,
			travel = 0.12,
			time = 0.3,
			stagger = 0.1,
			opacity = 0.6,
			easing = "Quad Out",
			fadeEasing = "Quad In",
		},
		dashLines = {
			color = Color3.fromHex("#FFFFFF"),
			count = 14,
			inner = 0.6,
			outer = 1,
			lengthPx = { 150, 260 },
			widthPx = { 10, 18 },
			jitter = 8,
			travel = 0.1,
			time = 0.28,
			stagger = 0.04,
			opacity = 0.7,
			easing = "Quad Out",
			fadeEasing = "Quad In",
		},
	},
	afterimages = {
		dashAfterimage = { count = 3, interval = 0.06, color = Color3.fromHex("#8CC8FF"), transparencyStart = 0.5, time = 0.24 },
	},
	-- The design's sound names -> our sound keys (the design names them only). false = no sound of ours yet (Roblox's
	-- own footstep, jump and land sounds still play). variance = the extra 8 pitch spread.
	sounds = {
		run_start_scuff = false,
		footstep_soft = false,
		jump_hop = false,
		land_soft_tap = false,
		land_squish = { key = "sfx.squish", volume = 0.45 },
		land_heavy_boing = { key = "sfx.impactBoing", volume = 0.8 },
		double_jump_pop = { key = "sfx.doubleJump", volume = 1 },
		fall_whistle = false,
		dash_whoosh = { key = "sfx.dashWhoosh", volume = 1 },
		dash_stop = { key = "sfx.dashPlant", volume = 0.8 },
		slide_start_swish = { key = "sfx.dashWhoosh", volume = 1, pitch = 0.82 },
		slide_scrape_loop = false,
		slide_end_pop = { key = "sfx.pop", volume = 0.4 },
		mega_boing = { key = "sfx.impactBoing", volume = 1, pitch = 0.8 }, -- extra 4
		chain_boing = { key = "sfx.impactBoing", volume = 0.35 }, -- extra 3 (pitched up per hop by MoveFxController)
	} :: { [string]: any },

	-- CONFIG.moments, split where the game sends the signal itself (takeoff / landing are the design's shared blocks).
	moments = {
		run = {
			{ t = 0, pose = "runLean" },
			{ t = 0, burst = "runKickPuff", at = "backFoot", aim = "backUp" },
			{ t = 0, sound = "run_start_scuff" },
			{ on = "step", t = 0, burst = "stepPuff", at = "stepFoot", aim = "up" },
			{ on = "step", t = 0, sound = "footstep_soft" },
			{ on = "stop", t = 0, pose = "runSettle" },
		},
		takeoff = {
			{ t = 0, pose = "jumpRise" },
			{ t = 0, burst = "takeoffPuff", at = "feet", aim = "up" },
			{ t = 0, sound = "jump_hop" },
			{ on = "apex", t = 0, pose = "jumpFall" },
		},
		landing = {
			{ on = "landSoft", t = 0, burst = "landPuffSoft", at = "feet", aim = "up" },
			{ on = "landSoft", t = 0, pose = "landSoft" },
			{ on = "landSoft", t = 0, dip = "landDipSoft" },
			{ on = "landSoft", t = 0, sound = "land_soft_tap" },
			{ on = "landNormal", t = 0, burst = "landPuffNormal", at = "feet", aim = "up" },
			{ on = "landNormal", t = 0, ring = "landRingNormal", at = "feet" },
			{ on = "landNormal", t = 0, pose = "landNormal" },
			{ on = "landNormal", t = 0, dip = "landDipNormal" },
			{ on = "landNormal", t = 0, sound = "land_squish" },
			{ on = "landHard", t = 0, burst = "landPuffHard", at = "feet", aim = "up" },
			{ on = "landHard", t = 0, burst = "landStarsHard", at = "feet", aim = "up" },
			{ on = "landHard", t = 0, ring = "landRingHard", at = "feet" },
			{ on = "landHard", t = 0, pose = "landHard" },
			{ on = "landHard", t = 0, dip = "landDipHard" },
			{ on = "landHard", t = 0, shake = "landShakeHard" },
			{ on = "landHard", t = 0, sound = "land_heavy_boing" },
			{ on = "landHard", t = 0, pop = "boingText", at = "feet", views = { "3P" } },
		},
		doubleJump = {
			{ t = 0, pose = "doubleFlip" },
			{ t = 0, burst = "doubleStars", at = "feet", aim = "down" },
			{ t = 0, burst = "doublePuff", at = "feet", aim = "down" },
			{ t = 0, burst = "doubleSparkles", at = "chest" },
			{ t = 0, ring = "doubleRing", at = "feet" },
			{ t = 0, fov = "doubleFov", views = { "1P" } },
			{ t = 0, sound = "double_jump_pop" },
			{ t = 0, ring = "doubleHalo", at = "chest", face = "up" },
			{ t = 0, emit = "flipStreak", at = "chest", ["for"] = 0.26 },
		},
		fall = {
			{ t = 0, pose = "fallFlail" },
			{ t = 0, sound = "fall_whistle" },
			{ on = "fastFall", t = 0, emit = "fallWind", at = "chest", aim = "up", ["for"] = 0.6 },
			{ on = "fastFall", t = 0, lines = "fallLines", views = { "1P" } },
			{ on = "land", t = 0, stop = "fallWind" },
		},
		dash = {
			{ t = 0, pose = "dashPose" },
			{ t = 0, afterimage = "dashAfterimage" },
			{ t = 0, trail = "dashRibbon", at = "leftShoulder", ["for"] = 0.22 },
			{ t = 0, trail = "dashRibbon", at = "rightShoulder", ["for"] = 0.22 },
			{ t = 0, burst = "dashPuffStart", at = "feet", aim = "back" },
			{ t = 0, fov = "dashFov", views = { "1P" } },
			{ t = 0, lines = "dashLines", views = { "1P" } },
			{ t = 0, sound = "dash_whoosh" },
			{ t = 0, ring = "dashShock", at = "chest", face = "back" },
			{ t = 0, emit = "dashSparks", at = "chest", aim = "back", ["for"] = 0.22 },
			{ on = "dashEnd", t = 0, burst = "dashPuffEnd", at = "feet", aim = "up" },
			{ on = "dashEnd", t = 0, sound = "dash_stop" },
		},
		slide = {
			{ t = 0, pose = "slidePose" },
			{ t = 0, burst = "slideStartPuff", at = "feet", aim = "up" },
			{ t = 0, emit = "slideDust", at = "leadFoot", aim = "backUp", ["for"] = 0.6 },
			{ t = 0, emit = "slideSprinkles", at = "leadFoot", aim = "backUp", ["for"] = 0.45 },
			{ t = 0, trail = "slideStreak", at = "slideGround", ["for"] = 0.7 },
			{ t = 0, fov = "slideFov" },
			{ t = 0, dip = "slideCamDrop" },
			{ t = 0, shake = "slideRumble" },
			{ t = 0, sound = "slide_start_swish" },
			{ t = 0, sound = "slide_scrape_loop" },
			{ on = "slideEnd", t = 0, burst = "dashPuffEnd", at = "feet", aim = "up" },
			{ on = "slideEnd", t = 0, sound = "slide_end_pop" },
		},
		-- Extra 4 (NOT IN DESIGN): played with the hard landing after a big drop.
		mega = {
			{ t = 0, burst = "megaConfetti", at = "feet", aim = "up" },
			{ t = 0, ring = "megaRing", at = "feet" },
			{ t = 0, pop = "megaText", at = "feet", views = { "3P" } },
			{ t = 0, sound = "mega_boing" },
		},
	} :: { [string]: { any } },

	-- CONFIG.phone: the particle counts are the [PC, phone] pairs (every phone count is the PC count halved, rounded
	-- up, which MoveVfx's x0.5 gives); trails last x0.7.
	phone = { countShare = 0.5, trailLifetimeScale = 0.7 },
	-- The own run's step puffs (the design's "Footstep" marker; the preview steps every 0.31 s at the lobby's 20 studs/s):
	-- one step every strideStuds on the ground, alternating feet. A run starts at runFromShare x the walk speed after
	-- standing, and stops below stopBelowShare.
	run = { strideStuds = 6.2, runFromShare = 0.6, stopBelowShare = 0.25, standSeconds = 0.25 },
	-- Air: a fall without a jump counts after fallAfterSeconds in the air going down (steps and slopes are not falls).
	air = { fallAfterSeconds = 0.12, minLandSpeed = 4 },

	-- The owner's 8 extras (2026-10-28, NOT IN DESIGN; the design's own rules still hold: at most 60 particles an effect).
	extras = {
		-- 1: stars, rings and sparkles take the held squishy's colour (Catalog visuals.accent).
		squishyColour = true,
		-- 2: dust puffs take a light tint of the floor (floorShare of the floor colour over the design's cream).
		floorShare = 0.35,
		-- 3: a hop chain: a jump within chainSeconds of a landing adds one (up to chainMax); its landing puffs x
		-- (1 + chainCount x n) and a chain_boing pitched chainPitch x n higher.
		chainSeconds = 0.35,
		chainMax = 5,
		chainCount = 0.15,
		chainPitch = 0.08,
		-- 4: a mega landing: a hard landing after a drop of at least megaDrop studs adds Moments.mega.
		megaDrop = 24,
		-- 6: lobby footprints: a flat print per step, fading over footprintSeconds; at most footprintMax at once.
		footprintSeconds = 2.5,
		footprintMax = 16,
		footprintSize = v(0.9, 0.05, 1.35),
		footprintColor = Color3.fromHex("#3B2A35"),
		footprintTransparency = 0.72,
		-- 7: phone buzz (HapticEffect): which landing / move buzzes and how.
		haptics = {
			landHard = "GameplayCollision",
			mega = "GameplayExplosion",
			doubleJump = "UIClick",
			dash = "UIClick",
		},
		-- 8: every movement sound plays a little higher or lower (± this share).
		soundVariance = 0.05,
	},
}

return MoveFx
