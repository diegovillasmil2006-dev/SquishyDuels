--!strict
-- CollectionFormat (client only, pure). DESIGN §7.6 (the Collection row: 8 pedestals, each with a client-built squishy
-- at scale 2.5 in catalog order, facing -X), §7.7 (owned = full colour on a Cream nameplate; not owned = Lavender
-- silhouette, plate "Not owned yet"; models built and animated only within 60 studs). What CollectionController places
-- and shows, as plain data; no instances:
--   PLATE_TOKEN / SILHOUETTE_TOKEN       the Art/Palette tokens of the nameplate and of an unowned silhouette
--   squishyForSlot(slot, list?)          the squishy id of pedestal `slot` (1..8): Catalog.list() order; nil outside
--   slotOf(id, list?)                    the reverse; nil for an id without a pedestal
--   shouldBuild(distance, built, ...)    build within buildStuds; a built model stays until buildStuds + hysteresis
--   restCFrame(top, pivotAboveBottom, angle)   the model's pivot: bottom on the pedestal top, face toward -X at 0°
--   phaseOf(slot) / swayAngle(t, phase, amplitudeDeg, periodSeconds, reduced)   the gentle display sway (0 under
--                                        ReducedMotion)
--   plate(id, owned)                     the nameplate texts: { title = squishy name, status, owned }
-- Readings (DESIGN silent; Part 6):
--   * The radius (60) and the scale (2.5) stay in WorldLayout.Collection (buildStuds, squishyScale); the margin, the
--     check period, the sway and the nameplate size are Config.Inspect.Collection.
--   * "Animated" (§7.6) is a slow sway about the pedestal's vertical axis (+Y, counter-clockwise seen from above for a
--     positive angle) of at most swayDeg either side of the -X facing, so every face stays toward the approach aisle
--     (Part 6 review: a full turntable showed half the row's backs). Each slot starts at its own phase ((slot - 1) /
--     pedestal count of a period), so the row does not sway in lockstep. Under ReducedMotion the models stand still,
--     every face toward -X.
--   * A distance that is not a finite number >= 0 (no character, no camera) never builds and drops a built model.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

-- Types

export type Plate = {
	title: string, -- the squishy's name
	status: string, -- collection.owned ("Owned") / collection.notOwned ("Not owned yet")
	owned: boolean,
}

-- Constants

local LAYOUT = WorldLayout.Collection
local DISPLAY = Config.Inspect.Collection
local TAU = 2 * math.pi
-- The face (the pivot's LookVector, -Z) turned toward -X: CFrame.Angles(0, 90°, 0).LookVector = (-1, 0, 0).
local FACE_MINUS_X_DEG = 90

-- Module table

local CollectionFormat = {}

CollectionFormat.PLATE_TOKEN = "Cream"
CollectionFormat.SILHOUETTE_TOKEN = "Lavender"

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function isSlot(slot: unknown, count: number): boolean
	return finite(slot) and math.floor(slot :: number) == slot and (slot :: number) >= 1 and (slot :: number) <= count
end

local function textOf(key: string, fallback: string): string
	return Strings.resolve(key) or fallback
end

-- Public

-- The squishy of pedestal `slot` (1..pedestal count): the slot-th def of `list` (default Catalog.list()). nil for a
-- slot without a pedestal or without a squishy.
function CollectionFormat.squishyForSlot(slot: number, list: { Types.SquishyDef }?): string?
	local defs = list or Catalog.list()
	if not isSlot(slot, #LAYOUT.pedestals) then
		return nil
	end
	local def = defs[slot]
	return if def then def.id else nil
end

-- The pedestal slot of squishy `id` in `list` (default Catalog.list()); nil when it has none.
function CollectionFormat.slotOf(id: string, list: { Types.SquishyDef }?): number?
	local defs = list or Catalog.list()
	for slot, def in defs do
		if def.id == id then
			return if slot <= #LAYOUT.pedestals then slot else nil
		end
	end
	return nil
end

-- Whether a pedestal's model should exist at `distance` studs: an unbuilt model builds within buildStuds (default
-- WorldLayout.Collection.buildStuds); a built one is kept until it is more than hysteresisStuds (default
-- Config.Inspect.Collection.hysteresisStuds) past that radius.
function CollectionFormat.shouldBuild(
	distance: number,
	built: boolean,
	buildStuds: number?,
	hysteresis: number?
): boolean
	if not finite(distance) or distance < 0 then
		return false
	end
	local radius = if finite(buildStuds) then buildStuds :: number else LAYOUT.buildStuds
	local margin = if finite(hysteresis) then math.max(hysteresis :: number, 0) else DISPLAY.hysteresisStuds
	if built then
		return distance <= radius + margin
	end
	return distance <= radius
end

-- The pivot CFrame of a displayed model whose pivot is `pivotAboveBottom` studs above its bottom, standing on the
-- pedestal top point `pedestalTop`: its face (the pivot's LookVector) toward -X at angleDeg 0 (§7.6 facing), turned
-- angleDeg about +Y.
function CollectionFormat.restCFrame(pedestalTop: Vector3, pivotAboveBottom: number, angleDeg: number): CFrame
	local lift = if finite(pivotAboveBottom) then pivotAboveBottom else 0
	local angle = if finite(angleDeg) then angleDeg else 0
	return CFrame.new(pedestalTop + Vector3.new(0, lift, 0)) * CFrame.Angles(0, math.rad(FACE_MINUS_X_DEG + angle), 0)
end

-- The sway phase of a slot, in periods [0, 1): (slot - 1) / pedestal count. 0 for a slot without a pedestal.
function CollectionFormat.phaseOf(slot: number): number
	local count = #LAYOUT.pedestals
	if not isSlot(slot, count) then
		return 0
	end
	return ((slot - 1) / count) % 1
end

-- The display angle at `t` seconds, in degrees: amplitudeDeg × sin(2π (t / periodSeconds + phase01)), always within
-- ±amplitudeDeg of the -X facing. 0 when `reduced` (ReducedMotion: the model stands still, its face toward -X), and for
-- an amplitude or period that is not a finite number > 0.
function CollectionFormat.swayAngle(
	t: number,
	phase01: number,
	amplitudeDeg: number,
	periodSeconds: number,
	reduced: boolean
): number
	if reduced or not finite(amplitudeDeg) or amplitudeDeg <= 0 or not finite(periodSeconds) or periodSeconds <= 0 then
		return 0
	end
	local time = if finite(t) then t else 0
	local phase = if finite(phase01) then phase01 else 0
	return amplitudeDeg * math.sin(TAU * (time / periodSeconds + phase))
end

-- The nameplate of squishy `id`: its name and "Owned" / "Not owned yet" (WorldLayout.Collection.ownedKey /
-- notOwnedKey). An unknown id shows the id as its title.
function CollectionFormat.plate(id: string, owned: boolean): Plate
	local def = Catalog.get(id)
	local key = if owned then LAYOUT.ownedKey else LAYOUT.notOwnedKey
	return {
		title = if def then textOf(def.nameKey, def.id) else id,
		status = textOf(key, key),
		owned = owned == true,
	}
end

return CollectionFormat
