--!strict
-- MatchPodium (client only). End screens round B1 (2026-10-26; owner: "Yes, build step 1 of round B like that. You can
-- make and upload the sounds."; `E:n` = Diego's uploads/sd/tdm-end.js line n, `S:n` = his "Squishy Duels LOADING
-- SCREEN Y MATCH HUD.dc.html"): the 3D end of a Team or Free for All match. MatchEnd starts it at the podium cue
-- (Config.UI.Match.finish.podium.at after the last squish, S:824: the jelly wave covers the screen) or at a skip, and
-- ends it with the session. Owner 2026-10-26: "Middle of the arena", "Top 6", "Two steps" (this is step 1; the
-- fireworks, balloons, spotlights, confetti and sprinkle rain are step 2). Every number is Config's (CFG below).
-- * Where: the match's map (Workspace.DuelMaps[view.mapName]; a preview: the first map of its mode): its pivot is the
--   centre, its Y the floor (MatchMapService's rule), the scene `lift` over it. The scene faces the one of `yaws`
--   turns from the map's own whose camera shots the map's geometry blocks least.
-- * On this screen only, while it shows: the camera is the scene's (deps.saveCamera / restoreCamera; its subject is the
--   scene's anchor, so Roblox's camera never fades the local character back in) and graded (a ColorCorrectionEffect on
--   the camera, E:205-206); the first-person hands are put away (deps.setAway); every match character (players, the
--   SD_Bots rigs), the players' held squishies (deps.setHeldHidden), the storm wall and the map's middle prop (its
--   parts within hideRadius of the centre, under hideTop, over the floor art: every one of Diego's maps has a prop
--   there) are hidden through LocalTransparencyModifier (their effects and labels off), written again each frame and
--   put back at the end.
-- * Who (lineup, pure; T:44-48 ranks()): Team: your team, the MVP first, then most squishes, then fewest times
--   squished; on the cake when it won, else (a loss, a draw) in the "good game" line. Free for All: the standings' top
--   (owner: "Top 6") on the cake for everyone; the line on a draw. At most `max`. Only the players whose body this
--   screen has stand (present, pure: one streamed out, a bot without a rig is left out and the rest close up; found in
--   a real match: alone at the line's 6th place); the crown is only the MVP's.
-- * The cake (E:35-63): three sponge tiers, a frosting cap in the winners' light colour, cream dollops round each top
--   edge (the design's torus rim), drips and sprinkles (its seeded Park-Miller spread), outlined by a Highlight (the
--   design's toon outline). Phones draw phoneDetail of the dollops, drips and sprinkles.
-- * The players (E:197-225): a copy of each one's character (Archivable on for the Clone, then back; a preview copies
--   the local character for its pretend players), its scripts, Animator and labels gone, its root anchored at its slot
--   facing the camera, every other part massless and non-colliding; Anim/PodiumPoses' clips on its joints (Motor6Ds or
--   the newer avatars' AnimationConstraints, JointLayer's rule; written in the render step, the parts follow on the
--   next frame) (VICTORY_ORDER by rank on the cake, DEFEAT_ORDER in the line), the root offset scaled to the rig's
--   height; each holds its own squishy (SquishyCache "World", squashed by SquishDeformer) where the clip's prop track
--   puts it (E:129-147). Before its clip starts a player idles (E:214). Cake ranks are timed so each HIT lands at
--   hits[rank] (E:18, 200); the line starts at line.start + line.step per player.
-- * HITs (E:151-171): ranks 2-6 pop stars at the chest, dip the FOV (not under ReducedMotion) and send "poseHit" { slot
--   = rank - 2 }; "hearts" pops hearts; the MVP's HIT is the slam: a hit-stop of the poses, two rings, a sprinkle
--   burst, a light flash, the camera kick and "mvpSlam" { strong }, then the crown (E:226-240) drops on the head
--   ("crown" when it lands), wobbles and bobs with the clip's loop.
-- * The camera (E:241-266, camera(), pure): the cake: an orbit closing in, a push up to the top, the hero shot, the FOV
--   ticks and the slam's kick (strong: settings' camera shake on, no ReducedMotion, your win; else a soft FOV dip),
--   then a slow breathing sway; the line: a slow push-in with the same sway.
-- * skip() (E:314-322) jumps to skipAt with every clip done (no more events) and the crown on.
-- * anchors() -> { { userId, at } }: the world point over each player's head where MatchEnd's name tag sits
--   (E:323-331).
-- * Round B2 (2026-10-26; owner: "Yes, build step 2 of round B like that. You can make and upload the pictures."):
--   the party whenever the cake shows (party, Config's numbers; phones take the budget's phone counts). Its pieces
--   are Roblox particles with the pictures of Diego's shapes (img.podium.*, white, tinted), spinning, shrinking away:
--   - cannons(spec) (E:93-105): at the "!" (S:831; MatchEnd, a victory), before the scene: 4 cannons at the map's
--     corners blast flakes, petals and cubes in turn in the winners' colours, lemon and white toward the middle,
--     with a star puff at each mouth; their own folder goes once the last piece is gone;
--   - spotlights (E:77-83, 296): 4 warm beams sweeping their aims round the cake (spotAim);
--   - fireworks (E:106-121): a rocket with a lemon-to-white trail every rocketGap from behind the cake, bursting into
--     stars and hearts;
--   - balloons (E:122-128, 300-301): at the design's times, the standing players' squishies in turn, scaled up on a
--     string, rising and swaying from either side (balloonStart);
--   - sprinkle rain (E:302-304) over the cake.
--   results() (E:312), and a skip, thin it: rainThin, rocketGapThin, the beams at thinAlpha. The design's bouncing
--   crowd (E:284) is not built: Diego's arenas here have no crowd.
-- Pure (unit-tested): lineup(view, teamOf, mvp), present(ids, has), slots(cake, n), starts(cake, n),
-- camera(tp, cake, shots), crownAt(u, f), bestYaw(blocked), cakeParts(detail): the cake's pieces as numbers;
-- cannonAim(x, z), spotAim(tp, i), balloonStart(i), split(n, k).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)

local Client = script.Parent.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local FxShapes = require(Client.Anim.FxShapes)
local PodiumPoses = require(Client.Anim.PodiumPoses)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishyCache = require(Client.Models.SquishyCache)

-- Types

export type Lineup = { cake: boolean, ids: { number }, mvp: number? }

-- MatchHudController's: the camera and the held squishies (the controllers this UI module may not require).
export type Deps = {
	saveCamera: () -> any,
	restoreCamera: (snapshot: any) -> (),
	setHeldHidden: (player: Player, hidden: boolean) -> (),
	gripC0: (hand: BasePart) -> CFrame,
	setAway: (on: boolean) -> (), -- FirstPersonController's: the first-person hands put away
}

export type Spec = {
	view: any, -- the Result freeze
	lineup: Lineup,
	who: (userId: number) -> any, -- MatchKit.who
	kind: string, -- MatchEnd's Result kind: "victory" | "defeat" | "draw"
	preview: boolean,
	compact: boolean,
	reduced: boolean,
	shake: boolean, -- settings' camera shake
	look: Color3, -- the winners' light colour (the frosting)
	main: Color3, -- round B2: the winners' main colour (the design's TEAM hex)
	onEvent: (name: string, data: { [string]: any }) -> (),
}

-- Round B2: the cannons at the "!".
export type CannonSpec = { view: any, preview: boolean, compact: boolean, main: Color3, light: Color3 }

export type Shots = { ticks: { number }, kickAt: number?, strong: boolean }

