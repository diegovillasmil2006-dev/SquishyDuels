--!strict
-- Config.Monetization: Robux coin bundles, game passes and PolicyService retry settings (DESIGN §3.10, §6.10,
-- §6.11). Shared, data only.
-- Robux stays OFF until the team creates real products under the group in Creator Hub (M7): every productId is nil
-- and must never be invented. No Robux price is stored here or in Strings; prices come from GetProductInfoAsync.
-- Robux guards (Config.validate, §17.9, Part 7): G7 = a coin bundle has exactly the fields key, nameKey, productId,
-- coins and onSale; every game pass names a `benefit` listed in CosmeticBenefits; no bundle or pass key, pass benefit,
-- nameKey or nameKey text mentions the lobby training (grip, train, rested, afk, idle, squeeze, pad, cushion, level,
-- capsule).
-- G7b = coin bundles stay off (no productId) while Config.Grip.enabled and allowBundlesWithCapsules is false (G-E; lobby
-- spec 2026-10-11 §11, was allowBundlesWithTrainer). The bundle amounts need redoing before Robux is ever turned on
-- (spec 2026-10-12 §12).

export type CoinBundle = {
	key: string, -- bundleKey sent by PromptCoinBundle, ^[a-z_]+$, <= 24 chars
	nameKey: string,
	productId: number?, -- nil = not offered
	coins: number,
	onSale: boolean,
}

export type GamePass = {
	key: string, -- passKey sent by PromptGamePass, ^[a-z_]+$, <= 24 chars
	nameKey: string,
	passId: number?, -- nil = not offered
	benefit: string?, -- one of CosmeticBenefits (G7); a pass without one is never offered
}

local COIN_BUNDLES: { CoinBundle } = {
	{ key = "coins_handful", nameKey = "bundle.handful", productId = nil, coins = 1000, onSale = true },
	{ key = "coins_jar", nameKey = "bundle.jar", productId = nil, coins = 2750, onSale = true },
	{ key = "coins_tin", nameKey = "bundle.tin", productId = nil, coins = 6500, onSale = true },
	{ key = "coins_barrel", nameKey = "bundle.barrel", productId = nil, coins = 18000, onSale = true },
}

-- ProcessReceipt looks bundles up by product id (§3.10): any configured id, even one that failed boot validation.
local byProductId: { [number]: CoinBundle } = {}
for _, bundle in COIN_BUNDLES do
	local productId = bundle.productId
	if productId ~= nil and byProductId[productId] == nil then
		byProductId[productId] = bundle
	end
end

local Monetization = {
	CoinBundles = COIN_BUNDLES,
	byProductId = byProductId,

	-- No pass benefits exist in v1. A pass is shown only with a validated id AND a team-defined benefit.
	GamePasses = {} :: { GamePass },
	ShowPassesComingSoon = false,
	-- The only benefits a game pass may grant (G7): cosmetic ones, named by the team. Empty in v1. Never Grip, trainer
	-- levels, Double Grip, slow training, pad access, box odds, limit refills, quest skips or combat power (§6.11).
	CosmeticBenefits = {} :: { string },

	-- Boot validation of every configured product id (§3.10): exists, Creator.CreatorTargetId == creatorGroupId,
	-- IsForSale. GetProductInfoAsync runs in pcall with productInfoRetries retries.
	creatorGroupId = 706867720, -- DIJAY Studios
	productInfoRetries = 2,
	-- Game pass ownership checks on join use "bounded retries" (§3.10); DESIGN gives no count, so this mirrors
	-- productInfoRetries [P].
	passCheckRetries = 2,

	-- PolicyGateService (§6.10): `attempts` checks of GetPolicyInfoForPlayerAsync waiting `waitSeconds[n]` after
	-- failed attempt n. PolicyRetry (state `unknown` only) is allowed once per manualRetryMinSeconds, at most
	-- manualRetryMaxPerSession times.
	Policy = {
		attempts = 3,
		waitSeconds = { 2, 4, 8 },
		manualRetryMinSeconds = 30,
		manualRetryMaxPerSession = 5,
	},
}

return Monetization
