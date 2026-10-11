--!strict
-- MeshQuality (client only; no connections). DESIGN §17.6.1, §18.3.4: the editable-mesh quality rule shared by the
-- giant pads and the jelly ripple's skins. "Low" on the compact layout (Config.UI.Breakpoints: viewport height below
-- compactBelowHeight or width below compactBelowWidth) or on a touch-only device (touch, and no keyboard, mouse or
-- gamepad); otherwise "High". The viewport can read 1 x 1 in the first frames, so pick() answers nil until it has a
-- real size and the caller asks again later.
--
--   MeshQuality.pick(viewport, input) -> Quality?   pure
--   MeshQuality.input() -> Input                    reads UserInputService
--   MeshQuality.forCamera(camera?) -> Quality?      pick(camera.ViewportSize, input()); nil without a camera
-- The giant pads' own once-per-session slow-frame downgrade stays in their controller.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Quality = "High" | "Low"
export type Input = { touch: boolean, keyboard: boolean, mouse: boolean, gamepad: boolean }

-- Constants

local BREAKPOINTS = Config.UI.Breakpoints
local MIN_REAL_PIXELS = 2 -- a smaller viewport is not laid out yet

-- Module table

local MeshQuality = {}

-- Public

-- The quality for a viewport size and the input devices; nil while the viewport is not real yet.
function MeshQuality.pick(viewport: Vector2, input: Input): Quality?
	if viewport.X < MIN_REAL_PIXELS or viewport.Y < MIN_REAL_PIXELS then
		return nil
	end
	local compact = viewport.Y < BREAKPOINTS.compactBelowHeight or viewport.X < BREAKPOINTS.compactBelowWidth
	local touchOnly = input.touch and not input.keyboard and not input.mouse and not input.gamepad
	return if compact or touchOnly then "Low" else "High"
end

-- The input devices this client has now.
function MeshQuality.input(): Input
	return {
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		mouse = UserInputService.MouseEnabled,
		gamepad = UserInputService.GamepadEnabled,
	}
end

-- The quality for this client's camera; nil without a camera or before the viewport is real.
function MeshQuality.forCamera(camera: Camera?): Quality?
	if camera == nil then
		return nil
	end
	return MeshQuality.pick(camera.ViewportSize, MeshQuality.input())
end

return MeshQuality
