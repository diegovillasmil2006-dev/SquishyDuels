--!strict
-- KillcamScreen (client only). Killcam step 2 (2026-10-26; owner: "Yes, build step 2 of the killcam like that. You can
-- make and upload the splat sound."; `S:n` = Diego's "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html" line n): the
-- screen pieces over UI/Match/Killcam's replay (S:195-229, S:744-784), which MatchEnd shows while the replay plays.
-- Every number is Config.UI.Match.finish.killcam.screen's (CFG below), in the end screen's stage px (its layouts and
-- fit: the same stage maths as MatchEnd).
-- * In (S:744-754): a white flash; the movie bars slide in from the screen's top and bottom (past the safe area); the
--   edges darken (the radial vignette drawn as two edge gradients); the KILLCAM pill (a blinking red dot, KILLCAM and
--   YOUR VIEW / NAME'S VIEW) drops in at the top left, right of Roblox's own buttons (ctx.coreCorner); FINAL KILL drops
--   in letter by letter, squashing as it lands; the killer's card slides in at the bottom left (its head, its name in
--   its colour, "squished" and the victim's name in theirs, its squishy's picture and name); the card sound.
-- * slow(on) (S:577, 204-206): the SLOW-MO pill at the top right while the replay is slow.
-- * throw() (S:578): the toss sound at each of the killer's throws.
-- * impact(at) (S:760-775): at the squished player's screen point (kept inside the bars and the sides) SQUISHED! slams
--   in letter by letter and fades after its hold; a flash, Diego's burst and three rings (white, the killer's colour,
--   lemon), the screen's jolt (camera shake on, no ReducedMotion); the boom, the splat and the slam 0.14 s later.
-- * finish(clock) (S:776-784): the bars slide out, the rest fades, the letters rise, a last flash; done() goneS later.
-- Under ReducedMotion only the fades play (S:752-753, 765) and there is no burst, rings, jolt or hit flash.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local MatchHudFormat = require(UI.MatchHudFormat)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local SquishyImage = require(UI.Components.SquishyImage)
local Tweens = require(UI.Parent.Anim.Tweens)
local MatchKit = require(script.Parent.MatchKit)

-- Types

export type Info = {
	killer: MatchKit.Who,
	victim: MatchKit.Who,
	reduced: boolean,
	compact: boolean,
}

export type Screen = {
	update: (self: Screen, clock: number) -> (),
	slow: (self: Screen, on: boolean) -> (),
	throw: (self: Screen) -> (),
	impact: (self: Screen, at: Vector3) -> (),
	finish: (self: Screen, clock: number) -> (),
	done: (self: Screen) -> boolean,
	destroy: (self: Screen) -> (),
}

type Posed = { holder: GuiObject, poser: Tweens.Poser, fades: { Tweens.FadeGroup } }

-- Constants

