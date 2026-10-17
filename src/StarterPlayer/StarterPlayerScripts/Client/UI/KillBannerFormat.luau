--!strict
-- KillBannerFormat (client, pure; kill banners 2026-10-16, v2 2026-10-17, VillasmilGaming: Valorant-style). The maths of
-- the killer's kill banner (UI/KillBanner draws it, Controllers/KillBannerController triggers it), unit-tested in Edit
-- mode. Sizes are in emblems (1 = the emblem's width), angles in degrees from the top, clockwise; t in seconds.
--   tierFor(streak)                 the banner for a K.O. streak: 1-6, every K.O. past the 6th shows the 6k banner
--   setFor(squishyId)               the kill set of the squishy that made the K.O. (Catalog eliminationEffectId,
--                                   Art/KillStyle.resolve: an unknown squishy or set plays "standard")
--   slots(tier, crownCount?, fan?)  the ornaments: { kind "ornament" | "crown", angle, order, newest } — 1k-5k: one per
--                                   K.O. at Config.UI.KillBanner.slotAngles; 6k: all five plus the crown pieces at
--                                   ±crownAngle (count per side, fanned), which are the newest
--   shards(count, seed)             the impact shards: { angle, dist, size, spin, delay } (Random(seed): the same for a
--                                   seed), spread round the emblem, a jitter each
--   emblemPx(layoutHeight)          the emblem's width in px at UI scale 1 (emblemPx, at most emblemShare of the height,
--                                   at least emblemMinPx)
--   centerY(height, barBottom?, emblem)  the banner's centre in px from the gui's top: under the duel / match HUD's top
--                                   bar (barBottom + gap + the banner's upper reach), never above topShare of the height
--                                   (no bar: topShare); the held squishy at the bottom of the screen stays clear
--   soundRegion(tier)               (start, finish) seconds of the tier's sound in its sheet (Config.Audio.killBanner)
--   totalSeconds()                  intro + hold + outro
--   pose(t, slots, shards, replaced, reduced, tier)  every animated value at t (Pose below):
--     intro: the emblem SLAMS in from slamFrom× (turned slamTurn°, see-through) to slamDip× at slamAt, bounces to
--     popScale and settles; its white silhouette flashes and fades; two shock rings and two light slashes burst out;
--     the shards fly out spinning; the rays spin fast and slow down; the frame settles from 1.3 and spins; the whole
--     banner shakes (shakeEm, decaying); the earlier ornaments fly in staggered from flyFrom× their radius, spinning,
--     the newest (or the 6k crown) slams in at newestAt with its own small shake.
--     hold: the emblem breathes, the glow pulses, the frame and the rays turn.
--     outro: the emblem squashes (wide, flat) and pops away, the ornaments fly back out and fade, the rest fades.
--     A K.O. during a banner restarts it from replaceFrom× (no blink). ReducedMotion: no slam, shake, spin, rays or
--     shards; plain fades (reducedFadeSeconds).
--   ornamentAngle(slotAngle, turn)  the picture's rotation: pointing out of the emblem, plus its own turn

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local KillStyle = require(Shared.Art.KillStyle)

-- Types

export type Slot = {
	kind: string, -- "ornament" | "crown"
	angle: number,
	order: number,
	newest: boolean,
}

export type Shard = {
	angle: number, -- degrees from the top
	dist: number, -- how far it flies (emblems)
	size: number, -- emblems
	spin: number, -- degrees over its flight
	delay: number, -- seconds after the slam
}

export type PieceState = { scale: number, fade: number, radius: number, spin: number }
export type RingState = { scale: number, fade: number, thickness: number }
export type ShardState = { x: number, y: number, scale: number, fade: number, rot: number }

export type Pose = {
	shakeX: number, -- emblems
	shakeY: number,
	emblemScale: number,
	emblemSquashX: number,
	emblemSquashY: number,
	emblemTurn: number, -- degrees
	emblemFade: number, -- 0 = solid .. 1 = gone
	flashFade: number,
	shadowFade: number,
	glowScale: number,
	glowFade: number,
	raysScale: number,
	raysTurn: number,
	raysFade: number,
	frameScale: number,
	frameFade: number,
	frameTurn: number, -- seconds of spin at the style's speed (the caller multiplies by its degrees/s)
	frameBoost: number, -- extra degrees from the intro's fast spin
	crownFrameScale: number,
	crownFrameFade: number,
	slashScale: number, -- the slashes' length (emblems)
	slashFade: number,
	rings: { RingState },
	pieces: { PieceState }, -- per slot, in slots() order
	shards: { ShardState }, -- per shard, in shards() order
	done: boolean,
}

-- Constants

local CFG = Config.UI.KillBanner
local AUDIO = Config.Audio.killBanner
local RING_DELAY = 0.07 -- the second shock ring follows the first
local RING_SECONDS = 0.42
local RING_FROM, RING_TO = 0.55, 2.7
local SLASH_SECONDS = 0.22
local SHARD_SECONDS = 0.55
local PIECE_POP_SECONDS = 0.22
local PIECE_OUT_SECONDS = 0.2
local PIECE_OUT_STAGGER = 0.025
local FRAME_FROM = 1.3
local GLOW_FADE = 0.3
local GLOW_PULSE = 0.06
local GLOW_HZ = 1.4
local BREATH = 0.025
local BREATH_HZ = 1.1
local RAYS_FADE = 0.45
local RAYS_SPIN = 30 -- degrees/s while holding
local RAYS_BOOST = 540 -- degrees the intro adds, slowing down
local FRAME_BOOST = 420
local SQUASH_SHARE = 0.35 -- the outro's squash part, then the pop away
local FLASH_SECONDS = 0.22 -- the white silhouette fades this long after the slam

-- Module table

local KillBannerFormat = {}

-- Private

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function easeOutCubic(u: number): number
	local v = 1 - clamp01(u)
	return 1 - v * v * v
end

local function easeInCubic(u: number): number
	local v = clamp01(u)
	return v * v * v
end

local function easeInOutSine(u: number): number
	return 0.5 - 0.5 * math.cos(math.pi * clamp01(u))
end

local function easeOutBack(u: number): number
	local c1, c3 = 1.70158, 2.70158
	local v = clamp01(u) - 1
	return 1 + c3 * v * v * v + c1 * v * v
end

-- A pop: from -> peak over the first half of `seconds` (ease out), peak -> 1 over the second half.
local function pop(t: number, at: number, seconds: number, from: number, peak: number): number
	local u = (t - at) / seconds
	if u <= 0 then
		return from
	elseif u < 0.5 then
		return from + (peak - from) * easeOutCubic(u / 0.5)
	elseif u < 1 then
		return peak + (1 - peak) * easeInOutSine((u - 0.5) / 0.5)
	end
	return 1
end

-- A decaying shake (emblems) at t seconds after it started: two sines out of phase, (1 - u)² of the amplitude.
local function shake(t: number, at: number, amplitude: number, seconds: number): (number, number)
	local u = (t - at) / seconds
	if u < 0 or u >= 1 then
		return 0, 0
	end
	local a = amplitude * (1 - u) * (1 - u)
	return a * math.sin(t * 97), a * math.cos(t * 83)
end

-- Public

function KillBannerFormat.tierFor(streak: unknown): number
	if type(streak) ~= "number" or streak ~= streak then
		return 1
	end
	return math.clamp(math.floor(streak), 1, CFG.tiers)
end

function KillBannerFormat.setFor(squishyId: unknown): string
	local def = if type(squishyId) == "string" then Catalog.get(squishyId) else nil
	if def == nil then
		return KillStyle.STANDARD
	end
	return KillStyle.resolve(def.eliminationEffectId)
end

function KillBannerFormat.slots(tier: number, crownCount: number?, crownFan: number?): { Slot }
	local list: { Slot } = {}
	local t = KillBannerFormat.tierFor(tier)
	local ornaments = math.min(t, #CFG.slotAngles)
	for i = 1, ornaments do
		table.insert(list, { kind = "ornament", angle = CFG.slotAngles[i], order = i, newest = t < CFG.tiers and i == t })
	end
	if t >= CFG.tiers then
		local count = math.max(math.floor(crownCount or 1), 1)
		local fan = crownFan or 0
		local order = ornaments
		for _, side in { -1, 1 } do
			for k = 1, count do
				order += 1
				local offset = (k - (count + 1) / 2) * fan
				table.insert(list, { kind = "crown", angle = side * (CFG.crownAngle + offset), order = order, newest = true })
			end
		end
	end
	return list
end

function KillBannerFormat.shards(count: number, seed: number): { Shard }
	local rng = Random.new(seed)
	local list: { Shard } = {}
	local n = math.max(math.floor(count), 0)
	for i = 1, n do
		table.insert(list, {
			angle = (i - 1) * 360 / n + rng:NextNumber(-12, 12),
			dist = CFG.shardDistance * rng:NextNumber(0.75, 1.15),
			size = CFG.shardSize * rng:NextNumber(0.6, 1.2),
			spin = rng:NextNumber(-540, 540),
			delay = rng:NextNumber(0, 0.06),
		})
	end
	return list
end

function KillBannerFormat.emblemPx(layoutHeight: number): number
	local h = if layoutHeight == layoutHeight and layoutHeight > 0 then layoutHeight else 0
	local wanted = math.min(CFG.emblemPx, h * CFG.emblemShare)
	return math.floor(math.max(wanted, CFG.emblemMinPx) + 0.5)
end

function KillBannerFormat.centerY(height: number, barBottom: number?, emblem: number): number
	local h = if height == height and height > 0 and height < math.huge then height else 0
	local y = h * CFG.topShare
	if barBottom and barBottom == barBottom and math.abs(barBottom) < math.huge then
		y = math.max(y, barBottom + CFG.gapPx + emblem * CFG.upperReach)
	end
	return y
end

function KillBannerFormat.soundRegion(tier: number): (number, number)
	local t = math.clamp(KillBannerFormat.tierFor(tier), 1, AUDIO.tiers)
	local start = (t - 1) * AUDIO.slotSeconds
	return start, start + AUDIO.soundSeconds
end

function KillBannerFormat.totalSeconds(): number
	return CFG.introSeconds + CFG.holdSeconds + CFG.outroSeconds
end

function KillBannerFormat.ornamentAngle(slotAngle: number, turn: number?): number
	return slotAngle + (turn or 0)
end

function KillBannerFormat.pose(
	t: number,
	slots: { Slot },
	shards: { Shard },
	replaced: boolean,
	reduced: boolean,
	tier: number
): Pose
	local intro, hold, outro = CFG.introSeconds, CFG.holdSeconds, CFG.outroSeconds
	local outroStart = intro + hold
	local total = outroStart + outro
	local six = KillBannerFormat.tierFor(tier) >= CFG.tiers
	local pieces: { PieceState } = {}
	local shardStates: { ShardState } = {}
	local rings: { RingState } = {}

	if reduced then
		local fadeSeconds = CFG.reducedFadeSeconds
		local fadeIn = if replaced then 0 else 1 - clamp01(t / fadeSeconds)
		local fadeOut = clamp01((t - (total - fadeSeconds)) / fadeSeconds)
		local fade = math.max(fadeIn, fadeOut)
		for _ in slots do
			table.insert(pieces, { scale = 1, fade = fade, radius = 1, spin = 0 })
		end
		for _ in shards do
			table.insert(shardStates, { x = 0, y = 0, scale = 0, fade = 1, rot = 0 })
		end
		for _ = 1, 2 do
			table.insert(rings, { scale = 1, fade = 1, thickness = 0 })
		end
		return {
			shakeX = 0,
			shakeY = 0,
			emblemScale = 1,
			emblemSquashX = 1,
			emblemSquashY = 1,
			emblemTurn = 0,
			emblemFade = fade,
			flashFade = 1,
			shadowFade = 0.45 + 0.55 * fade,
			glowScale = 1,
			glowFade = GLOW_FADE + (1 - GLOW_FADE) * fade,
			raysScale = 1,
			raysTurn = 0,
			raysFade = 1,
			frameScale = 1,
			frameFade = fade,
			frameTurn = 0,
			frameBoost = 0,
			crownFrameScale = 1,
			crownFrameFade = if six then fade else 1,
			slashScale = 0,
			slashFade = 1,
			rings = rings,
			pieces = pieces,
			shards = shardStates,
			done = t >= total,
		}
	end

	local outroU = clamp01((t - outroStart) / outro)
	local fadeIn = if replaced then 0 else 1 - clamp01(t / CFG.slamAt)

	-- the emblem: slam (from slamFrom, turned and see-through) -> dip at slamAt -> popScale -> 1; breath; squash, pop
	local emblemScale: number
	local emblemTurn = 0
	local from = if replaced then CFG.replaceFrom else CFG.slamFrom
	if t < CFG.slamAt then
		local u = clamp01(t / CFG.slamAt)
		emblemScale = from + (CFG.slamDip - from) * easeInCubic(u)
		emblemTurn = (if replaced then 0 else CFG.slamTurn) * (1 - u)
	elseif t < intro then
		local u = (t - CFG.slamAt) / (intro - CFG.slamAt)
		emblemScale = if u < 0.45
			then CFG.slamDip + (CFG.popScale - CFG.slamDip) * easeOutCubic(u / 0.45)
			else CFG.popScale + (1 - CFG.popScale) * easeInOutSine((u - 0.45) / 0.55)
	elseif t < outroStart then
		emblemScale = 1 + BREATH * math.sin(2 * math.pi * BREATH_HZ * (t - intro))
	else
		emblemScale = 1
	end
	local squashX, squashY = 1, 1
	if t >= outroStart then
		if outroU < SQUASH_SHARE then
			local u = easeOutCubic(outroU / SQUASH_SHARE)
			squashX, squashY = 1 + 0.28 * u, 1 - 0.38 * u
		else
			local u = easeInCubic((outroU - SQUASH_SHARE) / (1 - SQUASH_SHARE))
			squashX, squashY = 1.28 * (1 - u), 0.62 + 0.6 * u
			emblemScale = 1 - u
			emblemTurn = 25 * u
		end
	end
	local emblemFade = math.max(fadeIn * 0.85, easeInCubic(clamp01((outroU - SQUASH_SHARE) / (1 - SQUASH_SHARE))))

	-- the white silhouette flash (at the slam) and the ink shadow
	local flashIn = CFG.slamAt * 0.6
	local flashFade = 1
	if t >= flashIn and t < CFG.slamAt then
		flashFade = 1 - 0.9 * (t - flashIn) / (CFG.slamAt - flashIn)
	elseif t >= CFG.slamAt and t < CFG.slamAt + FLASH_SECONDS then
		flashFade = 0.1 + 0.9 * (t - CFG.slamAt) / FLASH_SECONDS
	end
	local shadowFade = 0.45 + 0.55 * emblemFade

	-- the whole banner shakes at the slam, and again (smaller) when the newest ornament slams in
	local sx1, sy1 = shake(t, CFG.slamAt, CFG.shakeEm, 0.3)
	local sx2, sy2 = shake(t, CFG.newestAt + PIECE_POP_SECONDS * 0.5, CFG.shakeEm * (if six then 0.9 else 0.45), 0.25)

	-- glow, rays, frame
	local glowScale = if t < intro then pop(t, 0, intro, 0.6, 1.25) else 1 + GLOW_PULSE * math.sin(2 * math.pi * GLOW_HZ * (t - intro))
	local glowFade = GLOW_FADE + (1 - GLOW_FADE) * math.max(fadeIn, outroU)
	local raysScale = if t < intro then pop(t, CFG.slamAt * 0.5, intro, 0.3, 1.15) else 1
	local raysBoost = RAYS_BOOST * easeOutCubic(t / (intro + 0.5))
	local raysFade = RAYS_FADE + (1 - RAYS_FADE) * math.max(fadeIn, outroU)
	if not six and tier < 5 then
		raysFade = 0.68 + 0.32 * math.max(fadeIn, outroU) -- quieter rays below 5k
	end
	local frameScale = if t < intro then FRAME_FROM + (1 - FRAME_FROM) * easeOutCubic(t / intro) else 1
	if t >= outroStart then
		frameScale = 1 + 0.22 * easeOutCubic(outroU)
	end
	local frameFade = math.max(fadeIn, outroU)
	local frameBoost = FRAME_BOOST * easeOutCubic(t / (intro + 0.4))

	local crownFrameScale, crownFrameFade = 1, 1
	if six then
		crownFrameScale = if t < CFG.newestAt then 0.5 else pop(t, CFG.newestAt, PIECE_POP_SECONDS, 0.5, 1.12)
		crownFrameFade = if t < CFG.newestAt then 1 else outroU
		if t >= outroStart then
			crownFrameScale = 1 + 0.3 * easeOutCubic(outroU)
		end
	end

	-- the slashes and the shock rings
	local su = (t - CFG.slamAt * 0.7) / SLASH_SECONDS
	local slashScale = if su <= 0 then 0 else CFG.slashLength * easeOutCubic(su)
	local slashFade = if su <= 0 or su >= 1 then 1 else easeInCubic(su)
	for i = 1, 2 do
		local ru = (t - CFG.slamAt - (i - 1) * RING_DELAY) / RING_SECONDS
		if ru <= 0 or ru >= 1 then
			table.insert(rings, { scale = RING_FROM, fade = 1, thickness = 0 })
		else
			table.insert(rings, {
				scale = RING_FROM + (RING_TO + (i - 1) * 0.4 - RING_FROM) * easeOutCubic(ru),
				fade = easeInCubic(ru),
				thickness = (1 - ru) * (if i == 1 then 1 else 0.6),
			})
		end
	end

	-- the shards (flying out from the slam)
	for _, shard in shards do
		local u = (t - CFG.slamAt - shard.delay) / SHARD_SECONDS
		if u <= 0 or u >= 1 then
			table.insert(shardStates, { x = 0, y = 0, scale = 0, fade = 1, rot = 0 })
		else
			local d = (0.35 + shard.dist * easeOutCubic(u))
			local a = math.rad(shard.angle)
			table.insert(shardStates, {
				x = math.sin(a) * d,
				y = -math.cos(a) * d,
				scale = shard.size * (1 - 0.6 * u),
				fade = easeInCubic(u),
				rot = shard.angle + shard.spin * u,
			})
		end
	end

	-- the ornaments: fly in spinning (staggered), the newest slams in at newestAt; fly back out in the outro
	local count = #slots
	for index, slot in slots do
		local at = if slot.newest then CFG.newestAt else CFG.slamAt + CFG.staggerSeconds * (slot.order - 1)
		local peak = if slot.newest then CFG.newestPopScale else 1.15
		local u = (t - at) / PIECE_POP_SECONDS
		local scale = if u <= 0 then 0 else pop(t, at, PIECE_POP_SECONDS, 0.2, peak)
		local radius = if u <= 0 then CFG.flyFrom else 1 + (CFG.flyFrom - 1) * (1 - easeOutBack(u))
		local spin = if u <= 0 then 240 else 240 * (1 - easeOutCubic(u))
		local fade = if u <= 0 then 1 else 0
		local leave = outroStart + PIECE_OUT_STAGGER * (count - index)
		if t >= leave then
			local lu = clamp01((t - leave) / PIECE_OUT_SECONDS)
			scale *= 1 - easeInCubic(lu)
			radius = 1 + 0.6 * easeInCubic(lu)
			fade = math.max(fade, lu)
		end
		pieces[index] = { scale = scale, fade = fade, radius = radius, spin = spin }
	end

	return {
		shakeX = sx1 + sx2,
		shakeY = sy1 + sy2,
		emblemScale = emblemScale,
		emblemSquashX = squashX,
		emblemSquashY = squashY,
		emblemTurn = emblemTurn,
		emblemFade = emblemFade,
		flashFade = flashFade,
		shadowFade = shadowFade,
		glowScale = glowScale,
		glowFade = glowFade,
		raysScale = raysScale,
		raysTurn = RAYS_SPIN * t + raysBoost,
		raysFade = raysFade,
		frameScale = frameScale,
		frameFade = frameFade,
		frameTurn = t,
		frameBoost = frameBoost,
		crownFrameScale = crownFrameScale,
		crownFrameFade = crownFrameFade,
		slashScale = slashScale,
		slashFade = slashFade,
		rings = rings,
		pieces = pieces,
		shards = shardStates,
		done = t >= total,
	}
end

return KillBannerFormat
