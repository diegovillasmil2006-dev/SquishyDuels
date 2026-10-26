--!strict
-- MatchIntro (client only). Round 1 of the match screens (2026-10-26; owner: "Yes, build the rules step and round 1
-- like that. You can make and upload the pictures and sounds."; `S:n` = Diego's "Squishy Duels LOADING SCREEN Y MATCH
-- HUD.dc.html" line n, `T:n` = its uploads/tdm-hud.js, ALL HUDS zip page 3): a MatchHudController piece ("intro") for
-- Team and Free for All (owner: the same screens; Free for All has no team colours, heads or VS). Every number is
-- Config.UI.Match.intro's.
-- * The Loading arena cover (S:434-440) while the match waits for you to reach the map (your row's `arrived`): the
--   duel emblem bobbing over the lilac radial, "Loading arena" and three pulsing dots; it fades as the intro starts.
-- * The intro (S:335-425; the timeline S:611-637, T:132-143) from your arrival while the match waits (Waiting): the
--   dim and the corner glows, the map's name slammed in, the mode and goal lines, the team heads, one card per player
--   sliding in from its side (your team on the left, you first: yellow border and YOU; Free for All: you first, then
--   the others, half a side, in their slot colours), the duel emblem, the VS diamond spinning in, the LOADING PLAYERS
--   bar. A player still on the way has a shimmering "Loading…" card until the server says they arrived; then their
--   head pops in. The crowd murmur loops under it; the arena behind is blurred (a client BlurEffect in Lighting).
-- * The exit (S:639-658) when the server starts the Countdown (everyone in and Config.Match.introMinSeconds of
--   intro): the cards slide out, the lines drop, the two wipes meet in the middle and pull apart, the blur goes.
-- * The 3-2-1 (S:126-133, S:660-671): a beat every count.beatS, the last at the countdown's end (server time), each
--   with the slam, the urgent tick and a white ring; SQUISH! / GO GO GO at the end with the impact, the sparks, three
--   rings and a jolt. MatchController keeps the duel HUD's own countdown off meanwhile.
-- A match this client meets late shows only what is left (Countdown: the beats; Active: nothing). Under ReducedMotion
-- only the fades play (MatchHudFormat.trackPose), the wipes fade in and out, the loops rest and UiFx skips its
-- effects. Each layer (the intro, the cover, the count) is a stage of the design's px under a UIScale (stageScale)
-- fitting the safe area and stretched along the other side; the compact class takes the phone layout.
-- Pure (unit-tested): layoutName(compact), stageScale(canvas, layout), titleLines(mapName), columns(view),
-- beat(view, now), lines(view).

-- Services

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
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
local UiIdle = require(UI.Parent.Anim.UiIdle)
local MatchKit = require(script.Parent.MatchKit)

-- Types

export type Columns = {
	left: { any }, -- MatchPlayer rows, top to bottom
	right: { any },
	leftTeam: string?, -- Team: the left column's team (yours)
	rightTeam: string?,
}

type Card = {
	userId: number,
	side: number, -- -1 the left column, 1 the right
	row: number, -- 0-based, top to bottom
	order: number, -- the whoosh's semitone (S:629: row x 2, + 1 on the right)
	holder: CanvasGroup,
	poser: Tweens.Poser,
	head: GuiObject, -- the arrived picture (pops in)
	headPoser: Tweens.Poser,
	loading: { GuiObject }, -- shown while the player is on the way
	arrivedOnly: { GuiObject }, -- shown once they are in
	shine: Frame?,
	shinePoser: Tweens.Poser?,
}

-- An element of the timeline: its motion through a poser, its fade through fade groups (a frame's poser fades only
-- its own background; the groups take everything inside, as MatchFoundShow's tracks do).
type Posed = { holder: GuiObject, poser: Tweens.Poser, fades: { Tweens.FadeGroup } }

type Made = {
	layoutName: string,
	layout: any,
	covers: { Frame }, -- the whole-screen layers: the dim, the wipes, the cover's background
	dim: Frame,
	wipes: { Frame },
	bootBg: Frame,
	stages: { Frame }, -- intro, cover, count
	scales: { UIScale },
	intro: Frame,
	glows: { ImageLabel },
	cards: { Card },
	title: Posed,
	mode: Posed,
	logo: Posed,
	vs: Posed?,
	vsText: Posed?,
	headers: { { text: Posed, line: Posed, dots: { GuiObject } } },
	bar: Posed,
	barText: Frame,
	barFill: Frame,
	barInner: number,
	barShown: number, -- the fill's share now (it eases to the arrived share)
	barCount: number, -- the arrived count its text shows
	boot: Frame,
	count: Frame,
	countCentre: Frame,
	countLabel: Posed,
	countLabelText: Frame,
	countNumber: Posed,
	countFaces: { [number]: Frame }, -- 3, 2, 1, 0 (SQUISH!)
	rays: ImageLabel?,
	loops: { UiIdle.Handle },
}

-- Constants

local CFG = Config.UI.Match.intro
local COUNT = CFG.count
local EXIT = CFG.exit
local TEXT = Strings.matchHud.intro
local TEAM_NAMES = Config.Match.teamNames
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local MAX_ROWS = 6 -- S:620: six cards a side
local MEASURE_MARGIN_PX = 2 -- TextService rounding (MatchKit's)
local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Colors.inkUI
local BLUR_NAME = "SD_MatchIntroBlur"
local GLOW_KEY = "img.intro.glow"
local RAYS_KEY = "img.intro.countRays"
local EMBLEM_KEY = "img.nav.duel" -- the duel emblem (S:388, S:436)
local GRIP_KEY = "img.icon.grip"
local PATTERN_KEY = "img.intro.pattern."
local HEAD_URL = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150" -- MatchKit's
local SOUND = {
	slam = "match.intro.slam",
	whoosh = "match.intro.whoosh",
	vs = "match.intro.vs",
	pop = "match.intro.cardPop",
	murmur = "match.intro.murmur",
	tick = "match.vote.tickUrgent", -- S:666 clockTick(true)
	countSlam = "match.count.slam",
	go = "match.found.impact", -- S:668 mfImpact
}
local EXIT_WHOOSH = 11 -- S:651 introWhoosh(11)

-- Module table

local MatchIntro = {}

-- Public: pure --------------------------------------------------------------------------------------------------------

function MatchIntro.layoutName(compact: boolean): string
	return if compact then "phone" else "desktop"
end

-- The stage's scale on a safe area of `canvas` base px: the whole layout fits (the smaller share).
function MatchIntro.stageScale(canvas: Vector2, layout: any): number
	if canvas.X <= 0 or canvas.Y <= 0 then
		return 1
	end
	return math.max(0.05, math.min(canvas.X / layout.width, canvas.Y / layout.height))
end

-- The map's name in capitals: two lines split at the space nearest the middle (S:384 SWEETSHOP / STADIUM), else one.
function MatchIntro.titleLines(mapName: string): { string }
	local name = string.upper(mapName)
	local middle = #name / 2
	local best: number? = nil
	for at in string.gmatch(name, "() ") do
		if best == nil or math.abs(at - middle) < math.abs(best - middle) then
			best = at
		end
	end
	if best == nil then
		return { name }
	end
	return { string.sub(name, 1, best - 1), string.sub(name, best + 1) }
end

-- The cards' columns (T:10: your team is always the left column, you first). Free for All: you first, then the others
-- in view order, the first half on the left. At most six a side.
function MatchIntro.columns(view: any): Columns
	local mine: any = nil
	for _, player in view.players do
		if player.userId == view.you.userId then
			mine = player
			break
		end
	end
	local left, right = {}, {}
	if mine then
		table.insert(left, mine)
	end
	if view.mode == "tdm" then
		local leftTeam = if mine and mine.team then mine.team else TEAM_NAMES[1]
		local rightTeam = if leftTeam == TEAM_NAMES[1] then TEAM_NAMES[2] else TEAM_NAMES[1]
		for _, player in view.players do
			if player ~= mine then
				table.insert(if player.team == leftTeam then left else right, player)
			end
		end
		while #left > MAX_ROWS do
			table.remove(left)
		end
		while #right > MAX_ROWS do
			table.remove(right)
		end
		return { left = left, right = right, leftTeam = leftTeam, rightTeam = rightTeam }
	end
	local others = {}
	for _, player in view.players do
		if player ~= mine then
			table.insert(others, player)
		end
	end
	local half = math.min(math.ceil((#others + #left) / 2), MAX_ROWS)
	for _, player in others do
		if #left < half then
			table.insert(left, player)
		elseif #right < MAX_ROWS then
			table.insert(right, player)
		end
	end
	return { left = left, right = right }
end

-- The countdown's beat at server time `now`: 3, 2, 1 (count.beatS apart, the last beatS before the end), 0 = SQUISH!
-- (the end reached); nil before the first beat or outside the Countdown.
function MatchIntro.beat(view: any, now: number): number?
	if view.matchPhase ~= "Countdown" then
		return nil
	end
	local endsAt = view.phaseEndsAt
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return nil
	end
	local left = endsAt - now
	if left <= 0 then
		return 0
	end
	-- Server times are ~1.8e9 s: their sums carry ~1e-7 s of rounding, so a beat's own moment counts as that beat.
	local n = math.ceil(left / COUNT.beatS - 1e-4)
	return if n <= 3 then n else nil
end

-- The intro's mode and goal lines (S:986): "TEAM DEATHMATCH · 6v6", "FIRST TO 30 SQUISHES · 3:00".
function MatchIntro.lines(view: any): (string, string)
	local mode = view.mode
	local rules = Config.Match.Modes[mode]
	local players = if rules then rules.maxPlayers else #view.players
	local size =
		Strings.format(TEXT.size[mode] or TEXT.size.ffa, { n = if mode == "tdm" then players // 2 else players })
	local name = string.upper(Strings.match.mode[mode] or "")
	local seconds = if rules then rules.matchSeconds else 0
	local clock = string.format("%d:%02d", seconds // 60, seconds % 60)
	local target = view.koTarget or (if rules then rules.koTarget else 0)
	return Strings.format(TEXT.mode, { mode = name, size = size }),
		Strings.format(TEXT.goal, { target = target, clock = clock })
end

-- Private: builders ---------------------------------------------------------------------------------------------------

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

local function picture(name: string, key: string, props: { [string]: any }): ImageLabel
	local made: ImageLabel = Create("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Image = AssetTable.image(key) or "",
		ScaleType = Enum.ScaleType.Stretch,
		Active = false,
	})
	for property, value in props do
		if property ~= "Parent" then
			(made :: any)[property] = value
		end
	end
	made.Parent = props.Parent
	return made
end

local function ink(object: GuiObject, px: number): UIStroke
	return Create("UIStroke", {
		Name = "Outline",
		Color = INK,
		Thickness = px,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = object,
	})
end

-- One line of `kind` (sized from TextService: AutomaticSize is wrong under a UIScale), centred in its box; `stroke` =
-- the design's -webkit-text-stroke (the outline is half of it; nil: the house's thinnest on light text, none on dark).
local function text(
	name: string,
	str: string,
	kind: string,
	color: Color3?,
	stroke: number?,
	z: number
): (TextLabel, Vector2)
	local size = Vector2.new(
		math.ceil(Theme.textWidth(str, kind :: any)) + MEASURE_MARGIN_PX + (stroke or 0),
		math.ceil(Theme.lineHeight(kind :: any))
	)
	local label = Theme.label({
		Name = name,
		Text = str,
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		Size = UDim2.fromOffset(size.X, size.Y),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Active = false,
	}, kind :: any, nil, color)
	if stroke then
		local outline = label:FindFirstChild("SD_Outline")
		if outline and outline:IsA("UIStroke") then
			outline.Thickness = stroke / 2
		else
			Theme.noOutline(label)
			ink(label, stroke / 2)
		end
	end
	return label, size
end

-- A letter-spaced line (CSS letter-spacing; Roblox has none): a label per character, `em` apart, in a holder as wide
-- as the line (the design's padding-left balances the last letter's spacing, so the letters sit centred).
local function spaced(
	name: string,
	str: string,
	kind: string,
	color: Color3?,
	stroke: number?,
	em: number,
	z: number
): (Frame, Vector2)
	local gap = em * Theme.textSize(kind)
	local height = math.ceil(Theme.lineHeight(kind :: any))
	local holder = frame(name, { ZIndex = z })
	local x = 0
	for _, code in utf8.codes(str) do
		local char = utf8.char(code)
		local width = Theme.textWidth(char, kind :: any)
		if char ~= " " then
			local label = text("Char", char, kind, color, stroke, z)
			label.AnchorPoint = Vector2.new(0.5, 0)
			label.Position = UDim2.fromOffset(math.round(x + width / 2), 0)
			label.Parent = holder
		end
		x += width + gap
	end
	local size = Vector2.new(math.ceil(math.max(x - gap, 0)), height)
	holder.Size = UDim2.fromOffset(size.X, size.Y)
	return holder, size
end

-- The design's stacked big text (S:385-386, S:131-132, S:437): an ink copy `shadow` px lower and one in place, both
-- with the ink outline (stroke / 2), under the face: `colors` top to bottom with no outline, else white with it.
local function stacked(
	name: string,
	str: string,
	kind: string,
	stroke: number,
	shadow: number,
	colors: ColorSequence?,
	z: number
): (Frame, Vector2)
	local size = Vector2.new(
		math.ceil(Theme.textWidth(str, kind :: any)) + MEASURE_MARGIN_PX + stroke,
		math.ceil(Theme.lineHeight(kind :: any))
	)
	local holder = frame(name, { Size = UDim2.fromOffset(size.X, size.Y), ZIndex = z })
	local function layer(layerName: string, y: number, color: Color3, outline: boolean, layerZ: number): TextLabel
		local label = Theme.label({
			Name = layerName,
			Text = str,
			AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, y),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = layerZ,
			Active = false,
			Parent = holder,
		}, kind :: any, nil, color)
		Theme.noOutline(label)
		if outline then
			ink(label, stroke / 2)
		end
		return label
	end
	if shadow > 0 then
		layer("Shadow", shadow, INK, true, z)
	end
	if colors then
		layer("Back", 0, INK, true, z + 1)
		Create("UIGradient", { Rotation = 90, Color = colors, Parent = layer("Face", 0, WHITE, false, z + 2) })
	else
		layer("Face", 0, WHITE, true, z + 2)
	end
	return holder, size
end

local function posed(holder: GuiObject): Posed
	return { holder = holder, poser = Tweens.poser(holder), fades = { Tweens.fadeGroup(holder) } }
end

local function gradient(object: GuiObject, keys: { ColorSequenceKeypoint }, rotation: number?): UIGradient
	object.BackgroundColor3 = WHITE
	return Create("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(keys), Parent = object })
end

local function key(at: number, color: Color3): ColorSequenceKeypoint
	return ColorSequenceKeypoint.new(at, color)
end

local function inner(stroke: UIStroke)
	MatchKit.inner(stroke)
end

-- A player's picture filling `parent`: the avatar head for a real player, else their squishy (MatchKit.head's rule).
local function headPicture(who: MatchKit.Who, size: number, parent: GuiObject, z: number): GuiObject
	if who.player then
		return Create("ImageLabel", {
			Name = "Head",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Image = string.format(HEAD_URL, who.userId),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = z,
			Active = false,
			Parent = parent,
		})
	end
	local holder = frame("Head", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = parent,
	})
	if who.squishyId ~= "" then
		local image = SquishyImage.new(who.squishyId, { name = "Toy", size = size })
		image.root.AnchorPoint = Vector2.new(0.5, 0.5)
		image.root.Position = UDim2.fromScale(0.5, 0.5)
		image.root.Parent = holder
	end
	return holder
end

local function toy(squishyId: string, size: number, z: number): Frame
	local image = SquishyImage.new(squishyId, { name = "Toy", size = size })
	image.root.ZIndex = z
	return image.root
end

local function squishyName(squishyId: string): string
	local def = Catalog.get(squishyId)
	return if def then Strings.resolve(def.nameKey) or "" else ""
end

-- S:351 tdShim: a soft white band (`share` of the box) crossing a clipping box `width` px wide on a loop
-- (translateX -120% -> 220% of its own width, linear); at rest out of sight.
local function shimmer(parent: GuiObject, width: number, alpha: number, z: number, loops: { UiIdle.Handle })
	local S = CFG.loadingShimmer
	local band = math.round(width * S.share)
	local strip = frame("Shimmer", {
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		Size = UDim2.new(0, band, 1, 0),
		ZIndex = z,
		Parent = parent,
	})
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 1 - alpha),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = strip,
	})
	local handle = UiIdle.addFrames(strip, {
		{ at = 0, x = -1.2 * band },
		{ at = 1, x = 2.2 * band },
	}, { periodS = S.periodS, curve = "linear" })
	if handle then
		table.insert(loops, handle)
	end
end

-- The grip chip (S:357, S:376): mint, ink border inside, the Grip icon and the level.
local function gripChip(
	level: number,
	spec: any,
	kind: string,
	color: Color3?,
	stroke: number?,
	z: number
): (Frame, number)
	local number, numberSize = text("Level", tostring(level), kind, color, stroke, z + 1)
	local width = spec.border + spec.padLeft + spec.icon + spec.gap + numberSize.X + spec.padRight + spec.border
	local chip = frame("Grip", { Size = UDim2.fromOffset(width, spec.height + (spec.lip or 0)), ZIndex = z })
	if spec.lip then
		local lip = frame("Lip", {
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, spec.lip),
			Size = UDim2.fromOffset(width, spec.height),
			ZIndex = z,
			Parent = chip,
		})
		Theme.corner(spec.radius, lip)
	end
	local face = frame(
		"Face",
		{ BackgroundTransparency = 0, Size = UDim2.fromOffset(width, spec.height), ZIndex = z, Parent = chip }
	)
	Theme.corner(spec.radius, face)
	gradient(face, { key(0, Palette.StickerGripTop), key(1, Palette.StickerGripEnd) })
	inner(Theme.stroke(INK, spec.border, face))
	picture("Icon", GRIP_KEY, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, spec.border + spec.padLeft, 0.5, 0),
		Size = UDim2.fromOffset(spec.icon, spec.icon),
		ZIndex = z + 1,
		Parent = face,
	})
	number.AnchorPoint = Vector2.new(0, 0.5)
	number.Position = UDim2.new(0, spec.border + spec.padLeft + spec.icon + spec.gap, 0.5, 0)
	number.Parent = face
	return chip, width
