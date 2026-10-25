--!strict
-- AbilityBarFormat (client only, pure). Duel HUD part 2 (owner 2026-10-24; `D:n` = "Squishy Duels Duel HUD.dc.html"
-- line n, the co-owner's Duel HUD export): the ability bar's numbers, unit-tested in Edit mode. The view and its
-- input are Controllers/AbilityBarController.
--   form(width, touch)            "phone" under Config.UI.AbilityBar.phoneBelowWidth or on touch, else "desk" (§2)
--   canvasScale(form, size)       the design canvas's UIScale: min(width / W, height / H) (§2)
--   cooldownText(remaining)       "" when ready; whole seconds rounded up from 1 s; one decimal under it (D:401)
--   sweepFraction(left, total)    the share of the circle the dark sweep still covers, 0..1 (D:390)
--   sweepRotations(fraction)      the two half-disc masks drawing that sweep (see the function)
--   ultLeft(charge, max, rate, since, live)   seconds until the ultimate's meter is full, the received whole-number
--                                 charge run on at `rate` while the match is live, never past the next whole point
--   phoneRect(id, size)           a phone button's box (px of the canvas-scaled gui), from the bottom-right corner
--   phoneArcLeft(size)            the arc's left edge (the Catch button), so the touch Throw keeps clear of it
--   ultIconKey(ultimateId)        the AssetTable key of an ultimate's icon (D:397)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Form = "desk" | "phone"
export type AbilityId = "catch" | "ult" | "dash"
export type Rect = { x: number, y: number, w: number, h: number }

-- Constants

local BAR = Config.UI.AbilityBar
local FULL_TURN = 360
local HALF_TURN = 180
-- D:397 the icon file of each ultimate (uploads/duel-icons/ult-<Squishy>.svg)
local ULT_ICONS: { [string]: string } = {
	dragon_rush = "img.duel.icon.ult.Dragon",
	flock_volley = "img.duel.icon.ult.Birdie",
	rain_check = "img.duel.icon.ult.CloudBunny",
	bubble_pop = "img.duel.icon.ult.CupcakeAxolotl",
	sprinkle_roller = "img.duel.icon.ult.Donut",
}

-- Module table

local AbilityBarFormat = {}

-- Private

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Public

function AbilityBarFormat.form(width: number, touch: boolean): Form
	return if touch or width < BAR.phoneBelowWidth then "phone" else "desk"
end

function AbilityBarFormat.canvasScale(form: Form, size: Vector2): number
	local canvas = BAR[form].canvas
	local k = math.min(size.X / canvas.X, size.Y / canvas.Y)
	return if finite(k) and k > 0 then k else 1
end

function AbilityBarFormat.cooldownText(remaining: number): string
	if not finite(remaining) or remaining <= 0 then
		return ""
	end
	if remaining >= 1 then
		return tostring(math.ceil(remaining))
	end
	-- one decimal, never "0.0" while something is left
	return string.format("%.1f", math.max(remaining, 0.05))
end

function AbilityBarFormat.sweepFraction(left: number, total: number): number
	if not finite(left) or not finite(total) or total <= 0 or left <= 0 then
		return 0
	end
	return math.clamp(left / total, 0, 1)
end

-- The dark sweep covers the circle from (1 - fraction) x 360° to 360° clockwise from 12 o'clock (D:399 conic-gradient),
-- so it shrinks clockwise toward 12. Drawn with the reticle's two half discs (right 0..180°, left 180..360°) whose
-- UIGradient masks are clear on their first half: rotating a mask by r hides the first r degrees of its half, so the
-- right mask turns min(a, 180) and the left max(a, 180), a = the clear angle. Returns (rightDeg, leftDeg).
function AbilityBarFormat.sweepRotations(fraction: number): (number, number)
	local f = if finite(fraction) then math.clamp(fraction, 0, 1) else 0
	local clear = (1 - f) * FULL_TURN
	return math.min(clear, HALF_TURN), math.max(clear, HALF_TURN)
end

-- The server sends the meter as whole points (AbilityService floors it), only when that whole number changes; the true
-- charge then lies in [charge, charge + 1). While live it grows at `rate` a second, so the client runs it on from the
-- last value but never past the next whole point (the next message corrects it). Seconds left, 0 when full.
-- `cap` (default 1) is how far it may run on: a caller that starts from the middle of [charge, charge + 1) passes 0.5.
function AbilityBarFormat.ultLeft(
	charge: number,
	chargeMax: number,
	rate: number,
	since: number,
	live: boolean,
	cap: number?
): number
	if not finite(charge) or not finite(chargeMax) or chargeMax <= 0 then
		return 0
	end
	if charge >= chargeMax then
		return 0
	end
	if not finite(rate) or rate <= 0 then
		return math.huge
	end
	local grown = if live and finite(since) and since > 0 then math.min(rate * since, cap or 1) else 0
	local estimate = math.min(charge + grown, chargeMax)
	return (chargeMax - estimate) / rate
end

function AbilityBarFormat.phoneRect(id: AbilityId, size: Vector2): Rect
	local place = BAR.phone.places[id]
	local k = AbilityBarFormat.canvasScale("phone", size)
	local px = place.size * k
	return {
		x = size.X - (place.right + place.size) * k,
		y = size.Y - (place.bottom + place.size) * k,
		w = px,
		h = px,
	}
end

function AbilityBarFormat.phoneArcLeft(size: Vector2): number
	local left = math.huge
	for _, id in { "catch", "ult", "dash" } :: { AbilityId } do
		left = math.min(left, AbilityBarFormat.phoneRect(id, size).x)
	end
	return left
end

function AbilityBarFormat.ultIconKey(ultimateId: string?): string?
	return if ultimateId then ULT_ICONS[ultimateId] else nil
end

return AbilityBarFormat
