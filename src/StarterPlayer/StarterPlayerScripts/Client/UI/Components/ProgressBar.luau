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

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)

local UI = script.Parent.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Spec = {
	name: string,
	fraction: number?, -- 0..1 (default 0)
	accent: Theme.AccentName?, -- default "mint"
	heightPx: number?, -- base px; default 14
	widthPx: number?, -- base px; nil = the parent's width
	layoutOrder: number?,
	parent: Instance?,
}

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
local FILL_BEVEL_SHARE = 0.25 -- the fill's shade band, as a share of the bar's height (the design's 3 of 16 px ≈ 0.2)
local FILL_GLOSS_SHARE = 0.3 -- Candy UI: the fill's light band along its top
local FILL_GLOSS_MIX = 0.4 -- how far that band is towards white

-- The fill's foam colours for an accent (Candy UI: the gloss band).
local function fillColors(accent: Theme.Accent): Theme.FoamColors
	return { face = accent.face, top = accent.face:Lerp(Color3.new(1, 1, 1), FILL_GLOSS_MIX), bevel = accent.shade }
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
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundColor3 = Theme.Colors.track,
		BorderSizePixel = 0,
		Size = if spec.widthPx then UDim2.fromOffset(spec.widthPx, height) else UDim2.new(1, 0, 0, height),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.corner(height, root)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, root)
	Theme.rim(root, Theme.Colors.rim, 0.75, 1)
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
		top = height * FILL_GLOSS_SHARE,
		bevel = height * FILL_BEVEL_SHARE,
		colors = fillColors(accent),
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
		foam:paint(fillColors(Theme.accent(name)))
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