local END = Config.UI.Match.finish
local CFG = END.killcam.screen
local TEXT = Strings.matchHud.killcam
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Colors.inkUI
local BLEED = 80 -- stage px the bars and the flash reach past the safe area (to the screen's edges)
local SMALL = "Small" -- the text kinds drawn scaled to the design's px
local BIG = "Big"
local TITLE = "Reveal"
local STAMP = "IntroTitle"
local SOUND = {
	card = "match.vote.card", -- S:754 snd.card()
	toss = "match.vote.toss", -- S:578 snd.toss()
	boom = "match.found.impact", -- S:769 snd.mfImpact()
	splat = "match.splat", -- S:769 splat(1)
	slam = "match.count.slam", -- S:769 snd.slam()
}
-- The design's easings (cubic-bezier, the whole run's, as WAAPI's `easing`).
local BARS_IN = Tweens.bezier(0.2, 0.9, 0.3, 1) -- S:748
local BARS_OUT = Tweens.bezier(0.5, 0, 0.75, 0) -- S:779
local LETTERS = Tweens.bezier(0.3, 0.7, 0.4, 1) -- S:752
local CARD = Tweens.bezier(0.2, 1, 0.4, 1) -- S:753
local STAMP_IN = Tweens.bezier(0.2, 0.9, 0.3, 1) -- S:765
local EASE_OUT = Tweens.curve("easeOut")

-- Module table

local KillcamScreen = {}

-- Private ---------------------------------------------------------------------------------------------------------

local function frame(name: string, props: { [string]: any }): Frame
	local made: Frame =
		Create("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false })
	for property, value in props do
		if property ~= "Parent" then
			(made :: any)[property] = value
		end
	end
	made.Parent = props.Parent
	return made
end

local function posed(holder: GuiObject): Posed
	return { holder = holder, poser = Tweens.poser(holder), fades = { Tweens.fadeGroup(holder) } }
end

local function pose(p: Posed, alpha: number?, motion: Tweens.Pose)
	if alpha then
		for _, fade in p.fades do
			fade:setAlpha(alpha)
		end
	end
	p.poser:set(motion)
end

-- One line at the design's `px` (a house kind drawn under a UIScale), `stroke` its -webkit-text-stroke px, `em` its
-- letter-spacing; returns its holder and size.
local function text(
	name: string,
	str: string,
	kind: string,
	px: number,
	color: Color3?,
	stroke: number?,
	em: number?,
	z: number
): (Frame, Vector2)
	local k = px / Theme.textSize(kind :: any)
	local inner: GuiObject, size: Vector2
	if em then
		inner, size = MatchKit.spaced("Text", str, kind, color, if stroke then stroke / k else nil, em, z)
	else
		inner, size = MatchKit.line("Text", str, kind, color, if stroke then stroke / k else nil, z)
	end
	local w, h = math.ceil(size.X * k), math.ceil(size.Y * k)
	local holder = frame(name, { Size = UDim2.fromOffset(w, h), ZIndex = z })
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	Create("UIScale", { Scale = k, Parent = inner })
	inner.Parent = holder
	return holder, Vector2.new(w, h)
end

-- A run of letters `gap` px apart, each its own holder anchored at its bottom middle (S:209, 225: transform-origin
-- 50% 100% for the title; the stamp's turn about their centres); returns the row, its size and the letters.
local function letters(
	name: string,
	str: string,
	kind: string,
	px: number,
	stroke: number,
	gap: number,
	colorOf: (char: string) -> Color3,
	z: number
): (Frame, Vector2, { Posed })
	local row = frame(name, { ZIndex = z })
	local out: { Posed } = {}
	local space = Theme.textWidth("x x", kind :: any) - Theme.textWidth("xx", kind :: any)
	local x, h = 0, 0
	for _, code in utf8.codes(str) do
		local char = utf8.char(code)
		if char == " " then
			x += math.ceil(space * px / Theme.textSize(kind :: any)) + gap
			continue
		end
		local holder, size = text("Letter", char, kind, px, colorOf(char), stroke, nil, z)
		local advance = size.X - stroke -- the CSS stroke is drawn over the glyph's edge: no wider letter
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.fromOffset(x + advance / 2, size.Y)
		holder.Parent = row
		table.insert(out, posed(holder))
		x += advance + gap
		h = math.max(h, size.Y)
	end
	local size = Vector2.new(math.max(x - gap, 0), h)
	row.Size = UDim2.fromOffset(size.X, size.Y)
	return row, size, out
end

-- A pill (S:199, 204): fully round, its border inside; the caller sets its face.
local function pill(name: string, height: number, border: number, borderColor: Color3, borderAlpha: number, z: number)
	local holder = frame(name, { BackgroundTransparency = 0, Size = UDim2.fromOffset(0, height), ZIndex = z })
	Theme.corner(height / 2, holder)
	MatchKit.inner(Theme.stroke(borderColor, border, holder, borderAlpha))
	return holder
end

-- The design's `@keyframes`-style run at u (0..1) of an animation `ms` long: its frames' pose (fades only under
-- ReducedMotion: the first and the last alpha).
local function run(frames: { Tweens.Pose }, elapsed: number, ms: number, whole: Tweens.Curve, reduced: boolean): Tweens.Pose
	local u = if ms > 0 then math.clamp(elapsed / (ms / 1000), 0, 1) else 1
	if reduced then
		local fade = math.min(ms, FADE_MS)
		local k = if fade > 0 then math.clamp(elapsed / (fade / 1000), 0, 1) else 1
		local a, b = frames[1].alpha or 1, frames[#frames].alpha or 1
		return { alpha = a + (b - a) * k }
	end
	return Tweens.poseAt(frames, u, nil, whole)
end

-- Public ----------------------------------------------------------------------------------------------------------

function KillcamScreen.new(ctx: MatchHudFormat.Context, info: Info): Screen
	local L = CFG.layouts[if info.compact then "phone" else "desktop"]
	local stageL = END.layouts[if info.compact then "phone" else "desktop"]
	local reduced = info.reduced
	local z = END.z - 1 -- under the end screen's own layer (S:195 z 11, S:233 z 12)
	local t0 = os.clock()
	local killer, victim = info.killer, info.victim

	local layer = frame("SD_KillcamScreen", { Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = ctx.root })
	-- The vignette (S:196): the edges darken, two edge gradients.
	local V = CFG.vignette
	local clear = V.clearShare / 2
	local shade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - V.edgeAlpha),
		NumberSequenceKeypoint.new(0.5 - clear, 1),
		NumberSequenceKeypoint.new(0.5 + clear, 1),
		NumberSequenceKeypoint.new(1, 1 - V.edgeAlpha),
	})
	local vignette = frame("Vignette", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * BLEED, 1, 2 * BLEED),
		ZIndex = z,
		Parent = layer,
	})
	for _, rotation in { 0, 90 } do
		local edge = frame(if rotation == 0 then "Sides" else "TopBottom", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.MatchEndShade,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
			Parent = vignette,
		})
		Create("UIGradient", { Rotation = rotation, Transparency = shade, Parent = edge })
	end
	local vignetteFade = posed(vignette)

	-- The stage: the end screen's px, fit to the safe area.
	local stage = frame("Stage", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = z,
		Parent = layer,
	})
	local scale = Create("UIScale", { Parent = stage }) :: UIScale
	local stageW, stageH = stageL.width, stageL.height
	local function fit()
		local canvas = ctx.canvas()
		local k = if canvas.X > 0 and canvas.Y > 0
			then math.max(0.05, math.min(canvas.X / stageL.width, canvas.Y / stageL.height))
			else 1
		stageW = math.max(canvas.X / k, stageL.width)
		stageH = math.max(canvas.Y / k, stageL.height)
		stage.Size = UDim2.fromOffset(math.round(stageW), math.round(stageH))
		scale.Scale = k
	end
	fit()

	-- The bars (S:197-198), reaching past the safe area.
	local bars: { { frame: Frame, top: boolean } } = {}
	for _, top in { true, false } do
		table.insert(bars, {
			top = top,
			frame = frame(if top then "BarTop" else "BarBottom", {
				BackgroundTransparency = 0,
				BackgroundColor3 = Palette.MatchEndShade,
				AnchorPoint = Vector2.new(0, if top then 1 else 0),
				Position = UDim2.new(0, -BLEED, if top then 0 else 1, 0),
				Size = UDim2.new(1, 2 * BLEED, 0, L.bar + BLEED),
				ZIndex = z + 1,
				Parent = stage,
			}),
		})
	end

	-- The KILLCAM pill (S:199-203), right of Roblox's own buttons.
	local P = CFG.pill
	local corner = if ctx.coreCorner then ctx.coreCorner().left / math.max(scale.Scale, 0.05) else 0
	local pillLeft = math.max(L.pillL, if corner > 0 then corner + P.gap else 0)
	local kcPill = pill("KillcamPill", L.pillH, P.border, Palette.Frosting, 0.65, z + 2)
	kcPill.BackgroundColor3 = Palette.Frosting
	kcPill.BackgroundTransparency = 0.92
	kcPill.Position = UDim2.fromOffset(pillLeft, L.pillT)
	kcPill.Parent = stage
	local dot = frame("Dot", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.DuelSquished,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, P.padX, 0.5, 0),
		Size = UDim2.fromOffset(L.dot, L.dot),
		ZIndex = z + 3,
		Parent = kcPill,
	})
	Theme.corner(L.dot / 2, dot)
	local word, wordSize = text("Word", TEXT.pill, SMALL, L.pillPx, Palette.Frosting, nil, 0.14, z + 3)
	local pov = if killer.you
		then TEXT.yourView
		else Strings.format(TEXT.view, { name = string.upper(killer.name) })
	local povLabel, povSize = text("View", pov, SMALL, L.pillPx, Palette.MatchEndMuted, nil, 0.06, z + 3)
	local px = P.padX + L.dot + P.gap
	for _, part in { { word, wordSize }, { povLabel, povSize } } do
		local object, size = part[1] :: Frame, part[2] :: Vector2
		object.AnchorPoint = Vector2.new(0, 0.5)
		object.Position = UDim2.new(0, px, 0.5, 0)
		object.Parent = kcPill
		px += size.X + P.gap
	end
	kcPill.Size = UDim2.fromOffset(px - P.gap + P.padX, L.pillH)
	local pillPosed = posed(kcPill)

	-- The SLOW-MO pill (S:204-206).
	local slowPill = pill("SlowPill", L.pillH, P.border, INK, 0, z + 2)
	MatchKit.gradient(slowPill, { text = INK, top = Palette.MatchFfaCyanTop, faceEnd = Palette.StickerFxCyan })
	slowPill.AnchorPoint = Vector2.new(1, 0)
	slowPill.Position = UDim2.new(1, -L.right, 0, L.pillT)
	slowPill.Parent = stage
	local slowWord, slowSize = text("Word", TEXT.slow, SMALL, L.pillPx, INK, nil, 0.12, z + 3)
	slowWord.AnchorPoint = Vector2.new(0.5, 0.5)
	slowWord.Position = UDim2.fromScale(0.5, 0.5)
	slowWord.Parent = slowPill
	slowPill.Size = UDim2.fromOffset(slowSize.X + 2 * P.padX, L.pillH)
	local slowPosed = posed(slowPill)
	local slowAt: number? = nil

	-- FINAL KILL (S:207-211).
	local titleRow, _, titleLetters = letters(
		"Title",
		TEXT.title,
		TITLE,
		L.title,
		L.titleStroke,
		L.letterGap,
		function(): Color3
			return Palette.Lemon
		end,
		z + 2
	)
	titleRow.AnchorPoint = Vector2.new(0.5, 0)
	titleRow.Position = UDim2.new(0.5, 0, 0, L.titleT)
	titleRow.Parent = stage

	-- The killer's card (S:212-222).
	local card = frame("Card", { ZIndex = z + 2 })
	local lip = frame("Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		Position = UDim2.fromOffset(0, L.cardBorder),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 2,
		Parent = card,
	})
	Theme.corner(L.cardRadius, lip)
	local face = frame("Face", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.MatchIntroCard,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 3,
		Parent = card,
	})
	Theme.corner(L.cardRadius, face)
	MatchKit.inner(Theme.stroke(INK, L.cardBorder, face))
	local head = MatchKit.head({
		name = "Head",
		who = killer,
		size = L.head,
		border = L.cardBorder,
		radius = L.headRadius,
		z = z + 4,
	})
	local nameColor = if killer.you then Palette.Lemon else killer.look.text
	local name, nameSize = text("Name", killer.name, BIG, L.name, nameColor, L.nameStroke, nil, z + 4)
	local sub = frame("Sub", { ZIndex = z + 4 })
	local subWord, subWordSize = text("Word", TEXT.squished .. " ", SMALL, L.sub, Palette.MatchEndMuted, nil, nil, z + 4)
	subWord.Parent = sub
	local victimColor = if victim.you then Palette.Lemon else victim.look.text
	local victimName, victimSize = text("Victim", victim.name, SMALL, L.sub, victimColor, nil, nil, z + 4)
	victimName.Position = UDim2.fromOffset(subWordSize.X, 0)
	victimName.Parent = sub
	local subW, subH = subWordSize.X + victimSize.X, math.max(subWordSize.Y, victimSize.Y)
	sub.Size = UDim2.fromOffset(subW, subH)
	local column = frame("Column", { ZIndex = z + 4 })
	name.Parent = column
	sub.Position = UDim2.fromOffset(0, nameSize.Y + L.textGap)
	sub.Parent = column
	local columnW, columnH = math.max(nameSize.X, subW), nameSize.Y + L.textGap + subH
	column.Size = UDim2.fromOffset(columnW, columnH)
	-- The squishy's pill (S:218-221).
	local def = Catalog.get(killer.squishyId)
	local toyName = if def then Strings.resolve(def.nameKey) or "" else ""
	local toyPill = frame("Toy", {
		BackgroundTransparency = 0.9,
		BackgroundColor3 = Palette.Frosting,
		ZIndex = z + 4,
	})
	Theme.corner(L.toy / 2, toyPill)
	local toyW = 4
	if def then
		local picture = SquishyImage.new(killer.squishyId, { name = "Picture", size = L.toy })
		picture.root.Position = UDim2.fromOffset(4, 0)
		picture.root.Parent = toyPill
		toyW += L.toy + 6
	end
	local toyWord, toyWordSize = text("Name", toyName, SMALL, L.sub, Palette.Frosting, nil, nil, z + 5)
	toyWord.AnchorPoint = Vector2.new(0, 0.5)
	toyWord.Position = UDim2.new(0, toyW, 0.5, 0)
	toyWord.Parent = toyPill
	toyW += toyWordSize.X + 10
	toyPill.Size = UDim2.fromOffset(toyW, L.toy)
	-- Lay the card out: the head, the column, the pill, each centred on the card's middle.
	local cx = L.cardPad
	local cardH = math.max(L.head, columnH, L.toy) + 2 * L.cardPad
	for _, part in { { head, L.head }, { column, columnW }, { toyPill, toyW } } do
		local object, w = part[1] :: GuiObject, part[2] :: number
		object.AnchorPoint = Vector2.new(0, 0.5)
		object.Position = UDim2.new(0, cx, 0.5, 0)
		object.Parent = face
		cx += w + L.cardGap
	end
	local cardW = cx - L.cardGap + L.cardPadR
	card.Size = UDim2.fromOffset(cardW, cardH)
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.new(0, L.cardL, 1, -L.cardB - L.cardBorder)
	card.Parent = stage
	local cardPosed = posed(card)

	-- SQUISHED! (S:223-227), placed at the squish.
	local stampRow, _, stampLetters = letters(
		"Stamp",
		TEXT.stamp,
		STAMP,
		L.stampPx,
		L.stampStroke,
		L.letterGap,
		function(char: string): Color3
			return if char == "!" then Palette.MatchTeamRedScore else WHITE
		end,
		z + 2
	)
	stampRow.AnchorPoint = Vector2.new(0.5, 0.5)
	stampRow.Rotation = CFG.stamp.rot
	stampRow.Visible = false
	stampRow.Parent = stage
	local stampPosed = posed(stampRow)
	local stampAt: number? = nil

	-- The flash (S:227), over everything of this layer.
	local flash = frame("Flash", {
		BackgroundTransparency = 1,
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * BLEED, 1, 2 * BLEED),
		ZIndex = z + 10,
		Parent = layer,
	})
	local hitFlashAt: number? = nil
	local outAt: number? = nil
	local finished = false

	ctx.play(SOUND.card)

	local screen = {}

	local function flashOf(elapsed: number, ms: number, peak: number, at: number): number
		local u = elapsed / (ms / 1000)
		if u < 0 or u >= 1 then
			return 0
		end
		return if u < at then peak * u / at else peak * (1 - (u - at) / (1 - at))
	end

	function screen.update(_self: any, clock: number)
		if finished then
			return
		end
		fit()
		local t = clock - t0
		local out = outAt
		local ot = if out then clock - out else -1
		local outK = if out then math.clamp(ot / (CFG.outMs / 1000), 0, 1) else 0
		-- The flashes: in, the squish's, out.
		local f = 0
		local Fi = CFG.flashIn
		local u = t / (Fi.ms / 1000)
		if u < 1 then
			f = Fi.peak * (1 - EASE_OUT(math.clamp(u, 0, 1)))
		end
		local hit = hitFlashAt
		if hit and not reduced then
			local Fh = CFG.flashHit
			f = math.max(f, flashOf(clock - hit - Fh.delayMs / 1000, Fh.ms, Fh.peak, Fh.at))
		end
		if out then
			local Fo = CFG.flashOut
			f = math.max(f, flashOf(ot, Fo.ms, Fo.peak, Fo.at))
		end
		flash.BackgroundTransparency = 1 - f
		-- The bars.
		local B = CFG.bars
		for _, bar in bars do
			local top = bar.top
			local k = if out
				then 1 - BARS_OUT(math.clamp(ot / (B.outMs / 1000), 0, 1))
				else BARS_IN(math.clamp(t / (B.inMs / 1000), 0, 1))
			local travel = L.bar * k -- in: its inner edge L.bar from the stage's edge (the bleed stays past it)
			bar.frame.Position = UDim2.new(0, -BLEED, if top then 0 else 1, math.round(if top then travel else -travel))
		end
		-- The vignette.
		local va = math.clamp(t / (V.ms / 1000), 0, 1) * (1 - outK)
		pose(vignetteFade, va, {})
		-- The KILLCAM pill and its blinking dot (kcBlink steps(2): 1, then 0.2).
		local Pp = run({ { at = 0, alpha = 0, y = -P.rise }, { at = 1, alpha = 1, y = 0 } }, t - P.delayMs / 1000, P.ms, EASE_OUT, reduced)
		pose(pillPosed, (Pp.alpha or 1) * (1 - outK), { y = Pp.y or 0 })
		dot.BackgroundTransparency = if (t % P.blinkS) < P.blinkS / 2 then 0 else 0.8
		-- SLOW-MO.
		local sa = slowAt
		pose(slowPosed, if sa then math.clamp((clock - sa) / (CFG.slow.ms / 1000), 0, 1) * (1 - outK) else 0, {})
		-- FINAL KILL.
		local Lt = CFG.letters
		for i, letter in titleLetters do
			local lt = t - (Lt.delayMs + (i - 1) * Lt.stepMs) / 1000
			local p = run({
				{ at = 0, alpha = 0, y = -Lt.drop, sx = Lt.sx, sy = Lt.sy },
				{ at = 0.6, alpha = 1, y = 0, sx = Lt.landSx, sy = Lt.landSy },
				{ at = 1, alpha = 1, y = 0, sx = 1, sy = 1 },
			}, lt, Lt.ms, LETTERS, reduced)
			local alpha = (p.alpha or 1) * (1 - outK)
			local y = (p.y or 0) - CFG.outRise * outK
			pose(letter, alpha, { y = y, sx = p.sx or 1, sy = p.sy or 1 })
		end
		-- The card.
		local C = CFG.card
		local cp = run({
			{ at = 0, alpha = 0, x = -C.slide, scale = C.from },
			{ at = 0.65, alpha = 1, x = C.over, scale = C.peak },
			{ at = 1, alpha = 1, x = 0, scale = 1 },
		}, t - C.delayMs / 1000, C.ms, CARD, reduced)
		pose(cardPosed, (cp.alpha or 1) * (1 - outK), { x = cp.x or 0, scale = cp.scale or 1 })
		-- SQUISHED!
		local st = stampAt
		if st then
			local S = CFG.stamp
			local hold = (clock - st) / (S.holdMs / 1000)
			local holdAlpha = if hold < 0.75 then 1 elseif hold < 1 then 1 - (hold - 0.75) / 0.25 else 0
			pose(stampPosed, holdAlpha * (1 - outK), {})
			for i, letter in stampLetters do
				local lt = clock - st - (i - 1) * S.stepMs / 1000
				local p = run({
					{ at = 0, alpha = 0, scale = S.from, rot = S.fromRot },
					{ at = 0.55, alpha = 1, scale = S.mid, rot = 0 },
					{ at = 1, alpha = 1, scale = 1, rot = 0 },
				}, lt, S.ms, STAMP_IN, reduced)
				pose(letter, p.alpha or 1, { scale = p.scale or 1, rot = p.rot or 0 })
			end
		end
		if out and ot >= CFG.goneS then
			finished = true
			layer.Visible = false
		end
	end

	function screen.slow(_self: any, on: boolean)
		if on and slowAt == nil then
			slowAt = os.clock()
		elseif not on then
			slowAt = nil -- S:204: it goes at once
		end
	end

	function screen.throw(_self: any)
		ctx.play(SOUND.toss)
	end

	function screen.impact(_self: any, at: Vector3)
		if stampAt ~= nil or outAt ~= nil then
			return
		end
		local camera = Workspace.CurrentCamera
		local point = camera:WorldToScreenPoint(at)
		local origin, abs = stage.AbsolutePosition, stage.AbsoluteSize
		local k = if abs.X > 0 then stageW / abs.X else 1
		local compact = info.compact
		local pad = if compact then CFG.stampPad.phone else CFG.stampPad.desktop
		local up = if compact then CFG.stampUp.phone else CFG.stampUp.desktop
		local x = math.clamp((point.X - origin.X) * k, pad, math.max(pad, stageW - pad))
		local yLow = L.bar + L.stampPx
		local y = math.clamp((point.Y - origin.Y) * k - up, yLow, math.max(yLow, stageH - L.bar - L.stampPx))
		stampRow.Position = UDim2.fromOffset(math.round(x), math.round(y))
		stampRow.Visible = true
		stampAt = os.clock()
		hitFlashAt = stampAt
		ctx.play(SOUND.boom)
		ctx.play(SOUND.splat)
		task.delay(CFG.slamAtS, function()
			if not finished then
				ctx.play(SOUND.slam)
			end
		end)
		if reduced then
			return
		end
		local s = scale.Scale
		local Bu = CFG.burst
		UiFx.sparks(stampRow, { n = Bu.n, spread = Bu.spread * s, size = Bu.size * s, up = Bu.up * s, ms = Bu.ms })
		local colors = { WHITE, killer.look.mid or killer.look.faceEnd, Palette.Lemon }
		for i, size in CFG.rings.sizes do
			task.delay((i - 1) * CFG.rings.stepMs / 1000, function()
				if not finished then
					UiFx.ring(stampRow, colors[i], size * s)
				end
			end)
		end
		UiFx.jolt(stage, CFG.jolt * s)
	end

	function screen.finish(_self: any, clock: number)
		if outAt == nil then
			outAt = clock
		end
	end

	function screen.done(_self: any): boolean
		return finished
	end

	function screen.destroy(_self: any)
		finished = true
		layer:Destroy()
	end

	screen.update(screen, t0)
	return screen :: any
end

return KillcamScreen
