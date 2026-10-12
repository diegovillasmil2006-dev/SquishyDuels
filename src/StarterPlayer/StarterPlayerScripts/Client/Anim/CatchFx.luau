--!strict
-- CatchFx (client only, pure): the catch's world effects as plain specs (feature 1, 2026-10-11; Config.Vfx.Catch;
-- design: the combat-effects page "Squishy Combat FP v2.html", html:353, 359, 361). VfxController plays them (FxPool
-- emits at one point, its tracked rings facing the camera) for every viewer but a first-person catcher, who sees the
-- overlay's own (ViewmodelController): the catch at the catch point (CatchController.Caught), the burst at the
-- catcher's hands (CatchController.Burst). FxPool halves the counts under ReducedMotion and holds every emit to the
-- particle budgets; each list totals at most Budgets.liveParticlesPerEffect (Config.validate). No instances, no clock.
--
-- API
--   CatchFx.caught(accent) -> ({ Emit }, { Ring })   the catch ring and its sparks (design: html:353)
--   CatchFx.burst(accent) -> ({ Emit }, { Ring })    the accent and White pieces, the sparks, the White puffs and the
--       ring (design: html:359, 361; the sparks' and puffs' speed, size and life against the pieces' are the design
--       burst's shares, Config.FirstPerson.crush, the same burst function)
--   CatchFx.total(emits) -> number                   the particles a list emits

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Art.Palette)

-- Types

export type Emit = { count: number, props: { [string]: any } }
export type Ring = { diameter: number, seconds: number, colour: Color3 }

-- Constants

local CATCH = Config.Vfx.Catch
local SHARES = Config.FirstPerson.crush -- the design burst's spark and puff shares (squishy-lib-v2.js:323, 327)
local TEXTURES = Config.Vfx.Textures
local SPEED_MIN, SPEED_MAX = 0.45, 1.2 -- × the burst's speed (design: fx.js:104, 0.45 + 0.75·random)
local SIZE_SPREAD = 0.4 -- the size ± this share (design: fx.js:105, 0.6 + 0.8·random)
local LIFE_MIN, LIFE_MAX = 0.7, 1.3 -- × the life (design: fx.js:105, 0.7 + 0.6·random)
local SPARK_SPEED_MIN, SPARK_SPEED_MAX = 0.9, 1.8 -- × the burst's speed (design: squishy-lib-v2.js:323)

-- Module table

local CatchFx = {}

-- Private

-- A Size sequence starting at `width` (± SIZE_SPREAD of it per particle) and shrinking to nothing.
local function sized(width: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, width, width * SIZE_SPREAD),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function lifetime(life: number): NumberRange
	return NumberRange.new(life * LIFE_MIN, life * LIFE_MAX)
end

-- Public

function CatchFx.caught(accent: Color3): ({ Emit }, { Ring })
	local emits: { Emit } = {
		{
			count = CATCH.sparks, -- design: html:353
			props = {
				Texture = TEXTURES.sparkles,
				Lifetime = lifetime(CATCH.sparkLifetime),
				Speed = NumberRange.new(CATCH.sparkSpeed * SPARK_SPEED_MIN, CATCH.sparkSpeed * SPARK_SPEED_MAX),
				SpreadAngle = Vector2.new(180, 180),
				Size = sized(CATCH.sparkSizeStuds),
				Color = ColorSequence.new(accent),
				LightEmission = 1,
			},
		},
	}
	local rings: { Ring } = {
		{ diameter = CATCH.ringStuds, seconds = CATCH.ringSeconds, colour = accent }, -- design: html:353
	}
	return emits, rings
end

function CatchFx.burst(accent: Color3): ({ Emit }, { Ring })
	local speed, width, life = CATCH.burstSpeed, 2 * CATCH.burstSize, CATCH.burstLifetime -- design: html:359
	local lifeShare = life / SHARES.burstLife -- the shares are seconds of the design burst's 1.1 s life
	local fall = Vector3.new(0, -CATCH.burstGravity, 0)
	local accentPieces = math.ceil(CATCH.burstPieces / 2) -- design: html:359 (the toy's colours and White)
	local function piece(count: number, colour: Color3): Emit
		return {
			count = count,
			props = {
				Texture = TEXTURES.smoke,
				Lifetime = lifetime(life),
				Speed = NumberRange.new(speed * SPEED_MIN, speed * SPEED_MAX),
				SpreadAngle = Vector2.new(180, 180),
				Size = sized(width),
				Color = ColorSequence.new(colour),
				Acceleration = fall,
				Drag = CATCH.burstDrag,
			},
		}
	end
	local emits: { Emit } = {
		piece(accentPieces, accent),
		piece(CATCH.burstPieces - accentPieces, Palette.White),
		{
			count = CATCH.burstSparks,
			props = {
				Texture = TEXTURES.sparkles,
				Lifetime = lifetime(SHARES.sparkLife * lifeShare),
				Speed = NumberRange.new(speed * SPARK_SPEED_MIN, speed * SPARK_SPEED_MAX),
				SpreadAngle = Vector2.new(180, 180),
				Size = sized(width * SHARES.sparkSizeShare),
				Color = ColorSequence.new(accent),
				LightEmission = 1,
				Drag = CATCH.burstDrag,
			},
		},
		{
			count = CATCH.burstPuffs,
			props = {
				Texture = TEXTURES.smoke,
				Lifetime = lifetime(SHARES.puffLife * lifeShare),
				Speed = NumberRange.new(0, speed * SHARES.puffSpeedShare),
				SpreadAngle = Vector2.new(180, 180),
				Size = sized(width * SHARES.puffSizeShare),
				Color = ColorSequence.new(Palette.White), -- design: html:359 (puffColor '#ffffff')
				Drag = CATCH.burstDrag,
			},
		},
	}
	local rings: { Ring } = {
		{ diameter = CATCH.burstRingStuds, seconds = CATCH.burstRingSeconds, colour = accent }, -- design: html:361
	}
	return emits, rings
end

function CatchFx.total(emits: { Emit }): number
	local n = 0
	for _, emit in emits do
		n += emit.count
	end
	return n
end

return table.freeze(CatchFx)
