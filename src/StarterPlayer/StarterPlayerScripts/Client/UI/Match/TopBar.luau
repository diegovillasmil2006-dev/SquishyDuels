--!strict
-- TopBar (client only). The live top bar (2026-10-26, owner: "Yes, build the live top bar like that (Free for All: the
-- leader vs you), after the cake podium step 1 is done."; `S:n` = Diego's "Squishy Duels LOADING SCREEN Y MATCH
-- HUD.dc.html" line n, `T:n` = its uploads/tdm-hud.js line n): a MatchHudController piece ("topBar"), top centre from the
-- 3-2-1 (it drops in with the count, S:661-665) through Overtime (MatchHudFormat.topBarLive), gone leaveDelay into the
-- Result (S:735). One row (S:142) in stage px under the intro's stage scale (T:57 desktop, T:64 phone):
--   [heads] [score + bar] [timer + FIRST TO n] [score + bar] [heads]
-- * Team: your team left (MatchIntro.columns: you first, nearest the score; S:956 radiating out), 6 slots a side. A head
--   (MatchKit.head, S:146) is the avatar head (a bot: its squishy) on its team's light inside the team's gradient, an
--   ink lip under it; yours has the #FFD86B border and the YOU tag (S:148); a knocked-out head turns grey with a red
--   bubble of the seconds until they are back (S:147). Each score in its team's colour (S:153, S:161) over a bar of
--   score / target filling from the middle out (S:154, S:162: .5 s with an overshoot).
-- * Free for All [P, owner's pick]: one head a side, the best other player left (MatchHudFormat.ffaRival: the leader,
--   the runner-up when you lead) vs you right, each with their place tag (MatchEnd.ordinal), K.O.s and bar.
-- * Middle (S:157-158): the timer pill (img.icon.clock; MatchHudFormat.topBarTime, OVERTIME in overtime) over the
--   yellow FIRST TO {target} pill.
-- * Phone (T:66, S:490 zz()): the heads are small dots in their colours (no pictures, YOU tags or bubbles; Free for
--   All keeps its place tags), no bars and no goal pill.
-- * Motion: drops in from the top (S:665); a side whose score goes up bumps its number (S:696; text scales evenly:
--   √(sx·sy)); a squished player's head shakes (S:697). Reduced motion: it simply shows, no bump or shake.
-- * Under it: your live power-ups as small pills (what the old test readout listed, [P]); the toast column
--   (ctx.toastsBelow) and the kill feed (ctx.shared.topBarBottom, S:990) start under it. MatchController leaves its test
--   readout off while Config.UI.Match.enabled.topBar is on.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local MatchFormat = require(UI.MatchFormat)
local MatchHudFormat = require(UI.MatchHudFormat)
local Theme = require(UI.Theme)
local Tweens = require(UI.Parent.Anim.Tweens)
local MatchEnd = require(script.Parent.MatchEnd)
local MatchIntro = require(script.Parent.MatchIntro)
local MatchKit = require(script.Parent.MatchKit)

-- Types

type Side = {
	players: { any }, -- view players, nearest the score first
	score: number,
	scoreColor: Color3,
	fill: { top: Color3, faceEnd: Color3 },
	tags: { [number]: string }, -- userId -> the tag over their head
	key: string, -- what the colours depend on (the team or the rival)
}

type Slot = { frame: Frame, poser: Tweens.Poser, key: string, userId: number?, bubble: TextLabel?, shakeAt: number? }

type Score = {
	holder: Frame,
	label: TextLabel,
	poser: Tweens.Poser,
	fill: Frame?,
	gradient: UIGradient?,
	key: string,
	value: number?,
	bumpAt: number?,
	from: number,
	to: number,
	fillAt: number,
}

type Made = {
	layout: string,
	L: any,
	root: Frame,
	scale: UIScale,
	pose: Frame,
	heads: { Frame },
	slots: { { Slot } },
	scores: { Score },
	timer: Frame,
	pill: Frame,
	lip: Frame?,
	time: TextLabel,
	goal: Frame?,
	boosts: Frame,
	boostKey: string,
	rowSize: Vector2,
	timeWidth: number,
}

-- Constants

local CFG = Config.UI.Match.topBar
local MATCH = Config.Match
local TEAM_NAMES = MATCH.teamNames
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local WORDS = Strings.matchHud.top
local READOUT = Strings.match.readout
local CLOCK_KEY = "img.icon.clock"
local SLOTS = 6 -- S:960: six heads a side
local SCORE_SAMPLE = "88" -- the widest score: the number keeps one width
local TOAST_KEY = "match"
local MEASURE_MARGIN_PX = 2
local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Colors.inkUI

