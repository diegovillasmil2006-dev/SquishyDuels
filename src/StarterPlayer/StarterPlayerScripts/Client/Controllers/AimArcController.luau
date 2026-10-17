--!strict
-- AimArcController (client only). The aim arc (jayyyyy 2026-10-16: "AIM ARC yes"; the charge throw's trajectory
-- preview that feature 1 left out). Design: the combat-effects page "Squishy Combat FP v2.html", html:256-294 ("aim
-- preview: marching dashed arc + landing marker"); every number is Config.Vfx.AimArc (metres / 0.28 = studs).
-- * While the local player charges a throw (hold to charge: duels, practice, Free for All / Team Deathmatch) with
--   c > showFromCharge, dashes show the path the squishy flies if let go now, and a ring and dot where it lands.
-- * The path is the real throw's: ThrowController.chargePreview() is the launch fire() would send now (launchFor's
--   origin hint and direction: the solved aim, the crosshair when the aim ray hits nothing, aim assist; × launchSpeed:
--   the toy's speed × ThrowCharge.speedFactor of the charge the server will measure × the throw boost), with the toy's
--   gravity and radius; the samples are ProjectileMath.positionAt, the formula the server sweeps. Where it lands:
--   Workspace:Spherecast of the toy's radius along the server's own sub-steps (ProjectileMath.subSteps at
--   1 / castChordSeconds, at most maxCasts, over Duel.Rules.ProjectileMaxLifetime) against what a throw hits
--   (collidable parts in the Default group; never Workspace.SD_ClientFx), the first hit's time as
--   ProjectileMath.impactTime takes it. No hit: no marker (design: html:293). The design's own throw physics
--   (html:269-279) is not used, so the arc lands where the real throw lands. Review fix (2026-10-16, job aimarc):
--   players are left out of the cast unless they are an enemy now (excluded: the own character, a Team Deathmatch
--   teammate, a lobby player walking through the practice lane), as the server's throw meets players only as enemy
--   capsules (CombatService, HitMath); an enemy's body stays in (about its capsule): the duel opponent
--   (StateController.duel) and a match's live enemies (ThrowController.enemyTargets). Batch B (2026-10-17): the bots'
--   rigs (Workspace.SD_Bots: the practice bot, match bots) stay in, except a TDM teammate's (botIsEnemy: its SD_Team).
-- * Looks (design: html:257-292): up to `dashes` dashes every gapStuds from startStuds along the path (never on the
--   thrower), marching marchRate gaps a second, (widthStuds + widthChargeStuds·c) wide, growing from widthFrom over the
--   first widthRampStuds, thinner and shorter toward the end (farFade); every whiteEvery-th dash Art/Palette White,
--   the others the toy's Catalog accent; opacity × `opacity`. The marker: a ring (inner share markerInner) and a dot
--   (markerDot) on the hit surface, facing its normal, outer radius markerStuds + markerChargeStuds·c pulsing
--   ± markerPulse, opacity markerOpacity. The arc's share eases in at fadeInRate and out at fadeOutRate (the last path
--   stays while it fades) and hides at hideBelow.
-- * Unlit like the design's MeshBasicMaterial: CylinderHandleAdornments (default shading, depth-tested, so walls hide
--   them) on one invisible anchor part in Workspace.SD_ClientFx/AimArc, made on the first show: no physics part moves,
--   no particles. Only the local player's own charge is drawn; nobody else sees it.
-- * ReducedMotion (Anim/Tweens.reducedMotion): no marching, no pulse, no fade (it shows and hides at once). The arc
--   itself stays: it is information, not motion.
-- * One Anim/Scheduler "render" effect, after ThrowController's step (it is added in start()); idle it is one call
--   that returns at once. A charging frame: one path of at most ProjectileMaxLifetime / stepSeconds samples (maths),
--   up to maxCasts Spherecasts (until the first hit), the dashes' CFrame / Radius / Height.
-- Build choices (NOT IN DESIGN, [P] in Config.Vfx.AimArc): a dash is an adornment cylinder (the design's capsule has
-- rounded ends); the ring's thickness; the cast chord and cap. Known limits: the arc does not stop where a projectile
-- leaves an arena's Bounds (the server expires it there). The server sweeps Include lists (a duel: the slot's Geometry
-- without Barriers, its query-only floor paint included; a match: the map's collidable parts; practice: the range's
-- parts and a flat floor at its height); this cast takes every collidable part instead, so it lands on the floor
-- right under a duel's paint (a fraction of a stud) and would stop on a collidable lobby part in the practice lane
-- that is not a range part (none known).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local ProjectileMath = require(Shared.ProjectileMath)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)

