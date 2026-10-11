--!strict
-- ScrollHint (client only). Foam fix round 2 (2026-10-09; DESIGN §11.2: what scrolls on a phone shows that it scrolls).
-- On touch, Roblox draws a ScrollingFrame's scroll bar only while the list moves, so a list cut at its window's edge
-- looked like its end (Settings' two switches, Inspect's "How to get", the Squishies and Shop details on phones). This
-- rail keeps the bar on screen on touch while the list is longer than its window: a faint InkUI track and an InkUI
-- thumb (Layout.scrollThumb) over the strip where the engine's bar goes (the thumb follows the scroll, so it lines up
-- with the engine's bar while the list moves). With a mouse, keys or a gamepad it hides (the engine's bar shows there).
--   local hint = ScrollHint.new({ scroll = list, parent = holder })
--   hint.root        the rail (Frame "ScrollRail", not Active, ZIndex 2, hidden until needed): the caller places it over
--                    the list window's right edge inside `parent` (a frame without a layout), e.g. AnchorPoint (1, 0) at
--                    Position (1, 0), and sizes it as wide as the list's ScrollBarThickness and as tall as its window
--                    (it starts 0 px tall)
--   hint:destroy()
-- It follows the list's window, canvas and scroll position and the player's PreferredInput by itself; it never sizes
-- anything it listens to.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	scroll: ScrollingFrame,
	parent: Instance,
	name: string?, -- default "ScrollRail"
}

export type ScrollHint = {
	root: Frame,
	destroy: (self: ScrollHint) -> (),
}

-- Constants

local TRACK_TRANSPARENCY = 0.82 -- reading: a faint lane; the thumb is solid InkUI like the engine's bar
local ZINDEX = 2 -- over the list beside it

-- Module table

local ScrollHint = {}

-- Private

local function onTouch(): boolean
	local ok, input = pcall(function(): Enum.PreferredInput
		return UserInputService.PreferredInput
	end)
	return ok and input == Enum.PreferredInput.Touch
end

-- The product of the UIScales from `object` up to its ScreenGui: the list's CanvasPosition is in its own unscaled px,
-- its window and canvas sizes in screen px (the reading of InventoryController's and GripController's scroll follow).
local function drawnScale(object: Instance): number
	local scale = 1
	local node: Instance? = object
	while node ~= nil do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	return scale
end

-- Public

function ScrollHint.new(spec: Spec): ScrollHint
	local cleanup = Cleanup.new()
	local scroll = spec.scroll
	-- Candy UI: a light rail and thumb, so they read on the dark windows.
	local rail: Frame = Create("Frame", {
		Name = spec.name or "ScrollRail",
		BackgroundColor3 = Theme.Colors.text,
		BackgroundTransparency = TRACK_TRANSPARENCY,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(scroll.ScrollBarThickness, 0), -- nothing shows before the caller sizes it
		Active = false,
		Selectable = false,
		Visible = false,
		ZIndex = ZINDEX,
	})
	cleanup:add(rail)
	Theme.corner(Theme.Radius.pill, rail)
	local thumb: Frame = Create("Frame", {
		Name = "Thumb",
		BackgroundColor3 = Theme.Colors.ink2,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = ZINDEX,
		Parent = rail,
	})
	Theme.corner(Theme.Radius.pill, thumb)

	local function update()
		local offset = scroll.CanvasPosition.Y * drawnScale(scroll)
		local bar = Layout.scrollThumb(scroll.AbsoluteWindowSize.Y, scroll.AbsoluteCanvasSize.Y, offset)
		local shown = bar.shown and onTouch()
		if rail.Visible ~= shown then
			rail.Visible = shown
		end
		if shown then
			thumb.Size = UDim2.fromScale(1, bar.size)
			thumb.Position = UDim2.fromScale(0, bar.top)
		end
	end
	for _, property in { "AbsoluteWindowSize", "AbsoluteCanvasSize", "CanvasPosition" } do
		cleanup:add(scroll:GetPropertyChangedSignal(property):Connect(update))
	end
	local okSignal, inputChanged = pcall(function(): RBXScriptSignal
		return UserInputService:GetPropertyChangedSignal("PreferredInput")
	end)
	if okSignal then
		cleanup:add(inputChanged:Connect(update))
	end
	update()
	rail.Parent = spec.parent

	local self = {} :: ScrollHint
	self.root = rail

	function self.destroy(_: ScrollHint)
		cleanup:clean()
	end

	return self
end

return ScrollHint
