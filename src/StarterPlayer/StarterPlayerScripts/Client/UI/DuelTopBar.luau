--!strict
-- DuelTopBar (client only). Duel HUD part 3 (owner 2026-10-24, "yes, start part 3"; `D:n` = "Squishy Duels Duel
-- HUD.dc.html" line n, the co-owner's Duel HUD export, ported 1:1; superprompt §3): the duel 1v1 top bar, drawn by
-- DuelController inside its TopBar frame (so the banners, the countdown and the toasts that sit under the bar keep
-- their place), in duels only (matches hide the TopBar).
-- * Desk (D:56-96): "First to N!" · your column (pink score plate, your avatar with the gold ring, your squishy's badge
--   at its bottom-right, your name) · the timer plate · the opponent's column (blue plate, avatar, badge bottom-left) ·
--   "Duel 1v1". Phone (D:152-177): your avatar · your score · the timer over "FIRST TO N" · their score · their avatar.
-- * The score = the lives the other one lost (a duel is won at N = the lives, owner 2026-10-24: "Keep 3 lives"); a new
--   point bumps that plate (D:360). The timer turns pink at 10 s or less (D:416).
-- * SQUISHED: while a player's hit invulnerability runs (the duel's "squished" moment, before they stand again), their
--   headshot goes grey and the SQUISHED tag pops in on it (desk, D:70) or a red slash crosses it (phone, D:157).
-- * Headshots: Players:GetUserThumbnailAsync (HeadShot 150), fetched once per user off the frame (a test dummy has
--   none: its avatar shows only the round background).
-- Sizes: Config.UI.DuelTopBar; colours: Art/Palette; texts: Strings.duel.top*. The bar draws in design px: its root is
-- the design size x `scale` (the canvas scale over the HUD's own UI scale) with one UIScale inside.
-- Pure (unit-tested): scores(youLives, foeLives, lives), timerLow(phase, endsAt, now), squished(invulnUntil, now).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Create = require(UI.Create)
local MotionTrack = require(UI.MotionTrack)
local Theme = require(UI.Theme)
local SquishyImage = require(UI.Components.SquishyImage)
local Scheduler = require(UI.Parent.Anim.Scheduler)
local Tweens = require(UI.Parent.Anim.Tweens)

-- Types

export type Form = "desk" | "phone"

export type SideInfo = {
	userId: number,
	name: string,
	squishyId: string,
	score: number,
	squished: boolean,
}

export type Info = {
	form: Form,
	scale: number, -- design px -> the parent's px
	you: SideInfo,
	foe: SideInfo,
	timer: string,
	timerLow: boolean,
	target: number,
}

type Side = {
	plate: Frame,
	plateScale: UIScale,
	score: TextLabel,
	head: ImageLabel,
	badgeAt: Vector2?, -- the badge face's centre (desk)
	badgePx: number?,
	badge: SquishyImage.SquishyImage?,
	canvas: Frame,
	name: TextLabel?,
	tag: Frame?,
	slash: Frame?,
	shownScore: number?,
	shownSquished: boolean?,
	userId: number?,
	squishyId: string?,
	bump: Scheduler.Handle?,
}

export type DuelTopBar = {
	root: Frame,
	update: (self: DuelTopBar, info: Info) -> (),
	destroy: (self: DuelTopBar) -> (),
}

-- Constants

local BAR = Config.UI.DuelTopBar
local INK = Palette.StickerInk
local WHITE = Palette.White
local LIVE: { [string]: boolean } = { Active = true, SuddenDeath = true }
local TAG_IN: { Tweens.Pose } = { -- D:25 dhTag
	{ at = 0, alpha = 0, y = 8, scale = 0.7 },
	{ at = 0.6, alpha = 1, y = -2, scale = 1.08 },
	{ at = 1, alpha = 1, y = 0, scale = 1 },
}
local BUMP: { Tweens.Pose } = { -- D:360
	{ at = 0, scale = 1 },
	{ at = 0.3, scale = BAR.bumpPeak },
	{ at = 0.65, scale = 0.96 },
	{ at = 1, scale = 1 },
}

-- Module table

local DuelTopBar = {}

-- Private

local headshots: { [number]: string } = {}
local fetching: { [number]: boolean } = {}

local function headshotOf(userId: number): string
	if userId <= 0 then
		return "" -- a Studio test dummy
	end
	local known = headshots[userId]
	if known then
		return known
	end
	if not fetching[userId] then
		fetching[userId] = true
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and type(content) == "string" then
				headshots[userId] = content
			end
			fetching[userId] = nil
		end)
	end
	return ""
