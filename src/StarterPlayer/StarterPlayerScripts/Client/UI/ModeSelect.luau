--!strict
-- ModeSelect (client only). Diego's mode select (2026-10-24; `L:n` = "Squishy Duels LOBBY HUD.dc.html" line n, from his
-- ALL HUDS zip: the markup L:173-216, the behaviour L:985-1003 and L:1355-1368): the full-screen picker the DUEL button
-- opens (HudController). Three cards, Config.UI.ModeSelect.cards = DUEL 1v1, TEAM DEATHMATCH, FREE FOR ALL (the ids
-- HudFormat.duelAction reads); the middle one starts picked. A tap on another card picks it; PLAY on the picked one
-- plays it (spec.onPlay, after the screen closed).
--   local screen = ModeSelect.open({ layer = gui, onPlay = function(id) end, onClose = function() end })
--   screen:pick(index, animate?);   screen:play();   screen:close(quiet?);   screen:picked() -> id;   screen.root
-- * The screen (L:174-215): the blue radial, the big rays turning 90 s, each card's glow behind it (the picked one's
--   shows), seven faint squishies drifting, ten shards, sixteen bubbles rising and fourteen twinkles (the design's seeded
--   field, ModeSelect.field), the edge shadow, the cards, "SELECT A GAME MODE" and the red X. Its px are screen px (the
--   design sizes it in vw / vh: its layer has no UI scale).
-- * A card (L:184-207): its soft shadow, ink lip, glow ring and glow (picked), the face (its gradient) and border (white
--   when picked); in its content box (a rounded CanvasGroup: ClipsDescendants ignores UICorner), drawn in ref px under
--   a UIScale (cq = 1% of the content height, L:187): its rays turning 28 s, the ghost number, the art (its own loop, a
--   shine across it, a drop shadow), the bottom fade, the title, the sub pill and, on the picked card, PLAY; then the
--   unpicked cards' dim.
-- * Motion: the screen fades in (.25 s); the cards pop in 70 ms apart (sdPop) and PLAY pops in on the picked card; a pick
--   scales the cards (1 / .82, .5 s overshoot) and fades the border, ring, dim and background glow over. Under
--   ReducedMotion the loops rest (Anim/UiIdle and the field's own step) and the pops and picks only fade.
-- * Input: the cards and PLAY are buttons (mouse, touch); Left / Right and the D-pad pick, Enter / Space / ButtonA play
--   (the selected X closes instead), through ContextActionService while it shows (sunk: no jump, no squeeze). PLAY
--   takes the gamepad selection. Back (Backspace / ButtonB / the Roblox menu) and the focus restore are the caller's
--   (UIController.pushBack, Focus).
-- * Sounds (Button.playSound): the open and each pick ui.click at the tab pitch (L:985, L:991: tab()), a close ui.back
--   (snd.close, not when quiet); PLAY none (the join that follows plays its own).
-- Pure (unit-tested): layout(screen), step(index, delta, count), field().

-- Services

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(script.Parent.Components.Button)
local Create = require(script.Parent.Create)
local Focus = require(script.Parent.Focus)
local SquishyImage = require(script.Parent.Components.SquishyImage)
local Theme = require(script.Parent.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Spec = {
	layer: Instance, -- a full-screen ScreenGui (Config.UI.ModeSelect.layer)
	onPlay: (id: string) -> (), -- PLAY on a card (a Config.UI.ModeSelect.cards id), after the screen closed
	onClose: (() -> ())?, -- the screen closed, any way
}

export type ModeSelect = {
	root: Frame,
	pick: (self: ModeSelect, index: number, animate: boolean?) -> (),
	picked: (self: ModeSelect) -> string,
	play: (self: ModeSelect) -> (),
	close: (self: ModeSelect, quiet: boolean?) -> (),
	isOpen: (self: ModeSelect) -> boolean,
}

export type Layout = {
	width: number,
	height: number,
	cardW: number,
	cardH: number,
	gap: number,
	left: number,
	top: number,
	contentScale: number, -- a card's ref px -> screen px
	refWidth: number, -- a card's content box width in ref px (its height is inner.refHeight)
	raysPx: number,
	glowPx: number,
	titleScale: number,
	titleBottom: number,
}

export type Shard = { x: number, y: number, angle: number, length: number, color: string, dur: number, delay: number }
export type Bubble = { x: number, size: number, dur: number, delay: number }
export type Spark = { x: number, y: number, size: number, dur: number, delay: number }
export type Toy = { x: number, y: number, width: number, id: string, dur: number, delay: number }
export type Field = { shards: { Shard }, bubbles: { Bubble }, sparks: { Spark }, toys: { Toy } }

type Card = {
	id: string,
	slot: Frame,
	pop: Frame,
	click: TextButton,
	border: UIStroke,
	ringStroke: UIStroke,
	ringGlow: ImageLabel,
	bgGlow: ImageLabel,
	dim: Frame,
	ref: Frame,
	refScale: UIScale,
	rays: ImageLabel?,
	art: Frame,
	artLoop: UiIdle.Handle?,
	artSize: number,
	artShine: UIGradient,
	titleBox: Frame,
	titleScale: UIScale,
	titleWidth: number,
	playHolder: Frame,
	playPop: Frame,
	play: ImageButton,
	playShine: UIGradient,
	looks: { Tween },
	pickTrack: Tweens.Keyframes?,
}

-- Constants

local MS = Config.UI.ModeSelect
local CARD = MS.card
local INNER = MS.inner
local FIELD = MS.field
local PLAY = INNER.play
local CQ = INNER.refHeight / 100
local PLAY_K = CQ / PLAY.drawnCq -- the PLAY picture (drawn for cq drawnCq) in ref px
local INK = Palette.StickerInk
local WHITE = Palette.White
local CLICK_SOUND = "ui.click"
local BACK_SOUND = "ui.back"
local TAB_PITCH = Config.Audio.uiPitch.tab
local HEADER_PX = Config.UI.TextSize.Hero -- the modeHeader role's kind: the title's 40 px
local POSE_SCALE = "SD_Pose" -- Tweens.poser's UIScale
local ACTION_LEFT = "SD_ModeSelectLeft"
local ACTION_RIGHT = "SD_ModeSelectRight"
local ACTION_PLAY = "SD_ModeSelectPlay"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local LOOK_STYLE = Enum.EasingStyle.Sine -- CSS `ease` transitions (L:176, L:186-187, L:206)
local LOOK_DIRECTION = Enum.EasingDirection.InOut
local MEASURE_MARGIN_PX = 6 -- scaled text draws a little wider than TextService measures (Theme.textBoundsAt)

-- Module table

local ModeSelect = {}

-- Private

local function color(name: string): Color3
	local value = (Palette :: any)[name]
	return if typeof(value) == "Color3" then value else WHITE
end

local function sequence(stops: { { any } }): ColorSequence
	local keys = {}
	for _, stop in stops do
		table.insert(keys, ColorSequenceKeypoint.new(stop[1], color(stop[2])))
	end
	return ColorSequence.new(keys)
end

-- CSS border-box: the stroke inside the box (UIStroke.BorderStrokePosition, where the engine has it).
local function inner(stroke: UIStroke)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
end

local function picture(name: string, key: string, props: { [string]: any }): ImageLabel
	local label: ImageLabel = Create("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Image = AssetTable.image(key) or "",
		Active = false,
	})
	for property, value in props do
		if property ~= "Parent" then
			(label :: any)[property] = value
		end
	end
	label.Parent = props.Parent
	return label
end

-- Theme.text turns wrapping on; under a UIScale a line draws wider than TextService measures, so a wrapping label
-- drops its last word (found by playing at phone size: "SELECT A GAME"). One line each, the drop copies too.
local function oneLine(label: TextLabel)
	label.TextWrapped = false
	for _, text in label:GetDescendants() do
		if text:IsA("TextLabel") then
			text.TextWrapped = false
		end
	end
end

local function clear(name: string, props: { [string]: any }): Frame
	local frame: Frame = Create("Frame", { Name = name, BackgroundTransparency = 1, Active = false })
	for property, value in props do
		if property ~= "Parent" then
			(frame :: any)[property] = value
		end
	end
	frame.Parent = props.Parent
	return frame
end

-- A band sweeping across a white silhouette (L:192 sdArtShine, L:200 sdShine): the UIGradient's transparency is clear
-- but for the band (`from`..`from + width` of the picture's width: clear for its first and last `edge` share, white at
-- `alpha` in its middle); the step moves it with Offset.
local function shineGradient(
	parent: GuiObject,
	from: number,
	width: number,
	edge: number,
	alpha: number,
	rotation: number
): UIGradient
	local function key(at: number, value: number): NumberSequenceKeypoint
		return NumberSequenceKeypoint.new(math.clamp(at, 0, 1), value)
	end
	local keys = {
		key(0, 1),
		key(from + width * edge, 1),
		key(from + width / 2, 1 - alpha),
		key(from + width * (1 - edge), 1),
		key(1, 1),
	}
	-- A keypoint list must rise strictly from 0 to 1: drop a clamped one that repeats its neighbour.
	local list = {}
	for _, point in keys do
		local last = list[#list]
		if last == nil or point.Time > last.Time then
			table.insert(list, point)
		end
	end
	if list[#list].Time < 1 then
		table.insert(list, key(1, 1))
	end
	return Create("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new(list),
		Offset = Vector2.new(-2, 0),
		Parent = parent,
	})
end

-- The shine's place `u` (0..1) into its period: held at `from` until `hold`, then eased to `to` (ease-in-out).
local function shineAt(u: number, from: number, to: number, hold: number): number
	if u <= hold then
		return from
	end
	local k = Tweens.curve("easeInOut")((u - hold) / (1 - hold))
	return from + (to - from) * k
end

-- 0 at the ends of a period, 1 at its middle, eased both ways (the field's "0%,100% / 50%" loops).
local function swing(u: number, curve: (number) -> number): number
	return if u < 0.5 then curve(u * 2) else curve((1 - u) * 2)
end

local function loopU(now: number, start: number, dur: number, delay: number): number
	if dur <= 0 then
		return 0
	end
	return ((now - start - delay) / dur) % 1
end

-- Public: pure -------------------------------------------------------------------------------------------------------

-- The screen's geometry for a screen of `screen` px (L:182-184, L:175-176, L:213; see Config.UI.ModeSelect).
function ModeSelect.layout(screen: Vector2): Layout
	local width, height = math.max(screen.X, 1), math.max(screen.Y, 1)
	local gap = width * CARD.gapShare
	local cardH = math.min(height * CARD.heightShare, CARD.maxHeight)
	-- [P] the design lets the row overflow a narrow screen; here it shrinks to fit inside edgeMargin.
	local room = width - 2 * CARD.edgeMargin - 2 * gap
	cardH = math.max(math.min(cardH, room / (3 * CARD.aspect)), 2 * CARD.border + 2)
	local cardW = cardH * CARD.aspect
	local scale = (cardH - 2 * CARD.border) / INNER.refHeight
	local corner = math.sqrt((width / 2) ^ 2 + (height * (1 - MS.glow.centreY)) ^ 2) -- farthest corner of the glow
	local title = math.clamp(height * MS.title.share, MS.title.minPx, MS.title.maxPx)
	return {
		width = width,
		height = height,
		cardW = cardW,
		cardH = cardH,
		gap = gap,
		left = (width - (3 * cardW + 2 * gap)) / 2,
		top = (height - height * CARD.bottomShare - cardH) / 2,
		contentScale = scale,
		refWidth = (cardW - 2 * CARD.border) / scale,
		raysPx = math.max(width, height) * MS.rays.share,
		glowPx = 2 * MS.glow.reach * corner,
		titleScale = title / HEADER_PX,
		titleBottom = height * MS.title.bottomShare,
	}
end

-- The card `delta` away from `index` among `count`, held at the ends (L:987: no wrap).
function ModeSelect.step(index: number, delta: number, count: number?): number
	return math.clamp(index + delta, 1, count or #MS.cards)
end

-- The design's seeded field (L:993-1002): Park-Miller from FIELD.seed, drawn shards -> bubbles -> sparks -> squishies in
-- the design's order and rounded as it rounds them (toFixed), so every run and every player sees the same field.
function ModeSelect.field(): Field
	local seed = FIELD.seed
	local function r(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local function fixed(n: number, digits: number): number
		local m = 10 ^ digits
		return math.round(n * m) / m
	end
	local S, B, P, T = FIELD.shard, FIELD.bubble, FIELD.spark, FIELD.toys
	local shards: { Shard } = {}
	for _, def in FIELD.shards do
		local dur = fixed(S.dur[1] + r() * S.dur[2], 2)
		local delay = fixed(-r() * S.delay, 2)
		table.insert(shards, {
			x = def[1],
			y = def[2],
			angle = def[3],
			length = def[4],
			color = def[5],
			dur = dur,
			delay = delay,
		})
	end
	local bubbles: { Bubble } = {}
	for _ = 1, B.count do
		local x = fixed(B.x[1] + r() * B.x[2], 1)
		local size = math.round(B.size[1] + r() * B.size[2])
		local dur = fixed(B.dur[1] + r() * B.dur[2], 1)
		local delay = fixed(-r() * B.delay, 1)
		table.insert(bubbles, { x = x, size = size, dur = dur, delay = delay })
	end
	local sparks: { Spark } = {}
	for _ = 1, P.count do
		local x = fixed(P.x[1] + r() * P.x[2], 1)
		local y = fixed(P.y[1] + r() * P.y[2], 1)
		local size = math.round(P.size[1] + r() * P.size[2])
		local dur = fixed(P.dur[1] + r() * P.dur[2], 2)
		local delay = fixed(-r() * P.delay, 2)
		table.insert(sparks, { x = x, y = y, size = size, dur = dur, delay = delay })
	end
	local toys: { Toy } = {}
	for index, place in T.places do
		local dur = fixed(T.dur[1] + r() * T.dur[2], 1)
		local delay = fixed(-r() * T.delay, 1)
		table.insert(
			toys,
			{ x = place[1], y = place[2], width = place[3], id = T.ids[index], dur = dur, delay = delay }
		)
	end
	return { shards = shards, bubbles = bubbles, sparks = sparks, toys = toys }
end

-- Public -------------------------------------------------------------------------------------------------------------

function ModeSelect.open(spec: Spec): ModeSelect
	local closed = false
	local picked = MS.startIndex
	local handles: { Scheduler.Handle } = {}
	local resized: RBXScriptConnection? = nil
	local root: Frame = Create("Frame", {
		Name = "SD_ModeSelect",
		BackgroundColor3 = Palette.ModeBase,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = true, -- every tap stays on the screen (no squeeze through it)
		ClipsDescendants = true,
		ZIndex = 1,
	})
	Focus.prepareGroup(root)

	-- The background (L:174-181), each layer one ZIndex up.
	picture(
		"Bg",
		"img.mode.bg",
		{ Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 1, Parent = root }
	)
	local rays = Theme.rays(root, "img.mode.rays", 1, MS.rays.alpha, MS.rays.spinS, MS.rays.centreY)
	if rays then
		rays.ZIndex = 2
	end
	local glows: { ImageLabel } = {}
	for index, id in MS.cards do
		glows[index] = picture("Glow_" .. id, "img.mode.glow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, MS.glow.centreY),
			ImageColor3 = color(INNER.looks[id].glow),
			ImageTransparency = if index == picked then 0 else 1,
			ZIndex = 3,
			Parent = root,
		})
	end
	local field = ModeSelect.field()
	local toyParts: { { holder: Frame, image: SquishyImage.SquishyImage, scale: UIScale, centre: Vector2 } } = {}
	for _, toy in field.toys do
		local holder = clear(
			"Toy_" .. toy.id,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(100, 100), ZIndex = 4, Parent = root }
		)
		local scale: UIScale = Create("UIScale", { Parent = holder })
		local image = SquishyImage.new(toy.id, { size = 100, parent = holder })
		for _, part in image.root:GetDescendants() do
			if part:IsA("ImageLabel") or part:IsA("ViewportFrame") then
				part.ImageTransparency = 1 - (1 - part.ImageTransparency) * FIELD.toys.alpha
			end
		end
		table.insert(toyParts, { holder = holder, image = image, scale = scale, centre = Vector2.zero })
	end
	local shardParts: { { box: Frame, image: ImageLabel } } = {}
	for index, shard in field.shards do
		local box = clear(
			"Shard_" .. index,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Rotation = shard.angle, ZIndex = 5, Parent = root }
		)
		local image = picture("Image", "img.mode.shard", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Stretch,
			ImageColor3 = color(shard.color),
			ZIndex = 5,
			Parent = box,
		})
		table.insert(shardParts, { box = box, image = image })
	end
	local bubbleParts: { { holder: Frame, image: ImageLabel, rim: UIStroke } } = {}
	for index, bubble in field.bubbles do
		local holder = clear("Bubble_" .. index, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(bubble.x / 100, 0, 1, FIELD.bubble.bottom),
			Size = UDim2.fromOffset(bubble.size, bubble.size),
			ZIndex = 6,
			Parent = root,
		})
		local image = picture("Image", "img.mode.bubble", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ImageTransparency = 1,
			ZIndex = 6,
			Parent = holder,
		})
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = image })
		local rim = Theme.stroke(WHITE, FIELD.bubble.rim, image, 1)
		inner(rim)
		table.insert(bubbleParts, { holder = holder, image = image, rim = rim })
	end
	local sparkParts: { ImageLabel } = {}
	for index, spark in field.sparks do
		sparkParts[index] = picture("Spark_" .. index, "img.duel.star", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(spark.x / 100, spark.size / 2, spark.y / 100, spark.size / 2),
			Size = UDim2.fromOffset(0, 0),
			ImageTransparency = 1,
			ZIndex = 7,
			Parent = root,
		})
	end
	picture(
		"Vignette",
		"img.mode.vignette",
		{ Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 8, Parent = root }
	)

	-- "SELECT A GAME MODE" (L:212-214) and the X (L:215).
	local header = Theme.label({
		Name = "Mode_Title",
		Text = Strings.hud.modeSelect.title,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(
			Theme.textWidth(Strings.hud.modeSelect.title, "Hero") + MEASURE_MARGIN_PX,
			Theme.lineHeight("Hero")
		),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 10,
		Parent = root,
	}, "Hero")
	Theme.stickerText(header, "modeHeader")
	oneLine(header)
	local headerScale: UIScale = Create("UIScale", { Parent = header })
	local X = MS.close
	local handle = {} :: ModeSelect
	local closeButton = Button.new({
		name = "Mode_Close",
		text = Strings.hud.modeSelect.close,
		kind = "close",
		accent = "cancelX",
		height = X.face,
		radius = X.radius,
		border = X.border,
		lip = X.lip,
		highlight = { px = X.highlightPx, a = 0.5 },
		bevel = { px = 0, a = 0 },
		iconSize = X.iconPx,
		fx = "x",
		parent = root,
		onActivated = function()
			handle:close()
		end,
	})
	closeButton.root.AnchorPoint = Vector2.new(1, 0)
	closeButton.root.ZIndex = 11

	-- The background fades in as one (L:174 sdFade); the cards pop in on their own.
	local backgroundFade = Tweens.fadeGroup(root)

	-- The cards (L:183-210).
	local row = clear("Mode_Cards", { Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = root })
	local cards: { Card } = {}
	for index, id in MS.cards do
		local look = INNER.looks[id]
		local texts = Strings.hud.modeSelect.cards[id]
		local slot = clear("Mode_" .. id, { ZIndex = if index == picked then 2 else 1, Parent = row })
		local pop = clear("Pop", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Parent = slot,
		})
		local click: TextButton = Create("TextButton", {
			Name = "Pick",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Selectable = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Parent = pop,
		})
		-- The glow ring (L:186): a 6 px ring at .35 round the card 6 px out, the 80 px glow round it.
		local ringInset = CARD.ring.inset
		local ring = clear("Ring", {
			Position = UDim2.fromOffset(-ringInset, -ringInset),
			Size = UDim2.new(1, 2 * ringInset, 1, 2 * ringInset),
			ZIndex = 1,
			Parent = click,
		})
		Theme.corner(CARD.ring.radius, ring)
		local ringStroke = Theme.stroke(WHITE, CARD.ring.width, ring, 1)
		local glowPad = CARD.glow.pad
		local ringGlow = picture("Glow", "img.mode.cardGlow", {
			Position = UDim2.fromOffset(-glowPad, -glowPad),
			Size = UDim2.new(1, 2 * glowPad, 1, 2 * glowPad),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(table.unpack(CARD.glow.slice)),
			ImageColor3 = color(look.glow),
			ImageTransparency = 1,
			ZIndex = 1,
			Parent = ring,
		})
		-- The card (L:187): the soft shadow, the lip, the face and its border.
		local shadowPad = CARD.shadow.pad
		picture("Shadow", "img.mode.cardShadow", {
			Position = UDim2.fromOffset(-shadowPad, CARD.shadow.y - shadowPad),
			Size = UDim2.new(1, 2 * shadowPad, 1, 2 * shadowPad),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(table.unpack(CARD.shadow.slice)),
			ImageColor3 = Palette.ModeShadow,
			ImageTransparency = 1 - CARD.shadow.alpha,
			ZIndex = 2,
			Parent = click,
		})
		local lip: Frame = Create("Frame", {
			Name = "Lip",
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, CARD.lip),
			Size = UDim2.fromScale(1, 1),
			Active = false,
			ZIndex = 3,
			Parent = click,
		})
		Theme.corner(CARD.radius, lip)
		local face: Frame = Create("Frame", {
			Name = "Face",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			ZIndex = 4,
			Parent = click,
		})
		Theme.corner(CARD.radius, face)
		Create("UIGradient", { Rotation = look.rotation, Color = sequence(look.stops), Parent = face })
		local b = CARD.border
		local body: CanvasGroup = Create("CanvasGroup", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(b, b),
			Size = UDim2.new(1, -2 * b, 1, -2 * b),
			Active = false,
			ZIndex = 5,
			Parent = click,
		})
		Theme.corner(CARD.radius - b, body)
		local borderBox = clear("Border", { Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = click })
		Theme.corner(CARD.radius, borderBox)
		local border = Theme.stroke(if index == picked then WHITE else INK, b, borderBox)
		inner(border)

		-- The content box in ref px (L:188-205).
		local ref = clear("Ref", { Size = UDim2.fromOffset(100, INNER.refHeight), ZIndex = 1, Parent = body })
		local refScale: UIScale = Create("UIScale", { Parent = ref })
		local cardRays = Theme.rays(ref, "img.mode.raysCard", 1, INNER.rays.alpha, INNER.rays.spinS, INNER.rays.centreY)
		if cardRays then
			cardRays.ZIndex = 1
		end
		local ghost = Theme.label({
			Name = "Ghost",
			Text = texts.ghost,
			AutomaticSize = Enum.AutomaticSize.None,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, INNER.ghostTop),
			Size = UDim2.new(1, 0, 0, Theme.lineHeight("ModeGhost")),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = WHITE,
			TextTransparency = 1 - INNER.ghostAlpha,
			TextWrapped = false,
			ZIndex = 2,
			Parent = ref,
		}, "ModeGhost")
		Theme.noOutline(ghost)
		oneLine(ghost)
		local A = INNER.art
		local art = clear("Art", { ZIndex = 3, Parent = ref })
		picture("Shadow", look.mask, {
			Position = UDim2.fromOffset(0, A.shadowCq * CQ),
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = INK,
			ImageTransparency = 1 - A.shadowAlpha,
			ZIndex = 3,
			Parent = art,
		})
		picture("Picture", look.art, { Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = art })
		local artShineImage = picture("Shine", look.mask, { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = art })
		local SH = INNER.shine
		local artShine = shineGradient(artShineImage, 0, SH.band, SH.edge, SH.alpha, SH.rotation)
		local fade: Frame = Create("Frame", {
			Name = "Fade",
			BackgroundColor3 = color(look.deep),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, INNER.fade.share),
			Active = false,
			ZIndex = 6,
			Parent = ref,
		})
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(INNER.fade.at, 0),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = fade,
		})
		-- The column (L:195-204): the title, the sub pill and PLAY, from the bottom up.
		local column = clear("Column", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1 - INNER.column.bottom),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = ref,
		})
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, INNER.column.gapCq * CQ),
			Parent = column,
		})
		local lines = select(2, string.gsub(texts.title, "\n", "\n")) + 1
		local lineH = Theme.lineHeight("ModeTitle")
		local titleH = math.ceil(lineH * (1 + (lines - 1) * INNER.titleLineHeight))
		local titleBox =
			clear("TitleBox", { Size = UDim2.fromOffset(100, titleH), LayoutOrder = 1, ZIndex = 7, Parent = column })
		local titleScale: UIScale = Create("UIScale", { Parent = titleBox })
		local title = Theme.label({
			Name = "Title",
			Text = texts.title,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			LineHeight = INNER.titleLineHeight,
			TextWrapped = false,
			ZIndex = 7,
			Parent = titleBox,
		}, "ModeTitle")
		Theme.stickerText(title, "modeTitle")
		oneLine(title) -- its two lines are its own "\n", never a wrap
		local titleWidth = Theme.textBounds(texts.title, "ModeTitle").X + MEASURE_MARGIN_PX
		local subW = Theme.textWidth(texts.sub, "Small") + 2 * INNER.sub.padXCq * CQ + MEASURE_MARGIN_PX
		local subH = Theme.textSize("Small") + 2 * INNER.sub.padYCq * CQ
		local sub: Frame = Create("Frame", {
			Name = "Sub",
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(subW, subH),
			LayoutOrder = 2,
			Active = false,
			ZIndex = 7,
			Parent = column,
		})
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = sub })
		local subLabel = Theme.label({
			Name = "Label",
			Text = texts.sub,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = WHITE,
			TextWrapped = false,
			ZIndex = 8,
			Parent = sub,
		}, "Small")
		Theme.noOutline(subLabel)
		oneLine(subLabel)
		-- PLAY (L:198-203): the picture's box at the holder's top + 1 cq, popping about its middle.
		local boxW, boxH = PLAY.boxW * PLAY_K, PLAY.boxH * PLAY_K
		local playHolder = clear("PlayBox", {
			Size = UDim2.fromOffset(boxW, PLAY.topCq * CQ + boxH),
			LayoutOrder = 3,
			Visible = index == picked,
			ZIndex = 7,
			Parent = column,
		})
		local playPop = clear("Pop", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(boxW / 2, PLAY.topCq * CQ + boxH / 2),
			Size = UDim2.fromOffset(boxW, boxH),
			ZIndex = 7,
			Parent = playHolder,
		})
		local playRect = {
			Position = UDim2.fromOffset(-PLAY.pad * PLAY_K, -PLAY.pad * PLAY_K),
			Size = UDim2.fromOffset(PLAY.canvasW * PLAY_K, PLAY.canvasH * PLAY_K),
		}
		local play: ImageButton = Create("ImageButton", {
			Name = "Play",
			BackgroundTransparency = 1,
			Image = AssetTable.image("img.mode.play") or "",
			AutoButtonColor = false,
			Position = playRect.Position,
			Size = playRect.Size,
			ZIndex = 7,
			Parent = playPop,
		})
		Focus.decorate(play, 12)
		local playShineImage = picture("Shine", "img.mode.playMask", {
			Position = playRect.Position,
			Size = playRect.Size,
			ZIndex = 8,
			Parent = playPop,
		})
		local PS = PLAY.shine
		local boxShare = PLAY.boxW / PLAY.canvasW
		local playShine =
			shineGradient(playShineImage, PLAY.pad / PLAY.canvasW, PS.band * boxShare, 0, PS.alpha, PS.rotation)
		local dim: Frame = Create("Frame", {
			Name = "Dim",
			BackgroundColor3 = Palette.ModeDim,
			BackgroundTransparency = if index == picked then 1 else 1 - CARD.dimAlpha,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			ZIndex = 2,
			Parent = body,
		})
		local card: Card = {
			id = id,
			slot = slot,
			pop = pop,
			click = click,
			border = border,
			ringStroke = ringStroke,
			ringGlow = ringGlow,
			bgGlow = glows[index],
			dim = dim,
			ref = ref,
			refScale = refScale,
			rays = cardRays,
			art = art,
			artLoop = nil,
			artSize = 0,
			artShine = artShine,
			titleBox = titleBox,
			titleScale = titleScale,
			titleWidth = titleWidth,
			playHolder = playHolder,
			playPop = playPop,
			play = play,
			playShine = playShine,
			looks = {},
			pickTrack = nil,
		}
		cards[index] = card
		click.Activated:Connect(function()
			handle:pick(index, true)
		end)
		play.Activated:Connect(function()
			if index == picked then
				handle:play()
			end
		end)
	end

	-- The picked card's look (L:186-187, L:206, L:176): border, ring, glow, dim; `ms` 0 sets it at once.
	local function applyLook(card: Card, on: boolean, animate: boolean)
		for _, tween in card.looks do
			tween:Cancel()
		end
		table.clear(card.looks)
		local function to(object: Instance, goals: { [string]: any }, ms: number)
			if animate then
				table.insert(card.looks, Tweens.fade(object, goals, ms, LOOK_STYLE, LOOK_DIRECTION))
			else
				for property, value in goals do
					(object :: any)[property] = value
				end
			end
		end
		to(card.border, { Color = if on then WHITE else INK }, CARD.borderMs)
		to(card.ringStroke, { Transparency = if on then 1 - CARD.ring.alpha else 1 }, CARD.ringMs)
		to(card.ringGlow, { ImageTransparency = if on then 0 else 1 }, CARD.ringMs)
		to(card.dim, { BackgroundTransparency = if on then 1 else 1 - CARD.dimAlpha }, CARD.dimMs)
		to(card.bgGlow, { ImageTransparency = if on then 0 else 1 }, MS.glow.ms)
	end

	-- The picked card's scale (L:185: 1, else .82, .5 s cubic-bezier(.22,1.3,.36,1)).
	local function applyScale(card: Card, on: boolean, animate: boolean)
		local running = card.pickTrack
		if running then
			running:cancel()
			card.pickTrack = nil
		end
		local target = if on then 1 else CARD.other
		local current = card.click:FindFirstChild(POSE_SCALE)
		local from = if current and current:IsA("UIScale") then current.Scale else target
		if animate and from ~= target and not Tweens.reducedMotion() then
			local track = Tweens.keyframes(card.click, { { at = 0, scale = from }, { at = 1, scale = target } }, {
				ms = CARD.pickMs,
				curve = "modePick",
			})
			card.pickTrack = track
			Scheduler.add(track, "render")
		else
			Tweens.poser(card.click):set({ scale = target })
		end
	end

	-- A one-shot pop (sdPop) of `holder` with everything in it fading in: scale, lift and turn through Tweens.poser, the
	-- fade through Tweens.fadeGroup; under ReducedMotion only the fade. `after` runs once it ended.
	local function popIn(
		holder: GuiObject,
		frames: { Tweens.Pose },
		ms: number,
		delayMs: number,
		curve: string,
		after: (() -> ())?
	)
		local fadeGroup = Tweens.fadeGroup(holder)
		local poser = Tweens.poser(holder)
		local reduced = Tweens.reducedMotion()
		local elapsed = 0
		local function frame(u: number): boolean
			local pose = Tweens.poseAt(frames, u, curve)
			if not reduced then
				poser:set({ x = pose.x, y = pose.y, rot = pose.rot, scale = pose.scale })
			end
			fadeGroup:setAlpha(pose.alpha or 1)
			return u < 1
		end
		frame(0)
		table.insert(
			handles,
			Scheduler.add(function(dt: number): boolean
				if closed then
					return false
				end
				elapsed += dt
				local t = elapsed - delayMs / 1000
				if t < 0 then
					return true
				end
				if frame(math.min(t / (ms / 1000), 1)) then
					return true
				end
				fadeGroup:restore()
				if after then
					after()
				end
				return false
			end, "render")
		)
	end

	local layoutNow = ModeSelect.layout(Vector2.new(1, 1))

	-- Everything the screen's size moves (the vw / vh / vmax parts, the cards and their innards, the title and the X).
	local function place()
		local size = root.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local L = ModeSelect.layout(size)
		layoutNow = L
		if rays then
			rays.Size = UDim2.fromOffset(L.raysPx, L.raysPx)
		end
		for _, glow in glows do
			glow.Size = UDim2.fromOffset(L.glowPx, L.glowPx)
		end
		local vw = L.width / 100
		for index, toy in field.toys do
			local part = toyParts[index]
			local w = toy.width * vw
			part.scale.Scale = w / 100
			part.centre = Vector2.new(toy.x / 100 * L.width + w / 2, toy.y / 100 * L.height + w / 2)
			part.holder.Position = UDim2.fromOffset(part.centre.X, part.centre.Y)
		end
		for index, shard in field.shards do
			-- L:178: rotated about its left middle (transform-origin 0 50%); Roblox turns about the centre.
			local len = shard.length * vw
			local thick = len * FIELD.shard.thick
			local a = math.rad(shard.angle)
			local x = shard.x / 100 * L.width + math.cos(a) * len / 2
			local y = shard.y / 100 * L.height + thick / 2 + math.sin(a) * len / 2
			local box = shardParts[index].box
			box.Position = UDim2.fromOffset(x, y)
			box.Size = UDim2.fromOffset(len, thick)
		end
		headerScale.Scale = L.titleScale
		-- The whole width (before its scale): centred, the line never runs out of room.
		header.Size = UDim2.fromOffset(L.width / L.titleScale, header.Size.Y.Offset)
		header.Position = UDim2.new(0.5, 0, 1, -L.titleBottom)
		closeButton.root.Position = UDim2.new(1, -X.right, 0, X.top)
		for index, card in cards do
			card.slot.Position = UDim2.fromOffset(L.left + (index - 1) * (L.cardW + L.gap), L.top)
			card.slot.Size = UDim2.fromOffset(L.cardW, L.cardH)
			card.refScale.Scale = L.contentScale
			card.ref.Size = UDim2.fromOffset(L.refWidth, INNER.refHeight)
			if card.rays then
				local px = INNER.rays.share * L.refWidth
				card.rays.Size = UDim2.fromOffset(px, px)
			end
			local A = INNER.art
			local artSize = A.share * L.refWidth
			card.art.Position = UDim2.fromOffset(A.left * L.refWidth, A.top * INNER.refHeight)
			card.art.Size = UDim2.fromOffset(artSize, artSize)
			if math.abs(artSize - card.artSize) > 0.5 then
				-- The art's loop moves in px of the art's size (L:1359-1363's % of itself): made again for a new size.
				card.artSize = artSize
				local old = card.artLoop
				if old then
					old:remove()
				end
				local loop = INNER.looks[card.id].loop
				local frames: { Tweens.Pose } = {}
				for _, f in loop.frames do
					table.insert(frames, {
						at = f.at,
						x = if f.x then f.x * artSize else nil,
						y = if f.y then f.y * artSize else nil,
						scale = f.scale,
						rot = f.rot,
					})
				end
				card.artLoop = UiIdle.addFrames(card.art, frames, { periodS = loop.periodS, curve = loop.curve })
			end
			card.titleBox.Size = UDim2.fromOffset(L.refWidth, card.titleBox.Size.Y.Offset)
			card.titleScale.Scale = math.min(1, INNER.titleFit * L.refWidth / math.max(card.titleWidth, 1))
		end
	end

	-- The field's loops (L:177-180, mpDrift / mpShard / mpRise + mpWob / mpTwinkle) and the shines (L:192, L:200), one
	-- render step for all; at rest (each loop's 0% pose) under ReducedMotion.
	local start = os.clock()
	local easeInOut = Tweens.curve("easeInOut")
	local function stepField(now: number)
		local still = Tweens.reducedMotion()
		local L = layoutNow
		for index, toy in field.toys do
			local part = toyParts[index]
			local v = if still then 0 else swing(loopU(now, start, toy.dur, toy.delay), easeInOut)
			local T = FIELD.toys
			part.holder.Position = UDim2.fromOffset(part.centre.X + T.drift[1] * v, part.centre.Y + T.drift[2] * v)
			part.holder.Rotation = -T.tilt + 2 * T.tilt * v
		end
		for index, shard in field.shards do
			local v = if still then 0 else swing(loopU(now, start, shard.dur, shard.delay), easeInOut)
			local image = shardParts[index].image
			local len = shard.length * L.width / 100
			image.Position = UDim2.new(0.5, FIELD.shard.move * len * v, 0.5, 0)
			image.Size = UDim2.fromScale(1 + (FIELD.shard.stretch - 1) * v, 1)
		end
		local B = FIELD.bubble
		local wobble = if still then 0 else swing(((now - start) / B.wobbleS) % 1, easeInOut)
		for index, bubble in field.bubbles do
			local part = bubbleParts[index]
			local u = if still then 0 else loopU(now, start, bubble.dur, bubble.delay)
			local alpha = if u < B.fadeIn then u / B.fadeIn elseif u <= B.fadeOut then 1 else (1 - u) / (1 - B.fadeOut)
			part.holder.Position = UDim2.new(bubble.x / 100, 0, 1, B.bottom - B.rise * L.height * u)
			part.image.Position = UDim2.new(0.5, -B.wobblePx + 2 * B.wobblePx * wobble, 0.5, 0)
			part.image.Size = UDim2.fromScale(1 + B.squash * wobble, 1 - B.squash * wobble)
			part.image.ImageTransparency = 1 - alpha
			part.rim.Transparency = 1 - B.rimAlpha * alpha
		end
		for index, spark in field.sparks do
			local v = if still then 0 else swing(loopU(now, start, spark.dur, spark.delay), easeInOut)
			local image = sparkParts[index]
			image.Size = UDim2.fromOffset(spark.size * v, spark.size * v)
			image.Rotation = FIELD.spark.spin * v
			image.ImageTransparency = 1 - v
		end
		local SH, PS = INNER.shine, PLAY.shine
		local playShare = PLAY.boxW / PLAY.canvasW
		for _, card in cards do
			local period = INNER.looks[card.id].shineS
			local u = if still then 0 else ((now - start) / period) % 1
			card.artShine.Offset = Vector2.new(shineAt(u, SH.from, SH.to, SH.hold) * SH.band, 0)
			local p = if still then 0 else ((now - start) / PS.periodS) % 1
			card.playShine.Offset = Vector2.new(shineAt(p, PS.from, PS.to, PS.hold) * PS.band * playShare, 0)
		end
	end

	-- Input (L:986-988): Left / Right pick, Enter / Space play (ButtonA too: on the X it closes). In a pcall: the
	-- Edit-mode test runner has no player input to bind.
	local function bind()
		pcall(function()
			ContextActionService:BindActionAtPriority(ACTION_LEFT, function(_, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin then
					handle:pick(ModeSelect.step(picked, -1), true)
				end
				return Enum.ContextActionResult.Sink
			end, false, ACTION_PRIORITY, Enum.KeyCode.Left, Enum.KeyCode.DPadLeft)
			ContextActionService:BindActionAtPriority(ACTION_RIGHT, function(_, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin then
					handle:pick(ModeSelect.step(picked, 1), true)
				end
				return Enum.ContextActionResult.Sink
			end, false, ACTION_PRIORITY, Enum.KeyCode.Right, Enum.KeyCode.DPadRight)
			ContextActionService:BindActionAtPriority(
				ACTION_PLAY,
				function(_, state: Enum.UserInputState)
					if state == Enum.UserInputState.Begin then
						local selected = GuiService.SelectedObject
						if selected and (selected == closeButton.root or selected:IsDescendantOf(closeButton.root)) then
							handle:close()
						else
							handle:play()
						end
					end
					return Enum.ContextActionResult.Sink
				end,
				false,
				ACTION_PRIORITY,
				Enum.KeyCode.Return,
				Enum.KeyCode.KeypadEnter,
				Enum.KeyCode.Space,
				Enum.KeyCode.ButtonA
			)
		end)
	end

	-- The handle ------------------------------------------------------------------------------------------------------

	handle.root = root

	function handle.pick(_: ModeSelect, index: number, animate: boolean?)
		local target = ModeSelect.step(index, 0)
		if closed or target == picked then
			return
		end
		Button.playSound(CLICK_SOUND, TAB_PITCH)
		local before = picked
		picked = target
		local move = animate == true
		for i, card in cards do
			local on = i == picked
			card.slot.ZIndex = if on then 2 else 1
			if i == before or on then
				applyLook(card, on, move)
				applyScale(card, on, move)
				card.playHolder.Visible = on
			end
		end
		local card = cards[picked]
		if move then
			popIn(card.playPop, CARD.popFrames, PLAY.popMs, PLAY.popDelayMs, "slot")
		end
		local selected = GuiService.SelectedObject
		if selected == nil or selected:IsDescendantOf(root) then
			Focus.select(card.play)
		end
	end

	function handle.picked(_: ModeSelect): string
		return MS.cards[picked]
	end

	function handle.play(_: ModeSelect)
		if closed then
			return
		end
		local id = MS.cards[picked]
		handle:close(true)
		spec.onPlay(id)
	end

	function handle.isOpen(_: ModeSelect): boolean
		return not closed
	end

	function handle.close(_: ModeSelect, quiet: boolean?)
		if closed then
			return
		end
		closed = true
		if not quiet then
			Button.playSound(BACK_SOUND)
		end
		pcall(function()
			for _, action in { ACTION_LEFT, ACTION_RIGHT, ACTION_PLAY } do
				ContextActionService:UnbindAction(action)
			end
		end)
		for _, h in handles do
			h:disconnect()
		end
		if resized then
			resized:Disconnect()
		end
		for _, card in cards do
			local track = card.pickTrack
			if track then
				track:cancel()
			end
			for _, tween in card.looks do
				tween:Cancel()
			end
		end
		for _, part in toyParts do
			part.image:destroy()
		end
		closeButton:destroy()
		root:Destroy() -- its UiIdle loops (the rays, the art) end with it
		if spec.onClose then
			spec.onClose()
		end
	end

	-- Build ----------------------------------------------------------------------------------------------------------

	for i, card in cards do
		local on = i == picked
		applyLook(card, on, false)
		applyScale(card, on, false)
	end
	root.Parent = spec.layer
	place()
	resized = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	stepField(os.clock())
	table.insert(
		handles,
		Scheduler.add(function(_dt: number, now: number): boolean
			if closed then
				return false
			end
			stepField(now)
			return true
		end, "render")
	)
	-- The screen fades in (L:174), the cards pop in 70 ms apart (L:184, L:1364), PLAY on the picked one (L:199).
	backgroundFade:setAlpha(0)
	local fadeIn = 0
	table.insert(
		handles,
		Scheduler.add(function(dt: number): boolean
			if closed then
				return false
			end
			fadeIn += dt
			local u = math.min(fadeIn / (MS.fadeMs / 1000), 1)
			backgroundFade:setAlpha(Tweens.curve("ease")(u))
			if u >= 1 then
				backgroundFade:restore()
				return false
			end
			return true
		end, "render")
	)
	for i, card in cards do
		popIn(card.pop, CARD.popFrames, CARD.popMs, (i - 1) * CARD.popStepMs, "search", function()
			applyLook(card, i == picked, false) -- a pick during the pop: its fade put the old look back
		end)
	end
	popIn(cards[picked].playPop, CARD.popFrames, PLAY.popMs, PLAY.popDelayMs, "slot")
	bind()
	Button.playSound(CLICK_SOUND, TAB_PITCH)
	Focus.select(cards[picked].play)
	return handle
end

return ModeSelect