-- Module table

local TopBar = {}

-- Private: builders -----------------------------------------------------------------------------------------------------

local function frame(name: string, props: { [string]: any }): Frame
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false }
	for key, value in props do
		base[key] = value
	end
	return Create("Frame", base)
end

-- A pill: the ink border inside, a top -> end gradient (or one colour), its text centred in ink.
local function pill(name: string, text: string, kind: string, spec: any, top: Color3, faceEnd: Color3, z: number): Frame
	local label, size = MatchKit.line("Text", text, kind, INK, nil, z)
	local height = math.max(spec.height, size.Y)
	local box = frame(name, {
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(size.X + 2 * (spec.padX + spec.border), height),
		ZIndex = z,
	})
	Theme.corner(spec.radius or height / 2, box)
	MatchKit.gradient(box, { text = INK, top = top, faceEnd = faceEnd })
	MatchKit.inner(Theme.stroke(INK, spec.border, box))
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Parent = box
	return box
end

-- A side's score (S:153) and, on the desktop, its bar under it (S:154): the fill grows from the middle out.
local function scoreBlock(name: string, L: any, inward: number, z: number): Score
	local label, labelSize = MatchKit.label({ name = "Score", text = SCORE_SAMPLE, role = L.scoreRole, z = z })
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	local bar = L.bar
	local height = labelSize.Y + (if bar then L.scoreGap + bar.height else 0)
	local holder = frame(name, { Size = UDim2.fromOffset(L.scoreW, height), ZIndex = z })
	label.Parent = holder
	local fill: Frame? = nil
	local gradient: UIGradient? = nil
	if bar then
		local track = frame("Track", {
			BackgroundTransparency = 1 - CFG.trackAlpha,
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, labelSize.Y + L.scoreGap),
			Size = UDim2.fromOffset(L.scoreW, bar.height),
			ClipsDescendants = true,
			ZIndex = z,
			Parent = holder,
		})
		Theme.corner(bar.height / 2, track)
		MatchKit.inner(Theme.stroke(INK, bar.border, track))
		local made = frame("Fill", {
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			AnchorPoint = Vector2.new(inward, 0),
			Position = UDim2.new(inward, (1 - 2 * inward) * bar.border, 0, bar.border),
			Size = UDim2.fromOffset(0, bar.height - 2 * bar.border),
			ZIndex = z,
			Parent = track,
		})
		Theme.corner((bar.height - 2 * bar.border) / 2, made)
		gradient = Create("UIGradient", { Rotation = 90, Parent = made })
		fill = made
	end
	return {
		holder = holder,
		label = label,
		poser = Tweens.poser(label),
		fill = fill,
		gradient = gradient,
		key = "",
		value = nil,
		bumpAt = nil,
		from = 0,
		to = 0,
		fillAt = -math.huge,
	}
end

-- The middle (S:157-158): the timer pill with its lip, the clock and the time, and the goal pill under it.
local function timerBlock(L: any, view: any, z: number): (Frame, Frame, Frame?, TextLabel, Frame?)
	local T = L.timer
	local holder = frame("Timer", { ZIndex = z })
	local lip: Frame? = nil
	if T.lip > 0 then
		lip = frame("Lip", {
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, T.lip),
			Size = UDim2.fromOffset(0, T.height),
			ZIndex = z,
			Parent = holder,
		})
		Theme.corner(T.height / 2, lip :: Frame)
	end
	local pillFrame = frame("Pill", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.MatchTopTimer,
		Size = UDim2.fromOffset(0, T.height),
		ZIndex = z,
		Parent = holder,
	})
	Theme.corner(T.height / 2, pillFrame)
	MatchKit.inner(Theme.stroke(INK, T.border, pillFrame))
	local picture = AssetTable.image(CLOCK_KEY)
	if picture then
		Create("ImageLabel", {
			Name = "Clock",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, T.padLeft, 0.5, 0),
			Size = UDim2.fromOffset(T.clock, T.clock),
			Image = picture,
			ZIndex = z,
			Active = false,
			Parent = pillFrame,
		})
	end
	local time = MatchKit.line("Time", "0:00", T.text, WHITE, nil, z)
	time.AnchorPoint = Vector2.new(0, 0.5)
	time.Position = UDim2.new(0, T.padLeft + T.clock + T.gap, 0.5, 0)
	time.Parent = pillFrame
	local goal: Frame? = nil
	local G = L.goal
	if G then
		local text = Strings.format(WORDS.goal, { target = view.koTarget or 0 })
		local made = pill("Goal", text, G.text, G, Palette.MatchTopGoalTop, Palette.Lemon, z)
		made.AnchorPoint = Vector2.new(0.5, 0)
		made.Parent = holder
		goal = made
	end
	return holder, pillFrame, lip, time, goal
