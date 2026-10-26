--!strict
-- SquishMedal (client only). The squish medals (2026-10-26, owner: "Yes, build the medals like that, only for double and
-- triple squishes. You can make and upload the sound and picture."; `S:n` = Diego's "Squishy Duels LOADING SCREEN Y MATCH
-- HUD.dc.html" line n): a MatchHudController piece ("medal"). Your 2nd squish within Config.UI.Match.feed.multiWindowS
-- of the last is DOUBLE SQUISH!, the 3rd and on TRIPLE SQUISH! (the kill feed's own rule, S:687: MatchHudFormat.feedLine
-- / medalOf); a squish alone shows none (owner: Diego's kill banner is that moment, so S:702's SQUISHED! is left out).
-- One medal (S:67-80, Config/MatchMedal), centred at y 470 of the page's legacy layer (S:539: 1440 x 810 scaled to fit
-- the safe area), lifted over the desktop ability bar when it would reach it (MatchHudFormat.dockClear):
--   the gold medal (img.medal.face in a 5 px ink rim over its 6 px lip) with the victim's picture squashed in it (S:73:
--   scale 1.3, .62, 22 px down; a bot: its squishy), the gold rays turning behind it (img.medal.rays, 6 s a turn), the
--   green +1 on its corner; TRIPLE / DOUBLE SQUISH! (42 px #FFE36B), the victim's name, and your streak with its flame
--   from a streak of 2 (S:78).
-- smMedal (S:36): slams in from 2.6x turned -10deg, settles, holds, rises 40 px as it fades; gone at 1.95 s (S:706).
-- Sounds (S:707): the stamp (match.vote.stamp: the same lib:204 recipe) and 90 ms later the chime (match.medal.claim,
-- ui.coin while it has no id); the page's splat is left to the kill banner's own kill sound. 160 ms in: Diego's burst
-- and gold ring (UiFx.sparks / ring, S:708). A newer medal replaces the one showing (S:67 stacks them on one spot, where
-- the older one's words poke out around the new one). Reduced motion: it only fades.

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
local MatchHudFormat = require(UI.MatchHudFormat)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local SquishyImage = require(UI.Components.SquishyImage)
local Tweens = require(UI.Parent.Anim.Tweens)
local MatchKit = require(script.Parent.MatchKit)

-- Types

type Medal = {
	root: Frame, -- placed on the safe area; its UIScale the layer's scale
	scale: UIScale,
	poser: Tweens.Poser,
	rim: Frame,
	rays: ImageLabel,
	column: Vector2, -- the column's size (S:70), layer px
	born: number,
	claimed: boolean,
	burst: boolean,
}

-- Constants

local CFG = Config.UI.Match.medal
local FEED = Config.UI.Match.feed
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local WORDS = Strings.matchHud.medal
local FACE_KEY = "img.medal.face"
local RAYS_KEY = "img.medal.rays"
local FLAME_KEY = "img.icon.flame"
local HEAD_URL = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150" -- MatchKit.head's
local SOUND_STAMP = "match.vote.stamp"
local SOUND_CLAIM = "match.medal.claim"
local SOUND_CLAIM_FALLBACK = "ui.coin"
local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Colors.inkUI

-- Module table

local SquishMedal = {}

-- Private

local function frame(name: string, props: { [string]: any }): Frame
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false }
	for key, value in props do
		base[key] = value
	end
	return Create("Frame", base)
end

local function picture(name: string, key: string, props: { [string]: any }): ImageLabel?
	local id = AssetTable.image(key)
	if id == nil then
		return nil
	end
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1, Image = id, Active = false }
	for k, value in props do
		base[k] = value
	end
	return Create("ImageLabel", base)
end

-- The streak pill (S:78): the flame and "{n} squish streak" on the orange gradient, an ink lip under it.
local function streakPill(streak: number, z: number): Frame
	local S = CFG.streak
	local label, size =
		MatchKit.label({ name = "Text", text = Strings.format(WORDS.streak, { n = streak }), role = S.role, z = z })
	local width = S.padLeft + S.flame + S.gap + size.X + S.padRight
	local holder = frame("Streak", { Size = UDim2.fromOffset(width, S.height + S.lip), ZIndex = z })
	local lip = frame("Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		Position = UDim2.fromOffset(0, S.lip),
		Size = UDim2.fromOffset(width, S.height),
		ZIndex = z,
		Parent = holder,
	})
	Theme.corner(S.height / 2, lip)
	local pill = frame("Pill", { BackgroundTransparency = 0, Size = UDim2.fromOffset(width, S.height), ZIndex = z })
	Theme.corner(S.height / 2, pill)
	MatchKit.gradient(pill, { text = WHITE, top = Palette.MatchMedalStreakTop, faceEnd = Palette.MatchMedalStreakEnd })
	MatchKit.inner(Theme.stroke(INK, S.border, pill))
	pill.Parent = holder
	local flame = picture("Flame", FLAME_KEY, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S.padLeft, 0.5, -S.flameUp),
		Size = UDim2.fromOffset(S.flame, S.flame),
		ZIndex = z,
	})
	if flame then
		flame.Parent = pill
	end
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, S.padLeft + S.flame + S.gap, 0.5, 0)
	label.Parent = pill
	return holder
