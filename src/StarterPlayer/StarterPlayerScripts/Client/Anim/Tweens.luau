--!strict
-- Tweens (client only). Small UI tween helpers on TweenService (DESIGN §9.13, §11.1) that apply the ReducedMotion rules
-- in one place: scale effects are off (the end value is set at once) and fades are capped at
-- Config.UI.motion.reducedMotionMaxFadeMs.
--   Tweens.play(gui, 180, { Position = ... }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
--   Tweens.playSpec(gui, Config.UI.motion.modalClose, { GroupTransparency = 1 })
--   Tweens.fade(dimmer, { BackgroundTransparency = 0.45 }, 180)
--   Tweens.scale(uiScale, 0.94, 1, Config.UI.motion.modalOpen)
--   Scheduler.add(Tweens.countUp(120, 380, 400, function(n) label.Text = Format.coins(n) end), "render")
-- Every Tween is created and played here and returned, so the owner can put it in its Cleanup (Tween is an Instance).
-- UI number count-ups are Scheduler render effects (PreRender, §9.1 #3), not Tween instances.

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UiPrefs = require(script.Parent.Parent.UI.UiPrefs)

-- Types

export type Spec = {
	ms: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
}

export type CountUp = {
	step: (self: CountUp, dt: number, now: number) -> boolean,
	finish: (self: CountUp) -> (),
	cancel: (self: CountUp) -> (),
}

-- Constants

local DEFAULT_STYLE = Enum.EasingStyle.Quad
local DEFAULT_DIRECTION = Enum.EasingDirection.Out
local MAX_FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs

-- Module table

local Tweens = {}

-- Private

local function seconds(ms: number): number
	if not (ms > 0) then
		return 0
	end
	return ms / 1000
end

-- Public

-- True while scale effects must be skipped and fades shortened: Roblox's own GuiService.ReducedMotionEnabled (§9.12),
-- or (UI overhaul 2026-10-11) the in-game Settings "Reduce motion" switch (UI/UiPrefs.reduceMotion).
function Tweens.reducedMotion(): boolean
	return GuiService.ReducedMotionEnabled or UiPrefs.get("reduceMotion")
end

function Tweens.info(ms: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(seconds(ms), style or DEFAULT_STYLE, direction or DEFAULT_DIRECTION)
end

-- Creates, plays and returns a tween of `instance` to `goals` over `ms`.
function Tweens.play(
	instance: Instance,
	ms: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(instance, Tweens.info(ms, style, direction), goals)
	tween:Play()
	return tween
end

-- Same with a { ms, style?, direction? } spec, e.g. an entry of Config.UI.motion.
function Tweens.playSpec(instance: Instance, spec: Spec, goals: { [string]: any }): Tween
	return Tweens.play(instance, spec.ms, goals, spec.style, spec.direction)
end

-- A transparency/colour fade; capped at reducedMotionMaxFadeMs under ReducedMotion.
function Tweens.fade(
	instance: Instance,
	goals: { [string]: any },
	ms: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local duration = if Tweens.reducedMotion() then math.min(ms, MAX_FADE_MS) else ms
	return Tweens.play(instance, duration, goals, style, direction)
end

-- A UIScale pop from `from` to `to`. Under ReducedMotion the scale is set to `to` at once and nil is returned.
function Tweens.scale(uiScale: UIScale, from: number, to: number, spec: Spec): Tween?
	if Tweens.reducedMotion() then
		uiScale.Scale = to
		return nil
	end
	uiScale.Scale = from
	return Tweens.playSpec(uiScale, spec, { Scale = to })
end

-- Cancels a tween if there is one (nil-safe).
function Tweens.cancel(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

-- A number count-up effect for the Scheduler render phase: calls onValue(value) every frame with
-- from → to eased by TweenService:GetValue over `ms`, and exactly `to` on the last frame. Under ReducedMotion it
-- jumps to `to` on its first step. finish() jumps to the end now; cancel() stops without another call.
function Tweens.countUp(
	from: number,
	to: number,
	ms: number,
	onValue: (value: number) -> (),
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): CountUp
	local easing = style or DEFAULT_STYLE
	local easingDirection = direction or DEFAULT_DIRECTION
	local duration = seconds(ms)
	local elapsed = 0
	local done = false
	local effect = {} :: CountUp

	function effect.step(_: CountUp, dt: number, _now: number): boolean
		if done then
			return false
		end
		elapsed += dt
		if duration <= 0 or elapsed >= duration or Tweens.reducedMotion() then
			done = true
			onValue(to)
			return false
		end
		local alpha = TweenService:GetValue(elapsed / duration, easing, easingDirection)
		onValue(from + (to - from) * alpha)
		return true
	end

	function effect.finish(_: CountUp)
		if not done then
			done = true
			onValue(to)
		end
	end

	function effect.cancel(_: CountUp)
		done = true
	end

	return effect
end

return Tweens
