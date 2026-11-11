--!strict
-- Config/GearLooks (big job item 9, 2026-11-10; the owner's "Launcher and gear models: each tier its own look").
-- Required directly (Config/init is near Roblox's 200,000-character limit). The numbers of Shared/GearLooks (pure) and
-- Client/Controllers/GearLooksController: where the 28 models of ReplicatedStorage.SD_Gear (tools/meshes/
-- gear_models.py) sit on a player, for everyone to see.
-- The owner's "Launchers & Biomes" sheet puts the held launcher in the right hand and the platform launcher on the
-- front half of a launch spot. Claude's calls where the game differs from the sheet: the right hand holds the squishy
-- and throws it, so the held launcher is in the LEFT hand; the deck has no launch spots any more (owner 2026-10-18),
-- and the throw's camera looks at the thrower from the front, so the platform launcher stands BESIDE its player.
-- LihFolk vault: "Accessories and Armor That Follow Animation" (weld gear, never touch joints; massless, no collide,
-- query or touch; refit to the body part's size; copy the first-person fade), "Pet Hatching and Following End to End"
-- (a follower is a client-side model, never a server one).

local GearLooks = {
	enabled = true, -- false: nobody wears gear and no launcher stands on the deck (the game as before)
	refreshSeconds = 0.25, -- how often every player's gear, character and place are looked at again
	-- A character wears its gear on this client within wearStuds of the camera and takes it off beyond dropStuds
	-- (the held squishy's own numbers, Config.Anim.held).
	wearStuds = 150,
	dropStuds = 180,
	-- Big job item 10: a Golden piece (3 gear cards, Config/Gear) is its own model with every colour blended this far
	-- toward gold (a Palette token) and a little shine, as a Golden squishy in the pen (Config.UI.Pen.forms.golden);
	-- the ink hull stays dark.
	gold = { color = "CandyGold", blend = 0.8, reflectance = 0.25 }, -- 0.7 read as beige on a pink and white piece
	-- A worn piece is fitted to its body part axis by axis: the part's size over the size the piece was modelled for
	-- (`fitStuds`: the blocky R15 body), each axis within min..max and none more than `stretch` times the thinnest
	-- one, so the piece keeps its shape on a slim Rthro body or a bulky package (seen 2026-11-10: the owner's own
	-- avatar has a 1.15-stud torso and a 0.44-stud arm; one size for all hung off it like a barrel).
	scale = { min = 0.5, max = 1.5, stretch = 1.5 },
	-- The body part a line sits on: the first one the character has (R15, then R6). `y` = how far along the part's
	-- height its origin sits, as a share of that height from the part's centre; `h` = the share of the part's height
	-- the piece is fitted to (an R6 arm is upper and lower arm in one part).
	-- The held launcher: its grip point `gapStuds` in front of the fist, its up along the arm, its front the hand's;
	-- always its own size.
	held = {
		mounts = { { part = "LeftHand", y = 0, h = 1 }, { part = "Left Arm", y = -0.42, h = 1 } },
		gapStuds = 0.15,
	},
	-- Arm gear: a cuff round the throwing arm's lower half.
	arm = {
		mounts = { { part = "RightLowerArm", y = 0, h = 1 }, { part = "Right Arm", y = -0.25, h = 0.5 } },
		fitStuds = Vector3.new(1, 1.05, 1),
	},
	-- Armor: round the chest (its origin the upper torso's centre).
	armor = {
		mounts = { { part = "UpperTorso", y = 0, h = 1 }, { part = "Torso", y = 0.1, h = 0.8 } },
		fitStuds = Vector3.new(2, 1.6, 1),
	},
	-- The platform launcher: only while its player is in the highway's throw area (WorldLayout.Highway.throwArea),
	-- on the deck floor `sideStuds` beside them (on the side of the deck's middle, so it never hangs over an edge;
	-- it changes sides only once the player is `flipStuds` past the middle) and `aheadStuds` toward the lane, facing
	-- down the lane. Its centre keeps `halfWidthStuds` / `frontStuds` / `backStuds` from the deck's edges (the biggest
	-- launcher's footprint). It glides after its player at `followRate` (1 - e^(-dt x rate)); it is taken away once
	-- the player is `leaveStuds` outside the area.
	platform = {
		sideStuds = 4.5,
		aheadStuds = 1.5,
		flipStuds = 1.5,
		halfWidthStuds = 2.9,
		frontStuds = 2.8,
		backStuds = 2.8,
		followRate = 8,
		leaveStuds = 2,
	},
}

return GearLooks
