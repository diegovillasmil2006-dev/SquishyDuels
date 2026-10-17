--!strict
-- RespawnBar (client only). Match HUD M7 (2026-10-17; plan work/matchhud2/PLAN.md §4 M7 = v1 M5; `M:n` = "Squishy Duels
-- Match HUD.dc.html" line n): a MatchHudController piece ("respawn"): while you are knocked out and coming back
-- (MatchHudFormat.respawnShows: not out of team lives, Active / Overtime) the knocked-out vignette and the RESPAWNING IN
-- bar; both go at your respawn, with ui.pop (M:553; ui.click while it has no id).
-- * The bar (M:195-200): "RESPAWNING IN" and the whole seconds left in the coin yellow (MatchHudFormat.respawnLeft),
--   over a 380 px trough whose Grip-mint fill is the share of the wait gone, from the server's respawn time (v1 §1.11;
--   M:198 is a fixed 3 s CSS fill). smRise .4 s in. Bottom centre, else beside or above the "squished by" card
--   (ctx.shared.cardRect), never on the thumbstick zone (MatchHudFormat.barPlace, v1 §1.3h; [P] it may cover the touch
--   buttons, which do nothing while you are knocked out).
-- * The vignette (M:60-62): img.fx.radial.matchVignette stretched over the whole screen (Config.UI.Match.vignette
--   .margin past the safe area), else M:61's stops on two edge gradients; and backdrop-filter saturate(.4)
--   brightness(.95) as a ColorCorrectionEffect in Lighting (client only, this piece's own), faded in over sdFade's
--   .4 s, gone at once at the respawn. It sits behind every other piece (this piece is built first).
-- The duel HUD's key dock (bottom centre, under the bar) is hidden meanwhile by MatchController (Match HUD M7).

-- Services

local Lighting = game:GetService("Lighting")
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
local Tweens = require(UI.Parent.Anim.Tweens)
local MatchKit = require(script.Parent.MatchKit)

-- Constants

local CFG = Config.UI.Match.respawn
local VIGNETTE = Config.UI.Match.vignette
local MATCH = Config.Match
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local Z_VIGNETTE = 1
local Z = 4
local KEY_VIGNETTE = "img.fx.radial.matchVignette"
local CORRECTION_NAME = "SD_MatchKnockedOut"
local WHITE = Color3.new(1, 1, 1)
local DIGITS_SAMPLE = "8" -- the widest digit: the number keeps one width as it counts down

-- Module table

local RespawnBar = {}

-- Private

-- The vignette (see the header), hidden; returns its root.
local function vignette(parent: GuiObject): Frame
	local margin = VIGNETTE.margin
	local root: Frame = Create("Frame", {
		Name = "MatchVignette",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
		ZIndex = Z_VIGNETTE,
		Visible = false,
		Active = false,
		Parent = parent,
	})
	local picture = AssetTable.image(KEY_VIGNETTE)
	if picture then
		Create("ImageLabel", {
			Name = "Picture",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = picture,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = Z_VIGNETTE,
			Active = false,
			Parent = root,
		})
		return root
	end
	-- Fallback [P]: M:61's mid and edge stops darkening each edge (one vertical, one horizontal gradient).
	local f = VIGNETTE.fallback
	local clear = math.clamp(f.clearShare, 0.05, 0.9) / 2 -- the clear middle, each side of 0.5
	local mid = (0.5 - clear) / 2 -- the mid stop halfway out
	local transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - f.edgeAlpha),
		NumberSequenceKeypoint.new(mid, 1 - f.midAlpha),
		NumberSequenceKeypoint.new(0.5 - clear, 1),
		NumberSequenceKeypoint.new(0.5 + clear, 1),
		NumberSequenceKeypoint.new(1 - mid, 1 - f.midAlpha),
		NumberSequenceKeypoint.new(1, 1 - f.edgeAlpha),
	})
	local colors = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Palette.MatchVignetteEdge),
		ColorSequenceKeypoint.new(0.5, Palette.MatchVignetteMid),
		ColorSequenceKeypoint.new(1, Palette.MatchVignetteEdge),
	})
	for _, rotation in { 0, 90 } do
		local edge: Frame = Create("Frame", {
			Name = if rotation == 0 then "Sides" else "TopBottom",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = Z_VIGNETTE,
			Active = false,
			Parent = root,
		})
		Create("UIGradient", { Rotation = rotation, Color = colors, Transparency = transparency, Parent = edge })
	end
	return root
end

type Bar = {
	root: Frame, -- placed; its UIScale "SD_Fit"
	fit: UIScale,
	pose: CanvasGroup,
	number: TextLabel,
	fill: Frame,
	size: Vector2,
}