end

-- Private: what each side shows -----------------------------------------------------------------------------------------

local function teamFill(team: string?): { top: Color3, faceEnd: Color3 }
	local look = MatchHudFormat.playerLook("tdm", team, nil)
	return { top = look.top, faceEnd = look.mid or look.faceEnd }
end

local function teamScoreColor(team: string?): Color3
	return if team == TEAM_NAMES[2] then Palette.MatchTeamBlueScore else Palette.MatchTeamRedScore
end

local function sides(ctx: MatchHudFormat.Context, view: any): (Side, Side)
	if view.mode == "tdm" then
		local cols = MatchIntro.columns(view)
		local score = view.teamScore or {}
		local function side(team: string, players: { any }): Side
			local tags = {}
			if view.you.userId then
				tags[view.you.userId] = WORDS.you
			end
			return {
				players = players,
				score = score[team] or 0,
				scoreColor = teamScoreColor(team),
				fill = teamFill(team),
				tags = tags,
				key = team,
			}
		end
		return side(cols.leftTeam, cols.left), side(cols.rightTeam, cols.right)
	end
	local mine: any = nil
	for _, player in view.players do
		if player.userId == view.you.userId then
			mine = player
		end
	end
	local rival = MatchHudFormat.ffaRival(view)
	local left: Side = {
		players = {},
		score = 0,
		scoreColor = WHITE,
		fill = { top = WHITE, faceEnd = WHITE },
		tags = {},
		key = "",
	}
	if rival then
		local look = MatchKit.who(ctx, view, rival.userId).look
		left = {
			players = { rival },
			score = rival.kos,
			scoreColor = look.text,
			fill = { top = look.top, faceEnd = look.mid or look.faceEnd },
			tags = { [rival.userId] = MatchEnd.ordinal(MatchHudFormat.placeOf(view, rival.userId)) },
			key = tostring(rival.userId),
		}
	end
	local right: Side = {
		players = if mine then { mine } else {},
		score = if mine then mine.kos else 0,
		scoreColor = Palette.Lemon,
		fill = { top = Palette.MatchTopGoalTop, faceEnd = Palette.Lemon },
		tags = if mine then { [mine.userId] = MatchEnd.ordinal(MatchHudFormat.placeOf(view, mine.userId)) } else {},
		key = "you",
	}
	return left, right
end

-- Private: the build -----------------------------------------------------------------------------------------------------

local function build(ctx: MatchHudFormat.Context, view: any): Made
	local layout = MatchIntro.layoutName(ctx.compact())
	local L = CFG.layouts[layout]
	local z = CFG.z
	local root = frame("MatchTopBar", { AnchorPoint = Vector2.new(0.5, 0), ZIndex = z, Parent = ctx.root })
	local scale: UIScale = Create("UIScale", { Parent = root })
	local pose = frame("Pose", { Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = root })
	local count = if view.mode == "tdm" then SLOTS else 1
	local heads, slots = {}, {}
	for index, name in { "HeadsLeft", "HeadsRight" } do
		local width = count * L.head + (count - 1) * L.headGap
		local holder = frame(name, {
			Size = UDim2.fromOffset(width, L.headPadTop + L.head + L.headLip),
			ZIndex = z,
			Parent = pose,
		})
		local list = {}
		for i = 1, count do
			-- Slot1 sits nearest the score (S:956): the left side counts leftwards.
			local x = if index == 1 then (count - i) * (L.head + L.headGap) else (i - 1) * (L.head + L.headGap)
			local slotFrame = frame("Slot" .. i, {
				Position = UDim2.fromOffset(x, L.headPadTop),
				Size = UDim2.fromOffset(L.head, L.head),
				ZIndex = z,
				Parent = holder,
			})
			table.insert(list, { frame = slotFrame, poser = Tweens.poser(slotFrame), key = "", userId = nil })
		end
		table.insert(heads, holder)
		table.insert(slots, list)
	end
	local scores = { scoreBlock("ScoreLeft", L, 1, z), scoreBlock("ScoreRight", L, 0, z) }
	for _, s in scores do
		s.holder.Parent = pose
	end
	local timer, pillFrame, lip, time, goal = timerBlock(L, view, z)
	timer.Parent = pose
	local boosts = frame("Boosts", { AnchorPoint = Vector2.new(0.5, 0), ZIndex = z, Parent = pose })
	return {
		layout = layout,
		L = L,
		root = root,
		scale = scale,
		pose = pose,
		heads = heads,
		slots = slots,
		scores = scores,
		timer = timer,
		pill = pillFrame,
		lip = lip,
		time = time,
		goal = goal,
		boosts = boosts,
		boostKey = "",
		rowSize = Vector2.zero,
		timeWidth = -1,
	}
