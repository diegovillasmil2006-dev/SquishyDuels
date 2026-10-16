--!strict
-- ProgressBar (client only). Foam UI restyle (spec 2026-10-09, "Progress bar (Biscuit track, accent fill, ink
-- stroke)"; Butter progress bars remapped to Mint): the Grip bar, quest progress, stat bars.
--   local bar = ProgressBar.new({ name = "Bar", fraction = 0.4, parent = card })   -- fills its parent's width
--   bar:set(0.64, true)   -- eases there (the variant's fillMs on Config.UI.curves.bars; at once under ReducedMotion)
--   bar:setAccent("sky")
-- A Biscuit pill track with the InkUI 2 px outline of bars; the fill is a pill in the accent (default Mint) with its
-- shade along the bottom (FILL_BEVEL_SHARE of the height). The fill hides at 0. The bar shows a share only: a "12 / 20"
-- text goes next to it, never inside it (the caller's label). ProgressBar.clamp(fraction) is the shown share, pure.
-- Candy UI (UI overhaul 2026-10-11): the track is the darkest surface (Colors.track, with a faint inner rim so it reads
-- on a recessed field too) and the fill a glossy jelly: a light
-- band along its top (FILL_GLOSS_SHARE of the height, the face towards white) over the face and its shade.
-- UI FINAL R1 (H:84-85, H:187, H:240, H:271, H:367, H:444), replacing that look: spec.variant picks the design's bar
-- (Config.UI.Sticker.bars, default "stat"): the trough (StickerTrough; the Grip track white at .7), its 3 px border
-- (the ink; the stat, quest and odds bars StickerInkDeep), the quest trough's inner shade along its top, and the fill:
-- the accent's gradient (top -> shade; the Grip bar its own green, the collected bar the yellow, the volume bar the
-- pink) under its top highlight. Readings: the border stays outside the box (a caller's height is the inner track, as
-- before, until each screen's own round sizes it); the fill is a pill (Roblox clips to rectangles, not the round
-- track); no rim; the Grip bar's 3 px ink lip (H:84) comes with R4's Grip row.
-- UI FINAL R2 (P9, G2.5; H:84-85, H:187, H:240, H:271, H:367): the border is drawn INSIDE the bar's height (the
-- design's border-box; heightPx defaults to the variant's design height, Config.UI.Sticker.bars) and the fill sits
-- inside it (a bar too thin for its border keeps a 2 px track: the border thins to fit, a reading); the fill eases
-- to a new value over the variant's fillMs on the design's cubic-bezier(.3,1.5,.5,1) (Config.UI.Sticker
-- .barFillCurve, a Scheduler render effect), drawn at most full: the curve's overshoot past 100% is cut at the
-- track's end as the design's trough clips it (overflow:hidden, H:84, H:187, H:240, H:367; ProgressBar.fillAt,
-- pure); the Grip fill is never narrower than minFillPx (H:85 min-width: shown at 0 too); the Grip and quest fills
-- carry their moving shine strip (Config.UI.Sticker.barShines / shines, Anim/UiIdle "shine", Theme.shineBand).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Spec = {
	name: string,
	fraction: number?, -- 0..1 (default 0)
	accent: Theme.AccentName?, -- default "mint" (the fill, unless the variant has its own)
	variant: Variant?, -- default "stat"
	heightPx: number?, -- base px, the border inside it; default the variant's design height
	widthPx: number?, -- base px; nil = the parent's width
	layoutOrder: number?,
	parent: Instance?,
}

-- UI FINAL R1: the design's bars (Config.UI.Sticker.bars).
export type Variant = "grip" | "stat" | "quest" | "odds" | "collected" | "volume"

export type ProgressBar = {
	root: Frame,
	fill: Frame,
	set: (self: ProgressBar, fraction: number, animate: boolean?) -> (),
	get: (self: ProgressBar) -> number,
	setAccent: (self: ProgressBar, accent: Theme.AccentName) -> (),
	destroy: (self: ProgressBar) -> (),
}

-- Constants

