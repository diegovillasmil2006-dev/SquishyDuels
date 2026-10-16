--!strict
-- KillBannerFormat (client, pure; kill banners 2026-10-16, VillasmilGaming: Valorant-style). The maths of the killer's
-- kill banner (UI/KillBanner draws it, Controllers/KillBannerController triggers it), unit-tested in Edit mode:
--   tierFor(streak)                 the banner for a K.O. streak: 1-6, every K.O. past the 6th shows the 6k banner
--   setFor(squishyId)               the kill set of the squishy that made the K.O. (Catalog eliminationEffectId,
--                                   Art/KillStyle.resolve: an unknown squishy or set plays "standard")
--   slots(tier)                     the ornaments to draw: { kind "ornament" | "crown", angle (degrees from the top,
--                                   clockwise), order (appearance order, 1 first), newest } — 1k-5k: one ornament per
--                                   K.O. at Config.UI.KillBanner.slotAngles; 6k: all five plus the crown pieces at
--                                   ±crownAngle (count per side, fanned), which are the newest
--   discPx(layoutHeight)            the medallion's diameter in px at UI scale 1 (discPx, at most discShare of the
--                                   height, at least discMinPx)
--   centerYShare(compact)           the medallion's centre, as a share of the gui height
--   soundRegion(tier)               (start, finish) seconds of the tier's sound in its sheet (Config.Audio.killBanner)
--   totalSeconds()                  intro + hold + outro
--   pose(t, slots, replaced, reduced, tier)  every animated value at t seconds since the K.O. (Pose below):
--                                   the medallion pops (from 0, or from replaceFromScale when a banner was showing),
--                                   overshoots to popScale and settles; a white flash fades; the glow swells and
--                                   breathes; the frame settles from 1.25 and spins; the earlier ornaments appear
--                                   staggered, the newest (or the 6k crown) pops to newestPopScale at newestAt; the
--                                   outro shrinks the medallion, flings the frame out and takes the ornaments back in
--                                   reverse. ReducedMotion: scale 1, no flash, no spin, a reducedFadeSeconds fade in and
--                                   out.
--   ornamentAngle(slotAngle, turn)  the picture's rotation: pointing out of the medallion, plus its own turn

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

export type PieceState = { scale: number, fade: number }

export type Pose = {
	medScale: number, -- the medallion (disc, ring, centre)
	medFade: number, -- 0 = solid .. 1 = gone
	flashFade: number,
	glowScale: number,
	glowFade: number,
	frameScale: number,
	frameFade: number,
	frameTurn: number, -- 0..1 of the style's spin per second, × t (the caller multiplies by its degrees/s)
	crownFrameScale: number,
	crownFrameFade: number,
	pieces: { PieceState }, -- per slot, in slots() order
	done: boolean,
}

-- Constants

local CFG = Config.UI.KillBanner
local AUDIO = Config.Audio.killBanner
local FLASH_SECONDS = 0.25
local FADE_IN_SECONDS = 0.08
local PIECE_POP_SECONDS = 0.18
local PIECE_OUT_SECONDS = 0.18
local PIECE_OUT_STAGGER = 0.025
local FRAME_FROM = 1.25
local GLOW_FADE = 0.35
local GLOW_PULSE = 0.04
local GLOW_HZ = 0.9
local CROWN_FRAME_FROM = 0.6
local OUTRO_SHRINK = 0.45

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

-- A pop: 0 -> peak over the first half of `seconds` (ease out), peak -> 1 over the second half.
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

function KillBannerFormat.discPx(layoutHeight: number): number
	local h = if layoutHeight == layoutHeight and layoutHeight > 0 then layoutHeight else 0
	local wanted = math.min(CFG.discPx, h * CFG.discShare)
	return math.floor(math.max(wanted, CFG.discMinPx) + 0.5)
end

function KillBannerFormat.centerYShare(compact: boolean): number
	return if compact then CFG.compactCenterYShare else CFG.centerYShare
end

function KillBannerFormat.soundRegion(tier: number): (number, number)
	local t = math.clamp(KillBannerFormat.tierFor(tier), 1, AUDIO.tiers)
	local start = (t - 1) * AUDIO.slotSeconds
	return start, start + AUDIO.soundSeconds
end

function KillBannerFormat.totalSeconds(): number
	return CFG.introSeconds + CFG.holdSeconds + CFG.outroSeconds
end

