--!strict
-- KneadOverlay (client only). Spec phase2-squeeze §1.18, §1.20, §3.7: the knead screen's 2D layer over Inspect's stage
-- (its front layer, above the viewport; design: the FP page html:59-77): the warm vignette, the wax HUD
-- (UI/Components/WaxMeter) and the fingertip ring. Built in code from Config.UI.Knead, Art/Palette and UI/KneadFormat;
-- nothing in it takes input.
--   local overlay = KneadOverlay.new(stage, options?)   -- a ViewportStage.Stage (its `front` and `root`); options.hud:
--                                              the wax HUD (user 2026-10-12: nil = Config.Wax.enabled; false = none,
--                                              and setHud / setCompact do nothing)
--   overlay:setHud(hud, animate?)              a KneadFormat.Hud
--   overlay:setRing(state, position?)          a KneadMath.ringState at a screen point (InputObject.Position space);
--                                              while the ring shows, the system cursor hides (UserInputService
--                                              .MouseIconEnabled, put back when it hides and on destroy)
--   overlay:setCompact(on)                     phones: the HUD's bar and state only
--   overlay:destroy()
-- The vignette: KneadFormat.vignettePixels on a Config.UI.Knead.vignetteTexels² EditableImage, stretched over the stage
-- (the CSS gradient's ellipse is relative to the box, so a square image stretched is exact), fading in over vignetteMs
-- (Anim/Tweens.fade: capped under ReducedMotion). No EditableImage (budget, engine): no vignette. The ring: a circle with
-- a white inner border and an ink outer ring (the design's soft drop shadow is left out), sized and filled by
-- KneadFormat.ring, its size easing over ringSizeMs (at once under ReducedMotion).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local KneadFormat = require(UI.KneadFormat)
local WaxMeter = require(UI.Components.WaxMeter)
local Tweens = require(Client.Anim.Tweens)

export type StageLike = { front: Frame, root: Frame }

export type Options = {
	hud: boolean?, -- the wax HUD (user 2026-10-12: nil = Config.Wax.enabled)
}

export type Overlay = {
	setHud: (self: Overlay, hud: KneadFormat.Hud, animate: boolean?) -> (),
	setRing: (self: Overlay, state: string, position: Vector2?) -> (),
	setCompact: (self: Overlay, on: boolean) -> (),
	destroy: (self: Overlay) -> (),
}

local KNEAD = Config.UI.Knead
local VIGNETTE_Z = 1
local METER_Z = 3
local RING_Z = 4

local KneadOverlay = {}

-- The vignette's image, or nil when no EditableImage can be made.
local function vignetteImage(): EditableImage?
	local n = KNEAD.vignetteTexels
	local ok, made = pcall(function(): EditableImage?
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(n, n) })
		if image then
			image:WritePixelsBuffer(Vector2.zero, Vector2.new(n, n), KneadFormat.vignettePixels(n))
		end
		return image
	end)
	return if ok then made else nil
end

function KneadOverlay.new(stage: StageLike, options: Options?): Overlay
	local cleanup = Cleanup.new()
	local front = stage.front
	local hudOption = if options then options.hud else nil
	local showHud = if hudOption == nil then Config.Wax.enabled else hudOption

	local image = vignetteImage()
	if image then
		local vignette: ImageLabel = Create("ImageLabel", {
			Name = "KneadVignette",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Stretch,
			ImageContent = Content.fromObject(image),
			ImageTransparency = 1,
			Active = false,
			ZIndex = VIGNETTE_Z,
			Parent = front,
		})
		cleanup:add(vignette)
		cleanup:add(function()
			pcall(function()
				image:Destroy()
			end)
		end)
		cleanup:add(Tweens.fade(vignette, { ImageTransparency = 0 }, KNEAD.vignetteMs))
	end

	-- User 2026-10-12: no wax HUD with the wax off (Config.Wax.enabled).
	local meter = if showHud then WaxMeter.new({ name = "WaxMeter", parent = front, zIndex = METER_Z }) else nil
	if meter then
		cleanup:add(meter)
	end

	local ring: Frame = Create("Frame", {
		Name = "KneadRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(KNEAD.ringPx, KNEAD.ringPx),
		BackgroundColor3 = Palette.White,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Active = false,
		ZIndex = RING_Z,
		Parent = front,
	})
	cleanup:add(ring)
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	local border: UIStroke = Create("UIStroke", {
		Name = "Border",
		Color = Palette.White,
		Thickness = KNEAD.ringStrokePx,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ring,
	})
	pcall(function()
		(border :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local outline: UIStroke = Create("UIStroke", {
		Name = "Outline",
		Color = Palette.KneadInk,
		Thickness = KNEAD.ringOutlinePx,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ring,
	})
	pcall(function()
		(outline :: any).BorderStrokePosition = Enum.BorderStrokePosition.Outer
	end)

	-- The system cursor while the ring shows (restored when it hides or the overlay goes).
	local cursorWas: boolean? = nil
	local function showCursor(show: boolean)
		if not show and cursorWas == nil then
			cursorWas = UserInputService.MouseIconEnabled
			UserInputService.MouseIconEnabled = false
		elseif show and cursorWas ~= nil then
			UserInputService.MouseIconEnabled = cursorWas
			cursorWas = nil
		end
	end
	cleanup:add(function()
		showCursor(true)
	end)

	local ringTween: Tween? = nil
	local ringPx = KNEAD.ringPx
	cleanup:add(function()
		Tweens.cancel(ringTween)
	end)

	local self = {} :: Overlay

	function self.setHud(_: Overlay, hud: KneadFormat.Hud, animate: boolean?)
		if meter then
			meter:set(hud, animate)
		end
	end

	function self.setRing(_: Overlay, state: string, position: Vector2?)
		local spec = KneadFormat.ring(state)
		local size = front.AbsoluteSize
		if not spec.visible or position == nil or size.X <= 0 or size.Y <= 0 then
			ring.Visible = false
			showCursor(true)
			return
		end
		local at = front.AbsolutePosition
		ring.Position = UDim2.fromScale((position.X - at.X) / size.X, (position.Y - at.Y) / size.Y)
		ring.BackgroundTransparency = spec.transparency
		if spec.px ~= ringPx then
			ringPx = spec.px
			Tweens.cancel(ringTween)
			ringTween = nil
			local goal = UDim2.fromOffset(spec.px, spec.px)
			if ring.Visible and not Tweens.reducedMotion() then
				ringTween = Tweens.play(ring, KNEAD.ringSizeMs, { Size = goal })
			else
				ring.Size = goal
			end
		end
		ring.Visible = true
		showCursor(false)
	end

	function self.setCompact(_: Overlay, on: boolean)
		if meter then
			meter:setCompact(on)
		end
	end

	function self.destroy(_: Overlay)
		cleanup:clean()
	end

	return self
end

return KneadOverlay
