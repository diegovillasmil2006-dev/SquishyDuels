--!strict
-- SquishyBlueprints: part lists for the squishies plus `gift_box` and `dragon_head_vfx` (DESIGN §8.1, §8.2). The
-- giant pads' `giant_*` blueprints went with the pads (build plan Phase 6).
-- Shared (client runtime and edit-time generators), data only. Built by Art/SquishyBuilder; all numbers [P].
--
-- The module is a frozen map `{ [blueprintId]: Blueprint }`; the squishy blueprint ids equal the squishy ids. Each
-- blueprint lives in its own child module (one owner per file); Kit (a sibling, not in the map) holds the types, the
-- field reference and the face kit helpers. A new blueprint is added to the map below by name.

local Kit = require(script.Kit)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

-- Types (re-exported: SquishyBuilder and tests read SquishyBlueprints.<Type>)

export type Shape = Kit.Shape
export type Look = Kit.Look
export type FacePlacement = Kit.FacePlacement
export type Attachment = Kit.Attachment
export type PartSpec = Kit.PartSpec
export type Axis = Kit.Axis
export type Section = Kit.Section
export type Feel = Kit.Feel
export type Motion = Kit.Motion
export type Blueprint = Kit.Blueprint

local SquishyBlueprints: { [string]: Blueprint } = {
	kitty_bread = require(script.kitty_bread),
	toast = require(script.toast),
	banana = require(script.banana),
	butter = require(script.butter),
	chocolate = require(script.chocolate),
	bird = require(script.bird),
	donut = require(script.donut),
	dragon = require(script.dragon),
	-- The 6 new squishies (spec 2026-10-09 §3.3 order).
	boba_bear = require(script.boba_bear),
	pancake_pup = require(script.pancake_pup),
	mochi_fox = require(script.mochi_fox),
	strawberry_frog = require(script.strawberry_frog),
	cloud_bunny = require(script.cloud_bunny),
	cupcake_axolotl = require(script.cupcake_axolotl),
	gift_box = require(script.gift_box),
	dragon_head_vfx = require(script.dragon_head_vfx),
}

return TableUtil.deepFreeze(SquishyBlueprints)
