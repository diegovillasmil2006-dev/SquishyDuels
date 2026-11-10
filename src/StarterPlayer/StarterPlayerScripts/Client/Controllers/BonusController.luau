--!strict
-- BonusController (client only). Big job item 4 (2026-11-10; the owner: "A bonus for joining my Roblox group (DIJAY
-- Studios), and redeem codes"): what the two rows on top of the Settings window do (SettingsController builds them).
-- LihFolk vault "Roblox Communities as Your On-Platform Hub" (the join prompt only when the player asks for it; the
-- server decides who is a member; a hint at most once a visit, after a good moment, never in the tutorial) and "Codes
-- Redemption System End to End" (the typed text goes to the server as it is; the server's answer is shown).
--   BonusController.isMember()          the server's word (the Player attribute SD_GroupBoost above 0, PerkService)
--   BonusController.groupPercent()      the group bonus in whole percent (the row's text)
--   BonusController.join()              yields: Roblox's join prompt (skipped for a member), then GroupCheck; toasts
--                                       the result (the gift's own toast comes from the server)
--   BonusController.redeem(text, at?)   yields: CodeRedeem with the typed text; on a yes the claim sound, the candy
--                                       burst at `at`, the coin flight and "+N Coins"; else the reason. True on a yes
-- The hint (bonus.groupTip): once a visit, a moment after a daily reward claim, to a player who is not a member and is
-- done with the tutorial.

-- Services

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Bonus = require(Shared.Config.Bonus)
local Cleanup = require(Shared.Util.Cleanup)
local Format = require(Shared.Util.Format)
local JoyFx = require(Shared.Config.JoyFx)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local OnboardingFormat = require(Client.UI.OnboardingFormat)
local UiFx = require(Client.UI.UiFx)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Constants

local GROUP = Bonus.Group
local CODES = Bonus.Codes
local ATTR_BOOST = "SD_GroupBoost"
local PERCENT = math.floor(GROUP.penBoost * 100 + 0.5)
local REMOTE_CHECK = "GroupCheck"
local REMOTE_REDEEM = "CodeRedeem"
local SOUND_REDEEM = "ui.purchase" -- the daily claim's sound: a reward landed
local TIP_DELAY_SECONDS = 4 -- after the claim's own toast and coin flight
local JOINED: { [string]: boolean } = { Joined = true, AlreadyMember = true }
local PENDING = "JoinRequestPending"

-- Module table

local BonusController = {}

-- Private

local cleanup: Cleanup.Cleanup? = nil
local joining = false
local redeeming = false
local tipDone = false

local function percentArgs(): { [string]: any }
	return { percent = PERCENT }
end

local function tutorialOver(): boolean
	local onboarding = StateController.get("onboarding")
	if type(onboarding) ~= "table" then
		return false
	end
	return onboarding.skipped == true or OnboardingFormat.isComplete(OnboardingFormat.done(onboarding))
end

-- Roblox's join prompt. Returns the status name ("Joined", "AlreadyMember", "JoinRequestPending", "None"), "" when the
-- prompt could not open.
local function promptJoin(): string
	local ok, status = pcall(function(): any
		return GroupService:PromptJoinAsync(GROUP.id)
	end)
	return if ok and typeof(status) == "EnumItem" then status.Name else ""
end

-- Public

function BonusController.isMember(): boolean
	local value = Players.LocalPlayer:GetAttribute(ATTR_BOOST)
	return type(value) == "number" and value > 0
end

function BonusController.groupPercent(): number
	return PERCENT
end

function BonusController.join()
	if joining then
		return
	end
	joining = true
	if not BonusController.isMember() then
		local status = promptJoin()
		if not JOINED[status] then
			if status == PENDING then
				UIController.toast(Strings.bonus.groupPending, "info")
			end
			joining = false
			return
		end
	end
	local result = NetController.invokeAsync(REMOTE_CHECK)
	joining = false
	if not result.ok then
		NotifyController.showResult(result :: any)
		return
	end
	local data: any = if type(result.data) == "table" then result.data else {}
	if data.member ~= true then
		UIController.toast(Strings.bonus.groupNotYet, "info")
	elseif data.coins == 0 then
		UIController.toast(Strings.format(Strings.bonus.groupOn, percentArgs()), "success")
	end
end

function BonusController.redeem(text: string, at: GuiObject?): boolean
	local typed = string.sub(text, 1, CODES.maxTyped)
	if redeeming or string.match(typed, "%S") == nil then
		return false
	end
	redeeming = true
	local from: Vector2? = if at then at.AbsolutePosition + at.AbsoluteSize / 2 else nil
	local result = NetController.invokeAsync(REMOTE_REDEEM, typed)
	redeeming = false
	if not result.ok then
		NotifyController.showResult(result :: any)
		return false
	end
	local data: any = if type(result.data) == "table" then result.data else {}
	local coins = if type(data.coins) == "number" then math.floor(data.coins) else 0
	SoundController.play(SOUND_REDEEM)
	if at and JoyFx.enabled then
		UiFx.burst(at, "medium", nil, { glow = false })
	end
	if coins > 0 then
		if from then
			HudController.flyCoins(from, coins)
		end
		UIController.toast(
			Strings.format(Strings.common.coinsGain, { coins = Format.coins(coins) }),
			"success",
			{ sound = false } -- one sound per action: the redeem's
		)
	end
	return true
end

-- Lifecycle

function BonusController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(StateController.changed("daily"):connect(function(value: any, old: any)
		if tipDone or StateController.isApplyingFull() or type(value) ~= "table" or type(old) ~= "table" then
			return
		end
		if value.lastClaimDay == old.lastClaimDay then
			return
		end
		tipDone = true -- one claim a visit is the one good moment
		if BonusController.isMember() or not tutorialOver() then
			return
		end
		task.delay(TIP_DELAY_SECONDS, function()
			if cleanup == c and not BonusController.isMember() then
				UIController.toast(Strings.format(Strings.bonus.groupTip, percentArgs()), "info")
			end
		end)
	end))
	c:add(function()
		joining, redeeming, tipDone = false, false, false
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function BonusController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return BonusController
