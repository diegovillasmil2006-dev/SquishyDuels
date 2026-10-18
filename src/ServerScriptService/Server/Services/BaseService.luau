--!strict
-- BaseService (server only). Lobby bases spec 2026-10-11 §2, §4, §6, §8; build plan Phases 3 and 4.
-- The island's 10 plots (WorldLayout.Bases), one per player in the server:
-- * playerAdded: the lowest free plot. It goes to the Player attribute SD_Plot (1..10; clients read it) and the
--   plot's name sign shows the player's DisplayName (the owner view below). The player spawns on the plot (its
--   SpawnLocation, WorldLayout.Tags.BaseSpawn with the Plot attribute) once the world has one (Squish Island, Phase 4);
--   without it CharacterService's lobby spawn stays. With no plot free (a player who left is freed on their leave
--   hook, so only briefly, or in a Studio test with more players than plots), it tries again every RETRY_SECONDS for
--   RETRY_FOR_SECONDS while the player waits in the hub; a plot found later is used from their next respawn.
-- * Batch 3 (friends, review #6): a player who joined from a friend's invite (GetJoinData().ReferredByPlayerId) or
--   followed a friend in (Player.FollowUserId) while that friend has a plot here gets the free plot nearest to the
--   friend's on the ring (min(|i - p|, 10 - |i - p|); a tie takes the lower number) instead of the lowest one.
-- * playerRemoving: the plot is free again ("Open plot", grey, no pen). Rejoining gives the lowest free plot again
--   (maybe another one); the pen lives in the profile, so it comes back wherever the player lands.
-- * The owner view (Phase 4, spec §4, §8): render(plot) shows on the plot's generated Model (Tags.Base with that Plot)
--   who owns it. The name sign's live "Owner" label reads the owner's DisplayName, or Strings base.openPlot; every part
--   with SD_BaseTint ("full" / "light") takes the plot's colour (WorldLayout.Bases.colors) while it has an owner and the
--   open grey (Bases.openColors) otherwise.
-- * Pens3 phase 1 (the pen replaced the capsules and the statue): a "Pen" Folder, replaced on every render, holds the
--   owner's pen (drawPen; lobby design v6, `LK:n` = lobby-kit.js line n, `K:n` = kit.json line n), built in the plot's
--   frame from WorldLayout.Bases.pen and its steps[spots] (the tier):
--   - Wb (owner 2026-10-17, "whole base, like Ride a Pet"): the pen is the whole base, inside the plot's own white
--     fence (LobbyBuilder), so no pen fence, rails or colliders are drawn; a bought spot adds a squishy, never fence.
--     Every piece below stands on the plot's fenced floor (Bases.pen.walk), clear of what LobbyBuilder stands there
--     (Bases.props) and inside a walk block (Bases.pen.blocks: no squishy walks through it).
--   - Sign: the Model "Sign" (LK:96-101 pen_upgrade_sign: Post, the state Trim, the price Face with its SurfaceGui
--     Title / Row (Icon, Price) / Line) at Bases.pen.signs.pen, attributes SD_PenSign = plot and SD_Price = the next
--     spot's price (none at maxSpots); the Face's ProximityPrompt (PenPrompt) is a hold of Config.Economy.Pen
--     .signHoldSeconds, off at MAX. Everyone sees this face: the title, the coin icon and the price (MAX with the star
--     picture and the gold trim at maxSpots; the star is a picture, not LK's star shape: placeholder); the owner's
--     client recolours its own sign locally and writes its Line (Controllers/PenController).
--   - The base Model's attributes for every client's walking squishies (PenController): SD_PenSpots, SD_Pen
--     (PenMath.encode of the placed items), SD_PenRate (PenMath.rate) and SD_PenTier; none on an open plot.
-- * Pens3 phase 10 (the pen look, lobby design v6; `L:n` = layout.json line n, `P3D:n` = "Squishy Lobby 3D.html"):
--   - Gate: the Model "Gate" (LK:87-96 pen_gate, K:700) at Bases.pen.gate (wb: in the front-right corner, beside the
--     Donut Arch, so the path sees both name signs): 2 GatePosts (they block, K: "block") with their balls in the
--     tier's post colour (L:187 GatePost tints), the SignFrame in the plot's colour (BaseTint), the OwnerSign
--     (P3D:245-251: the headshot in a PenOwnerDisc<n> disc, the display name, "BASE n"), the NumberBadge disc reading
--     the base number (P3D:268) and the VisitorBoard (a heart and "0 visitors" until phase 18, P3D:277); its GUIs as
--     K:7872-7873 says (PixelsPerStud 25, hidden beyond 150 studs), on P3D's planes 0.1 stud inside each face. The
--     headshot (K:4271): deps.headshotOf(userId) (Players:GetUserThumbnailAsync on its own thread, pcall), asked once
--     per user and cached for the server's life, painted on that owner's gate when it comes (after a failure it is
--     asked again on the next draw).
--   - Tier decor (PenMath.decorOf; K:4170-4189; wb: round the whole base): tier 2 adds the gate's 7 Neon bulbs and the
--     2 "Lamp"s (LK:240-244) at Bases.pen.lamps; tier 3 also the gate's "Bow" Model (LK:58 bowGeo(0.9) at y 13.5, its
--     pivot A12's) and the 2 "Tree"s (LK:235-239) at Bases.pen.trees. A shape Roblox parts cannot make is a stand-in at
--     the design's sizes (placeholders): a bow loop (a torus) is a ring of 6 rods, a trunk stripe (a torus round the
--     trunk) a disc, the canopy (a lathe) a cylinder under an ellipsoid, the lamp's swirl (2 tori on the candy's front)
--     2 rings drawn on the candy's SurfaceGui. The lamp pole and the trunk block (K: "block"); the rest is decor.
--   - The base Model's SD_PenOwner: the owner's UserId (none for a player without one), for the clients' gate motion
--     (Controllers/PenLookController).
-- * Pens3 phase 11 (the shelf rows + the TOP spot; `CHK:n` = check/CHECK.md line n):
--   - Shelf: the Model "Shelf" at Bases.pen.shelf.at on every drawn pen (LK:182-189 base_shelf, K:798-842; at the
--     plot's back): the ShelfBack (27.4 × 15.6 × 0.6) in the plot's colour
--     (BaseTint), the 11 ShelfFrame boards in Frosting, the "ShelfBow" Model (bowGeo(1.1) at (0, 15.6, -0.5), the
--     gate bow's stand-in rings) and one invisible ShelfCollider over the whole 27.4 × 15.6 × 6 (K "collision":
--     "block": nobody climbs into a cubby; every visible part is decor). Over every cubby that is not open
--     (PenMath.isOpen of its slot, Bases.pen.shelf.cubbies k = slot 12 + k) a "Lock": LK:191's lock_glass (5.8 × 6.3 ×
--     0.15, K:98 Glass at Transparency 0.5) where L:247 puts it, with the img.icon.lock picture on its front (v6's
--     padlock is broken, CHK:57), attribute SD_ShelfSlot. The "Top" Model (placeholder: a pedestal, PLAN phase 11): a
--     Frosting column and a Gold top on the shelf's top behind the bow, the TOP spot's squishy standing on it
--     (Bases.pen.shelf.top); until the TOP spot is bought, a "TopLock" BillboardGui with the lock picture over it.
--   - SHELF SPOTS sign: the Model "ShelfSign" at Bases.pen.signs.shelf, the PEN SPACE sign's pieces and states (K:4240:
--     PEN SPACE left, SHELF SPOTS right), titled pen.shelfSign.title, attributes SD_ShelfSign = plot and SD_Price =
--     PenMath.shelfPrice (the next row's, then the TOP spot's; none once all is open: MAX), its "ShelfPrompt" a hold
--     like PenPrompt, off at MAX. The owner's client paints and buys it like the pen's (Controllers/PenController).
--   - The base Model's SD_Pen holds the pen's walkers only (PenMath.inPen), SD_Shelf the shelf's and the TOP spot's
--     squishies (PenMath.encodeShelf of PenMath.onShelf; the clients stand them in their cubbies), SD_ShelfRows and
--     SD_ShelfTop the open rows and the TOP spot; SD_PenRate is every placed squishy's (PenMath.rate).
--   A plot renders when it is handed out or freed, when its owner's profile loads (the data port's Loaded) and on
--   refresh(player) after a pen change (PenService: a spot bought, a squishy granted). Until the profile is ready a plot
--   shows its owner's name and colour only; without the generated plot or with a broken pen nothing is drawn and
--   nothing fails.
-- No remote ever names a plot: PenBuySpot always buys the caller's own next spot.
-- Dependencies are injectable (useDeps) so unit tests run without the world or the task scheduler; a player is only a
-- table key (an Instance also gets the attribute; a Player also gets the spawn). playerAdded / playerRemoving never
-- yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Deps = {
	delay: (seconds: number, fn: () -> ()) -> (), -- task.delay
	spawnOf: (plot: number) -> SpawnLocation?, -- the plot's SpawnLocation in the generated world, or nil
	plotModel: (plot: number) -> Instance?, -- the plot's generated Model, or nil
	penOf: (player: any) -> any, -- the pen (Types.PenState) of the player's READY profile, or nil
	displayNameOf: (player: any) -> string,
	friendOf: (player: any) -> any?, -- Batch 3: the friend in this server who invited the player (or was followed)
	-- Pens3 phase 10: asks for the user's headshot and calls done with it later (nil when it could not be had).
	headshotOf: (userId: number, done: (image: string?) -> ()) -> (),
}