end

-- The YOU tag (S:362, S:373): yellow, ink border inside, ink text.
local function youTag(spec: any, kind: string, z: number): (Frame, number)
	local label, labelSize = text("Text", TEXT.you, kind, INK, nil, z + 1)
	local width = labelSize.X + 2 * (spec.padX + spec.border)
	local tag = frame("You", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Lemon,
		Size = UDim2.fromOffset(width, spec.height),
		ZIndex = z,
	})
	Theme.corner(spec.radius, tag)
	inner(Theme.stroke(INK, spec.border, tag))
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Parent = tag
	return tag, width
end

-- The squishy's banner tile (T:76-91: ScaleType.Tile) filling `parent`.
local function pattern(squishyId: string, tile: number, alpha: number, z: number, parent: GuiObject): ImageLabel?
	local image = AssetTable.image(PATTERN_KEY .. squishyId)
	if image == nil then
		return nil
	end
	return Create("ImageLabel", {
		Name = "Pattern",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = image,
		ImageTransparency = 1 - alpha,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile, tile),
		ZIndex = z,
		Active = false,
		Parent = parent,
	})
end

-- A loading head `width` px wide (S:351, S:372): the plum box with the shimmer (and "Loading…" on the desktop card).
local function loadingHead(
	parent: GuiObject,
	width: number,
	words: boolean,
	kind: string,
	z: number,
	loops: { UiIdle.Handle }
): Frame
	local box = frame("Loading", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.MatchIntroDim,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = z,
		Parent = parent,
	})
	shimmer(box, width, if words then 0.32 else 0.35, z + 1, loops)
	if words then
		local label = text("Text", TEXT.cardLoading, kind, Palette.Frosting, nil, z + 2)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Parent = box
	end
	return box
