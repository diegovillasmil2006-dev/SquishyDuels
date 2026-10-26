--!strict
-- HeldSquishyController (client only). DESIGN §9.5, §9.3, §9.15, §8.1 rules 3-4.
-- Every client shows a held model on every character within Config.Anim.held.buildStuds (150) of the camera and
-- destroys it beyond destroyStuds (180); the local player's own character always has one. The squishy comes from the
-- replicated Player attribute SD_Equipped (server-written); a change rebuilds the model.
--
-- Model: SquishyCache.clone(id, "Held") (unanchored, welded to its Root), parented to Workspace.SD_ClientFx (client
-- parts never stream out, §9.1 #5). Weld: Part0 = RightHand (R15) or "Right Arm" (R6), Part1 = Root,
-- C0 = the hand's RightGripAttachment.CFrame, C1 = CFrame.new(hold.grip) * CFrame.Angles(0, rad(hold.heldYaw), 0).
-- A hand without RightGripAttachment gets the stock attachment's frame instead (bottom of the hand, turned -90° about
-- X, as on the standard R15 RightHand and R6 Right Arm), so hold.grip and heldYaw mean the same on every rig.
-- Every part is Massless, non-colliding, non-query, group SD_Cosmetic (builder), so physics and hit queries never
-- change, and remote models follow the interpolated hand through the weld (no per-frame CFrame writes).
--
-- Idle (Config.Anim.held): period 2.4 s with a random phase; S.Y = 1 + 0.025·sin φ, S.X = S.Z = 1 - 0.0125·sin φ
-- through the SquishDeformer; bob 0.03 studs through a Weld.C1 offset at φ + π/2.
-- The squishy rig (squishy overhaul spec 2026-10-09 §3.2): every held model has one Anim/SquishRig from its blueprint's
-- `motion`; this controller is its only owner: it steps it once a frame and writes the model once (deformer:apply,
-- the rig's out times the idle and the overlays). Other controllers act through getRig (tap, press, hold, kick, hit,
-- setFace; never step) and react. Detail levels (re-ranked every rangeCheckSeconds, and at once when Anim/HeroRigs
-- changes): the hero rigs animating outside the held models (the Inspect model, the box reveal) come out of the budget
-- first; the own model is "hero" (sections, the only held model with section C0 writes) while heroRigs (3; phone
-- heroRigsLow 2) leaves it a slot, else the first "near" one; the next Config.Vfx.Budgets.nearRigs (6; phone
-- nearRigsLow 3) on-screen models within deformingRigStuds (120) by distance are "near" (squash, face, blink, jiggle),
-- the rest up to deformingRigs (12; phone deformingRigsLow 8, the outside heroes included) "far" (breathing and
-- squash); the others rest. Phone = MeshQuality "Low", or nil in the first frames. The slots the held models leave go
-- to the Collection displays first
-- (CollectionController.setIdleSlots), then to the lobby breathers (AmbientController.setBreatheSlots, §18.9): no slot
-- is counted twice (splitSlots). No blink while the own model is hidden (LocalTransparencyModifier >= 0.99). Rig
-- stepping and writes run in the "SD_Rigs" profiler scope (spec §5). A far model whose rig sleeps (breathing only) is
-- stepped and written every 2nd frame (farStride, rig speed-up pass); any input wakes it the same frame.
-- Feel pass (§18.5.1 A6-A7; all lobby and duel values in Config.Anim.held):
--   * Lobby idle: while the holder's SD_DuelPhase is "" (or unset) the idle uses held.lobbyIdle (2.8 s, ampY 0.035,
--     ampXZ 0.0175, bob 0.05); in a duel the values above. Both idles run on their own clocks and the result crossfades
--     over lobbyIdle.crossfadeSeconds when the phase changes (blending outputs, never periods, so no phase jump).
--     ReducedMotion: the idle × 0.5 (idleSample).
--   * Movement jiggle (here, no new connection): kicks on the rig's feel jiggle (spec §3.2: the toy's feel spring, a
--     kick peaks at kick × the feel gain, shown at most held.motionJiggle.maxJ). Kicks: a change of the root's
--     horizontal speed between frames gives clamp(|Δspeed| · perSpeed, 0, maxImpulse); a landing (vy from
--     <= landingFromVy to >= landingToVy) gives landingImpulse. Reading: "speed change" is the change of the horizontal
--     speed (not of its direction, so walking around a corner at a steady speed does not buzz). Only models that
--     animate; off under ReducedMotion.
--   * Equip pop: a rebuild after SD_Equipped changed on the same character scales the new model popInFrom -> 1 on the
--     pop-in spring (popInOmega, popInZeta) plus held.equipPopPuffs puffs at the hand (FxPool halves them under
--     ReducedMotion, which also skips the scale).
-- Overlays: other controllers (the squeeze glue, the throw windup and pop-in, the elimination) add a named overlay;
-- every frame, right after the rig step, its step(dt, now, out) sees that step's rig output (events, press amount)
-- and returns a scale multiplier and a twist (radians about the squishy's squeeze axis, written by the deformer into
-- Weld.C1) on top of the rig's. An optional prepare(dt, now) runs right before the rig step (the throw windup's hold
-- and squish face, so they show in the same frame).
-- Hidden (all parts LocalTransparencyModifier = 1 and no shadows: that modifier alone keeps a part's shadow) while dead
-- or seated, or while any reason given to setHidden() holds (the thrown copy is out, Part 4). The local model otherwise
-- follows the hand's LocalTransparencyModifier, so it fades with the arm in first person (shadow kept, like the arm's).
-- First person (spec 2026-10-10 §3.4): one rig, two views. setMirror(fn) (the local player only; ViewmodelController,
-- made once at show) gets every frame the same final out as the own model (rig × idle × pop-in × overlays) and that
-- scale on top of the rig's (finishOut), which the overlay divides back out (spec 2026-10-11 §3.4: the design's toy
-- has no idle scale, equip pop or throw pop-in of ours), and writes the overlay copy; while a mirror is set and Roblox
-- hides the hand (first person, LocalTransparencyModifier >= 0.99) the hidden own model is not written, it blinks while
-- mirrored (mirrorRule) and gets no movement jiggle. The hidden branch rests the mirror once (fn(nil, Vector3.one)).
-- isMirrored() tells whether a mirror is set. setMirror's fx (owner 2026-10-26: the zoomed-in squeeze sparkles floated
-- in the air at the hidden hand): while mirrored, mirrorFx() hands the own effects (the equip pop's puffs here, the
-- squeeze's puffs, release sparkles and steam from SqueezeFeel) to the overlay, which draws them on the toy you see,
-- instead of world particles at the hidden own model. Reacted(player, kind, strength) fires on every react() (its one
-- caller is VfxController's afterHold).
-- Cleanup: one Cleanup per player (connections) and one per held model (model, deformer, the hand's and character's
-- Destroying); CharacterRemoving or the character's Destroying destroys the held model, PlayerRemoving everything.
-- (DESIGN §9.4 puts the held model in the joint layer's Cleanup; here the two have separate owners, with the same
-- triggers.)

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Signal = require(Shared.Util.Signal)
local Spring = require(Shared.Util.Spring)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local HeroRigs = require(Client.Anim.HeroRigs)
local MeshQuality = require(Client.Anim.MeshQuality)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local AmbientController = require(script.Parent.AmbientController)
local CollectionController = require(script.Parent.CollectionController)

-- Types

-- An overlay step gets this frame's rig output (right after the rig step: its events, press amount) and returns
-- (scale multiplier in pivot space, twist in radians, keep). keep ~= true removes it after this frame. removed runs
-- once whenever the overlay goes away for any reason (finished, replaced, model hidden/culled/destroyed). prepare, when
-- given, runs every frame right BEFORE the rig step, so what it tells the rig (hold, setFace) shows in that frame.
export type Overlay = {
	step: (dt: number, now: number, out: SquishRig.Out) -> (Vector3, number, boolean),
	removed: (() -> ())?,
	prepare: ((dt: number, now: number) -> ())?,
}

-- The first-person mirror: the own model's final out and the scale put on top of the rig's S (the idle × the equip pop
-- × the overlays, finishOut) each frame; nil out = rest.
export type Mirror = (out: SquishRig.Out?, scale: Vector3) -> ()

-- The first-person mirror's effects (mirrorFx): kind "puffs", "sparkles", "steam", "confetti" or "ring", how many and
-- their colour.
export type MirrorFx = (kind: string, count: number, colour: Color3) -> ()

type Held = {
	model: Model,
	squishyId: string,
	def: Types.SquishyDef,
	character: Model,
	humanoid: Humanoid,
	hand: BasePart,
	weld: Weld,
	baseC1: CFrame,
	deformer: SquishDeformer.Deformer,
	parts: { BasePart },
	shadowParts: { BasePart }, -- the parts built with CastShadow (every visual part, not the Root)
	phase: number,
	modifier: number,
	shadowsOff: boolean,
	detail: SquishRig.Detail?, -- nil = not animating (out of the rig budget): it rests
	resting: boolean,
	overlays: { [string]: Overlay },
	hiddenReasons: { [string]: boolean },
	cleanup: Trove,
	lobbyWeight: number, -- 0 = the duel idle, 1 = the lobby idle (crossfaded)
	rig: SquishRig.Rig,
	out: SquishRig.Out, -- the rig's one out table (no per-frame tables)
	reduced: boolean, -- ReducedMotion as the rig last heard it
	lastSpeed: number?, -- the root's horizontal speed last frame (nil after a pause)
	falling: boolean, -- the root fell at <= landingFromVy since the last landing
	pop: Spring.Spring<number>?, -- the equip pop scale (nil when none runs)
	popUntil: number, -- os.clock() safety stop of the equip pop
	oddFrame: boolean, -- the far stride's frame parity (farStride; random per model)
}

type Entry = {
	player: Player,
	cleanup: Trove,
	held: Held?,
}

-- A Util/Cleanup as stored in the records above. Its generic add<T>() makes the type checker's exact record
-- comparison fail ("Entry" vs "Entry"), so records see only what they use.
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}

-- Constants

local HELD = Config.Anim.held
local LOBBY_IDLE = HELD.lobbyIdle
local JIGGLE = HELD.motionJiggle
local BUDGET = Config.Vfx.Budgets
local SQUEEZE_PARTICLES = Config.Anim.squeeze.particles
local ATTR_EQUIPPED = "SD_Equipped"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local ROOT_PART = "HumanoidRootPart"
local REDUCED_IDLE = 0.5 -- §18.1: ReducedMotion "idle × 0.5"
local POP_SETTLE = 0.002 -- the equip pop ends once the spring is this close to 1 (and this slow)
local POP_MAX_SECONDS = 1.5 -- reading: a safety stop for the equip pop (it settles in about 0.5 s)
local POP_MIN_SCALE = 0.05 -- as ThrowController's pop-in: never a zero or negative scale
local HIDDEN_MODIFIER = 0.99 -- spec §3.2: no blink on the own model while it is this hidden
local COLLECTION_IDLE_MAX = Config.Inspect.Collection.idleMax
local PROFILE_RIGS = "SD_Rigs" -- the profiler scope of rig stepping and writes (spec §5)
local CLIENT_FX = "SD_ClientFx"
local GRIP_ATTACHMENT = "RightGripAttachment"
-- Rotation of the stock RightGripAttachment (R15 RightHand and R6 Right Arm): -90° about X.
local STOCK_GRIP_ROTATION = CFrame.Angles(-math.pi / 2, 0, 0)
local TAU = 2 * math.pi
-- How often distances, streaming and the deformation budget are re-checked (not per frame).
local RANGE_CHECK_SECONDS = HELD.rangeCheckSeconds

-- Module table

local HeldSquishyController = {}

-- Fired with (player, model?) when a player's held model is built (model) or removed (nil).
HeldSquishyController.HeldChanged = Signal.new() :: Signal.Signal<Player, Model?>
-- Fired with (player, kind, strength) by every react() (first-person spec 2026-10-10 §3.4).
HeldSquishyController.Reacted = Signal.new() :: Signal.Signal<Player, "hit" | "land", number>

-- Private

local log = Log.new("Held")
local entries: { [Player]: Entry } = {}
local cleanup: Cleanup.Cleanup? = nil
local mirror: Mirror? = nil -- the local player's first-person mirror (setMirror)
local mirrorFx: MirrorFx? = nil -- its effects (setMirror's fx)
local rng = Random.new()
local rangeTimer = math.huge -- first frame runs a range pass
local rankedHeroes = 0 -- HeroRigs.count() at the last range pass

local function clientFxFolder(): Instance
	local folder = Workspace:FindFirstChild(CLIENT_FX)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = CLIENT_FX
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

local function findHand(character: Model): (BasePart?, Humanoid?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil, nil
	end
	local handName = if humanoid.RigType == Enum.HumanoidRigType.R6 then "Right Arm" else "RightHand"
	local hand = character:FindFirstChild(handName)
	if hand == nil or not hand:IsA("BasePart") then
		return nil, humanoid
	end
	return hand, humanoid
end

local function equippedId(player: Player): string?
	local id = player:GetAttribute(ATTR_EQUIPPED)
	if type(id) == "string" and Catalog.isValidId(id) then
		return id
	end
	return nil
end

local function removeOverlay(held: Held, name: string)
	local overlay = held.overlays[name]
	if overlay == nil then
		return
	end
	held.overlays[name] = nil
	local removed = overlay.removed
	if removed then
		local ok, err = pcall(function(): any
			removed()
			return nil
		end)
		if not ok then
			log:error(`overlay {name} removed() failed:`, err)
		end
	end
end

local function clearOverlays(held: Held)
	if next(held.overlays) == nil then
		return
	end
	for name in table.clone(held.overlays) do
		removeOverlay(held, name)
	end
end

local function destroyHeld(entry: Entry)
	local held = entry.held
	if held == nil then
		return
	end
	entry.held = nil
	clearOverlays(held)
	held.cleanup:clean()
	HeldSquishyController.HeldChanged:fire(entry.player, nil)
end

-- The equip pop's puffs at the hand (§18.5.1 A7): the squeeze puff look (Config.Anim.squeeze.particles) in the
-- squishy's accent, White for a Common (reading: the squeeze puffs' colour rule). The local player's in first person go
-- to the overlay's toy (mirrorFx): the own model is hidden there.
local function equipPuffs(def: Types.SquishyDef, at: Vector3, isLocal: boolean)
	local colour = if def.rarity == "Common" then Palette.White else Color3.fromHex(def.visuals.accent)
	if isLocal and HeldSquishyController.mirrorFx("puffs", HELD.equipPopPuffs, colour) then
		return
	end
	local p = SQUEEZE_PARTICLES
	FxPool.default():emit(at, HELD.equipPopPuffs, {
		Texture = Config.Vfx.Textures.smoke,
		Lifetime = NumberRange.new(p.lifetimeMin, p.lifetimeMax),
		Size = NumberSequence.new(p.sizeFrom, p.sizeTo),
		Speed = NumberRange.new(p.speedMin, p.speedMax),
		SpreadAngle = Vector2.new(p.spreadDeg, p.spreadDeg),
		Color = ColorSequence.new(colour),
	})
end

local function buildHeld(
	entry: Entry,
	character: Model,
	hand: BasePart,
	humanoid: Humanoid,
	squishyId: string,
	equipPop: boolean
)
	local def = Catalog.get(squishyId)
	if def == nil then
		return
	end
	local c = Cleanup.new()
	local model = c:add(SquishyCache.clone(squishyId, "Held"))
	local root = model.PrimaryPart
	if root == nil then
		c:clean()
		log:warn(`held model for {squishyId} has no Root`)
		return
	end
	local baseC1 = CFrame.new(def.hold.grip) * CFrame.Angles(0, math.rad(def.hold.heldYaw), 0)
	local weld = Instance.new("Weld")
	weld.Name = "SD_HeldWeld"
	weld.Part0 = hand
	weld.Part1 = root
	weld.C0 = HeldSquishyController.gripC0(hand)
	weld.C1 = baseC1
	weld.Parent = root

	local parts: { BasePart } = {}
	local shadowParts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			if descendant.CastShadow then
				table.insert(shadowParts, descendant)
			end
		end
	end

	local deformer = SquishDeformer.attach(model, { twist = "weld", weld = weld, twistAxis = def.anim.squeezeAxis })
	c:add(deformer)
	-- A character (or hand) destroyed without CharacterRemoving takes its held model along at once.
	local function onDestroying()
		local current = entry.held
		if current and current.model == model then
			destroyHeld(entry)
		end
	end
	c:add(character.Destroying:Connect(onDestroying))
	c:add(hand.Destroying:Connect(onDestroying))
	model.Parent = clientFxFolder()

	local now = os.clock()
	local reduced = Tweens.reducedMotion()
	local blueprint = SquishyBlueprints[def.blueprintId]
	-- Config.validate checks that every Catalog blueprint has its motion row.
	local rig = SquishRig.new(blueprint.motion :: SquishRig.Motion, {
		axis = def.anim.squeezeAxis,
		rarity = def.rarity :: string,
		reduced = reduced,
		sections = blueprint.sections,
		foamRecoveryT = def.anim.foamRecoveryT,
	})
	local isLocal = entry.player == Players.LocalPlayer
	local pop: Spring.Spring<number>? = nil
	if equipPop then
		if not reduced then
			pop = Spring.new(HELD.popInFrom, HELD.popInOmega, HELD.popInZeta, 1)
		end
		local at = (hand.CFrame * weld.C0 * baseC1:Inverse()).Position
		local ok, err = pcall(function(): any
			equipPuffs(def, at, isLocal)
			return nil
		end)
		if not ok then
			log:warn("equip pop puffs failed:", err)
		end
	end
	entry.held = {
		model = model,
		squishyId = squishyId,
		def = def,
		character = character,
		humanoid = humanoid,
		hand = hand,
		weld = weld,
		baseC1 = baseC1,
		deformer = deformer,
		parts = parts,
		shadowParts = shadowParts,
		phase = rng:NextNumber(0, TAU),
		modifier = 0,
		shadowsOff = false,
		-- The own model animates at once (a hero); others wait for the next range pass.
		detail = if isLocal then "hero" else nil,
		resting = true,
		overlays = {},
		hiddenReasons = {},
		cleanup = c :: any,
		lobbyWeight = if HeldSquishyController.isLobbyPhase(entry.player:GetAttribute(ATTR_DUEL_PHASE)) then 1 else 0,
		rig = rig,
		out = SquishRig.newOut(),
		reduced = reduced,
		lastSpeed = nil,
		falling = false,
		pop = pop,
		popUntil = now + POP_MAX_SECONDS,
		oddFrame = rng:NextInteger(0, 1) == 1,
	}
	HeldSquishyController.HeldChanged:fire(entry.player, model)
end

local function cameraPosition(): Vector3
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

-- Builds, keeps or destroys one player's held model. Returns the hand distance to the camera (math.huge if none).
local function refresh(entry: Entry, from: Vector3): number
	local player = entry.player
	local isLocal = player == Players.LocalPlayer
	local character = player.Character
	local squishyId = equippedId(player)
	local hand, humanoid = nil, nil
	if character and character:IsDescendantOf(Workspace) then
		hand, humanoid = findHand(character)
	end
	if character == nil or hand == nil or humanoid == nil or squishyId == nil or not hand:IsDescendantOf(Workspace) then
		destroyHeld(entry)
		return math.huge
	end
	local distance = (hand.Position - from).Magnitude
	local held = entry.held
	local equipPop = false
	if held then
		local stale = held.character ~= character or held.hand ~= hand or held.squishyId ~= squishyId
		if stale or held.model.Parent == nil or (not isLocal and distance > HELD.destroyStuds) then
			-- §18.5.1 A7: only a new SD_Equipped on the same character and hand pops (not a respawn or a rebuild).
			equipPop = held.character == character and held.hand == hand and held.squishyId ~= squishyId
			destroyHeld(entry)
			held = nil
		end
	end
	if held == nil and (isLocal or distance <= HELD.buildStuds) then
		buildHeld(entry, character :: Model, hand :: BasePart, humanoid :: Humanoid, squishyId :: string, equipPop)
	end
	return distance
end

-- A held model's detail level (nil = it rests). The rig hears every change (a drop to near or far turns its sections
-- off, so the deformer writes their base C0 once; far also drops the face, blink and jiggle).
local function setDetail(held: Held, detail: SquishRig.Detail?)
	if held.detail == detail then
		return
	end
	held.detail = detail
	if detail then
		held.rig:setDetail(detail)
	end
end

-- Range pass: build/destroy by distance, then hand the rig budget to the closest on-screen models by detail level.
local function rangePass()
	local from = cameraPosition()
	local camera = Workspace.CurrentCamera
	local candidates: { Held } = {}
	local distances: { [Held]: number } = {}
	local localHeld: Held? = nil
	for _, entry in entries do
		local distance = refresh(entry, from)
		local held = entry.held
		if held then
			if entry.player == Players.LocalPlayer then
				localHeld = held
				continue
			end
			local onScreen = true
			if camera then
				local _, visible = camera:WorldToViewportPoint(held.hand.Position)
				onScreen = visible
			end
			if onScreen and distance <= BUDGET.deformingRigStuds then
				table.insert(candidates, held)
				distances[held] = distance
			else
				setDetail(held, nil)
			end
		end
	end
	table.sort(candidates, function(a: Held, b: Held): boolean
		return distances[a] < distances[b]
	end)
	if localHeld then
		table.insert(candidates, 1, localHeld) -- the own model always animates first
	end
	-- The hero rigs animating outside the held models (Inspect, the box reveal) come out of the budget first.
	rankedHeroes = HeroRigs.count()
	local total, near, ownHero = HeldSquishyController.rigBudget(MeshQuality.forCamera(camera), rankedHeroes)
	for rank, candidate in candidates do
		setDetail(candidate, HeldSquishyController.detailAt(rank, localHeld ~= nil, total, near, ownHero))
	end
	-- The slots left: the Collection displays first, then the lobby breathers (§18.9: both count in the budget at the
	-- lowest priority). setIdleSlots answers how many it uses.
	local left = total - math.min(#candidates, total)
	local _, ambient = HeldSquishyController.splitSlots(left, CollectionController.setIdleSlots(left))
	AmbientController.setBreatheSlots(ambient)
end

local function isDownOrSeated(held: Held): boolean
	local humanoid = held.humanoid
	return humanoid.Health <= 0 or humanoid.Sit
end

-- LocalTransparencyModifier on every part; while hidden also no shadows (the modifier alone keeps them, the way a
-- first-person character keeps its shadow). Writes only on a change.
local function setLook(held: Held, modifier: number, hidden: boolean)
	if held.modifier ~= modifier then
		held.modifier = modifier
		for _, part in held.parts do
			part.LocalTransparencyModifier = modifier
		end
	end
	if held.shadowsOff ~= hidden then
		held.shadowsOff = hidden
		for _, part in held.shadowParts do
			part.CastShadow = not hidden
		end
	end
end

-- One frame of the movement jiggle (§18.5.1 A6): kicks on the rig's feel jiggle from the root's horizontal speed
-- change and from a landing. `off` (ReducedMotion, or only the first-person overlay shows the rig: the design's toy
-- has no walk jiggle, spec 2026-10-11 §2) gives none and clears the state.
local function kickMotion(held: Held, off: boolean)
	local root = held.character:FindFirstChild(ROOT_PART)
	if off or root == nil or not root:IsA("BasePart") then
		held.lastSpeed = nil
		held.falling = false
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local last = held.lastSpeed
	local kick = if last then HeldSquishyController.jiggleKick(last, speed) else 0
	held.lastSpeed = speed
	local landed, falling = HeldSquishyController.landingStep(held.falling, velocity.Y)
	held.falling = falling
	if landed then
		kick += JIGGLE.landingImpulse
	end
	if kick > 0 then
		held.rig:kick(kick)
	end
end

-- Calls the first-person mirror (nil out = rest it), never letting its error stop the held models' frame.
local function callMirror(fn: Mirror, out: SquishRig.Out?, scale: Vector3)
	local ok, err = pcall(fn :: any, out, scale) -- no closure: this runs every frame
	if not ok then
		log:error("first-person mirror failed:", err)
	end
end

local function updateHeld(entry: Entry, held: Held, dt: number, now: number)
	local hidden = next(held.hiddenReasons) ~= nil or isDownOrSeated(held)
	local modifier = 0
	local isLocal = entry.player == Players.LocalPlayer
	if hidden then
		modifier = 1
	elseif isLocal then
		modifier = held.hand.LocalTransparencyModifier
	end
	setLook(held, modifier, hidden)
	local ownMirror = if isLocal then mirror else nil

	-- The idle crossfade follows the holder's phase even while the model rests, so a model that starts animating
	-- again shows the right idle at once.
	local lobbyTarget = if HeldSquishyController.isLobbyPhase(entry.player:GetAttribute(ATTR_DUEL_PHASE)) then 1 else 0
	held.lobbyWeight = HeldSquishyController.crossfade(held.lobbyWeight, lobbyTarget, dt, LOBBY_IDLE.crossfadeSeconds)

	if hidden or held.detail == nil then
		clearOverlays(held)
		held.pop = nil
		held.lastSpeed = nil
		held.falling = false
		if not held.resting then
			held.rig:reset()
			held.deformer:setTwistBase(held.baseC1)
			held.deformer:rest()
			held.resting = true
			if ownMirror then
				callMirror(ownMirror, nil, Vector3.one)
			end
		end
		return
	end

	local reduced = Tweens.reducedMotion()
	local rig, out = held.rig, held.out
	if reduced ~= held.reduced then
		held.reduced = reduced
		rig:setReduced(reduced)
	end
	local writeOwn, blink = HeldSquishyController.mirrorRule(modifier, ownMirror ~= nil)
	rig:setBlink(blink)
	kickMotion(held, reduced or not writeOwn)
	local busy = held.pop ~= nil or next(held.overlays) ~= nil
	local skip, odd = HeldSquishyController.farStride(held.detail, rig:isAwake(), busy, held.oddFrame)
	held.oddFrame = odd
	if skip then
		return -- a sleeping far rig: written every 2nd frame (farStride)
	end
	-- Before the step: an overlay's hold or face (the throw windup) shows in this frame, not the next.
	for name, overlay in held.overlays do
		local prepare = overlay.prepare
		if prepare then
			local ok, err = pcall(prepare :: any, dt, now) -- no closure: this runs every frame
			if not ok then
				log:error(`overlay {name} prepare failed and was removed:`, err)
				removeOverlay(held, name)
			end
		end
	end
	rig:step(dt, out)

	local scale, bob = HeldSquishyController.idleSample(now, held.phase, held.lobbyWeight, reduced)
	local pop = held.pop
	if pop and reduced then
		held.pop = nil -- ReducedMotion: no scale pop
	elseif pop then
		scale *= math.max(pop:step(dt), POP_MIN_SCALE)
		if pop:isSettled(POP_SETTLE) or now >= held.popUntil then
			held.pop = nil
		end
	end
	local twist = out.twist
	for name, overlay in held.overlays do
		local ok, overlayScale, overlayTwist, keep = pcall(overlay.step, dt, now, out)
		if not ok then
			log:error(`overlay {name} failed and was removed:`, overlayScale)
			removeOverlay(held, name)
			continue
		end
		scale *= overlayScale
		twist += overlayTwist
		if keep ~= true then
			removeOverlay(held, name)
		end
	end

	-- One write: the rig's frame times the idle and the overlays. The model moves +bob along its own Y (deferred:
	-- apply() writes Weld.C1 once, with the twist on top). In first person the overlay's mirror gets the same out and
	-- that scale, and writes its copy instead of the hidden own model (mirrorRule).
	HeldSquishyController.finishOut(out, scale, twist)
	if writeOwn then
		held.deformer:setTwistBase(CFrame.new(0, -bob, 0) * held.baseC1, true)
		held.deformer:apply(out)
	end
	if ownMirror then
		callMirror(ownMirror, out, scale)
	end
	held.resting = false
end

local function step(dt: number, now: number): boolean
	rangeTimer += dt
	-- A hero rig starting or stopping outside (Inspect, the box reveal) re-ranks on this frame, not up to
	-- rangeCheckSeconds later, so the held models make room for it at once.
	if rangeTimer >= RANGE_CHECK_SECONDS or HeroRigs.count() ~= rankedHeroes then
		rangeTimer = 0
		rangePass()
	end
	debug.profilebegin(PROFILE_RIGS)
	for _, entry in entries do
		local held = entry.held
		if held then
			if held.model.Parent == nil or held.weld.Parent == nil then
				destroyHeld(entry) -- destroyed from outside; rebuilt on the next range pass
			else
				updateHeld(entry, held, dt, now)
			end
		end
	end
	debug.profileend()
	return true
end

local function track(player: Player)
	if entries[player] then
		return
	end
	local c = Cleanup.new()
	local entry: Entry = { player = player, cleanup = c :: any, held = nil }
	entries[player] = entry
	local function refreshNow()
		if entries[player] == entry then
			refresh(entry, cameraPosition())
		end
	end
	c:add(player:GetAttributeChangedSignal(ATTR_EQUIPPED):Connect(refreshNow))
	-- The hand may not have replicated yet; the next range pass (<= RANGE_CHECK_SECONDS) builds it then.
	c:add(player.CharacterAdded:Connect(refreshNow))
	c:add(player.CharacterRemoving:Connect(function()
		destroyHeld(entry)
	end))
	c:add(function()
		destroyHeld(entry)
	end)
end

local function untrack(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	entries[player] = nil
	entry.cleanup:clean()
end

-- Public: pure helpers (unit-tested; §18.5.1 A6) ---------------------------------------------------------------------

-- True when a holder's SD_DuelPhase means the lobby ("" or unset): the lobby idle applies.
function HeldSquishyController.isLobbyPhase(phase: unknown): boolean
	return phase == nil or phase == ""
end

-- Moves the lobby/duel idle weight toward `target` (0 or 1) at a rate that crosses the whole way in `seconds`.
function HeldSquishyController.crossfade(weight: number, target: number, dt: number, seconds: number): number
	if not (seconds > 0) then
		return target
	end
	local stepSize = math.max(dt, 0) / seconds
	if weight < target then
		return math.min(target, weight + stepSize)
	end
	return math.max(target, weight - stepSize)
end

-- The idle at clock `now` for a model with random `phase`: the duel idle (Config.Anim.held: idlePeriodSeconds,
-- idleAmpY, idleAmpXZ, bobStuds) and the lobby idle (held.lobbyIdle), each on its own clock, blended by `lobbyWeight`
-- (0 = duel, 1 = lobby); × REDUCED_IDLE under ReducedMotion. Returns the scale (S.Y = 1 + ampY·sin φ,
-- S.X = S.Z = 1 - ampXZ·sin φ) and the bob (studs, at φ + π/2).
function HeldSquishyController.idleSample(
	now: number,
	phase: number,
	lobbyWeight: number,
	reduced: boolean
): (Vector3, number)
	local w = math.clamp(lobbyWeight, 0, 1)
	local phiDuel = TAU * now / HELD.idlePeriodSeconds + phase
	local phiLobby = TAU * now / LOBBY_IDLE.periodSeconds + phase
	local sDuel, sLobby = math.sin(phiDuel), math.sin(phiLobby)
	local y = (1 - w) * HELD.idleAmpY * sDuel + w * LOBBY_IDLE.ampY * sLobby
	local xz = (1 - w) * HELD.idleAmpXZ * sDuel + w * LOBBY_IDLE.ampXZ * sLobby
	local bob = (1 - w) * HELD.bobStuds * math.sin(phiDuel + math.pi / 2)
		+ w * LOBBY_IDLE.bobStuds * math.sin(phiLobby + math.pi / 2)
	if reduced then
		y, xz, bob = y * REDUCED_IDLE, xz * REDUCED_IDLE, bob * REDUCED_IDLE
	end
	return Vector3.new(1 - xz, 1 + y, 1 - xz), bob
end

-- The phase that makes idleSample(now, phase, 1, false) show the lobby breath `amount` (S.Y = 1 + lobbyIdle.ampY ×
-- amount, -1 to 1) on its rising side (or falling): Inspect goes on from the box reveal's breath this way
-- (IdleRig:breathNow), so the shape never jumps at the hand-off.
function HeldSquishyController.lobbyPhaseFor(amount: number, rising: boolean, now: number): number
	local angle = math.asin(math.clamp(if amount == amount then amount else 0, -1, 1))
	return (if rising then angle else math.pi - angle) - TAU * now / LOBBY_IDLE.periodSeconds
end

-- The jiggle kick of a horizontal speed change between two frames: clamp(|Δspeed| · perSpeed, 0, maxImpulse).
function HeldSquishyController.jiggleKick(lastSpeed: number, speed: number): number
	local delta = math.abs(speed - lastSpeed)
	if delta ~= delta then
		return 0
	end
	return math.clamp(delta * JIGGLE.perSpeed, 0, JIGGLE.maxImpulse)
end

-- Landing detection: `falling` turns on once vy <= landingFromVy; a landing is vy >= landingToVy after that.
-- Returns (landed, falling).
function HeldSquishyController.landingStep(falling: boolean, vy: number): (boolean, boolean)
	if vy ~= vy then
		return false, falling
	end
	if vy <= JIGGLE.landingFromVy then
		return false, true
	end
	if falling and vy >= JIGGLE.landingToVy then
		return true, false
	end
	return false, falling
end

-- The rig budget for a mesh quality (spec §3.2 detail levels, §5) while `heroes` (default 0) hero rigs animate outside
-- the held models (the Inspect model, the box reveal: Anim/HeroRigs): (the deforming rigs left for the held models, the
-- near ones, whether the own model may still be a hero). The outside heroes take their slots first, inside
-- deformingRigs and heroRigs; "Low", or nil in the first frames (MeshQuality.forCamera), is the phone tier.
function HeldSquishyController.rigBudget(quality: string?, heroes: number?): (number, number, boolean)
	local high = quality == "High"
	local total = if high then BUDGET.deformingRigs else BUDGET.deformingRigsLow
	local heroCap = if high then BUDGET.heroRigs else BUDGET.heroRigsLow
	local outside = math.clamp(math.floor(heroes or 0), 0, total)
	return total - outside, if high then BUDGET.nearRigs else BUDGET.nearRigsLow, outside < heroCap
end

-- The detail level of the `rank`-th held model in budget order (the own model first when `own`, then the others by
-- distance): the own model "hero" (or, when `ownHero` is false, the first of the `near` "near" ones), the next ones
-- up to `near` "near", the rest up to `total` "far", none (nil) beyond.
function HeldSquishyController.detailAt(
	rank: number,
	own: boolean,
	total: number,
	near: number,
	ownHero: boolean?
): SquishRig.Detail?
	if rank > total then
		return nil
	end
	local demoted = own and ownHero == false
	if own and rank == 1 then
		return if demoted then "near" else "hero"
	end
	local other = if own then rank - 1 else rank
	return if other <= (if demoted then near - 1 else near) then "near" else "far"
end

-- The far stride (rig speed-up pass): a "far" model whose rig sleeps (SquishRig isAwake false: only the idle moves it,
-- at most about 0.002 studs a frame, 0.15 px at 10 studs) and that runs no overlay or equip pop is stepped and written
-- every 2nd frame; `odd` is the model's frame parity (random at build, so half the far models write on each frame). Any
-- input wakes the rig at once, so it is stepped that very frame with that frame's dt: no timing point moves. A sleeping
-- far rig has no clock that shows (no blinks at far). Returns (skip this frame, the next parity).
function HeldSquishyController.farStride(
	detail: SquishRig.Detail?,
	awake: boolean,
	busy: boolean,
	odd: boolean
): (boolean, boolean)
	if detail ~= "far" or awake or busy then
		return false, odd
	end
	return not odd, not odd
end

-- The `left` rig slots the held models leave, split (spec §3.2): the Collection displays first, the rest to the lobby
-- breathers; nothing counted twice. `collectionAnswer` is what CollectionController.setIdleSlots(left) answered: the
-- slots it uses, or no number (then it may use up to Config.Inspect.Collection.idleMax). Returns (collection, ambient).
function HeldSquishyController.splitSlots(left: number, collectionAnswer: unknown): (number, number)
	local slots = math.max(0, if left == left then math.floor(left) else 0)
	local used = if type(collectionAnswer) == "number" and collectionAnswer == collectionAnswer
		then collectionAnswer
		else COLLECTION_IDLE_MAX
	local collection = math.clamp(math.floor(used), 0, slots)
	return collection, slots - collection
end

-- First person (spec 2026-10-10 §3.4): (write the own model, blink) for the own hand's LocalTransparencyModifier and
-- whether a mirror is set. While the overlay mirrors it and Roblox hides the hand, the hidden own model is not written
-- (the mirror's writes replace its, net cost about zero); it blinks while its hand shows or while mirrored.
function HeldSquishyController.mirrorRule(modifier: number, mirrored: boolean): (boolean, boolean)
	local handHidden = modifier >= HIDDEN_MODIFIER
	return not (mirrored and handHidden), mirrored or not handHidden
end

-- A frame's last step: the rig's out.S times `scale` (the idle × the equip pop × the overlays) and `twist` on top. The
-- first-person mirror gets `scale` with the out, so the overlay shows the rig's own S (out.S / scale).
function HeldSquishyController.finishOut(out: SquishRig.Out, scale: Vector3, twist: number)
	out.S *= scale
	out.twist = twist
end

-- Public

-- Weld C0 for a hand (§9.5): its RightGripAttachment.CFrame; without one, the stock attachment's frame at the bottom
-- of the hand (same -90° X turn), so the held model faces the same way on every rig.
function HeldSquishyController.gripC0(hand: BasePart): CFrame
	local grip = hand:FindFirstChild(GRIP_ATTACHMENT)
	if grip and grip:IsA("Attachment") then
		return grip.CFrame
	end
	return CFrame.new(0, -hand.Size.Y / 2, 0) * STOCK_GRIP_ROTATION
end

-- The held model of a player (nil when none is shown).
function HeldSquishyController.getModel(player: Player): Model?
	local entry = entries[player]
	local held = entry and entry.held
	return if held then held.model else nil
end

-- The squishy id of a player's held model (nil when none is shown).
function HeldSquishyController.getSquishyId(player: Player): string?
	local entry = entries[player]
	local held = entry and entry.held
	return if held then held.squishyId else nil
end

-- True while the player has a visible held model (drives the hold pose).
function HeldSquishyController.isHolding(player: Player): boolean
	local entry = entries[player]
	local held = entry and entry.held
	if held == nil then
		return false
	end
	return next(held.hiddenReasons) == nil and not isDownOrSeated(held)
end

-- Adds (or replaces) a named overlay on the player's held model; nil removes it. Returns false when no model is held.
function HeldSquishyController.setOverlay(player: Player, name: string, overlay: Overlay?): boolean
	local entry = entries[player]
	local held = entry and entry.held
	if held == nil then
		return false
	end
	removeOverlay(held, name)
	if overlay then
		held.overlays[name] = overlay
	end
	return true
end

-- Hides the held model while any reason is set (e.g. "thrown" in Part 4).
function HeldSquishyController.setHidden(player: Player, reason: string, hidden: boolean)
	local entry = entries[player]
	local held = entry and entry.held
	if held then
		if hidden then
			held.hiddenReasons[reason] = true
		else
			held.hiddenReasons[reason] = nil
		end
	end
end

-- The rig of the player's held model while it animates (nil otherwise; spec 2026-10-09 §3.2). Other controllers act
-- through it (tap, press / release, hold / clearHold, kick, hit, setFace); this controller is its only owner and the
-- only one that steps it. A rebuilt model has a new rig: ask again, never keep it.
function HeldSquishyController.getRig(player: Player): SquishRig.Rig?
	local entry = entries[player]
	local held = entry and entry.held
	return if held and held.detail ~= nil then held.rig else nil
end

-- A one-shot reaction on the player's held model (spec §3.2): "hit" = the squish face for Config.Anim.rig.face.
-- hitSeconds and the hit boing (a squash peaking at rig.hitKick × strength whatever the feel); "land" = a landing kick
-- (held.motionJiggle.landingImpulse × strength). Strength 0-1, default 1. Nothing while the model does not animate.
-- Every call fires Reacted(player, kind, strength or 1), with or without an animating model (the first-person hand's
-- flinch, spec 2026-10-10 §3.3).
function HeldSquishyController.react(player: Player, kind: "hit" | "land", strength: number?)
	local rig = HeldSquishyController.getRig(player)
	if rig then
		if kind == "hit" then
			rig:hit(strength)
		elseif kind == "land" then
			local s = if strength ~= nil and strength == strength then math.max(strength, 0) else 1
			rig:kick(JIGGLE.landingImpulse * s)
		end
	end
	HeldSquishyController.Reacted:fire(player, kind, if strength ~= nil then strength else 1)
end

-- Sets (or with nil clears) the local player's first-person mirror (spec 2026-10-10 §3.4): made once by
-- ViewmodelController when its overlay shows, called every frame with the own model's final out and the scale on top
-- of the rig's (finishOut), and with (nil, Vector3.one) once when the model hides. `fx` draws the own effects on the
-- overlay's toy (mirrorFx); clearing the mirror clears it.
function HeldSquishyController.setMirror(fn: Mirror?, fx: MirrorFx?)
	assert(fn == nil or type(fn) == "function", "[SD][Held] the mirror must be a function or nil")
	assert(fx == nil or type(fx) == "function", "[SD][Held] the mirror fx must be a function or nil")
	mirror = fn
	mirrorFx = if fn then fx else nil
end

-- Hands an own effect to the first-person overlay while it mirrors the rig: the own model is hidden then, so world
-- particles at it would float in the air. True when the overlay took it (an error in it is logged, still true).
function HeldSquishyController.mirrorFx(kind: string, count: number, colour: Color3): boolean
	local fx = mirrorFx
	if mirror == nil or fx == nil then
		return false
	end
	local ok, err = pcall(fx :: any, kind, count, colour)
	if not ok then
		log:error("first-person mirror fx failed:", err)
	end
	return true
end

-- True while a first-person mirror is set (the local player's overlay shows their rig): ThrowController then leaves
-- the windup hold off (spec 2026-10-11 §3.5).
function HeldSquishyController.isMirrored(): boolean
	return mirror ~= nil
end

-- Small table for Studio debug hooks and tests.
function HeldSquishyController.debugState(): { [string]: any }
	local players: { [string]: any } = {}
	local count = 0
	local tiers = { hero = 0, near = 0, far = 0, none = 0 }
	for player, entry in entries do
		local held = entry.held
		if held then
			count += 1
			local tier = held.detail or "none"
			tiers[tier] += 1
			local overlayNames = {}
			for name in held.overlays do
				table.insert(overlayNames, name)
			end
			players[player.Name] = {
				squishyId = held.squishyId,
				placeholder = SquishyCache.isPlaceholder(held.model),
				hidden = held.modifier >= 1,
				animating = held.detail ~= nil,
				detail = tier,
				face = held.out.face,
				parts = #held.parts,
				overlays = overlayNames,
				massless = held.model.PrimaryPart ~= nil and (held.model.PrimaryPart :: BasePart).Massless,
			}
		end
	end
	return { count = count, players = players, tiers = tiers }
end

-- Lifecycle

function HeldSquishyController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Players.PlayerAdded:Connect(track))
	c:add(Players.PlayerRemoving:Connect(untrack))
	for _, player in Players:GetPlayers() do
		track(player)
	end
	c:add(Scheduler.add(step, "render"))
	c:add(function()
		for player in table.clone(entries) do
			untrack(player)
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function HeldSquishyController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return HeldSquishyController
