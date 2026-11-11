--!strict
-- Config/Coats (big job item 10, 2026-11-10; the owner 2026-10-15: "waxing the squishies so they give a coin boost",
-- "there should be more than wax", the category approved with "YESSS THATS THE WAY"). Required directly (Config/init is
-- near Roblox's 200,000-character limit). The 7 coatings a squishy can wear: index = PenItem.coat (1..7); the boost is
-- Config.Economy.Pen.coatMult[coat + 1] (x1.5, 2, 3, 4, 6, 8, 12 on that squishy's coins). Math: Shared/CoatMath.
-- The looks and where each one comes from are the lobby design's kit.json > looks.coatings ("A squishy has at most one
-- fusion form AND one coating. The fusion form sets the colour, the coating sets the finish. Only colour + material +
-- Reflectance/Transparency"): Wax and Glitter are "Shop" items; Jelly, Frost, Chrome, Neon and Galaxy belong to the
-- zones Boba Lagoon .. Divine Heaven ("<zone> reward"). Claude's calls (the old money paper is lost; vault page "Big
-- job 2026-11" > My calls): `zone` = the highway zone that must be reached before the coating can be bought (the
-- first time a player reaches zone 3..7 they also get one of its coating for free: HighwayService), and `price`, the
-- Coins of one bought in the pen's picker, on the scale of that zone's gear and box prices. A coating from the bag is
-- free to put on; a squishy's old coating goes back to the bag (as when it is fused or sold).
-- `look`: the design's finish (a Material's name, Reflectance, Transparency; `tint` + `blend` = the share of the
-- squishy's own colour that turns to the tint). A colour here is the design file's own value.

local Coats = {
	list = {
		{
			id = "wax",
			zone = 1,
			price = 1_000_000,
			look = { material = "SmoothPlastic", reflectance = 0.15, transparency = 0 },
		},
		{
			id = "glitter",
			zone = 1,
			price = 50_000_000,
			look = { material = "Foil", reflectance = 0.1, transparency = 0, tint = Color3.fromHex("#FFD6F2"), blend = 0.2 },
		},
		{
			id = "jelly",
			zone = 3,
			price = 1_000_000_000,
			look = { material = "Glass", reflectance = 0.05, transparency = 0.35 },
		},
		{
			id = "frost",
			zone = 4,
			price = 50_000_000_000,
			look = { material = "Ice", reflectance = 0.1, transparency = 0, tint = Color3.fromHex("#CFEFFF"), blend = 0.4 },
		},
		{
			id = "chrome",
			zone = 5,
			price = 1_500_000_000_000,
			look = {
				material = "SmoothPlastic",
				reflectance = 0.5,
				transparency = 0,
				tint = Color3.fromHex("#E6EAF2"),
				blend = 0.5,
			},
		},
		{
			id = "neon",
			zone = 6,
			price = 20_000_000_000_000,
			look = { material = "Neon", reflectance = 0, transparency = 0 },
		},
		{
			id = "galaxy",
			zone = 7,
			price = 200_000_000_000_000,
			look = { material = "Glass", reflectance = 0.2, transparency = 0.1, tint = Color3.fromHex("#2B1E5C"), blend = 0.65 },
		},
	},
}

return Coats
