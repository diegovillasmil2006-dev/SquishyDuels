--!strict
-- DeathCard (client only). Match HUD M7 (2026-10-17; plan work/matchhud2/PLAN.md §4 M7 = v1 M5, §12; `M:n` = "Squishy
-- Duels Match HUD.dc.html" line n): the "squished by" card, a MatchHudController piece ("card"). It shows when you are
-- squished and the match goes on (MatchHudFormat.cardShows, M:536), comes in with M:558's 620 ms track and leaves with
-- M:565's 260 ms one at your respawn (M:551-553), at once when the live phases end, and on its own one respawn wait
-- after a K.O. that left you out of team lives (TDM: nothing brings you back).
--   header (M:157-162)  [FINAL KILL] [You] squished by [killer]
--   banner (M:164-175)  the killer's squishy: its rarity's gradient (115deg), dots, turning rays, the rarity pill, its
--                       name, its "title" (M:388), its picture (smToyIn, then smToyBob), two twinkles, a shine
--   info row (M:176-191) the killer's head, name, @handle, GRIP LEVEL and WIN STREAK boxes (owner: win streak shown;
--                       each box hides when the player has no such attribute: bots)
-- A K.O. with nobody to blame (storm, fall: owner 2026-10-16, [P]): "squished by THE STORM / A FALL", the banner in the
-- cause's colours with its name and a tip, no picture and no info row (MatchHudFormat.causeCard).
-- Place (MatchHudFormat.cardPlace): bottom left (M:156); with touch controls above the thumbstick zone, shrunk to fit
-- (owner: never over the thumbstick corner). The card's rect goes to ctx.shared.cardRect for the RESPAWNING bar.
-- Sounds and feel (M:547-548, M:560): match.knockedOut (ui.error while it has no id), match.splat at
-- Config.Audio.matchHud.splatYou (sfx.impactSoft), the HUD's jolt (UiFx.jolt 10, the camera-shake setting), then
-- match.whoosh (sfx.inspect.whoosh) and ui.click at uiPitch.card 260 ms later. Diego's kill banner never shows for your
-- own K.O. (it is the killer's), so nothing here doubles it.
-- Pictures while their ids are nil: img.fx.raysCard -> img.fx.rays, img.fx.dotsCard -> img.fx.dots (a 26 px tile
-- drawn 24), img.icon.grip -> img.icon.squeeze, img.fx.spark -> small turned squares. M13's final card: build(...,
-- final = true) adds the FINAL KILL chip; `bottomFinal` is M13's to place.
-- Reading: CanvasGroups hold the card (its fade) and its body (the rounded clip: ClipsDescendants ignores UICorner).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local IconGlyph = require(UI.Components.IconGlyph)
local Layout = require(UI.Layout)
local MatchHudFormat = require(UI.MatchHudFormat)
local RarityTag = require(UI.Components.RarityTag)
local SquishyImage = require(UI.Components.SquishyImage)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)
local MatchKit = require(script.Parent.MatchKit)

-- Types

export type BuildSpec = {
	killer: MatchKit.Who?, -- nil: nobody to blame
	victim: MatchKit.Who,
	cause: string?,
	final: boolean?,
	preview: boolean,
}

export type Built = {
	root: Frame, -- placed by the caller; its UIScale "SD_Fit"
	fit: UIScale,
	pose: CanvasGroup, -- the show / hide tracks
	toy: Frame?, -- smToyIn's holder
	size: Vector2, -- base px before SD_Fit
}

type Shown = {
	built: Built,
	born: number, -- os.clock()
	at: number, -- the K.O.'s server time
	hiding: number?, -- os.clock() the hide began
	poser: Tweens.Poser,
	toyPoser: Tweens.Poser?,
}

-- Constants

