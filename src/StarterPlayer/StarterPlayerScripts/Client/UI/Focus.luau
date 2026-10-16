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
--   once). Button prompts are text ("E", "X", "R2", "B") in Strings. UI FINAL R2 (PR24): `insets` { top, bottom }
--   (base px) keep the ring off the part of the object that is not the drawn face (a Button's lip under it, a
--   chip's touch padding), so it goes round the face; one ring per radius and insets. The Button itself takes its
--   design hover pose while selected and draws a copy of the ring inside its posed face (UI/Components/Button);
--   blank() is the clear selection image it gives its hit box instead (Roblox's selection stays).
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

-- UI FINAL R2 (PR24): what the ring leaves out at the top and the bottom of the object (base px).
export type Insets = { top: number, bottom: number }

-- Constants

local FOCUS = Config.UI.motion.focus
local OUTSET_PX = FOCUS.outerStrokePx + FOCUS.innerStrokePx

-- Module table

local Focus = {}

-- Private

local selectionImages: { [string]: Frame } = {}
local blankImage: Frame? = nil

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
-- radius and insets, never parented: Roblox draws it over the selected object). The rings are concentric with the
-- object's corners; UI FINAL R2 (PR24): `insets` move them in from its top and bottom (the face of a Button).
function Focus.selectionImage(radiusPx: number?, insets: Insets?): Frame
	local radius = math.max(0, math.floor(radiusPx or Theme.Radius.button))
	local top = if insets then math.max(0, insets.top) else 0
	local bottom = if insets then math.max(0, insets.bottom) else 0
	local key = `{radius}:{top}:{bottom}`
	local cached = selectionImages[key]
	if cached then
		return cached
	end
	local outer: Frame = Create("Frame", {
		Name = "SD_FocusRing",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, OUTSET_PX * 2, 1, OUTSET_PX * 2 - top - bottom),
		Position = UDim2.fromOffset(-OUTSET_PX, top - OUTSET_PX),
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
	selectionImages[key] = outer
	return outer
end

-- UI FINAL R2 (PR24): a clear selection image (built once, never parented), for an object that draws its own ring.
function Focus.blank(): Frame
	local made = blankImage
	if made then
		return made
	end
	local frame: Frame = Create("Frame", {
		Name = "SD_FocusBlank",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	blankImage = frame
	return frame
end

function Focus.decorate(object: GuiObject, radiusPx: number?, insets: Insets?)
	object.Selectable = true
	object.SelectionImageObject = Focus.selectionImage(radiusPx, insets)
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