end

-- Private: cards ------------------------------------------------------------------------------------------------------

type CardSpec = {
	who: MatchKit.Who,
	level: number,
	side: number,
	row: number,
	nameColor: Color3,
	border: Color3,
	look: MatchHudFormat.PlayerLook,
	layout: any,
	z: number,
	loops: { UiIdle.Handle },
}

local function cardShell(spec: CardSpec, c: any): (CanvasGroup, CanvasGroup, Vector2)
	local L = spec.layout
	local z = spec.z
	local holder: CanvasGroup = Create("CanvasGroup", {
		Name = "Card",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(L.colW, L.cardH + c.lip),
		Position = UDim2.fromOffset(0, spec.row * (L.cardH + L.cardGap)),
		ZIndex = z,
		Active = false,
	})
	local lip = frame("Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		Position = UDim2.fromOffset(0, c.lip),
		Size = UDim2.fromOffset(L.colW, L.cardH),
		ZIndex = z,
		Parent = holder,
	})
	Theme.corner(c.radius, lip)
	local box = frame("Box", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.MatchIntroCard,
		Size = UDim2.fromOffset(L.colW, L.cardH),
		ZIndex = z + 1,
		Parent = holder,
	})
	Theme.corner(c.radius, box)
	inner(Theme.stroke(spec.border, c.border, box))
	-- The content inside the border, clipped to its rounded inner edge (S:347 overflow hidden).
	local size = Vector2.new(L.colW - 2 * c.border, L.cardH - 2 * c.border)
	local content: CanvasGroup = Create("CanvasGroup", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(c.border, c.border),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = z + 2,
		Active = false,
		Parent = box,
	})
	Theme.corner(math.max(c.radius - c.border, 0), content)
	return holder, content, size
end

local function lookKeys(look: MatchHudFormat.PlayerLook): { ColorSequenceKeypoint }
	local keys = { key(0, look.top) }
	if look.mid then
		table.insert(keys, key(0.58, look.mid))
	end
	table.insert(keys, key(1, look.faceEnd))
	return keys
end

-- The desktop card (S:345-363).
local function desktopCard(spec: CardSpec): Card
	local L = spec.layout
	local c = L.card
	local z = spec.z
	local holder, content, size = cardShell(spec, c)
	local right = spec.side > 0
	local topH = size.Y - c.footer
	local function x(at: number, width: number): number -- mirrored on the right (S:347 row-reverse)
		return if right then size.X - at - width else at
	end
	local strip = frame("Strip", {
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(x(0, c.strip), 0),
		Size = UDim2.fromOffset(c.strip, topH),
		ZIndex = z + 3,
		Parent = content,
	})
	gradient(strip, lookKeys(spec.look))
	local headBox = frame("HeadBox", {
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(x(c.strip, c.head), 0),
		Size = UDim2.fromOffset(c.head, topH),
		ClipsDescendants = true,
		ZIndex = z + 3,
		Parent = content,
	})
	gradient(headBox, lookKeys(spec.look))
	local head = headPicture(spec.who, math.max(c.head, topH), headBox, z + 4)
	local loading = loadingHead(headBox, c.head, true, L.loadingText, z + 5, spec.loops)
	local bannerW = size.X - c.strip - c.head
	local banner = frame("Banner", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Frosting,
		Position = UDim2.fromOffset(x(c.strip + c.head, bannerW), 0),
		Size = UDim2.fromOffset(bannerW, topH),
		ClipsDescendants = true,
		ZIndex = z + 3,
		Parent = content,
	})
	pattern(spec.who.squishyId, c.tile, 1, z + 3, banner)
	if spec.who.squishyId ~= "" then
		local pic = toy(spec.who.squishyId, c.toy, z + 4)
		pic.AnchorPoint = Vector2.new(if right then 1 else 0, 0.5)
		pic.Position = UDim2.new(if right then 1 else 0, if right then -c.padX else c.padX, 0.5, c.toyDown / 2)
		pic.Parent = banner
	end
	local chip, chipW = gripChip(spec.level, c.chip, L.gripText, nil, c.gripStroke, z + 4)
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, if right then c.padX else bannerW - c.padX - chipW, 0.5, c.chip.lip / 2)
	chip.Parent = banner
	-- The banner's shimmer (S:359): a slanted white band, once, as the card lands.
	local shineSpec = c.shine
	local shine = frame("Shine", {
		Position = UDim2.fromOffset(shineSpec.from, 0),
		Size = UDim2.new(0, shineSpec.width, 1, 0),
		ZIndex = z + 5,
		Visible = false,
		Parent = banner,
	})
	Theme.shineBand(shine, shineSpec.alpha, shineSpec.slant)
	-- The footer (S:361-363): the name in the player's colour, the squishy's name.
	local footer = frame("Footer", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		Position = UDim2.fromOffset(0, topH),
		Size = UDim2.fromOffset(size.X, c.footer),
		ZIndex = z + 3,
		Parent = content,
	})
	local toyLabel, toySize =
		text("ToyName", squishyName(spec.who.squishyId), L.toyText, Palette.MatchIntroToyName, nil, z + 4)
	toyLabel.AnchorPoint = Vector2.new(1, 0.5)
	toyLabel.Position = UDim2.new(1, -c.footerPadX, 0.5, 0)
	toyLabel.TextXAlignment = Enum.TextXAlignment.Right
	toyLabel.Parent = footer
	local room = size.X - 2 * c.footerPadX - toySize.X - c.footerPadX
	local name = MatchHudFormat.clipText(spec.who.name, room, function(s: string): number
		return Theme.textWidth(s, L.nameText)
	end)
	local nameLabel = text("Name", name, L.nameText, spec.nameColor, nil, z + 4)
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0, c.footerPadX, 0.5, 0)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = footer
	if spec.who.you then
		local tag = youTag(c.you, L.youText, z + 6)
		tag.Position = UDim2.fromOffset(c.border + c.you.x, c.border + c.you.y)
		tag.Parent = holder
	end
	return {
		userId = spec.who.userId,
		side = spec.side,
		row = spec.row,
		order = spec.row * 2 + (if right then 1 else 0),
		holder = holder,
		poser = Tweens.poser(holder),
		head = head,
		headPoser = Tweens.poser(head),
		loading = { loading },
		arrivedOnly = {},
		shine = shine,
		shinePoser = Tweens.poser(shine),
	}