-- Pointing out of the medallion: a slot at `slotAngle` degrees from the top turns its picture by that much.
function KillBannerFormat.ornamentAngle(slotAngle: number, turn: number?): number
	return slotAngle + (turn or 0)
end

function KillBannerFormat.pose(
	t: number,
	slots: { Slot },
	replaced: boolean,
	reduced: boolean,
	tier: number
): Pose
	local intro, hold, outro = CFG.introSeconds, CFG.holdSeconds, CFG.outroSeconds
	local outroStart = intro + hold
	local total = outroStart + outro
	local pieces: { PieceState } = {}
	local six = KillBannerFormat.tierFor(tier) >= CFG.tiers

	if reduced then
		local fadeSeconds = CFG.reducedFadeSeconds
		local fadeIn = if replaced then 0 else 1 - clamp01(t / fadeSeconds)
		local fadeOut = clamp01((t - (total - fadeSeconds)) / fadeSeconds)
		local fade = math.max(fadeIn, fadeOut)
		for _ in slots do
			table.insert(pieces, { scale = 1, fade = fade })
		end
		return {
			medScale = 1,
			medFade = fade,
			flashFade = 1,
			glowScale = 1,
			glowFade = GLOW_FADE + (1 - GLOW_FADE) * fade,
			frameScale = 1,
			frameFade = fade,
			frameTurn = 0,
			crownFrameScale = 1,
			crownFrameFade = if six then fade else 1,
			pieces = pieces,
			done = t >= total,
		}
	end

	local from = if replaced then CFG.replaceFromScale else 0
	local medScale: number
	if t < intro then
		medScale = pop(t, 0, intro, from, CFG.popScale)
	elseif t < outroStart then
		medScale = 1
	else
		medScale = 1 - OUTRO_SHRINK * easeInCubic((t - outroStart) / outro)
	end
	local outroU = clamp01((t - outroStart) / outro)
	local fadeIn = if replaced then 0 else 1 - clamp01(t / FADE_IN_SECONDS)
	local medFade = math.max(fadeIn, easeInCubic(outroU))

	local flashFade = if t < FLASH_SECONDS then 0.1 + 0.9 * clamp01(t / FLASH_SECONDS) else 1

	local glowScale: number
	if t < intro then
		glowScale = pop(t, 0, intro, 0.7, 1.12)
	else
		glowScale = 1 + GLOW_PULSE * math.sin(2 * math.pi * GLOW_HZ * (t - intro))
	end
	local glowFade = GLOW_FADE + (1 - GLOW_FADE) * math.max(fadeIn, outroU)

	local frameScale = if t < intro then FRAME_FROM + (1 - FRAME_FROM) * easeOutCubic(t / intro) else 1
	if t >= outroStart then
		frameScale = 1 + 0.18 * easeOutCubic(outroU)
	end
	local frameFade = math.max(fadeIn, outroU)

	local crownFrameScale, crownFrameFade = 1, 1
	if six then
		crownFrameScale = if t < CFG.newestAt
			then CROWN_FRAME_FROM
			else CROWN_FRAME_FROM + (1 - CROWN_FRAME_FROM) * easeOutCubic((t - CFG.newestAt) / PIECE_POP_SECONDS)
		crownFrameFade = if t < CFG.newestAt then 1 else math.max(0, outroU)
		if t >= outroStart then
			crownFrameScale = 1 + 0.25 * easeOutCubic(outroU)
		end
	end

	local count = #slots
	for index, slot in slots do
		local at = if slot.newest then CFG.newestAt else 0.06 + CFG.staggerSeconds * (slot.order - 1)
		local peak = if slot.newest then CFG.newestPopScale else 1.12
		local scale = if t < at then 0 else pop(t, at, PIECE_POP_SECONDS, 0, peak)
		local fade = if t < at then 1 else 0
		local leave = outroStart + PIECE_OUT_STAGGER * (count - index)
		if t >= leave then
			local u = clamp01((t - leave) / PIECE_OUT_SECONDS)
			scale *= 1 - easeInCubic(u)
			fade = math.max(fade, u)
		end
		pieces[index] = { scale = scale, fade = fade }
	end

	return {
		medScale = medScale,
		medFade = medFade,
		flashFade = flashFade,
		glowScale = glowScale,
		glowFade = glowFade,
		frameScale = frameScale,
		frameFade = frameFade,
		frameTurn = t,
		crownFrameScale = crownFrameScale,
		crownFrameFade = crownFrameFade,
		pieces = pieces,
		done = t >= total,
	}
end

return KillBannerFormat
