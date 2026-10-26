--!strict
-- Killcam (client only). Killcam step 1 (2026-10-26; owner: "Yes, build step 1 of the killcam like that."; "Add it on
-- top", "Two steps": this is step 1, the replay; step 2 adds the screen pieces: the bars, the pills, FINAL KILL, the
-- killer's card, the SQUISHED! stamp and the sounds; `K:n` = Diego's uploads/match-stage.html line n, `S:n` = his
-- "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html"): the match's final squish again, through the killer's eyes
-- (K:397-534). Every number is Config.UI.Match.finish.killcam's (CFG below).
-- * The tape (K:403-419 record): MatchHudController's session keeps one (tape(deps); none in a Studio preview) and
--   records it each frame at tape.hz, the last tape.keep seconds, in server time (the time ProjectileRenderer draws
--   the throws by): each match player's root and head CFrames, its R15 joints' Transforms (PodiumPoses.JOINTS: Motor6Ds
--   or AnimationConstraints), where its held squishy is (deps.held: shown and in the hand), and the match throws in
--   flight (deps.flying). It stops `after` past the final squish, or at once at an end with no killcam.
-- * new(spec, tape, deps) -> Replay? (K:452-465): the window from `before` before the final squish (outcome.finalKo.at)
--   to `after` after it (window, pure); nil when nobody made the squish (the storm, a fall), the killer or the victim is
--   not on the tape then (streamed out), or the tape has less than minBefore before it. The tape stops there.
-- * The scene: a copy of every other player's character on the tape (MatchPodium's copies; the killer's own is not
--   drawn: the camera is in its head, K:506), posed each frame from the tape (lerped between samples), each with its
--   squishy where the tape had it held; the throws in flight as squishies; the real characters and held squishies
--   hidden on this screen (LocalTransparencyModifier, written each frame, put back at the end), the first-person hands
--   away (deps.setAway).
-- * Speed (K:500-507, speed(): pure): full speed, slowing to x0.22 round the squish, full again; the squish freezes for
--   `freeze` (the hit-stop), then it plays out to the window's end.
-- * The camera (K:478-490): at the killer's head (+ forward), looking ahead at the victim's height and turning onto the
--   victim by the throw (lookWeight: pure), leaning toward the killer's toy in flight; FOV 72 -> 54 round the squish ->
--   66, + the squish's punch (fov: pure). The squish jolts it (settings' camera shake on, no ReducedMotion).
-- * The arm (K:434-448, 491-498, armPoints: pure): the killer's own right avatar arm (Anim/OwnArm; owner 2026-10-11:
--   first-person arms are the player's own) at the bottom right, bobbing with the killer's walk, punching forward at
--   each of its throws, its squishy on the fist while the tape has it held.
-- * The squish (K:200-207, 519-523 hitFx(..., 1.7)): sparks, a white ring facing the camera, a ring on the floor in the
--   victim's colour, a warm light, the jolt, and our own kill effect (Anim/KillVfx: the killer's kill set) at the
--   victim.
-- * skip() ends it (K:527, S:872); done() is true from the window's end; destroy() puts everything back.
-- * Killcam step 2 (2026-10-26): spec.onEvent tells the screen pieces (UI/Match/KillcamScreen) its moments: "slow"
--   { on } when it slows or speeds up again (K:524: frozen, or under x0.9), "throw" at each of the killer's throws
--   (K:471), "impact" { at } at the squish: the victim's root + victimUp (K:522).
-- Pure (unit-tested): smooth(x), speed(d), lookWeight(t, t0, throwAt), fov(d, punch), length(), bracket(frames, t),
-- window(frames, ko), armPoints(bob, amp, push, lift).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local KillStyle = require(Shared.Art.KillStyle)
local Palette = require(Shared.Art.Palette)

local Client = script.Parent.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local FxShapes = require(Client.Anim.FxShapes)
local KillVfx = require(Client.Anim.KillVfx)
local OwnArm = require(Client.Anim.OwnArm)
local PodiumPoses = require(Client.Anim.PodiumPoses)
local SquishyCache = require(Client.Models.SquishyCache)
local MatchPodium = require(script.Parent.MatchPodium)

-- Types

