--!strict
-- PenLookController (client only). Pens3 phase 10 (build plan work/pens3/PLAN.md "PHASE 10"; lobby design v6, approved
-- by the owner: `K:n` = kit.json line n, `P3D:n` = "Squishy Lobby 3D.html" line n): the motion of every base's gate
-- on this client. All cosmetic: BaseService draws the pen, gate and decor; nothing here decides anything.
-- * Bases: every plot Model tagged WorldLayout.Tags.Base (PenController's way). Its SD_PenOwner (the owner's UserId)
--   and SD_PenTier (BaseService sets them with each redraw of its "Pen" Folder) are read when it is first seen
--   (nothing plays); a change marks it and the one effect checks it on its next frame, when the redrawn pen is in.
--   changes() compares them with the last ones seen:
--   - A10 SignAssignPop (K:5607-5639, Config.UI.Pen.signAssign): a new owner (a player was given the base): the gate's
--     OwnerSign part scales about its centre.
--   - A12 GateBowWiggle (K:5673-5710, gateBow): the same owner reaching tier III; and, every frame, a tier III base
--     within Config.UI.Pen.animateStuds of the camera whose owner steps onto the base's fenced floor (inside(): wb,
--     owner 2026-10-17, the pen is the whole base; off it at the last check). The gate's Bow Model turns about its
--     pivot's Z.
--   - Wb: no A14 FenceGrow or E15 PenUpgradePoof any more (K:5749-5781, K:4627-4645: "at each segment that pops in";
--     the pen has no fence now). A bought spot plays A13 on its sign (PenController) and its new squishy walks in.
-- * E17 SignGlint (K:4662-4676, glint): on every Coins or pen change, the local player's own PEN SPACE sign's state
--   (PenController.signState of its SD_Price); a turn from too expensive to can buy at one price (glint()) sparkles
--   once in front of its price face, never again for that price (calm: no repeat, no flashing).
-- * ReducedMotion (Tweens.reducedMotion): no A10 / A12 and no glint (K's fallback "off"). E17 uses the engine's
--   sparkles texture until K's sparkle.png is uploaded.
-- * One Scheduler render effect checks the marked bases, steps every running motion and the walk-in checks. A motion
--   whose part a redraw removed is dropped; any other ends with its parts exactly as BaseService built them (destroy()
--   ends them too).
-- Public: the pure parts (changes, inside, glint), init(), start(), destroy() (tests and leak checks; the bootstrap
-- never calls it), debugState().

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local Scheduler = require(Client.Anim.Scheduler)
local Timeline = require(Client.Anim.Timeline)
local Tweens = require(Client.Anim.Tweens)
local PenController = require(script.Parent.PenController)
local StateController = require(script.Parent.StateController)

-- Types

export type Seen = { owner: number?, tier: number? }
export type Changes = { assign: boolean, bow: boolean }
export type SignSeen = { state: string, price: number? }
export type DebugState = { started: boolean, bases: number, motions: number }

type Base = {
	plot: number,
	model: Model,
	frame: CFrame,
	seen: Seen,
	dirty: boolean,
	inside: boolean?, -- its owner on the base's floor at the last check (nil: not checked, or out of range)
	cleanup: any, -- Cleanup.Cleanup: its connections
}

-- A running motion: steps to os.clock() `now`; false when it is over (math.huge ends it at once, its parts at rest).
type Motion = (now: number) -> boolean

-- Constants

local P = Config.UI.Pen
local LAYOUT = WorldLayout.Bases.pen
local TAG_BASE = WorldLayout.Tags.Base
local ATTR_PLOT_MODEL = WorldLayout.Attributes.Plot
local ATTR_PLOT = "SD_Plot" -- the local player's plot (BaseService)
local ATTR_OWNER = "SD_PenOwner"
local ATTR_TIER = "SD_PenTier"
local ATTR_PRICE = "SD_Price"
local PEN_FOLDER = "Pen"
local ROYAL_TIER = 3 -- K:4170-4189 tier III
local ASSIGN = Timeline.new(P.signAssign)
local BOW = Timeline.new(P.gateBow)
local SPARKLES = Config.Vfx.Textures.sparkles

-- Module table

local PenLookController = {}

-- Private

local cleanup: Cleanup.Cleanup? = nil
local effect: Scheduler.Handle? = nil
local bases: { [number]: Base } = {}
local motions: { Motion } = {}
local moving: { [Instance]: boolean } = {} -- a sign or bow in a motion now (never two at once)
local lastSign: SignSeen? = nil -- the own sign at the last check (E17)
local glinted: { [number]: boolean } = {} -- the prices whose glint went off

local function read(model: Instance): Seen
	local function number(name: string): number?
		local value = model:GetAttribute(name)
		return if type(value) == "number" then value else nil
	end
	return { owner = number(ATTR_OWNER), tier = number(ATTR_TIER) }
end

local function pick(parent: Instance?, ...: string): Instance?
	local found = parent
	for _, name in { ... } do
		found = if found then found:FindFirstChild(name) else nil
	end
	return found
end

-- A10: the owner sign pops (see the header).
local function startAssign(sign: Instance, start: number)
	if not sign:IsA("BasePart") or moving[sign] then
		return
	end
	local part = sign :: BasePart
	local size = part.Size
	moving[part] = true
	table.insert(motions, function(now: number): boolean
		local ms = (now - start) * 1000
		if not part:IsDescendantOf(Workspace) or ASSIGN:isDone(ms) then
			moving[part] = nil
			if part:IsDescendantOf(Workspace) then
				part.Size = size
			end
			return false
		end
		part.Size = size * ASSIGN:eval(ms)
		return true
	end)
end

-- A12: the bow wiggles (see the header).
local function startBow(bow: Instance?, start: number)
	if bow == nil or not bow:IsA("Model") or moving[bow] then
		return
	end
	local model = bow :: Model
	local pivot = model:GetPivot()
	moving[model] = true
	table.insert(motions, function(now: number): boolean
		local ms = (now - start) * 1000
		if not model:IsDescendantOf(Workspace) or BOW:isDone(ms) then
			moving[model] = nil
			if model:IsDescendantOf(Workspace) then
				model:PivotTo(pivot)
			end
			return false
		end
		model:PivotTo(pivot * CFrame.Angles(0, 0, math.rad(BOW:eval(ms))))
		return true
	end)
end

-- A marked base's check (see the header).
local function check(base: Base, now: number)
	base.dirty = false
	local seen = read(base.model)
	local found = PenLookController.changes(base.seen, seen)
	base.seen = seen
	local pen = base.model:FindFirstChild(PEN_FOLDER)
	if pen == nil or Tweens.reducedMotion() then
		return
	end
	local sign = pick(pen, "Gate", "OwnerSign")
	if found.assign and sign then
		startAssign(sign, now)
	end
	if found.bow then
		startBow(pick(pen, "Gate", "Bow"), now)
	end
end

-- A12's other trigger: the owner of a tier III base near the camera steps onto its floor (see the header).
local function walkIns(now: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	for _, base in bases do
		local seen = base.seen
		local owner = if seen.tier == ROYAL_TIER and seen.owner then Players:GetPlayerByUserId(seen.owner) else nil
		local character = if owner then owner.Character else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local near = ((base.frame * LAYOUT.gate).Position - eye).Magnitude <= P.animateStuds
		if root == nil or not root:IsA("BasePart") or not near then
			base.inside = nil
		else
			local inside = PenLookController.inside(base.frame:PointToObjectSpace(root.Position))
			if inside and base.inside == false and not Tweens.reducedMotion() then
				startBow(pick(base.model, PEN_FOLDER, "Gate", "Bow"), now)
			end
			base.inside = inside
		end
	end
end

-- The one effect (see the header).
local function step(_dt: number, now: number): boolean
	for _, base in bases do
		if base.dirty then
			check(base, now)
		end
	end
	for index = #motions, 1, -1 do
		if not motions[index](now) then
			table.remove(motions, index)
		end
	end
	walkIns(now)
	return true
end

-- E17 (see the header).
local function glintCheck()
	local player = Players.LocalPlayer
	local plot = if player then player:GetAttribute(ATTR_PLOT) else nil
	local base = if type(plot) == "number" then bases[plot] else nil
	local sign = if base then pick(base.model, PEN_FOLDER, "Sign") else nil
	if sign == nil then
		lastSign = nil
		return
	end
	local value = sign:GetAttribute(ATTR_PRICE)
	local price = if type(value) == "number" then value else nil
	local state = PenController.signState(price, StateController.coins()).state
	if price and PenLookController.glint(lastSign, state, price, glinted) then
		glinted[price] = true
		local face = sign:FindFirstChild("Face")
		if face and face:IsA("BasePart") and not Tweens.reducedMotion() then
			local g = P.glint
			FxPool.default():emit(face.CFrame * CFrame.new(0, 0, -(face.Size.Z / 2 + g.out)), g.count, {
				Texture = SPARKLES,
				Color = ColorSequence.new(Palette.White),
				Size = NumberSequence.new(g.size),
				Lifetime = NumberRange.new(g.seconds),
				Speed = NumberRange.new(0),
			})
		end
	end
	lastSign = { state = state, price = price }
end

local function watch(model: Instance)
	local plot = model:GetAttribute(ATTR_PLOT_MODEL)
	local frame = if type(plot) == "number" then WorldLayout.plotFrame(plot) else nil
	if cleanup == nil or frame == nil or not model:IsA("Model") or bases[plot :: number] ~= nil then
		return
	end
	local c = Cleanup.new()
	local base: Base = {
		plot = plot :: number,
		model = model :: Model,
		frame = frame,
		seen = read(model),
		dirty = false,
		inside = nil,
		cleanup = c,
	}
	bases[base.plot] = base
	for _, name in { ATTR_OWNER, ATTR_TIER } do
		c:add(model:GetAttributeChangedSignal(name):Connect(function()
			base.dirty = true
		end))
	end
end

local function unwatch(model: Instance)
	for plot, base in table.clone(bases) do
		if base.model == model then
			bases[plot] = nil
			base.cleanup:clean()
		end
	end
end

-- Public: the pure parts -------------------------------------------------------------------------------------------

-- What a base's new owner / tier play against the last seen (see the header); nothing at first sight (nil).
function PenLookController.changes(old: Seen?, new: Seen): Changes
	local found: Changes = { assign = false, bow = false }
	if old == nil or new.owner == nil then
		return found
	end
	if new.owner ~= old.owner then
		found.assign = true
		return found
	end
	found.bow = old.tier ~= nil and old.tier < ROYAL_TIER and new.tier == ROYAL_TIER
	return found
end

-- A plot-local point on the base's fenced floor (wb: the pen is the whole base, WorldLayout.Bases.pen.walk).
function PenLookController.inside(point: Vector3): boolean
	local walk = LAYOUT.walk
	return point.X > walk.minX and point.X < walk.maxX and point.Z > walk.minZ and point.Z < walk.maxZ
end

-- E17: the own sign turned from too expensive (`last`) to can buy at the same price, and that price has not glinted.
function PenLookController.glint(last: SignSeen?, state: string, price: number?, done: { [number]: boolean }): boolean
	return last ~= nil
		and last.state == "tooExpensive"
		and state == "canBuy"
		and price ~= nil
		and last.price == price
		and not done[price]
end

function PenLookController.debugState(): DebugState
	local count = 0
	for _ in bases do
		count += 1
	end
	return { started = cleanup ~= nil, bases = count, motions = #motions }
end

-- Lifecycle

function PenLookController.init()
	-- Nothing to register: the gates are world objects.
end

function PenLookController.start()
	if cleanup ~= nil then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	c:add(function()
		for _, motion in table.clone(motions) do
			motion(math.huge) -- every part back as built
		end
		table.clear(motions)
		table.clear(moving)
		for plot, base in table.clone(bases) do
			bases[plot] = nil
			base.cleanup:clean()
		end
		local handle = effect
		if handle then
			handle:disconnect()
		end
		effect, lastSign = nil, nil
		table.clear(glinted)
	end)
	for _, model in CollectionService:GetTagged(TAG_BASE) do
		watch(model)
	end
	c:add(CollectionService:GetInstanceAddedSignal(TAG_BASE):Connect(watch))
	c:add(CollectionService:GetInstanceRemovedSignal(TAG_BASE):Connect(unwatch))
	for _, field in { "coins", "pen" } do
		c:add(StateController.changed(field):connect(glintCheck))
	end
	effect = Scheduler.add(step, "render")
	glintCheck()
end

function PenLookController.destroy()
	local c = cleanup
	if c then
		cleanup = nil
		c:clean()
	end
end

return PenLookController
