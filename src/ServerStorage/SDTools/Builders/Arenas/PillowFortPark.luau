--!strict
-- PillowFortPark: builds the arena template "Arena_PillowFortPark", the "Plush playroom - quilted court, pillow walls,
-- blanket fort, giant sofa" (design sd/arenas2.js:45-114, facts sd/main.js:445-448; phase 4 spec 2026-10-11 §2.3,
-- §4.5, §4.6). Server only, Edit mode only (ServerStorage.SDTools); Main's target "arena_pillow_fort_park" runs
-- build(ctx) and swaps the tree into ServerStorage.SD_Templates. ArenaKit makes the gameplay frame (Candy Court's) and
-- the cover (World/Arenas); this module adds the art:
--   Floor     the mint and strawberry quilt halves, out to the walls
--   Markings  the quilt's stitch lines every 8 studs, the design's white lines, mint / strawberry end and team lines,
--             centre ring and ring spawn marks (ArenaKit.court)
--   Rails     the bolster pillows round the court with their lilac bands, in the gutter
--   Cover     the Plush Blocks' star and heart patches (glyphs)
--   Decor     the rug apron, a Pillow Fort behind each end (D1), the giant sofa with one giant squishy (D5: the other two
--             are extras), the toy shelf, 3 string lights and 5 hanging stars.
-- Every design number carries its sd/arenas2.js line; out-of-bounds items keep their distance beyond the court edge
-- (spec §4.6, ArenaKit.at) and stay inside the 190-stud apron. Plain colours only (D6: the bulbs do not glow). Rounded
-- pills are blocks (decor) and tori are flat discs (spec §4.6).

local ArenaKit = require(script.Parent.ArenaKit)

-- Types

type Kit = ArenaKit.Kit

-- Constants

local ARENA_ID = "pillow_fort_park"
local HALF_PI = math.pi / 2

local COURT: ArenaKit.CourtStyle = {
	line = "White", -- design: sd/arenas2.js:50 quilt_stitch #FFFFFF (the court() line colour, :52)
	sideWidth = 1, -- design: sd/arenas2.js:21
	endWidth = 1,
	endA = "ArenaTeamStrawberry", -- design: sd/arenas2.js:21 (berry end line at +x)
	endB = "ArenaTeamMint",
	centreWidth = 2.2, -- design: sd/arenas2.js:22
	edgeWidth = 0.8, -- design: sd/arenas2.js:22
	zoneWidth = 0.8, -- design: sd/arenas2.js:26
	teamA = "ArenaTeamStrawberry",
	teamB = "ArenaTeamMint",
	halfA = "ArenaQuiltStrawberry", -- design: sd/arenas2.js:50 quilt_strawberry
	halfB = "ArenaQuiltMint", -- design: sd/arenas2.js:50 quilt_mint
	circle = "ring", -- design: sd/arenas2.js:23 flat(10, 11.2)
	padMarker = "ring", -- design: sd/arenas2.js:27
}

-- Quilt stitches (sd/arenas2.js:53): dashes 0.3 x 1.8 on lines every 8 studs both ways; here continuous 0.3-wide lines
-- (the dashes would cost hundreds of parts), under the court lines.
local STITCH_PITCH = 8 -- design: sd/arenas2.js:53
local STITCH_WIDTH = 0.3 -- design: sd/arenas2.js:53
local STITCH_TOPS = { 0.03, 0.032 } -- along Z, along X (crossings never share a plane; court lines top 0.04)

-- Bolster pillows (sd/arenas2.js:56-59): capsules r 1.9, the long sides' L / 2 - 6 per half in periwinkle or cream by
-- quarter, the ends' W - 4 in the team colour, lilac band tori (r 1.95, tube 0.28) every 16. Spec §4.5: Ø3.8, beside
-- the court edge; each long one 48 per half (82 / 88 of it), each end one 70 (124 / 128 of the width), with ball ends.
local BOLSTER = 3.8 -- design: sd/arenas2.js:57 CapsuleGeometry(1.9)
local LONG_BOLSTER = 48
local END_BOLSTER = 70
local BAND = 2 * (1.95 + 0.28) -- design: sd/arenas2.js:57 TOR(1.95, 0.28)
local BAND_THICKNESS = 2 * 0.28
local BAND_PITCH = 16 -- design: sd/arenas2.js:57-58

-- Pillow Fort (sd/arenas2.js:67-77), a backdrop behind each end (D1), opening toward the court.
local FORT_Z = 62 -- spec §4.6

-- Giant sofa (sd/arenas2.js:92-95) off the +z long side (X +76 by the decor rule), 2 studs in so its back fits the
-- apron; seat, back and cushions cut from 170 to 150 long (spec §4.6), arms at the ends. The legs sit under the floor in
-- the design (y -1) and are left out.
local SOFA_X = 74
local SOFA_LENGTH = 150 -- spec §4.6 (design 170)
local SOFA_CUSHION = 48 -- 3 across the 150 (design 54 of 170)
-- The middle giant squishy (sd/arenas2.js:112 MochiFox at x 0, y 19, 24 tall, facing the court); D5: the other two
-- (CloudBunny, BobaBear, ~60 parts) are extras, off.
local SOFA_SQUISHY = "mochi_fox"
local SQUISHY_TALL = 24 -- design: sd/arenas2.js:112
local SQUISHY_SEAT_Y = 19 -- design: sd/arenas2.js:112

-- Giant toy shelf (sd/arenas2.js:97-102) off the -z long side (X -70), cut from 150 to 130 long (spec §4.6), books
-- seeded like the design's rng(31): about 30 (spec §4.6).
local SHELF_LENGTH = 130
local BOOK_COLORS = { "ArenaTeamStrawberry", "ArenaSky", "ArenaButter", "ArenaViolet", "ArenaTeamMint" } -- :100
local BOOKS_PER_ROW = 10
local SEED = 31 -- design: sd/arenas2.js:48 rng(31)

-- String lights (sd/arenas2.js:104-106): catenaries at z -34 / 0 / 34 from x -L / 2 - 26 to L / 2 + 26, y 44 at the
-- ends and 32 in the middle; 8 wire segments and 7 bulbs each (spec §4.6: the design has 60 segments, 20 bulbs).
local LIGHT_SEGMENTS = 8
local BULB = 2 * 0.55 -- design: sd/arenas2.js:105 SPH(0.55)

-- Hanging stars (sd/arenas2.js:107-108): { x, z, y } star r 3.2 butter on a string to y 40.
local STARS = { { -50, -34, 30 }, { 0, 0, 26 }, { 50, 34, 30 }, { -20, 34, 33 }, { 30, -34, 33 } }
local STAR_SIZE = 2 * 3.2 -- design: sd/arenas2.js:107 starGeo(3.2, 1.4, 0.8)

-- Plush Block patches (sd/arenas2.js:80): the front (+z) patch white, the side (+x) patch butter; emb 0 = star in front.
local PLUSH_EMBLEMS: { [string]: number } = { Plush1 = 0, Plush2 = 1 } -- design: sd/arenas2.js:88
local PATCH_SIZE = 2 * 1.3 -- design: sd/arenas2.js:79 starGeo(1.3, 0.6) / heartGeo(1.2)

-- Module table

local PillowFortPark = {}
PillowFortPark.GENERATOR_ID = "arena_pillow_fort_park"
PillowFortPark.VERSION = 1
PillowFortPark.ROOT_NAME = "Arena_PillowFortPark"
PillowFortPark.ARENA_ID = ARENA_ID

-- Private

local function stitches(k: Kit)
	local halfX, halfZ = k.layout.halfX, k.layout.halfZ
	local count = 0
	for x = -halfX + STITCH_PITCH, halfX - 1, STITCH_PITCH do
		count += 1
		ArenaKit.part(
			k,
			k.markings,
			string.format("StitchX_%02d", count),
			Vector3.new(STITCH_WIDTH, STITCH_TOPS[1], 2 * halfZ),
			CFrame.new(x, STITCH_TOPS[1] / 2, 0),
			"White",
			"marking"
		)
	end
	count = 0
	for z = -halfZ + STITCH_PITCH, halfZ - 1, STITCH_PITCH do
		count += 1
		ArenaKit.part(
			k,
			k.markings,
			string.format("StitchZ_%02d", count),
			Vector3.new(2 * halfX, STITCH_TOPS[2], STITCH_WIDTH),
			CFrame.new(0, STITCH_TOPS[2] / 2, z),
			"White",
			"marking"
		)
	end
end

-- One bolster along `axis` ("X" or "Z") centred at `centre`, `length` long, with ball ends and bands every 16.
local function bolster(
	k: Kit,
	name: string,
	centre: Vector3,
	axis: string,
	length: number,
	token: string,
	bands: number
)
	local turn = if axis == "Z" then CFrame.Angles(0, HALF_PI, 0) else CFrame.identity -- a Cylinder runs along its X
	local frame = CFrame.new(centre) * turn
	ArenaKit.rod(k, k.rails, name, BOLSTER, length, frame, token, "solid", Enum.Material.Fabric)
	for index, sign in { -1, 1 } do
		ArenaKit.ball(
			k,
			k.rails,
			`{name}End{index}`,
			BOLSTER,
			frame:PointToWorldSpace(Vector3.new(sign * length / 2, 0, 0)),
			token,
			"solid"
		)
	end
	for index = 1, bands do
		local offset = (index - (bands + 1) / 2) * BAND_PITCH
		ArenaKit.rod(
			k,
			k.rails,
			`{name}Band{index}`,
			BAND,
			BAND_THICKNESS,
			frame * CFrame.new(offset, 0, 0),
			"ArenaLilac",
			"solid"
		) -- design: sd/arenas2.js:57-58
	end
end

local function buildRails(k: Kit)
	local halfX, halfZ = k.layout.halfX, k.layout.halfZ
	local y = BOLSTER / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- design: sd/arenas2.js:57 (sz * sx) < 0 ? peri : cream, in game: periwinkle where X and Z share a sign.
			local token = if sx * sz > 0 then "ArenaPeriwinkle" else "ArenaCushionCream"
			bolster(
				k,
				`Bolster{if sz < 0 then "A" else "B"}{if sx < 0 then "West" else "East"}`,
				Vector3.new(sx * (halfX + BOLSTER / 2), y, sz * halfZ / 2),
				"Z",
				LONG_BOLSTER,
				token,
				3
			)
		end
	end
	for _, sz in { -1, 1 } do
		bolster(
			k,
			`BolsterEnd{if sz < 0 then "A" else "B"}`,
			Vector3.new(0, y, sz * (halfZ + BOLSTER / 2)),
			"X",
			END_BOLSTER,
			if sz < 0 then "ArenaTeamStrawberry" else "ArenaTeamMint", -- design: sd/arenas2.js:58
			5
		)
	end
end

-- The Plush Blocks' patches (sd/arenas2.js:80): the design's +z face is the Body's Back face, +x its Right face.
local function plushPatches(k: Kit)
	for _, piece in k.def.cover do
		local design = string.sub(piece.name, 3)
		local emb = PLUSH_EMBLEMS[design]
		if emb == nil then
			continue
		end
		local model = k.cover:FindFirstChild("Cover_" .. piece.name)
		local body = if model then model:FindFirstChild("Body") else nil
		if body == nil or not body:IsA("BasePart") then
			error(`no Body for {piece.name}`, 0)
		end
		local front = if emb == 1 then ArenaKit.HEART else ArenaKit.STAR
		local side = if emb == 1 then ArenaKit.STAR else ArenaKit.HEART
		ArenaKit.glyph(k, body, Enum.NormalId.Back, front, "White", "ArenaInk", PATCH_SIZE)
		ArenaKit.glyph(k, body, Enum.NormalId.Right, side, "ArenaButter", "ArenaInk", PATCH_SIZE)
	end
end

-- The Pillow Fort (sd/arenas2.js:67-77) at (0, z), its open side toward local +x (the court).
local function fort(k: Kit, name: string, z: number, ry: number, print: string, team: string)
	local model, frame = ArenaKit.group(k, name, 0, z, ArenaKit.yaw(ry))
	local function block(part: string, size: Vector3, x: number, y: number, pz: number, token: string)
		ArenaKit.part(k, model, part, size, frame * CFrame.new(x, y, pz), token)
	end
	block("BackCushion", Vector3.new(4.8, 7.4, 17.4), -7, 3.7, 0, "ArenaCushionCream") -- design: sd/arenas2.js:69
	for index, sign in { -1, 1 } do
		block(`SideCushion{index}`, Vector3.new(11, 7, 4.8), -1.6, 3.5, sign * 7.2, print) -- design: sd/arenas2.js:70
		ArenaKit.ball(
			k,
			model,
			`Button{index}`,
			0.9,
			frame:PointToWorldSpace(Vector3.new(-1.6, 3.5, sign * 9.65)),
			"ArenaTrimWhite"
		)
		-- The slanted blanket: a panel rb(14.4, 0.7, 9.6) with 2 white stripes, tilted 0.72 rad (sd/arenas2.js:71).
		local slope = frame * CFrame.new(-1.6, 10.2, sign * 3.6) * CFrame.Angles(sign * 0.72, 0, 0)
		ArenaKit.part(k, model, `Blanket{index}`, Vector3.new(14.4, 0.7, 9.6), slope, team)
		for stripe, offset in { -2.6, 2.6 } do
			ArenaKit.part(
				k,
				model,
				`BlanketStripe{index}_{stripe}`,
				Vector3.new(14.5, 0.76, 1),
				slope * CFrame.new(0, 0, offset),
				"ArenaTrimWhite"
			)
		end
	end
	ArenaKit.rod(k, model, "RidgeRoll", 1.4, 14.4 + 1.4, frame * CFrame.new(-1.6, 13.4, 0), "ArenaCushionCream") -- :72
	ArenaKit.disc(k, model, "FlagPole", 0.44, 7, frame:PointToWorldSpace(Vector3.new(5.4, 15.4, 0)), "ArenaTrimWhite") -- :73
	-- The pennant: a triangle (0, 0) - (4.2, -1.3) - (0, -2.6) at (5.4, 18.8) (sd/arenas2.js:73-74), flying along +x.
	ArenaKit.triangle(
		k,
		model,
		"Pennant",
		2.6,
		4.2,
		0.15,
		frame * CFrame.new(5.4, 18.8 - 1.3, 0) * CFrame.Angles(0, 0, -HALF_PI),
		team
	)
	ArenaKit.disc(k, model, "Rug", 9.2, 0.05, frame:PointToWorldSpace(Vector3.new(-1, 0.025, 0)), "ArenaLilac") -- :75
end

-- The giant sofa (sd/arenas2.js:92-95): its seat along Z, its back away from the court (+X), and the giant squishy.
local function sofa(k: Kit, shared: Instance)
	local model, frame = ArenaKit.group(k, "GiantSofa", SOFA_X, 0, ArenaKit.yaw(0))
	local half = SOFA_LENGTH / 2
	ArenaKit.part(k, model, "Seat", Vector3.new(SOFA_LENGTH, 13, 36), frame * CFrame.new(0, 6.5, 0), "ArenaPeriwinkle") -- :93
	ArenaKit.part(
		k,
		model,
		"Back",
		Vector3.new(SOFA_LENGTH, 34, 12),
		frame * CFrame.new(0, 17, 15),
		"ArenaPeriwinkleDeep"
	) -- :93
	for index, sign in { -1, 1 } do
		ArenaKit.part(
			k,
			model,
			`Arm{index}`,
			Vector3.new(18, 24, 40),
			frame * CFrame.new(sign * (half + 5), 12, 0),
			"ArenaPeriwinkle"
		) -- design: sd/arenas2.js:93 (arms 18 wide overlapping the seat ends by 4)
	end
	for index = -1, 1 do
		ArenaKit.part(
			k,
			model,
			`Cushion{index + 2}`,
			Vector3.new(SOFA_CUSHION, 7, 31),
			frame * CFrame.new(index * SOFA_LENGTH / 3, 15.5, -1),
			"ArenaCushionCream"
		) -- design: sd/arenas2.js:94 pill(54, 7, 31) at x k * 55, y 15.5
	end
	-- The giant squishy: Art/SquishyBuilder at edit time (Viewport mode: anchored, nothing collides), scaled like the
	-- design's toyAt (its height, or 0.8 of its width, = 24), standing on the cushions, facing the court (-X).
	local art = shared:FindFirstChild("Art")
	local module = if art then art:FindFirstChild("SquishyBuilder") else nil
	if module == nil or not module:IsA("ModuleScript") then
		table.insert(k.warnings, "Pillow Fort Park: no Shared/Art/SquishyBuilder; the sofa squishy is left out")
		return
	end
	local SquishyBuilder = (require :: (ModuleScript) -> any)(module)
	local function bounds(built: Model): (Vector3, Vector3)
		local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in built:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local cf, h = part.CFrame, part.Size / 2
				local e = Vector3.new(
					math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z,
					math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z,
					math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
				)
				low = low:Min(cf.Position - e)
				high = high:Max(cf.Position + e)
			end
		end
		return low, high
	end
	local probe = SquishyBuilder.build(SOFA_SQUISHY, "Viewport", 1)
	local low, high = bounds(probe)
	probe:Destroy()
	local size = high - low
	local scale = SQUISHY_TALL / math.max(size.Y, size.X * 0.8) -- design: sd/lobby.js:26 toyAt
	local squishy = SquishyBuilder.build(SOFA_SQUISHY, "Viewport", scale) :: Model
	squishy.Name = "GiantSquishy"
	-- Root is at the origin facing -Z: turn it to face -X and lift its lowest point onto the cushions.
	local footY = low.Y * scale
	local seat = frame:PointToWorldSpace(Vector3.new(0, SQUISHY_SEAT_Y - footY, -1))
	local place = CFrame.new(seat) * CFrame.Angles(0, HALF_PI, 0)
	for _, part in squishy:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = place * part.CFrame
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	squishy.Parent = model
end

-- The giant toy shelf (sd/arenas2.js:97-102): 4 boards, 4 sides, the back, rows of seeded books.
local function shelf(k: Kit, random: () -> number)
	local x, _ = ArenaKit.at(k, 0, -(k.design.W / 2 + 34)) -- design: sd/arenas2.js:97
	local model, frame = ArenaKit.group(k, "ToyShelf", x, 0, ArenaKit.yaw(0))
	local half = SHELF_LENGTH / 2
	ArenaKit.part(k, model, "Board1", Vector3.new(SHELF_LENGTH, 2, 12), frame * CFrame.new(0, 1, 0), "ArenaToyWood")
	for index, y in { 14, 27, 40 } do
		ArenaKit.part(
			k,
			model,
			`Board{index + 1}`,
			Vector3.new(SHELF_LENGTH, 1.6, 12),
			frame * CFrame.new(0, y, 0),
			"ArenaToyWood"
		) -- design: sd/arenas2.js:98
	end
	for index, t in { -1, -1 / 3, 1 / 3, 1 } do -- design: sd/arenas2.js:99 sides at x -75 / -25 / 25 / 75 (thirds)
		ArenaKit.part(
			k,
			model,
			`Side{index}`,
			Vector3.new(2.4, 42, 12),
			frame * CFrame.new(t * half, 21, 0),
			"ArenaToyWoodDark"
		)
	end
	ArenaKit.part(k, model, "Back", Vector3.new(SHELF_LENGTH, 42, 1.2), frame * CFrame.new(0, 21, -5.6), "ArenaToyWood") -- :99
	-- Books (sd/arenas2.js:101): width 2.2-3.8, height 7-11, depth 8, standing on each board, 12% leaning 0.18 rad.
	local count = 0
	for _, rowY in { 2, 15.6, 28.6 } do
		for book = 1, BOOKS_PER_ROW do
			local width = 2.2 + random() * 1.6
			local height = 7 + random() * 4
			local lean = if random() < 0.12 then 0.18 else 0
			local bay = (book - 0.5) / BOOKS_PER_ROW * 2 - 1 -- spread over the shelf, between the sides
			count += 1
			ArenaKit.part(
				k,
				model,
				string.format("Book%02d", count),
				Vector3.new(width, height, 8),
				frame * CFrame.new(bay * (half - 6), rowY + height / 2, 0) * CFrame.Angles(0, 0, lean),
				BOOK_COLORS[(count - 1) % #BOOK_COLORS + 1]
			)
		end
	end
end

-- The 3 string lights (sd/arenas2.js:104-106): a catenary of wire segments with bulbs hanging under it.
local function stringLights(k: Kit)
	local _, endZ = ArenaKit.at(k, -(k.design.L / 2 + 26), 0) -- design: sd/arenas2.js:105 x0 = -L / 2 - 26
	for index, designZ in { -34, 0, 34 } do
		local x, _ = ArenaKit.at(k, 0, designZ)
		local model = ArenaKit.model(k.decor, `StringLight{index}`, CFrame.new(x, 0, 0))
		local function point(t: number): Vector3
			return Vector3.new(x, 44 - 12 * math.sin(math.pi * t), endZ - 2 * endZ * t) -- design: sd/arenas2.js:105
		end
		for segment = 1, LIGHT_SEGMENTS do
			local a, b = point((segment - 1) / LIGHT_SEGMENTS), point(segment / LIGHT_SEGMENTS)
			local along = b - a
			ArenaKit.part(
				k,
				model,
				`Wire{segment}`,
				Vector3.new(0.15, 0.15, along.Magnitude),
				CFrame.lookAt((a + b) / 2, b),
				"ArenaInk"
			) -- design: sd/arenas2.js:105 B(L2, 0.15, 0.15)
			if segment < LIGHT_SEGMENTS then
				ArenaKit.ball(k, model, `Bulb{segment}`, BULB, b - Vector3.new(0, 0.6, 0), "ArenaLampGlow")
			end
		end
	end
end

-- The 5 hanging stars (sd/arenas2.js:107-108): a star glyph on both faces of a clear plate, on a string up to y 40.
local function hangingStars(k: Kit, random: () -> number)
	for index, star in STARS do
		local x, z = ArenaKit.at(k, star[1], star[2])
		local y = star[3]
		local model, frame = ArenaKit.group(k, `HangingStar{index}`, x, z, random() * 3)
		local plate = ArenaKit.part(
			k,
			model,
			"Star",
			Vector3.new(STAR_SIZE, STAR_SIZE, 0.2),
			frame * CFrame.new(0, y, 0),
			"ArenaButter"
		)
		plate.Transparency = 1 -- only the glyphs show
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			ArenaKit.glyph(k, plate, face, ArenaKit.STAR, "ArenaButter", "ArenaInk", STAR_SIZE)
		end
		ArenaKit.part(
			k,
			model,
			"String",
			Vector3.new(0.12, 37 - y, 0.12),
			frame * CFrame.new(0, (y + 43) / 2, 0),
			"ArenaInk"
		) -- design: sd/arenas2.js:108
	end
end

local function art(k: Kit, shared: Instance)
	ArenaKit.floorHalves(k, "ArenaQuiltStrawberry", "ArenaQuiltMint", Enum.Material.Fabric)
	stitches(k)
	ArenaKit.court(k, COURT)
	buildRails(k)
	plushPatches(k)
	fort(k, "PillowFortB", FORT_Z, 0, "ArenaPillowMintPrint", "ArenaTeamMint") -- design: sd/arenas2.js:68 (team A, ry 0)
	fort(k, "PillowFortA", -FORT_Z, math.pi, "ArenaPillowStrawberryPrint", "ArenaTeamStrawberry")
	sofa(k, shared)
	local random = ArenaKit.rng(SEED)
	shelf(k, random)
	stringLights(k)
	hangingStars(k, random)
end

-- Public

-- Builds the new template tree, unparented and marked (Generated contract). Never yields, never changes the place.
function PillowFortPark.build(ctx: ArenaKit.BuildContext): ArenaKit.BuildResult
	return ArenaKit.build(ctx, {
		arenaId = ARENA_ID,
		generatorId = PillowFortPark.GENERATOR_ID,
		version = PillowFortPark.VERSION,
		rootName = PillowFortPark.ROOT_NAME,
		apron = "ArenaPlayroomRug", -- design: sd/arenas2.js:51 floor_base rug
		padA = "ArenaQuiltStrawberry",
		padB = "ArenaQuiltMint",
		jellyTransparency = 1 - 0.12, -- design: sd/arenas2.js:29 (opacity 0.12)
	}, function(k: Kit)
		art(k, ctx.Shared)
	end)
end

return PillowFortPark
