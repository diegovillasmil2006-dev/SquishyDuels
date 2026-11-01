--!strict
-- HighwayTraps: the 7 highway traps of the owner's "Launchers & Biomes - Concept Sheet" (Desktop "jason designs",
-- Candy Toy-Box Park Lobby.zip, concept-kit.js:282-300, `M.<biome>_<trap>`), one per biome in highway order, ported
-- part for part (traps you can see, plan step 5, 2026-10-31: HighwayService shows the landing biome's trap under a
-- trapped throw where it stops). Each stands on the lane top at its origin (the sheet's P(id, [x, 1, z]), y 1 = the
-- lane top), x right and z back like the lane (WorldLayout.highwayCFrame).
-- The sheet's kit calls (concept-kit.js:88-95): u = a box standing on y (its centre size.y / 2 higher), b = a box at
-- its centre, c = an upright cylinder {diameter, height} at its centre, s = a ball {diameter}; rot = the sheet's
-- degrees (three.js XYZ = CFrame.fromEulerAnglesXYZ). The palette keys name a Roblox material and the sheet's hex.
-- Glass parts are see-through (0.45, HighwayZones' props), Neon and Glass cast no shadow. Boosters (plan step 6) add
-- r = the sheet's torus {radius, tube, segments} as that many straight segments in its XY plane (three.js'
-- TorusGeometry ring, standing across the lane).
--   HighwayTraps.build(biome, origin) -> Model?  an unparented decor Model (anchored, no collide, query or touch) of
--                                                biome 1..7's trap at `origin`; nil for any other biome
--   HighwayTraps.make(piece, origin) -> Model    the same for any piece in this shape (Art/HighwayBoosters' too)
--   HighwayTraps.kit                             the u / b / c / s / r constructors of a piece's parts

-- Types

export type PartDef = { kind: string, key: string, size: { number }, at: { number }, rot: { number }? }
export type Trap = { id: string, pal: { [string]: { string } }, parts: { PartDef } }

-- Constants

local GLASS_SEE_THROUGH = 0.45

local function u(key: string, size: { number }, at: { number }, rot: { number }?): PartDef
	return { kind = "u", key = key, size = size, at = at, rot = rot }
end
local function b(key: string, size: { number }, at: { number }, rot: { number }?): PartDef
	return { kind = "b", key = key, size = size, at = at, rot = rot }
end
local function c(key: string, d: number, h: number, at: { number }, rot: { number }?): PartDef
	return { kind = "c", key = key, size = { d, h }, at = at, rot = rot }
end
local function s(key: string, d: number, at: { number }): PartDef
	return { kind = "s", key = key, size = { d }, at = at }
end
local function r(key: string, radius: number, tube: number, at: { number }, segments: number): PartDef
	return { kind = "r", key = key, size = { radius, tube, segments }, at = at }
end

local TRAPS: { Trap } = {
	{ -- 1 Candy Meadow (concept-kit.js:282)
		id = "cm_gum_puddle",
		pal = { gum = { "Glass", "FF9ED2" }, bub = { "Glass", "FF7FC0" } },
		parts = {
			u("gum", { 8, 0.35, 5 }, { 0, 0, 0 }),
			u("gum", { 5, 0.36, 6.5 }, { 1, 0, 0 }),
			u("gum", { 3, 0.5, 3 }, { -2.4, 0, 1.4 }, { 0, 20, 0 }),
			s("bub", 2.2, { 1.6, 1.2, -0.6 }),
		},
	},
	{ -- 2 Bakery Town (concept-kit.js:285)
		id = "bt_jam_puddle",
		pal = { jam = { "Glass", "C2185B" }, seed = { "Sand", "E0315F" } },
		parts = {
			u("jam", { 7, 0.4, 5 }, { 0, 0, 0 }),
			u("jam", { 4, 0.42, 7 }, { 1.4, 0, 0.4 }, { 0, 15, 0 }),
			u("jam", { 2.4, 0.6, 2.4 }, { -2.6, 0, -1.6 }, { 0, 30, 0 }),
			u("seed", { 0.6, 0.3, 0.6 }, { -1, 0.4, 1 }, { 0, 45, 0 }),
			u("seed", { 0.6, 0.3, 0.6 }, { 1.8, 0.4, -1.2 }, { 0, 45, 0 }),
			u("seed", { 0.6, 0.3, 0.6 }, { 0.4, 0.4, 2.6 }, { 0, 45, 0 }),
			u("seed", { 0.6, 0.3, 0.6 }, { 2.4, 0.4, 1.6 }, { 0, 45, 0 }),
		},
	},
	{ -- 3 Boba Lagoon (concept-kit.js:288)
		id = "bl_splash_pool",
		pal = { rim = { "WoodPlanks", "EED6B8" }, water = { "Glass", "7FD8D0" }, drop = { "Glass", "DFF4FF" } },
		parts = {
			u("rim", { 10, 1, 1 }, { 0, 0, -4.5 }),
			u("rim", { 1, 1, 8 }, { -4.5, 0, 0 }),
			u("rim", { 10, 1, 1 }, { 0, 0, 4.5 }),
			u("rim", { 1, 1, 8 }, { 4.5, 0, 0 }),
			u("water", { 8, 0.7, 8 }, { 0, 0, 0 }),
			b("drop", { 0.8, 0.8, 0.8 }, { -1.5, 2, 0 }, { 45, 45, 0 }),
			b("drop", { 0.8, 0.8, 0.8 }, { 1.4, 2.8, -1 }, { 45, 45, 0 }),
			b("drop", { 0.8, 0.8, 0.8 }, { 0.2, 3.6, 1.2 }, { 45, 45, 0 }),
		},
	},
	{ -- 4 Frozen Dessert Peaks (concept-kit.js:291)
		id = "fd_marshmallow",
		pal = { m = { "Fabric", "FFF3F7" }, toast = { "Sand", "F2C487" } },
		parts = {
			c("m", 3.2, 2.4, { -1.8, 1.2, 0 }),
			c("m", 3.2, 2.4, { 1.8, 1.2, 0.4 }),
			c("m", 3.0, 2.2, { 0, 3.0, 0.2 }, { 90, 0, 70 }),
			c("toast", 3.0, 0.2, { -1.8, 2.5, 0 }),
		},
	},
	{ -- 5 Lava Volcano (concept-kit.js:294)
		id = "lv_lava_pit",
		pal = { rim = { "Basalt", "3A2C3A" }, lava = { "Neon", "FF6A3D" }, bub = { "Neon", "FFB03A" } },
		parts = {
			c("rim", 11, 0.8, { 0, 0.4, 0 }),
			c("lava", 9, 0.85, { 0, 0.43, 0 }),
			u("bub", { 1, 0.6, 1 }, { -2, 0.85, 1 }, { 0, 30, 0 }),
			u("bub", { 0.8, 0.48, 0.8 }, { 1.6, 0.85, -1.4 }, { 0, 30, 0 }),
			u("bub", { 0.6, 0.36, 0.6 }, { 0.6, 0.85, 2.2 }, { 0, 30, 0 }),
		},
	},
	{ -- 6 Rainbow Road (concept-kit.js:297)
		id = "rr_cloud_gap",
		pal = { cloud = { "Fabric", "FFFFFF" }, shade = { "Fabric", "E6DDFF" } },
		parts = {
			u("shade", { 12, 0.6, 9 }, { 0, -0.6, 0 }),
			b("cloud", { 9, 1.6, 7 }, { 0, 0.5, 0 }),
			b("cloud", { 5, 1.4, 4 }, { -2.6, 1.3, 1 }),
			b("cloud", { 4, 1.2, 4 }, { 2.8, 1.2, -1.2 }),
			b("cloud", { 3, 1, 3 }, { 0.4, 2, 0.4 }),
		},
	},
	{ -- 7 Divine Heaven (concept-kit.js:300)
		id = "dh_soft_cloud",
		pal = { cloud = { "Fabric", "FFE9A8" }, hi = { "Fabric", "FFF6EC" } },
		parts = {
			b("cloud", { 10, 1.6, 8 }, { 0, 0.6, 0 }),
			b("cloud", { 6, 1.6, 5 }, { -2.4, 1.6, 0.8 }),
			b("cloud", { 5, 1.4, 4 }, { 2.6, 1.5, -1 }),
			b("hi", { 3, 1, 3 }, { 0.4, 2.6, 0.2 }),
		},
	},
}

-- Module table

local HighwayTraps = {}

HighwayTraps.list = TRAPS
HighwayTraps.kit = { u = u, b = b, c = c, s = s, r = r }

-- Private

local function finish(part: Part, material: Enum.Material, hex: string, parent: Instance)
	part.Color = Color3.fromHex(hex)
	part.Material = material
	part.Transparency = if material == Enum.Material.Glass then GLASS_SEE_THROUGH else 0
	part.CastShadow = material ~= Enum.Material.Neon and material ~= Enum.Material.Glass
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
end

-- The sheet's torus: `segments` straight pieces round a circle of `radius` in its XY plane, each the tube thick.
local function makeRing(def: PartDef, material: Enum.Material, hex: string, origin: CFrame, parent: Instance)
	local radius, tube, segments = def.size[1], def.size[2], def.size[3]
	local length = 2 * radius * math.sin(math.pi / segments) + tube -- a little overlap closes the joints
	local centre = origin * CFrame.new(def.at[1], def.at[2], def.at[3])
	for i = 0, segments - 1 do
		local angle = (i + 0.5) * 2 * math.pi / segments
		local part = Instance.new("Part")
		part.Name = def.key
		part.Size = Vector3.new(2 * tube, length, 2 * tube)
		part.CFrame = centre
			* CFrame.new(radius * math.cos(angle), radius * math.sin(angle), 0)
			* CFrame.Angles(0, 0, angle)
		finish(part, material, hex, parent)
	end
end

local function makePart(def: PartDef, pal: { [string]: { string } }, origin: CFrame, parent: Instance)
	local entry = pal[def.key]
	local material = (Enum.Material :: any)[entry[1]] :: Enum.Material
	if def.kind == "r" then
		makeRing(def, material, entry[2], origin, parent)
		return
	end
	local part = Instance.new("Part")
	part.Name = def.key
	local at = Vector3.new(def.at[1], def.at[2], def.at[3])
	local turn = if def.rot
		then CFrame.fromEulerAnglesXYZ(math.rad(def.rot[1]), math.rad(def.rot[2]), math.rad(def.rot[3]))
		else CFrame.identity
	if def.kind == "c" then
		local d, h = def.size[1], def.size[2]
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(h, d, d)
		turn *= CFrame.Angles(0, 0, math.rad(90)) -- a Roblox cylinder runs along X: stand it up
	elseif def.kind == "s" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(def.size[1], def.size[1], def.size[1])
	else
		part.Size = Vector3.new(def.size[1], def.size[2], def.size[3])
		if def.kind == "u" then
			at += Vector3.new(0, def.size[2] / 2, 0)
		end
	end
	part.CFrame = origin * CFrame.new(at) * turn
	finish(part, material, entry[2], parent)
end

-- Public

function HighwayTraps.make(piece: Trap, origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = piece.id
	for _, def in piece.parts do
		makePart(def, piece.pal, origin, model)
	end
	model.WorldPivot = origin
	return model
end

function HighwayTraps.build(biome: number, origin: CFrame): Model?
	local trap = TRAPS[biome]
	return if trap then HighwayTraps.make(trap, origin) else nil
end

return HighwayTraps