export type Podium = {
	step: (self: Podium, now: number) -> (),
	skip: (self: Podium) -> (),
	results: (self: Podium) -> (), -- round B2: the results are up (E:312): the party thins

	anchors: (self: Podium) -> { { userId: number, at: Vector3 } },
	destroy: (self: Podium) -> (),
}

type Joint = { motor: any, name: string } -- a Motor6D or an AnimationConstraint (both have .Transform: JointLayer's)

type Rig = {
	userId: number,
	rank: number,
	clip: PodiumPoses.Clip,
	start: number,
	base: CFrame, -- its feet at its slot, facing the camera (our -Z)
	k: number, -- its height against the design rig's
	model: Model,
	joints: { Joint },
	head: BasePart?,
	torso: BasePart?,
	hand: BasePart?,
	leftHand: BasePart?,
	toy: Model?,
	deformer: any,
	toyC1: CFrame?,
	lastF: number,
	done: boolean,
}

type CakePiece = { kind: string, size: Vector3, at: CFrame, color: string }

-- Round B2: a spotlight, a rocket, a balloon.
type Spot = { from: Vector3, tip: Attachment, beam: Beam }
type Rocket = { holder: BasePart, trail: Trail, p: Vector3, v: Vector3, t: number, life: number }
type Balloon = { toy: Model, cord: BasePart, p: Vector3, t: number, ph: number, speed: number }

-- Constants

local CFG = Config.UI.Match.finish.podium
local CAM = CFG.camera
local UP = Vector3.new(0, 1, 0)
local MAPS_FOLDER = "DuelMaps"
local BOTS_FOLDER = "SD_Bots" -- BotService: the match bots' rigs, named after the bot
local CLIENT_FX = "SD_ClientFx"
local STORM_WALL = "SD_StormWall" -- MatchController's
local ATTR_MATCH_ID = "SD_MatchId"
local PARTY = CFG.party
-- Round B2: the pictures of the design's particle shapes (fx.js:65-77), white to tint.
local STAR_KEY = "img.podium.star"
local HEART_KEY = "img.podium.heart"
local CHIP_KEY = "img.podium.chip" -- the flakes and the cubes
local PETAL_KEY = "img.podium.petal"
local SPRINKLE_KEY = "img.podium.sprinkle" -- the capsules
local FIRST_REAL_ID = 1 -- bots and the Studio fixtures' pretend players have ids below this
local log = Log.new("MatchPodium")

-- Module table

local MatchPodium = {}

-- Public: pure ----------------------------------------------------------------------------------------------------

local function eio(t: number): number
	local x = math.clamp(t, 0, 1)
	return if x < 0.5 then 4 * x * x * x else 1 - (-2 * x + 2) ^ 3 / 2
end

local function eout(t: number): number
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 3
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Who stands where (header). teamOf(userId) -> their team; mvp: MatchEnd.mvp (nil: none).
function MatchPodium.lineup(view: any, teamOf: (userId: number) -> string?, mvp: number?): Lineup?
	local outcome = type(view) == "table" and view.outcome
	if type(outcome) ~= "table" then
		return nil
	end
	local standings = outcome.standings or {}
	local rows: { any } = {}
	local cake: boolean
	if view.mode == "tdm" then
		local mine = type(view.you) == "table" and view.you.team or nil
		cake = outcome.kind == "win" and mine ~= nil and outcome.winnerTeam == mine
		for _, s in standings do
			if mine ~= nil and teamOf(s.userId) == mine then
				table.insert(rows, s)
			end
		end
		table.sort(rows, function(a: any, b: any): boolean
			local am, bm = cake and a.userId == mvp, cake and b.userId == mvp
			if am ~= bm then
				return am
			end
			if a.kos ~= b.kos then
				return a.kos > b.kos
			end
			return a.knockedOut < b.knockedOut
		end)
	else
		cake = outcome.kind == "win"
		rows = standings
	end
	local ids = {}
	for index, s in rows do
		if index > CFG.max then
			break
		end
		table.insert(ids, s.userId)
	end
	if #ids == 0 then
		return nil
	end
	return { cake = cake, ids = ids, mvp = if cake then mvp else nil }
end

-- The lineup's players that stand (header): those `has` says have a body here, in their order.
function MatchPodium.present(ids: { number }, has: (userId: number) -> boolean): { number }
	local out = {}
	for _, userId in ids do
		if has(userId) then
			table.insert(out, userId)
		end
	end
	return out
end

-- Each place { x, y, z, turn } (design studs, rad): the cake's ranks, or the line centred on the middle.
function MatchPodium.slots(cake: boolean, n: number): { { number } }
	local out = {}
	for i = 1, n do
		if cake then
			table.insert(out, CFG.cakeSlots[i])
		else
			local L = CFG.line
			local x = (i - (n + 1) / 2) * L.gap
			table.insert(out, { x, 0, L.depth - math.abs(x) * L.slope, -x * L.turn })
		end
	end
	return out
end

-- When each one's clip starts (podium seconds; E:200).
function MatchPodium.starts(cake: boolean, n: number): { number }
	local out = {}
	for i = 1, n do
		if cake then
			local clip = PodiumPoses.CLIPS[PodiumPoses.VICTORY_ORDER[i]]
			table.insert(out, CFG.hits[i] - (clip.hit or 0) / PodiumPoses.FPS)
		else
			table.insert(out, CFG.line.start + (i - 1) * CFG.line.step)
		end
	end
	return out
end

local function orbit(tp: number): (Vector3, Vector3)
	local O = CAM.orbit
	local u = eio((tp - O.from) / O.span)
	local a = math.rad(-O.deg + 2 * O.deg * u)
	local r = O.radius - O.close * u
	return Vector3.new(math.sin(a) * r, O.y + O.rise * u, math.cos(a) * r), Vector3.new(0, O.lookY, 0)
end

-- The camera at podium time tp (E:242-266), in the scene's frame: (position, look-at point, vertical FOV).
function MatchPodium.camera(tp: number, cake: boolean, shots: Shots): (Vector3, Vector3, number)
	local p, l, fov
	if not cake then
		local L = CAM.line
		local u = eio(tp / L.span)
		p, l, fov = v3(L.from):Lerp(v3(L.to), u), v3(L.look), L.fov
	else
		local P, H = CAM.push, CAM.hero
		p, l = orbit(tp)
		fov = P.fov
		if tp >= P.at then
			local u = eio((tp - P.at) / P.span)
			local p1, l1 = orbit(P.at)
			p, l = p1:Lerp(v3(P.pos), u), l1:Lerp(v3(P.look), u)
			fov = P.fov - (P.fov - P.fovTo) * u
		end
		if tp >= H.at then
			local u = eout((tp - H.at) / H.span)
			p, l = v3(P.pos):Lerp(v3(H.pos), u), v3(P.look):Lerp(v3(H.look), u)
			fov = P.fovTo - (P.fovTo - H.fovTo) * u
		end
		for _, t0 in shots.ticks do
			local k = (tp - t0) / CAM.tick.s
			if k >= 0 and k <= 1 then
				fov -= CAM.tick.fov * math.sin(math.pi * k)
			end
		end
		local kickAt = shots.kickAt
		if kickAt ~= nil and tp >= kickAt then
			local t = tp - kickAt
			if shots.strong then
				local K = CAM.kick
				fov += -K.fov * math.exp(-t * K.decay) * math.cos(t * K.freq)
				if t < K.shakeS then
					local amp = K.amp * (1 - t / K.shakeS)
					local side = (l - p):Cross(UP).Unit
					p += side * math.sin(2 * math.pi * K.hz * t) * amp + UP * math.cos(2 * math.pi * K.hz * t * K.yHz) * amp * K.yAmp
				end
			else
				fov -= CAM.softKick.fov * math.sin(math.pi * math.clamp(t / CAM.softKick.s, 0, 1))
			end
		end
	end
	local B = CAM.breathe
	if tp >= B.from or not cake then
		local d = (p - l).Magnitude
		local w = 2 * math.pi * B.hz * tp
		local side = (l - p):Cross(UP).Unit
		l += side * d * math.tan(math.rad(B.yawDeg) * math.sin(w)) + UP * d * math.tan(
			math.rad(B.pitchDeg) * math.sin(w + B.phase)
		)
	end
	return p, l, fov
end

-- The crown u s after the slam, the MVP's clip at frame f (E:226-240): its height over the seat, its spin (rad), its
-- squash (x/z, y) and whether it has landed.
function MatchPodium.crownAt(u: number, f: number): (number, number, number, number, boolean)
	local C = CFG.crown
	if u < C.dropS then
		local k = u / C.dropS
		return C.drop * (1 - k * k), (1 - k) * C.spin, 1, 1, false
	end
	local w = u - C.dropS
	local sq = if w < C.wobbleS then math.exp(-w * C.wobbleDecay) * math.cos(w * C.wobbleHz) else 0
	local bob = if f >= C.bobFrom then math.abs(math.sin((f - C.bobFrom) / C.bobFrames * math.pi)) * C.bob else 0
	return bob, 0, 1 + C.squashX * sq, 1 - C.squashY * sq, true
end

-- The turn with the fewest blocked shots (the first on a tie).
function MatchPodium.bestYaw(blocked: { number }): number
	local best = 1
	for i, n in blocked do
		if n < blocked[best] then
			best = i
		end
	end
	return best
end

-- The cake's pieces (E:40-59) in the scene's frame: kind "cylinder" (axis up), "ball" or "sprinkle" (lying flat);
-- color "sponge" | "frosting" | "cream" | "lemon" | "white" | "mint". detail: the share of dollops, drips and
-- sprinkles drawn (1 on desktop).
function MatchPodium.cakeParts(detail: number): { CakePiece }
	local C = CFG.cake
	local out: { CakePiece } = {}
	local function cylinder(radius: number, height: number, y: number, color: string)
		table.insert(out, {
			kind = "cylinder",
			size = Vector3.new(height, 2 * radius, 2 * radius),
			at = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color = color,
		})
	end
	for i, tier in C.tiers do
		local r, h, y0 = tier[1], tier[2], tier[3]
		local top = y0 + h
		cylinder(r, h, y0 + h / 2, "sponge")
		cylinder(r + C.capOver, C.capH, top - C.capDrop, "frosting")
		-- the cream rim: dollops round the top edge
		local dollops = math.max(6, math.round(2 * math.pi * r / C.dollopGap * detail))
		for k = 0, dollops - 1 do
			local a = k / dollops * 2 * math.pi
			table.insert(out, {
				kind = "ball",
				size = Vector3.one * 2 * C.rim,
				at = CFrame.new(math.cos(a) * r, top, math.sin(a) * r),
				color = "cream",
			})
		end
		-- drips down the side (E:45-46)
		local n = math.round(r * C.drips * detail)
		for k = 0, n - 1 do
			local a = k / n * 2 * math.pi + (i - 1)
			local j = k % 3
			local length = C.dripLen[1] + j * C.dripLen[2]
			local y = top - C.dripDrop[1] - j * C.dripDrop[2]
			local rr = r + 0.08
			local x, z = math.cos(a) * rr, math.sin(a) * rr
			table.insert(out, {
				kind = "cylinder",
				size = Vector3.new(length, 2 * C.drip, 2 * C.drip),
				at = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2),
				color = "frosting",
			})
			table.insert(out, {
				kind = "ball",
				size = Vector3.one * 2 * C.drip,
				at = CFrame.new(x, y - length / 2, z),
				color = "frosting",
			})
		end
	end
	-- the sprinkles (E:49-59): seed 7, four colour bins in turn
	local S = C.sprinkle
	local seed = C.seed
	local function rnd(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local bins = { "frosting", "lemon", "white", "mint" }
	for i, tier in C.tiers do
		local r, h, y0 = tier[1], tier[2], tier[3]
		local rIn = if i < #C.tiers then C.tiers[i + 1][1] + S.inner else S.centre
		local rOut = r - S.edge
		local count = math.round(C.sprinkles[i] * detail)
		for k = 0, C.sprinkles[i] - 1 do
			local a = rnd() * 2 * math.pi
			local rr = math.sqrt(rIn * rIn + rnd() * (rOut * rOut - rIn * rIn))
			local yaw = rnd() * math.pi
			if k < count then
				-- E:55: Euler (π/2, 0, yaw) lays the capsule flat along (-sin yaw, 0, cos yaw); our cylinder runs along X
				table.insert(out, {
					kind = "sprinkle",
					size = Vector3.new(S.length + 2 * S.radius, 2 * S.radius, 2 * S.radius),
					at = CFrame.new(math.cos(a) * rr, y0 + h + S.rise, math.sin(a) * rr)
						* CFrame.Angles(0, -(yaw + math.pi / 2), 0),
					color = bins[k % 4 + 1],
				})
			end
		end
	end
	return out
end

-- Round B2 (pure). A cannon at (x, z) aims over the middle (E:97): (-x, up, -z), as a unit, in the scene's frame.
function MatchPodium.cannonAim(x: number, z: number): Vector3
	return Vector3.new(-x, PARTY.cannons.up, -z).Unit
end

-- Spotlight i's aim at podium time tp (E:296), on the floor of the scene's frame.
function MatchPodium.spotAim(tp: number, i: number): Vector3
	local S = PARTY.spots.sweep
	return Vector3.new(math.sin(tp * S.xHz + (i - 1) * S.xPhase) * S.x, 0, math.cos(tp * S.zHz + (i - 1)) * S.z)
end

-- Balloon i's (0 first) string foot and rising speed (E:126-127): left first, then right, in turn.
function MatchPodium.balloonStart(i: number): (Vector3, number)
	local B = PARTY.balloons
	local side = if i % 2 == 1 then 1 else -1
	return Vector3.new(side * (B.x + (i * B.xStep) % B.xMod), B.y, -(B.z + (i * B.zStep) % B.zMod)),
		B.speed + (i % 3) * B.speedStep
end

-- n pieces dealt in turn into k groups (the design's i % k colours and kinds): each group's count.
function MatchPodium.split(n: number, k: number): { number }
	local out = {}
	for j = 1, k do
		out[j] = n // k + (if j <= n % k then 1 else 0)
	end
	return out
end

-- Private: building -----------------------------------------------------------------------------------------------

local function part(className: string, props: { [string]: any }): BasePart
	local made = Instance.new(className) :: BasePart
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Material = Enum.Material.SmoothPlastic
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(made :: any)[key] = value
		end
	end
	made.Parent = props.Parent
	return made
end

local function outline(model: Instance)
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineColor = Palette.StickerInk
	h.OutlineTransparency = CFG.cake.outline
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = model
end

local function buildCake(frame: CFrame, frosting: Color3, detail: number, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Cake"
	local colors: { [string]: Color3 } = {
		sponge = Palette.ArenaCakeSponge,
		frosting = frosting,
		cream = Palette.Frosting,
		lemon = Palette.Lemon,
		white = Color3.new(1, 1, 1),
		mint = Palette.StickerMintTop,
	}
	for _, piece in MatchPodium.cakeParts(detail) do
		local made = part("Part", {
			Name = piece.kind,
			Size = piece.size,
			CFrame = frame * piece.at,
			Color = colors[piece.color],
			Parent = model,
		}) :: Part
		made.Shape = if piece.kind == "ball" then Enum.PartType.Ball else Enum.PartType.Cylinder
	end
	outline(model)
	model.Parent = parent
	return model
end

type CrownPiece = { part: BasePart, at: CFrame, size: Vector3, ball: boolean }

local function buildCrown(parent: Instance): (Model, { CrownPiece })
	local C = CFG.crown
	local model = Instance.new("Model")
	model.Name = "Crown"
	local pieces: { CrownPiece } = {}
	local function add(className: string, size: Vector3, at: CFrame, color: Color3, ball: boolean?)
		local made = part(className, { Name = className, Size = size, CFrame = at, Color = color, Parent = model })
		if ball then
			(made :: Part).Shape = Enum.PartType.Ball
		end
		table.insert(pieces, { part = made, at = at, size = size, ball = ball == true })
	end
	-- the band: a ring of short pieces, each turned along the ring
	for i = 0, C.bandPieces - 1 do
		local a = i / C.bandPieces * 2 * math.pi
		local width = 2 * math.pi * C.radius / C.bandPieces * 1.08
		add(
			"Part",
			Vector3.new(width, C.bandH, C.bandThick),
			CFrame.new(math.cos(a) * C.radius, C.bandH / 2, math.sin(a) * C.radius)
				* CFrame.Angles(0, -(a + math.pi / 2), 0),
			Palette.Lemon
		)
	end
	-- the spikes (two wedges back to back: a flat point) and their gems; the first at the front (-Z here, the design's
	-- +Z: E:69)
	for i = 0, C.spikes - 1 do
		local a = i / C.spikes * 2 * math.pi - math.pi / 2
		local around = CFrame.new(math.cos(a) * C.radius, C.spikeY, math.sin(a) * C.radius)
			* CFrame.Angles(0, -(a + math.pi / 2), 0)
		local half = Vector3.new(C.bandThick, C.spikeH, C.spikeW / 2)
		add(
			"WedgePart",
			half,
			around * CFrame.new(-C.spikeW / 4, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Palette.Lemon
		)
		add(
			"WedgePart",
			half,
			around * CFrame.new(C.spikeW / 4, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			Palette.Lemon
		)
		add(
			"Part",
			Vector3.one * C.gem,
			CFrame.new(math.cos(a) * C.radius, C.gemY, math.sin(a) * C.radius),
			Color3.new(1, 1, 1),
			true
		)
	end
	outline(model)
	model.Parent = parent
	return model, pieces
end

local function placeCrown(pieces: { CrownPiece }, at: CFrame, k: number, sx: number, sy: number)
	for _, p in pieces do
		local pos = p.at.Position
		local scaled = Vector3.new(pos.X * sx, pos.Y * sy, pos.Z * sx) * k
		p.part.CFrame = at * CFrame.new(scaled) * p.at.Rotation
		p.part.Size = if p.ball
			then p.size * k * (sx + sy) / 2
			else Vector3.new(p.size.X * sx, p.size.Y * sy, p.size.Z * sx) * k
	end
end

-- Round B2: the party's pieces. A spray part (invisible, anchored) its emitters sit on, one per picture and colour.
local function sprayHolder(parent: Instance): BasePart
	return part("Part", { Name = "Spray", Size = Vector3.one * 0.2, Transparency = 1, Parent = parent })
end

local function spread(v: any, lo: number, hi: number): NumberRange
	return if type(v) == "table" then NumberRange.new(v[1], v[2]) else NumberRange.new(v * lo, v * hi)
end

-- A piece's span over its life: about S.size (a table: that range; a number: ±40%, E:104), shrinking away at the end.
local function sizes(v: any): NumberSequence
	local mid, env
	if type(v) == "table" then
		mid, env = (v[1] + v[2]) / 2, (v[2] - v[1]) / 2
	else
		mid, env = v, v * 0.4
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, mid, env),
		NumberSequenceKeypoint.new(0.85, mid, env),
		NumberSequenceKeypoint.new(1, 0),
	})
end

-- `count` pieces of picture `key` tinted `color` from `at`: along `aim` within S.spread degrees, or every way
-- (E:99-117). S: speed (studs/s), size, life, gravity (studs/s² down), drag (Roblox's halving rate), spinDeg, glow.
local function spray(holder: BasePart, at: Vector3, aim: Vector3?, count: number, key: string, color: Color3, S: any)
	if count <= 0 then
		return
	end
	local name = key .. "|" .. color:ToHex()
	local found = holder:FindFirstChild(name)
	local emitter: ParticleEmitter
	if found and found:IsA("ParticleEmitter") then
		emitter = found
	else
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = name
		emitter.Enabled = false
		emitter.Texture = AssetTable.image(key) or ""
		emitter.Color = ColorSequence.new(color)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.LightInfluence = 0
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Parent = holder
	end
	local up = if aim then aim.Unit else Vector3.yAxis
	holder.CFrame = if math.abs(up.Y) > 0.999
		then CFrame.new(at) * (if up.Y < 0 then CFrame.Angles(math.pi, 0, 0) else CFrame.identity)
		else CFrame.lookAt(at, at + up) * CFrame.Angles(-math.pi / 2, 0, 0) -- its top (the emission side) along aim
	local angle = if aim then S.spread or 0 else 180
	emitter.SpreadAngle = Vector2.new(angle, angle)
	emitter.Speed = spread(S.speed, 0.45, 1.2)
	emitter.Lifetime = spread(S.life, 0.7, 1.3)
	emitter.Size = sizes(S.size)
	emitter.Acceleration = Vector3.new(0, -(S.gravity or 0), 0)
	emitter.Drag = S.drag or 0
	emitter.RotSpeed = NumberRange.new(-(S.spinDeg or 0), S.spinDeg or 0)
	emitter.LightEmission = if S.glow then 0.5 else 0
	emitter:Emit(count)
end

-- A copy of a character for the scene, or nil.
local function copyCharacter(source: Model): Model?
	local was = source.Archivable
	source.Archivable = true
	local ok, copy = pcall(function(): Model?
		return source:Clone()
	end)
	source.Archivable = was
	if not ok or copy == nil then
		return nil
	end
	local model = copy :: Model
	for _, d in model:GetDescendants() do
		if
			d:IsA("BaseScript")
			or d:IsA("ModuleScript")
			or d:IsA("Animator")
			or d:IsA("ForceField")
			or d:IsA("Sound")
			or d:IsA("BillboardGui")
			or d:IsA("Highlight")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			(d :: any).Transform = CFrame.identity
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
	end
	return model
end

local function sourceCharacter(spec: Spec, userId: number): Model?
	local local_ = Players.LocalPlayer
	if spec.preview then
		return local_.Character
	end
	if userId >= FIRST_REAL_ID then
		local player = Players:GetPlayerByUserId(userId)
		return if player then player.Character else nil
	end
	-- a bot: its rig is named after it (BotService), in this match when it says so
	local bots = Workspace:FindFirstChild(BOTS_FOLDER)
	local name = nil
	for _, p in (spec.view.players or {}) :: { any } do
		if p.userId == userId then
			name = p.displayName
		end
	end
	if bots == nil or name == nil then
		return nil
	end
	local matchId = local_:GetAttribute(ATTR_MATCH_ID)
	local fallback: Model? = nil
	for _, rig in bots:GetChildren() do
		if rig:IsA("Model") and rig.Name == name then
			if matchId == nil or rig:GetAttribute(ATTR_MATCH_ID) == matchId then
				return rig
			end
			fallback = rig
		end
	end
	return fallback
end

-- Killcam step 1 (2026-10-26): UI/Match/Killcam copies the match players the same way.
MatchPodium.copyCharacter = copyCharacter
function MatchPodium.sourceCharacter(view: any, preview: boolean, userId: number): Model?
	return sourceCharacter({ view = view, preview = preview } :: any, userId)
end

local function findMap(view: any, preview: boolean): Model?
	local maps = Workspace:FindFirstChild(MAPS_FOLDER)
	if maps == nil then
		return nil
	end
	local found = maps:FindFirstChild(view.mapName or "")
	if found and found:IsA("Model") then
		return found
	end
	if preview then
		local mode = if view.mode == "tdm" then "TDM" else "FFA"
		for _, m in maps:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Mode") == mode then
				return m
			end
		end
	end
	return nil
end

-- The parts of the map's middle prop (header): their world box meets the circle round the centre above the floor art.
local function middleParts(map: Model, centre: Vector3, floorY: number): { BasePart }
	local out = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, size = d.CFrame, d.Size
			local ax = math.abs(cf.RightVector.X) * size.X
				+ math.abs(cf.UpVector.X) * size.Y
				+ math.abs(cf.LookVector.X) * size.Z
			local ay = math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z
			local az = math.abs(cf.RightVector.Z) * size.X
				+ math.abs(cf.UpVector.Z) * size.Y
				+ math.abs(cf.LookVector.Z) * size.Z
			local dx = math.max(0, math.abs(cf.Position.X - centre.X) - ax / 2)
			local dz = math.max(0, math.abs(cf.Position.Z - centre.Z) - az / 2)
			if
				dx * dx + dz * dz < CFG.hideRadius * CFG.hideRadius
				and cf.Position.Y + ay / 2 > floorY + CFG.hideFloor
				and cf.Position.Y - ay / 2 < floorY + CFG.hideTop
			then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- Public ----------------------------------------------------------------------------------------------------------

-- Round B2 (E:93-105): the confetti cannons at the "!" (header), round the map's centre in the map's own turn.
function MatchPodium.cannons(spec: CannonSpec)
	local map = findMap(spec.view, spec.preview)
	if map == nil then
		return
	end
	local C = PARTY.cannons
	local budget = PARTY.budget[if spec.compact then "phone" else "desktop"]
	local pivot = map:GetPivot()
	local frame = CFrame.new(pivot.X, pivot.Y + CFG.lift, pivot.Z) * pivot.Rotation
	local folder = Instance.new("Folder")
	folder.Name = "SD_PodiumCannons"
	folder.Parent = Workspace
	local holder = sprayHolder(folder)
	local kinds = { CHIP_KEY, PETAL_KEY, CHIP_KEY } -- E:100: flake, petal, cube
	local colors = { spec.main, spec.light, Palette.Lemon, Color3.new(1, 1, 1) }
	local piece =
		{ speed = C.speed, size = C.size, life = C.life, gravity = C.gravity, drag = C.drag, spinDeg = C.spinDeg }
	piece.spread = C.spread
	local puff = { speed = C.puff.speed, size = C.puff.size, life = C.puff.life, glow = true }
	for _, at in C.at do
		local mouth = frame * Vector3.new(at[1], C.y, at[2])
		local aim = frame:VectorToWorldSpace(MatchPodium.cannonAim(at[1], at[2]))
		-- 12 = the kinds' 3 by the colours' 4: piece i is kind i % 3 and colour i % 4
		for j, n in MatchPodium.split(budget.cannon, 12) do
			spray(holder, mouth, aim, n, kinds[(j - 1) % 3 + 1], colors[(j - 1) % 4 + 1], piece)
		end
		for j, n in MatchPodium.split(C.puff.count, 2) do
			spray(holder, mouth, nil, n, STAR_KEY, if j == 1 then Color3.new(1, 1, 1) else Palette.Lemon, puff)
		end
	end
	task.delay(C.life[2] * 1.3 + 0.5, function()
		folder:Destroy()
	end)
end

function MatchPodium.new(spec: Spec, deps: Deps): Podium?
	local view = spec.view
	local lineup = spec.lineup
	local map = findMap(view, spec.preview)
	if map == nil then
		log:warn(`no map {tostring(view.mapName)}: the podium is skipped`)
		return nil
	end
	local camera = Workspace.CurrentCamera
	local pivot = map:GetPivot()
	local centre = Vector3.new(pivot.X, pivot.Y + CFG.lift, pivot.Z)
	local cake = lineup.cake
	local strong = spec.shake and not spec.reduced and spec.kind == "victory"
	local detail = if spec.compact then CFG.cake.phoneDetail else 1
	local fx = FxPool.default()

	-- What this screen hides (header), and what it was.
	local hiddenParts: { [Instance]: number } = {}
	local switched: { [Instance]: boolean } = {}
	local heldHidden: { Player } = {}
	local characters: { Model } = {}
	local middle = middleParts(map, pivot.Position, pivot.Y)
	local function hidePart(d: Instance)
		if d:IsA("BasePart") or d:IsA("Decal") then
			if hiddenParts[d] == nil then
				hiddenParts[d] = (d :: any).LocalTransparencyModifier
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
	local function hideTree(root: Instance)
		hidePart(root)
		for _, d in root:GetDescendants() do
			hidePart(d)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
		deps.setHeldHidden(player, true)
		table.insert(heldHidden, player)
	end
	local bots = Workspace:FindFirstChild(BOTS_FOLDER)
	if bots then
		for _, rig in bots:GetChildren() do
			if rig:IsA("Model") then
				table.insert(characters, rig)
			end
		end
	end
	-- Everything to hide, listed once; written again each frame (Roblox's camera and the controllers may write some).
	local targets: { Instance } = {}
	for _, root in characters do
		table.insert(targets, root)
		for _, d in root:GetDescendants() do
			table.insert(targets, d)
		end
	end
	for _, p in middle do
		table.insert(targets, p)
		for _, d in p:GetDescendants() do
			table.insert(targets, d)
		end
	end
	local function hideAll()
		for _, d in targets do
			hidePart(d)
		end
		local clientFx = Workspace:FindFirstChild(CLIENT_FX)
		local wall = clientFx and clientFx:FindFirstChild(STORM_WALL)
		if wall then
			hideTree(wall)
		end
	end
	hideAll()

	-- The scene's turn: the one whose shots the map blocks least.
	local exclude: { Instance } = table.clone(middle)
	for _, c in characters do
		table.insert(exclude, c)
	end
	local fxFolder = Workspace:FindFirstChild(CLIENT_FX)
	if fxFolder then
		table.insert(exclude, fxFolder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local orbitFrom, orbitLook = orbit(0)
	local orbitTo = orbit(CAM.push.at)
	local shots: { { Vector3 } } = if cake
		then {
			{ orbitLook, orbitFrom },
			{ orbitLook, orbitTo },
			{ v3(CAM.push.look), v3(CAM.push.pos) },
			{ v3(CAM.hero.look), v3(CAM.hero.pos) },
		}
		else {
			{ v3(CAM.line.look), v3(CAM.line.from) },
			{ v3(CAM.line.look), v3(CAM.line.to) },
		}
	local _, baseYaw, _ = pivot:ToEulerAnglesYXZ()
	local blocked = {}
	for i = 1, CFG.yaws do
		local f = CFrame.new(centre) * CFrame.Angles(0, baseYaw + (i - 1) / CFG.yaws * 2 * math.pi, 0)
		local n = 0
		for _, shot in shots do
			local from, to = f * shot[1], f * shot[2]
			if Workspace:Raycast(from, to - from, params) ~= nil then
				n += 1
			end
		end
		blocked[i] = n
	end
	local yaw = baseYaw + (MatchPodium.bestYaw(blocked) - 1) / CFG.yaws * 2 * math.pi
	local frame = CFrame.new(centre) * CFrame.Angles(0, yaw, 0)

	-- The camera and its grade.
	local snapshot = deps.saveCamera()
	deps.setAway(true)
	local folder = Instance.new("Folder")
	folder.Name = "SD_Podium"
	folder.Parent = Workspace
	local anchor =
		part("Part", { Name = "Anchor", Size = Vector3.one, CFrame = frame, Transparency = 1, Parent = folder })
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = anchor
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SD_PodiumGrade"
	local G = CFG.grade
	grade.Saturation = if cake then G.cakeSaturation else G.lineSaturation
	grade.Brightness = if cake then 0 else G.lineBrightness
	grade.TintColor = if cake then Color3.new(1, 1, 1) else Palette.PodiumLineTint
	grade.Parent = camera

	-- The cake and the crown.
	local crownPieces: { CrownPiece } = {}
	local crownModel: Model? = nil
	if cake then
		buildCake(frame, spec.look, detail, folder)
		local made, pieces = buildCrown(folder)
		crownModel, crownPieces = made, pieces
		made.Parent = nil
	end

	-- The players: those with a body here, closed up.
	local copies: { [number]: Model } = {}
	local standing = MatchPodium.present(lineup.ids, function(userId: number): boolean
		local source = sourceCharacter(spec, userId)
		local copy = if source then copyCharacter(source) else nil
		if copy then
			copies[userId] = copy
		end
		return copy ~= nil
	end)
	local slots = MatchPodium.slots(cake, #standing)
	local starts = MatchPodium.starts(cake, #standing)
	local rigs: { Rig } = {}
	for i, userId in standing do
		local model = copies[userId]
		do
			local slot = slots[i]
			local base = frame * CFrame.new(slot[1], slot[2], slot[3]) * CFrame.Angles(0, slot[4] + math.pi, 0)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local height = if humanoid and root then humanoid.HipHeight + root.Size.Y / 2 else CFG.rigHeight
			if root then
				root.CFrame = base * CFrame.new(0, height, 0)
			end
			local joints: { Joint } = {}
			for _, name in PodiumPoses.ORDER do
				local path = PodiumPoses.JOINTS[name]
				local holder = model:FindFirstChild(path[1])
				local motor = holder and holder:FindFirstChild(path[2])
				if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
					table.insert(joints, { motor = motor, name = name })
				end
			end
			local clip = PodiumPoses.CLIPS[(if cake then PodiumPoses.VICTORY_ORDER else PodiumPoses.DEFEAT_ORDER)[i]]
			local rig: Rig = {
				userId = userId,
				rank = i,
				clip = clip,
				start = starts[i],
				base = base,
				k = height / CFG.rigHeight,
				model = model,
				joints = joints,
				head = model:FindFirstChild("Head") :: BasePart?,
				torso = model:FindFirstChild("UpperTorso") :: BasePart?,
				hand = model:FindFirstChild("RightHand") :: BasePart?,
				leftHand = model:FindFirstChild("LeftHand") :: BasePart?,
				toy = nil,
				deformer = nil,
				toyC1 = nil,
				lastF = -1,
				done = false,
			}
			model.Name = "Player_" .. tostring(userId)
			model.Parent = folder
			local who = spec.who(userId)
			local def = who and Catalog.get(who.squishyId)
			if def and rig.hand then
				local ok, toy = pcall(SquishyCache.clone, who.squishyId, "World")
				if ok and toy then
					rig.toy = toy
					rig.toyC1 = CFrame.new(def.hold.grip) * CFrame.Angles(0, math.rad(def.hold.heldYaw), 0)
					toy.Parent = folder
					local okD, deformer = pcall(SquishDeformer.attach, toy)
					rig.deformer = if okD then deformer else nil
				end
			end
			table.insert(rigs, rig)
		end
	end

	-- The timeline.
	local startAt: number? = nil
	local last = 0
	local tp, ptime, hitStop = 0, 0, 0
	local ticks: { number } = {}
	local kickAt: number? = nil
	local crownT = -1
	local crowned = false
	local skipped = false
	local mvpFrame = 0
	local finished = false

	-- Round B2: the party (header), whenever the cake shows.
	local budget = PARTY.budget[if spec.compact then "phone" else "desktop"]
	local white = Color3.new(1, 1, 1)
	local thin = false
	local sprayer = sprayHolder(folder)
	local spots: { Spot } = {}
	local rockets: { Rocket } = {}
	local rocketT = PARTY.rockets.first
	local balloons: { Balloon } = {}
	local balloonIndex = 0
	local rain: { ParticleEmitter } = {}
	local rng = Random.new()
	local function between(r: { number }): number
		return r[1] + rng:NextNumber() * (r[2] - r[1])
	end
	if cake then
		local Sp = PARTY.spots
		for _, from in Sp.from do
			local origin = Instance.new("Attachment")
			origin.Name = "SpotFrom"
			origin.Parent = anchor
			origin.WorldPosition = frame * v3(from)
			local tip = Instance.new("Attachment")
			tip.Name = "SpotTo"
			tip.Parent = anchor
			local beam = Instance.new("Beam")
			beam.Name = "Spot"
			beam.Attachment0 = origin
			beam.Attachment1 = tip
			beam.Width0 = 0.4
			beam.Width1 = 2 * Sp.radius
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Color = ColorSequence.new(Palette.PodiumSpot)
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Transparency = NumberSequence.new(1 - Sp.alpha)
			beam.Parent = anchor
			table.insert(spots, { from = origin.WorldPosition, tip = tip, beam = beam })
		end
		-- the rain: one emitter a colour over a box above the cake
		local R = PARTY.rain
		local cloud = part("Part", {
			Name = "Rain",
			Size = Vector3.new(R.area[1], R.ySpread, R.area[2]),
			CFrame = frame * CFrame.new(0, R.y + R.ySpread / 2, R.z0 + R.area[2] / 2),
			Transparency = 1,
			Parent = folder,
		})
		local colors = { spec.main, spec.look, Palette.Lemon, white, Palette.StickerMintTop, Palette.MatchEndLilac }
		for _, color in colors do
			local e = Instance.new("ParticleEmitter")
			e.Name = "Sprinkles"
			e.Texture = AssetTable.image(SPRINKLE_KEY) or ""
			e.Color = ColorSequence.new(color)
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.SpreadAngle = Vector2.new(5, 5)
			e.Speed = NumberRange.new(R.speed[1], R.speed[2])
			e.Acceleration = Vector3.new(0, -R.gravity, 0)
			e.Drag = R.drag
			e.Lifetime = NumberRange.new(R.life)
			e.Size = sizes(R.size)
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-R.spinDeg, R.spinDeg)
			e.LightInfluence = 0
			e.Rate = budget.rain / #colors
			e.Parent = cloud
			table.insert(rain, e)
		end
	end

	local function rocket()
		local R = PARTY.rockets
		local p = Vector3.new((rng:NextNumber() - 0.5) * 2 * R.halfX, R.y, -(R.back + rng:NextNumber() * R.backSpread))
		local v =
			Vector3.new((rng:NextNumber() - 0.5) * 2 * R.side, between(R.rise), (rng:NextNumber() - 0.5) * 2 * R.depth)
		local holder = part("Part", {
			Name = "Rocket",
			Size = Vector3.one * 0.2,
			CFrame = frame * CFrame.new(p),
			Transparency = 1,
			Parent = folder,
		})
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position = Vector3.new(-R.trail.width / 2, 0, 0)
		a1.Position = Vector3.new(R.trail.width / 2, 0, 0)
		a0.Parent, a1.Parent = holder, holder
		local trail = Instance.new("Trail") -- E:108: a lemon-to-white ribbon
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = R.trail.life
		trail.Color = ColorSequence.new(Palette.Lemon, white)
		trail.Transparency = NumberSequence.new(1 - R.trail.alpha, 1)
		trail.FaceCamera = true
		trail.LightEmission = 0.6
		trail.LightInfluence = 0
		trail.Parent = holder
		table.insert(rockets, { holder = holder, trail = trail, p = p, v = v, t = 0, life = between(R.life) })
	end

	local function party(dt: number, dtf: number)
		if not cake then
			return
		end
		local Sp = PARTY.spots
		for i, s in spots do
			local dir = (frame * MatchPodium.spotAim(tp, i) - s.from).Unit
			s.tip.WorldPosition = s.from + dir * Sp.length
		end
		-- fireworks
		local R = PARTY.rockets
		rocketT -= dt
		if rocketT <= 0 then
			rocket()
			rocketT = if thin then budget.rocketGapThin else budget.rocketGap
		end
		for index = #rockets, 1, -1 do
			local r = rockets[index]
			r.t += dtf
			r.v -= Vector3.new(0, R.gravity * dtf, 0)
			r.p += r.v * dtf
			r.holder.CFrame = frame * CFrame.new(r.p)
			if r.t >= r.life then
				local at = frame * r.p
				local stars = { spec.main, spec.look, Palette.Lemon, white }
				for j, n in MatchPodium.split(budget.sparks, #stars) do
					spray(sprayer, at, nil, n, STAR_KEY, stars[j], {
						speed = R.stars.speed,
						size = R.stars.size,
						life = R.stars.life,
						gravity = R.stars.gravity,
						drag = R.stars.drag,
						glow = true,
					})
				end
				local hearts = { spec.main, spec.look, Palette.StickerPinkSoft }
				for j, n in MatchPodium.split(budget.hearts, #hearts) do
					spray(sprayer, at, nil, n, HEART_KEY, hearts[j], R.hearts)
				end
				r.trail.Enabled = false
				local holder = r.holder
				task.delay(R.trail.life + 0.1, function()
					holder:Destroy()
				end)
				table.remove(rockets, index)
			end
		end
		-- balloons
		local B = PARTY.balloons
		while balloonIndex < math.min(budget.balloons, #B.at) and tp >= B.at[balloonIndex + 1] do
			local i = balloonIndex
			balloonIndex += 1
			local rig = rigs[i % math.max(#rigs, 1) + 1]
			local who = rig and spec.who(rig.userId)
			if who and Catalog.get(who.squishyId) then
				local ok, toy = pcall(SquishyCache.clone, who.squishyId, "World", B.scale)
				if ok and toy then
					toy.Name = "Balloon"
					toy.Parent = folder
					local cord = part("Part", {
						Name = "BalloonString",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(B.string, B.stringWidth, B.stringWidth),
						Color = Palette.Frosting,
						Parent = folder,
					})
					local p, speed = MatchPodium.balloonStart(i)
					table.insert(balloons, { toy = toy, cord = cord, p = p, t = 0, ph = i * B.phase, speed = speed })
				end
			end
		end
		for index = #balloons, 1, -1 do
			local q = balloons[index]
			q.t += dt
			q.p += Vector3.new(math.sin(q.t * B.sway[2] + q.ph) * B.sway[1] * dt, q.speed * dt, 0)
			local base = frame * CFrame.new(q.p) * CFrame.Angles(0, 0, math.sin(q.t * B.tilt[2] + q.ph) * B.tilt[1])
			q.toy:PivotTo(base * CFrame.new(0, B.lift, 0) * CFrame.Angles(0, math.pi, 0)) -- facing the camera
			q.cord.CFrame = base * CFrame.new(0, B.string / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			if q.p.Y > B.top then
				q.toy:Destroy()
				q.cord:Destroy()
				table.remove(balloons, index)
			end
		end
	end

	local function thinParty()
		if thin then
			return
		end
		thin = true
		for _, e in rain do
			e.Rate = budget.rainThin / #rain
		end
		for _, s in spots do
			s.beam.Transparency = NumberSequence.new(1 - PARTY.spots.thinAlpha)
		end
	end

	-- The slam's and the HITs' bursts (E:156-166): the design's capsules, stars and hearts (round B2's pictures).
	local function burst(at: Vector3, count: number, colors: { Color3 }, B: any, up: number, key: string)
		local texture = AssetTable.image(key) or ""
		local each = math.max(1, math.round(count / #colors))
		for _, color in colors do
			fx:emit(at, each, {
				Texture = texture,
				Color = ColorSequence.new(color),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, B.size), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(B.life * 0.8, B.life),
				Speed = NumberRange.new(B.speed[1], B.speed[2]),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, up, 0),
				Drag = 1.4,
				LightEmission = 0.4,
				LightInfluence = 0,
				RotSpeed = NumberRange.new(-180, 180),
			})
		end
	end

	local function slam()
		local S = CFG.slam
		hitStop = CFG.hitStop
		kickAt = tp
		FxShapes.ring(
			frame * Vector3.new(0, S.ring.y, 0),
			frame.UpVector,
			S.ring.size,
			S.ring.s,
			Color3.new(1, 1, 1),
			S.ring.from
		)
		local top = frame * Vector3.new(0, S.ring2.y, 0)
		FxShapes.ring(top, (camera.CFrame.Position - top).Unit, S.ring2.size, S.ring2.s, Palette.Lemon, S.ring2.from)
		burst(
			frame * Vector3.new(0, S.burst.y, 0),
			if spec.compact then S.burst.phone else S.burst.desktop,
			{ spec.look, Palette.Lemon, Color3.new(1, 1, 1), Palette.StickerMintTop, Palette.MatchEndLilac },
			S.burst,
			-S.burst.gravity,
			SPRINKLE_KEY
		)
		local light = Instance.new("PointLight")
		light.Color = Palette.PodiumSlamLight
		light.Brightness = S.light.brightness
		light.Range = S.light.range
		local holder = part("Part", {
			Name = "SlamLight",
			Size = Vector3.one,
			CFrame = frame * CFrame.new(0, S.light.y, S.light.z),
			Transparency = 1,
			Parent = folder,
		})
		light.Parent = holder
		task.delay(S.light.s, function()
			holder:Destroy()
		end)
		crownT = 0
		spec.onEvent("mvpSlam", { strong = strong })
	end

	local function onPoseEvent(rig: Rig, name: string)
		local chest = if rig.torso then (rig.torso.CFrame * CFrame.new(0, 0.2 * rig.k, -0.8 * rig.k)).Position else nil
		if name == "hit" then
			if rig.rank == 1 and cake then
				slam()
				return
			end
			if not spec.reduced then
				table.insert(ticks, tp)
			end
			if chest then
				local St = CFG.stars
				burst(
					chest,
					if spec.compact then St.phone else St.desktop,
					{ Palette.Lemon, Color3.new(1, 1, 1), spec.look },
					St,
					St.rise,
					STAR_KEY
				)
			end
			spec.onEvent("poseHit", { slot = rig.rank - 2 })
		elseif name == "hearts" and chest then
			local Ht = CFG.hearts
			burst(
				chest + Vector3.new(0, Ht.up * rig.k, 0),
				if spec.compact then Ht.phone else Ht.desktop,
				{ Palette.StickerPinkSoft, Palette.StickerFxPink, Color3.new(1, 1, 1) },
				Ht,
				-Ht.gravity,
				HEART_KEY
			)
		end
	end

	local function anchorCF(rig: Rig, m: string, o: { number }): CFrame
		local P = CFG.prop
		local k = rig.k
		local offset = rig.base:VectorToWorldSpace(PodiumPoses.flip(o) * k)
		if m == "air" then
			return rig.base * CFrame.new(PodiumPoses.flip(o) * k)
		end
		local hand, head, torso = rig.hand, rig.head, rig.torso
		local cf: CFrame
		if m == "head" and head then
			cf = head.CFrame * CFrame.new(0, head.Size.Y / 2 + P.headLift * k, 0)
		elseif m == "chest" and torso then
			cf = torso.CFrame * CFrame.new(0, P.chestUp * k, -P.chestFront * k)
		elseif m == "hands" and hand and rig.leftHand and torso then
			local a = (hand.CFrame * deps.gripC0(hand)).Position
			local b = (rig.leftHand.CFrame * CFrame.new(0, -P.handsDrop * k / 2, 0)).Position
			cf = CFrame.new((a + b) / 2) * torso.CFrame.Rotation
		elseif hand then
			cf = hand.CFrame * deps.gripC0(hand) * (rig.toyC1 :: CFrame):Inverse()
		else
			cf = rig.base
		end
		return cf + offset
	end

	local function placeToy(rig: Rig, f: number)
		local toy = rig.toy
		if toy == nil then
			return
		end
		local A, B, t = PodiumPoses.sampleProp(rig.clip, f)
		local a = anchorCF(rig, A.m, A.o)
		local b = anchorCF(rig, B.m, B.o)
		local r = { A.r[1] + (B.r[1] - A.r[1]) * t, A.r[2] + (B.r[2] - A.r[2]) * t, A.r[3] + (B.r[3] - A.r[3]) * t }
		toy:PivotTo(a:Lerp(b, t) * PodiumPoses.jointCFrame(r))
		local deformer = rig.deformer
		if deformer then
			deformer:setScale(
				Vector3.new(
					A.sc[1] + (B.sc[1] - A.sc[1]) * t,
					A.sc[2] + (B.sc[2] - A.sc[2]) * t,
					A.sc[3] + (B.sc[3] - A.sc[3]) * t
				)
			)
		end
	end

	local function runPoses()
		local I = CFG.idle
		for _, rig in rigs do
			local clip = rig.clip
			local t = ptime - rig.start
			local f = if t < 0 then 0 else PodiumPoses.frameAt(clip, t)
			local pose = PodiumPoses.samplePose(clip, f)
			if t < 0 then
				local b = math.sin(ptime * I.speed + (rig.rank - 1))
				pose.off = { pose.off[1], pose.off[2] + b * I.lift, pose.off[3] }
				pose.waist = { pose.waist[1] + b * I.waist, pose.waist[2], pose.waist[3] }
			end
			for _, joint in rig.joints do
				local cf = PodiumPoses.jointCFrame(pose[joint.name])
				if joint.name == "root" then
					cf = CFrame.new(PodiumPoses.flip(pose.off) * rig.k) * cf
				end
				joint.motor.Transform = cf
			end
			placeToy(rig, f)
			local raw = t * PodiumPoses.FPS
			if t >= 0 and not rig.done then
				for _, ev in clip.events do
					if ev.f > rig.lastF and ev.f <= raw then
						onPoseEvent(rig, ev.k)
					end
				end
				rig.lastF = raw
				if raw >= clip.len then
					rig.done = true
				end
			end
			if rig.rank == 1 then
				mvpFrame = f
			end
		end
	end

	local function crownStep()
		local crown = crownModel
		local mvp = rigs[1]
		if crown == nil or mvp == nil or mvp.userId ~= lineup.mvp or crownT < 0 or mvp.head == nil then
			if crown then
				crown.Parent = nil
			end
			return
		end
		crown.Parent = folder
		local head = mvp.head :: BasePart
		local seat = head.CFrame * CFrame.new(0, head.Size.Y / 2 + CFG.crown.seat * mvp.k, 0)
		local y, spin, sx, sy, landed = MatchPodium.crownAt(crownT, mvpFrame)
		if landed then
			if not crowned then
				crowned = true
				if not skipped then
					spec.onEvent("crown", {})
				end
			end
			placeCrown(crownPieces, seat * CFrame.new(0, y, 0), mvp.k, sx, sy)
		else
			placeCrown(
				crownPieces,
				CFrame.new(seat.Position + Vector3.new(0, y, 0)) * mvp.base.Rotation * CFrame.Angles(0, spin, 0),
				mvp.k,
				1,
				1
			)
		end
	end

	local function render()
		local p, l, fov = MatchPodium.camera(tp, cake, { ticks = ticks, kickAt = kickAt, strong = strong })
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(frame * p, frame * l)
		camera.FieldOfView = fov
	end

	local podium = {}

	function podium.step(_self: any, now: number)
		if finished then
			return
		end
		local at = startAt
		if at == nil then
			startAt = now
			last = now
		end
		local dt = math.clamp(now - last, 0, 0.1)
		last = now
		tp += dt
		local held = hitStop > 0 -- E:292: the hit-stop holds the poses and the fireworks too
		if held then
			hitStop -= dt
		else
			ptime += dt
		end
		if crownT >= 0 then
			crownT += dt
		end
		runPoses()
		crownStep()
		party(dt, if held then 0 else dt)
		render()
		hideAll()
	end

	function podium.results(_self: any)
		thinParty()
	end

	function podium.skip(_self: any)
		if finished then
			return
		end
		skipped = true
		thinParty()
		tp, ptime, hitStop = CFG.skipAt, CFG.skipAt, 0
		table.clear(ticks)
		kickAt = nil
		for _, rig in rigs do
			rig.done = true
			rig.lastF = math.huge
		end
		if cake then
			crownT = 1
			crowned = true
		end
	end

	function podium.anchors(_self: any): { { userId: number, at: Vector3 } }
		local out = {}
		for _, rig in rigs do
			local head = rig.head
			if head then
				local lift = if rig.rank == 1
						and rig.userId == lineup.mvp
						and cake
						and crownT >= 0
					then CFG.mvpPlateLift
					else CFG.plateLift
				table.insert(out, {
					userId = rig.userId,
					at = (head.CFrame * CFrame.new(0, head.Size.Y / 2 + lift * rig.k, 0)).Position,
				})
			end
		end
		return out
	end

	function podium.destroy(_self: any)
		if finished then
			return
		end
		finished = true
		for _, rig in rigs do
			if rig.deformer then
				pcall(rig.deformer.destroy, rig.deformer)
			end
		end
		folder:Destroy()
		if crownModel then
			crownModel:Destroy()
		end
		grade:Destroy()
		for d, value in hiddenParts do
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

	-- The first frame now, so the cut lands under the jelly wave.
	podium.step(podium, os.clock())
	return podium :: any
end

return MatchPodium
