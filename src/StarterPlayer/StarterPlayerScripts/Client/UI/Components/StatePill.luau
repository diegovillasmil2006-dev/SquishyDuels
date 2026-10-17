--!strict
-- StatePill (client only). UI FINAL R5 ([PR23], plan work/ui/PLAN.md R5; `H:n` = "Squishy Duels HUD.dc.html" line n):
-- a window's loading, data-error or filter-empty state as one pill in the design's timer-pill look (H:391,
-- Config.UI.Sticker.statePill): 40 high, padding 0 16 0 4, gap 6, a 3 px ink border drawn inside, full radius, the well
-- #5B36D9, a 30 px icon slot and the text 16 px (the design's 15, PR2) in the soft white (#F3EDFF). With spinner =
-- true the icon slot holds the Button spinner (H:465: an ink ring whose top quarter is white, one turn every .7 s; at
-- rest under ReducedMotion). It grows with its text (AutomaticSize X); the caller places it.
--   local pill = StatePill.new({ name = "Loading", text = Strings.common.loading, spinner = true, parent = body })
--   pill:setText(text);   pill.root.Visible = false;   pill:destroy()

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
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Spec = {
	name: string,
	text: string,
	spinner: boolean?,
	layoutOrder: number?,
	parent: Instance?,
}

export type StatePill = {
	root: Frame,
	setText: (self: StatePill, text: string) -> (),
	destroy: (self: StatePill) -> (),
}

-- Constants

local PILL = Config.UI.Sticker.statePill
local SPINNER_RING_PX = 5 -- H:465 (as Button's spinner)
local SPINNER_TURN_SECONDS = 0.7 -- H:465
local ARC_SHARE = 0.15 -- the white arc: the ring's top share
local ARC_EDGE = 0.001
local WHITE = Color3.new(1, 1, 1)

-- Module table

local StatePill = {}

function StatePill.new(spec: Spec): StatePill
	local cleanup = Cleanup.new()
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundColor3 = Theme.Colors.biscuit, -- the well #5B36D9 (H:391)
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, PILL.height),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.corner(PILL.height, root)
	local stroke = Theme.stroke(Theme.Colors.inkUI, PILL.border, root)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PILL.padLeft),
		PaddingRight = UDim.new(0, PILL.padRight),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, PILL.gap, root, Enum.HorizontalAlignment.Left)
	local icon: Frame = Create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PILL.iconPx, PILL.iconPx),
		LayoutOrder = 1,
		Parent = root,
	})
	if spec.spinner then
		local spinner: Frame = Create("Frame", {
			Name = "Spinner",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = icon,
		})
		Theme.corner(PILL.iconPx, spinner)
		local ring = Theme.stroke(WHITE, SPINNER_RING_PX, spinner)
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, WHITE),
				ColorSequenceKeypoint.new(ARC_SHARE, WHITE),
				ColorSequenceKeypoint.new(ARC_SHARE + ARC_EDGE, Theme.Colors.inkUI),
				ColorSequenceKeypoint.new(1, Theme.Colors.inkUI),
			}),
			Parent = ring,
		})
		cleanup:add(Scheduler.add(function(dt: number): boolean
			if not root.Visible then
				return true -- shown only now and then (a loading window): no work while hidden
			elseif Tweens.reducedMotion() then
				spinner.Rotation = 0
			else
				spinner.Rotation = (spinner.Rotation + 360 * dt / SPINNER_TURN_SECONDS) % 360
			end
			return true
		end, "render"))
	end
	local label = Theme.label({
		Name = "Text",
		Text = spec.text,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = root,
	}, "Small", nil, Theme.Colors.textFaint)
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: StatePill
	self.root = root
	function self.setText(_: StatePill, text: string)
		label.Text = text
	end
	function self.destroy(_: StatePill)
		cleanup:clean()
	end
	return self
end

return StatePill