-- Constants

local PLOT_COUNT = #WorldLayout.Bases.frames
local ATTR_PLOT = "SD_Plot"
local TAG_SPAWN = WorldLayout.Tags.BaseSpawn
local ATTR_SPAWN_PLOT = WorldLayout.Attributes.Plot
local RETRY_FOR_SECONDS = 5 -- lobby spec §6: "it tries again for up to 5 s"
local RETRY_SECONDS = 0.5 -- reading (the spec gives no step)
local TAG_BASE = WorldLayout.Tags.Base
local ATTR_TINT = WorldLayout.Attributes.BaseTint
local OWNER_LABEL = "Owner"
-- Pens3 phase 1: the pen (see the header).
local PEN = WorldLayout.Bases.pen
local PEN_FOLDER = "Pen"
local PEN_ATTRS =
	{ "SD_PenSpots", "SD_Pen", "SD_PenRate", "SD_PenTier", "SD_PenOwner", "SD_Shelf", "SD_ShelfRows", "SD_ShelfTop" }
local TIER_COLORS = { -- K:4170-4189: the gate posts' colour per tier (L:187 GatePost tints)
	{ post = "PenFenceWaferPost" },
	{ post = "PenFenceMintPost" },
	{ post = "PenFenceRoyalPost" },
}
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Roblox cylinder runs along X: this stands it up
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a quarter turn about Y: a piece's X along the plot's Z
-- LK:97-99 pen_upgrade_sign, in sign studs (its front -Z = the Face's side): the post r 0.25 h 3.2 at z 0.15, the state
-- trim 3.8 × 2.8 × 0.3 from y 3 at z 0.15, the price face 3.4 × 2.4 × 0.3 centred at y 4.4, z -0.05.
local SIGN_POST_SIZE = Vector3.new(3.2, 0.5, 0.5)
local SIGN_POST = CFrame.new(0, 1.6, 0.15) * UPRIGHT
local SIGN_TRIM_SIZE = Vector3.new(3.8, 2.8, 0.3)
local SIGN_TRIM = CFrame.new(0, 3 + 2.8 / 2, 0.15)
local SIGN_FACE_SIZE = Vector3.new(3.4, 2.4, 0.3)
local SIGN_FACE = CFrame.new(0, 4.4, -0.05)
-- The face's SurfaceGui (reading; Kit/Signs' look: 50 px a stud, LightInfluence 0.15, Fredoka One, ink text): the title
-- in its top quarter, the icon and price row in the middle, the owner's line under it (y and h: shares of the face's
-- height; px: the largest text size).
local SIGN_PX_PER_STUD = 50
local SIGN_LIGHT = 0.15
local SIGN_FONT = Enum.Font.FredokaOne
local SIGN_INSET = 0.05 -- each side
local SIGN_TITLE = { y = 0.06, h = 0.24, px = 25 }
local SIGN_ROW = { y = 0.34, h = 0.32, px = 32, gap = 4 }
local SIGN_LINE = { y = 0.72, h = 0.2, px = 20 }
local PROMPT_STUDS = 10 -- the plan
-- Pens3 phase 10 (see the header): LK's pieces in piece studs (front -Z, the GUIs' side; turned like the sign). A
-- cylinder turned by ALONG_Z has its +X end (the Right face) toward the front.
local GATE = { -- LK:87-96 pen_gate
	postSize = Vector3.new(12, 1.2, 1.2), -- r 0.6, 12 tall at x ±4
	postX = 4,
	ballSize = Vector3.new(1.6, 1.6, 1.6), -- r 0.8 at y 12.3
	ballY = 12.3,
	frameSize = Vector3.new(8.4, 3.6, 0.3), -- from y 8.4, at z 0.3
	frame = CFrame.new(0, 8.4 + 3.6 / 2, 0.3),
	signSize = Vector3.new(7.4, 3, 0.4),
	sign = CFrame.new(0, 10.2, 0),
	badgeSize = Vector3.new(0.4, 2.2, 2.2), -- a disc r 1.1, 0.4 thick, facing the front
	badge = CFrame.new(0, 12.6, -0.1) * ALONG_Z,
	boardSize = Vector3.new(2.6, 1.2, 0.25),
	board = CFrame.new(-2.3, 7.55, -0.05),
	bulbSize = Vector3.new(0.5, 0.5, 0.5), -- 7 balls r 0.25, 1.2 apart from x -3.6, at y 12.15, z 0.1
	bulbs = 7,
	bulbX = -3.6,
	bulbStep = 1.2,
	bulbY = 12.15,
	bulbZ = 0.1,
}
local BOW =
	{ -- LK:58 bowGeo(0.9) at y 13.5: 2 tori (r 1.1, tube 0.45, at ±1.2 and 1.1 up, turned ±0.6) and a ball r 0.7
		at = CFrame.new(0, 13.5, 0),
		scale = 0.9,
		loopX = 1.2,
		loopY = 1.1,
		loopTurn = 0.6,
		radius = 1.1,
		tube = 0.45,
		knot = 0.7,
		rods = 6, -- a loop's stand-in ring (a torus is no Roblox part)
	}