export type Flying = { id: number, squishyId: string, scale: number, at: CFrame, thrower: number }
export type Body = { root: CFrame, head: CFrame, joints: { [string]: CFrame }, held: CFrame? }
export type Frame = { t: number, bodies: { [number]: Body }, flying: { Flying } }
export type Window = { t0: number, t1: number, hit: number, throwAt: number, throws: { number } }

-- MatchHudController's: the camera, the held squishies, the hands and the throws (controllers a UI module may not
-- require).
export type Deps = {
	saveCamera: () -> any,
	restoreCamera: (snapshot: any) -> (),
	setHeldHidden: (player: Player, hidden: boolean) -> (),
	setAway: (on: boolean) -> (),
	held: (player: Player) -> Model?, -- the squishy shown in the player's hand now, or nil
	flying: () -> { Flying },
}

export type Tape = {
	frames: { Frame },
	record: (self: Tape, view: any, now: number) -> (),
	stop: (self: Tape) -> (),
}

export type Spec = {
	view: any, -- the Result freeze
	ko: any, -- its outcome.finalKo (Types.MatchEventView: at, by, victim)
	who: (userId: number) -> any, -- MatchKit.who
	preview: boolean,
	reduced: boolean,
	shake: boolean, -- settings' camera shake
	onEvent: ((name: string, data: { [string]: any }) -> ())?, -- killcam step 2 (header)
}

export type Replay = {
	step: (self: Replay, now: number) -> (),
	skip: (self: Replay) -> (),
	done: (self: Replay) -> boolean,
	destroy: (self: Replay) -> (),
}

type Source = { model: Model, root: BasePart, head: BasePart, joints: { [string]: any }, player: Player? }

type Copy = {
	userId: number,
	model: Model,
	root: BasePart?,
	height: number, -- its root over its feet
	joints: { [string]: any },
	toy: Model?,
	shown: boolean,
}

-- Constants

local CFG = Config.UI.Match.finish.killcam
local CAM = CFG.camera
local ARM = CFG.arm
local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)
local BOTS_FOLDER = "SD_Bots" -- BotService: the match bots' rigs
local STAR_KEY = "img.podium.star" -- round B2's star picture: the sparks
local FIRST_REAL_ID = 1 -- bots and the Studio fixtures' pretend players have ids below this
local RESOLVE_SECONDS = 1 -- the tape looks the players' characters up again this often
local STOP_GRACE = 0.25 -- the tape records this long past the window's end

-- Module table

local Killcam = {}

-- Public: pure ----------------------------------------------------------------------------------------------------

function Killcam.smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

-- K:444-449 rsp(d): the replay's speed d seconds from the squish.
function Killcam.speed(d: number): number
	local S = CFG.speed
	if d < S.a then
		return 1
	elseif d < S.b then
		return 1 - (1 - S.slow) * Killcam.smooth((d - S.a) / (S.b - S.a))
	elseif d < S.c then
		return S.slow
	elseif d < S.d then
		return S.slow + (1 - S.slow) * Killcam.smooth((d - S.c) / (S.d - S.c))
	end
	return 1
end

-- K:483: how far the look has turned from straight ahead onto the victim at tape time t.
function Killcam.lookWeight(t: number, t0: number, throwAt: number): number
	return CAM.lookFrom + (1 - CAM.lookFrom) * Killcam.smooth((t - t0) / math.max(1 / 60, throwAt - t0))
end

-- K:489: the FOV d seconds from the squish, with the squish's punch (1 at the squish, fading).
function Killcam.fov(d: number, punch: number): number
	local F = CAM.fov
	local base = if d < F.nearFrom then F.far elseif d < F.afterFrom then F.near else F.after
	return base + punch * CAM.punch
end

-- The real seconds a whole window plays for, the freeze included.
function Killcam.length(): number
	local dt = 1 / 600
	local t, total = -CFG.before, CFG.freeze
	while t < CFG.after do
		t += dt * Killcam.speed(t)
		total += dt
	end
	return total
end

-- The samples round tape time t: frames[a] at or before it, frames[b] after it, and how far between (0..1).
function Killcam.bracket(frames: { Frame }, t: number): (number, number, number)
	local n = #frames
	if n == 0 then
		return 0, 0, 0
	elseif t <= frames[1].t then
		return 1, 1, 0
	elseif t >= frames[n].t then
		return n, n, 0
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if frames[mid].t <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = frames[lo].t, frames[hi].t
	return lo, hi, if b > a then (t - a) / (b - a) else 0