end

local function round(object: GuiObject)
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = object })
end

local function disc(name: string, px: number, centre: Vector2, color: Color3, z: number, parent: Instance): Frame
	local frame: Frame = Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centre.X, centre.Y),
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	})
	round(frame)
	return frame
end

-- Fredoka with the Ink outline (-webkit-text-stroke N = a UIStroke of N / 2).
local function text(props: { [string]: any }, px: number, strokePx: number, color: Color3?): TextLabel
	props.BackgroundTransparency = 1
	props.FontFace = Theme.font("Button")
	props.TextSize = px
	props.TextColor3 = color or WHITE
	props.TextWrapped = false
	local label: TextLabel = Create("TextLabel", props)
	if strokePx > 0 then
		Create("UIStroke", {
			Color = INK,
			Thickness = strokePx / 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = label,
		})
	end
	return label
end

-- A skewed plate: its box (placed, scaled by the bump) holding the baked picture and its number.
local function plate(
	name: string,
	box: Vector2,
	image: Vector2,
	key: string,
	topLeft: Vector2,
	numberPx: number,
	strokePx: number,
	parent: Instance
): (Frame, UIScale, TextLabel)
	local holder: Frame = Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(topLeft.X + box.X / 2, topLeft.Y + box.Y / 2),
		Size = UDim2.fromOffset(box.X, box.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
	local scale: UIScale = Create("UIScale", { Parent = holder })
	Create("ImageLabel", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-(image.X - box.X) / 2, 0),
		Size = UDim2.fromOffset(image.X, image.Y),
		Image = AssetTable.image(key) or "",
		ZIndex = 2,
		Parent = holder,
	})
	local number = text({
		Name = "Number",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Text = "",
		Parent = holder,
	}, numberPx, strokePx)
	return holder, scale, number
end

-- An avatar `px` wide centred at `centre`: the rings and the drop behind, the Ink border, the round background and
-- the headshot (D:63, 83, 154, 172).
local function avatar(
	px: number,
	border: number,
	centre: Vector2,
	bgKey: string,
	gold: number?,
	ink: number?,
	drop: number?,
	parent: Instance
): ImageLabel
	if drop then
		disc("Drop", px, centre + Vector2.new(0, drop), INK, 4, parent)
	end
	if ink then
		disc("InkRing", px + 2 * ink, centre, INK, 5, parent)
	end
	if gold then
		disc("GoldRing", px + 2 * gold, centre, Palette.Lemon, 6, parent)
	end
	disc("Border", px, centre, INK, 7, parent)
	local inner = px - 2 * border
	local bg: ImageLabel = Create("ImageLabel", {
		Name = "Background",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centre.X, centre.Y),
		Size = UDim2.fromOffset(inner, inner),
		BackgroundTransparency = 1,
		Image = AssetTable.image(bgKey) or "",
		ZIndex = 8,
		Parent = parent,
	})
	round(bg)
	local head: ImageLabel = Create("ImageLabel", {
		Name = "Headshot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centre.X, centre.Y),
		Size = UDim2.fromOffset(inner, inner),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 9,
		Parent = parent,
	})
	round(head)
	return head
end