local CFG = Config.UI.Match.card
local MATCH = Config.Match
local AUDIO = Config.Audio
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local LIVE_PHASES: { [string]: boolean } = { Active = true, Overtime = true }
local Z = 3
local WHITE = Color3.new(1, 1, 1)
local KEY_RAYS, KEY_RAYS_FALLBACK = "img.fx.raysCard", "img.fx.rays"
local KEY_DOTS, KEY_DOTS_FALLBACK = "img.fx.dotsCard", "img.fx.dots"
local KEY_GRIP, KEY_GRIP_FALLBACK = "img.icon.grip", "img.icon.squeeze"
local KEY_FLAME = "img.icon.flame"
local KEY_SPARK = "img.fx.spark"
local ATTR_GRIP = "SD_GripLevel" -- NameplateController's
local ATTR_STREAK = "SD_WinStreak" -- Match HUD M2
local SPARK_SHARE = 0.62 -- reading: the turned square's side for a 4-point star of that size
local CAUSE_COLORS: { [string]: { Color3 } } = { -- [P] the same as the feed's cause chips
	storm = { Palette.StickerPurpleBarTop, Palette.StickerPurpleBarEnd },
	outOfBounds = { Palette.StickerBlueBarTop, Palette.StickerBlueBarEnd },
	other = { Palette.StickerCardTop, Palette.StickerCardBottom },
}
local BOB_FRAMES = { { at = 0, y = 0 }, { at = 0.5, y = -CFG.toyBob.risePx }, { at = 1, y = 0 } }

-- Module table

local DeathCard = {}

-- Private

local function key(wanted: string, fallback: string): string
	return if AssetTable.image(wanted) then wanted else fallback
end

local function frame(props: { [string]: any }): Frame
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or Z
	props.Active = false
	if props.BackgroundColor3 == nil then
		props.BackgroundTransparency = 1
	end
	return Create("Frame", props)
end

-- A design pill (M:159, M:161): the player's gradient, their name.
local function pill(text: string, look: MatchHudFormat.PlayerLook): (Frame, number)
	local spec = CFG.pill
	return MatchKit.chip({
		name = "Pill",
		text = text,
		role = spec.role,
		height = spec.height,
		padX = spec.padX,
		border = spec.border,
		top = look.top,
		faceEnd = look.faceEnd,
		z = Z,
	})
end

-- The rarity's light / main / deep stops (lib:12-17), else its card face.
local function rarityStops(squishyId: string): { Color3 }
	local def = Catalog.get(squishyId)
	local style = if def then RarityStyle.get(def.rarity) else nil
	if style == nil then
		return { Palette.StickerCardTop, Palette.StickerPillTop, Palette.StickerCardBottom }
	end
	local ui = style.ui
	return { ui.light or ui.faceTop, ui.base or style.color, ui.dark or ui.faceBottom }
end

local function header(parent: Frame, spec: BuildSpec)
	local cfg = CFG.header
	local items: { { object: any, width: number } } = {}
	if spec.final then
		local chipCfg = CFG.finalChip
		local chip, width = MatchKit.chip({
			name = "FinalKill",
			text = Strings.matchHud.card.finalKill,
			role = chipCfg.role,
			height = chipCfg.height,
			padX = chipCfg.padX,
			border = chipCfg.border,
			top = Palette.StickerYellowTop,
			faceEnd = Palette.StickerYellowEnd,
			z = Z,
		})
		table.insert(items, { object = chip, width = width })
	end
	local you, youWidth = pill(spec.victim.name, spec.victim.look)
	table.insert(items, { object = you, width = youWidth })
	local by, bySize =
		MatchKit.label({ name = "By", text = Strings.matchHud.card.squishedBy, role = CFG.byRole, z = Z })
	table.insert(items, { object = by, width = bySize.X })
	local killer = spec.killer
	if killer then
		local them, themWidth = pill(killer.name, killer.look)
		table.insert(items, { object = them, width = themWidth })
	else
		local words = MatchHudFormat.causeCard(spec.cause)
		local colors = CAUSE_COLORS[spec.cause or ""] or CAUSE_COLORS.other
		local cause, causeWidth = pill(words.pill, { text = WHITE, top = colors[1], faceEnd = colors[2] })
		table.insert(items, { object = cause, width = causeWidth })
	end
	local x = cfg.padLeft
	for _, item in items do
		local object = item.object :: GuiObject
		object.AnchorPoint = Vector2.new(0, 0.5)
		object.Position = UDim2.fromOffset(x, cfg.height / 2)
		object.Parent = parent
		x += item.width + cfg.gap
	end
end

local function twinkle(parent: Frame, spec: any)
	local size = spec.size
	local holder: GuiObject
	local spark = AssetTable.image(KEY_SPARK)
	if spark then
		holder = Create("ImageLabel", {
			Name = "Twinkle",
			BackgroundTransparency = 1,
			Image = spark,
			ImageColor3 = if spec.cream then Palette.StickerCreamYellow else WHITE,
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(spec.x, spec.y),
			ZIndex = Z,
			Active = false,
			Parent = parent,
		})
	else
		local side = math.round(size * SPARK_SHARE)
		holder = frame({
			Name = "Twinkle",
			BackgroundColor3 = if spec.cream then Palette.StickerCreamYellow else WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(spec.x + size / 2, spec.y + size / 2),
			Size = UDim2.fromOffset(side, side),
			Rotation = 45,
			Parent = parent,
		})
	end
	UiIdle.add(holder, "twinkle", { periodS = CFG.banner.twinkleS, delayS = spec.delayS })
