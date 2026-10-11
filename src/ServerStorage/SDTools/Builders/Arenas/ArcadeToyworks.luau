--!strict
-- ArcadeToyworks: builds the arena template "Arena_ArcadeToyworks", the "Toy workshop arcade - studded brick walls,
-- cabinets, claw machine" (design sd/arenas2.js:177-259, facts sd/main.js:453-456; phase 4 spec 2026-10-11 §2.5,
-- §4.5, §4.6). Server only, Edit mode only (ServerStorage.SDTools); Main's target "arena_arcade_toyworks" runs
-- build(ctx) and swaps the tree into ServerStorage.SD_Templates. ArenaKit makes the gameplay frame (Candy Court's) and
-- the cover (World/Arenas); this module adds the art:
--   Floor     the mint and strawberry tile halves, out to the walls
--   Markings  the 8-stud tile checker, the design's white lines, mint / strawberry end and team lines, centre ring and
--             ring spawn marks (ArenaKit.court)
--   Rails     the white bumper rails with their team stripes, in the gutter
--   Cover     the cabinets' screens: the design's pixel invader and "PLAY" (a SurfaceGui)
--   Decor     the carpet apron, a Claw Machine behind each end (D1, no prizes: D5), the TOYWORKS marquees, the toy
--             conveyor, the prize counter and 2 gumball machines (D5: the design has 4).
-- Every design number carries its sd/arenas2.js line; out-of-bounds items keep their distance beyond the court edge
-- (spec §4.6, ArenaKit.at) and stay inside the 190-stud apron. Plain colours only (D6: marquees, bulbs and screens do
-- not glow); words come from Strings (world.arenaPlay / arenaToyworks / arenaPrizes). The carpet confetti and the
-- conveyor rollers are left out for the part budget (D5: this is the tightest arena).

local ArenaKit = require(script.Parent.ArenaKit)

-- Types

type Kit = ArenaKit.Kit

-- Constants

local ARENA_ID = "arcade_toyworks"
local HALF_PI = math.pi / 2
local ATTR_TEXT_KEY = "SD_TextKey" -- as Kit/Signs: WorldBinder re-applies static labels from Strings
local TAG_SIGN = "SD_Sign"

local COURT: ArenaKit.CourtStyle = {
	line = "ArenaTrimWhite", -- design: sd/arenas2.js:185 (court(..., M.white, ...))
	sideWidth = 1, -- design: sd/arenas2.js:21
	endWidth = 1,
	endA = "ArenaTeamStrawberry", -- design: sd/arenas2.js:21
	endB = "ArenaTeamMint",
	centreWidth = 2.2, -- design: sd/arenas2.js:22
	edgeWidth = 0.8,
	zoneWidth = 0.8, -- design: sd/arenas2.js:26
	teamA = "ArenaTeamStrawberry",
	teamB = "ArenaTeamMint",
	halfA = "ArenaTileStrawberryA", -- design: sd/arenas2.js:182 tile_berry_a
	halfB = "ArenaTileMintA", -- design: sd/arenas2.js:182 tile_mint_a
	circle = "ring", -- design: sd/arenas2.js:23
	padMarker = "ring", -- design: sd/arenas2.js:27
}

-- Tile checker (sd/arenas2.js:186): 8 x 8 squares, every other one in the light tile colour of its half; here aligned
-- on the centre line so no square straddles the halves.
local TILE = 8 -- design: sd/arenas2.js:186
local CHECKER_TOP = 0.02 -- under the court lines (0.04)

-- Bumper rails (sd/arenas2.js:187-188): rb(L / 2 - 1, 2.4, 2.6) white with a 0.7 team stripe rb(..., 0.7, 2.7) at y 1.5.
-- Spec §4.5: 1.6 deep in the 2-stud gutter; the stripe keeps the design's extra depth (2.7 / 2.6), inside the gutter.
local BUMPER_DEPTH = 1.6 -- spec §4.5 (design 2.6)
local BUMPER_HEIGHT = 2.4 -- design: sd/arenas2.js:187
local STRIPE_DEPTH = BUMPER_DEPTH * 2.7 / 2.6 -- design: sd/arenas2.js:187
local STRIPE_HEIGHT = 0.7 -- design: sd/arenas2.js:187
local STRIPE_Y = 1.5 -- design: sd/arenas2.js:187

-- The cabinet screen (sd/arenas2.js:196): a 256 x 192 canvas, the 8 x 6 invader in butter 16-px cells (14 drawn) from
-- (64, 30), "PLAY" in mint under it.
local INVADER = { "..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", "XX....XX", ".XXXXXX." } -- design: :196
local CANVAS = Vector2.new(256, 192)
local CELL, CELL_DRAWN, INVADER_ORIGIN = 16, 14, Vector2.new(64, 30)
local PLAY_TOP, PLAY_HEIGHT = 142, 40 -- design: sd/arenas2.js:196 (34 px text on the baseline H - 20)
local SCREEN_PIXELS_PER_STUD = 50

-- Claw Machine (sd/arenas2.js:211-222), a backdrop behind each end (D1), facing the court; spec §4.6: (0, +-63.5).
-- 4 of its 24 bulbs (D5); no prizes (D5).
local CLAW_Z = 63.5

-- TOYWORKS marquees (sd/arenas2.js:248-254) 22 beyond each end, facing the court; 4 bulbs a row (spec §4.6: 8; the
-- design has 25).
local MARQUEE_BEYOND = 22 -- design: sd/arenas2.js:249 (L / 2 + 22)
local MARQUEE_BULBS = { -18, -6, 6, 18 }

-- Toy conveyor (sd/arenas2.js:232-236) 18 beyond the +z long side: 180 long here (L + 30 cut to the apron), legs every
-- 48 (design 24), 7 toy boxes (design every 13).
local CONVEYOR_LENGTH = 180
local CONVEYOR_LEGS = { -72, -24, 24, 72 }
local TOY_BOXES = 7
local BOX_COLORS = { "ArenaTeamStrawberry", "ArenaSky", "ArenaButter" } -- design: sd/arenas2.js:236

-- Prize counter (sd/arenas2.js:237-241) 20 beyond the -z long side; 6 plush blobs a row (design about 23).
local BLOBS_PER_ROW = 6
local BLOB_COLORS = { "ArenaTeamStrawberry", "ArenaTeamMint", "ArenaButter", "ArenaViolet" } -- design: :240

-- Gumball machines (sd/arenas2.js:242-247): 2 of the design's 4 (D5), one at each corner diagonal.
local GUMBALL_SPOTS = { { -100, -72 }, { 100, 66 } } -- design: sd/arenas2.js:242 (x, z)
local GUMBALLS = 6 -- design: sd/arenas2.js:245 has 30
local GUMBALL_COLORS = { "ArenaTeamMint", "ArenaButter", "ArenaSky" } -- design: sd/arenas2.js:245
local SEED = 51 -- design: sd/arenas2.js:180 rng(51)

-- Module table

local ArcadeToyworks = {}
ArcadeToyworks.GENERATOR_ID = "arena_arcade_toyworks"
ArcadeToyworks.VERSION = 1
ArcadeToyworks.ROOT_NAME = "Arena_ArcadeToyworks"
ArcadeToyworks.ARENA_ID = ARENA_ID

-- Private

local function checker(k: Kit)
	local halfX, halfZ = k.layout.halfX, k.layout.halfZ
	local columns = math.round(2 * halfX / TILE)
	local rows = math.ceil(halfZ / TILE)
	local count = 0
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		local token = if side == "A" then "ArenaTileStrawberryB" else "ArenaTileMintB"
		for row = 0, rows - 1 do
			local near = row * TILE
			local depth = math.min(TILE, halfZ - near)
			for column = 0, columns - 1 do
				-- Light when (column + row) is odd on Side B; Side A's first row is the other parity so the checker
				-- runs on across the centre line.
				local parity = (column + row + (if side == "A" then 1 else 0)) % 2
				if parity == 1 then
					count += 1
					ArenaKit.part(
						k,
						k.markings,
						string.format("Tile_%02d", count),
						Vector3.new(TILE, CHECKER_TOP, depth),
						CFrame.new(-halfX + (column + 0.5) * TILE, CHECKER_TOP / 2, sign * (near + depth / 2)),
						token,
						"marking"
					)
				end
			end
		end
	end
end

local function buildRails(k: Kit)
	local halfX, halfZ = k.layout.halfX, k.layout.halfZ
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		local team = if side == "A" then "ArenaTeamStrawberry" else "ArenaTeamMint"
		for index, sx in { -1, 1 } do
			ArenaKit.part(
				k,
				k.rails,
				`{side}_Bumper{index}`,
				Vector3.new(BUMPER_DEPTH, BUMPER_HEIGHT, halfZ),
				CFrame.new(sx * (halfX + BUMPER_DEPTH / 2), BUMPER_HEIGHT / 2, sign * halfZ / 2),
				"ArenaTrimWhite",
				"solid"
			) -- design: sd/arenas2.js:187
			ArenaKit.part(
				k,
				k.rails,
				`{side}_Stripe{index}`,
				Vector3.new(STRIPE_DEPTH, STRIPE_HEIGHT, halfZ - 0.4),
				CFrame.new(sx * (halfX + STRIPE_DEPTH / 2), STRIPE_Y, sign * halfZ / 2),
				team,
				"solid"
			) -- design: sd/arenas2.js:187 (0.4 shorter)
		end
		local width = 2 * (halfX + BUMPER_DEPTH) -- closes the corners
		ArenaKit.part(
			k,
			k.rails,
			`{side}_BumperEnd`,
			Vector3.new(width, BUMPER_HEIGHT, BUMPER_DEPTH),
			CFrame.new(0, BUMPER_HEIGHT / 2, sign * (halfZ + BUMPER_DEPTH / 2)),
			"ArenaTrimWhite",
			"solid"
		) -- design: sd/arenas2.js:188
		ArenaKit.part(
			k,
			k.rails,
			`{side}_StripeEnd`,
			Vector3.new(width - 0.4, STRIPE_HEIGHT, STRIPE_DEPTH),
			CFrame.new(0, STRIPE_Y, sign * (halfZ + STRIPE_DEPTH / 2)),
			team,
			"solid"
		) -- design: sd/arenas2.js:188
	end
end

-- A static label baked from Strings and tagged for WorldBinder (as Kit/Signs' static lines).
local function label(k: Kit, parent: Instance, textKey: string, token: string): TextLabel
	local text = k.strings.resolve(textKey)
	if type(text) ~= "string" then
		error(`Strings has no text for {textKey}`, 0)
	end
	local made = Instance.new("TextLabel")
	made.Name = "Text"
	made.BackgroundTransparency = 1
	made.BorderSizePixel = 0
	made.Font = Enum.Font.FredokaOne
	made.TextColor3 = ArenaKit.color(k, token)
	made.TextScaled = true
	made.Text = text
	made:AddTag(TAG_SIGN)
	made:SetAttribute(ATTR_TEXT_KEY, textKey)
	made.Parent = parent
	return made
end

-- The cabinet screens (sd/arenas2.js:196, 202): the invader and "PLAY" on each Screen's front (its +Z, Back face).
local function screens(k: Kit)
	for _, piece in k.def.cover do
		local model = k.cover:FindFirstChild("Cover_" .. piece.name)
		local screen = if model then model:FindFirstChild("Screen") else nil
		if screen == nil or not screen:IsA("BasePart") then
			continue
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "ScreenGui"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = SCREEN_PIXELS_PER_STUD
		gui.LightInfluence = 0.15 -- as Kit/Signs
		gui.ClipsDescendants = true
		for y, row in INVADER do
			for x = 1, #row do
				if string.sub(row, x, x) == "X" then
					local cell = Instance.new("Frame")
					cell.Name = `Pixel{x}_{y}`
					cell.BorderSizePixel = 0
					cell.BackgroundColor3 = ArenaKit.color(k, "ArenaButter")
					cell.Position = UDim2.fromScale(
						(INVADER_ORIGIN.X + (x - 1) * CELL) / CANVAS.X,
						(INVADER_ORIGIN.Y + (y - 1) * CELL) / CANVAS.Y
					)
					cell.Size = UDim2.fromScale(CELL_DRAWN / CANVAS.X, CELL_DRAWN / CANVAS.Y)
					cell.Parent = gui
				end
			end
		end
		local play = label(k, gui, "world.arenaPlay", "ArenaTeamMint")
		play.Position = UDim2.fromScale(0, PLAY_TOP / CANVAS.Y)
		play.Size = UDim2.fromScale(1, PLAY_HEIGHT / CANVAS.Y)
		gui.Parent = screen
	end
end

-- The Claw Machine (sd/arenas2.js:211-222) at (0, z), its front (chute, local +z) toward the court.
local function claw(k: Kit, name: string, z: number, ry: number, team: string)
	local model, frame = ArenaKit.group(k, name, 0, z, ArenaKit.yaw(ry))
	local function piece(part: string, size: Vector3, x: number, y: number, pz: number, token: string): Part
		return ArenaKit.part(k, model, part, size, frame * CFrame.new(x, y, pz), token)
	end
	piece("Base", Vector3.new(10, 6, 10), 0, 3, 0, team) -- design: sd/arenas2.js:213
	piece("PrizeChute", Vector3.new(3.4, 2.6, 0.6), -2.6, 2.4, 5.05, "ArenaPlum") -- design: sd/arenas2.js:213
	local glass = piece("Glass", Vector3.new(9.2, 9, 9.2), 0, 10.5, 0, "ArenaGlass") -- design: sd/arenas2.js:214
	glass.Material = Enum.Material.Glass
	glass.Transparency = 1 - 0.26 -- design: sd/lobby.js:77 glass opacity 0.26
	glass.CastShadow = false
	for index, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		ArenaKit.disc(
			k,
			model,
			`Post{index}`,
			0.9,
			9,
			frame:PointToWorldSpace(Vector3.new(corner[1] * 4.6, 10.5, corner[2] * 4.6)),
			"ArenaTrimWhite"
		) -- design: sd/arenas2.js:215
	end
	piece("Top", Vector3.new(10.8, 3.4, 10.8), 0, 16.7, 0, "ArenaPlum") -- design: sd/arenas2.js:216
	local band = piece("MarqueeBand", Vector3.new(11, 1.2, 11), 0, 16.7, 0, "ArenaGlowCream") -- design: :216
	for index, spot in { { 0, 5.5 }, { 5.5, 0 }, { 0, -5.5 }, { -5.5, 0 } } do
		ArenaKit.ball(
			k,
			model,
			`Bulb{index}`,
			2 * 0.42,
			frame:PointToWorldSpace(Vector3.new(spot[1], 18.6, spot[2])),
			"ArenaLampGlow"
		) -- design: sd/arenas2.js:217 (one bulb mid-side of the 24)
	end
	ArenaKit.disc(k, model, "Cable", 0.36, 3.4, frame:PointToWorldSpace(Vector3.new(1, 13.3, 0.5)), "ArenaTrimWhite") -- :218
	ArenaKit.ball(k, model, "Hub", 1.4, frame:PointToWorldSpace(Vector3.new(1, 11.4, 0.5)), "ArenaGold") -- :218
	for index = 0, 2 do
		local a = index / 3 * 2 * math.pi
		ArenaKit.part(
			k,
			model,
			`Prong{index + 1}`,
			Vector3.new(0.3, 2.2, 0.3),
			frame
				* CFrame.new(1 + math.cos(a) * 0.7, 10.4, 0.5 + math.sin(a) * 0.7)
				* CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5),
			"ArenaGold"
		) -- design: sd/arenas2.js:219
	end
	-- The 2 TOYWORKS plates (ink, no background) on the band's front and back (sd/arenas2.js:220).
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		ArenaKit.sign(k, band, face, "world.arenaToyworks", "ArenaInk", "ArenaGlowCream", 1)
	end
end

-- The TOYWORKS marquee (sd/arenas2.js:248-254) behind the end `sign` (+1 = +Z), facing the court.
local function marquee(k: Kit, sign: number)
	local sx = -sign -- the design's end sign: its mint end (x < 0) is Side B
	local _, z = ArenaKit.at(k, sx * (k.design.L / 2 + MARQUEE_BEYOND), 0)
	local model, frame = ArenaKit.group(k, `Marquee{if sign > 0 then "B" else "A"}`, 0, z, ArenaKit.yaw(-sx * HALF_PI))
	for index, side in { -1, 1 } do
		ArenaKit.part(k, model, `Post{index}`, Vector3.new(4, 26, 4), frame * CFrame.new(side * 22, 13, 0), "ArenaPlum") -- :250
	end
	local board = ArenaKit.part(k, model, "Board", Vector3.new(50, 9, 3.4), frame * CFrame.new(0, 26, 0), "ArenaPlum") -- :251
	ArenaKit.sign(k, board, Enum.NormalId.Back, "world.arenaToyworks", "ArenaButter", "ArenaInk", 5) -- :251 (34 x 5.6)
	for row, y in { 21.8, 30.2 } do
		for index, x in MARQUEE_BULBS do
			ArenaKit.ball(
				k,
				model,
				`Bulb{row}_{index}`,
				1,
				frame:PointToWorldSpace(Vector3.new(x, y, 1.6)),
				"ArenaLampGlow"
			) -- design: sd/arenas2.js:252 SPH(0.5)
		end
	end
	for index, side in { -1, 1 } do
		ArenaKit.part(
			k,
			model,
			`TeamPanel{index}`,
			Vector3.new(7, 4, 0.3),
			frame * CFrame.new(side * 18, 17, 2.1),
			if side < 0 then "ArenaTeamMint" else "ArenaTeamStrawberry"
		) -- design: sd/arenas2.js:253
	end
end

-- The toy conveyor (sd/arenas2.js:232-236) off the +z long side, along the court.
local function conveyor(k: Kit)
	local x, _ = ArenaKit.at(k, 0, k.design.W / 2 + 18) -- design: sd/arenas2.js:232
	local model, frame = ArenaKit.group(k, "ToyConveyor", x, 0, ArenaKit.yaw(0))
	ArenaKit.part(
		k,
		model,
		"Belt",
		Vector3.new(CONVEYOR_LENGTH, 1.2, 8),
		frame * CFrame.new(0, 6, 0),
		"ArenaConveyorBelt"
	)
	for index, side in { -1, 1 } do
		ArenaKit.part(
			k,
			model,
			`Frame{index}`,
			Vector3.new(CONVEYOR_LENGTH + 2, 1.8, 1),
			frame * CFrame.new(0, 6, side * 4.4),
			"ArenaTrimWhite"
		) -- design: sd/arenas2.js:233
		for leg, lx in CONVEYOR_LEGS do
			ArenaKit.part(
				k,
				model,
				`Leg{index}_{leg}`,
				Vector3.new(1.4, 5, 1.4),
				frame * CFrame.new(lx, 2.5, side * 3.6),
				"ArenaPlum"
			) -- design: sd/arenas2.js:234
		end
	end
	for index = 0, TOY_BOXES - 1 do
		local bx = -CONVEYOR_LENGTH / 2 + 12 + index * (CONVEYOR_LENGTH - 24) / (TOY_BOXES - 1)
		ArenaKit.part(
			k,
			model,
			`ToyBox{index + 1}`,
			Vector3.new(5 + index % 2, 4 + index % 3, 5),
			frame * CFrame.new(bx, 8.6 + (index % 3) * 0.5, 0) * CFrame.Angles(0, (index % 4) * 0.25, 0),
			BOX_COLORS[index % 3 + 1]
		) -- design: sd/arenas2.js:235
	end
end

-- The prize counter (sd/arenas2.js:237-241) off the -z long side, its prize wall away from the court.
local function prizeCounter(k: Kit)
	local x, _ = ArenaKit.at(k, 0, -(k.design.W / 2 + 20)) -- design: sd/arenas2.js:237
	local model, frame = ArenaKit.group(k, "PrizeCounter", x, 0, ArenaKit.yaw(0))
	local function piece(part: string, size: Vector3, px: number, y: number, z: number, token: string): Part
		return ArenaKit.part(k, model, part, size, frame * CFrame.new(px, y, z), token)
	end
	piece("Body", Vector3.new(90, 6, 7), 0, 3, 0, "ArenaLilac") -- design: sd/arenas2.js:238
	piece("Top", Vector3.new(92, 0.8, 8), 0, 6.4, 0, "ArenaTrimWhite") -- design: sd/arenas2.js:238
	local glass = piece("Glass", Vector3.new(88, 4, 6), 0, 8.8, 0, "ArenaGlass") -- design: sd/arenas2.js:238
	glass.Material = Enum.Material.Glass
	glass.Transparency = 1 - 0.26 -- design: sd/lobby.js:77
	glass.CastShadow = false
	piece("PrizeWall", Vector3.new(100, 24, 3), 0, 12, -8, "ArenaToyWood") -- design: sd/arenas2.js:239
	for index, y in { 8, 15, 22 } do
		piece(`Shelf{index}`, Vector3.new(98, 1, 4), 0, y, -6.2, "ArenaTrimWhite") -- design: sd/arenas2.js:239
	end
	local count = 0
	for _, y in { 8.5, 15.5 } do
		for blob = 0, BLOBS_PER_ROW - 1 do
			count += 1
			ArenaKit.ellipsoid(
				k,
				model,
				string.format("Plush%02d", count),
				Vector3.new(2.8, 3, 2.6),
				frame * CFrame.new(-46 + blob * 92 / (BLOBS_PER_ROW - 1), y + 1.6, -6.2),
				BLOB_COLORS[(count - 1) % #BLOB_COLORS + 1]
			) -- design: sd/arenas2.js:240 pill(2.8, 3, 2.6)
		end
	end
	-- The "PRIZES" plate (sd/arenas2.js:241): ink text on a butter plate, 14 x 3.6, on the prize wall.
	local plate = piece("PrizesPlate", Vector3.new(14, 3.6, 0.2), 0, 26.2, -6.4, "ArenaButter")
	ArenaKit.sign(k, plate, Enum.NormalId.Back, "world.arenaPrizes", "ArenaInk", "ArenaButter", 2.4)
end

-- A gumball machine (sd/arenas2.js:242-247) at a design spot, its coin slot toward the court.
local function gumball(k: Kit, index: number, spot: { number }, random: () -> number)
	local x, z = ArenaKit.at(k, spot[1], spot[2])
	local model, frame = ArenaKit.group(k, `GumballMachine{index}`, x, z, math.atan2(-x, -z))
	ArenaKit.disc(
		k,
		model,
		"Stand",
		2.2 + 3.2,
		7,
		frame:PointToWorldSpace(Vector3.new(0, 3.5, 0)),
		"ArenaStrawberryRed"
	) -- :244
	ArenaKit.part(k, model, "CoinBox", Vector3.new(5, 3, 5), frame * CFrame.new(0, 8.4, 0), "ArenaStrawberryRed") -- :244
	ArenaKit.part(k, model, "CoinSlot", Vector3.new(1, 0.6, 0.2), frame * CFrame.new(0, 8.8, 2.55), "ArenaGold") -- :244
	for ball = 1, GUMBALLS do
		local a, r = random() * 2 * math.pi, random() * 3
		ArenaKit.ball(
			k,
			model,
			`Gumball{ball}`,
			1.5,
			frame:PointToWorldSpace(Vector3.new(math.cos(a) * r, 11.2 + random() * 3.6, math.sin(a) * r)),
			GUMBALL_COLORS[(ball - 1) % #GUMBALL_COLORS + 1]
		) -- design: sd/arenas2.js:245 SPH(0.75)
	end
	local globe = ArenaKit.ball(k, model, "Globe", 8.8, frame:PointToWorldSpace(Vector3.new(0, 13.6, 0)), "ArenaGlass") -- :246
	globe.Material = Enum.Material.Glass
	globe.Transparency = 1 - 0.26 -- design: sd/lobby.js:77
	globe.CastShadow = false
	ArenaKit.disc(
		k,
		model,
		"Cap",
		1.8 + 2.4,
		1.2,
		frame:PointToWorldSpace(Vector3.new(0, 18.2, 0)),
		"ArenaStrawberryRed"
	) -- :246
end

local function art(k: Kit)
	ArenaKit.floorHalves(k, "ArenaTileStrawberryA", "ArenaTileMintA")
	checker(k)
	ArenaKit.court(k, COURT)
	buildRails(k)
	screens(k)
	claw(k, "ClawMachineB", CLAW_Z, HALF_PI, "ArenaTeamMint") -- design: sd/arenas2.js:212 (team A, ry pi / 2)
	claw(k, "ClawMachineA", -CLAW_Z, -HALF_PI, "ArenaTeamStrawberry")
	marquee(k, 1)
	marquee(k, -1)
	conveyor(k)
	prizeCounter(k)
	local random = ArenaKit.rng(SEED)
	for index, spot in GUMBALL_SPOTS do
		gumball(k, index, spot, random)
	end
end

-- Public

-- Builds the new template tree, unparented and marked (Generated contract). Never yields, never changes the place.
function ArcadeToyworks.build(ctx: ArenaKit.BuildContext): ArenaKit.BuildResult
	return ArenaKit.build(ctx, {
		arenaId = ARENA_ID,
		generatorId = ArcadeToyworks.GENERATOR_ID,
		version = ArcadeToyworks.VERSION,
		rootName = ArcadeToyworks.ROOT_NAME,
		apron = "ArenaCarpet", -- design: sd/arenas2.js:183 floor_base carpet
		padA = "ArenaTileStrawberryA",
		padB = "ArenaTileMintA",
		jellyTransparency = 1 - 0.12, -- design: sd/arenas2.js:29 (opacity 0.12)
	}, art)
end

return ArcadeToyworks