end

-- Places the five blocks in one row (S:142: align-items flex-start, gap hgap) once the timer's width is known.
local function arrange(made: Made)
	local L = made.L
	local T = L.timer
	local textWidth = math.max(T.minWidth, made.time.Size.X.Offset)
	local pillWidth = T.padLeft + T.clock + T.gap + textWidth + T.padRight
	made.pill.Size = UDim2.fromOffset(pillWidth, T.height)
	local lip = made.lip
	if lip then
		lip.Size = UDim2.fromOffset(pillWidth, T.height)
	end
	local goal = made.goal
	local timerWidth = math.max(pillWidth, if goal then goal.Size.X.Offset else 0)
	made.pill.Position = UDim2.fromOffset((timerWidth - pillWidth) / 2, 0)
	if lip then
		lip.Position = UDim2.fromOffset((timerWidth - pillWidth) / 2, T.lip)
	end
	local timerHeight = T.height
	if goal then
		goal.Position = UDim2.new(0.5, 0, 0, T.height + L.timerGap)
		timerHeight = T.height + L.timerGap + goal.Size.Y.Offset
	end
	made.timer.Size = UDim2.fromOffset(timerWidth, timerHeight)
	local blocks: { Frame } = { made.heads[1], made.scores[1].holder, made.timer, made.scores[2].holder, made.heads[2] }
	local x, height = 0, 0
	for index, block in blocks do
		block.Position = UDim2.fromOffset(x, 0)
		x += block.Size.X.Offset + (if index < #blocks then L.gap else 0)
		height = math.max(height, block.Size.Y.Offset)
	end
	made.rowSize = Vector2.new(x, height)
	made.boosts.Position = UDim2.new(0.5, 0, 0, height + CFG.pill.below)
	made.root.Size = UDim2.fromOffset(x, height + made.boosts.Size.Y.Offset + CFG.pill.below)
end

-- One head slot (S:146-148): the ink lip, the head, the tag over it, the bubble of seconds while they are down.
local function fillSlot(ctx: MatchHudFormat.Context, made: Made, slot: Slot, view: any, player: any?, side: Side)
	local L = made.L
	local z = CFG.z
	local dead = player ~= nil and player.alive == false
	local tag = if player then side.tags[player.userId] else nil
	if tag and not L.youTag and view.mode == "tdm" then
		tag = nil -- the phone has no YOU tag (S:956 youTag); Free for All keeps its places
	end
	local key = if player
		then table.concat({ tostring(player.userId), tostring(dead), tag or "", side.key }, "|")
		else ""
	if key == slot.key then
		return
	end
	slot.key = key
	slot.userId = if player then player.userId else nil
	slot.bubble = nil
	slot.frame:ClearAllChildren()
	slot.frame:SetAttribute("UserId", slot.userId)
	if player == nil then
		return
	end
	local who = MatchKit.who(ctx, view, player.userId)
	local shown = table.clone(who)
	if dead then
		shown.look = { text = who.look.text, top = Palette.MatchTopDead, faceEnd = Palette.MatchTopDead }
	end
	if not L.pictures then
		shown.player = nil
		shown.squishyId = ""
	end
	if L.headLip > 0 then
		local lip = frame("Lip", {
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, L.headLip),
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
			Parent = slot.frame,
		})
		Theme.corner(L.headRadius, lip)
	end
	MatchKit.head({
		name = "Head",
		who = shown,
		size = L.head,
		border = L.headBorder,
		radius = L.headRadius,
		z = z,
		pad = L.headPad,
		inner = if dead then Palette.MatchTopDead else who.look.top,
		ink = if who.you then Palette.Lemon else nil,
		dim = if dead then CFG.deadDim else nil,
		parent = slot.frame,
	})
	if tag then
		local T = L.tag
		local tagFrame = pill(
			"Tag",
			tag,
			T.text,
			T,
			if who.you then Palette.Lemon else who.look.top,
			if who.you then Palette.Lemon else who.look.top,
			z
		)
		tagFrame.AnchorPoint = Vector2.new(0.5, 0)
		-- PR2 grows the tag: it keeps the design's bottom edge.
		tagFrame.Position = UDim2.new(0.5, 0, 0, T.top + T.height - tagFrame.Size.Y.Offset)
		tagFrame.Parent = slot.frame
	end
	local R = L.respawn
	if dead and L.deadMarks and R then
		local bubble = frame("Respawn", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.MatchFeedYouDown, -- S:147 #FF5A6E
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(R.size, R.size),
			ZIndex = z,
			Parent = slot.frame,
		})
		Theme.corner(R.size / 2, bubble)
		MatchKit.inner(Theme.stroke(INK, R.border, bubble))
		local seconds = MatchKit.line("Seconds", "8", R.text, WHITE, R.stroke, z)
		seconds.AnchorPoint = Vector2.new(0.5, 0.5)
		seconds.Position = UDim2.fromScale(0.5, 0.5)
		seconds.Parent = bubble
		slot.bubble = seconds
	end