local ROD_OVERLAP = 1.06 -- SDTools Kit/Props.rods': a ring's rods overlap a little so its joints never gap
local LAMP = { -- LK:240-244 lollipop_lamp
	poleSize = Vector3.new(8.2, 0.7, 0.7), -- r 0.35, 8.2 tall
	candySize = Vector3.new(0.6, 3.2, 3.2), -- a Neon disc r 1.6, 0.6 thick at y 9.2, facing the front
	candy = CFrame.new(0, 9.2, 0) * ALONG_Z,
	swirl = { { radius = 1, tube = 0.18 }, { radius = 0.45, tube = 0.15 } }, -- 2 tori on the candy's front
}
local TREE = { -- LK:235-239 gumdrop_tree
	trunkSize = Vector3.new(5, 1.2, 1.2), -- r 0.6, 5 tall
	stripeSize = Vector3.new(0.28, 1.56, 1.56), -- tori r 0.64, tube 0.14 -> discs r 0.78, 0.28 thick
	stripeY = { 1.2, 2.4, 3.6 },
	-- The canopy lathe (r 3 from y 4.6 up to 6, its dome to 8.8): a cylinder r 3 from 4.6 to 6 under an ellipsoid
	-- 6 × 4.2 × 6 centred at 6.7 (from 4.6 to 8.8; r 2.9 at 7.3 and 2.1 at 8.2 where the lathe has 2.7 and 2).
	baseSize = Vector3.new(1.4, 6, 6),
	baseY = 4.6 + 1.4 / 2,
	topSize = Vector3.new(6, 4.2, 6),
	topY = 6.7,
}
-- K:7872-7873: the gate's and the lamps' SurfaceGuis at PixelsPerStud 25, hidden beyond 150 studs; P3D draws the gate's
-- on planes GUI_INSET inside each face (P3D:267-269).
local GATE_PX_PER_STUD = 25
local GATE_GUI_STUDS = 150
local GUI_INSET = 0.1
-- P3D:245-251 the owner sign (shares of its 7.2 × 2.8 plane; text: P3D's canvas px over its 112-px height): the disc
-- r 0.36 h at (0.48 h, 0.5 h) with a 6-px ink ring (0.15 stud), the name at (0.6 w, 0.42 h) 88 px (74 past 5
-- letters), "BASE n" at (0.6 w, 0.8 h) 30 px. Reading: each text box 0.54 wide, from the disc to the right edge.
local OWNER_GUI = {
	disc = { x = 0.48 * 2.8 / 7.2, d = 0.72, ring = 0.15 },
	name = { x = 0.6, y = 0.42, w = 0.54, h = 0.66, short = 88 / 112, long = 74 / 112, shortLetters = 5 },
	base = { x = 0.6, y = 0.8, w = 0.54, h = 0.27, px = 30 / 112 },
}
local BADGE_GUI = { x = 0.5, y = 0.55, w = 1, h = 0.675, px = 54 / 80, stroke = 0.11 } -- P3D:268 on its 2-stud plane
local BOARD_GUI = { -- P3D:277 on its 2.4 × 1 plane (40 px tall): the heart 30 px at 0.28 w, the count 16 px at 0.62 w
	heart = { x = 0.28, y = 0.54, w = 0.24, h = 0.75, px = 30 / 40 },
	count = { x = 0.62, y = 0.54, w = 0.72, h = 0.4, px = 16 / 40 },
}
local HEADSHOT_TYPE = Enum.ThumbnailType.HeadShot
local HEADSHOT_SIZE = Enum.ThumbnailSize.Size150x150
local OWNER_DISCS = 6 -- Palette PenOwnerDisc1..6 (P3D:244)
local VISITORS_TODAY = 0 -- shortcut: phase 18 (visits) counts the visitors; the board reads 0 until then
-- Pens3 phase 11: the two walk-up signs (LK:96-101 pen_upgrade_sign, K:4240): PEN SPACE and SHELF SPOTS.
type SignKind = { model: string, at: CFrame, title: string, prompt: string, object: string, attribute: string }
local SIGNS: { pen: SignKind, shelf: SignKind } = {
	pen = {
		model = "Sign",
		at = PEN.signs.pen,
		title = Strings.pen.sign.title,
		prompt = "PenPrompt",
		object = Strings.pen.prompt.object,
		attribute = "SD_PenSign",
	},
	shelf = {
		model = "ShelfSign",
		at = PEN.signs.shelf,
		title = Strings.pen.shelfSign.title,
		prompt = "ShelfPrompt",
		object = Strings.pen.shelfPrompt.object,
		attribute = "SD_ShelfSign",
	},
}
-- LK:182-189 base_shelf / LK:190-193 shelf_lock, in shelf studs (front -Z, toward the gate): boards as {size, centre}.
local SHELF = {
	back = { Vector3.new(27.4, 15.6, 0.6), Vector3.new(0, 7.8, 2.7) },
	frame = {
		{ Vector3.new(0.8, 15.6, 6), Vector3.new(-13.3, 7.8, 0) }, -- the sides
		{ Vector3.new(0.8, 15.6, 6), Vector3.new(13.3, 7.8, 0) },
		{ Vector3.new(25.8, 1, 6), Vector3.new(0, 0.5, 0) }, -- the bottom
		{ Vector3.new(25.8, 0.8, 6), Vector3.new(0, 7.9, 0) }, -- the middle shelf (from y 7.5)
		{ Vector3.new(27.4, 0.8, 6), Vector3.new(0, 15.2, 0) }, -- the top (from y 14.8)
	},
	dividers = { -6.6, 0, 6.6 }, -- 0.6 × 6.5 × 6 from y 1 and from y 8.3
	dividerSize = Vector3.new(0.6, 6.5, 6),
	dividerY = { 1 + 6.5 / 2, 8.3 + 6.5 / 2 },
	collider = { Vector3.new(27.4, 15.6, 6), Vector3.new(0, 7.8, 0) }, -- K "block": the piece's whole box
	bow = CFrame.new(0, 15.6, -0.5), -- LK:187 bowGeo(1.1)
	bowScale = 1.1,
	lockSize = Vector3.new(5.8, 6.3, 0.15), -- LK:191 lock_glass, from y 0.1 over the cubby's floor
	lockY = 0.1 + 6.3 / 2,
	lockZ = -3.125, -- L:247 shelf_lock_05 in the shelf's frame
	lockTransparency = 0.5, -- K:98 Glass: "Glass, Transparency 0.5"
	lockPicture = 2.4, -- reading: the padlock picture's side (studs), about v6's padlock (1.6 wide + its shackle)
	-- Placeholder (PLAN phase 11, the TOP spot): a Frosting column r 1.5 × 3 and a Gold top r 1.7 × 0.3 on the shelf's
	-- top, behind the bow, centred under Bases.pen.shelf.top; its lock picture lockPicture studs, lockLift over it.
	topColumn = Vector3.new(3, 3, 3),
	topCap = Vector3.new(0.3, 3.4, 3.4),
	topReflectance = 0.2, -- K:73 Gold: "SmoothPlastic, Reflectance 0.2"
	topLockLift = 1.6,
}

-- Module table

local BaseService = {}

-- Private

local log = Log.new("Base")
local owners: { [number]: any } = {} -- plot -> player
local plots: { [any]: number } = {} -- player -> plot
local waiting: { [any]: boolean } = {} -- players with no plot yet, still retrying
local headshots: { [number]: string } = {} -- pens3 phase 10: UserId -> its headshot (kept for the server's life)
local asking: { [number]: boolean } = {} -- UserIds whose headshot is on its way

local function defaultDeps(): Deps
	return {
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		spawnOf = function(plot: number): SpawnLocation?
			for _, instance in WorldService.stations(TAG_SPAWN) do
				if instance:IsA("SpawnLocation") and instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		plotModel = function(plot: number): Instance?
			for _, instance in WorldService.stations(TAG_BASE) do
				if instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		penOf = function(player: any): any
			local port = StateService.dataPort()
			if port.status(player) ~= "ready" then
				return nil
			end
			local profile = port.getProfile(player)
			return if type(profile) == "table" then profile.pen else nil
		end,
		displayNameOf = function(player: any): string
			local ok, name = pcall(function(): any
				return player.DisplayName
			end)
			return if ok and type(name) == "string" then name else tostring(player)
		end,
		friendOf = function(player: any): any?
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return nil
			end
			local ok, data = pcall(player.GetJoinData, player) -- never yields
			local id = if ok and type(data) == "table" then (data :: any).ReferredByPlayerId else nil
			if type(id) ~= "number" or id <= 0 then
				id = player.FollowUserId
			end
			return if type(id) == "number" and id > 0 then Players:GetPlayerByUserId(id) else nil
		end,
		headshotOf = function(userId: number, done: (image: string?) -> ())
			task.spawn(function()
				local ok, image = pcall(function(): any
					return Players:GetUserThumbnailAsync(userId, HEADSHOT_TYPE, HEADSHOT_SIZE)
				end)
				done(if ok and type(image) == "string" then image else nil)
			end)
		end,
	}
end

local deps: Deps = defaultDeps()

-- Writes `text` into the TextLabel `name` somewhere under `model`.
local function setLabel(model: Instance, name: string, text: string)
	local label = model:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- A visual part of the pen: anchored, out of collisions, queries, touches and shadows.
local function piece(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- The part blocks players but stays out of queries (Kit/Prims' barrier order: CanQuery false after CanCollide).
local function block(part: Part): Part
	part.CanCollide = true
	part.CanQuery = false
	return part
end

-- The one-line width (px) of a sign text at `px` (TextService; a roomy estimate when it cannot answer).
local function textWidth(text: string, px: number): number
	local ok, size = pcall(function(): Vector2
		return TextService:GetTextSize(text, px, SIGN_FONT, Vector2.new(1000, 1000))
	end)
	return if ok and typeof(size) == "Vector2" then size.X else #text * px * 0.6
end

-- A TextLabel of the sign face, scaled to its box under the text size `px`.
local function signLabel(name: string, text: string, px: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = SIGN_FONT
	label.Text = text
	label.TextColor3 = Palette.PenSignText
	label.TextScaled = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = px
	cap.Parent = label
	label.Parent = parent
	return label
end

-- The PEN SPACE sign (see the header; pens3 phase 11: or the SHELF SPOTS sign, `kind`); `price` is the next buy's,
-- nil at MAX.
local function drawSign(folder: Instance, frame: CFrame, plot: number, price: number?, kind: SignKind)
	local at = frame * kind.at
	local max = price == nil
	local sign = Instance.new("Model")
	sign.Name = kind.model
	block(piece("Post", Enum.PartType.Cylinder, SIGN_POST_SIZE, at * SIGN_POST, Palette.PenSignPost, sign))
	local trim = if max then Palette.PenSignMax else Palette.PenSignCanBuy
	block(piece("Trim", Enum.PartType.Block, SIGN_TRIM_SIZE, at * SIGN_TRIM, trim, sign))
	local face = block(piece("Face", Enum.PartType.Block, SIGN_FACE_SIZE, at * SIGN_FACE, Palette.PenSignFace, sign))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PX_PER_STUD
	gui.LightInfluence = SIGN_LIGHT
	local width = 1 - 2 * SIGN_INSET
	local title = signLabel("Title", kind.title, SIGN_TITLE.px, gui)
	title.Position = UDim2.fromScale(SIGN_INSET, SIGN_TITLE.y)
	title.Size = UDim2.fromScale(width, SIGN_TITLE.h)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(SIGN_INSET, SIGN_ROW.y)
	row.Size = UDim2.fromScale(width, SIGN_ROW.h)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, SIGN_ROW.gap)
	list.Parent = row
	local rowPx = SIGN_FACE_SIZE.Y * SIGN_PX_PER_STUD * SIGN_ROW.h
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(rowPx, rowPx)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = AssetTable.image(if max then "img.icon.star" else "img.coin") or ""
	icon.LayoutOrder = 1
	icon.Parent = row
	local text = if price ~= nil then Format.coins(price) else Strings.pen.sign.max
	local room = SIGN_FACE_SIZE.X * SIGN_PX_PER_STUD * width - rowPx - SIGN_ROW.gap
	local priceLabel = signLabel("Price", text, SIGN_ROW.px, row)
	priceLabel.Size = UDim2.fromOffset(math.min(room, math.ceil(textWidth(text, SIGN_ROW.px)) + 2), rowPx)
	priceLabel.LayoutOrder = 2
	row.Parent = gui
	local line = signLabel("Line", "", SIGN_LINE.px, gui)
	line.Position = UDim2.fromScale(SIGN_INSET, SIGN_LINE.y)
	line.Size = UDim2.fromScale(width, SIGN_LINE.h)
	gui.Parent = face
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = kind.prompt
	prompt.ActionText = Strings.pen.prompt.action -- "Buy" (pen.shelfPrompt.action says the same)
	prompt.ObjectText = kind.object
	prompt.HoldDuration = Config.Economy.Pen.signHoldSeconds
	prompt.MaxActivationDistance = PROMPT_STUDS
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = not max
	prompt.Parent = face
	sign:SetAttribute(kind.attribute, plot)
	sign:SetAttribute("SD_Price", price)
	sign.WorldPivot = at
	sign.Parent = folder
end

-- Pens3 phase 10 (see the header) -----------------------------------------------------------------------------------

-- The player's UserId, or nil (a test's Folder player has none).
local function userIdOf(player: any): number?
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" and id > 0 then id else nil
end

-- A ring of `count` rods round `radius` in the XY plane of `cframe` (a torus's stand-in; Kit/Props.rods' way).
local function rods(
	name: string,
	radius: number,
	tube: number,
	cframe: CFrame,
	count: number,
	color: Color3,
	parent: Instance
)
	local length = 2 * radius * math.sin(math.pi / count) * ROD_OVERLAP
	for index = 0, count - 1 do
		local angle = (index + 0.5) * 2 * math.pi / count
		local at = cframe * CFrame.new(radius * math.cos(angle), radius * math.sin(angle), 0)
		piece(
			name,
			Enum.PartType.Cylinder,
			Vector3.new(length, 2 * tube, 2 * tube),
			at * CFrame.Angles(0, 0, angle + math.pi / 2),
			color,
			parent
		)
	end
end

-- LK:58 bowGeo(k) at `pivot` (see BOW): a Model `name` of 2 loops (rings of rods) and a knot, its pivot the bow's
-- origin (A12 / A16 turn it). Pens3 phase 11: the gate's (k 0.9) and the shelf's (k 1.1).
local function drawBow(parent: Instance, pivot: CFrame, k: number, name: string)
	local bow = Instance.new("Model")
	bow.Name = name
	for _, side in { -1, 1 } do
		local loop = pivot
			* CFrame.new(side * BOW.loopX * k, BOW.loopY * k, 0)
			* CFrame.Angles(0, 0, -side * BOW.loopTurn)
		rods("BowLoop", BOW.radius * k, BOW.tube * k, loop, BOW.rods, Palette.PenDecorIcing, bow)
	end
	local knot = 2 * BOW.knot * k
	piece(
		"BowKnot",
		Enum.PartType.Ball,
		Vector3.new(knot, knot, knot),
		pivot * CFrame.new(0, BOW.knot * k, 0),
		Palette.PenDecorIcing,
		bow
	)
	bow.WorldPivot = pivot
	bow.Parent = parent
end

-- A SurfaceGui on `face` (`width` × `height` studs) of `part`, K:7872-7873's way, and its design plane `inset` studs
-- inside the face (P3D's).
local function gateGui(part: BasePart, face: Enum.NormalId, width: number, height: number, inset: number): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GateGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GATE_PX_PER_STUD
	gui.LightInfluence = SIGN_LIGHT
	gui.MaxDistance = GATE_GUI_STUDS
	local plane = Instance.new("Frame")
	plane.Name = "Plane"
	plane.BackgroundTransparency = 1
	plane.AnchorPoint = Vector2.new(0.5, 0.5)
	plane.Position = UDim2.fromScale(0.5, 0.5)
	plane.Size = UDim2.fromScale((width - 2 * inset) / width, (height - 2 * inset) / height)
	plane.Parent = gui
	gui.Parent = part
	return plane
end

-- A label on a plane `height` studs tall: its centre and size as shares of the plane, its text at most `share` of
-- the plane's height.
local function planeLabel(name: string, text: string, plane: Frame, height: number, box: any, share: number): TextLabel
	local label = signLabel(name, text, math.floor(share * height * GATE_PX_PER_STUD), plane)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(box.x, box.y)
	label.Size = UDim2.fromScale(box.w, box.h)
	return label
end

local function round(gui: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = gui
end

-- Paints a user's headshot on every gate of theirs on the island now (it came after the gate was drawn).
local function paintHeadshot(userId: number, image: string)
	for plot, owner in owners do
		if userIdOf(owner) == userId then
			local model = deps.plotModel(plot)
			local pen = if model then model:FindFirstChild(PEN_FOLDER) else nil
			local gate = if pen then pen:FindFirstChild("Gate") else nil
			local label = if gate then gate:FindFirstChild("Headshot", true) else nil
			if label and label:IsA("ImageLabel") then
				label.Image = image
			end
		end
	end
end

-- The owner's headshot when the server has it, else "" (and it is asked for, once at a time).
local function headshotFor(owner: any): string
	local id = userIdOf(owner)
	if id == nil then
		return ""
	end
	if headshots[id] == nil and not asking[id] then
		asking[id] = true
		deps.headshotOf(id, function(image: string?)
			asking[id] = nil
			if image ~= nil then
				headshots[id] = image
				paintHeadshot(id, image)
			end
		end)
	end
	return headshots[id] or "" -- read again: a dep may answer at once
end

-- The owner sign's face (P3D:245-251, OWNER_GUI).
local function drawOwnerGui(sign: BasePart, plot: number, name: string, image: string)
	local size = GATE.signSize
	local plane = gateGui(sign, Enum.NormalId.Front, size.X, size.Y, GUI_INSET)
	local height = size.Y - 2 * GUI_INSET
	local disc = Instance.new("Frame")
	disc.Name = "HeadshotDisc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(OWNER_GUI.disc.x, 0.5)
	disc.Size = UDim2.fromScale(OWNER_GUI.disc.d * height / (size.X - 2 * GUI_INSET), OWNER_GUI.disc.d)
	disc.BackgroundColor3 = Palette["PenOwnerDisc" .. (plot - 1) % OWNER_DISCS + 1]
	round(disc)
	local ring = Instance.new("UIStroke")
	ring.Color = Palette.PenSignText
	ring.Thickness = OWNER_GUI.disc.ring * GATE_PX_PER_STUD
	ring.Parent = disc
	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.BackgroundTransparency = 1
	headshot.Size = UDim2.fromScale(1, 1)
	headshot.ScaleType = Enum.ScaleType.Crop
	headshot.Image = image
	round(headshot)
	headshot.Parent = disc
	disc.Parent = plane
	local n = OWNER_GUI.name
	local letters = utf8.len(name) or #name
	local share = if letters > n.shortLetters then n.long else n.short
	planeLabel("OwnerName", name, plane, height, n, share)
	local base = Strings.format(Strings.pen.gate.base, { n = plot })
	planeLabel("BaseLine", base, plane, height, OWNER_GUI.base, OWNER_GUI.base.px).TextColor3 = Palette.PenGateBaseText
end

-- The gate (see the header): posts, frame, owner sign, number badge, visitor board, and the tier's bulbs and bow.
local function drawGate(
	folder: Instance,
	at: CFrame,
	plot: number,
	step: WorldLayout.PenStep,
	decor: PenMath.Decor,
	owner: any,
	name: string
)
	local post = Palette[(TIER_COLORS[step.tier] or TIER_COLORS[1]).post]
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	for _, x in { -GATE.postX, GATE.postX } do
		local base = at * CFrame.new(x, 0, 0)
		local size = GATE.postSize
		block(
			piece("GatePost", Enum.PartType.Cylinder, size, base * CFrame.new(0, size.X / 2, 0) * UPRIGHT, post, gate)
		)
		piece("GatePostTop", Enum.PartType.Ball, GATE.ballSize, base * CFrame.new(0, GATE.ballY, 0), post, gate)
	end
	local tint = Palette[WorldLayout.Bases.colors[plot].full]
	piece("SignFrame", Enum.PartType.Block, GATE.frameSize, at * GATE.frame, tint, gate)
	local sign = piece("OwnerSign", Enum.PartType.Block, GATE.signSize, at * GATE.sign, Palette.PenSignFace, gate)
	drawOwnerGui(sign, plot, name, headshotFor(owner))
	local badge =
		piece("NumberBadge", Enum.PartType.Cylinder, GATE.badgeSize, at * GATE.badge, Palette.PenGateBadge, gate)
	local badgeSide = GATE.badgeSize.Y
	local badgePlane = gateGui(badge, Enum.NormalId.Right, badgeSide, badgeSide, GUI_INSET)
	local b = BADGE_GUI
	local number = planeLabel("Number", tostring(plot), badgePlane, badgeSide - 2 * GUI_INSET, b, b.px)
	number.TextColor3 = Palette.PenLabelText
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.PenLabelStroke
	stroke.Thickness = b.stroke * b.px * (badgeSide - 2 * GUI_INSET) * GATE_PX_PER_STUD
	stroke.Parent = number
	local board =
		piece("VisitorBoard", Enum.PartType.Block, GATE.boardSize, at * GATE.board, Palette.PenGateBoard, gate)
	local boardPlane = gateGui(board, Enum.NormalId.Front, GATE.boardSize.X, GATE.boardSize.Y, GUI_INSET)
	boardPlane.BackgroundTransparency = 0
	boardPlane.BackgroundColor3 = Palette.PenGateBoardFace
	boardPlane.BorderSizePixel = 0
	local boardHeight = GATE.boardSize.Y - 2 * GUI_INSET
	local heart = BOARD_GUI.heart
	planeLabel("Heart", Strings.pen.gate.heart, boardPlane, boardHeight, heart, heart.px).TextColor3 =
		Palette.PenGateHeart
	local count = BOARD_GUI.count
	planeLabel("Count", BaseService.visitorText(VISITORS_TODAY), boardPlane, boardHeight, count, count.px)
	if decor.bulbs then
		for index = 0, GATE.bulbs - 1 do
			local x = GATE.bulbX + index * GATE.bulbStep
			local bulb = piece(
				"GateBulb",
				Enum.PartType.Ball,
				GATE.bulbSize,
				at * CFrame.new(x, GATE.bulbY, GATE.bulbZ),
				Palette.PenGateGlow,
				gate
			)
			bulb.Material = Enum.Material.Neon
		end
	end
	if decor.bow then
		drawBow(gate, at * BOW.at, BOW.scale, "Bow")
	end
	gate.WorldPivot = at
	gate.Parent = folder
end

-- The lollipop lamps (tier 2 on) and the gumdrop trees (tier 3) at Bases.pen.lamps / trees (see the header).
local function drawDecor(folder: Instance, frame: CFrame, decor: PenMath.Decor)
	if decor.lamps then
		for _, spot in PEN.lamps do
			local at = frame * spot
			local lamp = Instance.new("Model")
			lamp.Name = "Lamp"
			local pole = LAMP.poleSize
			block(
				piece(
					"LampPole",
					Enum.PartType.Cylinder,
					pole,
					at * CFrame.new(0, pole.X / 2, 0) * UPRIGHT,
					Palette.PenDecorFrosting,
					lamp
				)
			)
			local candy =
				piece("LampCandy", Enum.PartType.Cylinder, LAMP.candySize, at * LAMP.candy, Palette.PenGateGlow, lamp)
			candy.Material = Enum.Material.Neon
			local side = LAMP.candySize.Y
			local plane = gateGui(candy, Enum.NormalId.Right, side, side, 0)
			for _, ring in LAMP.swirl do
				local swirl = Instance.new("Frame")
				swirl.Name = "Swirl"
				swirl.BackgroundTransparency = 1
				swirl.AnchorPoint = Vector2.new(0.5, 0.5)
				swirl.Position = UDim2.fromScale(0.5, 0.5)
				local inner = 2 * (ring.radius - ring.tube) / side -- the stroke grows outward from the frame's edge
				swirl.Size = UDim2.fromScale(inner, inner)
				round(swirl)
				local stroke = Instance.new("UIStroke")
				stroke.Color = Palette.PenDecorIcing
				stroke.Thickness = 2 * ring.tube * GATE_PX_PER_STUD
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = swirl
				swirl.Parent = plane
			end
			lamp.WorldPivot = at
			lamp.Parent = folder
		end
	end
	if decor.trees then
		for _, spot in PEN.trees do
			local at = frame * spot.at
			local tint = Palette[spot.color]
			local tree = Instance.new("Model")
			tree.Name = "Tree"
			local trunk = TREE.trunkSize
			block(
				piece(
					"Trunk",
					Enum.PartType.Cylinder,
					trunk,
					at * CFrame.new(0, trunk.X / 2, 0) * UPRIGHT,
					Palette.PenDecorFrosting,
					tree
				)
			)
			for _, y in TREE.stripeY do
				piece(
					"TrunkStripe",
					Enum.PartType.Cylinder,
					TREE.stripeSize,
					at * CFrame.new(0, y, 0) * UPRIGHT,
					Palette.PenDecorIcing,
					tree
				)
			end
			piece(
				"CanopyBase",
				Enum.PartType.Cylinder,
				TREE.baseSize,
				at * CFrame.new(0, TREE.baseY, 0) * UPRIGHT,
				tint,
				tree
			)
			local top =
				piece("CanopyTop", Enum.PartType.Block, TREE.topSize, at * CFrame.new(0, TREE.topY, 0), tint, tree)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = top
			tree.WorldPivot = at
			tree.Parent = folder
		end
	end
end

-- Pens3 phase 11: a lock picture (img.icon.lock) filling `parent` (a SurfaceGui or a BillboardGui).
local function lockPicture(parent: Instance)
	local picture = Instance.new("ImageLabel")
	picture.Name = "LockPicture"
	picture.BackgroundTransparency = 1
	picture.AnchorPoint = Vector2.new(0.5, 0.5)
	picture.Position = UDim2.fromScale(0.5, 0.5)
	picture.Size = UDim2.fromScale(1, 1)
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Image = AssetTable.image("img.icon.lock") or ""
	picture.Parent = parent
end

-- Pens3 phase 11: the shelf, its locks and the TOP spot's pedestal (see the header).
local function drawShelf(folder: Instance, frame: CFrame, plot: number, pen: any)
	local at = frame * PEN.shelf.at
	local shelf = Instance.new("Model")
	shelf.Name = "Shelf"
	local tint = Palette[WorldLayout.Bases.colors[plot].full]
	piece("ShelfBack", Enum.PartType.Block, SHELF.back[1], at * CFrame.new(SHELF.back[2]), tint, shelf)
	for _, board in SHELF.frame do
		piece("ShelfFrame", Enum.PartType.Block, board[1], at * CFrame.new(board[2]), Palette.PenDecorFrosting, shelf)
	end
	for _, y in SHELF.dividerY do
		for _, x in SHELF.dividers do
			local cframe = at * CFrame.new(x, y, 0)
			piece("ShelfFrame", Enum.PartType.Block, SHELF.dividerSize, cframe, Palette.PenDecorFrosting, shelf)
		end
	end
	drawBow(shelf, at * SHELF.bow, SHELF.bowScale, "ShelfBow") -- K's shelf_bow
	local collider = block(
		piece(
			"ShelfCollider",
			Enum.PartType.Block,
			SHELF.collider[1],
			at * CFrame.new(SHELF.collider[2]),
			Palette.PenDecorFrosting,
			shelf
		)
	)
	collider.Transparency = 1
	for index, cubby in PEN.shelf.cubbies do
		local slot = Config.Economy.Pen.maxSpots + index
		if not PenMath.isOpen(pen, slot) then
			local cframe = at * CFrame.new(cubby.X, cubby.Y + SHELF.lockY, SHELF.lockZ)
			local lock = piece("Lock", Enum.PartType.Block, SHELF.lockSize, cframe, Palette.PenShelfGlass, shelf)
			lock.Material = Enum.Material.Glass
			lock.Transparency = SHELF.lockTransparency
			lock:SetAttribute("SD_ShelfSlot", slot)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "LockGui"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = GATE_PX_PER_STUD
			gui.LightInfluence = SIGN_LIGHT
			gui.MaxDistance = GATE_GUI_STUDS
			local plane = Instance.new("Frame")
			plane.Name = "Plane"
			plane.BackgroundTransparency = 1
			plane.AnchorPoint = Vector2.new(0.5, 0.5)
			plane.Position = UDim2.fromScale(0.5, 0.5)
			plane.Size = UDim2.fromScale(SHELF.lockPicture / SHELF.lockSize.X, SHELF.lockPicture / SHELF.lockSize.Y)
			plane.Parent = gui
			lockPicture(plane)
			gui.Parent = lock
		end
	end
	local spot = PEN.shelf.top
	local top = Instance.new("Model")
	top.Name = "Top"
	local column = SHELF.topColumn
	local base = at * CFrame.new(spot.X, spot.Y - SHELF.topCap.X - column.X, spot.Z)
	local columnCFrame = base * CFrame.new(0, column.X / 2, 0) * UPRIGHT
	piece("TopColumn", Enum.PartType.Cylinder, column, columnCFrame, Palette.PenDecorFrosting, top)
	local capCFrame = base * CFrame.new(0, column.X + SHELF.topCap.X / 2, 0) * UPRIGHT
	local cap = piece("TopCap", Enum.PartType.Cylinder, SHELF.topCap, capCFrame, Palette.PenShelfGold, top)
	cap.Reflectance = SHELF.topReflectance
	if pen.top ~= true then
		local gui = Instance.new("BillboardGui")
		gui.Name = "TopLock"
		gui.Size = UDim2.fromScale(SHELF.lockPicture, SHELF.lockPicture) -- studs (a BillboardGui's scale)
		gui.StudsOffsetWorldSpace = Vector3.new(0, SHELF.topCap.X / 2 + SHELF.topLockLift, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = GATE_GUI_STUDS
		lockPicture(gui)
		gui.Parent = cap
	end
	top.WorldPivot = at * CFrame.new(spot)
	top.Parent = shelf
	shelf.WorldPivot = at
	shelf.Parent = folder
end

-- The owner's pen on the plot (see the header): a fresh "Pen" Folder and the base Model's pen attributes. False (and
-- nothing drawn) for a spot count with no step.
local function drawPen(model: Instance, plot: number, pen: any, owner: any, name: string): boolean
	local step = PEN.steps[pen.spots]
	local frame = WorldLayout.plotFrame(plot)
	if step == nil or frame == nil then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = PEN_FOLDER
	local decor = PenMath.decorOf(pen.spots)
	drawSign(folder, frame, plot, PenMath.spotPrice(pen.spots + 1), SIGNS.pen)
	drawGate(folder, frame * PEN.gate, plot, step, decor, owner, name)
	drawDecor(folder, frame, decor)
	drawShelf(folder, frame, plot, pen) -- pens3 phase 11
	drawSign(folder, frame, plot, PenMath.shelfPrice(pen), SIGNS.shelf)
	folder.Parent = model
	model:SetAttribute("SD_PenSpots", pen.spots)
	model:SetAttribute("SD_Pen", PenMath.encode(PenMath.inPen(pen))) -- pens3 phase 11: the walkers only
	model:SetAttribute("SD_Shelf", PenMath.encodeShelf(PenMath.onShelf(pen)))
	model:SetAttribute("SD_ShelfRows", pen.shelfRows)
	model:SetAttribute("SD_ShelfTop", pen.top == true)
	model:SetAttribute("SD_PenRate", PenMath.rate(pen))
	model:SetAttribute("SD_PenTier", step.tier)
	model:SetAttribute("SD_PenOwner", userIdOf(owner))
	return true
end

-- Shows the plot's owner on its generated Model, or an open plot (see the header). Never throws.
local function render(plot: number)
	local ok, err = pcall(function(): any
		local model = deps.plotModel(plot)
		if model == nil then
			return nil
		end
		local owner = owners[plot]
		local colors = if owner ~= nil then WorldLayout.Bases.colors[plot] else WorldLayout.Bases.openColors
		for _, part in model:GetDescendants() do
			local which = part:GetAttribute(ATTR_TINT)
			if part:IsA("BasePart") and (which == "full" or which == "light") then
				part.Color = Palette[colors[which]]
			end
		end
		local name = if owner ~= nil then deps.displayNameOf(owner) else Strings.resolve("base.openPlot") or ""
		setLabel(model, OWNER_LABEL, name)
		local old = model:FindFirstChild(PEN_FOLDER)
		if old then
			old:Destroy()
		end
		local pen = if owner ~= nil then deps.penOf(owner) else nil
		if type(pen) ~= "table" or not drawPen(model, plot, pen, owner, name) then
			for _, attribute in PEN_ATTRS do
				model:SetAttribute(attribute, nil) -- not cleared before a draw, so a client never sees a gap
			end
		end
		return nil
	end)
	if not ok then
		log:warn(`could not draw plot {plot}:`, err)
	end
end

-- The free plot for the player: the one nearest their friend's plot on the ring (Batch 3; a tie takes the lower
-- number), else the lowest free one; nil when all are taken.
local function freePlot(player: any): number?
	local friend = deps.friendOf(player)
	local near = if friend ~= nil then plots[friend] else nil
	local best, bestGap = nil, math.huge
	for plot = 1, PLOT_COUNT do
		if owners[plot] == nil then
			if near == nil then
				return plot
			end
			local gap = math.abs(plot - near)
			gap = math.min(gap, PLOT_COUNT - gap)
			if gap < bestGap then
				best, bestGap = plot, gap
			end
		end
	end
	return best
end

-- Gives the player a free plot (freePlot, and its spawn, when the world has it). Returns it, or nil when all are taken.
local function assign(player: any): number?
	local plot = freePlot(player)
	if plot == nil then
		return nil
	end
	owners[plot] = player
	plots[player] = plot
	if typeof(player) == "Instance" then
		(player :: Instance):SetAttribute(ATTR_PLOT, plot)
		local spawn = deps.spawnOf(plot)
		if spawn and (player :: Instance):IsA("Player") then
			(player :: Player).RespawnLocation = spawn
		end
	end
	render(plot)
	return plot
end

-- Public

-- The player's plot (1..10), or nil while they have none.
function BaseService.plotOf(player: any): number?
	return plots[player]
end

-- The player on plot `plot`, or nil for an open plot.
function BaseService.ownerOf(plot: number): any?
	return owners[plot]
end

-- Redraws the player's plot (their profile loaded, or their pen changed). Nothing for a player without a plot.
function BaseService.refresh(player: any)
	local plot = plots[player]
	if plot ~= nil then
		render(plot)
	end
end

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function BaseService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Pens3 phase 10: the visitor board's line (P3D:277): "1 visitor", else "N visitors".
function BaseService.visitorText(count: number): string
	local text = if count == 1 then Strings.pen.gate.visitor else Strings.pen.gate.visitors
	return Strings.format(text, { count = count })
end

-- Frees every plot and stops every retry (tests; not called by the bootstrap).
function BaseService.reset()
	table.clear(owners)
	table.clear(plots)
	table.clear(waiting)
	table.clear(headshots) -- pens3 phase 10
	table.clear(asking)
end

-- Lifecycle

function BaseService.init()
	StateService.dataPort().onLoaded(function(player: any)
		BaseService.refresh(player)
	end)
end

function BaseService.playerAdded(player: Player)
	if plots[player] ~= nil or assign(player) ~= nil then
		return
	end
	waiting[player] = true
	local triesLeft = math.floor(RETRY_FOR_SECONDS / RETRY_SECONDS)
	local function retry()
		if not waiting[player] then
			return -- left (or reset) meanwhile
		end
		triesLeft -= 1
		if assign(player) ~= nil then
			waiting[player] = nil
		elseif triesLeft <= 0 then
			waiting[player] = nil
			log:warn(`no free plot for {tostring(player)} after {RETRY_FOR_SECONDS} s; they stay in the hub`)
		else
			deps.delay(RETRY_SECONDS, retry)
		end
	end
	deps.delay(RETRY_SECONDS, retry)
end

function BaseService.playerRemoving(player: Player)
	waiting[player] = nil
	local plot = plots[player]
	if plot ~= nil then
		plots[player] = nil
		owners[plot] = nil
		render(plot)
	end
end

return BaseService