local function buildDeskSide(you: boolean, x0: number, canvas: Frame): Side
	local D = BAR.desk
	local column = D.plate.X
	local plateHolder, plateScale, score = plate(
		if you then "YouScore" else "FoeScore",
		D.plate,
		D.plateImage,
		if you then "img.duel.plate.scoreYouDesk" else "img.duel.plate.scoreFoeDesk",
		Vector2.new(x0, 0),
		D.numberPx,
		D.numberStrokePx,
		canvas
	)
	local centre = Vector2.new(x0 + column / 2, D.plate.Y + D.columnGapPx + D.avatarPx / 2)
	local head = avatar(
		D.avatarPx,
		D.avatarBorderPx,
		centre,
		if you then "img.duel.avatar.you" else "img.duel.avatar.foe",
		if you then D.goldRingPx else nil,
		if you then D.inkRingPx else nil,
		if you then D.youDropPx else D.foeDropPx,
		canvas
	)
	-- the squishy badge at the avatar's bottom-right (yours) or bottom-left (theirs), D:66, 86
	local half = D.avatarPx / 2
	local b = D.badgePx
	local bx = if you then centre.X + half + D.badgeOffset.X - b / 2 else centre.X - half - D.badgeOffset.X + b / 2
	local by = centre.Y + half + D.badgeOffset.Y - b / 2
	disc("BadgeDrop", b, Vector2.new(bx, by + D.badgeDropPx), INK, 10, canvas)
	disc("BadgeBorder", b, Vector2.new(bx, by), INK, 11, canvas)
	disc("BadgeFace", b - 2 * D.badgeBorderPx, Vector2.new(bx, by), Palette.Frosting, 12, canvas)
	local name = text({
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(centre.X, centre.Y + half + D.columnGapPx + D.nameTopPx),
		Size = UDim2.fromOffset(column * 2, D.namePx),
		Text = "",
		ZIndex = 14,
		Parent = canvas,
	}, D.namePx, D.nameStrokePx)
	-- SQUISHED (D:70): centred on the avatar, turned -8°; the holder pops in, its pill is the border-box
	local spec = D.tag
	local tag: Frame = Create("Frame", {
		Name = "Squished",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centre.X, centre.Y),
		Size = UDim2.fromOffset(spec.padPx * 2, spec.heightPx - 2 * spec.borderPx),
		Rotation = spec.rotation,
		BackgroundColor3 = Palette.DuelSquished,
		Visible = false,
		ZIndex = 15,
		Parent = canvas,
	})
	round(tag)
	Create("UIStroke", { Color = INK, Thickness = spec.borderPx, Parent = tag })
	local word = Strings.duel.topSquished
	text({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Text = word,
		ZIndex = 16,
		Parent = tag,
	}, spec.textPx, 0)
	local width = Theme.textWidth(word, "Chip") * spec.textPx / Theme.textSize("Chip")
	tag.Size = UDim2.fromOffset(math.ceil(width) + 2 * spec.padPx, spec.heightPx - 2 * spec.borderPx)
	return {
		plate = plateHolder,
		plateScale = plateScale,
		score = score,
		head = head,
		badgeAt = Vector2.new(bx, by),
		badgePx = b - 2 * D.badgeBorderPx,
		badge = nil,
		canvas = canvas,
		name = name,
		tag = tag,
		slash = nil,
	}
end