end

local function banner(parent: GuiObject, width: number, spec: BuildSpec): Frame?
	local cfg = CFG.banner
	local killer = spec.killer
	local stops = if killer
		then rarityStops(killer.squishyId)
		else (function(): { Color3 }
			local colors = CAUSE_COLORS[spec.cause or ""] or CAUSE_COLORS.other
			return { colors[1], colors[1]:Lerp(colors[2], 0.5), colors[2] }
		end)()
	local band = frame({
		Name = "Banner",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(width, cfg.height),
		ClipsDescendants = true,
		Parent = parent,
	})
	Create("UIGradient", {
		Rotation = cfg.rotation,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, stops[1]),
			ColorSequenceKeypoint.new(cfg.mid, stops[2]),
			ColorSequenceKeypoint.new(1, stops[3]),
		}),
		Parent = band,
	})
	local dots = AssetTable.image(key(KEY_DOTS, KEY_DOTS_FALLBACK))
	if dots then
		Create("ImageLabel", {
			Name = "Dots",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = dots,
			ImageTransparency = 1 - cfg.dots.alpha,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(cfg.dots.tile, cfg.dots.tile),
			ZIndex = Z,
			Active = false,
			Parent = band,
		})
	end
	local raysAt = frame({
		Name = "RaysAt",
		Position = UDim2.fromOffset(width - cfg.rays.fromRight, cfg.height / 2),
		Size = UDim2.fromOffset(0, 0),
		Parent = band,
	})
	Theme.rays(raysAt, key(KEY_RAYS, KEY_RAYS_FALLBACK), cfg.rays.size, cfg.rays.alpha, cfg.rays.spinS)
	-- The text column (M:166-170).
	local column = frame({ Name = "Text", Position = UDim2.fromOffset(cfg.textX, cfg.textY), Parent = band })
	local y = 0
	local nameText, lineText
	if killer then
		local def = Catalog.get(killer.squishyId)
		if def then
			local tag = RarityTag.new({ name = "Rarity", rarity = def.rarity, variant = "detail", parent = column })
			y += RarityTag.measurePill(def.rarity, "detail").pillHeight + cfg.textGap
			tag.root.ZIndex = Z
		end
		nameText = if def then Strings.resolve(def.nameKey) or killer.squishyId else killer.squishyId
		lineText =
			Strings.format(Strings.matchHud.card.title, { title = MatchHudFormat.squishyTitle(killer.squishyId) })
	else
		local words = MatchHudFormat.causeCard(spec.cause)
		nameText, lineText = words.name, words.line
	end
	local nameLabel, nameSize = MatchKit.label({ name = "Name", text = nameText, role = cfg.nameRole, z = Z })
	nameLabel.Position = UDim2.fromOffset(0, y)
	nameLabel.Parent = column
	y += nameSize.Y + cfg.textGap
	local lineLabel = MatchKit.label({ name = "Title", text = lineText, role = cfg.titleRole, z = Z })
	lineLabel.Position = UDim2.fromOffset(0, y)
	lineLabel.Parent = column
	-- The killer's squishy (M:171): smToyIn on the outer holder, smToyBob on the inner one.
	local toyHolder: Frame? = nil
	if killer and killer.squishyId ~= "" then
		local toy = cfg.toy
		local outer = frame({
			Name = "Toy",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(width - toy.right - toy.size / 2, toy.top + toy.size / 2),
			Size = UDim2.fromOffset(toy.size, toy.size),
			Parent = band,
		})
		local inner = frame({ Name = "Bob", Size = UDim2.fromScale(1, 1), Parent = outer })
		local picture = SquishyImage.new(killer.squishyId, {
			name = "Picture",
			size = toy.size,
			shadow = { px = toy.shadowPx, alpha = toy.shadowAlpha },
		})
		picture.root.Parent = inner
		UiIdle.addFrames(
			inner,
			BOB_FRAMES :: any,
			{ periodS = CFG.toyBob.periodS, delayS = CFG.toyBob.delayS, curve = "easeInOut" }
		)
		toyHolder = outer
	end
	for _, star in cfg.twinkles do
		twinkle(band, star)
	end
	local shine = cfg.shine
	local strip = frame({
		Name = "Shine",
		Position = UDim2.fromOffset(0, -shine.overhang),
		Size = UDim2.new(0, shine.px, 1, 2 * shine.overhang),
		Parent = band,
	})
	Theme.shineBand(strip, shine.alpha, shine.slantDeg)
	UiIdle.add(strip, "shine", { periodS = shine.periodS, delayS = shine.delayS })
	return toyHolder
