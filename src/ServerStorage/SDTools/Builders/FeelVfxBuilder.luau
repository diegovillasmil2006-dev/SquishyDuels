--!strict
-- FeelVfxBuilder: authors the physics upgrade's particle and trail templates (2026-10-28, part 1: movement) for the VFX
-- Studio plugin, as ReplicatedStorage.SD_MoveVfx.Feel (Client/Anim/FeelFx plays them through Anim/MoveVfx: paths
-- "Feel/<name>"). Server only, Edit mode only; runtime code never requires it. Like MoveVfxBuilder it is not one of
-- Main's targets: VFX Studio is the editor of record. build() returns a new, marked, UNPARENTED Folder "Feel"; the
-- caller swaps it into SD_MoveVfx (the Dash / DoubleJump templates there are left alone). A rebuild drops every tweak
-- made in VFX Studio since.
--
-- Every number is the co-owner's Claude Design page docs/squishy-fx-spec/move.html CONFIG.fx (notes.md "Part 1 · Move"),
-- one template per design name; megaConfetti is the owner's extra 4 (NOT IN DESIGN). Part 2 (2026-10-28, getting hit)
-- adds hit.html CONFIG.fx's particles and knockTrail (Page "hit.html"); the jelly takes the thrown squishy's colour
-- (SD_Tint "team": the design's "Color = the thrown squishy's main colour"), the skid and respawn dust the floor's
-- (extra 2). hit.html's fallWindKO is part 1's fallWind (the same numbers). Part 3 (duelflight.html, Page
-- "duelflight.html") adds only what the game did not have yet (Config.FlightFx's header); part 4 (highway.html) adds the
-- highway throw's particles and Rainbow Road's six flat band trails (Config.HighwayFx); its bounce drops and catch
-- leak take the thrown squishy's colour, its charge sparkles are drawn inward (ShapeInOut). The mapping (notes.md "How each
-- part maps to Roblox"): a template is an invisible anchored Part (its Top = the event's aim); its emitters sit in it,
-- so Cylinder / Sphere / Box shapes use the Part's size (Surface + Outward for Cylinder / Sphere, the design's shape);
-- Tints = one emitter per tint, the count split evenly; Count / Rate = the PC number (phones get the halves at runtime);
-- bursts carry VFX Studio's EmitCount, held emitters SD_Role "while" with their Rate. Our tint attributes: SD_Tint
-- "floor" (the cream dust takes the floor's tint, extra 2), "team" (the held squishy's colour, extra 1).
-- Textures: the kit pictures in AssetTable (img.kit.*).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetTable = require(ReplicatedStorage.Shared.AssetTable)

-- Constants

local GENERATOR_ID = "feel_vfx"
local VERSION = 4 -- 2: part 2's hit templates; 3: part 3's flight templates; 4: part 4's highway templates
local ROOT_NAME = "Feel"
local POINT = 0.05 -- the part size of a template with no shape (a point)
local RIBBON_HALF = 0.5 -- a trail's attachments are width apart: +- width x this

-- Types

type Seq = { { number } } | number
type Spec = { [string]: any }

-- The design's CONFIG.fx particle entries (move.html:73-157), keys as the design names them.
local CREAM = "#FFF4E6"
local SPECS: { [string]: Spec } = {
	runKickPuff = {
		Texture = "puff", Count = 5, Lifetime = { 0.3, 0.42 }, Speed = { 7, 11 }, SpreadAngle = { 25, 25 },
		Size = { { 0, 0.6 }, { 0.35, 1.3 }, { 1, 0.3 } }, Color = CREAM,
		Transparency = { { 0, 0.1 }, { 0.7, 0.4 }, { 1, 1 } }, Acceleration = { 0, 8, 0 }, Drag = 6,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	stepPuff = {
		Texture = "puff", Count = 2, Lifetime = { 0.22, 0.32 }, Speed = { 2, 4 }, SpreadAngle = { 40, 40 },
		Size = { { 0, 0.35 }, { 0.4, 0.8 }, { 1, 0.2 } }, Color = CREAM, Transparency = { { 0, 0.3 }, { 1, 1 } },
		Acceleration = { 0, 4, 0 }, Drag = 5, Rotation = { 0, 360 }, RotSpeed = { -60, 60 }, LightEmission = 0,
		Tint = "floor",
	},
	takeoffPuff = {
		Texture = "puff", Count = 10, Lifetime = { 0.3, 0.45 }, Speed = { 10, 15 }, SpreadAngle = { 8, 8 },
		Shape = "Cylinder", ShapeRadius = 0.7, Size = { { 0, 0.7 }, { 0.35, 1.5 }, { 1, 0.2 } }, Color = CREAM,
		Transparency = { { 0, 0.05 }, { 0.7, 0.35 }, { 1, 1 } }, Acceleration = { 0, 10, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	landPuffSoft = {
		Texture = "puff", Count = 6, Lifetime = { 0.25, 0.35 }, Speed = { 6, 9 }, SpreadAngle = { 8, 8 },
		Shape = "Cylinder", ShapeRadius = 0.6, Size = { { 0, 0.5 }, { 0.35, 1 }, { 1, 0.2 } }, Color = CREAM,
		Transparency = { { 0, 0.15 }, { 0.7, 0.45 }, { 1, 1 } }, Acceleration = { 0, 6, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	landPuffNormal = {
		Texture = "puff", Count = 12, Lifetime = { 0.3, 0.45 }, Speed = { 11, 16 }, SpreadAngle = { 8, 8 },
		Shape = "Cylinder", ShapeRadius = 0.8, Size = { { 0, 0.8 }, { 0.35, 1.7 }, { 1, 0.3 } }, Color = CREAM,
		Transparency = { { 0, 0.05 }, { 0.7, 0.35 }, { 1, 1 } }, Acceleration = { 0, 10, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	landPuffHard = {
		Texture = "puff", Count = 20, Lifetime = { 0.35, 0.55 }, Speed = { 18, 28 }, SpreadAngle = { 10, 10 },
		Shape = "Cylinder", ShapeRadius = 1, Size = { { 0, 1.1 }, { 0.35, 2.4 }, { 1, 0.4 } }, Color = CREAM,
		Transparency = { { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }, Acceleration = { 0, 14, 0 }, Drag = 6,
		Rotation = { 0, 360 }, RotSpeed = { -120, 120 }, LightEmission = 0, Tint = "floor",
	},
	landStarsHard = {
		Texture = "star", Count = 6, Lifetime = { 0.35, 0.5 }, Speed = { 12, 20 }, SpreadAngle = { 45, 45 },
		Size = { { 0, 0.8 }, { 0.7, 0.7 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0,
		Acceleration = { 0, -70, 0 }, Drag = 1, Rotation = { 0, 360 }, RotSpeed = { -300, 300 }, LightEmission = 0.2,
		Tint = "team",
	},
	doubleStars = {
		Texture = "star", Count = 12, Lifetime = { 0.35, 0.55 }, Speed = { 16, 26 }, SpreadAngle = { 60, 60 },
		Size = { { 0, 1 }, { 0.6, 0.8 }, { 1, 0 } }, Color = { { 0, "#FFFFFF" }, { 0.25, "#FFD86B" }, { 1, "#FFD86B" } },
		Transparency = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } }, Acceleration = { 0, -50, 0 }, Drag = 3,
		Rotation = { 0, 360 }, RotSpeed = { -270, 270 }, LightEmission = 0.2, Tint = "team",
	},
	doublePuff = {
		Texture = "puff", Count = 8, Lifetime = { 0.3, 0.45 }, Speed = { 10, 16 }, SpreadAngle = { 35, 35 },
		Size = { { 0, 0.9 }, { 0.3, 1.8 }, { 1, 0.3 } }, Color = CREAM,
		Transparency = { { 0, 0.05 }, { 0.7, 0.4 }, { 1, 1 } }, Acceleration = { 0, 12, 0 }, Drag = 6,
		Rotation = { 0, 360 }, RotSpeed = { -120, 120 }, LightEmission = 0,
	},
	doubleSparkles = {
		Texture = "sparkle", Count = 10, Lifetime = { 0.25, 0.4 }, Speed = { 4, 9 }, SpreadAngle = { 180, 180 },
		Shape = "Sphere", ShapeRadius = 1.4, Size = { { 0, 0 }, { 0.25, 1.1 }, { 1, 0 } }, Color = "#FFFFFF",
		Transparency = 0, Drag = 2, Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7, Tint = "team",
	},
	flipStreak = {
		Texture = "sparkle", Rate = 50, Lifetime = { 0.2, 0.3 }, Speed = { 2, 4 }, SpreadAngle = { 180, 180 },
		Shape = "Sphere", ShapeRadius = 1.6, Size = { { 0, 0.6 }, { 1, 0 } }, Color = "#FFFFFF", Transparency = 0,
		Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7, Tint = "team",
	},
	fallWind = {
		Texture = "speedline", Rate = 30, Lifetime = { 0.12, 0.2 }, Speed = { 40, 60 }, SpreadAngle = { 4, 4 },
		Shape = "Box", ShapeSize = { 5, 6, 5 }, Size = { { 0, 0.5 }, { 1, 0.4 } }, Squash = 1.6, Color = "#FFFFFF",
		Transparency = { { 0, 0.4 }, { 1, 1 } }, Orientation = "VelocityParallel", LightEmission = 0.3,
	},
	dashPuffStart = {
		Texture = "puff", Count = 6, Lifetime = { 0.25, 0.4 }, Speed = { 8, 12 }, SpreadAngle = { 30, 30 },
		Size = { { 0, 0.7 }, { 0.35, 1.4 }, { 1, 0.2 } }, Color = CREAM,
		Transparency = { { 0, 0.1 }, { 0.7, 0.4 }, { 1, 1 } }, Acceleration = { 0, 6, 0 }, Drag = 6,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	dashPuffEnd = {
		Texture = "puff", Count = 5, Lifetime = { 0.25, 0.35 }, Speed = { 6, 10 }, SpreadAngle = { 8, 8 },
		Shape = "Cylinder", ShapeRadius = 0.6, Size = { { 0, 0.5 }, { 0.35, 1.1 }, { 1, 0.2 } }, Color = CREAM,
		Transparency = { { 0, 0.15 }, { 0.7, 0.45 }, { 1, 1 } }, Acceleration = { 0, 6, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	dashSparks = {
		Texture = "speedline", Rate = 60, Lifetime = { 0.1, 0.16 }, Speed = { 30, 45 }, SpreadAngle = { 6, 6 },
		Shape = "Box", ShapeSize = { 3, 5, 1 }, Size = { { 0, 0.5 }, { 1, 0.4 } }, Squash = 1.4, Color = "#FFFFFF",
		Transparency = { { 0, 0.3 }, { 1, 1 } }, Orientation = "VelocityParallel", LightEmission = 0.5,
		LockedToPart = true,
	},
	slideStartPuff = {
		Texture = "puff", Count = 10, Lifetime = { 0.3, 0.45 }, Speed = { 10, 15 }, SpreadAngle = { 8, 8 },
		Shape = "Cylinder", ShapeRadius = 0.8, Size = { { 0, 0.8 }, { 0.35, 1.6 }, { 1, 0.3 } }, Color = CREAM,
		Transparency = { { 0, 0.05 }, { 0.7, 0.35 }, { 1, 1 } }, Acceleration = { 0, 10, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	slideDust = {
		Texture = "puff", Rate = 40, Lifetime = { 0.3, 0.45 }, Speed = { 3, 7 }, SpreadAngle = { 30, 30 },
		Size = { { 0, 0.6 }, { 0.35, 1.4 }, { 1, 0.3 } }, Color = CREAM,
		Transparency = { { 0, 0.15 }, { 0.7, 0.45 }, { 1, 1 } }, Acceleration = { 0, 6, 0 }, Drag = 4,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	slideSprinkles = {
		Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Rate = 24,
		Lifetime = { 0.35, 0.6 }, Speed = { 10, 16 }, SpreadAngle = { 30, 30 }, Size = 0.32,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -110, 0 }, Drag = 1,
		Rotation = { 0, 360 }, RotSpeed = { -420, 420 }, LightEmission = 0,
	},
	-- Extra 4 (NOT IN DESIGN): the mega landing's confetti pop, the slide sprinkles' look, upward.
	megaConfetti = {
		Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Count = 24,
		Lifetime = { 0.55, 0.85 }, Speed = { 20, 32 }, SpreadAngle = { 35, 35 }, Size = 0.4,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -90, 0 }, Drag = 1.5,
		Rotation = { 0, 360 }, RotSpeed = { -420, 420 }, LightEmission = 0,
	},
	-- Part 2: hit.html CONFIG.fx (104-155).
	jellySplat = {
		Page = "hit.html", Texture = "jelly", Count = 16, Lifetime = { 0.4, 0.7 }, Speed = { 20, 36 },
		SpreadAngle = { 70, 70 }, Size = { { 0, 0.7 }, { 0.25, 0.95 }, { 1, 0.3 } }, Color = "#FF8FB1",
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -110, 0 }, Drag = 1.5,
		Orientation = "VelocityParallel", Squash = 0.3, LightEmission = 0, Tint = "team",
	},
	jellySplatBig = {
		Page = "hit.html", Texture = "jelly", Count = 26, Lifetime = { 0.45, 0.8 }, Speed = { 26, 46 },
		SpreadAngle = { 80, 80 }, Size = { { 0, 0.8 }, { 0.25, 1.1 }, { 1, 0.35 } }, Color = "#FF8FB1",
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -110, 0 }, Drag = 1.5,
		Orientation = "VelocityParallel", Squash = 0.3, LightEmission = 0, Tint = "team",
	},
	hitStars = {
		Page = "hit.html", Texture = "star", Count = 8, Lifetime = { 0.35, 0.55 }, Speed = { 14, 24 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 0.9 }, { 0.7, 0.8 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0,
		Acceleration = { 0, -40, 0 }, Drag = 2, Rotation = { 0, 360 }, RotSpeed = { -300, 300 }, LightEmission = 0.2,
	},
	hitStarsBig = {
		Page = "hit.html", Texture = "star", Count = 14, Lifetime = { 0.4, 0.65 }, Speed = { 18, 32 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 1.1 }, { 0.7, 1 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0,
		Acceleration = { 0, -40, 0 }, Drag = 2, Rotation = { 0, 360 }, RotSpeed = { -300, 300 }, LightEmission = 0.2,
	},
	hitSprinkles = {
		Page = "hit.html", Texture = "confetti", Tints = { "#8EDFC4", "#FFD86B", "#8CC8FF" }, Count = 18,
		Lifetime = { 0.45, 0.75 }, Speed = { 18, 30 }, SpreadAngle = { 80, 80 }, Size = 0.35,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -120, 0 }, Drag = 1,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0,
	},
	hitSprinklesBig = {
		Page = "hit.html", Texture = "confetti", Tints = { "#8EDFC4", "#FFD86B", "#8CC8FF" }, Count = 30,
		Lifetime = { 0.5, 0.85 }, Speed = { 22, 38 }, SpreadAngle = { 90, 90 }, Size = 0.4,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -120, 0 }, Drag = 1,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0,
	},
	skidPuff = {
		Page = "hit.html", Texture = "puff", Count = 8, Lifetime = { 0.3, 0.45 }, Speed = { 8, 13 },
		SpreadAngle = { 8, 8 }, Shape = "Cylinder", ShapeRadius = 0.7, Size = { { 0, 0.7 }, { 0.35, 1.5 }, { 1, 0.3 } },
		Color = CREAM, Transparency = { { 0, 0.1 }, { 0.7, 0.4 }, { 1, 1 } }, Acceleration = { 0, 8, 0 }, Drag = 6,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	poofCloud = {
		Page = "hit.html", Texture = "puff", Count = 14, Lifetime = { 0.45, 0.7 }, Speed = { 6, 12 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 1.6, Size = { { 0, 2 }, { 0.3, 4.2 }, { 1, 1 } },
		Color = { { 0, "#FFFFFF" }, { 1, "#FFC7DA" } }, Transparency = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } },
		Acceleration = { 0, 6, 0 }, Drag = 4, Rotation = { 0, 360 }, RotSpeed = { -60, 60 }, LightEmission = 0,
	},
	poofConfetti = {
		Page = "hit.html", Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Count = 32,
		Lifetime = { 0.6, 1 }, Speed = { 20, 34 }, SpreadAngle = { 180, 180 }, Size = 0.4,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -90, 0 }, Drag = 1.5,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0,
	},
	poofSparkles = {
		Page = "hit.html", Texture = "sparkle", Count = 12, Lifetime = { 0.4, 0.7 }, Speed = { 2, 6 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 2.2, Size = { { 0, 0 }, { 0.3, 1.3 }, { 1, 0 } },
		Color = "#FFFFFF", Transparency = 0, Drag = 2, Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7,
	},
	respawnPuff = {
		Page = "hit.html", Texture = "puff", Count = 10, Lifetime = { 0.3, 0.45 }, Speed = { 8, 12 },
		SpreadAngle = { 8, 8 }, Shape = "Cylinder", ShapeRadius = 1, Size = { { 0, 0.8 }, { 0.35, 1.8 }, { 1, 0.3 } },
		Color = CREAM, Transparency = { { 0, 0.05 }, { 0.7, 0.35 }, { 1, 1 } }, Acceleration = { 0, 10, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	respawnSparkles = {
		Page = "hit.html", Texture = "sparkle", Count = 10, Lifetime = { 0.35, 0.6 }, Speed = { 6, 10 },
		SpreadAngle = { 10, 10 }, Shape = "Cylinder", ShapeRadius = 1.5, Size = { { 0, 0 }, { 0.3, 1 }, { 1, 0 } },
		Color = "#FFFFFF", Transparency = 0, Acceleration = { 0, 14, 0 }, Drag = 2, Rotation = { 0, 45 },
		RotSpeed = { -90, 90 }, LightEmission = 0.7,
	},
	fallPoof = {
		Page = "hit.html", Texture = "puff", Count = 12, Lifetime = { 0.4, 0.6 }, Speed = { 8, 14 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 1.4, Size = { { 0, 1.6 }, { 0.3, 3.4 }, { 1, 0.8 } },
		Color = { { 0, "#FFFFFF" }, { 1, "#B9A6E8" } }, Transparency = { { 0, 0 }, { 0.6, 0.25 }, { 1, 1 } },
		Acceleration = { 0, 10, 0 }, Drag = 4, Rotation = { 0, 360 }, RotSpeed = { -60, 60 }, LightEmission = 0,
	},
	finalConfetti = {
		Page = "hit.html", Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Count = 40,
		Lifetime = { 0.7, 1.2 }, Speed = { 24, 40 }, SpreadAngle = { 180, 180 }, Size = 0.45,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -80, 0 }, Drag = 1.5,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0,
	},
	dizzyStars = {
		Page = "hit.html", Texture = "star", Rate = 24, Lifetime = { 0.3, 0.45 }, Speed = { 4, 7 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 1.4, Size = { { 0, 0 }, { 0.3, 0.8 }, { 1, 0 } },
		Color = "#FFD86B", Transparency = 0, Drag = 2, Rotation = { 0, 360 }, RotSpeed = { -300, 300 },
		LightEmission = 0.3, LockedToPart = true,
	},
	-- Part 3: duelflight.html CONFIG.fx (78-134), the pieces the game did not have yet (Config.FlightFx's header).
	releasePuff = {
		Page = "duelflight.html", Texture = "puff", Count = 4, Lifetime = { 0.18, 0.28 }, Speed = { 6, 10 },
		SpreadAngle = { 35, 35 }, Size = { { 0, 0.5 }, { 0.4, 1 }, { 1, 0.2 } }, Color = CREAM,
		Transparency = { { 0, 0.2 }, { 1, 1 } }, Drag = 6, Rotation = { 0, 360 }, RotSpeed = { -90, 90 },
		LightEmission = 0,
	},
	chargedSparkTrail = {
		Page = "duelflight.html", Texture = "sparkle", Rate = 40, Lifetime = { 0.2, 0.35 }, Speed = { 1, 3 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 0.6 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0, Drag = 2,
		Rotation = { 0, 45 }, RotSpeed = { -180, 180 }, LightEmission = 0.7,
	},
	chargedAura = {
		Page = "duelflight.html", Texture = "sparkle", Rate = 40, Lifetime = { 0.2, 0.3 }, Speed = { 2, 5 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 1.5, Size = { { 0, 0.7 }, { 1, 0 } },
		Color = "#FFD86B", Transparency = 0, Rotation = { 0, 45 }, RotSpeed = { -180, 180 }, LightEmission = 0.8,
		LockedToPart = true,
	},
	chargeSparksA = {
		Page = "duelflight.html", Texture = "sparkle", Rate = 12, Lifetime = { 0.25, 0.4 }, Speed = { 4, 7 },
		SpreadAngle = { 0, 0 }, Shape = "Sphere", ShapeInOut = "Inward", ShapeRadius = 1.6,
		Size = { { 0, 0 }, { 0.4, 0.6 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0, Drag = 0,
		Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7,
	},
	chargeSparksB = {
		Page = "duelflight.html", Texture = "sparkle", Rate = 30, Lifetime = { 0.2, 0.35 }, Speed = { 5, 8 },
		SpreadAngle = { 0, 0 }, Shape = "Sphere", ShapeInOut = "Inward", ShapeRadius = 1.6,
		Size = { { 0, 0 }, { 0.4, 0.7 }, { 1, 0 } }, Color = "#FFFFFF", Transparency = 0, Drag = 0,
		Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7,
	},
	chargeReadyPop = {
		Page = "duelflight.html", Texture = "sparkle", Count = 10, Lifetime = { 0.2, 0.35 }, Speed = { 6, 10 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 0.8 }, { 1, 0 } }, Color = "#FFFFFF", Transparency = 0, Drag = 3,
		Rotation = { 0, 45 }, RotSpeed = { -180, 180 }, LightEmission = 0.7,
	},
	bounceDrops = {
		Page = "duelflight.html", Texture = "jelly", Count = 6, Lifetime = { 0.25, 0.4 }, Speed = { 10, 16 },
		SpreadAngle = { 50, 50 }, Size = { { 0, 0.45 }, { 1, 0.15 } }, Color = "#FF8FB1",
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -120, 0 }, Drag = 1,
		Orientation = "VelocityParallel", Squash = 0.3, LightEmission = 0, Tint = "team",
	},
	catchLeak = {
		Page = "duelflight.html", Texture = "jelly", Rate = 14, Lifetime = { 0.25, 0.4 }, Speed = { 4, 8 },
		SpreadAngle = { 55, 55 }, Size = { { 0, 0.3 }, { 1, 0.1 } }, Color = "#FF8FB1",
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -60, 0 }, Drag = 1,
		Orientation = "VelocityParallel", Squash = 0.3, LightEmission = 0, Tint = "team",
	},
	-- Part 4: highway.html CONFIG.fx (85-179). zoneSparkles take the zone's colour, landDrops the squishy's (SD_Tint
	-- "team": HighwayFxController sets which), the launch, landing and roll dust the floor's (extra 2).
	windupSparks = {
		Page = "highway.html", Texture = "sparkle", Rate = 60, Lifetime = { 0.22, 0.32 }, Speed = { 9, 12 },
		SpreadAngle = { 0, 0 }, Shape = "Sphere", ShapeInOut = "Inward", ShapeRadius = 3,
		Size = { { 0, 0 }, { 0.4, 0.7 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0, Rotation = { 0, 45 },
		RotSpeed = { -90, 90 }, LightEmission = 0.7, LockedToPart = true,
	},
	launchStars = {
		Page = "highway.html", Texture = "star", Count = 16, Lifetime = { 0.4, 0.7 }, Speed = { 20, 34 },
		SpreadAngle = { 50, 50 }, Size = { { 0, 1 }, { 0.7, 0.9 }, { 1, 0 } },
		Color = { { 0, "#FFFFFF" }, { 0.2, "#FFD86B" }, { 1, "#FFD86B" } }, Transparency = 0, Acceleration = { 0, -40, 0 },
		Drag = 2, Rotation = { 0, 360 }, RotSpeed = { -300, 300 }, LightEmission = 0.2,
	},
	launchPuff = {
		Page = "highway.html", Texture = "puff", Count = 8, Lifetime = { 0.25, 0.4 }, Speed = { 8, 12 },
		SpreadAngle = { 40, 40 }, Size = { { 0, 0.7 }, { 0.35, 1.6 }, { 1, 0.3 } }, Color = CREAM,
		Transparency = { { 0, 0.1 }, { 0.7, 0.4 }, { 1, 1 } }, Drag = 6, Rotation = { 0, 360 }, RotSpeed = { -90, 90 },
		LightEmission = 0,
	},
	launchSparkles = {
		Page = "highway.html", Texture = "sparkle", Count = 12, Lifetime = { 0.3, 0.5 }, Speed = { 3, 7 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 1.5, Size = { { 0, 0 }, { 0.3, 1.1 }, { 1, 0 } },
		Color = "#FFFFFF", Transparency = 0, Drag = 2, Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7,
	},
	launchDust = {
		Page = "highway.html", Texture = "puff", Count = 18, Lifetime = { 0.35, 0.55 }, Speed = { 18, 28 },
		SpreadAngle = { 10, 10 }, Shape = "Cylinder", ShapeRadius = 1.5, Size = { { 0, 1 }, { 0.35, 2.4 }, { 1, 0.4 } },
		Color = CREAM, Transparency = { { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }, Acceleration = { 0, 12, 0 }, Drag = 5,
		Rotation = { 0, 360 }, RotSpeed = { -120, 120 }, LightEmission = 0, Tint = "floor",
	},
	apexTwinkle = {
		Page = "highway.html", Texture = "sparkle", Count = 16, Lifetime = { 0.3, 0.5 }, Speed = { 8, 14 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 0 }, { 0.3, 1 }, { 1, 0 } }, Color = "#FFFFFF", Transparency = 0,
		Drag = 3, Rotation = { 0, 45 }, RotSpeed = { -120, 120 }, LightEmission = 0.7, LockedToPart = true,
	},
	zoneSparkles = {
		Page = "highway.html", Texture = "sparkle", Count = 16, Lifetime = { 0.3, 0.5 }, Speed = { 10, 20 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 3, Size = { { 0, 0 }, { 0.3, 1.4 }, { 1, 0 } },
		Color = "#FFFFFF", Transparency = 0, Drag = 2, Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7,
		LockedToPart = true, Tint = "team",
	},
	meadowConfetti = {
		Page = "highway.html", Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Rate = 40,
		Lifetime = { 0.35, 0.55 }, Speed = { 16, 26 }, SpreadAngle = { 35, 35 }, Size = 0.4,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -20, 0 }, Drag = 2,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0, LockedToPart = true,
	},
	sprinkleBurst = {
		Page = "highway.html", Texture = "confetti", Tints = { "#FF8FB1", "#8CC8FF", "#FFF4E6", "#8EDFC4" }, Count = 40,
		Lifetime = { 0.45, 0.7 }, Speed = { 24, 36 }, SpreadAngle = { 180, 180 }, Size = 0.4,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Drag = 2.5, Rotation = { 0, 360 }, RotSpeed = { -540, 540 },
		LightEmission = 0, LockedToPart = true,
	},
	bakerySprinkles = {
		Page = "highway.html", Texture = "confetti", Tints = { "#FF8FB1", "#8CC8FF", "#FFF4E6", "#8EDFC4" }, Rate = 40,
		Lifetime = { 0.35, 0.55 }, Speed = { 16, 26 }, SpreadAngle = { 35, 35 }, Size = 0.32,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -20, 0 }, Drag = 2,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0, LockedToPart = true,
	},
	splashBurst = {
		Page = "highway.html", Texture = "jelly", Count = 28, Lifetime = { 0.35, 0.55 }, Speed = { 20, 32 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 0.7 }, { 1, 0.2 } }, Color = "#8CC8FF",
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -60, 0 }, Drag = 2,
		Orientation = "VelocityParallel", Squash = 0.3, LightEmission = 0, LockedToPart = true,
	},
	lagoonBubbles = {
		Page = "highway.html", Texture = "ring", Rate = 30, Lifetime = { 0.4, 0.7 }, Speed = { 6, 12 },
		SpreadAngle = { 50, 50 }, Shape = "Sphere", ShapeRadius = 1.4, Size = { { 0, 0.2 }, { 0.5, 0.7 }, { 1, 0.9 } },
		Color = "#FFFFFF", Transparency = { { 0, 0.1 }, { 0.85, 0.3 }, { 1, 1 } }, Acceleration = { 0, 18, 0 }, Drag = 2,
		LightEmission = 0.3, LockedToPart = true,
	},
	frostBurst = {
		Page = "highway.html", Texture = "sparkle", Count = 30, Lifetime = { 0.35, 0.55 }, Speed = { 22, 34 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 0 }, { 0.25, 1.2 }, { 1, 0 } },
		Color = { { 0, "#FFFFFF" }, { 1, "#CFE0FF" } }, Transparency = 0, Drag = 3, Rotation = { 0, 45 },
		RotSpeed = { -180, 180 }, LightEmission = 0.7, LockedToPart = true,
	},
	snowSparkles = {
		Page = "highway.html", Texture = "sparkle", Rate = 40, Lifetime = { 0.35, 0.6 }, Speed = { 10, 18 },
		SpreadAngle = { 45, 45 }, Shape = "Sphere", ShapeRadius = 1.2, Size = { { 0, 0 }, { 0.3, 0.75 }, { 1, 0 } },
		Color = { { 0, "#FFFFFF" }, { 1, "#CFE0FF" } }, Transparency = 0, Acceleration = { 0, -12, 0 }, Drag = 2,
		Rotation = { 0, 45 }, RotSpeed = { -120, 120 }, LightEmission = 0.7, LockedToPart = true,
	},
	lavaBurst = {
		Page = "highway.html", Texture = "star", Count = 28, Lifetime = { 0.35, 0.6 }, Speed = { 22, 36 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 1 }, { 1, 0 } },
		Color = { { 0, "#FFE36B" }, { 0.5, "#FF9A5C" }, { 1, "#F2687F" } }, Transparency = 0, Acceleration = { 0, 30, 0 },
		Drag = 3, Rotation = { 0, 360 }, RotSpeed = { -300, 300 }, LightEmission = 0.4, LockedToPart = true,
	},
	lavaEmbers = {
		Page = "highway.html", Texture = "sparkle", Rate = 50, Lifetime = { 0.35, 0.6 }, Speed = { 12, 22 },
		SpreadAngle = { 40, 40 }, Shape = "Sphere", ShapeRadius = 1.2, Size = { { 0, 0.7 }, { 1, 0 } },
		Color = { { 0, "#FFE36B" }, { 0.5, "#FF9A5C" }, { 1, "#F2687F" } }, Transparency = 0, Acceleration = { 0, 26, 0 },
		Drag = 2, Rotation = { 0, 45 }, RotSpeed = { -180, 180 }, LightEmission = 0.8, LockedToPart = true,
	},
	rainbowBurst = {
		Page = "highway.html", Texture = "confetti",
		Tints = { "#FF6B8B", "#FFB36B", "#FFE36B", "#8EDFC4", "#8CC8FF", "#B892F0" }, Count = 48,
		Lifetime = { 0.45, 0.7 }, Speed = { 24, 36 }, SpreadAngle = { 180, 180 }, Size = 0.42,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Drag = 2.5, Rotation = { 0, 360 }, RotSpeed = { -540, 540 },
		LightEmission = 0, LockedToPart = true,
	},
	heavenBurst = {
		Page = "highway.html", Texture = "star", Count = 30, Lifetime = { 0.4, 0.65 }, Speed = { 20, 32 },
		SpreadAngle = { 180, 180 }, Size = { { 0, 1 }, { 0.7, 0.8 }, { 1, 0 } },
		Color = { { 0, "#FFFFFF" }, { 0.3, "#FFE7A3" }, { 1, "#FFD86B" } }, Transparency = 0, Drag = 3,
		Rotation = { 0, 360 }, RotSpeed = { -240, 240 }, LightEmission = 0.5, LockedToPart = true,
	},
	heavenSparkles = {
		Page = "highway.html", Texture = "star", Rate = 36, Lifetime = { 0.4, 0.65 }, Speed = { 8, 14 },
		SpreadAngle = { 60, 60 }, Shape = "Sphere", ShapeRadius = 1.6, Size = { { 0, 0 }, { 0.3, 0.8 }, { 1, 0 } },
		Color = { { 0, "#FFFFFF" }, { 0.4, "#FFE7A3" }, { 1, "#FFD86B" } }, Transparency = 0, Drag = 2,
		Rotation = { 0, 360 }, RotSpeed = { -200, 200 }, LightEmission = 0.6, LockedToPart = true,
	},
	landPuffBig = {
		Page = "highway.html", Texture = "puff", Count = 20, Lifetime = { 0.35, 0.55 }, Speed = { 20, 32 },
		SpreadAngle = { 10, 10 }, Shape = "Cylinder", ShapeRadius = 1.5, Size = { { 0, 1.2 }, { 0.35, 2.8 }, { 1, 0.5 } },
		Color = CREAM, Transparency = { { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }, Acceleration = { 0, 14, 0 }, Drag = 6,
		Rotation = { 0, 360 }, RotSpeed = { -120, 120 }, LightEmission = 0, Tint = "floor",
	},
	landDrops = {
		Page = "highway.html", Texture = "jelly", Count = 10, Lifetime = { 0.35, 0.55 }, Speed = { 14, 24 },
		SpreadAngle = { 50, 50 }, Size = { { 0, 0.6 }, { 1, 0.2 } }, Color = "#FF8FB1",
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -120, 0 }, Drag = 1,
		Orientation = "VelocityParallel", Squash = 0.3, LightEmission = 0, Tint = "team",
	},
	impactStars = {
		Page = "highway.html", Texture = "star", Count = 14, Lifetime = { 0.4, 0.6 }, Speed = { 18, 30 },
		SpreadAngle = { 55, 55 }, Size = { { 0, 1 }, { 0.7, 0.8 }, { 1, 0 } }, Color = "#FFD86B", Transparency = 0,
		Acceleration = { 0, -70, 0 }, Drag = 1, Rotation = { 0, 360 }, RotSpeed = { -300, 300 }, LightEmission = 0.2,
	},
	bouncePuff = {
		Page = "highway.html", Texture = "puff", Count = 8, Lifetime = { 0.25, 0.4 }, Speed = { 8, 12 },
		SpreadAngle = { 8, 8 }, Shape = "Cylinder", ShapeRadius = 0.9, Size = { { 0, 0.6 }, { 0.35, 1.4 }, { 1, 0.2 } },
		Color = CREAM, Transparency = { { 0, 0.1 }, { 0.7, 0.4 }, { 1, 1 } }, Acceleration = { 0, 8, 0 }, Drag = 7,
		Rotation = { 0, 360 }, RotSpeed = { -90, 90 }, LightEmission = 0, Tint = "floor",
	},
	rollDust = {
		Page = "highway.html", Texture = "puff", Rate = 16, Lifetime = { 0.2, 0.35 }, Speed = { 1, 3 },
		SpreadAngle = { 40, 40 }, Size = { { 0, 0.35 }, { 0.4, 0.8 }, { 1, 0.1 } }, Color = CREAM,
		Transparency = { { 0, 0.3 }, { 1, 1 } }, Acceleration = { 0, 4, 0 }, Drag = 4, Rotation = { 0, 360 },
		RotSpeed = { -60, 60 }, LightEmission = 0, Tint = "floor",
	},
	stopConfetti = {
		Page = "highway.html", Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Count = 40,
		Lifetime = { 0.8, 1.2 }, Speed = { 22, 36 }, SpreadAngle = { 35, 35 }, Size = 0.45,
		Transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } }, Acceleration = { 0, -70, 0 }, Drag = 1.2,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0,
	},
	stopSparkles = {
		Page = "highway.html", Texture = "sparkle", Count = 14, Lifetime = { 0.4, 0.7 }, Speed = { 3, 7 },
		SpreadAngle = { 180, 180 }, Shape = "Sphere", ShapeRadius = 2, Size = { { 0, 0 }, { 0.3, 1.3 }, { 1, 0 } },
		Color = "#FFFFFF", Transparency = 0, Drag = 2, Rotation = { 0, 45 }, RotSpeed = { -90, 90 }, LightEmission = 0.7,
	},
	confettiRain = {
		Page = "highway.html", Texture = "confetti", Tints = { "#FF8FB1", "#8EDFC4", "#FFD86B", "#8CC8FF" }, Rate = 50,
		Lifetime = { 0.9, 1 }, Speed = { 2, 6 }, SpreadAngle = { 20, 20 }, Shape = "Box", ShapeSize = { 24, 1, 24 },
		Size = 0.45, Transparency = { { 0, 0 }, { 0.85, 0 }, { 1, 1 } }, Acceleration = { 0, -36, 0 }, Drag = 0.5,
		Rotation = { 0, 360 }, RotSpeed = { -540, 540 }, LightEmission = 0,
	},
	fireworkA = {
		Page = "highway.html", Texture = "star", Tints = { "#FF8FB1", "#FFD86B" }, Count = 36, Lifetime = { 0.6, 0.9 },
		Speed = { 12, 18 }, SpreadAngle = { 180, 180 }, Size = { { 0, 0.9 }, { 0.7, 0.7 }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } }, Acceleration = { 0, -14, 0 }, Drag = 3,
		Rotation = { 0, 360 }, RotSpeed = { -240, 240 }, LightEmission = 0.4,
	},
	fireworkB = {
		Page = "highway.html", Texture = "star", Tints = { "#8EDFC4", "#8CC8FF" }, Count = 36, Lifetime = { 0.6, 0.9 },
		Speed = { 12, 18 }, SpreadAngle = { 180, 180 }, Size = { { 0, 0.9 }, { 0.7, 0.7 }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } }, Acceleration = { 0, -14, 0 }, Drag = 3,
		Rotation = { 0, 360 }, RotSpeed = { -240, 240 }, LightEmission = 0.4,
	},
	fireworkC = {
		Page = "highway.html", Texture = "star", Tints = { "#B9A6E8", "#FFFFFF" }, Count = 36, Lifetime = { 0.6, 0.9 },
		Speed = { 12, 18 }, SpreadAngle = { 180, 180 }, Size = { { 0, 0.9 }, { 0.7, 0.7 }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } }, Acceleration = { 0, -14, 0 }, Drag = 3,
		Rotation = { 0, 360 }, RotSpeed = { -240, 240 }, LightEmission = 0.4,
	},
}

-- The design's trails (CONFIG.fx dashRibbon, slideStreak). flat = the attachments lie along X (on the floor).
local TRAILS: { [string]: Spec } = {
	dashRibbon = {
		Color = { { 0, "#8CC8FF" }, { 1, "#B9A6E8" } }, Width = 0.9, Lifetime = 0.28,
		Transparency = { { 0, 0.2 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.15 } }, LightEmission = 0.35,
		FaceCamera = true, MinLength = 0.2,
	},
	slideStreak = {
		Color = { { 0, CREAM }, { 1, CREAM } }, Width = 1, Lifetime = 0.35, Transparency = { { 0, 0.35 }, { 1, 1 } },
		WidthScale = { { 0, 1 }, { 1, 0.5 } }, LightEmission = 0, FaceCamera = false, MinLength = 0.2, Flat = true,
	},
	-- Part 4: highway.html CONFIG.fx band* (138-143): Rainbow Road's painted road, six flat ribbons side by side.
	bandRed = { Page = "highway.html", Color = { { 0, "#FF6B8B" }, { 1, "#FF6B8B" } }, Width = 0.6, Lifetime = 0.45, Transparency = { { 0, 0.1 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.6 } }, LightEmission = 0.3, FaceCamera = false, MinLength = 1, Flat = true },
	bandOrange = { Page = "highway.html", Color = { { 0, "#FFB36B" }, { 1, "#FFB36B" } }, Width = 0.6, Lifetime = 0.45, Transparency = { { 0, 0.1 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.6 } }, LightEmission = 0.3, FaceCamera = false, MinLength = 1, Flat = true },
	bandYellow = { Page = "highway.html", Color = { { 0, "#FFE36B" }, { 1, "#FFE36B" } }, Width = 0.6, Lifetime = 0.45, Transparency = { { 0, 0.1 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.6 } }, LightEmission = 0.3, FaceCamera = false, MinLength = 1, Flat = true },
	bandMint = { Page = "highway.html", Color = { { 0, "#8EDFC4" }, { 1, "#8EDFC4" } }, Width = 0.6, Lifetime = 0.45, Transparency = { { 0, 0.1 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.6 } }, LightEmission = 0.3, FaceCamera = false, MinLength = 1, Flat = true },
	bandSky = { Page = "highway.html", Color = { { 0, "#8CC8FF" }, { 1, "#8CC8FF" } }, Width = 0.6, Lifetime = 0.45, Transparency = { { 0, 0.1 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.6 } }, LightEmission = 0.3, FaceCamera = false, MinLength = 1, Flat = true },
	bandViolet = { Page = "highway.html", Color = { { 0, "#B892F0" }, { 1, "#B892F0" } }, Width = 0.6, Lifetime = 0.45, Transparency = { { 0, 0.1 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0.6 } }, LightEmission = 0.3, FaceCamera = false, MinLength = 1, Flat = true },
	-- Part 2: hit.html CONFIG.fx.knockTrail (it draws the launch arc).
	knockTrail = {
		Page = "hit.html", Color = { { 0, "#FFFFFF" }, { 1, "#FFC7DA" } }, Width = 1.2, Lifetime = 0.25,
		Transparency = { { 0, 0.3 }, { 1, 1 } }, WidthScale = { { 0, 1 }, { 1, 0 } }, LightEmission = 0.2,
		FaceCamera = true, MinLength = 0.3,
	},
}

-- Module table

local FeelVfxBuilder = {}
FeelVfxBuilder.GENERATOR_ID = GENERATOR_ID
FeelVfxBuilder.VERSION = VERSION
FeelVfxBuilder.ROOT_NAME = ROOT_NAME
FeelVfxBuilder.SPECS = SPECS
FeelVfxBuilder.TRAILS = TRAILS

-- Private

local function numberSeq(value: Seq): NumberSequence
	if type(value) == "number" then
		return NumberSequence.new(value)
	end
	local keys = {}
	for _, row in value do
		table.insert(keys, NumberSequenceKeypoint.new(row[1], row[2]))
	end
	return NumberSequence.new(keys)
end

local function colorSeq(value: any): ColorSequence
	if type(value) == "string" then
		return ColorSequence.new(Color3.fromHex(value))
	end
	local keys = {}
	for _, row in value do
		table.insert(keys, ColorSequenceKeypoint.new(row[1], Color3.fromHex(row[2])))
	end
	return ColorSequence.new(keys)
end

local function range(value: { number }): NumberRange
	return NumberRange.new(value[1], value[2] or value[1])
end

local function carrier(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	return part
end

-- One ParticleEmitter of a design entry (colour `color` overrides the entry's: a tint's emitter).
function FeelVfxBuilder.emitter(name: string, spec: Spec, color: string?, share: number): ParticleEmitter
	local texture = AssetTable.image("img.kit." .. spec.Texture)
	assert(texture, `[SD][FeelVfxBuilder] no picture img.kit.{spec.Texture}`)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = colorSeq(color or spec.Color)
	e.Size = numberSeq(spec.Size)
	e.Transparency = numberSeq(spec.Transparency or 0)
	e.Lifetime = range(spec.Lifetime)
	e.Speed = range(spec.Speed)
	e.SpreadAngle = Vector2.new(spec.SpreadAngle[1], spec.SpreadAngle[2])
	e.Drag = spec.Drag or 0
	local a = spec.Acceleration
	e.Acceleration = if a then Vector3.new(a[1], a[2], a[3]) else Vector3.zero
	e.Rotation = range(spec.Rotation or { 0, 0 })
	e.RotSpeed = range(spec.RotSpeed or { 0, 0 })
	e.LightEmission = spec.LightEmission or 0
	e.LightInfluence = 0 -- the design's sprites are unlit (squishy-fx.js: toneMapped false)
	e.Brightness = 1
	e.EmissionDirection = Enum.NormalId.Top
	if spec.Squash then
		e.Squash = numberSeq(spec.Squash)
	end
	if spec.Orientation then
		e.Orientation = (Enum.ParticleOrientation :: any)[spec.Orientation]
	end
	if spec.LockedToPart then
		e.LockedToPart = true
	end
	local shape = spec.Shape
	if shape == "Cylinder" or shape == "Sphere" then
		e.Shape = (Enum.ParticleEmitterShape :: any)[shape]
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = if spec.ShapeInOut == "Inward"
			then Enum.ParticleEmitterShapeInOut.Inward -- part 3's charge sparkles: drawn into the squishy
			else Enum.ParticleEmitterShapeInOut.Outward
	elseif shape == "Box" then
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	e.Enabled = false
	if spec.Rate then
		e.Rate = spec.Rate * share
		e:SetAttribute("SD_Role", "while")
	else
		e.Rate = 0
		e:SetAttribute("EmitCount", math.max(1, math.floor(spec.Count * share + 0.5)))
	end
	if spec.Tint then
		e:SetAttribute("SD_Tint", spec.Tint)
	end
	return e
end

-- The carrier Part's size for a design shape (the emitters use it as their shape's box). Roblox's Cylinder shape stands
-- along the Part's X axis (checked in a Studio test game 2026-10-28: Size (2, 0.05, 2) sprayed two clumps, (0.05, 2, 2)
-- turned X-up a full ring), so a Cylinder template is X-long and marked SD_AxisX: FeelFx turns its X onto the aim.
function FeelVfxBuilder.shapeSize(spec: Spec): Vector3
	local r = spec.ShapeRadius or 0
	if spec.Shape == "Cylinder" then
		return Vector3.new(POINT, 2 * r, 2 * r)
	elseif spec.Shape == "Sphere" then
		return Vector3.new(2 * r, 2 * r, 2 * r)
	elseif spec.Shape == "Box" then
		local b = spec.ShapeSize
		return Vector3.new(b[1], b[2], b[3])
	end
	return Vector3.new(POINT, POINT, POINT)
end

local function particleTemplate(name: string, spec: Spec): Part
	local part = carrier(name, FeelVfxBuilder.shapeSize(spec))
	part:SetAttribute("SD_Theme", `docs/squishy-fx-spec/{spec.Page or "move.html"} CONFIG.fx.{name}`)
	if spec.Shape == "Cylinder" then
		part:SetAttribute("SD_AxisX", true)
	end
	local tints = spec.Tints
	if tints then
		for i, tint in tints do
			FeelVfxBuilder.emitter(`{name}{i}`, spec, tint, 1 / #tints).Parent = part
		end
	else
		FeelVfxBuilder.emitter(name, spec, nil, 1).Parent = part
	end
	return part
end

local function trailTemplate(name: string, spec: Spec): Part
	local part = carrier(name, Vector3.new(POINT, POINT, POINT))
	part:SetAttribute("SD_Theme", `docs/squishy-fx-spec/{spec.Page or "move.html"} CONFIG.fx.{name}`)
	local half = spec.Width * RIBBON_HALF
	local offset = if spec.Flat then Vector3.new(half, 0, 0) else Vector3.new(0, half, 0)
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "A"
	a0.Position = offset
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "B"
	a1.Position = -offset
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Name = name
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = colorSeq(spec.Color)
	t.Transparency = numberSeq(spec.Transparency)
	t.WidthScale = numberSeq(spec.WidthScale)
	t.Lifetime = spec.Lifetime
	t.MinLength = spec.MinLength or 0.1
	t.MaxLength = 0
	t.FaceCamera = spec.FaceCamera == true
	t.LightEmission = spec.LightEmission or 0
	t.LightInfluence = 0
	t.Brightness = 1
	t.Enabled = true
	t.Parent = part
	return part
end

-- Public

function FeelVfxBuilder.build(Generated: any?): Folder
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root:SetAttribute(
		"SD_Note",
		"Physics upgrade parts 1-4 (2026-10-28): the design's movement, hit, flight and highway particles and trails for the VFX Studio plugin; drag a template into Workspace, select it and press Emit / Trail to preview."
	)
	local names = {}
	for name in SPECS do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		particleTemplate(name, SPECS[name]).Parent = root
	end
	for name, spec in TRAILS do
		trailTemplate(name, spec).Parent = root
	end
	if Generated then
		Generated.mark(root, GENERATOR_ID, VERSION)
	end
	return root
end

return FeelVfxBuilder
