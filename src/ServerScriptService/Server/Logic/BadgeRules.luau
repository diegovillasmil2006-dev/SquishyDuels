--!strict
-- BadgeRules: which badges a player has earned (Batch 3, review #10; the user's badges in Config.Social.Badges).
-- Server only, pure: no instances, no yields. Services/ShowOffService awards what it returns through BadgeService.
--   earned(profile, gripLevel, flags, list) -> { [badge key] = true }
-- Rule kinds (Config.Social header): joined (always); stat {stat, atLeast} (profile.stats); gripLevel {atLeast};
-- ownRarityAll {rarity} (every Catalog squishy of that rarity owned); own {squishyId}; flag {flag} (a session flag,
-- e.g. duelBuddies). An unknown kind or a missing profile part earns nothing and never errors. Nothing here reads box
-- luck, Robux or invites. Pens3 phase 2: capsuleSlots and capsuleLevel went with the capsules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

-- Module table

local BadgeRules = {}

-- Private

local function number(value: any): number
	return if type(value) == "number" then value else 0
end

local function ownsAll(owned: { [string]: any }, rarity: any): boolean
	local list = Catalog.byRarity(rarity)
	if #list == 0 then
		return false
	end
	for _, def in list do
		if owned[def.id] == nil then
			return false
		end
	end
	return true
end

local function meets(rule: any, profile: any, gripLevel: number, flags: { [string]: boolean }): boolean
	local kind = rule.kind
	local owned = if type(profile.owned) == "table" then profile.owned else {}
	if kind == "joined" then
		return true
	elseif kind == "stat" then
		local stats = if type(profile.stats) == "table" then profile.stats else {}
		return number(stats[rule.stat]) >= number(rule.atLeast)
	elseif kind == "gripLevel" then
		return gripLevel >= number(rule.atLeast)
	elseif kind == "ownRarityAll" then
		return ownsAll(owned, rule.rarity)
	elseif kind == "own" then
		return type(rule.squishyId) == "string" and owned[rule.squishyId] ~= nil
	elseif kind == "flag" then
		return type(rule.flag) == "string" and flags[rule.flag] == true
	end
	return false
end

-- Public

function BadgeRules.earned(
	profile: any,
	gripLevel: number,
	flags: { [string]: boolean },
	list: { any }
): { [string]: boolean }
	local earned: { [string]: boolean } = {}
	if type(profile) ~= "table" then
		return earned
	end
	for _, badge in list do
		if type(badge.rule) == "table" and meets(badge.rule, profile, gripLevel, flags) then
			earned[badge.key] = true
		end
	end
	return earned
end

return table.freeze(BadgeRules)
