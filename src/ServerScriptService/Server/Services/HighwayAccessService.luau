--!strict
-- HighwayAccessService (server only). Access2 (owner 2026-10-18, "Both": a bridge to walk to the highway's launch deck,
-- plus a quick HIGHWAY button; the owner 2026-10-18: no launch spots, the deck is one open area where everybody walks
-- up and throws). GoHighway() (RF; Config.Net: a trip every 2 s, a burst of 2, one in flight; no argument: no remote
-- names a place, a player or a spot) moves the caller's own character onto the deck. PenBuySpot's shape and refusal
-- order, every refusal charged = false with nothing moved:
--   (1) the arguments (none; NetService drops a call with any) -> (2) no READY profile -> data.notReady -> (3) the
--   decision: no living character -> highway.noCharacter; the place has no SD_Highway deck -> highway.closed -> (4) the
--   server closing or a restart pending -> highway.paused -> (5) a duel or a match (SD_DuelPhase ~= "") ->
--   highway.inDuel; the 1v1 queue (QueueService.state ~= "Idle") or a match queue (MatchService.queued) ->
--   highway.inQueue -> (6) the deck streams in to the player (Player:RequestStreamAroundAsync, §5.4's, yields), then
--   (2)-(5) run AGAIN (a death, a pause, a duel or a queue meanwhile stops the trip), then the pick and the move
--   (unseat, PivotTo, velocity cleared) with no yield between them, so two trips at once never take one place.
--   Never a "busy" refusal (Check 2026-10-18 item 2). Reply ok({charged = false, savePending = false}): no Coins and
--   no profile field change, so nothing is saved.
-- Where (the decision): the deck's top as HighwayBuilder builds it (deckArea: the box round Deck's "deck_top" parts in
-- WorldLayout.Highway.origin's frame, -Z down the lane), a grid of points inside it POINT_MARGIN from its edges and
-- POINT_SPACING apart, nearest the middle first (points), then the bridge's walk from the deck end (bridgePoints:
-- only when the deck has no room). The first point whose floor (a ray down: the point's own floor, or a low launch
-- spot at most FLOOR_RISE above it) carries a character-sized box with no colliding part but the caller's own: the
-- character stands on that floor (never into a part) facing down the lane.
-- Dependencies are injectable (useDeps) so unit tests run with fakes; init() never yields.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local WorldLayout = require(Shared.World.WorldLayout)

local Services = script.Parent
local CharacterService = require(Services.CharacterService)
local MatchService = require(Services.MatchService)
local NetService = require(Services.NetService)
local QueueService = require(Services.QueueService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

-- The deck's top: `frame` its middle at the top's height (its -Z down the lane), `size` its x and z extent.
export type Deck = { frame: CFrame, size: Vector2 }

export type Deps = {
	statusOf: (player: any) -> string, -- DataService status: "loading" | "ready" | "offline" | "readonly"
	duelPhaseOf: (player: any) -> string, -- SD_DuelPhase ("" outside a duel or a match)
	queueState: (player: any) -> string, -- QueueService.state: "Idle" | "Searching" | "Matched"
	matchQueued: (player: any) -> string?, -- MatchService.queued: the mode a match queue holds the player for
	isClosing: () -> boolean,
	isRestartPending: () -> boolean,
	character: (player: any) -> (any, number?), -- the living character and its stand height, or nil
	deck: () -> Deck?, -- the deck's top in the place, nil while it has none
	floorAt: (point: Vector3, character: any) -> number?, -- the colliding top under a point (a ray down), or nil
	isClear: (cf: CFrame, size: Vector3, character: any) -> boolean, -- no colliding part in the box but the character's
	stream: (player: any, at: Vector3) -> (), -- streams the area round `at` in to the player (yields)
	move: (character: any, cf: CFrame) -> (), -- unseats, pivots and stills the character (never yields)
}

-- What a trip needs once every check has passed.
type Trip = { character: any, stand: number, deck: Deck }

-- What the remote answers: NetService.ok({charged, savePending}) or NetService.err(reason, false).
export type Reply =
	{ ok: boolean, data: { charged: boolean, savePending: boolean }?, reason: string?, charged: boolean? }

-- Constants

local REMOTE = "GoHighway"
local STATUS_READY = "ready"
local ATTR_PHASE = "SD_DuelPhase"
local IDLE = "Idle"
local HIGHWAY_ROOT = "SD_Highway" -- SDTools HighwayBuilder's root, Deck its deck
local DECK = "Deck"
local DECK_TOP = "deck_top" -- launch_platform's top slab parts (LK:158-164)
local POSITIONING = Config.Duel.Positioning -- a character's stand height (DuelService's rule)
local POINT_MARGIN = 2 -- reading: clear of the deck's trim ring (0.6 wide) and its rounded corners
-- Reading: half a body's room, so a gap between players standing anywhere is found (the clear box keeps bodies apart).
local POINT_SPACING = 1.5
local BODY = Vector3.new(3, 5.5, 3) -- reading: the room a character needs over the floor
local BODY_LIFT = 0.25 -- the box starts this far over the floor (the floor itself never counts)
local FLOOR_RISE = 0.6 -- a launch spot's top (0.4 over the deck) is still the deck's floor; more is not
local RAY_HEIGHT = 8 -- the floor ray starts this far over a point and reaches as far under it