-- The bar (M:196-199), hidden.
local function bar(parent: GuiObject): Bar
	local b = CFG.bar
	local label, labelSize =
		MatchKit.label({ name = "Label", text = Strings.matchHud.respawn.label, role = CFG.labelRole, z = Z })
	local number, numberSize = MatchKit.label({ name = "Number", text = DIGITS_SAMPLE, role = CFG.numberRole, z = Z })
	local rowHeight = math.max(labelSize.Y, numberSize.Y)
	local size = Vector2.new(CFG.width, rowHeight + CFG.rowGap + b.height + b.lip)
	local root: Frame = Create("Frame", {
		Name = "MatchRespawn",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = Z,
		Visible = false,
		Active = false,
		Parent = parent,
	})
	local fit: UIScale = Create("UIScale", { Name = "SD_Fit", Parent = root })
	local pose: CanvasGroup = Create("CanvasGroup", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
		Active = false,
		Parent = root,
	})
	-- M:197: the two texts side by side on their baseline (reading: bottoms aligned), centred.
	local rowWidth = labelSize.X + CFG.labelGap + numberSize.X
	local row: Frame = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(rowWidth, rowHeight),
		ZIndex = Z,
		Active = false,
		Parent = pose,
	})
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.fromScale(0, 1)
	label.Parent = row
	number.AnchorPoint = Vector2.new(0, 1)
	number.Position = UDim2.new(0, labelSize.X + CFG.labelGap, 1, 0)
	number.Parent = row
	-- M:198: the trough (ink at .6, a 4 px ink border, its 4 px lip) and the fill inside its border.
	local top = rowHeight + CFG.rowGap
	local lip: Frame = Create("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Colors.inkUI,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top + b.lip),
		Size = UDim2.fromOffset(size.X, b.height),
		ZIndex = Z,
		Active = false,
		Parent = pose,
	})
	Theme.corner(b.height / 2, lip)
	local trough: Frame = Create("Frame", {
		Name = "Trough",
		BackgroundColor3 = Theme.Colors.inkUI,
		BackgroundTransparency = 1 - b.troughAlpha,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.fromOffset(size.X, b.height),
		ZIndex = Z,
		Active = false,
		Parent = pose,
	})
	Theme.corner(b.height / 2, trough)
	MatchKit.inner(Theme.stroke(Theme.Colors.inkUI, b.border, trough))
	local innerHeight = b.height - 2 * b.border
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(b.border, b.border),
		Size = UDim2.fromOffset(0, innerHeight),
		ZIndex = Z,
		Active = false,
		Parent = trough,
	})
	Theme.foam(fill, {
		radius = innerHeight / 2,
		stroke = 0,
		top = b.highlight,
		fixedHeight = innerHeight,
		colors = {
			face = Palette.StickerGripTop,
			faceEnd = Palette.StickerGripEnd,
			top = Palette.StickerGripTop:Lerp(WHITE, b.highlightAlpha),
		},
	})
	return { root = root, fit = fit, pose = pose, number = number, fill = fill, size = size }
end

-- Public

function RespawnBar.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local shade = vignette(ctx.root)
	local shadeFade = Tweens.fadeGroup(shade)
	local made = bar(ctx.root)
	local poser = Tweens.poser(made.pose)
	local correction: ColorCorrectionEffect? = nil
	local since: number? = nil -- os.clock() the bar came in (nil: hidden)
	local innerWidth = CFG.width - 2 * CFG.bar.border

	local function hide()
		since = nil
		shade.Visible = false
		made.root.Visible = false
		local current = correction
		correction = nil
		if current then
			current:Destroy()
		end
	end

	local function place()
		-- [P] only the thumbstick zone: the touch buttons do nothing while you are knocked out (gone at the respawn).
		local zone: { MatchHudFormat.Area } = {}
		for _, area in ctx.touchAreas() do
			if area.kind == "zone" then
				table.insert(zone, area)
			end
		end
		local at = MatchHudFormat.barPlace(ctx.canvas(), zone, ctx.shared.cardRect, made.size, {
			bottom = CFG.bottom,
			gap = CFG.gap,
			top = CFG.top,
			scales = CFG.scales,
			fitMin = Config.UI.Match.compact.fitMin,
		})
		made.root.Position = UDim2.fromOffset(math.round(at.x), math.round(at.y))
		made.fit.Scale = at.scale
	end

	local piece = {}

	function piece.update(_self: any, view: any, now: number)
		if not MatchHudFormat.respawnShows(view) then
			if since ~= nil then
				local back = view.you.alive == true and (view.matchPhase == "Active" or view.matchPhase == "Overtime")
				hide()
				if back then
					ctx.play("ui.pop", nil, "ui.click") -- M:553: your respawn
				end
			end
			return
		end
		local clock = os.clock()
		local reduced = ctx.reduced()
		if since == nil then
			since = clock
			shade.Visible = true
			made.root.Visible = true
			local effect: ColorCorrectionEffect = Instance.new("ColorCorrectionEffect")
			effect.Name = CORRECTION_NAME
			effect.Saturation = 0
			effect.Brightness = 0
			effect.Parent = Lighting
			correction = effect
		end
		local t = clock - (since :: number)
		-- sdFade (M:61): the vignette and the colour change together.
		local fadeMs = if reduced then math.min(VIGNETTE.fadeMs, FADE_MS) else VIGNETTE.fadeMs
		local k = if fadeMs > 0 then Tweens.curve(VIGNETTE.curve)(math.clamp(t / (fadeMs / 1000), 0, 1)) else 1
		shadeFade:setAlpha(k)
		local effect = correction
		if effect then
			effect.Saturation = VIGNETTE.saturation * k
			effect.Brightness = VIGNETTE.brightness * k
		end
		local enter = CFG.enter
		poser:set(MatchHudFormat.trackPose(enter.frames, t, enter.ms, enter.curve, nil, reduced, FADE_MS))
		local respawnAt = view.you.respawnAt :: number
		made.number.Text = tostring(MatchHudFormat.respawnLeft(respawnAt, now))
		local share = MatchHudFormat.respawnShare(respawnAt, now, MATCH.respawnSeconds)
		made.fill.Size = UDim2.fromOffset(math.round(innerWidth * share), made.fill.Size.Y.Offset)
		place()
	end

	function piece.destroy(_self: any)
		hide()
		shade:Destroy()
		made.root:Destroy()
	end

	return piece :: any
end

return RespawnBar
