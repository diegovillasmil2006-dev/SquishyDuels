--!strict
-- KneadFormat (client only, pure). Spec phase2-squeeze §1.18-§1.20, §3.7: what the knead screen in Inspect shows, as
-- plain data (design: the FP page fp.js:569-577, 700-701, html:59-77). Read by UI/Components/WaxMeter, UI/KneadOverlay
-- and Controllers/KneadController; every text from Strings.knead, every number from Config.
--   stateKey(crunchiness)            "crunchy" above Config.Wax.hud.crunchy, "crackled" above crackled, else "soft"
--                                    (the design's `local`, fp.js:701; strictly above)
--   hud(waxLeft, crunchiness, cracks) -> Hud   the coat bar's share (round(waxLeft·100) %, fp.js:700), the state word
--                                    and "{n} cracks" (digit grouping, Util/Format; "1 crack" by the Strings rule)
--   rows(feel) -> Rows               the panel's Squeeze and Coat rows (fp.js:569-570), rich text with the label in bold
--                                    (an unknown feel is foam)
--   help(input) -> string            the caption while kneading for "Touch", "Gamepad" or any other input (the keyboard)
--   vignette(u, v) -> (Color3, alpha)   the design's radial-gradient(125% 95% at 50% 45%, ...) at the stage point (u, v)
--                                    (0..1, v down), with CSS's premultiplied interpolation between the stops (Config.UI
--                                    .Knead.vignette, colours Art/Palette VignetteGlow, VignetteWarm, KneadInk); before the
--                                    first stop it is clear, past the last stop the last
--   vignettePixels(n) -> buffer      that gradient on n × n texels (texel centres), RGBA8, row 0 at the top (an
--                                    EditableImage's WritePixelsBuffer layout)
--   ring(state) -> Ring              the fingertip ring for a KneadMath.ringState (html:59-62)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

export type StateKey = "crunchy" | "crackled" | "soft"

export type Hud = {
	fill: number, -- 0..1, whole percents
	state: string,
	count: string,
}

export type Rows = { squeeze: string, coat: string }

export type Ring = { visible: boolean, px: number, transparency: number }

local HUD = Config.Wax.hud
local UI = Config.UI.Knead
local VIGNETTE = UI.vignette
local KNEAD = Strings.knead
local DEFAULT_FEEL = Config.Knead.defaultFeel
local STOP_COLORS: { Color3 } = { Palette.VignetteGlow, Palette.VignetteWarm, Palette.KneadInk }
local PERCENT = 100
local BYTE = 255

local KneadFormat = {}

function KneadFormat.stateKey(crunchiness: number): StateKey
	if crunchiness > HUD.crunchy then
		return "crunchy"
	elseif crunchiness > HUD.crackled then
		return "crackled"
	end
	return "soft"
end

function KneadFormat.hud(waxLeft: number, crunchiness: number, cracks: number): Hud
	local share = if waxLeft == waxLeft then math.clamp(waxLeft, 0, 1) else 0
	local count = math.max(0, math.floor(cracks))
	local template = Strings.plural(count, KNEAD.cracks.one, KNEAD.cracks.many)
	return {
		fill = math.floor(share * PERCENT + 0.5) / PERCENT,
		state = KNEAD.state[KneadFormat.stateKey(crunchiness)],
		count = Strings.format(template, { n = Format.coins(count) }),
	}
end

function KneadFormat.rows(feel: string): Rows
	local key = if KNEAD.feel[feel] ~= nil then feel else DEFAULT_FEEL
	local feelText, coatText = KNEAD.feel[key], KNEAD.coat[key]
	return {
		squeeze = Strings.format(
			KNEAD.panelRow,
			{ row = KNEAD.squeezeRow, label = feelText.label, note = feelText.note }
		),
		coat = Strings.format(KNEAD.panelRow, { row = KNEAD.coatRow, label = coatText.label, note = coatText.note }),
	}
end

function KneadFormat.help(input: string?): string
	if input == "Touch" then
		return KNEAD.help.touch
	elseif input == "Gamepad" then
		return KNEAD.help.gamepad
	end
	return KNEAD.help.keyboard
end

function KneadFormat.vignette(u: number, v: number): (Color3, number)
	local dx = (u - VIGNETTE.cx) / VIGNETTE.rx
	local dy = (v - VIGNETTE.cy) / VIGNETTE.ry
	local r = math.sqrt(dx * dx + dy * dy)
	local stops, alphas = VIGNETTE.stops, VIGNETTE.alphas
	if r <= stops[1] then
		return STOP_COLORS[1], alphas[1]
	end
	for i = 1, #stops - 1 do
		local from, to = stops[i], stops[i + 1]
		if r <= to then
			local t = (r - from) / (to - from)
			local a0, a1 = alphas[i], alphas[i + 1]
			local alpha = a0 + (a1 - a0) * t
			if alpha <= 0 then
				return STOP_COLORS[i + 1], 0
			end
			local c0, c1 = STOP_COLORS[i], STOP_COLORS[i + 1]
			local function channel(x0: number, x1: number): number
				return (x0 * a0 * (1 - t) + x1 * a1 * t) / alpha
			end
			return Color3.new(channel(c0.R, c1.R), channel(c0.G, c1.G), channel(c0.B, c1.B)), alpha
		end
	end
	return STOP_COLORS[#stops], alphas[#stops]
end

function KneadFormat.vignettePixels(n: number): buffer
	local pixels = buffer.create(n * n * 4)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local color, alpha = KneadFormat.vignette((x + 0.5) / n, (y + 0.5) / n)
			local offset = (y * n + x) * 4
			buffer.writeu8(pixels, offset, math.floor(color.R * BYTE + 0.5))
			buffer.writeu8(pixels, offset + 1, math.floor(color.G * BYTE + 0.5))
			buffer.writeu8(pixels, offset + 2, math.floor(color.B * BYTE + 0.5))
			buffer.writeu8(pixels, offset + 3, math.floor(alpha * BYTE + 0.5))
		end
	end
	return pixels
end

function KneadFormat.ring(state: string): Ring
	if state == "press" then
		return { visible = true, px = UI.ringPressPx, transparency = UI.ringPressTransparency }
	elseif state == "pull" then
		return { visible = true, px = UI.ringPullPx, transparency = 0 }
	end
	return { visible = state == "over", px = UI.ringPx, transparency = 1 }
end

return KneadFormat