end

-- A stat box and its caption (M:182-189): the picture, the number; its column's width.
local function statBox(
	parent: Frame,
	picture: string,
	number: string,
	caption: string,
	streak: boolean
): (Frame, number)
	local box = CFG.info.box
	local numberLabel, numberSize = MatchKit.label({ name = "Number", text = number, role = box.numberRole, z = Z })
	local captionLabel, captionSize =
		MatchKit.label({ name = "Caption", text = caption, role = box.captionRole, z = Z })
	local boxWidth = 2 * box.border + box.padLeft + box.icon + box.gap + numberSize.X + box.padRight
	local columnWidth = math.max(boxWidth, captionSize.X)
	local boxHeight = box.height + box.lip
	local column = frame({
		Name = if streak then "WinStreak" else "Grip",
		Size = UDim2.fromOffset(columnWidth, boxHeight + box.captionGap + captionSize.Y),
		Parent = parent,
	})
	local face = frame({
		Name = "Box",
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(boxWidth, boxHeight),
		Parent = column,
	})
	local top = if streak then Palette.StickerStreakTop else Palette.StickerGripTop
	local bottom = if streak then Palette.StickerStreakEnd else Palette.StickerGripEnd
	local alpha = if streak then box.streakAlpha else box.gripAlpha
	local bands = Layout.stickerBands(box.border, box.highlight, 0, box.lip)
	Theme.foam(face, {
		radius = box.radius,
		stroke = box.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		fixedHeight = boxHeight,
		colors = { face = top, faceEnd = bottom, top = top:Lerp(WHITE, alpha), drop = Theme.Colors.inkUI },
	})
	local icon = IconGlyph.image(picture, { name = "Icon", sizePx = box.icon, parent = face })
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromOffset(box.border + box.padLeft, box.height / 2 + (if streak then box.flameY else 0))
	icon.ZIndex = Z
	numberLabel.AnchorPoint = Vector2.new(0, 0.5)
	numberLabel.Position = UDim2.fromOffset(box.border + box.padLeft + box.icon + box.gap, box.height / 2)
	numberLabel.Parent = face
	captionLabel.AnchorPoint = Vector2.new(0.5, 0)
	captionLabel.Position = UDim2.new(0.5, 0, 0, boxHeight + box.captionGap)
	captionLabel.TextXAlignment = Enum.TextXAlignment.Center
	captionLabel.Parent = column
	return column, columnWidth
end

