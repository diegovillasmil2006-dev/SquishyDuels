--!strict
-- HitFxController (client only; 2026-10-28, the physics upgrade's part 2: getting hit; owner: "Yes, build part 2").
-- The co-owner's Claude Design page docs/squishy-fx-spec/hit.html (numbers in Config.HitFx) on every client, with the
-- owner's answers (Decisions 2026-10-28): the design's knockback; a match K.O. keeps Diego's kill effect (VfxController)
-- and gets the candy poof; the K.O. camera keeps watching the attacker (no koCam / fallCam); the round's last K.O. gets
-- the slow motion and the movie bars before the killcam.
-- * momentFor (pure): a K.O. that ends the round (a duel's last life, a match K.O. that reaches the K.O. target) =
--   finalKO; any other match K.O. = squished; an ultimate's hit (a Dragon Rush lane, an Epic ultimate's projectile) =
--   hitUltimate; a throw charged at least Config.HitFx.chargedFrom = hitCharged; else hitNormal. matchWins (pure)
--   reads the match view from before the K.O. (the server sends ThrowImpact before its MatchState).
-- * play: VfxController.handleImpact starts the moment at the impact (t = 0); this client's role picks the views (V1P the
--   local victim, A1P the local attacker, OBS anyone else); the victim is a player's character or a bot's rig
--   (Workspace.SD_Bots, the one nearest the hit: no pose there, bots have no pose layer). `freeze` = this client's
--   hit-stop (FeelFx.freeze: poses and effects stand still, as the design's world does).
-- * The knockback (hit.html motions.knockback), on the local victim's own client only (it owns its body, so it
--   replicates): the body leaves at `vertical` studs/s up and gravity does the rest (part 1's fall gravity too); a Plane
--   LinearVelocity drives the flat speed (walking cannot cancel it): `horizontal` away from the thrower for `hold` s, then
--   x e^(-airDrag t) in the air, then a skid down at groundDecel once it lands (knockSpeed, pure). MoveFxController.knock
--   keeps the take-off, fall and landing moments out of it. The server's movement guard gives hitGraceSeconds after a hit.
-- * The land signal (the skid puff and the get-up): the own body once its floor reads again; anyone else once a ray finds
--   the floor within landSlack under the feet; both only while falling or still, after landMinSeconds; never later than
--   landMax.
-- * hide / show (the poof): every part and decal of the body at Transparency 1 on this client only (a client's property
--   writes never replicate), each one's own value kept and put back by show; parts added meanwhile (accessories) are
--   caught each frame; and the player's held squishy hidden. Not LocalTransparencyModifier: FirstPersonController reads
--   the own Head's modifier as Roblox's first person (seen 2026-10-28: the poof turned the first-person hands on).
-- * Match (StateController): a K.O. by falling off the map (MatchMoments ko cause "outOfBounds") plays fallOff; a player
--   who stands again (MatchChanged alive false -> true) plays respawn; the match ending shows everyone.
-- Off when Config.HitFx.enabled is false (VfxController keeps its old hit looks).
-- API: momentFor(...), matchWins(view, attackerId), knockFor(kind), knockSpeed(...) (pure, unit-tested);
--   play(moment, impact, attackerId, accent, noKnockback?, freeze?) -> boolean, hitStopFor(moment),
--   debugPlay(moment, opts?), debugState(); init(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Log = require(Shared.Util.Log)
local HIT_FX = require(Shared.Config.HitFx)

local Client = script.Parent.Parent
local FeelFx = require(Client.Anim.FeelFx)
local Scheduler = require(Client.Anim.Scheduler)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local MoveFxController = require(script.Parent.MoveFxController)
local StateController = require(script.Parent.StateController)

-- Constants

local KNOCK = HIT_FX.knockback
local MOMENTS = HIT_FX.moments
local HIDE_REASON = "poof"
local KNOCK_NAME = "SD_Knockback"
local HIDE_BIND = "SD_HitFxHide"
local BOTS_FOLDER = "SD_Bots" -- BotService: the practice bot's and the match bots' rigs
local BOT_REACH = 8 -- studs: a bot rig counts as the victim when its root is this near the hit
local SKID_MAX = 1 -- s: a skid never lasts longer (a wall can hold the body still)
local STILL_VY = 0.5 -- studs/s: falling or still, for the land check

-- Module table

local HitFxController = {}

-- Types

type Knock = {
	root: BasePart,
	attachment: Attachment,
	mover: LinearVelocity,
	unit: Vector3,
	speed: number,
	hold: number,
	start: number,
	landedAt: number?,
}
type Watch = { run: any, character: Model, since: number, own: boolean }
type Hidden = { player: Player?, saved: { [Instance]: number } } -- each part's and decal's own Transparency

-- Private state

local log = Log.new("HitFx")
local cleanup: Cleanup.Cleanup? = nil
local knock: Knock? = nil
local watches: { [Model]: Watch } = {}
local hidden: { [Model]: Hidden } = {} -- the hidden bodies
local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude
local stats = { hits = 0, knockbacks = 0, lands = 0, hides = 0, respawns = 0, falls = 0, last = "" }

-- Pure -------------------------------------------------------------------------------------------------------------------

-- The design moment of a "player" impact.
function HitFxController.momentFor(
	eliminated: boolean?,
	inMatch: boolean,
	matchFinal: boolean,
	ultimate: boolean,
	power: number?
): string
	if eliminated == true then
		return if inMatch and not matchFinal then "squished" else "finalKO"
	end
	if ultimate then
		return "hitUltimate"
	end
	if (power or 0) >= HIT_FX.chargedFrom then
		return "hitCharged"
	end
	return "hitNormal"
end

-- Whether a K.O. by `attackerId` wins the match, from the view before it: FFA their K.O.s + 1, TDM their team's score
-- + 1 reaches koTarget.
function HitFxController.matchWins(view: any, attackerId: number?): boolean
	if type(view) ~= "table" or attackerId == nil or type(view.koTarget) ~= "number" then
		return false
	end
	for _, p in view.players or {} do
		if p.userId == attackerId then
			if view.mode == "tdm" then
				local score = if view.teamScore and p.team then view.teamScore[p.team] else nil
				return type(score) == "number" and score + 1 >= view.koTarget
			end
			return type(p.kos) == "number" and p.kos + 1 >= view.koTarget
		end
	end
	return false
end

-- The knockback of a kind ("normal" | "charged" | "ultimate"): horizontal, vertical (studs/s), hold (s).
function HitFxController.knockFor(kind: string?): (number, number, number)
	local base = if kind == "charged" then KNOCK.charged else KNOCK.normal
	local mul = if kind == "ultimate" then KNOCK.ultimateMultiplier else 1
	return base.horizontal * mul, base.vertical * mul, base.hold
end

-- The flat speed `t` s into a knockback of `speed` (hit.html update()): held for `hold` s, then x e^(-airDrag x the time
-- since) in the air; after a landing `landedAt` s in, down at groundDecel to 0.
function HitFxController.knockSpeed(speed: number, hold: number, t: number, landedAt: number?): number
	local function air(at: number): number
		return if at <= hold then speed else speed * math.exp(-KNOCK.airDrag * (at - hold))
	end
	if landedAt == nil or t < landedAt then
		return air(t)
	end
	return math.max(air(landedAt) - KNOCK.groundDecel * (t - landedAt), 0)
end

function HitFxController.hitStopFor(moment: string): number
	return HIT_FX.hitStop[moment] or HIT_FX.hitStop.hitNormal
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The victim's body: a player's character, else the bot rig nearest `near`.
local function bodyOf(userId: number, near: Vector3?): (Player?, Model?)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player, player.Character
	end
	local folder = Workspace:FindFirstChild(BOTS_FOLDER)
	if folder == nil or near == nil then
		return nil, nil
	end
	local best, bestDistance = nil, BOT_REACH
	for _, rig in folder:GetChildren() do
		local root = if rig:IsA("Model") then rootOf(rig) else nil
		if root then
			local distance = (root.Position - near).Magnitude
			if distance < bestDistance then
				best, bestDistance = rig, distance
			end
		end
	end
	return nil, best
end

local function roleFor(victimId: number?, attackerId: number?): string
	local localPlayer = Players.LocalPlayer
	local localId = if localPlayer then localPlayer.UserId else nil
	if localId ~= nil and victimId == localId then
		return "V1P"
	elseif localId ~= nil and attackerId == localId then
		return "A1P"
	end
	return "OBS"
end

local function newActor(player: Player?, character: Model, root: BasePart, view: string, extra: { [string]: any }?): any
	local actor: any = {
		character = character,
		root = root,
		player = player,
		own = player ~= nil and player == Players.LocalPlayer,
		priority = if view == "OBS" then -1 else 1,
		floor = MoveFxController.floorColor(root),
		view = view,
	}
	for k, v in extra or {} do
		actor[k] = v
	end
	return actor
end

local function startRun(moment: string, actor: any): any
	local run = FeelFx.play(MOMENTS[moment], actor, HIT_FX)
	actor.run = run
	stats.last = moment
	return run
end

-- Every part and decal of a hidden body at Transparency 1, keeping each one's own value the first time it is seen.
local function hideParts(character: Model, entry: Hidden)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if entry.saved[d] == nil then
				entry.saved[d] = d.Transparency
			end
			d.Transparency = 1
		end
	end
end

local function setHidden(character: Model, player: Player?, on: boolean)
	local entry = hidden[character]
	if on and entry == nil then
		entry = { player = player, saved = {} }
		hidden[character] = entry
		hideParts(character, entry)
		stats.hides += 1
	elseif not on and entry ~= nil then
		hidden[character] = nil
		for d, transparency in entry.saved do
			if d.Parent then
				(d :: any).Transparency = transparency
			end
		end
	end
	if player then
		local ok, err = pcall(HeldSquishyController.setHidden, player, HIDE_REASON, on)
		if not ok then
			log:warn("held squishy hide failed:", err)
		end
	end
end

local function showAll()
	for character, entry in table.clone(hidden) do
		setHidden(character, entry.player, false)
		FeelFx.clearPose(character)
	end
end

-- The own knockback ---------------------------------------------------------------------------------------------------

local function stopKnock()
	local k = knock
	knock = nil
	if k then
		k.attachment:Destroy()
	end
end

local function startKnock(kind: string?, dir: Vector3?)
	local root = rootOf(Players.LocalPlayer.Character)
	if root == nil then
		return
	end
	stopKnock()
	local h, v, hold = HitFxController.knockFor(kind)
	local flat = if dir then Vector3.new(dir.X, 0, dir.Z) else Vector3.zero
	if flat.Magnitude < 1e-3 then
		local look = root.CFrame.LookVector
		flat = -Vector3.new(look.X, 0, look.Z)
	end
	local unit = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local attachment = Instance.new("Attachment")
	attachment.Name = KNOCK_NAME
	local mover = Instance.new("LinearVelocity")
	mover.Name = KNOCK_NAME
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.ForceLimitsEnabled = false
	mover.PlaneVelocity = Vector2.new(unit.X * h, unit.Z * h)
	mover.Parent = attachment
	attachment.Parent = root
	root.AssemblyLinearVelocity = Vector3.new(unit.X * h, v, unit.Z * h)
	knock = {
		root = root,
		attachment = attachment,
		mover = mover,
		unit = unit,
		speed = h,
		hold = hold,
		start = os.clock(),
		landedAt = nil,
	}
	MoveFxController.knock(HIT_FX.landMax + SKID_MAX)
	stats.knockbacks += 1
end

-- PreSimulation: the flat speed of this frame.
local function stepKnock()
	local k = knock
	if k == nil then
		return
	end
	local t = os.clock() - k.start
	if k.root.Parent == nil or k.attachment.Parent == nil or t > HIT_FX.landMax + SKID_MAX then
		stopKnock()
		return
	end
	local landed = if k.landedAt then k.landedAt - k.start else nil
	local s = HitFxController.knockSpeed(k.speed, k.hold, t, landed)
	if landed and s <= 0 then
		stopKnock()
		return
	end
	k.mover.PlaneVelocity = Vector2.new(k.unit.X * s, k.unit.Z * s)
end

-- Land watches --------------------------------------------------------------------------------------------------------

local function hasLanded(w: Watch, now: number): boolean
	local since = now - w.since
	if since >= HIT_FX.landMax then
		return true
	end
	if since < HIT_FX.landMinSeconds then
		return false
	end
	local character = w.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if humanoid == nil or root == nil then
		return true
	end
	if root.AssemblyLinearVelocity.Y > STILL_VY then
		return false
	end
	if w.own then
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end
	local reach = humanoid.HipHeight + root.Size.Y / 2 + HIT_FX.landSlack
	local fx = Workspace:FindFirstChild("SD_ClientFx")
	downParams.FilterDescendantsInstances = if fx then { character, fx } else { character }
	return Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), downParams) ~= nil
