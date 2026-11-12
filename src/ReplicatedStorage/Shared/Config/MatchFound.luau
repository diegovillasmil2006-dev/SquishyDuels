--!strict
-- Config.UI.MatchFound: the MATCH FOUND show. A child module of Config/UI (audit row 8, 2026-11-12: UI.luau was over
-- Roblox's 200,000-character Source limit, where the go-back tool fails); moved as it was.
-- Round 2 of the match flow (2026-10-25, owner: Diego's MATCH FOUND show for every mode; UI/MatchFoundShow; `L:n` =
-- "Squishy Duels LOBBY HUD.dc.html" line n, ALL HUDS zip; the markup L:626-741, the timeline L:1024-1048). Px are the
-- design's stage px (1440 x 810, centred and scaled to fit the screen, L:629); `ms` / `delayMs` from the show's start;
-- colours are Art/Palette names. The effects (converge, rings, burst, rain, jolt) are Fx.events.matchFound.

type ScreenGuiSpec = { displayOrder: number, insets: Enum.ScreenInsets } -- Config/UI's
type MotionPose = { -- Config/UI's
	at: number,
	x: number?,
	y: number?,
	sx: number?,
	sy: number?,
	scale: number?,
	rot: number?,
	alpha: number?,
}

return {
	layerName = "SD_MatchFound",
	-- L:627 z 30: over the windows and the HUD layers, under SD_Overlay 30 (UiFx's effects draw over the show, as the
	-- design's own FX layer does) and SD_Fade 40.
	layer = { displayOrder = 29, insets = Enum.ScreenInsets.None } :: ScreenGuiSpec,
	stage = { width = 1440, height = 810 },
	backdrop = { pad = 80, fadeMs = 350 }, -- L:628: inset -80px, sdFade .35s ease-out
	-- L:630-637 the rays group at (720, 330): the warm glow and the rays in (sdMfRaysIn, .46 s), the rays turning
	-- (sdSpin 28 s), the charge orb (sdMfOrb .5 s) and the white flash (sdMfFlash .6s .47s).
	centre = { x = 720, y = 330 },
	glow = { px = 760, ms = 800, delayMs = 460, curve = "easeOut" },
	rays = { px = 1560, ms = 900, delayMs = 460, curve = "coinFlip", spinS = 28 },
	raysFrames = { -- sdMfRaysIn
		{ at = 0, alpha = 0, scale = 0.15 },
		{ at = 0.6, alpha = 1, scale = 1.06 },
		{ at = 1, alpha = 1, scale = 1 },
	} :: { MotionPose },
	orb = {
		px = 180,
		ms = 500,
		curve = "mfOrb",
		frames = { -- sdMfOrb
			{ at = 0, alpha = 0, scale = 0 },
			{ at = 0.25, alpha = 1 },
			{ at = 0.8, alpha = 1, scale = 1.15 },
			{ at = 1, alpha = 0, scale = 0.2 },
		} :: { MotionPose },
	},
	flash = {
		px = 420,
		ms = 600,
		delayMs = 470,
		curve = "easeOut",
		frames = { -- sdMfFlash
			{ at = 0, alpha = 0, scale = 0.2 },
			{ at = 0.1, alpha = 1 },
			{ at = 1, alpha = 0, scale = 3.4 },
		} :: { MotionPose },
	},
	-- L:741 sdMfWhite .5s .47s ease-out: the whole screen in MatchFoundFlash (not under ReducedMotion).
	white = {
		ms = 500,
		delayMs = 470,
		curve = "easeOut",
		color = "MatchFoundFlash",
		frames = { { at = 0, alpha = 0 }, { at = 0.12, alpha = 0.7 }, { at = 1, alpha = 0 } } :: { MotionPose },
	},
	-- L:639-662 the found block (1440 x 560, turned about (720, 370)): the ribbon at (720, 370) with its tails, the
	-- emblem, the mode pill and the twinkles.
	block = { height = 560, originY = 370 },
	ribbon = {
		face = { x = 320, y = 306, width = 800, height = 128 }, -- L:645: left -400, top -64 of (720, 370)
		picture = { width = 880, height = 220, faceX = 40, faceY = 20 }, -- img.mf.banner: the face at (40, 20)
		ms = 500, -- L:645 sdMfUnfurl .5s .56s cubic-bezier(.3,1.3,.5,1)
		delayMs = 560,
		curve = "unfurl",
		openAt = 0.7, -- its clip opens from the middle (inset 50%) to -60 px by 70%
		openPad = 60,
		frames = {
			{ at = 0, alpha = 0, sy = 0.6 },
			{ at = 0.2, alpha = 1 },
			{ at = 0.7, sy = 1.08 },
			{ at = 1, alpha = 1, sy = 1 },
		} :: { MotionPose },
		border = 6,
		radius = 34,
		shine = { width = 90, overhang = 20, periodS = 2.8, delayS = 1.4, alpha = 0.25, rotation = 20 }, -- L:648
	},
	-- L:642-643 the tails (140 x 132), sdMfTailL / R .42s .82s cubic-bezier(.2,1.4,.4,1).
	tails = {
		width = 140,
		height = 132,
		leftX = 230,
		rightX = 1070,
		y = 330,
		ms = 420,
		delayMs = 820,
		curve = "search",
	},
	tailFrames = { { at = 0, alpha = 0, x = 90, sx = 0.3 }, { at = 1, alpha = 1, x = 0, sx = 1 } } :: { MotionPose },
	-- L:651: the letters (92 px, stroke 13, the 7 px drop), the space 30 px wide; sdMfLet .52s from .64 s + .045 s
	-- each (cubic-bezier(.2,1.5,.4,1)), then sdLvWave 1.8 s from 1.6 s + .09 s each.
	letters = {
		spacePx = 30,
		padBottom = 8,
		ms = 520,
		delayMs = 640,
		stepMs = 45,
		curve = "stars",
		frames = {
			{ at = 0, alpha = 0, y = 70, scale = 0.2, rot = -24 },
			{ at = 0.55, alpha = 1, y = -20, sx = 1.28, sy = 1.12, rot = 7 },
			{ at = 0.78, y = 5, sx = 0.94, sy = 1.05, rot = -2 },
			{ at = 1, alpha = 1, y = 0 },
		} :: { MotionPose },
		wave = { periodS = 1.8, delayS = 1.6, stepS = 0.09 }, -- motion.loops.lvWave's frames
	},
	-- L:655-657 the emblem (240 at (600, 70)): sdMfSlam .62s .44s cubic-bezier(.2,1,.4,1), then sdBob 2.6s from 1.3s;
	-- its drop shadow 0 9px 0 at .4.
	emblem = {
		x = 600,
		y = 70,
		px = 240,
		ms = 620,
		delayMs = 440,
		curve = "beat",
		shadowY = 9,
		shadowAlpha = 0.4,
		bobS = 2.6,
		bobDelayS = 1.3,
		frames = {
			{ at = 0, alpha = 0, scale = 3.4, rot = -28 },
			{ at = 0.5, alpha = 1, sx = 0.78, sy = 0.9, rot = 4 },
			{ at = 0.68, sx = 1.14, sy = 1.06, rot = -2 },
			{ at = 0.84, sx = 0.96, sy = 1.02, rot = 1 },
			{ at = 1, alpha = 1, scale = 1, rot = 0 },
		} :: { MotionPose },
	},
	-- L:658-661 the mode pill at top 466 (sdUp .45s 1.1s): 54 tall, padding 0 24 0 8, gap 12, border 5, the 6 px lip,
	-- the 3 px highlight at .12, on StickerPickerWell; its chip 34 tall, padding 0 12, border 3, the mode's gradient.
	pill = {
		y = 466,
		height = 54,
		padLeft = 8,
		padRight = 24,
		gap = 12,
		border = 5,
		lip = 6,
		highlightPx = 3,
		highlightAlpha = 0.12,
		color = "StickerPickerWell",
		chipHeight = 34,
		chipPad = 12,
		chipBorder = 3,
		ms = 450,
		delayMs = 1100,
		curve = "search",
		frames = { { at = 0, alpha = 0, y = 30 }, { at = 1, alpha = 1, y = 0 } } :: { MotionPose },
	},
	-- L:662 the twinkles { x, y, px, colour, delay s }, sdTwinkle 1.7 s.
	twinkleS = 1.7,
	twinkles = {
		{ 262, 290, 36, "StickerCreamYellow", 1 },
		{ 1146, 284, 42, "White", 1.3 },
		{ 318, 446, 24, "StickerPinkSoft", 1.6 },
		{ 1104, 452, 28, "StickerCreamYellow", 1.9 },
		{ 520, 96, 26, "White", 1.2 },
		{ 896, 82, 32, "StickerPinkSoft", 1.7 },
	},
	-- L:722-736 the players row at top 572, gap 12: each tile 66 (border 4, radius 18, the 5 px lip, the 4 px
	-- highlight at .45, the 6 px bottom shade at .12) with its squishy (56) and Grip level (right -8, bottom -9: 24
	-- tall, at least 30 wide, padding 0 6, border 3, radius 10); yours with YOU over it (top -36: 26 tall, padding 0
	-- 9, border 3, radius 9, the 3 px lip, bobbing 1.6 s); the VS badge (84, margin 0 6) before the second team.
	roster = {
		y = 572,
		gap = 12,
		tile = 66,
		border = 4,
		radius = 18,
		lip = 5,
		highlightPx = 4,
		highlightAlpha = 0.45,
		shadePx = 6,
		shadeAlpha = 0.12,
		picPx = 56,
		level = { right = -8, bottom = -9, height = 24, minWidth = 30, pad = 6, border = 3, radius = 10 },
		you = { top = -36, height = 26, pad = 9, border = 3, radius = 9, lip = 3, bobS = 1.6 },
		vs = { px = 84, margin = 6, ms = 550, delayMs = 1550, curve = "rise", rotation = -6 },
		-- Team modes: each half slides in from its side (sdMfInL / R .56s cubic-bezier(.2,1.2,.4,1)), the tiles nearest
		-- the middle first, .05 s apart from 1.2 s; Free for All: sdReveal .5s (cubic-bezier(.2,1.3,.4,1)) in order.
		slideMs = 560,
		slideCurve = "coinFlip",
		revealMs = 500,
		revealCurve = "rise",
		startMs = 1200,
		stepMs = 50,
		slideFrames = {
			{ at = 0, alpha = 0, x = -640, rot = -40 },
			{ at = 0.7, alpha = 1, x = 16, rot = 8 },
			{ at = 0.85, x = -5, rot = -3 },
			{ at = 1, alpha = 1, x = 0, rot = 0 },
		} :: { MotionPose },
		revealFrames = {
			{ at = 0, alpha = 0, scale = 0, rot = -30 },
			{ at = 0.55, alpha = 1, scale = 1.25, rot = 8 },
			{ at = 0.75, scale = 0.92, rot = -3 },
			{ at = 1, alpha = 1, scale = 1, rot = 0 },
		} :: { MotionPose },
		vsFrames = {
			{ at = 0, alpha = 0, scale = 4.5, rot = -35 },
			{ at = 0.5, alpha = 1, scale = 0.75, rot = 10 },
			{ at = 0.72, scale = 1.18, rot = -9 },
			{ at = 1, alpha = 1, scale = 1, rot = -6 },
		} :: { MotionPose },
	},
	-- L:1036-1048 the sounds (ms from the start; DUEL and TEAM whoosh and slam, FREE FOR ALL a second run of letters
	-- and a chime) and each one's look-alike while its own id is missing.
	sounds = {
		charge = { key = "match.found.charge", fallback = "sfx.inspect.whoosh", atMs = 0 },
		impact = { key = "match.found.impact", fallback = "sfx.impactSoft", atMs = 470 },
		letters = { key = "match.found.letters", fallback = "ui.click", atMs = 640 },
		chime = { key = "match.found.chime", fallback = "ui.coin", atMs = 1110 },
		whoosh = { key = "match.whoosh", fallback = "sfx.inspect.whoosh", atMs = 1200 },
		vs = { key = "match.found.vs", fallback = "sfx.impactSoft", atMs = 1570 },
		lettersSolo = { key = "match.found.lettersSolo", fallback = "ui.click", atMs = 1200 },
		chimeSolo = { key = "match.found.chime", fallback = "ui.coin", atMs = 1830 },
	},
	-- L:1048, L:1051: at 3 s the block flies up (translateY(-250px) scale(.4), fading, 460 ms cubic-bezier(.55,0,
	-- .8,.35)) with a whoosh; the rest (dim, rays, players) stays until the arena (the match or duel past
	-- Positioning), at most holdMaxS, then fades out over backdrop.fadeMs.
	exit = {
		atMs = 3000,
		ms = 460,
		curve = "mfFly",
		frames = { { at = 0, alpha = 1, y = 0, scale = 1 }, { at = 1, alpha = 0, y = -250, scale = 0.4 } } :: { MotionPose },
		holdMaxS = 6,
	},
	-- Round 3 of the match flow (2026-10-25, owner: the map vote for Team and Free for All; UI/MatchVoteBoard): L:665-720
	-- the markup, L:1056-1147 the timeline, lib:361-375 the chip toss. Stage px; ms from the swap (the block's flight)
	-- unless named; the vote's own times are the server's (Types.MatchVoteView).
	vote = {
		leadMs = 640, -- L:1065: the swap starts this long before the vote opens (at the earliest at exit.atMs)
		raysY = 390, -- L:630: the rays group moves down (.6 s) and fades to raysAlpha, back to 1 at the reveal
		raysAlpha = 0.42,
		raysMs = 600,
		rosterY = 628, -- L:727: the players row moves down (.7 s)
		rosterMs = 700,
		moveCurve = "mfMove",
		-- L:1059-1062, L:1078-1146 the sounds and each one's look-alike while its own id is missing. landSteps: the
		-- n-th voter's landing note (semitones, lib:259); rouletteLow: every other roulette step's (lib:269).
		sounds = {
			open = { key = "match.vote.open", fallback = "ui.coin", atMs = 280 },
			card = { key = "match.vote.card", fallback = "ui.click", atMs = 420, stepMs = 100 },
			press = { key = "ui.click", fallback = "ui.click" },
			tick = { key = "match.vote.tick", fallback = "ui.click" },
			tickUrgent = { key = "match.vote.tickUrgent", fallback = "ui.click" },
			toss = { key = "match.vote.toss", fallback = "sfx.inspect.whoosh" },
			land = { key = "match.vote.land", fallback = "ui.coin" },
			landMine = { key = "match.vote.landMine", fallback = "ui.coin" },
			stamp = { key = "match.vote.stamp", fallback = "sfx.impactSoft" },
			roulette = { key = "match.vote.roulette", fallback = "ui.click" },
			fanfare = { key = "match.vote.fanfare", fallback = "ui.coin" },
			burst = { key = "match.vote.burst", fallback = "sfx.impactSoft", atMs = 360 },
			whoosh = { key = "match.whoosh", fallback = "sfx.inspect.whoosh" },
		},
		landSteps = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26 },
		rouletteLow = -5,
		-- L:666-672 the head at (720, 80): its tails, the pill (img.vote.head*: the 600 x 92 face at (40, 20) of 680 x
		-- 170), the shine (70 px, sdShine 3.4s 1s) and the mode name (44 px) with its chip (32 tall, padding 0 10, ink,
		-- 17 px), 14 apart; sdMfHeadIn .6s .12s cubic-bezier(.25,1.3,.45,1).
		head = {
			x = 720,
			y = 80,
			picture = { width = 680, height = 170, faceX = 40, faceY = 20 },
			face = { width = 600, height = 92, border = 6, radius = 28 },
			tails = { width = 110, height = 104, leftX = -372, rightX = 262, y = -32 },
			gap = 14,
			chipHeight = 32,
			chipPad = 10,
			shine = { width = 70, periodS = 3.4, delayS = 1, transparency = 0.4 }, -- white at .6 in its middle
			ms = 600,
			delayMs = 120,
			curve = "mfHead",
			frames = {
				{ at = 0, alpha = 0, y = 240, scale = 1.7 },
				{ at = 0.6, alpha = 1, y = -8, scale = 0.95 },
				{ at = 0.8, y = 3, scale = 1.02 },
				{ at = 1, alpha = 1, y = 0, scale = 1 },
			} :: { MotionPose },
		},
		-- L:673-689 the line under it (top 134, 80 tall, 16 apart; sdUp .4s .35s ease) and the timer (76: its ink disc
		-- 73 at (1.5, 6.5), the face r 34 with a 5 px ink ring, the track r 25 x 7 at .28 ink, the white progress
		-- from 12 o'clock); each second's tick pops it 1.32 -> 1 (320 ms, cubic-bezier(.2,1.6,.4,1)); from urgentAt
		-- seconds on it is red and pulses 1.16 every .5 s.
		sub = {
			y = 134,
			height = 80,
			gap = 16,
			ms = 400,
			delayMs = 350,
			curve = "ease",
			frames = { { at = 0, alpha = 0, y = 30 }, { at = 1, alpha = 1, y = 0 } } :: { MotionPose },
		},
		timer = {
			px = 76,
			shadow = { x = 1.5, y = 6.5, px = 73 },
			facePx = 68, -- r 34
			border = 5,
			ringPx = 76, -- img.vote.ring (r 25, 7 wide) drawn over the whole 76
			trackAlpha = 0.28,
			color = "StickerGoldMid",
			urgentColor = "MatchFeedYouDown",
			urgentAt = 3,
			tickMs = 320,
			tickScale = 1.32,
			tickCurve = "slot",
			urgentPeriodS = 0.5,
			urgentScale = 1.16,
		},
		-- L:690-705 the cards (372 x 292 at top 248, 30 apart; img.vote.card.*: the card at (40, 30) of 452 x 400, its
		-- floating board img.vote.board.* on the same canvas), sdMfCardIn .62s from .3 s + .1 s each
		-- (cubic-bezier(.2,1.3,.4,1)); the board floats 9 px (sdMfFloat 3.6 s, each 1.2 s ahead); 3 twinkles each
		-- { x, y, px, delay s } (sdTwinkle 1.7 s).
		cards = {
			y = 248,
			width = 372,
			height = 292,
			gap = 30,
			picture = { width = 452, height = 400, cardX = 40, cardY = 30 },
			ms = 620,
			delayMs = 300,
			stepMs = 100,
			curve = "rise",
			frames = {
				{ at = 0, alpha = 0, y = 300, scale = 0.55, rot = -6 },
				{ at = 0.6, alpha = 1, y = -16, scale = 1.04, rot = 1 },
				{ at = 0.8, y = 5, scale = 0.99 },
				{ at = 1, alpha = 1, y = 0, scale = 1 },
			} :: { MotionPose },
			floatS = 3.6,
			floatStepS = 1.2,
			floatPx = 9,
			twinkleS = 1.7,
			twinkles = { { 30, 26, 22, 0.2 }, { 318, 44, 18, 0.9 }, { 56, 150, 14, 1.4 } },
			-- L:690 the glow (inset -12, radius 40, 0 0 44px 10px at .6; img.vote.glow: the 160 box at (70, 70) of
			-- 300, 9-sliced at 110), gold, white on the roulette's card; it pulses 1.025 (sdMfGlow 1.1 s).
			glow = {
				inset = 12,
				pad = 70,
				slice = 110,
				picturePx = 300,
				color = "StickerCoinText",
				rouletteColor = "White",
				fadeMs = 250,
				pulseS = 1.1,
				pulseScale = 1.025,
			},
			-- L:694, L:1394-1398 the cards' transition (.6s cubic-bezier(.3,1.45,.45,1); the tint and alpha .45 s): your
			-- pick lifted, the roulette's card raised and the others dimmed, the winner to the middle and the others
			-- down, smaller, greyed (grayscale(.85) brightness(.7): a grey tint here) and faded.
			moveMs = 600,
			moveCurve = "mfCard",
			tintMs = 450,
			mine = { y = -10, scale = 1.03 },
			roulette = { y = -12, scale = 1.05, others = 0.78 },
			won = { stepX = 402, y = -8, scale = 1.14 },
			lost = { y = 40, scale = 0.82, tint = 0.7, alpha = 0.45 },
		},
		-- L:707 the voters strip (left 14, top -26): 46 px chips 28 apart (margin-right -18), border 4, radius 15, the
		-- team colour, the 3 px lip and 3 px highlight at .45, the squishy 40; each sticks in (sdMfStick .42s).
		strip = {
			left = 14,
			top = -26,
			px = 46,
			step = 28,
			border = 4,
			radius = 15,
			lip = 3,
			highlightPx = 3,
			highlightAlpha = 0.45,
			picPx = 40,
			ms = 420,
			curve = "slot",
			frames = {
				{ at = 0, sx = 1.6, sy = 1.3, rot = -10 },
				{ at = 0.45, sx = 0.78, sy = 1.18, rot = 5 },
				{ at = 0.7, sx = 1.12, sy = 0.9, rot = -2 },
				{ at = 1, sx = 1, sy = 1, rot = 0 },
			} :: { MotionPose },
		},
		-- L:710 the count (right -16, top -20: 58, border 5, the 4 px lip, the 3 px highlight at .6, 28 px): gold for
		-- the single leader, else lilac; it pops in (sdSlot .35s) and squashes 1.3 at each landing (lib:376).
		count = {
			right = -16,
			top = -20,
			px = 58,
			border = 5,
			lip = 4,
			highlightPx = 3,
			highlightAlpha = 0.6,
			leaderTop = "StickerYellowTop",
			leaderEnd = "StickerYellowEnd",
			top0 = "MatchFfaPurpleTop",
			end0 = "MatchFfaPurple",
			squash = 1.3,
			squashMs = 460,
		},
		-- sdSlot .35s cubic-bezier(.2,1.6,.4,1): the count, YOUR VOTE and the roster's voted check pop in.
		popMs = 350,
		popCurve = "slot",
		popFrames = { { at = 0, scale = 0 }, { at = 0.65, scale = 1.35 }, { at = 1, scale = 1 } } :: { MotionPose },
		-- L:714 YOUR VOTE (bottom -20: 38 tall, padding 0 16 0 10, border 4, the green button, the 4 px lip, the 3 px
		-- highlight at .5, 17 px, the check 22, 6 apart).
		mine = {
			bottom = -20,
			height = 38,
			padLeft = 10,
			padRight = 16,
			gap = 6,
			border = 4,
			lip = 4,
			highlightPx = 3,
			highlightAlpha = 0.5,
			iconPx = 22,
		},
		-- L:715 LET'S GO! (top 70: 66 tall, padding 0 26, border 5, radius 20, the pink button, the 6 px lip, the 4 px
		-- highlight at .55, 38 px), stamped (sdStamp .5s .25s cubic-bezier(.2,1.3,.4,1)).
		go = {
			top = 70,
			height = 66,
			pad = 26,
			border = 5,
			radius = 20,
			lip = 6,
			highlightPx = 4,
			highlightAlpha = 0.55,
			ms = 500,
			delayMs = 250,
			curve = "rise",
			frames = {
				{ at = 0, alpha = 0, scale = 3, rot = -25 },
				{ at = 0.6, alpha = 1, scale = 0.9, rot = -8 },
				{ at = 1, alpha = 1, scale = 1, rot = -10 },
			} :: { MotionPose },
		},
		-- L:735 the roster's voted check (28 at right -9, top -9, border 3, green, the check 16).
		check = { px = 28, right = -9, top = -9, border = 3, iconPx = 16 },
		-- lib:361-375 the toss: a 46 px chip from the voter's tile to its place in the strip (yours 10 px higher while
		-- your pick moves), 560 ms (yours) / 700, arcing 110 / 150 above, spinning 360 (.7 -> 1.25 at 55% -> 1,
		-- ease-out); yours trails sparks (7 puffs); the landing's burst (L:1101) and the count's squash.
		toss = {
			px = 46,
			mineMs = 560,
			otherMs = 700,
			mineArc = 110,
			otherArc = 150,
			peakAt = 0.6,
			spin = 360,
			raise = 10,
			frames = {
				{ at = 0, scale = 0.7, rot = 0 },
				{ at = 0.55, scale = 1.25, rot = 216 },
				{ at = 1, scale = 1, rot = 360 },
			} :: { MotionPose },
			trail = { puffs = 7, n = 2, spread = 30, size = 8, ms = 420, colors = { "StickerCoinText", "White" } },
			landMine = {
				n = 16,
				spread = 130,
				size = 12,
				up = 20,
				colors = { "StickerCoinText", "White", "StickerFxGreen" },
			},
			landOther = { n = 9, spread = 80, size = 9, up = 20 },
			teamColors = { "StickerTdmRed", "StickerTdmBlue" },
			soloColor = "StickerFxYellow",
		},
		-- L:1129-1141 the reveal: the burst at (720, 390) 360 ms after it, the rings, the rain and the jolt; 3.1 s later
		-- the show goes (opacity 0, scale 1.04, 420 ms ease-in) and the teleport toast shows.
		reveal = {
			x = 720,
			y = 390,
			sparks = {
				n = 42,
				spread = 440,
				size = 15,
				ms = 1100,
				colors = { "StickerFxYellow", "StickerFxPink", "StickerFxCyan", "White", "StickerFxGreen" },
			},
			rings = { { color = "StickerCoinText", size = 560 }, { color = "White", size = 760, delayMs = 90 } },
			rain = 70,
			jolt = 8,
			endAfterMs = 3100,
			fadeMs = 420,
			fadeScale = 1.04,
			fadeCurve = "easeIn",
		},
		tapGapMs = 250, -- [P] taps closer than this are one (the server takes one vote per Config.Match.Vote.minIntervalSeconds)
		pickHoldS = 1.5, -- [P] your tapped card stays yours this long while the server's view catches up
	},
}