local function info(parent: GuiObject, y: number, width: number, killer: MatchKit.Who, preview: boolean)
	local cfg = CFG.info
	frame({
		Name = "InfoBorder",
		BackgroundColor3 = Theme.Colors.inkUI,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(width, cfg.borderTop),
		Parent = parent,
	})
	local row = frame({
		Name = "Info",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(0, y + cfg.borderTop),
		Size = UDim2.fromOffset(width, cfg.height),
		Parent = parent,
	})
	Theme.foam(row, {
		radius = 0,
		stroke = 0,
		top = cfg.highlight,
		fixedHeight = cfg.height,
		colors = {
			face = Palette.StickerPillTop,
			faceEnd = Palette.StickerPillBottom,
			top = Palette.StickerPillTop:Lerp(WHITE, cfg.highlightAlpha),
		},
	})
	local centre = cfg.height / 2
	local head = cfg.head
	local lip = frame({
		Name = "HeadLip",
		BackgroundColor3 = Theme.Colors.inkUI,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(cfg.padLeft, centre + head.lip / 2),
		Size = UDim2.fromOffset(head.size, head.size),
		Parent = row,
	})
	Theme.corner(head.radius, lip)
	local box = MatchKit.head({
		name = "Head",
		who = killer,
		size = head.size,
		border = head.border,
		radius = head.radius,
		z = Z,
		parent = row,
	})
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.fromOffset(cfg.padLeft, centre - head.lip / 2)
	-- The stat boxes from the right (M:182-189): Grip level, then win streak; each only when it is known.
	local player = killer.player
	local grip = if player then player:GetAttribute(ATTR_GRIP) else nil
	local streak = if player then player:GetAttribute(ATTR_STREAK) else nil
	if preview and player == nil then
		grip, streak = CFG.preview.grip, CFG.preview.streak
	end
	local right = width - cfg.padRight
	local words = Strings.matchHud.card
	for _, stat in
		{
			{ value = streak, picture = KEY_FLAME, caption = words.winStreak, streak = true },
			{ value = grip, picture = key(KEY_GRIP, KEY_GRIP_FALLBACK), caption = words.gripLevel, streak = false },
		}
	do
		if type(stat.value) == "number" then
			local column, columnWidth =
				statBox(row, stat.picture, tostring(math.floor(stat.value)), stat.caption, stat.streak)
			column.AnchorPoint = Vector2.new(1, 0.5)
			column.Position = UDim2.fromOffset(right, centre)
			right -= columnWidth + cfg.gap
		end
	end
	-- The name column between the head and the boxes (M:178-181): the name cut to fit, the @handle under it.
	local left = cfg.padLeft + head.size + cfg.gap
	local room = math.max(right - left, 0)
	local role = Config.UI.Sticker.text[cfg.nameRole]
	local nameText = MatchHudFormat.clipText(killer.name, room, function(text: string): number
		return Theme.textWidth(text, role.kind :: Theme.TextKind) + 2
	end)
	local nameLabel, nameSize = MatchKit.label({ name = "Name", text = nameText, role = cfg.nameRole, z = Z })
	local handleText = if player
		then Strings.format(words.handle, { name = player.Name })
		elseif preview then Strings.format(words.handle, { name = killer.name })
		else nil
	local handleLabel, handleSize = nil, Vector2.zero
	if handleText then
		local handleRole = Config.UI.Sticker.text[cfg.handleRole]
		local clipped = MatchHudFormat.clipText(handleText, room, function(text: string): number
			return Theme.textWidth(text, handleRole.kind :: Theme.TextKind) + 2
		end)
		handleLabel, handleSize = MatchKit.label({ name = "Handle", text = clipped, role = cfg.handleRole, z = Z })
	end
	local columnHeight = nameSize.Y + (if handleLabel then cfg.nameGap + handleSize.Y else 0)
	local column = frame({
		Name = "Who",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(left, centre),
		Size = UDim2.fromOffset(room, columnHeight),
		Parent = row,
	})
	nameLabel.Parent = column
	if handleLabel then
		handleLabel.Position = UDim2.fromOffset(0, nameSize.Y + cfg.nameGap)
		handleLabel.Parent = column
	end
end

-- Public

-- The card (unplaced, at rest), for this step and M13's final card.
function DeathCard.build(spec: BuildSpec): Built
	local width = CFG.width
	local body = CFG.body
	local innerWidth = width - 2 * body.border
	local hasInfo = spec.killer ~= nil
	local innerHeight = CFG.banner.height + (if hasInfo then CFG.info.borderTop + CFG.info.height else 0)
	local bodyHeight = innerHeight + 2 * body.border + body.lip
	local headerHeight = CFG.header.height
	local size = Vector2.new(width, headerHeight + CFG.rowGap + bodyHeight)
	local root = frame({ Name = "MatchDeathCard", Size = UDim2.fromOffset(size.X, size.Y) })
	local fit: UIScale = Create("UIScale", { Name = "SD_Fit", Parent = root })
	-- M:156 transform-origin 0 100%: the tracks scale the card about its bottom left.
	local pose: CanvasGroup = Create("CanvasGroup", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
		Active = false,
		Parent = root,
	})
	local head = frame({ Name = "Header", Size = UDim2.fromOffset(width, headerHeight), Parent = pose })
	header(head, spec)
	local shell = frame({
		Name = "Body",
		BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(0, headerHeight + CFG.rowGap),
		Size = UDim2.fromOffset(width, bodyHeight),
		Parent = pose,
	})
	local bands = Layout.stickerBands(body.border, 0, 0, body.lip)
	Theme.foam(shell, {
		radius = body.radius,
		stroke = body.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		fixedHeight = bodyHeight,
		colors = { face = Palette.StickerPillBottom, drop = Theme.Colors.inkUI },
	})
	local inside: CanvasGroup = Create("CanvasGroup", {
		Name = "Inside",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(body.border, body.border),
		Size = UDim2.fromOffset(innerWidth, innerHeight),
		ZIndex = Z,
		Active = false,
		Parent = shell,
	})
	Theme.corner(body.radius - body.border, inside)
	local toy = banner(inside, innerWidth, spec)
	local killer = spec.killer
	if killer then
		info(inside, CFG.banner.height, innerWidth, killer, spec.preview)
	end
	return { root = root, fit = fit, pose = pose, toy = toy, size = size }