local CODE_NOT_READY = "data.notReady"
local CODE_NO_CHARACTER = "highway.noCharacter"
local CODE_CLOSED = "highway.closed"
local CODE_PAUSED = "highway.paused"
local CODE_IN_DUEL = "highway.inDuel"
local CODE_IN_QUEUE = "highway.inQueue"

-- Module table

local HighwayAccessService = {}

-- Private

local log = Log.new("Highway")

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

-- §5.4 (DuelService's rule): R15 HipHeight + HRP.Size.Y/2 + R15ExtraHeight; R6 (or unknown) R6Height.
local function standHeight(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 and root and root:IsA("BasePart") then
		return humanoid.HipHeight + root.Size.Y / 2 + POSITIONING.R15ExtraHeight
	end
	return POSITIONING.R6Height
end

local function excluding(character: any): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if typeof(character) == "Instance" then { character } else {}
	params.RespectCanCollide = true
	return params
end

-- Public: the deck ------------------------------------------------------------------------------------------------

-- The deck's top from a built Deck (the box round its "deck_top" parts in the `origin` frame), or nil without them.
function HighwayAccessService.deckArea(deck: Instance, origin: CFrame): Deck?
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	local found = false
	for _, part in deck:GetDescendants() do
		if part:IsA("BasePart") and part.Name == DECK_TOP then
			found = true
			local cf = origin:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			local reach = Vector3.new(
				math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
				math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
				math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			)
			low = low:Min(cf.Position - reach)
			high = high:Max(cf.Position + reach)
		end
	end
	if not found then
		return nil
	end
	local middle = Vector3.new((low.X + high.X) / 2, high.Y, (low.Z + high.Z) / 2)
	return { frame = origin * CFrame.new(middle), size = Vector2.new(high.X - low.X, high.Z - low.Z) }
end

-- The points a trip may land on: a grid inside the deck's top, POINT_MARGIN in from its edges and POINT_SPACING apart
-- (centred), nearest the middle first (ties: smaller x, then smaller z, in the deck's frame). World points on the top.
function HighwayAccessService.points(deck: Deck): { Vector3 }
	local function axis(size: number): { number }
		local span = size - 2 * POINT_MARGIN
		local count = math.max(1, math.floor(span / POINT_SPACING + 1e-6) + 1)
		local first = -(count - 1) * POINT_SPACING / 2
		local list = {}
		for index = 0, count - 1 do
			table.insert(list, first + index * POINT_SPACING)
		end
		return list
	end
	local grid: { Vector2 } = {}
	for _, x in axis(deck.size.X) do
		for _, z in axis(deck.size.Y) do
			table.insert(grid, Vector2.new(x, z))
		end
	end
	table.sort(grid, function(a: Vector2, b: Vector2): boolean
		local da, db = a.Magnitude, b.Magnitude
		if math.abs(da - db) > 1e-6 then
			return da < db
		elseif a.X ~= b.X then
			return a.X < b.X
		end
		return a.Y < b.Y
	end)
	local points: { Vector3 } = {}
	for _, p in grid do
		table.insert(points, deck.frame * Vector3.new(p.X, 0, p.Y))
	end
	return points
end

-- Where a trip lands when the deck has no free point: down the middle of the bridge's walk (WorldLayout.Lobby.bridge,
-- the lobby's walk to the deck) from the deck end, POINT_SPACING apart, a body's half-depth inside either end so its
-- box never meets the deck's step. World points on the walk's top, deck end first.
function HighwayAccessService.bridgePoints(): { Vector3 }
	local spec = WorldLayout.Lobby.bridge
	local deckEnd = Vector3.new(spec.x, spec.toTop, spec.toZ)
	local back = Vector3.new(spec.x, spec.fromTop, spec.fromZ) - deckEnd
	local points: { Vector3 } = {}
	local along = BODY.Z / 2
	while along <= back.Magnitude - BODY.Z / 2 do
		table.insert(points, deckEnd + back.Unit * along)
		along += POINT_SPACING
	end
	return points
end

local function defaultDeps(): Deps
	return {
		statusOf = function(player: any): string
			return StateService.dataPort().status(player)
		end,
		duelPhaseOf = function(player: any): string
			local phase = if typeof(player) == "Instance" then (player :: Instance):GetAttribute(ATTR_PHASE) else nil
			return if type(phase) == "string" then phase else ""
		end,
		queueState = function(player: any): string
			return QueueService.state(player)
		end,
		matchQueued = function(player: any): string?
			return MatchService.queued(player)
		end,
		isClosing = function(): boolean
			return ShutdownService.isClosing()
		end,
		isRestartPending = function(): boolean
			return ShutdownService.isRestartPending()
		end,
		character = function(player: any): (any, number?)
			if not CharacterService.isAlive(player) or CharacterService.getRoot(player) == nil then
				return nil, nil
			end
			local character = player.Character
			return character, standHeight(character)
		end,
		deck = function(): Deck?
			local root = Workspace:FindFirstChild(HIGHWAY_ROOT)
			local deck = if root then root:FindFirstChild(DECK) else nil
			return if deck then HighwayAccessService.deckArea(deck, WorldLayout.Highway.origin) else nil
		end,
		floorAt = function(point: Vector3, character: any): number?
			local from = point + Vector3.new(0, RAY_HEIGHT, 0)
			local hit = Workspace:Raycast(from, Vector3.new(0, -2 * RAY_HEIGHT, 0), excluding(character))
			return if hit then hit.Position.Y else nil
		end,
		isClear = function(cf: CFrame, size: Vector3, character: any): boolean
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = if typeof(character) == "Instance" then { character } else {}
			params.RespectCanCollide = true
			return #Workspace:GetPartBoundsInBox(cf, size, params) == 0
		end,
		stream = function(player: any, at: Vector3)
			-- CharacterService.teleportAsync's stream request (§5.4), failures ignored: the move happens anyway.
			local ok, err = pcall(function(): any
				player:RequestStreamAroundAsync(at, POSITIONING.StreamAroundTimeoutSeconds)
				return nil
			end)
			if not ok then
				log:warn("stream request failed; moving anyway:", err)
			end
		end,
		move = function(character: any, cf: CFrame)
			-- CharacterService.teleportAsync's move without its stream, so nothing yields between the pick and here.
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Sit then
				humanoid.Sit = false
			end
			character:PivotTo(cf)
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end,
	}
end

local deps: Deps = defaultDeps()

-- The first free place for this character: the deck's points, then the bridge's (see the header).
local function pick(deck: Deck, character: any, stand: number): CFrame
	local function facing(at: Vector3): CFrame
		return CFrame.fromMatrix(at, deck.frame.RightVector, Vector3.new(0, 1, 0))
	end
	local bridge = HighwayAccessService.bridgePoints()
	for _, list in { HighwayAccessService.points(deck), bridge } do
		for _, point in list do
			local floor = deps.floorAt(point, character)
			if floor ~= nil and floor >= point.Y - 0.05 and floor <= point.Y + FLOOR_RISE then
				local body = CFrame.new(point.X, floor + BODY_LIFT + BODY.Y / 2, point.Z)
				if deps.isClear(body, BODY, character) then
					return facing(Vector3.new(point.X, floor + stand, point.Z))
				end
			end
		end
	end
	-- shortcut: with the deck and the bridge all taken (more bodies than a 10-player server holds) it lands on the
	-- bridge's first point unchecked; look again if servers grow or props fill the deck.
	return facing(bridge[1] + Vector3.new(0, stand, 0))
end

-- (2)-(5) of the header, in order: the refusal's code, or nil with what the trip needs.
local function check(player: any): (string?, Trip?)
	if deps.statusOf(player) ~= STATUS_READY then
		return CODE_NOT_READY, nil
	end
	local character, stand = deps.character(player)
	if character == nil or stand == nil then
		return CODE_NO_CHARACTER, nil
	end
	local deck = deps.deck()
	if deck == nil then
		return CODE_CLOSED, nil
	end
	if deps.isClosing() or deps.isRestartPending() then
		return CODE_PAUSED, nil
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL, nil
	end
	if deps.queueState(player) ~= IDLE or deps.matchQueued(player) ~= nil then
		return CODE_IN_QUEUE, nil
	end
	return nil, { character = character, stand = stand, deck = deck }
end

-- Public: the remote (see the header for the order of the checks) ----------------------------------------------------

function HighwayAccessService.go(player: any): Reply
	local code, trip = check(player)
	if trip == nil then
		return NetService.err(code :: string, false)
	end
	deps.stream(player, trip.deck.frame.Position) -- yields: so everything is checked again after it
	code, trip = check(player)
	if trip == nil then
		return NetService.err(code :: string, false)
	end
	deps.move(trip.character, pick(trip.deck, trip.character, trip.stand)) -- no yield since the pick
	log:info(`user {userIdOf(player)} went to the highway's launch deck`)
	return NetService.ok({ charged = false, savePending = false })
end

-- Public: tests -----------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function HighwayAccessService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function HighwayAccessService.init()
	NetService.onInvoke(REMOTE, function(player: Player): any
		return HighwayAccessService.go(player)
	end)
end

return HighwayAccessService
