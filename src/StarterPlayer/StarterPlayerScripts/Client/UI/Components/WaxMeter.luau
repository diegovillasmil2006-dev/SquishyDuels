--!strict
-- WaxMeter (client only). Spec phase2-squeeze §1.18, §3.7: the knead screen's wax HUD at the top centre of Inspect's
-- stage (design: the FP page html:72-77, 95): one row in a paper box with an ink outline and drop band, "Wax coat", the
-- coat bar (a white track, the WaxBar fill), the state word (WaxState) and the crack count (mono, faded). Sizes are
-- Config.UI.Knead's (base px), colours Art/Palette's Knead* / Wax* (the design's exact hex, user decision 2026-10-11),
-- text from UI/KneadFormat. Fonts: Fredoka -> FredokaOne (the Chip kind), DM Mono -> RobotoMono, both at the Chip size
-- (the design's 12 / 10.5 px are under Config.UI.minTextSize). It never takes input (Active false).
--   local meter = WaxMeter.new({ name = "WaxMeter", parent = stage.front, zIndex = 3 })
--   meter:set(hud, animate?)   a KneadFormat.Hud; the bar eases over fillMs (at once under ReducedMotion)
--   meter:setCompact(on)       phones (layout class "compact"; the design hides the HUD under 820 px, the game is phone
--                              first, user decision 2026-10-11): the bar and the state word only
--   meter.root, meter:destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local KneadFormat = require(UI.KneadFormat)
local Theme = require(UI.Theme)
local Tweens = require(Client.Anim.Tweens)

export type Spec = {
	name: string,
	parent: Instance?,
	zIndex: number?,
}

export type WaxMeter = {
	root: Frame,
	set: (self: WaxMeter, hud: KneadFormat.Hud, animate: boolean?) -> (),
	setCompact: (self: WaxMeter, on: boolean) -> (),
	destroy: (self: WaxMeter) -> (),
}

local KNEAD = Config.UI.Knead
local TEXT_KIND: Theme.TextKind = "Chip"
local MONO_FONT = Font.fromEnum(Enum.Font.RobotoMono)

local WaxMeter = {}

local function textLabel(name: string, order: number, color: Color3, zIndex: number): TextLabel
	local label: TextLabel = Create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = order,
		ZIndex = zIndex,
		Active = false,
	})
	Theme.text(label, TEXT_KIND, nil, color)
	label.TextWrapped = false
	return label
end

function WaxMeter.new(spec: Spec): WaxMeter
	local cleanup = Cleanup.new()
	local z = spec.zIndex or 1
	local root: Frame = Create("Frame", {
		Name = spec.name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, KNEAD.hudTopPx),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Palette.KneadPaper,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = z,
	})
	cleanup:add(root)
	Theme.foam(root, {
		radius = KNEAD.hudRadius,
		stroke = KNEAD.hudStrokePx,
		strokeColor = Palette.KneadInk,
		drop = KNEAD.hudDropPx,
		colors = { face = Palette.KneadPaper, drop = Palette.KneadInk },
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, KNEAD.hudPadX),
		PaddingRight = UDim.new(0, KNEAD.hudPadX),
		PaddingTop = UDim.new(0, KNEAD.hudPadY),
		PaddingBottom = UDim.new(0, KNEAD.hudPadY + KNEAD.hudDropPx), -- the content never sits on the drop band
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, KNEAD.hudGapPx, root)

	local title = textLabel("Title", 1, Palette.KneadInk, z)
	title.Text = Strings.knead.waxCoat
	title.Parent = root

	local track: Frame = Create("Frame", {
		Name = "Track",
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(KNEAD.trackWidth, KNEAD.trackHeight),
		LayoutOrder = 2,
		ZIndex = z,
		ClipsDescendants = true,
		Parent = root,
	})
	Theme.corner(KNEAD.trackHeight, track)
	Theme.stroke(Palette.KneadInk, KNEAD.trackStrokePx, track)
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Palette.WaxBar,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = track,
	})
	Theme.corner(KNEAD.trackHeight, fill)

	local state = textLabel("State", 3, Palette.WaxState, z)
	state.TextXAlignment = Enum.TextXAlignment.Left
	Create("UISizeConstraint", { MinSize = Vector2.new(KNEAD.stateMinWidth, 0), Parent = state })
	state.Parent = root

	local count = textLabel("Count", 4, Palette.KneadInk, z)
	count.FontFace = MONO_FONT
	count.TextTransparency = KNEAD.countTransparency
	count.Parent = root

	local tween: Tween? = nil
	local function stopTween()
		Tweens.cancel(tween)
		tween = nil
	end
	cleanup:add(stopTween)

	local self = {} :: WaxMeter
	self.root = root

	function self.set(_: WaxMeter, hud: KneadFormat.Hud, animate: boolean?)
		state.Text = hud.state
		count.Text = hud.count
		local goal = UDim2.fromScale(hud.fill, 1)
		if fill.Size == goal then
			return
		end
		stopTween()
		if animate and not Tweens.reducedMotion() then
			tween = Tweens.play(fill, KNEAD.fillMs, { Size = goal })
		else
			fill.Size = goal
		end
	end

	function self.setCompact(_: WaxMeter, on: boolean)
		title.Visible = not on
		count.Visible = not on
	end

	function self.destroy(_: WaxMeter)
		cleanup:clean()
	end

	self:set(KneadFormat.hud(1, 1, 0), false)
	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return WaxMeter