-- Types

-- One dash: its centre, unit direction along the path, width and length (studs).
export type Dash = { position: Vector3, direction: Vector3, width: number, length: number }

-- (fraction 0..1 of delta, contact point, surface normal) of the first thing a sphere of `radius` moved from `from` by
-- `delta` touches, or nil.
export type Cast = (from: Vector3, radius: number, delta: Vector3) -> (number?, Vector3?, Vector3?)

-- What one show draws: the launch (ThrowController.ChargePreview) and where it lands.
type Shown = {
	preview: ThrowController.ChargePreview,
	endTime: number,
	hit: Vector3?,
	normal: Vector3?,
}

-- Constants

local ARC = Config.Vfx.AimArc
local LIFETIME = Config.Duel.Rules.ProjectileMaxLifetime
local WHITE = Palette.White
local FX_FOLDER = "SD_ClientFx"
local OWN_FOLDER = "AimArc"
local DEFAULT_GROUP = "Default"
local MIN_CHORD = 1e-6 -- studs: a shorter chord is not cast
local BOTS_FOLDER = "SD_Bots" -- BotService: the practice bot's and the match bots' rigs
local TEAM_ATTR = "SD_Team" -- MatchService: a TDM fighter's team, on the Player or (BotService) on a bot's rig

-- Module table

local AimArcController = {}

-- State

local log = Log.new("AimArc")
local cleanup: Cleanup.Cleanup? = nil
local folder: Folder? = nil
local dashes: { CylinderHandleAdornment } = {}
local ring: CylinderHandleAdornment? = nil
local dot: CylinderHandleAdornment? = nil
local alpha = 0 -- the arc's opacity share (design: G.trajA)
local shown: Shown? = nil
local accent: Color3? = nil -- the colour the accent dashes have now
local transparency = 1 -- the dashes' Transparency now
local visibleDashes = 0
local markerShown = false
local points: { Vector3 } = {}
local dists: { number } = {}
local dashLayout: { Dash } = {}
local params: RaycastParams? = nil
local paramsList: { Instance } = {} -- what `params` leaves out (castParams rebuilds it when this changes)
local castCharacters: { Instance } = {}
local castEnemies: { Instance } = {}
local castList: { Instance } = {}

-- Public (pure)

-- The arc's opacity share one frame later (design: html:267): eases toward 1 (on) at fadeInRate or toward 0 at
-- fadeOutRate; under reduced motion it jumps there.
function AimArcController.fade(share: number, on: boolean, dt: number, reduced: boolean): number
	local target = if on then 1 else 0
	if reduced then
		return target
	end
	local rate = if on then ARC.fadeInRate else ARC.fadeOutRate
	return share + (target - share) * math.min(1, math.max(dt, 0) * rate)
end

-- The dashes' march (design: html:281): (t · marchRate) mod 1 of a gap at clock t; 0 under reduced motion.
function AimArcController.marchPhase(t: number, reduced: boolean): number
	if reduced then
		return 0
	end
	return (t * ARC.marchRate) % 1
end

-- Whether dash k (1 = the nearest) is a white one (design: html:288, k % 4 === 3 counted from 0); the others take the
-- toy's accent.
function AimArcController.isWhite(k: number): boolean
	return k % ARC.whiteEvery == 0
end

