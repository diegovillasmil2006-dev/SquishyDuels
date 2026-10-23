--!strict
-- HighwayMood (client only): Claude Design's zone moods (highway v2; Config.UI.Highway.mood). While the own squishy
-- flies through zone n, Lighting, its Atmosphere and its Bloom ease to zone n's mood over tweenSeconds; when the throw
-- ends the lobby's own values (saved at the first enter) ease back. Only in a running client (Edit-mode tests and the
-- server never touch Lighting). A missing Atmosphere or Bloom is skipped.
-- API: HighwayMood.goals(index) -> (lighting, atmosphere, bloom) goal tables (pure); HighwayMood.enter(index);
-- HighwayMood.reset().

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

type Goals = { [string]: any }

local M = Config.UI.Highway.mood
local LIGHT_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ExposureCompensation" }
local ATMO_PROPS = { "Color", "Decay", "Density", "Haze", "Glare" }
local BLOOM_PROPS = { "Intensity", "Threshold" }
local HALF_DAY = 12

local HighwayMood = {}

local saved: { light: Goals, atmo: Goals?, bloom: Goals? }? = nil
local playing: { Tween } = {}

local function token(name: string?): Color3?
	return if name then (Palette :: any)[name] else nil
end

local function snapshot(object: Instance?, props: { string }): Goals?
	if object == nil then
		return nil
	end
	local out = {}
	for _, prop in props do
		out[prop] = (object :: any)[prop]
	end
	return out
end

local function instances(): (Atmosphere?, BloomEffect?)
	return Lighting:FindFirstChildOfClass("Atmosphere"), Lighting:FindFirstChildOfClass("BloomEffect")
end

local function play(object: Instance?, goals: Goals?)
	if object == nil or goals == nil or next(goals) == nil then
		return
	end
	local tween = TweenService:Create(object, TweenInfo.new(M.tweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	table.insert(playing, tween)
	tween:Play()
end

local function stopAll()
	for _, tween in playing do
		tween:Cancel()
	end
	table.clear(playing)
end

-- The clock goes the short way round (17.6 -> 0.5 runs on through the night, not back through the day).
local function clockGoal(goals: Goals)
	local target = goals.ClockTime
	if type(target) ~= "number" then
		return
	end
	local now = Lighting.ClockTime
	if target - now < -HALF_DAY then
		goals.ClockTime = target + 24
	elseif target - now > HALF_DAY then
		goals.ClockTime = target - 24
	end
end

-- Zone `index`'s goals: Lighting, Atmosphere and Bloom (a field the zone leaves out is not in them).
function HighwayMood.goals(index: number): (Goals, Goals, Goals)
	local z = M.zones[index] or {}
	local light, atmo, bloom = {}, {}, {}
	light.ClockTime = z.clockTime
	light.Brightness = z.brightness
	light.Ambient = token(z.ambient)
	light.OutdoorAmbient = token(z.outdoor)
	light.ColorShift_Top = token(z.sun)
	light.ExposureCompensation = z.exposure
	atmo.Color = token(z.atmo)
	atmo.Decay = token(z.decay)
	atmo.Density = z.density
	atmo.Haze = z.haze
	atmo.Glare = z.glare
	bloom.Intensity = z.bloom
	bloom.Threshold = if z.bloom then M.bloomThreshold else nil
	return light, atmo, bloom
end

local function active(): boolean
	return RunService:IsClient() and RunService:IsRunning()
end

-- Eases to zone `index`'s mood (the lobby's values are saved the first time).
function HighwayMood.enter(index: number)
	if not active() then
		return
	end
	local atmosphere, bloomEffect = instances()
	if saved == nil then
		saved = {
			light = snapshot(Lighting, LIGHT_PROPS) :: Goals,
			atmo = snapshot(atmosphere, ATMO_PROPS),
			bloom = snapshot(bloomEffect, BLOOM_PROPS),
		}
	end
	local base = saved :: any
	local light, atmo, bloom = HighwayMood.goals(index)
	-- A field the zone leaves out goes back to the lobby's (the previous zone may have changed it).
	for _, prop in LIGHT_PROPS do
		light[prop] = if light[prop] ~= nil then light[prop] else base.light[prop]
	end
	for _, pair in { { atmo, base.atmo, ATMO_PROPS }, { bloom, base.bloom, BLOOM_PROPS } } do
		if pair[2] then
			for _, prop in pair[3] do
				pair[1][prop] = if pair[1][prop] ~= nil then pair[1][prop] else pair[2][prop]
			end
		end
	end
	clockGoal(light)
	stopAll()
	play(Lighting, light)
	play(atmosphere, atmo)
	play(bloomEffect, bloom)
end

-- Eases back to the lobby's values (nothing when no zone was entered).
function HighwayMood.reset()
	local base = saved
	if base == nil or not active() then
		return
	end
	saved = nil
	local atmosphere, bloomEffect = instances()
	local light = table.clone(base.light)
	clockGoal(light)
	stopAll()
	play(Lighting, light)
	play(atmosphere, base.atmo)
	play(bloomEffect, base.bloom)
end

return HighwayMood
