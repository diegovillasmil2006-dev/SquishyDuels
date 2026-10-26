--!strict
-- Config.UI.Match.medal: the squish medals (2026-10-26, owner: "Yes, build the medals like that, only for double and
-- triple squishes. You can make and upload the sound and picture."; `S:n` = Diego's LOADING SCREEN Y MATCH HUD page line
-- n): UI/Match/SquishMedal. Px of the page's legacy layer (S:63: 1440 x 810, scaled to fit the safe area, S:539).
-- Shared, data only. A child module of Config/UI (UI.luau is at Roblox's 200,000-character Source limit).

return {
	z = 5,
	layer = Vector2.new(1440, 810), -- S:63
	top = 470, -- S:67: the column's top
	gap = 6, -- S:70
	dockGap = 12, -- [P] lifted over the desktop ability bar by this much when it would reach it
	medal = { size = 96, border = 5, lip = 6, picture = 84, squashX = 1.3, squashY = 0.62, pictureDown = 22 }, -- S:73
	rays = { size = 216, turnSeconds = 6 }, -- S:72: left/top -60, sdSpin 6s
	plus = { right = -18, top = -8, height = 30, padX = 9, border = 4, role = "matchFeedName" }, -- S:74: 17 px, stroke 4
	titleRole = "matchMedalTitle", -- S:76: 42 px #FFE36B, stroke 9, drop 5
	nameRole = "matchRespawnLabel", -- S:77: 20 px white, stroke 5
	streak = { -- S:78: from a streak of 2
		min = 2,
		height = 32,
		padLeft = 4,
		padRight = 12,
		border = 3,
		lip = 3,
		flame = 28,
		flameUp = 4, -- margin-top -4
		gap = 4,
		role = "small", -- 16 px white, stroke 4
	},
	motion = { -- S:36 smMedal over 1.9 s, cubic-bezier(.2,1.3,.4,1) each step (Config.UI.curves.medal)
		ms = 1900,
		curve = "medal",
		frames = {
			{ at = 0, alpha = 0, scale = 2.6, rot = -10, y = 0 },
			{ at = 0.14, alpha = 1, scale = 0.86, rot = 2, y = 0 },
			{ at = 0.22, alpha = 1, scale = 1.08, rot = 0, y = 0 },
			{ at = 0.3, alpha = 1, scale = 1, rot = 0, y = 0 },
			{ at = 0.82, alpha = 1, scale = 1, rot = 0, y = 0 },
			{ at = 1, alpha = 0, scale = 0.9, rot = 0, y = -40 },
		},
	},
	goneAt = 1.95, -- S:706
	claimDelay = 0.09, -- S:707: the chime 90 ms after the stamp
	fx = { delay = 0.16, n = 26, spread = 230, size = 13, ring = 260 }, -- S:708: FX.burst and the #FFE36B FX.ring
}