-- A frame at `position` whose Z axis is `axis` (a cylinder adornment's axis), for any axis, straight up included.
function AimArcController.axisFrame(position: Vector3, axis: Vector3): CFrame
	local z = if axis.Magnitude > 1e-9 then axis.Unit else Vector3.zAxis
	local x = if math.abs(z.Y) < 0.95 then Vector3.yAxis:Cross(z).Unit else Vector3.xAxis:Cross(z).Unit
	return CFrame.fromMatrix(position, x, z:Cross(x), z)
end

-- The landing marker's outer radius (studs) for charge c at clock t and share `share` (design: html:292); no pulse
-- under reduced motion.
function AimArcController.markerRadius(c: number, t: number, share: number, reduced: boolean): number
	local pulse = if reduced then 1 else 1 + ARC.markerPulse * math.sin(ARC.markerPulseRate * t)
	return (ARC.markerStuds + ARC.markerChargeStuds * math.clamp(c, 0, 1)) * pulse * share
end

-- Where a throw (origin o, velocity v, gravity g, sphere radius) first touches something within tMax: `cast` along the
-- server's sub-steps (ProjectileMath.subSteps at perSecond, at most maxSteps), in order; the first hit's time
-- (ProjectileMath.impactTime from release 0), contact point and normal. No hit: tMax, nil, nil.
function AimArcController.landing(
	o: Vector3,
	v: Vector3,
	g: number,
	radius: number,
	tMax: number,
	perSecond: number,
	maxSteps: number,
	cast: Cast
): (number, Vector3?, Vector3?)
	for _, s in ProjectileMath.subSteps(o, v, g, 0, tMax, perSecond, maxSteps) do
		local delta = s.p1 - s.p0
		if delta.Magnitude > MIN_CHORD then
			local fraction, position, normal = cast(s.p0, radius, delta)
			if fraction ~= nil then
				return ProjectileMath.impactTime(0, s.a, s.b, fraction), position, normal
			end
		end
	end
	return math.max(tMax, 0), nil, nil
end

-- The path from release to `endTime`: positionAt every `step` seconds (the last sample exactly at endTime) into
-- out[1..n] and the distance along it into outDist (outDist[1] = 0). Returns n (>= 2).
function AimArcController.path(
	o: Vector3,
	v: Vector3,
	g: number,
	endTime: number,
	step: number,
	out: { Vector3 },
	outDist: { number }
): number
	local last = math.max(endTime, 0)
	local count = math.max(1, math.ceil(last / step - 1e-9))
	out[1] = o
	outDist[1] = 0
	for index = 1, count do
		local p = ProjectileMath.positionAt(o, v, g, if index == count then last else index * step)
		out[index + 1] = p
		outDist[index + 1] = outDist[index] + (p - out[index]).Magnitude
	end
	return count + 1
end

-- The dashes along a path of `count` samples (path()) for charge c, share `share` and march `phase` (design:
-- html:280-289): from startStuds + phase · gapStuds every gapStuds while short of the path's end, at most `dashes`.
-- Writes out[1..k] (reusing its tables) and returns k.
function AimArcController.layout(
	pts: { Vector3 },
	dist: { number },
	count: number,
	c: number,
	share: number,
	phase: number,
	out: { Dash }
): number
	local total = dist[count]
	local charge = math.clamp(c, 0, 1)
	local s = ARC.startStuds + phase * ARC.gapStuds
	local k = 0
	local j = 1
	while k < ARC.dashes and s < total do
		while j < count - 1 and dist[j + 1] < s do
			j += 1
		end
		local a, b = pts[j], pts[j + 1]
		local f = (s - dist[j]) / math.max(1e-5, dist[j + 1] - dist[j])
		local along = b - a
		local fade = 1 - ARC.farFade * (s / total)
		local ramp = ARC.widthFrom + (1 - ARC.widthFrom) * math.min(1, s / ARC.widthRampStuds)
		k += 1
		local dash = out[k]
		if dash == nil then
			dash = { position = a, direction = Vector3.zAxis, width = 0, length = 0 }
			out[k] = dash
		end
		dash.position = a:Lerp(b, f)
		dash.direction = if along.Magnitude > 1e-9 then along.Unit else Vector3.zAxis
		dash.width = (ARC.widthStuds + ARC.widthChargeStuds * charge) * ramp * fade * share
		dash.length = ARC.dashLengthStuds * fade
		s += ARC.gapStuds
	end
	return k
end

-- Review fix (2026-10-16, job aimarc): what the landing cast leaves out (see the header): every character in
-- `characters` (the players' characters, the own one included) that is not in `enemies`, then `fx` (the client
-- effects folder) when given. Writes out (cleared first) and returns it.
function AimArcController.excluded(
	characters: { Instance },
	enemies: { Instance },
	fx: Instance?,
	out: { Instance }
): { Instance }
	table.clear(out)
	for _, character in characters do
		if table.find(enemies, character) == nil then
			table.insert(out, character)
		end
	end
	if fx then
		table.insert(out, fx)
	end
	return out
end

-- Batch B (2026-10-17, the bots landed): whether a bot's rig counts as an enemy body for the cast: every bot but a
-- Team Deathmatch teammate (the same SD_Team as the local player's), as the server's throw never meets a teammate.
-- Bots elsewhere (another duel or match) stay in too: they are far from this throw's path.
function AimArcController.botIsEnemy(myTeam: unknown, botTeam: unknown): boolean
	return myTeam == nil or botTeam ~= myTeam
end

-- Private

-- The enemies' characters now (see the header): the duel opponent, a match's live enemies; none in practice.
local function enemyCharacters(out: { Instance }): { Instance }
	table.clear(out)
	local duel = StateController.duel()
	local opponentId = if duel and duel.opponent then duel.opponent.userId else nil
	local opponent = if type(opponentId) == "number" then Players:GetPlayerByUserId(opponentId) else nil
	if opponent and opponent.Character then
		table.insert(out, opponent.Character)
	end
	for _, target in ThrowController.enemyTargets() do
		if target.model then
			table.insert(out, target.model)
		end
	end
	return out
end

local function sameList(a: { Instance }, b: { Instance }): boolean
	if #a ~= #b then
		return false
	end
	for index, instance in a do
		if b[index] ~= instance then
			return false
		end
	end
	return true
end

-- The cast's params, made again only when what it leaves out changed (a respawn, a join, an enemy K.O.'d).
local function castParams(): RaycastParams
	table.clear(castCharacters)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(castCharacters, player.Character)
		end
	end
	enemyCharacters(castEnemies)
	local me = Players.LocalPlayer
	local myTeam = if me then me:GetAttribute(TEAM_ATTR) else nil
	local bots = Workspace:FindFirstChild(BOTS_FOLDER)
	if bots then
		for _, rig in bots:GetChildren() do
			if rig:IsA("Model") then
				table.insert(castCharacters, rig)
				if AimArcController.botIsEnemy(myTeam, rig:GetAttribute(TEAM_ATTR)) then
					table.insert(castEnemies, rig)
				end
			end
		end
	end
	local list = AimArcController.excluded(castCharacters, castEnemies, Workspace:FindFirstChild(FX_FOLDER), castList)
	local current = params
	if current == nil or not sameList(list, paramsList) then
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.CollisionGroup = DEFAULT_GROUP -- the arena barriers and dividers are left out by their groups (as the aim)
		p.IgnoreWater = true
		p.RespectCanCollide = true -- a throw flies through what nothing collides with (the server sweeps collidables)
		p.FilterDescendantsInstances = list
		params = p
		paramsList = table.clone(list)
		current = p
	end
	return current :: RaycastParams
end

local function spherecast(from: Vector3, radius: number, delta: Vector3): (number?, Vector3?, Vector3?)
	local result = Workspace:Spherecast(from, radius, delta, castParams())
	if result == nil then
		return nil, nil, nil
	end
	return result.Distance / delta.Magnitude, result.Position, result.Normal
end

local function newAdornment(name: string, anchor: BasePart, parent: Instance): CylinderHandleAdornment
	local adornment = Instance.new("CylinderHandleAdornment")
	adornment.Name = name
	adornment.Adornee = anchor
	adornment.AlwaysOnTop = false
	adornment.AdornCullingMode = Enum.AdornCullingMode.Never -- the anchor sits at the world origin, far from a map
	adornment.Visible = false
	adornment.Parent = parent
	return adornment
end

-- The adornments, made once on the first show.
local function ensureInstances()
	if folder ~= nil and folder.Parent ~= nil then
		return
	end
	local fx = Workspace:FindFirstChild(FX_FOLDER)
	if fx == nil then
		local made = Instance.new("Folder")
		made.Name = FX_FOLDER
		made.Parent = Workspace
		fx = made
	end
	local own = Instance.new("Folder")
	own.Name = OWN_FOLDER
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.identity -- the adornments' CFrames are world CFrames
	anchor.Parent = own
	table.clear(dashes)
	for index = 1, ARC.dashes do
		local dash = newAdornment("Dash" .. index, anchor, own)
		if AimArcController.isWhite(index) then
			dash.Color3 = WHITE
		end
		dashes[index] = dash
	end
	ring = newAdornment("Ring", anchor, own)
	dot = newAdornment("Dot", anchor, own)
	accent = nil
	transparency = 1
	visibleDashes = 0
	markerShown = false
	own.Parent = fx
	folder = own
end

local function hide()
	for index = 1, visibleDashes do
		dashes[index].Visible = false
	end
	visibleDashes = 0
	if markerShown and ring and dot then
		ring.Visible = false
		dot.Visible = false
	end
	markerShown = false
end

local function draw(view: Shown, now: number, reduced: boolean)
	ensureInstances()
	local preview = view.preview
	local count = AimArcController.path(
		preview.origin,
		preview.velocity,
		preview.gravity,
		view.endTime,
		ARC.stepSeconds,
		points,
		dists
	)
	local k = AimArcController.layout(
		points,
		dists,
		count,
		preview.charge,
		alpha,
		AimArcController.marchPhase(now, reduced),
		dashLayout
	)
	local colour = preview.color or WHITE
	if colour ~= accent then
		accent = colour
		for index, adornment in dashes do
			if not AimArcController.isWhite(index) then
				adornment.Color3 = colour
			end
		end
		if ring and dot then
			ring.Color3 = colour
			dot.Color3 = colour
		end
	end
	local dashTransparency = 1 - ARC.opacity * alpha
	local fadeChanged = dashTransparency ~= transparency
	transparency = dashTransparency
	for index = 1, k do
		local dash = dashLayout[index]
		local adornment = dashes[index]
		adornment.CFrame = AimArcController.axisFrame(dash.position, dash.direction)
		adornment.Radius = dash.width / 2
		adornment.Height = dash.length
		if fadeChanged or index > visibleDashes then
			adornment.Transparency = dashTransparency
		end
		if index > visibleDashes then
			adornment.Visible = true
		end
	end
	for index = k + 1, visibleDashes do
		dashes[index].Visible = false
	end
	visibleDashes = k
	local hit, normal = view.hit, view.normal
	local r, d = ring :: CylinderHandleAdornment, dot :: CylinderHandleAdornment
	if hit and normal and normal.Magnitude > 1e-6 then
		local n = normal.Unit
		local frame = AimArcController.axisFrame(hit + n * ARC.markerLiftStuds, n) -- flat on the surface
		local outer = AimArcController.markerRadius(preview.charge, now, alpha, reduced)
		local markerTransparency = 1 - ARC.markerOpacity * alpha
		r.CFrame = frame
		r.Radius = outer
		r.InnerRadius = outer * ARC.markerInner
		r.Height = ARC.markerHeightStuds
		r.Transparency = markerTransparency
		r.Visible = true
		d.CFrame = frame
		d.Radius = outer * ARC.markerDot
		d.Height = ARC.markerHeightStuds
		d.Transparency = markerTransparency
		d.Visible = true
		markerShown = true
	elseif markerShown then
		r.Visible = false
		d.Visible = false
		markerShown = false
	end
end

local function step(dt: number, now: number): boolean
	local preview = ThrowController.chargePreview()
	local on = preview ~= nil and preview.charge > ARC.showFromCharge
	local reduced = Tweens.reducedMotion()
	alpha = AimArcController.fade(alpha, on, dt, reduced)
	if on and preview then
		local endTime, hit, normal = AimArcController.landing(
			preview.origin,
			preview.velocity,
			preview.gravity,
			preview.radius,
			LIFETIME,
			1 / ARC.castChordSeconds,
			ARC.maxCasts,
			spherecast
		)
		shown = { preview = preview, endTime = endTime, hit = hit, normal = normal }
	end
	local view = shown
	if view == nil or alpha <= ARC.hideBelow then
		if not on then
			shown = nil
		end
		hide()
		return true
	end
	draw(view, now, reduced)
	return true
end

-- Lifecycle

function AimArcController.init()
	cleanup = Cleanup.new()
end

-- `scheduler` defaults to the client's (tests pass a private one).
function AimArcController.start(scheduler: Scheduler.Scheduler?)
	local c = cleanup
	if c == nil then
		return
	end
	local runner = scheduler or Scheduler.default()
	c:add(runner:add(function(dt: number, now: number): boolean
		local ok, err = pcall(step, dt, now)
		if not ok then
			log:error("aim arc update failed:", err)
			hide()
		end
		return true
	end, "render"))
	c:add(function()
		hide()
		shown = nil
		alpha = 0
		local own = folder
		folder = nil
		ring, dot = nil, nil
		table.clear(dashes)
		if own then
			own:Destroy()
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function AimArcController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return AimArcController
