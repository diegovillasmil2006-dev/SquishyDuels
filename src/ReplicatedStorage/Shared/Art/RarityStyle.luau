--!strict
-- RarityStyle: how each rarity looks, in the world and in the UI (DESIGN §4.3). Shared (client UI, client VFX,
-- edit-time generators). Constants plus two pure helpers; no instances are created here.
-- Rarity is never shown by colour alone: label text (Strings key in Rarity) + pips + colour, always together.
-- Trails are client-only and use solid gradient colours (no textures). Trail emitters name a texture by its key in
-- Config.Vfx.Textures (built-in rbxasset paths), never by path or asset id.
--
-- API:
--   RarityStyle.get(r)                         -> Style? (nil for anything that is not a rarity)
--   RarityStyle.trail(kind)                    -> TrailStyle? (kind = SquishyDef.visuals.trail)
--   RarityStyle.trailColorSequence(kind, accent) -> ColorSequence? (accent = the squishy's accent colour)

local Palette = require(script.Parent.Palette)
local Rarity = require(script.Parent.Parent.Rarity)
local Types = require(script.Parent.Parent.Types)

-- Types

type Rarity = Types.Rarity
type TrailKind = Types.TrailKind

export type PipShape = "dot" | "diamond"

export type CardGradient = {
	colors: { Color3 }, -- UIGradient colour stops, evenly spaced
	rotationDeg: number,
	shimmerDegPerSecond: number?, -- UIGradient.Rotation speed; static under ReducedMotion; nil = static
}

export type CardStyle = {
	strokePx: number, -- UIStroke thickness around the card, in the rarity colour
	gradient: CardGradient?, -- UIGradient on the UIStroke
	badgeKey: string?, -- Strings key of an extra badge
}

-- UI overhaul (2026-10-11): a collectible card's face in the rarity's colours (a vertical gradient, light top to deep
-- bottom, white outlined names on it) and the glow of a selection or a reveal.
export type UiStyle = {
	faceTop: Color3,
	faceBottom: Color3,
	glow: Color3,
}

export type Style = {
	rarity: Rarity,
	color: Color3, -- the rarity colour (label chip, card stroke, reveal glow, Inspect frame)
	ui: UiStyle, -- the UI card face and glow (UI overhaul)
	trailTint: Color3?, -- Epic only: trail end colour, lighter than the rarity colour
	labelTextColor: Color3, -- text on the rarity colour; contrast >= 4.5:1 (§4.3)
	pipShape: PipShape,
	pips: number, -- the same count as Rarity.get(r).pips (one source: Rarity)
	card: CardStyle,
	trail: TrailKind?, -- default world trail for the rarity; nil = no trail
}

export type TrailEmitter = {
	texture: string, -- key in Config.Vfx.Textures
	rate: number, -- particles per second
	lifetimeMin: number, -- s
	lifetimeMax: number, -- s
	maxLive: number, -- live particle cap for this emitter
}

export type TrailStyle = {
	kind: TrailKind,
	nameKey: string, -- Strings key ("Ribbon", ...), shown as "Trail: {name}" where trails can't render (§4.3)
	offsets: { number }, -- one Trail per entry: sideways offset of its centre from the model centre, studs
	width: number, -- distance between a Trail's two attachments, studs (the "Width" of §4.3) ...
	widthScaleTo: number, -- ... shrinking to this fraction at the tail (WidthScale 1 -> widthScaleTo)
	lifetime: number, -- s
	transparencyFrom: number,
	transparencyTo: number,
	startsWithAccent: boolean, -- true: the first colour stop is the squishy's accent, then `colors`
	colors: { Color3 }, -- remaining colour stops, evenly spaced along the trail
	faceCamera: boolean,
	maxLength: number, -- studs
	lightEmission: number,
	emitter: TrailEmitter?, -- particles travelling with the trail
}

-- Constants

local EPIC_TRAIL_TINT = Color3.fromHex("#B58CFF")

-- One source for the pip count: Rarity.
local function pipsOf(r: string): number
	local info = Rarity.get(r)
	return if info then info.pips else 0
end

local STYLES: { [string]: Style } = {
	Common = {
		rarity = "Common",
		color = Color3.fromHex("#A9B4C2"),
		ui = {
			faceTop = Color3.fromHex("#8493A8"),
			faceBottom = Color3.fromHex("#4B576D"),
			glow = Color3.fromHex("#DCE4EE"),
		},
		labelTextColor = Palette.Ink, -- 6.4:1
		pipShape = "dot",
		pips = pipsOf("Common"),
		card = { strokePx = 2 },
		trail = nil, -- shadow disc and size give readability
	},
	Uncommon = {
		rarity = "Uncommon",
		color = Color3.fromHex("#4CC38A"),
		ui = {
			faceTop = Color3.fromHex("#45C987"),
			faceBottom = Color3.fromHex("#1C7A55"),
			glow = Color3.fromHex("#8CFFC4"),
		},
		labelTextColor = Palette.Ink, -- 6.0:1
		pipShape = "dot",
		pips = pipsOf("Uncommon"),
		card = { strokePx = 3 },
		trail = "ribbon",
	},
	Epic = {
		rarity = "Epic",
		color = Color3.fromHex("#7C3AED"),
		ui = {
			faceTop = Color3.fromHex("#B067FF"),
			faceBottom = Color3.fromHex("#5B25C2"),
			glow = Color3.fromHex("#E2B8FF"),
		},
		trailTint = EPIC_TRAIL_TINT,
		labelTextColor = Palette.White, -- 5.7:1
		pipShape = "dot",
		pips = pipsOf("Epic"),
		-- reading: "static purple → pink UIGradient": the Epic purple to Palette Strawberry, left to right.
		card = {
			strokePx = 3,
			gradient = { colors = { Color3.fromHex("#7C3AED"), Palette.Strawberry }, rotationDeg = 0 },
		},
		trail = "twinRibbon",
	},
	Exclusive = {
		rarity = "Exclusive",
		color = Color3.fromHex("#FF9F1C"),
		ui = {
			faceTop = Color3.fromHex("#FFC94D"),
			faceBottom = Color3.fromHex("#E2700F"),
			glow = Color3.fromHex("#FFE7A0"),
		},
		labelTextColor = Palette.Ink, -- 6.5:1
		pipShape = "diamond",
		pips = pipsOf("Exclusive"),
		-- reading: §4.3 gives no shimmer colours; a Lemon highlight band between two rarity-orange stops.
		card = {
			strokePx = 4,
			gradient = {
				colors = { Color3.fromHex("#FF9F1C"), Palette.Lemon, Color3.fromHex("#FF9F1C") },
				rotationDeg = 0,
				shimmerDegPerSecond = 45,
			},
			badgeKey = "rarity.ultimateBadge",
		},
		trail = "comet",
	},
}

-- §4.3 gives the full Ribbon numbers; the twin ribbon and the comet list only what differs. Values they don't list
-- (marked "reading") are the Ribbon's.
local COMET_COLORS = { Color3.fromHex("#FF4F8B"), Color3.fromHex("#FF9F1C"), Color3.fromHex("#FFD86B") }

local TRAILS: { [string]: TrailStyle } = {
	ribbon = { -- Uncommon
		kind = "ribbon",
		nameKey = "trail.ribbon",
		offsets = { 0 },
		width = 0.6,
		widthScaleTo = 0,
		lifetime = 0.25,
		transparencyFrom = 0.25,
		transparencyTo = 1,
		startsWithAccent = true,
		colors = { Palette.White }, -- accent -> white
		faceCamera = true,
		maxLength = 10,
		lightEmission = 0.2,
	},
	twinRibbon = { -- Epic: 2 trails at ±0.3 + sparkles
		kind = "twinRibbon",
		nameKey = "trail.twinRibbon",
		offsets = { -0.3, 0.3 },
		width = 0.6, -- reading
		widthScaleTo = 0, -- reading
		lifetime = 0.32,
		transparencyFrom = 0.25, -- reading
		transparencyTo = 1, -- reading
		startsWithAccent = true,
		colors = { EPIC_TRAIL_TINT }, -- accent -> #B58CFF
		faceCamera = true, -- reading
		maxLength = 12,
		lightEmission = 0.2, -- reading
		emitter = { texture = "sparkles", rate = 20, lifetimeMin = 0.25, lifetimeMax = 0.35, maxLive = 8 },
	},
	comet = { -- Exclusive
		kind = "comet",
		nameKey = "trail.comet",
		offsets = { 0 },
		width = 0.6, -- reading
		widthScaleTo = 0, -- reading
		lifetime = 0.4,
		transparencyFrom = 0.25, -- reading
		transparencyTo = 1, -- reading
		startsWithAccent = false,
		colors = COMET_COLORS, -- #FF4F8B -> #FF9F1C -> #FFD86B
		faceCamera = true, -- reading
		maxLength = 14,
		lightEmission = 0.5,
		-- reading: §4.3 gives no particle lifetime for the comet; the twin ribbon's 0.25-0.35 s.
		emitter = { texture = "sparkles", rate = 30, lifetimeMin = 0.25, lifetimeMax = 0.35, maxLive = 12 },
	},
	ember = { -- Dragon: the comet trail with embers (fire texture) instead of sparkles
		kind = "ember",
		nameKey = "trail.ember",
		offsets = { 0 },
		width = 0.6, -- reading
		widthScaleTo = 0, -- reading
		lifetime = 0.4,
		transparencyFrom = 0.25, -- reading
		transparencyTo = 1, -- reading
		startsWithAccent = false,
		colors = COMET_COLORS,
		faceCamera = true, -- reading
		maxLength = 14,
		lightEmission = 0.5,
		emitter = { texture = "fire", rate = 30, lifetimeMin = 0.25, lifetimeMax = 0.35, maxLive = 12 }, -- reading
	},
}

local function freezeDeep(value: any)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end
	table.freeze(value)
	for _, child in value do
		freezeDeep(child)
	end
end
freezeDeep(STYLES)
freezeDeep(TRAILS)

-- Module table

local RarityStyle = {}

-- Public

function RarityStyle.get(r: unknown): Style?
	if type(r) ~= "string" then
		return nil
	end
	return STYLES[r]
end

function RarityStyle.trail(kind: unknown): TrailStyle?
	if type(kind) ~= "string" then
		return nil
	end
	return TRAILS[kind]
end

-- The colour gradient of a trail kind for one squishy: the accent first when the style starts with it, then the
-- style's stops, evenly spaced from 0 to 1.
function RarityStyle.trailColorSequence(kind: unknown, accent: Color3): ColorSequence?
	local style = RarityStyle.trail(kind)
	if style == nil then
		return nil
	end
	local stops: { Color3 } = {}
	if style.startsWithAccent then
		table.insert(stops, accent)
	end
	for _, color in style.colors do
		table.insert(stops, color)
	end
	if #stops == 1 then
		return ColorSequence.new(stops[1])
	end
	local keypoints: { ColorSequenceKeypoint } = {}
	for position, color in stops do
		table.insert(keypoints, ColorSequenceKeypoint.new((position - 1) / (#stops - 1), color))
	end
	return ColorSequence.new(keypoints)
end

return table.freeze(RarityStyle)