end

-- K:452-458: the window on the tape for the final squish `ko` (header), or nil. throwAt = the start of the killer's last
-- throw before the squish (K:457); throws = the killer's throws starting inside the window (each punches the arm).
function Killcam.window(frames: { Frame }, ko: any): Window?
	if type(ko) ~= "table" or type(ko.at) ~= "number" or ko.by == nil or ko.victim == nil or #frames == 0 then
		return nil
	end
	local hit = ko.at
	local first = frames[1].t
	if hit - first < CFG.minBefore then
		return nil
	end
	local a = Killcam.bracket(frames, hit)
	local bodies = frames[a].bodies
	if bodies[ko.by] == nil or bodies[ko.victim] == nil then
		return nil
	end
	local t0 = math.max(first, hit - CFG.before)
	local seen: { [number]: boolean } = {}
	local throws: { number } = {}
	local lastThrow: number? = nil
	for _, f in frames do
		if f.t > hit then
			break
		end
		for _, fly in f.flying do
			if fly.thrower == ko.by and not seen[fly.id] then
				seen[fly.id] = true
				lastThrow = f.t
				if f.t > t0 then
					table.insert(throws, f.t)
				end
			end
		end
	end
	return {
		t0 = t0,
		t1 = math.max(hit, math.min(frames[#frames].t, hit + CFG.after)),
		hit = hit,
		throwAt = math.max(t0, lastThrow or (hit - CFG.throwBefore)),
		throws = throws,
	}
end

-- K:434-448, 491-498: the arm's fist, the far end of its sleeve and its toy in the camera's space, and the arm's turn
-- (bob: the walk's phase; amp: the walk's share; push, lift: the throw's punch, studs).
function Killcam.armPoints(bob: number, amp: number, push: number, lift: number): (Vector3, Vector3, Vector3, CFrame)
	local B = ARM.bob
	local origin = ARM.at + Vector3.new(math.sin(bob) * B.x * amp, math.abs(math.cos(bob)) * B.y * amp + lift, -push)
	local turn = CFrame.Angles(-push * ARM.throw.turn, 0, 0) * CFrame.Angles(0, ARM.yaw, 0)
	return origin + turn * ARM.hand, origin + turn * ARM.shoulder, origin + turn * ARM.toy, turn
end

-- Private ---------------------------------------------------------------------------------------------------------

local function jointsOf(model: Model): { [string]: any }
	local out: { [string]: any } = {}
	for name, path in PodiumPoses.JOINTS do
		local holder = model:FindFirstChild(path[1])
		local motor = holder and holder:FindFirstChild(path[2])
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			out[name] = motor
		end
	end
	return out
end

-- A body between two samples (nil when the first has none).
local function bodyAt(userId: number, a: Frame, b: Frame, u: number): Body?
	local A = a.bodies[userId]
	if A == nil then
		return nil
	end
	local B = b.bodies[userId] or A
	local joints: { [string]: CFrame } = {}
	for name, cf in A.joints do
		joints[name] = cf:Lerp(B.joints[name] or cf, u)
	end
	local held: CFrame? = nil
	if A.held then
		held = if B.held then A.held:Lerp(B.held, u) else A.held
	end
	return { root = A.root:Lerp(B.root, u), head = A.head:Lerp(B.head, u), joints = joints, held = held }
end

-- The killer's toy in flight between two samples (its latest throw), or nil.
local function toyOf(killerId: number, a: Frame, b: Frame, u: number): Vector3?
	local found: Flying? = nil
	for _, fly in a.flying do
		if fly.thrower == killerId and (found == nil or fly.id > found.id) then
			found = fly
		end
	end
	if found == nil then
		return nil
	end
	for _, other in b.flying do
		if other.id == found.id then
			return found.at.Position:Lerp(other.at.Position, u)
		end
	end
	return found.at.Position
end

-- Public ----------------------------------------------------------------------------------------------------------

function Killcam.tape(deps: Deps): Tape
	local frames: { Frame } = {}
	local sources: { [number]: Source } = {}
	local resolvedAt = -math.huge
	local last = -math.huge
	local stopped = false
	local tape = {}
	tape.frames = frames

	local function resolve(view: any)
		table.clear(sources)
		for _, p in (view.players or {}) :: { any } do
			local model = MatchPodium.sourceCharacter(view, false, p.userId)
			local root = model and model:FindFirstChild("HumanoidRootPart")
			local head = model and model:FindFirstChild("Head")
			if model and root and root:IsA("BasePart") and head and head:IsA("BasePart") then
				sources[p.userId] = {
					model = model,
					root = root,
					head = head,
					joints = jointsOf(model),
					player = if p.userId >= FIRST_REAL_ID then Players:GetPlayerByUserId(p.userId) else nil,
				}
			end
		end
	end

	function tape.record(_self: any, view: any, now: number)
		if stopped or type(view) ~= "table" then
			return
		end
		local outcome = view.outcome
		if outcome then
			local ko = outcome.finalKo
			if type(ko) ~= "table" or ko.by == nil or type(ko.at) ~= "number" or now > ko.at + CFG.after + STOP_GRACE then
				stopped = true
				return
			end
		end
		if now - last < 1 / CFG.tape.hz then
			return
		end
		last = now
		local clock = os.clock()
		if clock - resolvedAt >= RESOLVE_SECONDS then
			resolvedAt = clock
			resolve(view)
		end
		local bodies: { [number]: Body } = {}
		for userId, s in sources do
			if s.model:IsDescendantOf(Workspace) then
				local joints: { [string]: CFrame } = {}
				for name, motor in s.joints do
					joints[name] = motor.Transform
				end
				local held = if s.player then deps.held(s.player) else nil
				bodies[userId] = {
					root = s.root.CFrame,
					head = s.head.CFrame,
					joints = joints,
					held = if held then held:GetPivot() else nil,
				}
			end
		end
		table.insert(frames, { t = now, bodies = bodies, flying = deps.flying() })
		while #frames > 1 and frames[1].t < now - CFG.tape.keep do
			table.remove(frames, 1)
		end
	end

	function tape.stop(_self: any)
		stopped = true
	end

	return tape :: any
end

function Killcam.new(spec: Spec, tape: Tape, deps: Deps): Replay?
	local frames = tape.frames
	local ko = spec.ko
	local win = Killcam.window(frames, ko)
	if win == nil then
		return nil
	end
	tape:stop()
	local view = spec.view
	local killerId: number, victimId: number = ko.by, ko.victim
	local camera = Workspace.CurrentCamera
	local fx = FxPool.default()
	local rng = Random.new()

	-- What this screen hides (header), and what it was.
	local hidden: { [Instance]: number } = {}
	local switched: { [Instance]: boolean } = {}
	local targets: { Instance } = {}
	local heldHidden: { Player } = {}
	local function list(root: Instance)
		table.insert(targets, root)
		for _, d in root:GetDescendants() do
			table.insert(targets, d)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			list(player.Character)
		end
		deps.setHeldHidden(player, true)
		table.insert(heldHidden, player)
	end
	local bots = Workspace:FindFirstChild(BOTS_FOLDER)
	if bots then
		for _, rig in bots:GetChildren() do
			if rig:IsA("Model") then
				list(rig)
			end
		end
	end
	local function hideAll()
		for _, d in targets do
			if d.Parent == nil then
				continue
			end
			if d:IsA("BasePart") or d:IsA("Decal") then
				if hidden[d] == nil then
					hidden[d] = (d :: any).LocalTransparencyModifier
				end
				if (d :: any).LocalTransparencyModifier < 1 then
					(d :: any).LocalTransparencyModifier = 1
				end
			elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("LayerCollector") then
				if switched[d] == nil then
					switched[d] = (d :: any).Enabled
				end
				if (d :: any).Enabled then
					(d :: any).Enabled = false
				end
			end
		end
	end

	-- The copies: everyone on the tape in the window but the killer.
	local folder = Instance.new("Folder")
	folder.Name = "SD_Killcam"
	folder.Parent = Workspace
	local ids: { [number]: boolean } = {}
	for _, f in frames do
		if f.t >= win.t0 and f.t <= win.t1 then
			for userId in f.bodies do
				ids[userId] = true
			end
		end
	end
	local copies: { Copy } = {}
	local heights: { [number]: number } = {}
	for userId in ids do
		if userId == killerId then
			continue
		end
		local source = MatchPodium.sourceCharacter(view, spec.preview, userId)
		local model = if source then MatchPodium.copyCharacter(source) else nil
		if model == nil then
			continue
		end
		model.Name = "Player_" .. tostring(userId)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local height = if humanoid and root then humanoid.HipHeight + root.Size.Y / 2 else 3
		heights[userId] = height
		local who = spec.who(userId)
		local toy: Model? = nil
		if who and Catalog.get(who.squishyId) then
			local ok, made = pcall(SquishyCache.clone, who.squishyId, "World")
			toy = if ok then made else nil
		end
		table.insert(copies, {
			userId = userId,
			model = model,
			root = root,
			height = height,
			joints = jointsOf(model),
			toy = toy,
			shown = false,
		})
	end

	-- The throws in flight, one squishy each.
	local flights: { [number]: Model } = {}
	local function flightModel(fly: Flying): Model?
		local m = flights[fly.id]
		if m == nil then
			local ok, made = pcall(SquishyCache.clone, fly.squishyId, "World", fly.scale)
			if not ok or made == nil then
				return nil
			end
			m = made
			flights[fly.id] = made
		end
		return m
	end

	-- The killer's arm and its squishy.
	local killerSource = MatchPodium.sourceCharacter(view, spec.preview, killerId)
	-- Its scale: the lower arm as wide as Diego's sleeve (OwnArm draws the hand handWidthDu wide; a rig with small hands
	-- would get a huge arm at the hand's scale, found in a real match with the bots).
	local u = ARM.studsPerDu
	local rightHand = killerSource and killerSource:FindFirstChild("RightHand")
	local rightLower = killerSource and killerSource:FindFirstChild("RightLowerArm")
	if rightHand and rightLower and rightHand:IsA("BasePart") and rightLower:IsA("BasePart") and rightLower.Size.X > 0 then
		u = ARM.sleeve * rightHand.Size.X / (Config.FirstPerson.ownArms.handWidthDu * rightLower.Size.X)
	end
	local arms = if killerSource then (OwnArm.make(killerSource, folder, u)) else nil
	if arms then
		for _, part in arms.left.parts do
			part:Destroy()
		end
		for _, part in arms.right.parts do
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	local armFrames: { [string]: CFrame } = {}
	local killerWho = spec.who(killerId)
	local killerDef = if killerWho then Catalog.get(killerWho.squishyId) else nil
	local armToy: Model? = nil
	if killerDef then
		local ok, made = pcall(SquishyCache.clone, (killerWho :: any).squishyId, "World", ARM.toyScale)
		armToy = if ok then made else nil
	end
	hideAll() -- after the arm: OwnArm reads the killer's real arm

	-- The camera.
	local snapshot = deps.saveCamera()
	deps.setAway(true)
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = folder
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = anchor

	-- The timeline (tape time t, from the window's start).
	local t = win.t0
	local frozen = 0
	local hitDone = false
	local punch, kickAmp = 0, 0
	local look: Vector3? = nil
	local fovNow = CAM.fov.far
	local bob, swing = 0, 0
	local lastRoot: Vector3? = nil
	local lastNow: number? = nil
	local ended, finished = false, false
	local slowed = false
	local function emit(name: string, data: { [string]: any })
		local fn = spec.onEvent
		if fn then
			fn(name, data)
		end
	end

	local function apply(at: number): (Frame, Frame, number)
		local ia, ib, u = Killcam.bracket(frames, at)
		local a, b = frames[ia], frames[ib]
		for _, c in copies do
			local body = bodyAt(c.userId, a, b, u)
			local show = body ~= nil
			if show ~= c.shown then
				c.shown = show
				c.model.Parent = if show then folder else nil
			end
			if body then
				if c.root then
					c.root.CFrame = body.root
				end
				for name, motor in c.joints do
					local cf = body.joints[name]
					if cf then
						motor.Transform = cf
					end
				end
			end
			local toy = c.toy
			if toy then
				local heldAt = if body then body.held else nil
				if heldAt then
					toy.Parent = folder
					toy:PivotTo(heldAt)
				else
					toy.Parent = nil
				end
			end
		end
		local seen: { [number]: boolean } = {}
		for _, fly in a.flying do
			local m = flightModel(fly)
			if m then
				seen[fly.id] = true
				local cf = fly.at
				for _, other in b.flying do
					if other.id == fly.id then
						cf = fly.at:Lerp(other.at, u)
						break
					end
				end
				m.Parent = folder
				m:PivotTo(cf)
			end
		end
		for id, m in flights do
			if not seen[id] then
				m.Parent = nil
			end
		end
		return a, b, u
	end

	local function aim(rdt: number, snap: boolean, a: Frame, b: Frame, u: number)
		local K = bodyAt(killerId, a, b, u)
		if K == nil then
			return
		end
		local flat = Vector3.new(K.root.LookVector.X, 0, K.root.LookVector.Z)
		local fw = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local eye = K.head.Position + fw * CAM.forward
		local target = eye + fw * CAM.far
		local V = bodyAt(victimId, a, b, u)
		if V then
			local vc = V.root.Position + Vector3.new(0, CAM.victimUp, 0)
			target = Vector3.new(target.X, vc.Y, target.Z):Lerp(vc, Killcam.lookWeight(t, win.t0, win.throwAt))
		end
		if t > win.throwAt and t < win.hit then
			local toyAt = toyOf(killerId, a, b, u)
			if toyAt then
				target = target:Lerp(toyAt, CAM.pull)
			end
		end
		local k = if snap then 1 else 1 - math.exp(-rdt * CAM.follow)
		local looked = if look then look:Lerp(target, k) else target
		look = looked
		local d = t - win.hit
		local tf = Killcam.fov(d, punch)
		fovNow = if snap then tf else fovNow + (tf - fovNow) * (1 - math.exp(-rdt * CAM.fov.follow))
		local jolt = Vector3.zero
		if kickAmp > 1e-3 then
			jolt = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5) * kickAmp
			kickAmp *= math.exp(-rdt * CAM.kickFade)
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(eye + jolt, looked + jolt)
		camera.FieldOfView = fovNow
		-- The arm: its walk bob from the root's travel, the throw's punch (K:491-498).
		local rp = K.root.Position
		local moved = if lastRoot and rdt > 0
			then Vector2.new(rp.X - lastRoot.X, rp.Z - lastRoot.Z).Magnitude / math.max(1e-4, rdt)
			else 0
		lastRoot = rp
		local walking = moved > ARM.walkSpeed
		bob += rdt * (if walking then ARM.bob.walk else ARM.bob.still)
		local push, lift = 0, 0
		if swing > 0 then
			swing += rdt * (if frozen > 0 then 0 else ARM.throw.rate * Killcam.speed(d))
			local w = math.sin(math.min(1, swing) * math.pi)
			push, lift = w * ARM.throw.push, w * ARM.throw.lift
			if swing >= 1 then
				swing = 0
			end
		end
		local hand, shoulder, toyAt, turn =
			Killcam.armPoints(bob, if walking then 1 else ARM.bob.stillAmp, push, lift)
		local eyeFrame = camera.CFrame
		if arms then
			OwnArm.partFrames(arms.right, hand / u, shoulder / u, 0, u, armFrames)
			for name, part in arms.right.parts do
				local f = armFrames[name]
				if f then
					part.CFrame = eyeFrame * f
				end
			end
		end
		local toy = armToy
		if toy then
			if K.held then
				toy.Parent = folder
				toy:PivotTo(eyeFrame * CFrame.new(toyAt) * turn * CFrame.Angles(0, math.pi, 0)) -- facing the camera
			else
				toy.Parent = nil
			end
		end
	end

	-- K:519-523 and hitFx(..., 1.7) (K:200-207): the squish (header).
	local function squish(a: Frame, b: Frame, u: number)
		local V = bodyAt(victimId, a, b, u)
		if V == nil then
			return
		end
		local H = CFG.hit
		local at = toyOf(killerId, a, b, u) or V.head.Position
		local S = H.sparks
		local colors = { WHITE, Palette.Lemon, Palette.PodiumSpot }
		local texture = AssetTable.image(STAR_KEY) or ""
		for _, color in colors do
			fx:emit(at, math.max(1, math.round(S.n / #colors)), {
				Texture = texture,
				Color = ColorSequence.new(color),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S.size), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(S.life * 0.8, S.life),
				Speed = NumberRange.new(S.speed * 0.5, S.speed),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -S.gravity, 0),
				Drag = 1,
				LightEmission = 0.5,
				LightInfluence = 0,
				RotSpeed = NumberRange.new(-180, 180),
			})
		end
		FxShapes.ring(at, (camera.CFrame.Position - at).Unit, H.ring.to, H.ring.s, WHITE)
		local look = spec.who(victimId)
		local tint = if look and look.look then look.look.mid or look.look.faceEnd or WHITE else WHITE
		local floorY = V.root.Position.Y - (heights[victimId] or 3)
		FxShapes.ring(Vector3.new(at.X, floorY + H.floorRing.up, at.Z), UP, H.floorRing.to, H.floorRing.s, tint)
		local holder = Instance.new("Part")
		holder.Name = "SquishLight"
		holder.Size = Vector3.one
		holder.Transparency = 1
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.CFrame = CFrame.new(at)
		holder.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = Palette.PodiumSlamLight
		light.Brightness = H.light.brightness
		light.Range = H.light.range
		light.Parent = holder
		TweenService:Create(light, TweenInfo.new(H.light.s), { Brightness = 0 }):Play()
		task.delay(H.light.s, function()
			holder:Destroy()
		end)
		if spec.shake and not spec.reduced then
			kickAmp = math.max(kickAmp, CAM.kick)
		end
		emit("impact", { at = V.root.Position + Vector3.new(0, CAM.victimUp, 0) })
		local style = KillStyle.get(KillStyle.resolve(if killerDef then killerDef.eliminationEffectId else nil))
		if style and KillVfx.has(style.killVfx) then
			KillVfx.kill(style.killVfx, V.root.Position)
		end
	end

	local replay = {}

	function replay.step(_self: any, now: number)
		if finished or ended then
			return
		end
		local snap = lastNow == nil
		local rdt = if lastNow then math.clamp(now - lastNow, 0, 0.1) else 0
		lastNow = now
		local prev = t
		local impact = false
		local sp = 0
		if frozen > 0 then
			frozen -= rdt
		else
			sp = Killcam.speed(t - win.hit)
			t = math.min(win.t1, t + rdt * sp)
			if not hitDone and t >= win.hit then
				t = win.hit
				hitDone = true
				frozen = CFG.freeze
				impact = true
				punch = 1
			end
		end
		for _, at in win.throws do
			if at > prev and at <= t then
				swing = 1e-3 -- K:471: the killer's throw punches the arm
				emit("throw", {})
			end
		end
		local slow = frozen > 0 or (not snap and sp < 0.9)
		if slow ~= slowed then
			slowed = slow
			emit("slow", { on = slow })
		end
		punch = math.max(0, punch - rdt * CAM.punchFade)
		local a, b, u = apply(t)
		aim(rdt, snap, a, b, u)
		if impact then
			squish(a, b, u)
		end
		hideAll()
		if t >= win.t1 and hitDone and frozen <= 0 then
			ended = true
		end
	end

	function replay.skip(_self: any)
		ended = true
	end

	function replay.done(_self: any): boolean
		return ended
	end

	function replay.destroy(_self: any)
		if finished then
			return
		end
		finished = true
		for _, c in copies do
			c.model:Destroy()
			if c.toy then
				c.toy:Destroy()
			end
		end
		for _, m in flights do
			m:Destroy()
		end
		if armToy then
			armToy:Destroy()
		end
		folder:Destroy()
		for d, value in hidden do
			if d.Parent ~= nil then
				(d :: any).LocalTransparencyModifier = value
			end
		end
		for d, value in switched do
			if d.Parent ~= nil then
				(d :: any).Enabled = value
			end
		end
		for _, player in heldHidden do
			deps.setHeldHidden(player, false)
		end
		deps.setAway(false)
		deps.restoreCamera(snapshot)
	end

	-- The first frame now: the cut lands at once.
	replay.step(replay, os.clock())
	return replay :: any
end

return Killcam