local DEFAULT_HEIGHT_PX = 14
local DEFAULT_VARIANT = "stat"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local VARIANTS = Config.UI.Sticker.bars
-- The variants with a fill of their own (else the accent's), and with the deep ink border.
local OWN_FILL: { [string]: { top: Color3, bottom: Color3 } } = {
	grip = { top = Palette.StickerGripTop, bottom = Palette.StickerGripEnd }, -- H:85
	collected = { top = Palette.StickerYellowTop, bottom = Palette.StickerYellowEnd }, -- H:187
	volume = { top = Palette.StickerVolumeTop, bottom = Palette.StickerVolumeEnd }, -- H:444
}
local DEEP_BORDER: { [string]: boolean } = { stat = true, quest = true, odds = true } -- H:240, H:271, H:367

-- The fill's colours: the variant's own gradient or the accent's (top -> mid -> shade) under its top highlight.
local function fillColors(variant: string, accent: Theme.Accent): Theme.FoamColors
	local look = VARIANTS[variant] or VARIANTS[DEFAULT_VARIANT]
	local own = OWN_FILL[variant]
	local top = if own then own.top else accent.top
	local mid = if own then nil else accent.mid
	local colors: Theme.StickerColors = {
		face = top,
		mid = mid,
		midAt = if mid then accent.midAt else nil,
		faceEnd = if own then own.bottom else accent.shade,
		top = top:Lerp(WHITE, look.fillHighlightAlpha or 0),
	}
	return colors :: any
end
local STICKER = Config.UI.Sticker
local FILL_CURVE = Tweens.curve(STICKER.barFillCurve) -- H:85, H:187, H:240, H:367
local MIN_TRACK_PX = 2 -- reading: a bar too thin for its border keeps this much track

-- Module table

local ProgressBar = {}

ProgressBar.HEIGHT_PX = DEFAULT_HEIGHT_PX

-- Public

-- The share a bar shows: 0..1, 0 for anything that is not a finite number.
function ProgressBar.clamp(fraction: number?): number
	if type(fraction) ~= "number" or fraction ~= fraction then
		return 0
	end
	return math.clamp(fraction, 0, 1)
end

-- UI FINAL R2: the fill's share u (0..1) into an eased change from `from` to `to`: the design's overshoot curve,
-- never past the track (the trough clips it, H:84) nor below 0.
function ProgressBar.fillAt(from: number, to: number, u: number): number
	return math.clamp(from + (to - from) * FILL_CURVE(math.clamp(u, 0, 1)), 0, 1)
end

function ProgressBar.new(spec: Spec): ProgressBar
	local cleanup = Cleanup.new()
	local variant: string = if spec.variant and VARIANTS[spec.variant] then spec.variant else DEFAULT_VARIANT
	local look = VARIANTS[variant]
	local height = spec.heightPx or look.height or DEFAULT_HEIGHT_PX
	-- UI FINAL R2 (P9): the border inside the height; a MIN_TRACK_PX track at least.
	local border = math.clamp(math.floor((height - MIN_TRACK_PX) / 2), 0, look.border or Theme.Stroke.bar)
	local innerHeight = height - 2 * border
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundColor3 = if look.troughAlpha then Theme.Colors.white else Theme.Colors.track,
		BackgroundTransparency = if look.troughAlpha then 1 - look.troughAlpha else 0,
		BorderSizePixel = 0,
		Size = if spec.widthPx then UDim2.fromOffset(spec.widthPx, height) else UDim2.new(1, 0, 0, height),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	if look.troughShadePx then
		-- H:367: the quest trough's inner shade along its top (the trough's own colour towards black), under the
		-- border.
		Theme.foam(root, {
			radius = height,
			stroke = 0,
			mode = "tint",
			top = border + look.troughShadePx,
			colors = { face = Theme.Colors.track, top = Theme.Colors.track:Lerp(BLACK, look.troughShadeAlpha or 0) },
		})
	else
		Theme.corner(height, root)
	end
	if border > 0 then
		local stroke =
			Theme.stroke(if DEEP_BORDER[variant] then Palette.StickerInkDeep else Theme.Colors.inkUI, border, root)
		pcall(function()
			(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner -- H:84: the border-box
		end)
	end
	-- The track inside the border: the fill's room.
	local inner: Frame = Create("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(border, border),
		Size = UDim2.new(1, -2 * border, 1, -2 * border),
		Parent = root,
	})
	local minFill = look.minFillPx or 0
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = minFill > 0,
		ClipsDescendants = true,
		Parent = inner,
	})
	if minFill > 0 then
		Create("UISizeConstraint", { MinSize = Vector2.new(minFill, 0), Parent = fill }) -- H:85 min-width
	end
	local accent = Theme.accent(spec.accent or "mint")
	local foam = Theme.foam(fill, {
		radius = innerHeight,
		stroke = 0,
		top = look.fillHighlightPx or 0,
		colors = fillColors(variant, accent),
		fixedHeight = innerHeight,
	})
	-- UI FINAL R2 (G4.13): the Grip / quest fill's moving shine strip (H:85, H:367).
	local shineName = (STICKER.barShines :: any)[variant]
	if shineName then
		local shine = (STICKER.shines :: any)[shineName]
		local strip: Frame = Create("Frame", {
			Name = "SD_Shine",
			BackgroundTransparency = 1,
			Size = UDim2.new(0, shine.px, 1, 0),
			Active = false,
			Parent = fill,
		})
		Theme.shineBand(strip, shine.alpha, shine.slantDeg) -- H:28: the leaning band
		local handle = UiIdle.add(strip, "shine", { periodS = shine.periodS })
		cleanup:add(function()
			if handle then
				handle:remove()
			end
		end)
	end

	local value = 0
	local motion: Scheduler.Handle? = nil
	local function stopTween()
		local current = motion
		motion = nil
		if current then
			current:disconnect()
		end
	end
	cleanup:add(stopTween)

	local self = {} :: ProgressBar
	self.root = root
	self.fill = fill

	function self.set(_: ProgressBar, fraction: number, animate: boolean?)
		value = ProgressBar.clamp(fraction)
		stopTween()
		local shownAtZero = minFill > 0 -- H:85: the Grip fill keeps its min-width at 0
		local ms = look.fillMs or 0
		if animate and ms > 0 and not Tweens.reducedMotion() then
			local from = fill.Size.X.Scale
			local to = value
			fill.Visible = true
			local elapsed = 0
			motion = Scheduler.add(function(dt: number): boolean
				elapsed += dt
				local u = math.min(elapsed * 1000 / ms, 1)
				fill.Size = UDim2.fromScale(ProgressBar.fillAt(from, to, u), 1)
				if u >= 1 then
					fill.Visible = to > 0 or shownAtZero
					motion = nil
					return false
				end
				return true
			end, "render")
		else
			fill.Size = UDim2.fromScale(value, 1)
			fill.Visible = value > 0 or shownAtZero
		end
	end

	function self.get(_: ProgressBar): number
		return value
	end

	function self.setAccent(_: ProgressBar, name: Theme.AccentName)
		foam:paint(fillColors(variant, Theme.accent(name)))
	end

	function self.destroy(_: ProgressBar)
		cleanup:clean()
	end

	self:set(spec.fraction or 0, false)
	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return ProgressBar