local function buildPhoneSide(you: boolean, canvas: Frame): Side
	local P = BAR.phone
	local h = P.size.Y
	local ax = if you then P.avatarPx / 2 else P.size.X - P.avatarPx / 2
	local centre = Vector2.new(ax, h / 2)
	local head = avatar(
		P.avatarPx,
		P.avatarBorderPx,
		centre,
		if you then "img.duel.avatar.you" else "img.duel.avatar.foe",
		if you then P.goldRingPx else nil,
		if you then P.inkRingPx else nil,
		nil,
		canvas
	)
	local px = if you then P.avatarPx + P.gapPx else P.size.X - P.avatarPx - P.gapPx - P.plate.X
	local plateHolder, plateScale, score = plate(
		if you then "YouScore" else "FoeScore",
		P.plate,
		P.plateImage,
		if you then "img.duel.plate.scoreYouPhone" else "img.duel.plate.scoreFoePhone",
		Vector2.new(px, (h - P.plate.Y) / 2),
		P.scorePx,
		P.scoreStrokePx,
		canvas
	)
	local spec = P.slash
	local slash: Frame = Create("Frame", {
		Name = "Squished",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centre.X, centre.Y),
		Size = UDim2.fromOffset(spec.size.X, spec.size.Y),
		Rotation = spec.rotation,
		BackgroundColor3 = Palette.DuelSquished,
		Visible = false,
		ZIndex = 15,
		Parent = canvas,
	})
	round(slash)
	Create("UIStroke", { Color = INK, Thickness = spec.strokePx, Parent = slash })
	return {
		plate = plateHolder,
		plateScale = plateScale,
		score = score,
		head = head,
		badge = nil,
		canvas = canvas,
		name = nil,
		tag = nil,
		slash = slash,
	}
end

-- Public: pure

-- (your score, theirs): the lives each one took from the other, never below 0.
function DuelTopBar.scores(youLives: number, foeLives: number, lives: number): (number, number)
	return math.max(0, lives - foeLives), math.max(0, lives - youLives)
end

function DuelTopBar.timerLow(phase: string, endsAt: number, now: number): boolean
	return LIVE[phase] == true and endsAt - now <= BAR.lowSeconds
end

function DuelTopBar.squished(invulnUntil: number?, now: number): boolean
	return invulnUntil ~= nil and invulnUntil > now
end

-- Public: the bar