end

-- The phone card (S:368-381).
local function phoneCard(spec: CardSpec): Card
	local L = spec.layout
	local c = L.card
	local z = spec.z
	local holder, content, size = cardShell(spec, c)
	local right = spec.side > 0
	local function x(at: number, width: number): number
		return if right then size.X - at - width else at
	end
	pattern(spec.who.squishyId, c.tile, c.tileAlpha, z + 3, content)
	local strip = frame("Strip", {
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(x(0, c.strip), 0),
		Size = UDim2.fromOffset(c.strip, size.Y),
		ZIndex = z + 4,
		Parent = content,
	})
	gradient(strip, lookKeys(spec.look))
	local headX = c.strip + c.headMargin
	local headBox = frame("HeadBox", {
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, x(headX, c.head), 0.5, 0),
		Size = UDim2.fromOffset(c.head, c.head),
		ZIndex = z + 4,
		Parent = content,
	})
	Theme.corner(c.headRadius, headBox)
	gradient(headBox, lookKeys(spec.look))
	inner(Theme.stroke(INK, c.headBorder, headBox))
	-- The picture inside the border, clipped to its rounded inner edge (MatchKit.head's CanvasGroup).
	local innerSize = c.head - 2 * c.headBorder
	local clip: CanvasGroup = Create("CanvasGroup", {
		Name = "Picture",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(innerSize, innerSize),
		ZIndex = z + 5,
		Active = false,
		Parent = headBox,
	})
	Theme.corner(math.max(c.headRadius - c.headBorder, 0), clip)
	local head = headPicture(spec.who, innerSize, clip, z + 5)
	local loadingBox = loadingHead(clip, innerSize, false, L.loadingText, z + 6, spec.loops)
	if spec.who.squishyId ~= "" then
		local pic = toy(spec.who.squishyId, c.toy, z + 5)
		pic.AnchorPoint = Vector2.new(0, 0.5)
		pic.Position = UDim2.new(0, x(size.X - c.toyMargin - c.toy, c.toy), 0.5, 0)
		pic.Parent = content
	end
	-- The middle: the name (and YOU), then the grip chip or "Loading…" (S:374-378).
	local midX = headX + c.head + c.headMargin
	local midW = size.X - midX - c.toyMargin - c.toy - c.toyMargin
	local middle = frame("Middle", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, x(midX, midW), 0.5, 0),
		Size = UDim2.fromOffset(midW, c.you.height + c.nameGap + c.chip.height),
		ZIndex = z + 5,
		Parent = content,
	})
	local tag: Frame? = nil
	local tagW = 0
	if spec.who.you then
		local made, width = youTag(c.you, L.youText, z + 6)
		tag, tagW = made, width + c.you.gap
	end
	local name = MatchHudFormat.clipText(spec.who.name, midW - tagW, function(s: string): number
		return Theme.textWidth(s, L.nameText)
	end)
	local nameLabel, nameSize = text("Name", name, L.nameText, spec.nameColor, nil, z + 6)
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0, 0, 0, c.you.height / 2)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = middle
	if tag then
		tag.Position = UDim2.fromOffset(math.min(nameSize.X, midW - tagW) + c.you.gap, 0)
		tag.Parent = middle
	end
	local chip = gripChip(spec.level, c.chip, L.gripText, INK, nil, z + 6)
	chip.Position = UDim2.fromOffset(0, c.you.height + c.nameGap)
	chip.Parent = middle
	local words = text("Loading", TEXT.cardLoading, L.loadingText, Palette.Frosting, nil, z + 6)
	words.AnchorPoint = Vector2.new(0, 0.5)
	words.Position = UDim2.new(0, 0, 0, c.you.height + c.nameGap + c.chip.height / 2)
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.Parent = middle
	return {
		userId = spec.who.userId,
		side = spec.side,
		row = spec.row,
		order = spec.row * 2 + (if right then 1 else 0),
		holder = holder,
		poser = Tweens.poser(holder),
		head = head,
		headPoser = Tweens.poser(head),
		loading = { loadingBox, words },
		arrivedOnly = { chip },
	}
end

-- Private: the layers --------------------------------------------------------------------------------------------------

local function stage(name: string, parent: GuiObject, z: number): (Frame, UIScale)
	local made = frame(name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = z,
		Visible = false,
		Parent = parent,
	})
	return made, Create("UIScale", { Parent = made })
end

-- The team head (S:340-347): the name letter-spaced in the team's text colour, the line drawn from the middle, its two
-- dots and the chevron.
local function header(
	name: string,
	color: Color3,
	L: any,
	parent: GuiObject,
	z: number
): { text: Posed, line: Posed, dots: { GuiObject } }
	local H = CFG.header
	-- The name's box is the design's font size (line-height 1), so the rule sits where the design has it; PR2's
	-- bigger phone text grows around that box's middle.
	local label = spaced("Name", name, L.hdrText, color, L.hdrStroke, L.hdrSpacing, z)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0, L.hdrFont / 2)
	label.Parent = parent
	local box = frame("Rule", {
		Position = UDim2.fromOffset(0, L.hdrFont + L.hdrGap),
		Size = UDim2.new(1, 0, 0, H.box),
		ZIndex = z,
		Parent = parent,
	})
	local line = frame("Line", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Frosting,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, H.lineY),
		Size = UDim2.new(1, -2 * H.lineInset, 0, H.line),
		ZIndex = z,
		Parent = box,
	})
	Theme.corner(H.line / 2, line)
	local dots: { GuiObject } = {}
	for _, at in { 0, 1 } do
		local dot = frame("Dot", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.Frosting,
			AnchorPoint = Vector2.new(at, 0),
			Position = UDim2.new(at, 0, 0, H.dotY),
			Size = UDim2.fromOffset(H.dot, H.dot),
			ZIndex = z + 1,
			Parent = box,
		})
		Theme.corner(H.dot / 2, dot)
		table.insert(dots, dot)
	end
	-- The chevron: a plum square turned 45 with its right and bottom edges drawn (a "v" pointing down).
	local chevron = frame("Chevron", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.MatchIntroDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, H.chevronY),
		Size = UDim2.fromOffset(H.chevron, H.chevron),
		Rotation = 45,
		ZIndex = z + 1,
		Parent = box,
	})
	for _, edge in { { 1, 0, H.chevronBorder, H.chevron }, { 0, 1, H.chevron, H.chevronBorder } } do
		frame("Edge", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.Frosting,
			AnchorPoint = Vector2.new(edge[1], edge[2]),
			Position = UDim2.fromScale(edge[1], edge[2]),
			Size = UDim2.fromOffset(edge[3], edge[4]),
			ZIndex = z + 2,
			Parent = chevron,
		})
	end
	table.insert(dots, chevron)
	return { text = posed(label), line = posed(line), dots = dots }
end

