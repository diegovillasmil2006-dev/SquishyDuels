--!strict
-- Config.UI.Match.topBar: the live top bar (2026-10-26, owner: "Yes, build the live top bar like that (Free for All: the
-- leader vs you)"; `S:n` = Diego's LOADING SCREEN Y MATCH HUD page line n, `T:n` = its uploads/tdm-hud.js): UI/Match/
-- TopBar. Stage px (T:57 desktop 1440 x 900, T:64 phone 750 x 369 in its safe area), the stage scaled to fit like the
-- intro's. T:59 / T:66 LAYOUT, S:490 zz() the per-form sizes, S:140-170 the markup. PR2: the design's 12-14 px text
-- reads 16 (the tags and the goal pill grow to hold it). Free for All [P, owner's pick]: one head a side (the leader, or
-- the runner-up when you lead, vs you), each with a place tag. Shared, data only. A child module of Config/UI (UI.luau
-- is at Roblox's 200,000-character Source limit).

return {
	z = 5, -- under the intro (6) and the end screen
	enter = { ms = 480, curve = "beat", lift = 1.4, settleAt = 0.7, settle = 6 }, -- S:665 -140% -> 6px -> 0
	bump = { -- S:696: the scoring side's number (text scales evenly: √(sx·sy))
		ms = 420,
		curve = "beat",
		frames = {
			{ at = 0, sx = 1, sy = 1 },
			{ at = 0.25, sx = 1.45, sy = 0.8 },
			{ at = 0.55, sx = 0.9, sy = 1.15 },
			{ at = 1, sx = 1, sy = 1 },
		},
	},
	shake = { ms = 320, px = 4, deg = 6, steps = { 0, -1, 1, -0.7, 0.5, -0.2, 0 } }, -- S:697 the squished head
	fill = { ms = 500, curve = "topFill" }, -- S:154 transition: width .5s
	trackAlpha = 0.55, -- S:154 rgba(30,20,40,.55)
	leaveDelay = 0.32, -- S:735: gone .32 s into the end
	deadDim = 0.6, -- [P] a knocked-out head's picture (S:956 greyscale; Roblox has none): darker
	pill = { height = 24, padX = 8, border = 2, radius = 9, gap = 6, below = 6 }, -- [P] your power-ups under it
	layouts = {
		desktop = {
			width = 1440,
			height = 900,
			top = 14, -- T:59 hudTop
			gap = 12, -- hgap
			feedGap = 12, -- S:990: the kill feed starts this far under it
			head = 40,
			headGap = 5,
			headPadTop = 4, -- zz hPadT
			headBorder = 3, -- zz hb
			headRadius = 12, -- hr
			headLip = 3, -- hs (box-shadow 0 3px 0 ink)
			headPad = 3, -- hp
			pictures = true, -- imgD
			youTag = true,
			deadMarks = true, -- the red bubble of seconds
			scoreW = 96,
			scoreRole = "matchTopScore", -- 52 px, stroke 10, drop 5
			scoreGap = 6, -- sGap
			bar = { height = 12, border = 3 }, -- hudBar, barBd
			timer = { -- S:157; timerH, tB, tSh, tPadL, tPadR, clock, tMin, timerFont 24
				height = 46,
				border = 4,
				lip = 4,
				padLeft = 9,
				padRight = 16,
				gap = 6,
				clock = 28,
				minWidth = 60,
				text = "Big",
			},
			timerGap = 5, -- tGap
			goal = { height = 22, padX = 8, border = 2, text = "Small" }, -- S:158 (12 px -> 16)
			tag = { top = -17, height = 17, padX = 5, border = 2, radius = 6, text = "Small" }, -- S:148
			respawn = { size = 26, border = 2, text = "Small", stroke = 3 }, -- S:147 rsS, rsF 14 -> 16
		},
		phone = {
			width = 750,
			height = 369,
			top = 10,
			gap = 10,
			feedGap = 6,
			head = 14,
			headGap = 4,
			headPadTop = 6,
			headBorder = 2,
			headRadius = 7, -- 999: a dot
			headLip = 0,
			headPad = 0,
			pictures = false,
			youTag = false,
			deadMarks = false,
			scoreW = 40,
			scoreRole = "matchTopScorePhone", -- 26 px, stroke 5, drop 2
			scoreGap = 0,
			bar = nil, -- barD none
			timer = {
				height = 26,
				border = 2,
				lip = 0,
				padLeft = 7,
				padRight = 11,
				gap = 6,
				clock = 15,
				minWidth = 34,
				text = "Small", -- 14 px -> 16
			},
			timerGap = 0,
			goal = nil, -- goalD none
			-- Free for All's place tags [P]: under the 14 px dot (the design's youTop head - 8 would hide the dot under the
			-- 16 px text, PR2), as tall as that text.
			tag = { top = 16, height = 20, padX = 5, border = 2, radius = 6, text = "Small" },
			respawn = nil,
		},
	},
}
