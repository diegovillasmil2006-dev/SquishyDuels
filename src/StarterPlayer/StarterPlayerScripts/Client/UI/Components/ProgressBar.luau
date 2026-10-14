--!strict
-- ProgressBar (client only). Foam UI restyle (spec 2026-10-09, "Progress bar (Biscuit track, accent fill, ink
-- stroke)"; Butter progress bars remapped to Mint): the Grip bar, quest progress, stat bars.
--   local bar = ProgressBar.new({ name = "Bar", fraction = 0.4, parent = card })   -- fills its parent's width
--   bar:set(0.64, true)   -- eases there (Config.UI.motion.barFill; at once under ReducedMotion)
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
-- track); no rim; the moving shine strips (H:85, H:367) come with R2's idle loops and the Grip bar's 3 px ink lip
-- (H:84) with R4's Grip row.

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
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Spec = {
	name: string,
	fraction: number?, -- 0..1 (default 0)
	accent: Theme.AccentName?, -- default "mint" (the fill, unless the variant has its own)
	variant: Variant?, -- default "stat"
	heightPx: number?, -- base px; default 14
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
local MOTION = Config.UI.motion.barFill

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

function ProgressBar.new(spec: Spec): ProgressBar
	local cleanup = Cleanup.new()
	local height = spec.heightPx or DEFAULT_HEIGHT_PX
	local variant: string = if spec.variant and VARIANTS[spec.variant] then spec.variant else DEFAULT_VARIANT
	local look = VARIANTS[variant]
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
		-- H:367: the quest trough's inner shade along its top (the trough's own colour towards black).
		Theme.foam(root, {
			radius = height,
			stroke = 0,
			mode = "tint",
			top = look.troughShadePx,
			colors = { face = Theme.Colors.track, top = Theme.Colors.track:Lerp(BLACK, look.troughShadeAlpha or 0) },
		})
	else
		Theme.corner(height, root)
	end
	Theme.stroke(
		if DEEP_BORDER[variant] then Palette.StickerInkDeep else Theme.Colors.inkUI,
		look.border or Theme.Stroke.bar,
		root
	)
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
		Parent = root,
	})
	local accent = Theme.accent(spec.accent or "mint")
	local foam = Theme.foam(fill, {
		radius = height,
		stroke = 0,
		top = look.fillHighlightPx or 0,
		colors = fillColors(variant, accent),
		fixedHeight = height,
	})

	local value = 0
	local tween: Tween? = nil
	local function stopTween()
		Tweens.cancel(tween)
		tween = nil
	end
	cleanup:add(stopTween)

	local self = {} :: ProgressBar
	self.root = root
	self.fill = fill

	function self.set(_: ProgressBar, fraction: number, animate: boolean?)
		value = ProgressBar.clamp(fraction)
		stopTween()
		local goal = UDim2.fromScale(value, 1)
		if value > 0 then
			fill.Visible = true
		end
		if animate and not Tweens.reducedMotion() then
			local played = Tweens.play(fill, MOTION.ms, { Size = goal }, MOTION.style, MOTION.direction)
			tween = played
			if value <= 0 then
				played.Completed:Connect(function(state: Enum.PlaybackState)
					if state == Enum.PlaybackState.Completed and value <= 0 then
						fill.Visible = false
					end
				end)
			end
		else
			fill.Size = goal
			fill.Visible = value > 0
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