local function build(ctx: MatchHudFormat.Context, view: any): Made
	local layoutName = MatchIntro.layoutName(ctx.compact())
	local L = CFG.layouts[layoutName]
	local tdm = view.mode == "tdm"
	local z0 = CFG.z
	local margin = CFG.margin
	local loops: { UiIdle.Handle } = {}
	-- A layer over the whole screen (the safe area plus the margin), drawn in `z` order among the stages: a child's
	-- ZIndex counts only among its siblings, so each such layer is its own child of the root.
	local covers: { Frame } = {}
	local function cover(name: string, z: number, props: { [string]: any }): Frame
		local made = frame(name, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			ZIndex = z,
			Parent = ctx.root,
		})
		for property, value in props do
			(made :: any)[property] = value
		end
		table.insert(covers, made)
		return made
	end
	local dim = cover("IntroDim", z0, { BackgroundColor3 = Palette.MatchIntroDim })
	local stages, scales = {}, {}
	local intro, introScale = stage("Intro", ctx.root, z0 + 1)
	table.insert(stages, intro)
	table.insert(scales, introScale)

	-- The columns (S:340-382) and the corner glows (S:339-340).
	local columns = MatchIntro.columns(view)
	local sides = {
		{ list = columns.left, team = columns.leftTeam, side = -1 },
		{ list = columns.right, team = columns.rightTeam, side = 1 },
	}
	local function teamLook(team: string?): MatchHudFormat.PlayerLook
		return MatchHudFormat.playerLook("tdm", team, nil)
	end
	local glows: { ImageLabel } = {}
	for index, s in sides do
		local tint = if tdm then (teamLook(s.team).mid or WHITE) else Palette.ModeFfaMid
		table.insert(
			glows,
			picture(if index == 1 then "GlowA" else "GlowB", GLOW_KEY, {
				ImageColor3 = tint,
				ImageTransparency = 1,
				ZIndex = z0 + 1,
				Parent = intro,
			})
		)
	end
	local cards: { Card } = {}
	local headers = {}
	for _, s in sides do
		local column = frame(if s.side < 0 then "ColumnL" else "ColumnR", {
			AnchorPoint = Vector2.new(if s.side < 0 then 0 else 1, 0),
			Position = UDim2.new(if s.side < 0 then 0 else 1, -s.side * L.side, 0, L.colTop),
			Size = UDim2.fromOffset(L.colW, MAX_ROWS * (L.cardH + L.cardGap)),
			ZIndex = z0 + 2,
			Parent = intro,
		})
		if tdm and s.team then
			local head = frame(if s.side < 0 then "HeadL" else "HeadR", {
				AnchorPoint = Vector2.new(if s.side < 0 then 0 else 1, 0),
				Position = UDim2.new(if s.side < 0 then 0 else 1, -s.side * L.side, 0, L.hdrTop),
				Size = UDim2.fromOffset(L.colW, L.colTop - L.hdrTop),
				ZIndex = z0 + 2,
				Parent = intro,
			})
			local label = string.upper(Strings.match.team[string.lower(s.team)] or s.team)
			table.insert(headers, header(label, teamLook(s.team).text, L, head, z0 + 2))
		end
		for row, player in s.list do
			local who = MatchKit.who(ctx, view, player.userId)
			local look = if tdm then teamLook(player.team) else who.look
			local spec: CardSpec = {
				who = who,
				level = player.level or 1,
				side = s.side,
				row = row - 1,
				nameColor = if who.you then Palette.Lemon else look.text,
				border = if who.you then Palette.Lemon else INK,
				look = look,
				layout = L,
				z = z0 + 2,
				loops = loops,
			}
			local card = if layoutName == "phone" then phoneCard(spec) else desktopCard(spec)
			card.holder.Parent = column
			table.insert(cards, card)
		end
	end

	-- The middle column (S:383-412): the title, the mode lines, the emblem, the VS.
	local centre = frame("Centre", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, L.titleTop),
		Size = UDim2.fromOffset(L.width, 1),
		ZIndex = z0 + 3,
		Parent = intro,
	})
	local y = 0
	local titleColors = ColorSequence.new({
		key(0, WHITE),
		key(0.4, Palette.MatchIntroTitle2),
		key(0.72, Palette.MatchIntroTitle3),
		key(1, Palette.MatchIntroTitleEnd),
	})
	local lineStep = math.round(Theme.textSize(L.titleText) * L.titleLine)
	local lines = MatchIntro.titleLines(view.mapName or "")
	local title = frame("Title", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(L.width, lineStep * #lines),
		ZIndex = z0 + 3,
		Parent = centre,
	})
	for index, line in lines do
		local holder = stacked("Line", line, L.titleText, L.titleStroke, L.titleShadow, titleColors, z0 + 3)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, 0, 0, math.round((index - 0.5) * lineStep))
		holder.Parent = title
	end
	y += lineStep * #lines + L.centreGap
	local modeLine, goalLine = MatchIntro.lines(view)
	local modePx = Theme.textSize(L.modeText)
	local mode = frame("Mode", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(L.width, math.round(2 * modePx + L.modeGap)),
		ZIndex = z0 + 3,
		Parent = centre,
	})
	for index, words in { modeLine, goalLine } do
		local holder = spaced("Line", words, L.modeText, Palette.Frosting, nil, L.modeSpacing, z0 + 3)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, 0, 0, math.round((index - 0.5) * modePx + (index - 1) * L.modeGap))
		holder.Parent = mode
	end
	y += math.round(2 * modePx + L.modeGap) + L.centreGap
	local logo = frame("Logo", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(L.logoBox, L.logoBox),
		ZIndex = z0 + 3,
		Parent = centre,
	})
	local diamond = frame("Diamond", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Frosting,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(L.logo, L.logo),
		Rotation = 45,
		ZIndex = z0 + 3,
		Parent = logo,
	})
	Theme.corner(10, diamond)
	inner(Theme.stroke(INK, 3, diamond))
	picture("Emblem", EMBLEM_KEY, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(L.logoImage, L.logoImage),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = z0 + 4,
		Parent = logo,
	})
	y += L.logoBox + L.centreGap
	local vs: Posed? = nil
	local vsText: Posed? = nil
	if tdm then
		local box = frame("VsBox", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(L.vsBox, L.vsBox),
			ZIndex = z0 + 3,
			Parent = centre,
		})
		local turn = frame("Vs", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(L.vs, L.vs),
			Rotation = 45,
			ZIndex = z0 + 3,
			Parent = box,
		})
		local lip = frame("Lip", {
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, L.vsShadow),
			Size = UDim2.fromScale(1, 1),
			ZIndex = z0 + 3,
			Parent = turn,
		})
		Theme.corner(L.vsRadius, lip)
		local face =
			frame("Face", { BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = z0 + 4, Parent = turn })
		Theme.corner(L.vsRadius, face)
		gradient(face, { key(0, WHITE), key(0.6, Palette.Frosting), key(1, Palette.MatchIntroVsEnd) })
		inner(Theme.stroke(INK, L.vsBorder, face))
		-- S:409: V in the left team's score colour, S in the right's.
		local leftRed = columns.leftTeam ~= TEAM_NAMES[2]
		local v = (if leftRed then Palette.MatchTeamRedScore else Palette.MatchTeamBlueScore):ToHex()
		local s = (if leftRed then Palette.MatchTeamBlueScore else Palette.MatchTeamRedScore):ToHex()
		local label = text("Text", TEXT.vs, L.vsText, WHITE, L.vsStroke, z0 + 5)
		label.RichText = true
		label.Text =
			`<font color="#{v}">{string.sub(TEXT.vs, 1, 1)}</font><font color="#{s}">{string.sub(TEXT.vs, 2)}</font>`
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, -math.round(L.vsPadBottom / 2))
		label.Parent = box
		vs = posed(turn)
		vsText = posed(label)
	end

	-- The load bar (S:414-419).
	local bar = frame("Load", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -L.barBottom),
		Size = UDim2.fromOffset(L.barW, math.ceil(Theme.lineHeight(L.barText)) + CFG.barGap + L.barH),
		ZIndex = z0 + 3,
		Parent = intro,
	})
	local trough = frame("Trough", {
		BackgroundTransparency = 0.4,
		BackgroundColor3 = INK,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, L.barH),
		ZIndex = z0 + 3,
		Parent = bar,
	})
	Theme.corner(L.barH / 2, trough)
	inner(Theme.stroke(INK, CFG.barBorder, trough))
	local fillH = L.barH - 2 * CFG.barBorder
	local fill = frame("Fill", {
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(CFG.barBorder, CFG.barBorder),
		Size = UDim2.fromOffset(0, fillH),
		ZIndex = z0 + 4,
		Parent = trough,
	})
	Theme.corner(fillH / 2, fill)
	gradient(fill, { key(0, Palette.StickerGripTop), key(1, Palette.StickerGripEnd) })

	-- The wipes (S:422-423): the left team's colours from the left, the right team's from the right.
	local wipes: { Frame } = {}
	local wipeLayer = cover("IntroWipes", z0 + 6, {})
	for index, s in sides do
		local look = if tdm then teamLook(s.team) else nil
		local mid = if look then look.mid or look.top else Palette.ModeFfaMid
		local dark = if look then look.faceEnd else Palette.ModeFfaEnd
		local wipe = frame(if index == 1 then "WipeL" else "WipeR", {
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(if index == 1 then 0 else 1, 0),
			Size = UDim2.fromScale(EXIT.wipeShare, 1),
			ZIndex = z0 + 6,
			Visible = false,
			Parent = wipeLayer,
		})
		gradient(wipe, if index == 1 then { key(0, dark), key(1, mid) } else { key(0, mid), key(1, dark) }, 0)
		table.insert(wipes, wipe)
	end

	-- The Loading arena cover (S:434-440): the radial as the outer colour under two tinted glows.
	local bootBg = cover("IntroBootBg", z0 + 7, {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.MatchBootOuter,
		Visible = false,
	})
	for _, glow in { { Palette.MatchBootMid, 1.5 }, { Palette.MatchBootInner, 0.7 } } do
		picture("Glow", GLOW_KEY, {
			ImageColor3 = glow[1],
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(glow[2], glow[2] * 1.6),
			ZIndex = z0 + 7,
			Parent = bootBg,
		})
	end
	local boot, bootScale = stage("Boot", ctx.root, z0 + 8)
	table.insert(stages, boot)
	table.insert(scales, bootScale)
	local B = CFG.boot
	local bootWords, wordsSize = stacked("Text", TEXT.loading, B.bootText, B.stroke, B.shadow, nil, z0 + 8)
	local dotsH = B.dots.px
	local blockH = B.emblem + B.gap + wordsSize.Y + B.gap + dotsH
	local block = frame("Block", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.max(B.emblem, wordsSize.X), blockH),
		ZIndex = z0 + 8,
		Parent = boot,
	})
	local emblem = frame("Emblem", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(B.emblem, B.emblem),
		ZIndex = z0 + 8,
		Parent = block,
	})
	local bob = picture(
		"Picture",
		EMBLEM_KEY,
		{ Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Fit, ZIndex = z0 + 8, Parent = emblem }
	)
	local bobLoop = UiIdle.addFrames(bob, B.bob.frames, { periodS = B.bob.periodS, curve = B.bob.curve })
	if bobLoop then
		table.insert(loops, bobLoop)
	end
	bootWords.AnchorPoint = Vector2.new(0.5, 0)
	bootWords.Position = UDim2.new(0.5, 0, 0, B.emblem + B.gap)
	bootWords.Parent = block
	local dotsW = 3 * B.dots.px + 2 * B.dots.gap
	for index = 1, 3 do
		local cell = frame("Dot", {
			Position = UDim2.new(0.5, -dotsW / 2 + (index - 1) * (B.dots.px + B.dots.gap), 1, -dotsH),
			Size = UDim2.fromOffset(B.dots.px, B.dots.px),
			ZIndex = z0 + 8,
			Parent = block,
		})
		local dot = frame("Face", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.StickerPinkSoft,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z0 + 8,
			Parent = cell,
		})
		Theme.corner(B.dots.px / 2, dot)
		local loop = UiIdle.addFrames(dot, B.dots.frames, {
			periodS = B.dots.periodS,
			delayS = (index - 1) * B.dots.stepS,
			curve = B.dots.curve,
		})
		if loop then
			table.insert(loops, loop)
		end
	end

	-- The 3-2-1 (S:126-133): the turning rays, the label over the number, centred.
	local count, countScale = stage("Count", ctx.root, z0 + 9)
	table.insert(stages, count)
	table.insert(scales, countScale)
	local countCentre = frame("Centre", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1, 1),
		ZIndex = z0 + 9,
		Parent = count,
	})
	local rays: ImageLabel? = nil
	if AssetTable.image(RAYS_KEY) then
		rays = picture("Rays", RAYS_KEY, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(COUNT.rays, COUNT.rays),
			ZIndex = z0 + 9,
			Parent = count,
		})
	end
	local numberPx = Theme.textSize(COUNT.numberText)
	local countColors = ColorSequence.new({
		key(0, Palette.StickerLevelGradTop),
		key(0.25, Palette.StickerCoinText),
		key(0.5, Palette.StickerPinkSoft),
		key(0.72, Palette.StickerFxPurple),
		key(1, Palette.StickerMintTop),
	})
	local labelH = math.ceil(Theme.lineHeight(COUNT.labelText))
	local bigH = COUNT.px -- CSS line-height 1
	local groupTop = -(labelH + COUNT.labelGap + bigH) / 2
	local number = frame("Number", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, math.round(groupTop + labelH + COUNT.labelGap + bigH / 2)),
		Size = UDim2.fromOffset(1, 1),
		ZIndex = z0 + 10,
		Parent = count,
	})
	local faces: { [number]: Frame } = {}
	for n = 0, 3 do
		local words = if n == 0 then TEXT.go else tostring(n)
		local px = if n == 0 then COUNT.goPx else COUNT.px
		-- Roblox draws text up to 100 px: the stack is drawn at the kind's size and scaled up.
		local k = px / numberPx
		local holder =
			stacked("Beat" .. n, words, COUNT.numberText, COUNT.stroke / k, COUNT.shadow / k, countColors, z0 + 10)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Visible = false
		Create("UIScale", { Name = "Size", Scale = k, Parent = holder })
		holder.Parent = number
		faces[n] = holder
	end
	local labelHolder = frame("Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, math.round(groupTop + labelH / 2)),
		Size = UDim2.fromOffset(1, 1),
		ZIndex = z0 + 10,
		Parent = count,
	})

	return {
		layoutName = layoutName,
		layout = L,
		covers = covers,
		dim = dim,
		wipes = wipes,
		bootBg = bootBg,
		stages = stages,
		scales = scales,
		intro = intro,
		glows = glows,
		cards = cards,
		title = posed(title),
		mode = posed(mode),
		logo = posed(logo),
		vs = vs,
		vsText = vsText,
		headers = headers,
		bar = posed(bar),
		barText = frame("Words", { Parent = bar }),
		barFill = fill,
		barInner = L.barW - 2 * CFG.barBorder,
		barShown = 0,
		barCount = -1,
		boot = boot,
		count = count,
		countCentre = countCentre,
		countLabel = posed(labelHolder),
		countLabelText = frame("Words", { Parent = labelHolder }),
		countNumber = posed(number),
		countFaces = faces,
		rays = rays,
		loops = loops,
	}