end

-- The medal (S:71-75): the rays, the lip, the ink rim with the gold face and the squashed picture, the +1.
local function medalCore(who: MatchKit.Who, z: number): (Frame, Frame, ImageLabel?)
	local M = CFG.medal
	local R = CFG.rays
	local holder = frame("Medal", { Size = UDim2.fromOffset(M.size, M.size), ZIndex = z })
	local rays = picture("Rays", RAYS_KEY, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(R.size, R.size),
		ZIndex = z,
		Parent = holder,
	})
	local lip = frame("Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		Position = UDim2.fromOffset(0, M.lip),
		Size = UDim2.fromOffset(M.size, M.size),
		ZIndex = z,
		Parent = holder,
	})
	Theme.corner(M.size / 2, lip)
	local rim = frame("Rim", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(M.size, M.size),
		ZIndex = z,
		Parent = holder,
	})
	Theme.corner(M.size / 2, rim)
	local inner = M.size - 2 * M.border
	local face = picture("Face", FACE_KEY, {
		Position = UDim2.fromOffset(M.border, M.border),
		Size = UDim2.fromOffset(inner, inner),
		ZIndex = z,
		Parent = rim,
	})
	if face == nil then -- no picture yet: the face's outer stop
		local flat = frame("Face", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.Lemon,
			Position = UDim2.fromOffset(M.border, M.border),
			Size = UDim2.fromOffset(inner, inner),
			ZIndex = z,
			Parent = rim,
		})
		Theme.corner(inner / 2, flat)
	end
	-- The picture inside the face (overflow hidden: a rounded CanvasGroup, as MatchKit.head's).
	local clip: CanvasGroup = Create("CanvasGroup", {
		Name = "Picture",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(M.border, M.border),
		Size = UDim2.fromOffset(inner, inner),
		ZIndex = z,
		Active = false,
		Parent = rim,
	})
	Theme.corner(inner / 2, clip)
	local down = M.pictureDown * M.squashY -- S:73: scale(...) translateY(22px): the move is squashed too
	if who.player then
		Create("ImageLabel", {
			Name = "Head",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, down),
			Size = UDim2.fromOffset(M.picture * M.squashX, M.picture * M.squashY),
			Image = string.format(HEAD_URL, who.userId),
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = z,
			Active = false,
			Parent = clip,
		})
	elseif who.squishyId ~= "" then
		local image = SquishyImage.new(who.squishyId, { size = M.picture })
		image.root.Name = "Toy"
		image.root.AnchorPoint = Vector2.new(0.5, 0.5)
		image.root.Position = UDim2.new(0.5, 0, 0.5, down)
		image:squash(M.squashX, M.squashY)
		image.root.Parent = clip
	end
	local P = CFG.plus
	local plus, width = MatchKit.chip({
		name = "Plus",
		text = WORDS.plus,
		role = P.role,
		height = P.height,
		padX = P.padX,
		border = P.border,
		top = Palette.MatchMedalPlusTop,
		faceEnd = Palette.MatchMedalPlusEnd,
		z = z,
	})
	plus.Position = UDim2.fromOffset(M.size - P.right - width, P.top)
	plus.Parent = holder
	return holder, rim, rays
end