end

-- Your live power-ups as pills under the bar ([P]); rebuilt when their words change (once a second while one lasts).
local function placeBoosts(made: Made, view: any, now: number, z: number)
	local words = {}
	if view.phase == "Active" then
		for _, left in MatchFormat.powerUpsLeft(view, now) do
			local name = READOUT.powerUpName[left.power]
			if name then
				table.insert(words, Strings.format(READOUT.powerUp, { name = name, seconds = left.seconds }))
			end
		end
	end
	local key = table.concat(words, "|")
	if key == made.boostKey then
		return
	end
	made.boostKey = key
	made.boosts:ClearAllChildren()
	local P = CFG.pill
	local x, height = 0, 0
	for index, text in words do
		local chip = pill("Pill" .. index, text, "Small", P, Palette.StickerGripTop, Palette.StickerGripEnd, z)
		chip.Position = UDim2.fromOffset(x, 0)
		chip.Parent = made.boosts
		x += chip.Size.X.Offset + P.gap
		height = math.max(height, chip.Size.Y.Offset)
	end
	made.boosts.Size = UDim2.fromOffset(math.max(x - P.gap, 0), height)
	arrange(made)
end

-- Public

function TopBar.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local made: Made? = nil
	local shownAt: number? = nil -- os.clock() it came in (nil: hidden)
	local endAt: number? = nil -- os.clock() the Result was first seen
	local fillCurve = Tweens.curve(CFG.fill.curve)

	local function hide()
		shownAt = nil
		ctx.shared.topBarBottom = nil
		local m = made
		if m then
			m.root.Visible = false
		end
		if ctx.toastsBelow then
			ctx.toastsBelow(TOAST_KEY, nil)
		end
	end

	local function drop()
		hide()
		local m = made
		made = nil
		if m then
			m.root:Destroy()
		end
	end

	local piece = {}

	function piece.update(_self: any, view: any, now: number)
		local live = MatchHudFormat.topBarLive(view)
		if not live then
			if shownAt ~= nil and view.matchPhase == "Result" then
				endAt = endAt or os.clock()
				if os.clock() - (endAt :: number) < CFG.leaveDelay then
					return -- S:735: it leaves .32 s into the end
				end
			end
			if shownAt ~= nil then
				hide()
			end
			return
		end
		endAt = nil
		local m = made
		if m == nil or m.layout ~= MatchIntro.layoutName(ctx.compact()) then
			drop()
			m = build(ctx, view)
			made = m
		end
		local current = m :: Made
		local L = current.L
		local clock = os.clock()
		local reduced = ctx.reduced()
		if shownAt == nil then
			shownAt = clock
			current.root.Visible = true
			if ctx.toastsBelow then
				ctx.toastsBelow(TOAST_KEY, current.root)
			end
		end
		-- The clock (S:157); the row is placed again when its width changes.
		local text = MatchHudFormat.topBarTime(view, now) or WORDS.overtime
		if current.time.Text ~= text or current.timeWidth < 0 then
			current.time.Text = text
			local width = math.ceil(Theme.textWidth(text, L.timer.text)) + MEASURE_MARGIN_PX
			current.time.Size = UDim2.fromOffset(width, current.time.Size.Y.Offset)
			if width ~= current.timeWidth then
				current.timeWidth = width
				arrange(current)
			end
		end
		-- The sides: heads, scores, bars.
		local left, right = sides(ctx, view)
		local target = math.max(view.koTarget or 1, 1)
		for index, side in { left, right } do
			for i, slot in current.slots[index] do
				fillSlot(ctx, current, slot, view, side.players[i], side)
				local bubble = slot.bubble
				local player = side.players[i]
				if bubble and player and player.respawnAt then
					bubble.Text = tostring(MatchHudFormat.respawnLeft(player.respawnAt, now))
				end
				local at = slot.shakeAt
				if at then
					local u = (clock - at) / (CFG.shake.ms / 1000)
					if u >= 1 or reduced then
						slot.shakeAt = nil
						slot.poser:set({ x = 0, rot = 0 })
					else
						local steps = CFG.shake.steps
						local f = u * (#steps - 1)
						local i0 = math.floor(f) + 1
						local s = steps[i0] + (steps[math.min(i0 + 1, #steps)] - steps[i0]) * (f - math.floor(f))
						slot.poser:set({ x = s * CFG.shake.px, rot = s * CFG.shake.deg })
					end
				end
			end
			local score = current.scores[index]
			if score.key ~= side.key then
				score.key = side.key
				score.label.TextColor3 = side.scoreColor
				local gradient = score.gradient
				if gradient then
					gradient.Color = ColorSequence.new(side.fill.top, side.fill.faceEnd)
				end
			end
			if score.value ~= side.score then
				if score.value ~= nil and side.score > score.value and not reduced then
					score.bumpAt = clock -- S:696
				end
				score.value = side.score
				score.label.Text = tostring(side.score)
				local share = math.clamp(side.score / target, 0, 1)
				local fillNow = score.from
					+ (score.to - score.from)
						* fillCurve(math.clamp((clock - score.fillAt) / (CFG.fill.ms / 1000), 0, 1))
				score.from, score.to, score.fillAt = fillNow, share, clock
			end
			local bumpAt = score.bumpAt
			if bumpAt then
				local bump = CFG.bump
				local t = clock - bumpAt
				if t >= bump.ms / 1000 then
					score.bumpAt = nil
					score.poser:set({ sx = 1, sy = 1 })
				else
					score.poser:set(
						MatchHudFormat.trackPose(bump.frames, t, bump.ms, nil, bump.curve, reduced, FADE_MS)
					)
				end
			end
			local fill = score.fill
			if fill and L.bar then
				local u = math.clamp((clock - score.fillAt) / (CFG.fill.ms / 1000), 0, 1)
				local share = score.from + (score.to - score.from) * fillCurve(u)
				local inner = L.scoreW - 2 * L.bar.border
				fill.Size = UDim2.fromOffset(math.clamp(math.round(inner * share), 0, inner), fill.Size.Y.Offset)
			end
		end
		placeBoosts(current, view, now, CFG.z)
		-- Placed on the safe area at the stage scale (the intro's), dropping in (S:665).
		local k = MatchIntro.stageScale(ctx.canvas(), L)
		current.scale.Scale = k
		current.root.Position = UDim2.new(0.5, 0, 0, math.round(L.top * k))
		local enter = CFG.enter
		local t = clock - (shownAt :: number)
		if reduced or t >= enter.ms / 1000 then
			current.pose.Position = UDim2.fromOffset(0, 0)
		else
			local frames = {
				{ at = 0, y = -enter.lift * current.rowSize.Y },
				{ at = enter.settleAt, y = enter.settle },
				{ at = 1, y = 0 },
			}
			local pose = Tweens.poseAt(frames, t / (enter.ms / 1000), nil, enter.curve)
			current.pose.Position = UDim2.fromOffset(0, math.round(pose.y or 0))
		end
		ctx.shared.topBarBottom = (L.top + current.rowSize.Y + L.feedGap) * k
	end

	function piece.onMoment(_self: any, moment: any, _view: any)
		local m = made
		if m == nil or moment.kind ~= "ko" or moment.victim == nil or ctx.reduced() then
			return
		end
		for _, list in m.slots do
			for _, slot in list do
				if slot.userId == moment.victim then
					slot.shakeAt = os.clock() -- S:697
				end
			end
		end
	end

	function piece.layout(_self: any)
		local m = made
		if m and m.layout ~= MatchIntro.layoutName(ctx.compact()) then
			drop()
		end
	end

	function piece.destroy(_self: any)
		drop()
	end

	return piece :: any
end

return TopBar