function DuelTopBar.new(parent: Instance, layoutOrder: number?): DuelTopBar
	local root: Frame = Create("Frame", {
		Name = "DesignBar",
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder or 0,
		Size = UDim2.fromOffset(0, 0),
		Parent = parent,
	})
	local canvas: Frame? = nil
	local canvasScale: UIScale? = nil
	local form: Form? = nil
	local sides: { you: Side?, foe: Side? } = { you = nil, foe = nil }
	local timer: TextLabel? = nil
	local firstTo: TextLabel? = nil

	local function build(newForm: Form)
		if canvas then
			canvas:Destroy()
		end
		for _, side in sides :: { [string]: Side } do
			if side.bump then
				side.bump:disconnect()
			end
			if side.badge then
				side.badge:destroy()
			end
		end
		local size = BAR[newForm].size
		local c: Frame = Create("Frame", {
			Name = "Canvas",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size.X, size.Y),
			Parent = root,
		})
		canvasScale = Create("UIScale", { Parent = c })
		if newForm == "desk" then
			local D = BAR.desk
			local x = 0
			firstTo = text({
				Name = "FirstTo",
				Size = UDim2.fromOffset(D.labelPx.X - D.labelPadPx, D.labelPx.Y),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "",
				Parent = c,
			}, D.labelTextPx, D.labelStrokePx, Palette.Frosting)
			x += D.labelPx.X + D.gapPx
			sides.you = buildDeskSide(true, x, c)
			x += D.plate.X + D.gapPx
			local _, _, t = plate("Timer", D.timer, D.timerImage, "img.duel.plate.timerDesk", Vector2.new(x, 0), D.numberPx, D.numberStrokePx, c)
			timer = t
			x += D.timer.X + D.gapPx
			sides.foe = buildDeskSide(false, x, c)
			x += D.plate.X + D.gapPx
			text({
				Name = "Mode",
				Position = UDim2.fromOffset(x + D.labelPadPx, 0),
				Size = UDim2.fromOffset(D.labelPx.X - D.labelPadPx, D.labelPx.Y),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Strings.duel.topMode,
				Parent = c,
			}, D.labelTextPx, D.labelStrokePx, Palette.Frosting)
		else
			local P = BAR.phone
			sides.you = buildPhoneSide(true, c)
			sides.foe = buildPhoneSide(false, c)
			local tx = (P.size.X - P.timer.X) / 2
			local _, _, t = plate("Timer", P.timer, P.timerImage, "img.duel.plate.timerPhone", Vector2.new(tx, 0), P.timerPx, P.timerStrokePx, c)
			timer = t
			firstTo = text({
				Name = "FirstTo",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(P.size.X / 2, P.timer.Y + P.firstToGapPx),
				Size = UDim2.fromOffset(P.timer.X * 2, P.firstToPx),
				Text = "",
				Parent = c,
			}, P.firstToPx, P.firstToStrokePx)
		end
		canvas = c
		form = newForm
	end

	local bar = { root = root } :: DuelTopBar

	local function updateSide(side: Side, info: SideInfo)
		local scoreText = tostring(info.score)
		if side.score.Text ~= scoreText then
			side.score.Text = scoreText
		end
		if side.shownScore ~= nil and info.score > side.shownScore and not Tweens.reducedMotion() then
			-- the bump (D:360): its easing (ease-out) runs over the whole animation
			if side.bump then
				side.bump:disconnect()
			end
			local elapsed = 0
			side.bump = Scheduler.add(function(dt: number): boolean
				elapsed += dt
				local u = math.min(elapsed * 1000 / BAR.bumpMs, 1)
				side.plateScale.Scale = Tweens.poseAt(BUMP, u, "linear", "easeOut").scale or 1
				if u >= 1 then
					side.plateScale.Scale = 1
					side.bump = nil
					return false
				end
				return true
			end, "render")
		end
		side.shownScore = info.score
		side.head.Image = headshotOf(info.userId)
		side.head.ImageColor3 = if info.squished then Palette.DuelHeadGrey else WHITE
		-- the badge: the squishy's picture, or its 3D model while that picture has no id (Components/SquishyImage)
		local at = side.badgeAt
		if at and side.squishyId ~= info.squishyId then
			side.squishyId = info.squishyId
			local badge = side.badge
			if badge then
				badge:setCatalogId(info.squishyId)
			else
				badge = SquishyImage.new(info.squishyId, { size = side.badgePx, name = "Badge", parent = side.canvas })
				local b = badge :: SquishyImage.SquishyImage
				b.root.AnchorPoint = Vector2.new(0.5, 0.5)
				b.root.Position = UDim2.fromOffset(at.X, at.Y)
				b.root.ZIndex = 13
				side.badge = b
			end
		end
		if side.name and side.name.Text ~= info.name then
			side.name.Text = info.name
		end
		if info.squished ~= side.shownSquished then
			side.shownSquished = info.squished
			local mark = side.tag or side.slash
			if mark then
				mark.Visible = info.squished
				if info.squished and side.tag then
					MotionTrack.play(side.tag, TAG_IN, BAR.tagMs, 0, "search")
				end
			end
		end
	end

	function bar.update(_: DuelTopBar, info: Info)
		if info.form ~= form then
			build(info.form)
		end
		local size = BAR[info.form].size
		local px = UDim2.fromOffset(math.ceil(size.X * info.scale), math.ceil(size.Y * info.scale))
		if root.Size ~= px then
			root.Size = px
		end
		local s = canvasScale :: UIScale
		if s.Scale ~= info.scale then
			s.Scale = info.scale
		end
		local t = timer :: TextLabel
		if t.Text ~= info.timer then
			t.Text = info.timer
		end
		t.TextColor3 = if info.timerLow then Palette.DuelTimerLow else WHITE
		local template = if info.form == "desk" then Strings.duel.topFirstTo else Strings.duel.topFirstToPhone
		local label = Strings.format(template, { n = info.target })
		local f = firstTo :: TextLabel
		if f.Text ~= label then
			f.Text = label
		end
		updateSide(sides.you :: Side, info.you)
		updateSide(sides.foe :: Side, info.foe)
	end

	function bar.destroy(_: DuelTopBar)
		for _, side in sides :: { [string]: Side } do
			if side.bump then
				side.bump:disconnect()
			end
			if side.badge then
				side.badge:destroy()
			end
		end
		root:Destroy()
	end

	return bar
end

return DuelTopBar