local function build(ctx: MatchHudFormat.Context, view: any, kind: string, victim: number, streak: number?): Medal
	local z = CFG.z
	local who = MatchKit.who(ctx, view, victim)
	local core, rim, rays = medalCore(who, z)
	local title, titleSize = MatchKit.label({ name = "Title", text = WORDS[kind], role = CFG.titleRole, z = z })
	local name, nameSize = MatchKit.label({ name = "Name", text = who.name, role = CFG.nameRole, z = z })
	local pill = if streak and streak >= CFG.streak.min then streakPill(streak, z) else nil
	local M, gap = CFG.medal, CFG.gap
	local pillSize = if pill then pill.Size else UDim2.new()
	local width = math.max(M.size, titleSize.X, nameSize.X, pillSize.X.Offset)
	local height = M.size + gap + titleSize.Y + gap + nameSize.Y + (if pill then gap + CFG.streak.height else 0)
	-- The pose turns and scales about the column's centre (S:70); room around it for the rays and the +1.
	local pad = (CFG.rays.size - M.size) / 2
	local box = Vector2.new(math.max(width, CFG.rays.size) + 2 * pad, height + 2 * pad)
	local root =
		frame("SquishMedal", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(box.X, box.Y), ZIndex = z })
	local scale: UIScale = Create("UIScale", { Parent = root })
	local pose: CanvasGroup = Create("CanvasGroup", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Active = false,
		Parent = root,
	})
	local top = pad
	core.AnchorPoint = Vector2.new(0.5, 0)
	core.Position = UDim2.new(0.5, 0, 0, top)
	core.Parent = pose
	local y = top + M.size + gap
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, y)
	title.Parent = pose
	y += titleSize.Y + gap
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, y)
	name.Parent = pose
	y += nameSize.Y + gap
	if pill then
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, y)
		pill.Parent = pose
	end
	root.Parent = ctx.root
	local fallbackRays: ImageLabel = rays or Create("ImageLabel", { Name = "Rays", ImageTransparency = 1 })
	return {
		root = root,
		scale = scale,
		poser = Tweens.poser(pose),
		rim = rim,
		rays = fallbackRays,
		column = Vector2.new(width, height),
		born = os.clock(),
		claimed = false,
		burst = false,
	}
end

-- Public

function SquishMedal.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local medals: { Medal } = {}
	local memory = MatchHudFormat.newFeedMemory()

	-- The column's centre on the safe area (S:67, S:539) and the layer's scale, over the desktop ability bar.
	local function place(medal: Medal): (Vector2, number)
		local canvas = ctx.canvas()
		local k = if canvas.X > 0 and canvas.Y > 0 then math.min(canvas.X / CFG.layer.X, canvas.Y / CFG.layer.Y) else 1
		local screen = ctx.root.AbsoluteSize
		local uiScale = if canvas.X > 0 then screen.X / canvas.X else 0
		local touch = #ctx.touchAreas() > 0
		local bottom = (CFG.top + medal.column.Y) * k
		local limit = canvas.Y - MatchHudFormat.dockClear(screen, uiScale, touch) - CFG.dockGap
		local lift = math.max(bottom - limit, 0)
		return Vector2.new(canvas.X / 2, (CFG.top + medal.column.Y / 2) * k - lift), k
	end

	local piece = {}

	function piece.update(_self: any, _view: any, _now: number)
		local clock = os.clock()
		local reduced = ctx.reduced()
		for index = #medals, 1, -1 do
			local medal = medals[index]
			local t = clock - medal.born
			if t >= CFG.goneAt then
				medal.root:Destroy()
				table.remove(medals, index)
				continue
			end
			local at, k = place(medal)
			medal.root.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
			medal.scale.Scale = k
			local motion = CFG.motion
			medal.poser:set(MatchHudFormat.trackPose(motion.frames, t, motion.ms, motion.curve, nil, reduced, FADE_MS))
			medal.rays.Rotation = (t / CFG.rays.turnSeconds * 360) % 360
			if not medal.claimed and t >= CFG.claimDelay then
				medal.claimed = true
				ctx.play(SOUND_CLAIM, nil, SOUND_CLAIM_FALLBACK)
			end
			if not medal.burst and t >= CFG.fx.delay then
				medal.burst = true
				local fx = CFG.fx
				UiFx.sparks(medal.rim, { n = fx.n, spread = fx.spread * k, size = fx.size * k })
				UiFx.ring(medal.rim, Palette.StickerCoinText, fx.ring * k)
			end
		end
	end

	function piece.onMoment(_self: any, moment: any, view: any)
		local line = MatchHudFormat.feedLine(memory, moment, view.you.userId, FEED.multiWindowS, FEED.streakMin)
		local kind = MatchHudFormat.medalOf(line)
		if kind == nil or line == nil then
			return
		end
		-- A newer medal replaces the one showing (S:67 stacks them on one spot, where the older words show around it).
		for _, old in medals do
			old.root:Destroy()
		end
		table.clear(medals)
		table.insert(medals, build(ctx, view, kind, line.victim, moment.streak))
		ctx.play(SOUND_STAMP)
		piece.update(piece, view, 0) -- its first frame at once (fill "both")
	end

	function piece.destroy(_self: any)
		for _, medal in medals do
			medal.root:Destroy()
		end
		table.clear(medals)
	end

	return piece :: any
end

return SquishMedal