end

local function stepWatches(_dt: number, _now: number): boolean
	local now = os.clock()
	for character, w in watches do
		if character.Parent == nil then
			watches[character] = nil
		elseif hasLanded(w, now) then
			watches[character] = nil
			stats.lands += 1
			local k = knock
			if w.own and k and k.landedAt == nil then
				k.landedAt = now
			end
			w.run:signal("land")
		end
	end
	return true
end

-- Hidden bodies stay hidden: parts added since (an accessory loading in) are caught too.
local function stepHidden()
	for character, entry in hidden do
		local player = entry.player
		if character.Parent == nil or (player and player.Parent == nil) then
			hidden[character] = nil
			continue
		end
		hideParts(character, entry)
	end
end

-- FeelFx calls (the moments' `call` events).
local function onCall(name: string, actor: any, ev: any)
	local character: Model = actor.character
	if name == "knockback" then
		if actor.own and actor.noKnockback ~= true then
			startKnock(ev.kind, actor.dir)
		elseif not actor.own then
			MoveFxController.knock(HIT_FX.landMax + SKID_MAX, character) -- no jump or landing puffs on the flying body
		end
		if actor.run then
			watches[character] = { run = actor.run, character = character, since = os.clock(), own = actor.own }
		end
	elseif name == "hide" then
		setHidden(character, actor.player, true)
	elseif name == "show" then
		setHidden(character, actor.player, false)
	end
end

-- Match: the falls off the map and the respawns ------------------------------------------------------------------------

local function playOn(moment: string, userId: number, view: any?)
	local player, character = bodyOf(userId, nil)
	if character == nil and view ~= nil then
		-- A bot: its rig is named after it (BotService).
		local p = StateController.matchParticipant(view, userId)
		local folder = Workspace:FindFirstChild(BOTS_FOLDER)
		local rig = if p and folder then folder:FindFirstChild(p.displayName) else nil
		character = if rig and rig:IsA("Model") then rig else nil
	end
	local root = rootOf(character)
	if character == nil or root == nil then
		return
	end
	startRun(moment, newActor(player, character, root, roleFor(userId, nil)))
end

local function onMatchMoments(moments: { any }, view: any)
	if not HIT_FX.enabled then
		return
	end
	for _, m in moments do
		if m.kind == "ko" and m.cause == "outOfBounds" and type(m.victim) == "number" then
			stats.falls += 1
			playOn("fallOff", m.victim, view)
		end
	end
end

local function onMatchChanged(new: any, old: any)
	if not HIT_FX.enabled then
		return
	end
	if new == nil or new.phase == "Returning" then
		showAll()
		return
	end
	if old == nil or old.matchId ~= new.matchId then
		return
	end
	for _, p in new.players do
		local before = StateController.matchParticipant(old, p.userId)
		if p.alive == true and before and before.alive == false then
			stats.respawns += 1
			playOn("respawn", p.userId, new)
		end
	end
end

-- Public -------------------------------------------------------------------------------------------------------------------

-- Plays `moment` for a "player" impact (VfxController.handleImpact). False when no victim body is here (nothing played).
function HitFxController.play(
	moment: string,
	impact: any,
	attackerId: number?,
	accent: Color3?,
	noKnockback: boolean?,
	freeze: number?
): boolean
	if not HIT_FX.enabled or MOMENTS[moment] == nil or type(impact.victimId) ~= "number" then
		return false
	end
	local player, character = bodyOf(impact.victimId, impact.position)
	local root = rootOf(character)
	if character == nil or root == nil then
		return false
	end
	if freeze and freeze > 0 then
		FeelFx.freeze(freeze)
	end
	stats.hits += 1
	startRun(
		moment,
		newActor(player, character, root, roleFor(impact.victimId, attackerId), {
			dir = impact.knockbackDir or (root.Position - impact.position),
			hitAt = impact.position,
			tint = accent,
			noKnockback = noKnockback == true,
		})
	)
	return true
end

-- Studio (DebugHooks "hitFx"): `moment` on the local player as if a squishy struck the chest from the front. opts.view
-- (default "V1P"; "OBS" shows what everyone else sees on the own body), opts.knockback (default true), opts.freeze
-- (default true: the moment's hit-stop), opts.photoAt (seconds in: the effects and the body stand still for
-- opts.photoHold s, default 3, for a screen capture).
function HitFxController.debugPlay(moment: string, opts: { [string]: any }?): (boolean, string?)
	local o: { [string]: any } = opts or {}
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = rootOf(character)
	if character == nil or root == nil then
		return false, "no character"
	end
	if MOMENTS[moment] == nil then
		return false, `unknown moment {moment}`
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	if o.freeze ~= false then
		FeelFx.freeze(HitFxController.hitStopFor(moment))
	end
	local id = HeldSquishyController.getSquishyId(player)
	startRun(
		moment,
		newActor(player, character, root, if type(o.view) == "string" then o.view else "V1P", {
			dir = -flat,
			hitAt = root.Position + flat * 0.6 + Vector3.new(0, 0.6, 0),
			tint = if id then MoveFxController.squishyTint(player) else nil,
			noKnockback = o.knockback == false,
		})
	)
	stats.hits += 1
	if type(o.photoAt) == "number" then
		local hold = if type(o.photoHold) == "number" then o.photoHold else 3
		task.delay(o.photoAt, function()
			FeelFx.freeze(hold, true)
			root.Anchored = true
			task.delay(hold, function()
				root.Anchored = false
			end)
		end)
	end
	return true, nil
end

function HitFxController.debugState(): { [string]: any }
	local hiddenCount = 0
	for _ in hidden do
		hiddenCount += 1
	end
	return {
		enabled = HIT_FX.enabled,
		knocking = knock ~= nil,
		watching = next(watches) ~= nil,
		hidden = hiddenCount,
		timeScale = FeelFx.timeScale(),
		stats = table.clone(stats),
		feel = FeelFx.counts(),
	}
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

function HitFxController.init()
	local c = Cleanup.new()
	cleanup = c
	FeelFx.setHooks({ call = onCall })
	c:add(RunService.PreSimulation:Connect(function()
		local ok, err = pcall(stepKnock)
		if not ok then
			log:warn("knockback step failed:", err)
		end
	end))
	c:add(Scheduler.add(function(dt: number, now: number): boolean
		local ok, err = pcall(stepWatches, dt, now)
		if not ok then
			log:warn("land watch failed:", err)
		end
		return true
	end, "render"))
	RunService:BindToRenderStep(HIDE_BIND, Enum.RenderPriority.Last.Value, stepHidden)
	c:add(StateController.MatchMoments:connect(onMatchMoments))
	c:add(StateController.MatchChanged:connect(onMatchChanged))
	c:add(Players.LocalPlayer.CharacterAdded:Connect(stopKnock))
	c:add(function()
		RunService:UnbindFromRenderStep(HIDE_BIND)
		stopKnock()
		showAll()
		table.clear(watches)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function HitFxController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return HitFxController
