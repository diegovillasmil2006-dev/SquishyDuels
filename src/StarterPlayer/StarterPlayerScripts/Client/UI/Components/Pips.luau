--!strict
-- Pips (client only). DESIGN §11.1 (UI/Components), §11.6 (duel HUD life pips), §9.8 (the victim's life pip pops).
--   local lives = Pips.new({ name = "YouLives", count = 3, filled = 3, color = Theme.Colors.sideA, parent = row })
--   lives:set(2, true)   -- the lost pip pops 1.2 -> 0 (Config.Vfx.Hit, Back In), then shows as a hollow ring
-- A filled pip is a solid circle in `color` with an InkUI ring (the 2 px outline of bars and chips, foam UI restyle);
-- an empty pip is the InkUI ring only, so the count reads without colour (the HUD shows the number next to it too).
-- Under ReducedMotion the pop is skipped.
-- Foam fix 2: the dots sit far enough apart that their outlines (drawn outside each dot) leave a gap between them;
-- Pips.rowWidth(count, sizePx?) is the row's resting width (every dot at full size), for layouts that must not follow
-- a dot's pop.

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
	count: number,
	filled: number,
	color: Color3,
	sizePx: number?,
	layoutOrder: number?,
	parent: Instance?,
}

export type Pips = {
	root: Frame,
	set: (self: Pips, filled: number, animate: boolean?) -> (),
	setCount: (self: Pips, count: number) -> (),
	destroy: (self: Pips) -> (),
}

type Pip = { frame: Frame, scale: UIScale, filled: boolean }

-- Constants

local HIT = Config.Vfx.Hit
local DEFAULT_SIZE_PX = 18
-- Foam fix 2: 6 px between two dots' outlines (each Theme.Stroke.bar wide, outside its dot); with 6 between the dots
-- themselves the outlines touched.
local GAP_PX = 6 + 2 * Theme.Stroke.bar

-- Module table

local Pips = {}

-- Public

-- The width (px before any UIScale) of a row of `count` dots `sizePx` big (default DEFAULT_SIZE_PX) at rest; 0 for
-- none or a bad count.
function Pips.rowWidth(count: number, sizePx: number?): number
	local n = if count == count and count > 0 and count < math.huge then math.floor(count) else 0
	if n <= 0 then
		return 0
	end
	return n * (sizePx or DEFAULT_SIZE_PX) + (n - 1) * GAP_PX
end

function Pips.new(spec: Spec): Pips
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, size),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.list(Enum.FillDirection.Horizontal, GAP_PX, root)

	local pips: { Pip } = {}
	local filledCount = 0

	local function paint(pip: Pip, filled: boolean)
		pip.filled = filled
		pip.frame.BackgroundTransparency = if filled then 0 else 1
		pip.scale.Scale = 1
	end

	local function build(count: number)
		for _, pip in pips do
			pip.frame:Destroy()
		end
		table.clear(pips)
		for i = 1, math.max(0, math.floor(count)) do
			local frame: Frame = Create("Frame", {
				Name = "Pip" .. i,
				LayoutOrder = i,
				BackgroundColor3 = spec.color,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(size, size),
				Parent = root,
			})
			Theme.corner(size, frame)
			Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, frame)
			local scale: UIScale = Create("UIScale", { Parent = frame })
			local pip: Pip = { frame = frame, scale = scale, filled = false }
			paint(pip, i <= filledCount)
			table.insert(pips, pip)
		end
	end

	local self = {} :: Pips
	self.root = root

	function self.set(_: Pips, filled: number, animate: boolean?)
		local target = math.clamp(math.floor(filled), 0, #pips)
		for i, pip in pips do
			local shouldFill = i <= target
			if pip.filled and not shouldFill and animate and not Tweens.reducedMotion() then
				pip.filled = false
				pip.scale.Scale = HIT.lifePipScaleFrom
				local tween =
					Tweens.play(pip.scale, HIT.lifePipMs, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				local connection: RBXScriptConnection
				connection = tween.Completed:Connect(function()
					connection:Disconnect()
					if not pip.filled then
						paint(pip, false)
					end
				end)
			elseif pip.filled ~= shouldFill then
				paint(pip, shouldFill)
			end
		end
		filledCount = target
	end

	function self.setCount(_: Pips, count: number)
		if math.floor(count) ~= #pips then
			build(count)
		end
	end

	function self.destroy(_: Pips)
		cleanup:clean()
	end

	filledCount = spec.filled
	build(spec.count)
	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return Pips
