--!strict
-- WorldLook: the lobby look upgrade's numbers in one place (user OK 2026-10-14, "do fixes from 1 to 3": FIX 1 lamps and
-- halos, FIX 2 finishes, FIX 3 the Blender mesh library, round 1). Server only, Edit mode only (ServerStorage.SDTools);
-- LobbyBuilder and CapsuleBuilder require it. No requires. Colours are Art/Palette token NAMES (no colour value lives
-- here). "NOT IN DESIGN" = beyond the design file (the user OK'd it for this upgrade); "reading" = our own choice.
-- Mesh ids live only inside the user-imported ServerStorage.SD_MeshLibrary MeshParts (like the Sky's skybox in
-- Lighting); never in code or Shared/AssetTable.

-- Types

export type Lamp = { token: string, brightness: number, range: number }
export type Halo = {
	token: string,
	size: number,
	gateSize: number,
	speed: NumberRange,
	drag: number,
	spread: Vector2,
	rate: number,
	lifetime: number,
}
export type Finish = { material: Enum.Material?, reflectance: number? }
export type MeshPiece = { name: string, size: Vector3, center: Vector3, noShadow: boolean? }

-- Module table

local WorldLook = {}

-- FIX 1 lamps (NOT IN DESIGN: the design lobby has no light objects). Shadowless PointLights in the design's lamp_glow
-- colour (lobby.js:78), each where the sun does not reach.
local LAMPS: { [string]: Lamp } = {
	SpawnLamp = { token = "LobbyLampGlow", brightness = 1.5, range = 24 }, -- 3 under the duel tower deck's underside
	ShopLamp = { token = "LobbyLampGlow", brightness = 1.5, range = 14 }, -- under the shop's awning
}
WorldLook.LAMPS = LAMPS

-- FIX 1 halo (NOT IN DESIGN): a slow twinkle over an item, drifting up about 1.7 studs (speed / drag ×
-- (1 - e^(-drag × lifetime))), 3 per second, about 4-5 alive, its size held from 0.15 to 0.7 of its life.
-- LobbyGold (the design's gold_trim) reads on cream; on the sky only by size: a gate's halo is seen from its plot spawn
-- about 44 studs away, so it takes gateSize (0.9 × 44 / 20: the hub halos' size on screen).
local HALO: Halo = {
	token = "LobbyGold",
	size = 0.9,
	gateSize = 2,
	speed = NumberRange.new(3, 4),
	drag = 2,
	spread = Vector2.new(60, 60),
	rate = 3,
	lifetime = 1.5,
}
WorldLook.HALO = HALO

-- FIX 2: a finish per Palette token, matched by COLOUR on the finished tree, so two coplanar faces of one colour always
-- share a material (Flicker_Test keys faces by colour/material). Reflectance = (0.6 - roughness) / 2 of the design's
-- roughness (lobby.js:72-82): a reading, NOT IN DESIGN (the design's toon shading never shows roughness).
local FINISH: { [string]: Finish } = {
	IslandGrass = { material = Enum.Material.Grass }, -- NOT IN DESIGN (spec §8 colour; the user named grass)
	IslandGrassEdge = { material = Enum.Material.Grass },
	IslandSand = { material = Enum.Material.Sand }, -- NOT IN DESIGN (the user named sand)
	HubWood = { material = Enum.Material.Wood }, -- spec §8 "wood": the 38 tree trunks and 10 planter nests
	LobbyVelvetRope = { material = Enum.Material.Fabric }, -- velvet_rope (lobby.js:77): the range's rope rails
	LobbyRoyalVelvet = { material = Enum.Material.Fabric }, -- royal_velvet (lobby.js:77): the royal capsule
	IslandSea = { reflectance = 0.15 }, -- NOT IN DESIGN: a little sky on the water
	IslandShallow = { reflectance = 0.15 }, -- the shallow ring, fountain and pond water
	LobbyGold = { reflectance = 0.13 }, -- gold_trim rough .34, metalness .35 (lobby.js:77)
	LobbyCoinInner = { reflectance = 0.15 }, -- coin_inner rough .30 (lobby.js:249)
	LobbyGlass = { reflectance = 0.24 }, -- glass rough .12 (its Transparency .74 stays)
	LobbyJellyCore = { reflectance = 0.15 }, -- jelly_core rough .30 (the jelly capsule)
	-- "Shiny candy" (the user's words). The design's candy is rough .60-.66, which the formula makes 0: NOT IN DESIGN.
	-- Kept only if the Batch A on/off picture shows it; else delete these 6 lines.
	LobbyMint = { reflectance = 0.1 },
	LobbyStrawberry = { reflectance = 0.1 },
	LobbyButter = { reflectance = 0.1 },
	LobbyViolet = { reflectance = 0.1 },
	LobbySky = { reflectance = 0.1 },
	LobbyStrawberryRed = { reflectance = 0.1 },
}
WorldLook.FINISH = FINISH

local TOY_ATTRIBUTE = "SD_BlueprintId" -- SquishyBuilder's toys (shared with the runtime squishies) keep their own look

-- FIX 3 (round 1): the Blender meshes (tools/meshes/lobby_meshes.py, the user's import).
WorldLook.MESH_LIBRARY = "SD_MeshLibrary" -- ServerStorage, the user's import (hand-made, never generated)
-- The library's attribute, true only once the user says Roblox approved the meshes (before that, other players may see
-- nothing where a mesh is): until then every rebuild keeps today's parts.
WorldLook.MESH_APPROVED = "SD_MeshesApproved"

-- Round-1 sets: pieces in build order. size / center = the Blender printout (studs, Roblox axes, in the set's frame:
-- DonutArch the arch frame F * (0, GATE_PILLAR.Y, gateZ), TowerPillar the pillar's centre, Lollipop the stick's foot,
-- CupcakeTree and CloudBunny their ground frame). The builder sets every Size, so only the import's proportions matter.
-- noShadow: the sprinkles' and the cloud's bounds are big, so the < 2-stud render rule misses them; the lollipop rings'
-- shadow falls inside the disk's, and they spin (a moving caster costs shadow work every frame).
local MESHES: { [string]: { MeshPiece } } = {
	DonutArch = {
		{ name = "DonutArch_Dough", size = Vector3.new(20.6, 10.3, 2.132), center = Vector3.new(0, 5.15, 0) },
		{ name = "DonutArch_Icing", size = Vector3.new(20.348, 9.356, 2.281), center = Vector3.new(0.029, 5.602, 0) },
		{
			name = "DonutArch_Sprinkles_White",
			size = Vector3.new(17.242, 4.96, 2.656),
			center = Vector3.new(-0.677, 6.15, 0),
			noShadow = true,
		},
		{
			name = "DonutArch_Sprinkles_Sky",
			size = Vector3.new(8.892, 8.338, 2.64),
			center = Vector3.new(-4.084, 5.173, 0),
			noShadow = true,
		},
		{
			name = "DonutArch_Sprinkles_Butter",
			size = Vector3.new(13.86, 6.711, 2.655),
			center = Vector3.new(-2.126, 6.792, 0),
			noShadow = true,
		},
		{
			name = "DonutArch_Sprinkles_Mint",
			size = Vector3.new(16.967, 6.559, 2.531),
			center = Vector3.new(0.804, 5.664, 0),
			noShadow = true,
		},
	},
	TowerPillar = {
		{ name = "tower_pillar", size = Vector3.new(7, 34.2, 7), center = Vector3.new(0, 0, 0) },
	},
	Lollipop = {
		{ name = "Lollipop_White", size = Vector3.new(14, 31, 1.75), center = Vector3.new(0, 15.5, 0) },
		{
			name = "Lollipop_RingA",
			size = Vector3.new(13.58, 13.58, 2.66),
			center = Vector3.new(0, 24, 0),
			noShadow = true,
		},
		{
			name = "Lollipop_RingB",
			size = Vector3.new(10.78, 10.78, 2.66),
			center = Vector3.new(0, 24, 0),
			noShadow = true,
		},
	},
	CupcakeTree = {
		{ name = "CupcakeTree_Cup", size = Vector3.new(4.28, 1.9, 4.28), center = Vector3.new(0, 4.95, 0) },
		{ name = "CupcakeTree_Frosting", size = Vector3.new(4.6, 2.4, 4.6), center = Vector3.new(0.023, 6.8, -0.023) },
	},
	CloudBunny = {
		{
			name = "CloudBunny",
			size = Vector3.new(16.961, 16.863, 12.041),
			center = Vector3.new(0.002, 4.371, 0.002),
			noShadow = true,
		},
	},
}
WorldLook.MESHES = MESHES

-- Public

-- Whether `part` sits inside a toy model under `root`.
function WorldLook.inToy(part: Instance, root: Instance): boolean
	local node = part.Parent
	while node and node ~= root do
		if node:GetAttribute(TOY_ATTRIBUTE) ~= nil then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Gives every visible SmoothPlastic part under `root` (toys aside) its colour's FINISH. A MeshPart keeps SmoothPlastic
-- (no UVs for a textured material) and takes only the reflectance; reflectance never goes down. Throws when `palette`
-- lacks a FINISH token or two FINISH tokens share a colour.
function WorldLook.finish(root: Instance, palette: { [string]: any })
	local byHex: { [string]: Finish } = {}
	for token, look in FINISH do
		local c = palette[token]
		assert(typeof(c) == "Color3", "[SD][WorldLook] Art/Palette has no colour " .. token)
		local hex = (c :: Color3):ToHex()
		assert(byHex[hex] == nil, "[SD][WorldLook] two FINISH tokens share the colour of " .. token)
		byHex[hex] = look
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.SmoothPlastic and d.Transparency < 1 then
			local look = byHex[d.Color:ToHex()]
			if look and not WorldLook.inToy(d, root) then
				if look.material and not d:IsA("MeshPart") then
					d.Material = look.material
				end
				if look.reflectance then
					d.Reflectance = math.max(d.Reflectance, look.reflectance)
				end
			end
		end
	end
end

-- FIX 3: the set's library MeshParts by piece name (the first MeshPart of that name at any depth, so a same-named
-- wrapper Model is passed over), or nil when the library or a piece is missing, not an archivable MeshPart, or off in
-- proportions (a turned import; the builder sets Size, so any uniform scale passes).
function WorldLook.meshTemplates(library: Instance?, pieces: { MeshPiece }): { [string]: MeshPart }?
	if library == nil then
		return nil
	end
	local descendants = library:GetDescendants()
	local found: { [string]: MeshPart } = {}
	for _, piece in pieces do
		local mesh: MeshPart? = nil
		for _, d in descendants do
			if d.Name == piece.name and d:IsA("MeshPart") then
				mesh = d :: MeshPart
				break
			end
		end
		if mesh == nil or not mesh.Archivable or (mesh.Size.Unit - piece.size.Unit).Magnitude > 0.01 then
			return nil
		end
		found[piece.name] = mesh
	end
	return found
end

return WorldLook