end

function DeathCard.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local shown: Shown? = nil
	local alive = true -- the piece lives (sounds wait 260 ms)

	local function drop()
		local current = shown
		shown = nil
		ctx.shared.cardRect = nil
		if current then
			current.built.root:Destroy()
		end
	end

	local function place()
		local current = shown
		if current == nil then
			return
		end
		local built = current.built
		local at = MatchHudFormat.cardPlace(ctx.canvas(), ctx.touchAreas(), built.size, {
			left = CFG.left,
			bottom = CFG.bottom,
			top = CFG.top,
			gap = CFG.gap,
			fitMin = Config.UI.Match.compact.fitMin,
			compact = ctx.compact(),
			compactShare = CFG.compactShare,
		})
		built.root.Position = UDim2.fromOffset(math.round(at.x), math.round(at.y))
		built.fit.Scale = at.scale
		ctx.shared.cardRect = { x = at.x, y = at.y, w = built.size.X * at.scale, h = built.size.Y * at.scale }
	end

	local piece = {}

	function piece.update(_self: any, view: any, now: number)
		local current = shown
		if current == nil then
			return
		end
		if not LIVE_PHASES[view.matchPhase] then
			drop() -- the end screens take over at once
			return
		end
		local clock = os.clock()
		local reduced = ctx.reduced()
		local you = view.you
		if current.hiding == nil and (you.alive or (you.out and now >= current.at + MATCH.respawnSeconds)) then
			current.hiding = clock
		end
		local hiding = current.hiding
		if hiding then
			local hide = CFG.hide
			local t = clock - hiding
			if t >= hide.ms / 1000 then
				drop()
				return
			end
			current.poser:set(MatchHudFormat.trackPose(hide.frames, t, hide.ms, nil, hide.wholeRun, reduced, FADE_MS))
		else
			local show = CFG.show
			local t = clock - current.born
			current.poser:set(MatchHudFormat.trackPose(show.frames, t, show.ms, nil, show.wholeRun, reduced, FADE_MS))
			local toyPoser = current.toyPoser
			if toyPoser and not reduced then
				local toyIn = CFG.toyIn
				local tt = t - toyIn.delayMs / 1000
				toyPoser:set(Tweens.poseAt(toyIn.frames :: any, math.clamp(tt / (toyIn.ms / 1000), 0, 1), toyIn.curve))
			end
		end
		place()
	end

	function piece.onMoment(_self: any, moment: any, view: any)
		if not MatchHudFormat.cardShows(moment, view) then
			return
		end
		drop()
		local killer = if type(moment.by) == "number" then MatchKit.who(ctx, view, moment.by) else nil
		local built = DeathCard.build({
			killer = killer,
			victim = MatchKit.who(ctx, view, view.you.userId),
			cause = moment.cause,
			final = false,
			preview = ctx.preview,
		})
		built.root.Parent = ctx.root
		shown = {
			built = built,
			born = os.clock(),
			at = if type(moment.at) == "number" then moment.at else 0,
			hiding = nil,
			poser = Tweens.poser(built.pose),
			toyPoser = if built.toy then Tweens.poser(built.toy) else nil,
		}
		place()
		piece.update(piece, view, if type(moment.at) == "number" then moment.at else 0)
		ctx.play("match.knockedOut", nil, "ui.error")
		ctx.play("match.splat", { volume = AUDIO.matchHud.splatYou }, "sfx.impactSoft")
		UiFx.jolt(ctx.root, CFG.jolt)
		ctx.play("match.whoosh", nil, "sfx.inspect.whoosh")
		task.delay(CFG.clickDelayMs / 1000, function()
			if alive then
				ctx.play("ui.click", { pitch = AUDIO.uiPitch.card })
			end
		end)
	end

	function piece.layout(_self: any)
		place()
	end

	function piece.destroy(_self: any)
		alive = false
		drop()
	end

	return piece :: any
end

return DeathCard
