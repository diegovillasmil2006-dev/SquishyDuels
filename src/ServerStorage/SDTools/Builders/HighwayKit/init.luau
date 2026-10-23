--!strict
-- HighwayKit: Claude Design's highway kit v2 (owner 2026-10-23: "Keep this highway as a stand-in; rebuild from Claude
-- Design's sketches when they come"; the delivery "3D highway zones model.zip": kit-core.js, kit-z12/z345/z67.js and
-- "Highway Zones Spec v2"), ported 1:1 as data for SDTools HighwayZones. Edit time only; no Instances.
-- HighwayKit.zones(Palette) -> the 7 zones, in Config.Economy.Highway.starts' order. Each zone (Design's fields):
--   id, name, from, to (studs); floor {n, c, m, w, th, checker?}; lane {c, m} or {stripes, m}; rail {c, m};
--   tiers {n, c, m, y0, y1, inset, thick, over?, slope?, u?} (the walls, right side; mirrored left); strips; outside
--   {ground?, hills?, peaks?, clouds?, spires?}; arch {pillar, pillarM, beam, beamM, strip, stripM}?; props {k, n,
--   parts, pl {x, d, y?, alt?, every?, c?, altC?}, spill?}; once {n, parts, pos {x, d}}; fx {particles, lights, beams}.
-- Materials are Roblox material names. Colours are hex strings: the base ones from Art/Palette (below), the rest
-- Design's tone() of them (HighwayKit.Core).

local Core = require(script.Core)
local Zones12 = require(script.Zones12)
local Zones345 = require(script.Zones345)
local Zones67 = require(script.Zones67)

local HighwayKit = {}
HighwayKit.Core = Core

-- Design's base colours (kit-z12/z345/z67.js constants) -> their Art/Palette tokens.
local TOKENS: { [string]: string } = {
	W = "White",
	K = "HighwayKitInk",
	PK = "HighwayPinkIcing",
	LN = "HighwayCandyLane",
	GR = "HighwayCandyGrass",
	Y = "HighwayLemon",
	AQ = "HighwayWater",
	LV = "HighwayBiome5",
	BR = "HighwayBiome2",
	SB = "HighwayBakeryGround",
	CR = "HighwayCrust",
	IC = "HighwayBiome4",
	TL = "HighwayBiome3",
	MT = "HighwayMilkTea",
	IL = "HighwayFrostLane",
	RK = "HighwayBasalt",
	LI = "HighwayLilac",
	AU = "HighwayBiome7",
	GC = "HighwayGoldCloud",
	SMOKE1 = "HighwaySmokeDark",
	SMOKE2 = "HighwaySmokeLight",
	CLOUD6 = "HighwayCloudLilac",
}

-- The colour table: each base colour's hex from Palette (errors on a missing token).
function HighwayKit.colors(palette: any): { [string]: string }
	local out = {}
	for key, token in TOKENS do
		local value = palette[token]
		if typeof(value) ~= "Color3" then
			error(string.format("[SD][HighwayKit] Art/Palette has no colour token %s", token), 0)
		end
		out[key] = "#" .. string.upper((value :: Color3):ToHex())
	end
	return out
end

-- The 7 zones (a fresh copy each call; every seeded layout the same each time).
function HighwayKit.zones(palette: any): { any }
	local C = HighwayKit.colors(palette)
	local zones = {}
	for _, part in { Zones12, Zones345, Zones67 } do
		for _, z in (part :: any)(Core, C) do
			table.insert(zones, z)
		end
	end
	return zones
end

return HighwayKit
