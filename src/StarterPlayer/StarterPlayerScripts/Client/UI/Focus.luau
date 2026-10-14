--!strict
-- Focus (client only). DESIGN §11.4 (controller navigation), §9.13 "Focused (gamepad)".
-- * prepareGroup(root): every modal/dialog root gets SelectionGroup = true and SelectionBehaviorUp/Down/Left/Right =
--   Stop, so the gamepad cursor never leaves it. Closed panels use Visible = false, never an invisible full-screen
--   button (that blocks directional selection since the 2025 update).
-- * follow(root, primary, cleanup): on open with PreferredInput == Gamepad, and whenever the input switches to Gamepad
--   while the root is visible, the primary button becomes GuiService.SelectedObject (falls back to GuiService:Select).
-- * capture() / restore(token): the focus before a panel opened comes back when it closes, if that object is still in
--   a PlayerGui and visible; otherwise nil. restoreWithin(token, root) does it only while the selection is still inside
--   `root` or empty (a non-modal panel never takes the focus back from a modal opened over it).
-- * decorate(button, radius?): the custom SelectionImageObject (outer InkUI 3 px + inner white 2 px strokes, readable
--   on light and dark backgrounds; UI FINAL R1, plan §2: the ink outside, as white is 1.1:1 on the pink windows), its
--   corners following the button's corner radius (foam UI: default Theme.Radius.button; one ring per radius, built
--   once). Button prompts are text ("E", "X", "R2", "B") in Strings.
-- AutoSelectGuiEnabled stays on (V).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

-- Types

export type Token = { previous: GuiObject?, restored: boolean }

-- Constants

local FOCUS = Config.UI.motion.focus
local OUTSET_PX = FOCUS.outerStrokePx + FOCUS.innerStrokePx

-- Module table

local Focus = {}

-- Private

local selectionImages: { [number]: Frame } = {}

local function isUsable(object: GuiObject?): boolean
	if object == nil or object.Parent == nil then
		return false
	end
	if object:FindFirstAncestorOfClass("PlayerGui") == nil then
		return false
	end
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not (node :: GuiObject).Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

-- Public

function Focus.prepareGroup(root: GuiObject)
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

function Focus.isGamepad(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

-- The shared selection adornment for objects with `radiusPx` corners (default Theme.Radius.button; built once per
-- radius, never parented: Roblox draws it over the selected object). The rings are concentric with the object's
-- corners.
function Focus.selectionImage(radiusPx: number?): Frame
	local radius = math.max(0, math.floor(radiusPx or Theme.Radius.button))
	local cached = selectionImages[radius]
	if cached then
		return cached
	end
	local outer: Frame = Create("Frame", {
		Name = "SD_FocusRing",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, OUTSET_PX * 2, 1, OUTSET_PX * 2),
		Position = UDim2.fromOffset(-OUTSET_PX, -OUTSET_PX),
	})
	Theme.corner(radius + OUTSET_PX, outer)
	Theme.stroke(Theme.Colors.inkUI, FOCUS.outerStrokePx, outer)
	local inner: Frame = Create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -FOCUS.outerStrokePx * 2, 1, -FOCUS.outerStrokePx * 2),
		Position = UDim2.fromOffset(FOCUS.outerStrokePx, FOCUS.outerStrokePx),
		Parent = outer,
	})
	Theme.corner(radius + FOCUS.innerStrokePx, inner)
	Theme.stroke(Theme.Colors.white, FOCUS.innerStrokePx, inner)
	selectionImages[radius] = outer
	return outer
end

function Focus.decorate(object: GuiObject, radiusPx: number?)
	object.Selectable = true
	object.SelectionImageObject = Focus.selectionImage(radiusPx)
end

-- Selects `target` when the player uses a gamepad (nil-safe). Returns true when the selection changed.
function Focus.select(target: GuiObject?): boolean
	if target == nil or not Focus.isGamepad() or not isUsable(target) then
		return false
	end
	local ok = pcall(function()
		GuiService.SelectedObject = target
	end)
	return ok
end

-- Selects the primary object of `root` now (gamepad only) and again whenever the input switches to Gamepad while
-- `root` is visible. Connections go into `cleanup`.
function Focus.follow(root: GuiObject, primary: () -> GuiObject?, cleanup: Cleanup.Cleanup)
	local function apply()
		if not isUsable(root) then
			return
		end
		local target = primary()
		if not Focus.select(target) and Focus.isGamepad() then
			pcall(function()
				GuiService:Select(root)
			end)
		end
	end
	apply()
	cleanup:add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		if Focus.isGamepad() then
			apply()
		end
	end))
end

-- The focus before a panel opens.
function Focus.capture(): Token
	return { previous = GuiService.SelectedObject, restored = false }
end

-- Puts the captured focus back if it is still usable, else clears the selection. Idempotent.
function Focus.restore(token: Token)
	if token.restored then
		return
	end
	token.restored = true
	local previous = token.previous
	pcall(function()
		GuiService.SelectedObject = if isUsable(previous) then previous else nil
	end)
end

-- restore(token), but only while the panel `root` that took the focus still holds it (the selection is inside `root`)
-- or nothing is selected. A selection that moved on since, into a modal opened over a non-modal panel (Inspect over
-- the duel result card), is left alone: that modal gives the focus back when it closes (Part 6 review).
function Focus.restoreWithin(token: Token, root: Instance)
	local selected = GuiService.SelectedObject
	if selected ~= nil and not selected:IsDescendantOf(root) then
		return
	end
	Focus.restore(token)
end

-- Clears the selection if it is inside `root` (a panel closing without a saved token).
function Focus.releaseWithin(root: Instance)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(root) then
		pcall(function()
			GuiService.SelectedObject = nil
		end)
	end
end

return Focus
