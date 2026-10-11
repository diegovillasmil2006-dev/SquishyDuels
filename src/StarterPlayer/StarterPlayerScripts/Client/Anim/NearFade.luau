--!strict
-- NearFade (client only, pure): first-person face safety (first-person spec 2026-10-10 §3.10). In first person, world
-- effects that come at the local camera fade out instead of filling the screen: projectiles and their outline
-- Highlights (ProjectileRenderer) and every Dragon Rush head (VfxController), through LocalTransparencyModifier. The
-- callers apply it only while first person is on; numbers in Config.FirstPerson (nearFade, rushFadeIn).
--
-- API
--   NearFade.amount(distance) -> number         0 beyond nearFade.to (4.5 studs from the camera), 1 inside
--                                               nearFade.from (2.5), linear between; 0 for a bad distance
--   NearFade.rushFadeIn(travelled) -> number    the local caster's own Rush head: 1 (clear) until rushFadeIn.from
--                                               (3 studs travelled from the lane origin), 0 (solid) at rushFadeIn.to (8)
--   NearFade.toward(value, near) -> number      a Highlight transparency moved toward 1 by `near` (a Highlight may
--                                               not follow LocalTransparencyModifier)
--   NearFade.projectile(distance, own, sinceRelease) -> number   amount(distance), except 0 for the local player's
--                                               own projectile in its first OWN_GRACE_SECONDS, which starts at the
--                                               hand on purpose (§3.6)
--   NearFade.rushHead(endFade, travelled, distance, isCaster, firstPerson) -> number   the head's modifier: the end
--                                               fade alone in third person; in first person the max of the end fade,
--                                               the caster's fade-in (isCaster only) and amount(distance)
-- Fades combine as their max, so one never lowers another (the end fade and the splat fade only ever grow).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Constants

local NEAR = Config.FirstPerson.nearFade
local RUSH_IN = Config.FirstPerson.rushFadeIn

-- Module table

local NearFade = {}

-- Spec §3.10: the own projectile is left alone this long after its release (it starts at the hand, inside the band).
NearFade.OWN_GRACE_SECONDS = 0.2

-- Public

function NearFade.amount(distance: number): number
	if not (distance < NEAR.to) then
		return 0 -- beyond the band, or NaN
	end
	return 1 - math.clamp((distance - NEAR.from) / (NEAR.to - NEAR.from), 0, 1)
end

function NearFade.rushFadeIn(travelled: number): number
	return 1 - math.clamp((travelled - RUSH_IN.from) / (RUSH_IN.to - RUSH_IN.from), 0, 1)
end

function NearFade.toward(value: number, near: number): number
	return value + (1 - value) * near
end

function NearFade.projectile(distance: number, own: boolean, sinceRelease: number): number
	if own and sinceRelease < NearFade.OWN_GRACE_SECONDS then
		return 0
	end
	return NearFade.amount(distance)
end

function NearFade.rushHead(
	endFade: number,
	travelled: number,
	distance: number,
	isCaster: boolean,
	firstPerson: boolean
): number
	if not firstPerson then
		return endFade
	end
	local fade = math.max(endFade, NearFade.amount(distance))
	if isCaster then
		fade = math.max(fade, NearFade.rushFadeIn(travelled))
	end
	return fade
end

return NearFade