end

-- Fits every stage into the safe area (see the header) and lays the glows out on the intro's stage.
local function fit(made: Made, canvas: Vector2)
	local L = made.layout
	local k = MatchIntro.stageScale(canvas, L)
	local size = Vector2.new(math.max(canvas.X / k, L.width), math.max(canvas.Y / k, L.height))
	for index, s in made.stages do
		s.Size = UDim2.fromOffset(math.round(size.X), math.round(size.Y))
		made.scales[index].Scale = k
	end
	local G = CFG.glow
	local side = math.round(size.X * G.size)
	for index, glow in made.glows do
		glow.Size = UDim2.fromOffset(side, side)
		glow.AnchorPoint = Vector2.new(if index == 1 then 0 else 1, 0)
		glow.Position = UDim2.new(
			if index == 1 then 0 else 1,
			(if index == 1 then 1 else -1) * math.round(size.X * G.left),
			0,
			math.round(size.Y - size.X * G.top)
		)
	end
end

-- New letter-spaced words in `holder` (the bar's count, the count's label), centred across it at `anchorY` of its
-- height; returns their fade group (the element's own groups were made before they were).
local function setWords(
	holder: Frame,
	words: string,
	kind: string,
	color: Color3?,
	stroke: number?,
	em: number,
	z: number,
	anchorY: number
): Tweens.FadeGroup
	holder:ClearAllChildren()
	local line, size = spaced("Line", words, kind, color, stroke, em, z)
	holder.Size = UDim2.fromOffset(size.X, size.Y)
	holder.AnchorPoint = Vector2.new(0.5, anchorY)
	holder.Position = UDim2.fromScale(0.5, anchorY)
	line.Parent = holder
	return Tweens.fadeGroup(line)
end

-- Public --------------------------------------------------------------------------------------------------------------

function MatchIntro.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local made: Made? = nil
	local rebuild = false
	-- The timeline (os.clock seconds; it outlives a rebuild).
	local seenWaiting = false
	local bootAt: number? = nil -- the cover came up
	local bootGoneAt: number? = nil -- it started to fade
	local introAt: number? = nil
	local exitAt: number? = nil
	local arrivedAt: { [number]: number } = {} -- userId -> when their head popped in (0: in from the start)
	local played: { [string]: boolean } = {}
	local countAt: number? = nil -- the count came up
	local beatShown: number? = nil
	local beatAt = 0
	local goAt: number? = nil
	local finished = false
	local murmur: any = nil
	local blur: BlurEffect? = nil

	local function play(name: string, opts: { [string]: any }?)
		ctx.play(name, opts)
	end

	local function once(name: string, fn: () -> ())
		if not played[name] then
			played[name] = true
			fn()
		end
	end

	local function clearBlur()
		local current = blur
		blur = nil
		if current then
			current:Destroy()
		end
	end

	local function stopMurmur(fadeMs: number?)
		local current = murmur
		murmur = nil
		if current then
			pcall(current.stop, current, fadeMs)
		end
	end

	local function teardown()
		local current = made
		made = nil
		if current then
			for _, handle in current.loops do
				handle:remove()
			end
			for _, layer in current.covers do
				layer:Destroy()
			end
			for _, s in current.stages do
				s:Destroy()
			end
		end
	end

	local function ensure(view: any): Made
		if rebuild then
			rebuild = false
			teardown()
		end
		local current = made
		if current then
			return current
		end
		local built = build(ctx, view)
		made = built
		fit(built, ctx.canvas())
		return built
	end

	local function finish()
		finished = true
		stopMurmur(CFG.murmur.outMs)
		clearBlur()
		teardown()
	end

	local function poseAt(track: any, t: number, reduced: boolean): Tweens.Pose
		return MatchHudFormat.trackPose(track.frames, t, track.ms, track.curve, track.wholeRun, reduced, FADE_MS)
	end

	local function pose(p: Posed, track: any, t: number, reduced: boolean)
		local at = poseAt(track, t, reduced)
		local alpha = at.alpha
		if alpha == nil then
			p.poser:set(at)
			return
		end
		for _, fade in p.fades do
			fade:setAlpha(alpha)
		end
		local motion = table.clone(at)
		motion.alpha = nil
		p.poser:set(motion)
	end

	-- A one-track pose of frames { from -> to } (the generated card and fall tracks).
	local function trackOf(frames: { any }, ms: number, curve: string?, wholeRun: string?): any
		return { frames = frames, ms = ms, curve = curve, wholeRun = wholeRun }
	end

	local function startIntro(view: any, clock: number)
		introAt = clock
		for _, player in view.players do
			if player.arrived then
				arrivedAt[player.userId] = 0
			end
		end
		murmur = if ctx.loop then ctx.loop(SOUND.murmur) else nil
		local effect = Instance.new("BlurEffect")
		effect.Name = BLUR_NAME
		effect.Size = CFG.blur.size
		effect.Parent = Lighting
		blur = effect
	end

	local function renderIntro(m: Made, view: any, clock: number, reduced: boolean)
		local t = clock - (introAt :: number)
		local te = if exitAt then clock - exitAt else nil
		local L = m.layout
		local shown = te == nil or te < EXIT.hideAt
		m.intro.Visible = shown
		-- The background (S:613): the dim and the glows fade in.
		local bgK = if shown then math.clamp(t / (CFG.bg.ms / 1000), 0, 1) else 0
		bgK = Tweens.curve(CFG.bg.curve)(bgK)
		m.dim.BackgroundTransparency = 1 - CFG.dimAlpha * bgK
		for _, glow in m.glows do
			glow.ImageTransparency = 1 - bgK
		end
		if not shown then
			return
		end
		-- The bar's count first (its new words fade with the bar below).
		local n, total = 0, #view.players
		for _, player in view.players do
			if player.arrived then
				n += 1
			end
		end
		if n ~= m.barCount then
			m.barCount = n
			local words = Strings.format(TEXT.players, { n = n, max = total })
			m.bar.fades[2] = setWords(m.barText, words, L.barText, Palette.Frosting, nil, CFG.barSpacing, CFG.z + 4, 0)
		end
		local fall =
			trackOf({ { at = 0, alpha = 1, y = 0 }, { at = 1, alpha = 0, y = EXIT.fallPx } }, EXIT.fallMs, EXIT.curve)
		local function entrance(p: Posed?, track: any, at: number)
			if p == nil then
				return
			end
			if te then
				pose(p, fall, te, reduced)
			else
				pose(p, track, t - at, reduced)
			end
		end
		entrance(m.title, CFG.title, CFG.title.at)
		entrance(m.mode, CFG.mode, CFG.mode.at)
		entrance(m.logo, CFG.logo, CFG.logo.at)
		entrance(m.bar, trackOf({ { at = 0, alpha = 0 }, { at = 1, alpha = 1 } }, CFG.bar.ms), CFG.bar.at)
		local V = CFG.vs
		if m.vs then
			if te then
				pose(
					m.vs,
					trackOf({ { at = 0, alpha = 1, y = 0 }, { at = 1, alpha = 0, y = EXIT.fallPx } }, EXIT.fallMs),
					te,
					reduced
				)
			else
				pose(m.vs, V, t - V.at, reduced)
			end
		end
		entrance(m.vsText, trackOf(V.textFrames, V.textMs, V.textCurve), V.at + V.textDelayMs / 1000)
		local Hd = CFG.headers
		for _, h in m.headers do
			entrance(h.text, trackOf({ { at = 0, alpha = 0 }, { at = 1, alpha = 1 } }, Hd.textMs, "easeOut"), Hd.at)
			local line = if reduced
				then trackOf({ { at = 0, alpha = 0 }, { at = 1, alpha = 1 } }, Hd.lineMs)
				else trackOf({ { at = 0, sx = 0 }, { at = 1, sx = 1 } }, Hd.lineMs, Hd.lineCurve)
			pose(h.line, line, t - Hd.at, false)
			local dotsK = math.clamp((t - Hd.at - Hd.dotsDelayMs / 1000) / (Hd.dotsMs / 1000), 0, 1)
			for _, dot in h.dots do
				dot.Visible = dotsK > 0
				dot.BackgroundTransparency = 1 - dotsK
				for _, edge in dot:GetChildren() do
					if edge:IsA("Frame") then
						edge.BackgroundTransparency = 1 - dotsK
					end
				end
			end
		end
		-- The cards (S:620-630): in from their side, top to bottom; out again on the exit (S:645).
		local C = CFG.cards
		local travel = C.travel * L.colW
		for _, card in m.cards do
			local at = C.at + card.row * C.rowS + (if card.side > 0 then C.rightS else 0)
			local out = card.side * travel
			-- The card is a CanvasGroup: its poser fades the whole card (no lip showing through the box).
			if te then
				local delay = card.row * EXIT.cardStepMs / 1000
				local exitTrack =
					trackOf({ { at = 0, alpha = 1, x = 0 }, { at = 1, alpha = 0, x = out } }, EXIT.cardsMs, EXIT.curve)
				card.poser:set(poseAt(exitTrack, te - delay, reduced))
			else
				local frames = if reduced
					then { { at = 0, alpha = 0 }, { at = 1, alpha = 1 } }
					else {
						{ at = 0, alpha = 0, x = out },
						{ at = 0.75, alpha = 1, x = -card.side * C.overshoot },
						{ at = 1, alpha = 1, x = 0 },
					}
				card.poser:set(poseAt(trackOf(frames, C.ms, nil, C.wholeRun), t - at, reduced))
				if t >= at then
					once("whoosh" .. card.order, function()
						play(SOUND.whoosh, { pitch = 2 ^ (card.order / 12) })
					end)
				end
				local shine, shinePoser = card.shine, card.shinePoser
				if shine and shinePoser then
					local S = L.card.shine
					local u = (t - at - S.delayMs / 1000) / (S.ms / 1000)
					shine.Visible = not reduced and u > 0 and u < 1
					if shine.Visible then
						shinePoser:set({ x = (S.to - S.from) * Tweens.curve("easeInOut")(u) })
					end
				end
			end
			-- Their head: loading until the server says they arrived, then it pops in (S:603-606).
			local inAt = arrivedAt[card.userId]
			local arrived = inAt ~= nil
			for _, part in card.loading do
				part.Visible = not arrived
			end
			for _, part in card.arrivedOnly do
				part.Visible = arrived
			end
			card.head.Visible = arrived
			if inAt and inAt > 0 then
				local H = CFG.head
				local frames = if reduced then { { at = 0, alpha = 0 }, { at = 1, alpha = 1 } } else H.frames
				card.headPoser:set(MatchHudFormat.trackPose(frames, clock - inAt, H.ms, H.curve, nil, false, FADE_MS))
			end
		end
		-- The load bar (S:414-419): the arrived share, eased in over barFillMs.
		local target = if total > 0 then n / total else 0
		local step = 1 / math.max(CFG.barFillMs / 1000 * 60, 1) -- about barFillMs at 60 frames a second
		m.barShown += math.clamp(target - m.barShown, -step, step)
		m.barFill.Size = UDim2.fromOffset(math.round(m.barInner * m.barShown), m.barFill.Size.Y.Offset)
		-- The sounds of the timeline (S:615, S:633).
		if te == nil then
			if t >= CFG.title.at then
				once("slam", function()
					play(SOUND.slam)
				end)
			end
			if m.vs and t >= V.at then
				once("vs", function()
					play(SOUND.vs)
				end)
			end
			local current = murmur
			if current then
				pcall(current.setVolume, current, math.clamp(t / (CFG.murmur.inMs / 1000), 0, 1))
			end
		end
	end

	local function renderWipes(m: Made, clock: number, reduced: boolean)
		local te = if exitAt then clock - exitAt else nil
		local closed = 0 -- 1 = the wipes meet in the middle
		if te then
			local inK = math.clamp((te - EXIT.wipeInAt) / (EXIT.wipeInMs / 1000), 0, 1)
			local outK = math.clamp((te - EXIT.wipeOutAt) / (EXIT.wipeOutMs / 1000), 0, 1)
			local ease = Tweens.curve(EXIT.wipeCurve)
			closed = if outK > 0 then 1 - ease(outK) else ease(inK)
		end
		for index, wipe in m.wipes do
			wipe.Visible = closed > 0
			local side = if index == 1 then -1 else 1
			if reduced then
				wipe.Position = UDim2.fromScale(if index == 1 then 0 else 1, 0)
				wipe.BackgroundTransparency = 1 - closed
			else
				local away = (1 - closed) * 1.01 * EXIT.wipeShare * side
				wipe.Position = UDim2.fromScale((if index == 1 then 0 else 1) + away, 0)
				wipe.BackgroundTransparency = 0
			end
		end
		local current = blur
		if current and te then
			current.Size = CFG.blur.size * (1 - math.clamp(te / (CFG.blur.outMs / 1000), 0, 1))
			if te >= CFG.blur.outMs / 1000 then
				clearBlur()
			end
		end
	end

	local function renderBoot(m: Made, clock: number)
		local since = bootAt
		local shown = since ~= nil
		local k = 1
		local gone = bootGoneAt
		if gone then
			k = 1 - math.clamp((clock - gone) / (CFG.boot.fadeMs / 1000), 0, 1)
			shown = shown and k > 0
		end
		m.bootBg.Visible = shown
		m.boot.Visible = shown
		if shown then
			m.bootBg.BackgroundTransparency = 1 - k
			for _, child in m.bootBg:GetChildren() do
				if child:IsA("ImageLabel") then
					child.ImageTransparency = 1 - k
				end
			end
			for _, d in m.boot:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextTransparency = 1 - k
					local outline = d:FindFirstChild("Outline")
					if outline and outline:IsA("UIStroke") then
						outline.Transparency = 1 - k
					end
				elseif d:IsA("ImageLabel") then
					d.ImageTransparency = 1 - k
				end
			end
		end
	end

	local function beatFx(m: Made, n: number)
		local k = m.scales[3].Scale
		if n > 0 then
			play(SOUND.tick)
			play(SOUND.countSlam)
			UiFx.ring(m.countCentre, WHITE, COUNT.ring * k)
			return
		end
		play(SOUND.go)
		local G = COUNT.goSparks
		UiFx.sparks(m.countCentre, { n = G.n, spread = G.spread * k, size = G.size * k, up = G.up * k, ms = G.ms })
		for _, r in COUNT.goRings do
			task.delay(r.delayMs / 1000, function()
				if made == m then
					UiFx.ring(m.countCentre, (Palette :: any)[r.color], r.size * k)
				end
			end)
		end
		UiFx.jolt(m.count, COUNT.goJolt * k)
	end

	local function renderCount(m: Made, clock: number, reduced: boolean)
		local since = countAt
		m.count.Visible = since ~= nil
		if since == nil then
			return
		end
		local shownBeat = beatShown
		local first = m.countLabelText:GetAttribute("SD_Words")
		local words = if shownBeat == 0 then TEXT.goLine else TEXT.getReady
		if first ~= words then
			m.countLabelText:SetAttribute("SD_Words", words)
			m.countLabel.fades = {
				setWords(
					m.countLabelText,
					words,
					COUNT.labelText,
					nil,
					COUNT.labelStroke,
					COUNT.labelSpacing,
					CFG.z + 10,
					0.5
				),
			}
		end
		pose(m.countLabel, COUNT.label, clock - since, reduced)
		local rays = m.rays
		if rays then
			rays.Rotation = if reduced then 0 else ((clock - since) / COUNT.raysSpinS * 360) % 360
		end
		for n, face in m.countFaces do
			face.Visible = n == shownBeat
		end
		if shownBeat ~= nil then
			local frames = COUNT.frames
			if shownBeat == 0 then
				frames = table.clone(frames)
				frames[#frames] = table.clone(frames[#frames])
				frames[#frames].alpha = 1 -- S:663: SQUISH! stays
			end
			pose(m.countNumber, trackOf(frames, COUNT.beatMs, nil, COUNT.wholeRun), clock - beatAt, reduced)
		end
	end

	local piece = {}

	function piece.update(_self: any, view: any, now: number)
		if finished then
			return
		end
		local phase = view.matchPhase
		local clock = os.clock()
		local reduced = ctx.reduced()
		if phase == "Waiting" then
			seenWaiting = true
			local mine: any = nil
			for _, player in view.players do
				if player.userId == view.you.userId then
					mine = player
					break
				end
			end
			if introAt == nil and mine and not mine.arrived then
				bootAt = bootAt or clock
			elseif introAt == nil then
				startIntro(view, clock)
				if bootAt then
					bootGoneAt = clock
				end
			end
			if introAt then
				for _, player in view.players do
					if player.arrived and arrivedAt[player.userId] == nil then
						arrivedAt[player.userId] = clock
						play(SOUND.pop)
					end
				end
			end
		elseif phase == "Countdown" then
			if introAt and exitAt == nil then
				exitAt = clock
				play(SOUND.whoosh, { pitch = 2 ^ (EXIT_WHOOSH / 12) })
				stopMurmur(CFG.murmur.outMs)
			end
			if bootAt and bootGoneAt == nil then
				bootGoneAt = clock
			end
			local n = MatchIntro.beat(view, now)
			if n ~= nil and n ~= beatShown and (beatShown == nil or n < beatShown) then
				countAt = countAt or clock
				beatShown = n
				beatAt = clock
				goAt = if n == 0 then clock else nil
				beatFx(ensure(view), n)
			end
		elseif phase == "Active" or phase == "Overtime" then
			if countAt ~= nil and goAt == nil then
				beatShown = 0
				beatAt = clock
				goAt = clock
				beatFx(ensure(view), 0)
			elseif countAt == nil and goAt == nil then
				finish() -- met late (the match was on already): nothing to show
				return
			end
		else
			finish()
			return
		end
		if not seenWaiting and countAt == nil then
			return -- a Countdown before its first beat, met late: nothing yet
		end
		local m = ensure(view)
		if introAt then
			renderIntro(m, view, clock, reduced)
		end
		renderWipes(m, clock, reduced)
		renderBoot(m, clock)
		renderCount(m, clock, reduced)
		local ended = goAt ~= nil and clock - (goAt :: number) >= COUNT.goHoldMs / 1000
		local exitEnded = exitAt == nil or clock - (exitAt :: number) >= EXIT.endAt
		if ended and exitEnded then
			finish()
		end
	end

	function piece.layout(_self: any)
		local current = made
		if current == nil then
			return
		end
		if current.layoutName ~= MatchIntro.layoutName(ctx.compact()) then
			rebuild = true -- the other layout, built at the next update (the timeline goes on)
			return
		end
		fit(current, ctx.canvas())
	end

	function piece.destroy(_self: any)
		finished = true
		stopMurmur(nil)
		clearBlur()
		teardown()
	end

	return piece :: any
end

return MatchIntro
