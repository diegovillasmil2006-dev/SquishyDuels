--!strict
-- KillBannerController (client only; kill banners 2026-10-16, VillasmilGaming: Valorant-style kill banners). When the
-- local player K.O.s someone, it shows the kill banner (UI/KillBanner in SD_KillBanner), plays the tier's kill sound
-- (the kill set's AssetTable sheet, one region, Config.Audio.killBanner) and the VFX Studio burst behind the banner
-- (Anim/KillVfx Banner/<set>). Cosmetic only: nothing here changes game state.
-- * The kill set is the set of the squishy that made the K.O. (Art/KillStyle; Catalog eliminationEffectId): Common and
--   Uncommon squishies share "standard"; each squishy above Uncommon has its own banner, sounds and burst.
-- * The tier is the K.O. streak (K.O.s without being knocked out; KillBannerFormat.tierFor): 1k-5k, and the 6k banner
--   with the 6k sound for the 6th K.O. and every one after it, until the player is knocked out.
-- * Free for All / Team Deathmatch: StateController.MatchMoments, the server's own streak (MatchMoment.streak, the
--   attacker's after the K.O.; MatchService resets it when that player is knocked out). A batch with several of the
--   player's K.O.s shows one banner, at the highest streak (matchKill, pure). The squishy is the match view's own
--   (you.squishyId). Storm and fall K.O.s (no attacker) show nothing.
-- * 1v1 duels (and the Studio test dummy): VfxController.KoDealt (the eliminator's K.O. moment, after the hit-stop) with
--   the server's effectId (the attacker's kill set). The streak is counted here (nextDuelStreak, pure): +1 per K.O.
--   dealt outside a match, back to 0 when the player is K.O.'d (VfxController.Eliminated, a match K.O. of the player)
--   or a duel ends in a loss or a draw (DuelResultReceived).
-- * Match banners wait for this client's hit-stop (HitStop.after), like the duel ones.
-- Studio only (Config.Debug.debugHooks): a BindableFunction PlayerScripts.SD_DebugKill:
--   Invoke("show", setId, tier)  one banner, sound and burst, no K.O.
--   Invoke("kill", setId, position?)  one kill effect (default: 8 studs in front of the camera)
--   Invoke("seek", t)  the showing banner drawn at t seconds and held there (screenshots)
--   Invoke("match", streak, squishyId)  a fake match K.O. by the player through the real match path (MatchMoments)
--   Invoke("state")  { duelStreak, showing, vfx counts, last = { setId, tier } of the last banner }

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local KillStyle = require(Shared.Art.KillStyle)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local Controllers = script.Parent
local Client = Controllers.Parent
local SoundController = require(Controllers.SoundController)
local StateController = require(Controllers.StateController)
local UIController = require(Controllers.UIController)
local VfxController = require(Controllers.VfxController)
local HitStop = require(Client.Anim.HitStop)
local KillVfx = require(Client.Anim.KillVfx)
local Tweens = require(Client.Anim.Tweens)
local KillBanner = require(Client.UI.KillBanner)
local KillBannerFormat = require(Client.UI.KillBannerFormat)

-- Types

export type DuelEvent = "dealt" | "knockedOut" | "lost"

-- Constants

local GUI_NAME = "SD_KillBanner"
local AUDIO = Config.Audio.killBanner
local KILL_FX = Config.Vfx.KillFx
local DEBUG_NAME = "SD_DebugKill"

-- Module table

local KillBannerController = {}

-- Fired with (setId, tier) whenever a banner shows (tests, debug).
KillBannerController.Shown = Signal.new() :: Signal.Signal<string, number>

-- Private state

local log = Log.new("KillBanner")
local cleanup: Cleanup.Cleanup? = nil
local banner: KillBanner.KillBanner? = nil
local duelStreak = 0
local lastShown: { setId: string, tier: number }? = nil -- Studio state readout

-- Pure ---------------------------------------------------------------------------------------------------------------

-- The duel streak after an event: +1 for a K.O. dealt, 0 when knocked out or a duel is lost / drawn.
function KillBannerController.nextDuelStreak(streak: number, event: DuelEvent): number
	if event == "dealt" then
		return math.max(math.floor(streak), 0) + 1
	end
	return 0
end

-- The local player's part of one MatchMoments batch: the highest streak of their K.O.s (nil: none) and whether they
-- were knocked out in it.
function KillBannerController.matchKill(moments: { any }, localId: number): (number?, boolean)
	local best: number? = nil
	local knockedOut = false
	for _, moment in moments do
		if type(moment) ~= "table" or moment.kind ~= "ko" then
			continue
		end
		if moment.victim == localId then
			knockedOut = true
		elseif moment.by == localId then
			local streak = if type(moment.streak) == "number" then moment.streak else 1
			best = if best then math.max(best, streak) else streak
		end
	end
	return best, knockedOut
end

-- Runtime ------------------------------------------------------------------------------------------------------------

local function ensureBanner(): KillBanner.KillBanner?
	local current = banner
	if current and current.root.Parent ~= nil then
		return current
	end
	local ok, gui = pcall(UIController.screenGui, GUI_NAME)
	if not ok then
		log:warn("no kill banner gui:", gui)
		return nil
	end
	local made = KillBanner.new(gui)
	banner = made
	if cleanup then
		cleanup:add(function()
			made:destroy()
		end)
	end
	return made
end

-- Where the burst sits this frame: KillFx.burstDepthStuds in front of the camera, on the banner's centre, facing
-- away from the viewer (the template's Front points into the screen).
local function burstFrame(): CFrame?
	local camera = Workspace.CurrentCamera
	local current = banner
	if camera == nil or current == nil then
		return nil
	end
	local center = current:center()
	if center == nil then
		return nil
	end
	local ray = camera:ScreenPointToRay(center.X, center.Y)
	local at = ray.Origin + ray.Direction * KILL_FX.burstDepthStuds
	return CFrame.lookAt(at, at + camera.CFrame.LookVector, camera.CFrame.UpVector)
end

local function playBurst(style: KillStyle.Style, tier: number)
	local camera = Workspace.CurrentCamera
	local current = banner
	if camera == nil or current == nil then
		return
	end
	local _, discPx = current:center()
	local radius = KillVfx.bannerRadius(discPx, camera.ViewportSize.Y, camera.FieldOfView, KILL_FX.burstDepthStuds)
	KillVfx.banner(style.bannerVfx, tier, burstFrame, radius)
end

local function playSound(style: KillStyle.Style, tier: number)
	local start, finish = KillBannerFormat.soundRegion(tier)
	local ok, err = pcall(SoundController.play, style.sound, {
		region = NumberRange.new(start, finish),
		variance = 0,
		volume = AUDIO.volume,
		priority = AUDIO.priority,
	})
	if not ok then
		log:warn("kill sound failed:", err)
	end
end

-- Shows the banner of `setId` at `tier`, with its sound and burst.
function KillBannerController.show(setId: string, tier: number)
	local style = KillStyle.get(KillStyle.resolve(setId)) :: KillStyle.Style
	local level = KillBannerFormat.tierFor(tier)
	local current = ensureBanner()
	if current == nil then
		return
	end
	current:show(style.id, level, Tweens.reducedMotion())
	playSound(style, level)
	local ok, err = pcall(playBurst, style, level)
	if not ok then
		log:warn("kill banner burst failed:", err)
	end
	lastShown = { setId = style.id, tier = level }
	KillBannerController.Shown:fire(style.id, level)
end

local function onMatchMoments(moments: { any }, view: any)
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local streak, knockedOut = KillBannerController.matchKill(moments, player.UserId)
	if knockedOut then
		duelStreak = KillBannerController.nextDuelStreak(duelStreak, "knockedOut")
	end
	if streak == nil then
		return
	end
	local squishyId = if type(view) == "table" and type(view.you) == "table" then view.you.squishyId else nil
	local setId = KillBannerFormat.setFor(squishyId)
	local tier = KillBannerFormat.tierFor(streak)
	HitStop.after(function()
		KillBannerController.show(setId, tier)
	end)
end

local function onKoDealt(effectId: string?)
	if StateController.match() ~= nil then
		return -- a match K.O.: its banner comes with the server's streak (MatchMoments)
	end
	duelStreak = KillBannerController.nextDuelStreak(duelStreak, "dealt")
	KillBannerController.show(KillStyle.resolve(effectId), KillBannerFormat.tierFor(duelStreak))
end

local function onEliminated(victimId: number, _attackerId: number?)
	local player = Players.LocalPlayer
	if player and victimId == player.UserId then
		duelStreak = KillBannerController.nextDuelStreak(duelStreak, "knockedOut")
	end
end

local function onDuelResult(result: any)
	local outcome = if type(result) == "table" then result.outcome else nil
	if outcome == "loss" or outcome == "draw" then
		duelStreak = KillBannerController.nextDuelStreak(duelStreak, "lost")
	end
end

local function debugHooks(c: Cleanup.Cleanup)
	if not (RunService:IsStudio() and Config.Debug.debugHooks) then
		return
	end
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChildOfClass("PlayerScripts")
	if scripts == nil then
		return
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = DEBUG_NAME
	fn.OnInvoke = function(command: string, a: any, b: any): any
		if command == "show" then
			KillBannerController.show(a, b or 1)
			return true
		elseif command == "kill" then
			local style = KillStyle.get(KillStyle.resolve(a)) :: KillStyle.Style
			local camera = Workspace.CurrentCamera
			local at = if typeof(b) == "Vector3"
				then b
				elseif camera then camera.CFrame.Position + camera.CFrame.LookVector * 8
				else Vector3.zero
			return KillVfx.kill(style.killVfx, at)
		elseif command == "seek" then
			local current = banner
			if current then
				current:seek(if type(a) == "number" then a else 1)
			end
			return current ~= nil
		elseif command == "match" then
			local streak = if type(a) == "number" then a else 1
			onMatchMoments({ { kind = "ko", by = player.UserId, victim = 0, streak = streak } }, { you = { squishyId = b } })
			return true
		elseif command == "state" then
			local current = banner
			return {
				duelStreak = duelStreak,
				showing = current ~= nil and current:showing(),
				vfx = KillVfx.counts(),
				last = lastShown,
			}
		end
		return nil
	end
	fn.Parent = scripts
	c:add(fn)
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function KillBannerController.init()
	cleanup = Cleanup.new()
end

function KillBannerController.start()
	local c = cleanup or Cleanup.new()
	cleanup = c
	c:add(StateController.MatchMoments:connect(onMatchMoments))
	c:add(VfxController.KoDealt:connect(onKoDealt))
	c:add(VfxController.Eliminated:connect(onEliminated))
	c:add(StateController.DuelResultReceived:connect(onDuelResult))
	debugHooks(c)
end

function KillBannerController.destroy()
	local c = cleanup
	cleanup = nil
	banner = nil
	if c then
		c:clean()
	end
	KillVfx.clear()
end

return KillBannerController
