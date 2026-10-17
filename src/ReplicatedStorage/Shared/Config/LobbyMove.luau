--!strict
-- Config.LobbyMove (2026-10-17, VillasmilGaming: "change the movement a little bit in the lobby", the lobby reference
-- video: a quicker run and power slides). Shared, data only. Read by Server/Services/LobbyMoveService (the lobby walk
-- speed, the slide's check) and Client/Controllers/LobbyMoveController (the slide: input, move, pose, effects). Checked
-- by UnitTest LobbyMove_Test (not Config/init: that script stays under Roblox's 200,000-character Source limit).
-- Speeds in studs/s, times in seconds, distances in studs, angles in degrees (joint space, as Config.Anim.dash's keys).

local LobbyMove = {
	-- The lobby run: Humanoid.WalkSpeed outside duels and matches (StarterPlayer's 16 before). Duels and matches set
	-- their own (Config.Duel.Rules.Movement) and give the saved one back after.
	walkSpeed = 20,

	-- The power slide (C, Left Ctrl, ButtonB in the Lobby context; never in the practice throw box, a duel or a match).
	Slide = {
		startSpeed = 40, -- the push along the slide at its start ...
		endSpeed = 18, -- ... easing out to this at its end (then the run takes over again)
		seconds = 0.7,
		cooldownSeconds = 0.9, -- the client's gate; the server allows cooldownToleranceSeconds less (jitter)
		cooldownToleranceSeconds = 0.15,
		minSpeedShare = 0.55, -- only while running: horizontal speed >= this x walkSpeed
		steerPerSecond = 2.2, -- radians a second the slide turns toward the move direction (a little steering)
		maxAccel = 2500, -- studs/s^2 the mover pushes with at most (x the assembly mass): above the run, never a shove
		blockedSeconds = 0.12, -- it ends once the body has run under half its slide speed this long (it hit something)
		hipDrop = 1.2, -- the Humanoid's HipHeight drops this much while sliding (the body sits low) ...
		minHipHeight = 0.6, -- ... never below this
		blendInSeconds = 0.07, -- the pose's weight up ...
		blendOutSeconds = 0.18, -- ... and back down at the end
		priority = 1.6, -- the pose layer's priority (over the hold and the dash's 1.5, under the throw's 2)
		pitch = 0.82, -- the slide's whoosh (sfx.dashWhoosh) a little lower than the dash's
		-- The pose (R15; checked on a solved rig 2026-10-17): leaning back, the lead leg out in front, the other tucked
		-- under, the free arm out behind for balance (the held arm keeps the hold pose).
		pose = {
			Root = Vector3.new(30, 0, -8),
			Waist = Vector3.new(-12, 0, 0),
			Neck = Vector3.new(-16, 0, 0),
			RightHip = Vector3.new(50, 0, 0),
			RightKnee = Vector3.new(-6, 0, 0),
			LeftHip = Vector3.new(4, 0, 0),
			LeftKnee = Vector3.new(-100, 0, 0),
			LeftShoulder = Vector3.new(15, 0, -75),
			LeftElbow = Vector3.new(20, 0, 0),
		},
	},
}

return LobbyMove
