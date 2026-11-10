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
	-- Series 01 (2026-11-10).
	berry_jelly = require(script.berry_jelly),
	peachy = require(script.peachy),
	grapey = require(script.grapey),
	bao_buddy = require(script.bao_buddy),
	pando = require(script.pando),
	cosmo = require(script.cosmo),
	-- Frosty Box (2026-11-10)
	cone_cub = require(script.cone_cub),
	slushy_seal = require(script.slushy_seal),
	ice_pop_beaver = require(script.ice_pop_beaver),
	mint_chip_mouse = require(script.mint_chip_mouse),
	sundae_manatee = require(script.sundae_manatee),
	gelato_narwhal = require(script.gelato_narwhal),
	parfait_wyvern = require(script.parfait_wyvern),
	-- Lava Box (2026-11-10)
	cocoa_quokka = require(script.cocoa_quokka),
	cinder_bun = require(script.cinder_bun),
	smore_skunk = require(script.smore_skunk),
	cayenne_kiwi = require(script.cayenne_kiwi),
	pizza_pangolin = require(script.pizza_pangolin),
	lava_cake_hippo = require(script.lava_cake_hippo),
	mallow_behemoth = require(script.mallow_behemoth),
	gift_box = require(script.gift_box),
	dragon_head_vfx = require(script.dragon_head_vfx),
}

return TableUtil.deepFreeze(SquishyBlueprints)
