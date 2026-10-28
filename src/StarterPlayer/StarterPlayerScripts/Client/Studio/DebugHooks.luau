--!strict
-- DebugHooks (client only, Studio only). DESIGN §13.1, §9.4, §13.4.
-- Loaded by the client bootstrap only inside Studio and only while Config.Debug.debugHooks is on (it re-checks both
-- and does nothing otherwise). Creates the BindableFunction PlayerScripts.SD_DebugClient for Play tests:
--   SD_DebugClient:Invoke("pose", name, weight)  shows a PoseLibrary pose on the local character on top of
--                                                everything (sign checks); name nil or weight <= 0 clears it
--   SD_DebugClient:Invoke("squeeze")             plays the local squeeze (SqueezeController.playLocal; feel only)
--   SD_DebugClient:Invoke("squeezePress")        Part 5: one real squeeze press where the player stands (anywhere in
--                                                the lobby since spec 2026-10-11 §5; the SqueezeRequest path, the same
--                                                rules as a key press); { ok = sent, error = reason }
--   SD_DebugClient:Invoke("squeezeHold", on)     Part 5 (§17.12 L3): on = true starts a virtual hold-to-squeeze where
--                                                the player stands under every stop rule (600 s, queue 60 s, modal,
--                                                context...); false releases it
--   SD_DebugClient:Invoke("grip")                Part 5: Grip client state (GripController.debugState: total, level,
--                                                card, waypoint, ...), the held-back grip.* toasts
--                                                (NotifyController.heldCount), nameplates and the squeeze state
--   SD_DebugClient:Invoke("gripIdle")            Part 5: opens the idle card as if LocalPlayer.Idled had reached
--                                                Config.Grip.idleReminderSeconds
--   SD_DebugClient:Invoke("ui")                  Part 5: the debugState of HudController, InventoryController,
--                                                SettingsController and SoundController, and the held-back toasts
--   SD_DebugClient:Invoke("state")               small table: equipped id, held models, joint layers, squeeze,
--                                                controls, Cleanup.liveCount(), cached templates, the audio zone,
--                                                the aim state and the AutoDriver (giantPads and the "padPathB"
--                                                command went with the giant pads, build plan Phase 6)
--   SD_DebugClient:Invoke("fire", target?)       one throw now through ThrowController (the same rules as a press and
--                                                the real ThrowRequest remote): target nil / "auto" = the opponent in a
--                                                duel, else the nearest practice target; "opponent"; "target"; or a
--                                                TargetId. Reading (§13.1 "fire(remote, …)", the fallback for firing
--                                                remotes from execute_luau): when `target` is the name of a client ->
--                                                server remote, that remote is sent with the remaining arguments
--                                                (RemoteEvent: { ok = sent }; RemoteFunction: { ok, result })
--   SD_DebugClient:Invoke("ult", target?)        the ultimate toward the same aim as "fire"
--   SD_DebugClient:Invoke("auto", on)            AutoDriver auto-fire on / off (it acts only while SD_TestScenario
--                                                is set)
--   SD_DebugClient:Invoke("drive")               the AutoDriver's state (scenario, mode, throws sent, last reason)
--   SD_DebugClient:Invoke("counts")              leak and load counters: PlayerGui descendants, Cleanup.liveCount(),
--                                                viewports, Workspace.SD_ClientFx descendants, Scheduler effects,
--                                                outgoing remote calls, and the projectile renderer (rendered, waiting,
--                                                pooled, highlights, trails, live connections), VFX, throw and
--                                                practice counters; feel pass (§18.11 juice check 12): meshQuota
--                                                (MeshQuota.count(): editable meshes held), splats and ripple (the
--                                                SplatController and JellyRippleController counters) and ambient
--                                                (AmbientController.debugState: lobby movers, breathers, resting)
-- Feel pass (DESIGN §18.10 L6, §18.11):
--   SD_DebugClient:Invoke("sounds")              the last play attempts (SoundController.recent(): { key, t, result },
--                                                result played / noId / cooldown / caps / distance) and the mix state;
--                                                before any id exists a noId result counts as "asked" (§18.6)
--   SD_DebugClient:Invoke("ripplePathB", on)     JellyRippleController.debugForcePathB(on): on = path B everywhere (one
--                                                log line per skin key), false = path A again
--   SD_DebugClient:Invoke("ripplePoke", piece, face, u, v)  JellyRippleController.debugPoke: one ripple on a cover
--                                                piece's face at (u, v), with no throw (S7, S10 checks)
--   SD_DebugClient:Invoke("juice", name, opts?)  one local visual from a fake payload; no remote is sent:
--                                                "splat", "hitstop", "punch", "confetti", "victim"
--                                                (VfxController.debugJuice(name, opts)) or "coinFlight"
--                                                (HudController.debugCoinFlight(amount); opts = the amount or
--                                                { amount = n }, default 200). Reading: when opts has no position,
--                                                these hooks add the surface under the screen centre (position and
--                                                normal; else a point ahead of the camera) and the equipped squishyId,
--                                                so a splat has a surface to land on
-- Part 7 (DESIGN §13.1, §13.2 Part 7 row; boxes, shop, quests, daily, onboarding):
--   SD_DebugClient:Invoke("boxes")               BoxController.debugState(): the selected box and its open-area view
--                                                (kind, text, enabled, reason, note), the policy and Coins (as
--                                                shown; serverCoins, ownedShown and heldReveals for the reveal
--                                                holds), the
--                                                in-flight / pending / played request ids, the reveal queue and the
--                                                running reveal (phase, elapsed, final, acked), the stage, the counter
--                                                prompt texts and the odds board text
--   SD_DebugClient:Invoke("openBox", boxId)      the real Open flow on that box (the screen opens on it, the open area
--                                                must allow it, the confirming press after the double-click guard,
--                                                BoxOpen with a new GUID); yields until the reply:
--                                                { ok, reason?, requestId, squishyId? }; the reveal then plays
--   SD_DebugClient:Invoke("holdReveals", on)     true pauses the unseen-reveal replay (reply reveals still play);
--                                                false resumes it (the L3 "disconnect mid-open" check)
--   SD_DebugClient:Invoke("skipReveal")          jumps the running reveal to its final state (sends AckReveal once)
--   SD_DebugClient:Invoke("shop" | "quests" | "daily" | "onboarding")   ShopController / QuestController /
--                                                DailyController / OnboardingController .debugState()
-- Part 6 (DESIGN §10, §10.11 leak test, §13.2 Part 6 row; Inspect and the Collection pedestals):
--   SD_DebugClient:Invoke("openInspect", id, source?)  InspectController.open(id, { source = source or "debug" }) (the
--                                                entry points' path; refused like them from Matched through
--                                                Returning); { ok = opened, state = InspectController.debugState() }
--   SD_DebugClient:Invoke("closeInspect", reason?)  InspectController.close(reason or "debug") (restore included);
--                                                { ok = closed, state = InspectController.debugState() }
--   SD_DebugClient:Invoke("inspect")             InspectController.debugState(): phase, squishyId, owned, source, the
--                                                model and stage, previews and dots, and the restore view (cameraType,
--                                                mouseIconEnabled, promptsEnabled, blocked, blockReasons, contexts,
--                                                selectedObject, musicDucked, restorePending) and the Equip state
--   SD_DebugClient:Invoke("inspectSqueeze")      one squeeze preview (InspectController.squeeze(); no remote, no Coins)
--   SD_DebugClient:Invoke("inspectSelect", id)   InspectController.select(id): another squishy while Inspect is open
--   SD_DebugClient:Invoke("collection")          CollectionController.debugState() (the pedestal displays)
--   "counts" also gives stageDescendants (#ViewportStage viewport descendants; -1 before the stage exists) and
--   clientFxChildren (#Workspace.SD_ClientFx children) for the §10.11 leak test (tools/mcp/inspect-leak.lua).
-- Part 8 (DESIGN §13.1, §11.2, §11.4; the layout audit under the Device Simulator and tools/mcp/acceptance.mjs):
--   SD_DebugClient:Invoke("layoutAudit", opts?)  Studio/LayoutAudit.run: what does not fit on screen. opts = nil (what
--                                                shows now, view "current"; also during a duel) | { screens = "all"
--                                                (lobby only: closes every modal, audits the bare lobby, then opens,
--                                                audits and closes each modal that opens without side effects, then
--                                                reopens what was open) | { screenName... }, maxItems = n (40) }.
--                                                Reply { ok, ran, mode, viewport, scale, class, textScale,
--                                                preferredInput, hud = { leftBottomShare, leftMaxShare, planFits,
--                                                narrow, thumbstickZone }, views = { { name, primary, primaryOk,
--                                                selected, offscreen, textOverflow, smallTargets, overlaps, smallText,
--                                                belowFold, textTruncated, brokenWords, hudOverlaps, thumbZone,
--                                                thumbZoneExpected } }, skipped, counts, truncated } (the rules are in
--                                                LayoutAudit's header; the foam fix batch added the last four lists,
--                                                hud.narrow and hud.thumbstickZone; dockRows went with the dock, spec
--                                                2026-10-11; `touch` reads ControlsController.preferredInput()).
--                                                Never sends a remote: Inspect
--                                                is skipped while its open would send the onboarding step, "queue"
--                                                and "boxReveal" are never opened
--   SD_DebugClient:Invoke("queue")               QueueController.debugState(): the queue state, the pill (pillVisible,
--                                                placement {x, y, width, row, fits}, hint) and linkedRowButtons. Reading
--                                                (integrator): execute_luau's plugin VM keeps its own require cache, so
--                                                require(QueueController) there is a fresh, unstarted copy; Studio checks
--                                                read the running one through this hook
-- Squishy overhaul (spec 2026-10-09 §5, §6 Studio checks 2, 3 and the perf scenarios):
--   SD_DebugClient:Invoke("rigPose", id, pose?)  shows `id` in Inspect (opens or selects it) and freezes its model in
--                                                `pose` = { squash = 0-1 of the toy's depth, face = "normal" | "squish"
--                                                | "wow", blink = 0-1 (1 = shut), sections = -1.1..1.1 × each
--                                                section's maxDeg } (InspectController.debugPose); pose nil lets it
--                                                live again; { ok, state = InspectController.debugState() }
--   SD_DebugClient:Invoke("revealPreview", id)   BoxController.debugRevealPreview(id): the box reveal of `id` as local
--                                                presentation only (no remote, no grant)
--   SD_DebugClient:Invoke("rigStress", n, opts?) Studio/RigStress: n client-only rigged squishies on stands in front of
--                                                the character, stepped in the "SD_Rigs" profiler scope (0 removes
--                                                them); opts = { squeeze = true (a tap every hold repeat), detail =
--                                                "hero" | "near" | "far" }; { ok, count }
--   SD_DebugClient:Invoke("screen", name, open?) UIController.open(name) (open true or nil) or close(name, "debug")
--                                                (false) of a registered screen, as its buttons do (perf.mjs
--                                                "squishies_screen"); { ok, open = isOpen(name), modals }
-- First person (spec 2026-10-10 §6 Studio checks 4, 5 and 12; spec 2026-10-11 §8):
--   SD_DebugClient:Invoke("firstPerson", on?)    FirstPersonController.setEnabled(on) (the session switch; nil only
--                                                reads); { ok, enabled, active, mode, look = FirstPersonController.look()
--                                                ("duel" | "practice" | "lobby" | nil), shown = the overlay is up }
--   SD_DebugClient:Invoke("lobbyZoom", on?)      Roblox's own first-person zoom in the lobby, as the mouse wheel does it
--                                                (perf.mjs "lobby_first_person"): true holds the max zoom at Roblox's
--                                                nearest (0.5) so the camera module zooms into the head; false puts the
--                                                saved max back, holds the min at the saved distance for two frames (the
--                                                camera comes back out, as FirstPersonController's exit) and then the
--                                                saved min; nil only reads. Refused while first person is on (it owns
--                                                the zoom); { ok, zoomed, look, shown }
--   SD_DebugClient:Invoke("vmPose", name?)       ViewmodelController.debugPose(name): freezes the first-person overlay
--                                                for pictures ("idle", "squeeze", "windup", "release", "empty",
--                                                "popin", "rush"); nil lets it live again; { ok, state = its
--                                                debugState() }
--   SD_DebugClient:Invoke("vmTouchGui", on)      ViewmodelController.setTouchGuiFallback(on): raises Roblox's TouchGui
--                                                over the overlay while it shows (if DisplayOrder -1 does not sort
--                                                under it); { ok, state }
--   SD_DebugClient:Invoke("vmInspect", t?)       final polish 2026-10-11: the held toy's Inspect showcase in the
--                                                overlay: a number freezes it at t seconds for pictures
--                                                (ViewmodelController.debugInspect), true plays it live (inspect(), as
--                                                R), nil lets the overlay live again; { ok, state }
-- Match HUD M4 (2026-10-16; plan work/matchhud2/PLAN.md §4 M4, v1 §1.9):
--   SD_DebugClient:Invoke("matchHud", state?, opts?)  MatchHudController.debugShow: shows one pretend match state
--                                                (Studio/MatchHudFixtures, e.g. "tdm_knockedOut", "ffa_endWin") with
--                                                every match HUD piece built and its moments played once; opts =
--                                                { players = 4..12 }; refused during a real match; state nil ends the
--                                                preview and lists the states (one harness loops them with
--                                                "layoutAudit"); { ok, state, pieces, phase, matchPhase, players,
--                                                moments, outcome, compact, scale } or { ok, states }; also
--                                                "matchHudState": MatchHudController.debugState()
-- The feel-pass modules of other lanes (JellyRippleController, SplatController, MeshQuota), the Part 7 screens of the
-- other lanes (ShopController, QuestController, DailyController, OnboardingController), the Part 6 controllers
-- (InspectController, CollectionController) and the new functions on built ones are looked up when a command runs
-- (reading of §18.10: lanes build in parallel, and the bootstrap also skips modules that are not there yet), so every
-- other hook keeps working while one of them is missing; a missing one answers
-- { ok = false, error = "<name> is not built yet" }.
-- Every command returns a table { ok = boolean, ... }; an unknown command returns { ok = false, error = <text> }.
-- These are debug strings for tests, never shown to players.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Remotes = require(Shared.Remotes)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local SquishyCache = require(Client.Models.SquishyCache)
local Theme = require(Client.UI.Theme)
local ViewportStage = require(Client.UI.ViewportStage)
local BoxController = require(Client.Controllers.BoxController)
local CharacterAnimController = require(Client.Controllers.CharacterAnimController)
local ControlsController = require(Client.Controllers.ControlsController)
local GripController = require(Client.Controllers.GripController)
local HeldSquishyController = require(Client.Controllers.HeldSquishyController)
local HudController = require(Client.Controllers.HudController)
local InventoryController = require(Client.Controllers.InventoryController)
local NameplateController = require(Client.Controllers.NameplateController)
local NetController = require(Client.Controllers.NetController)
local NotifyController = require(Client.Controllers.NotifyController)
local PracticeController = require(Client.Controllers.PracticeController)
local ProjectileRenderer = require(Client.Controllers.ProjectileRenderer)
local SettingsController = require(Client.Controllers.SettingsController)
local SoundController = require(Client.Controllers.SoundController)
local SqueezeController = require(Client.Controllers.SqueezeController)
local StateController = require(Client.Controllers.StateController)
local ThrowController = require(Client.Controllers.ThrowController)
local UIController = require(Client.Controllers.UIController)
local VfxController = require(Client.Controllers.VfxController)
local WorldBinder = require(Client.Controllers.WorldBinder)
local AutoDriver = require(script.Parent.AutoDriver)
local LayoutAudit = require(script.Parent.LayoutAudit)
local RigStress = require(script.Parent.RigStress)

-- Types

type Reply = { [string]: any }

-- Constants

local FUNCTION_NAME = "SD_DebugClient"
local ATTR_EQUIPPED = "SD_Equipped"
local CLIENT_FX = "SD_ClientFx"
-- The juice names VfxController.debugJuice takes (§18.11 juice checks 7-10); "coinFlight" goes to HudController.
local VFX_JUICE: { [string]: boolean } = { splat = true, hitstop = true, punch = true, confetti = true, victim = true }
local COIN_FLIGHT = "coinFlight"
local DEFAULT_COIN_FLIGHT = 200 -- reading: a duel-reward-sized gain (5 coins fly, §18.5.2 B2)
-- Part 7 screens of other lanes, looked up at run time: command -> controller name (Part 8: the queue pill).
local SCREEN_STATES: { [string]: string } = {
	shop = "ShopController",
	quests = "QuestController",
	daily = "DailyController",
	onboarding = "OnboardingController",
	queue = "QueueController",
}
-- Part 6 controllers, looked up at run time (lanes build in parallel).
local INSPECT_CONTROLLER = "InspectController"
local COLLECTION_CONTROLLER = "CollectionController"
local DEBUG_SOURCE = "debug" -- the source of an openInspect and the reason of a closeInspect when none is given
-- Part 8 layoutAudit: Inspect's first open marks the onboarding "inspect" step (OnboardingController, another lane's
-- module, looked up at run time like the others).
local ONBOARDING_CONTROLLER = "OnboardingController"
local ONBOARDING_FORMAT = "OnboardingFormat"
local ONBOARDING_FIELD = "onboarding"
local ONBOARDING_INSPECT_STEP = "inspect"
local JUICE_PROBE_STUDS = 60 -- the surface under the screen centre, this far at most ...
local JUICE_AHEAD_STUDS = 12 -- ... else a point this far ahead of the camera
local LOBBY_ZOOM_STUDS = 0.5 -- lobbyZoom: Roblox's nearest zoom (FirstPersonController's CUT_ZOOM)
local LOBBY_ZOOM_RESTORE_FRAMES = 2 -- lobbyZoom off: the min held at the saved distance this many frames

-- Module table

local DebugHooks = {}

-- Private

local log = Log.new("DebugClient")
local cleanup: Cleanup.Cleanup? = nil
local lobbyZoomSaved: { min: number, max: number, distance: number }? = nil -- lobbyZoom on: the zoom to put back

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

-- A client module that may not exist yet (another lane's file), or nil. It is the same table the bootstrap required.
local function optionalModule(folderName: string, name: string): any
	local folder = Client:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(name) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(dynamicRequire, module)
	return if ok then result else nil
end

-- A function of a module table, or nil when that module or function is not built yet.
local function functionOf(module: any, name: string): ((...any) -> ...any)?
	local fn = if type(module) == "table" then module[name] else nil
	return if type(fn) == "function" then fn else nil
end

local function missing(name: string): Reply
	return { ok = false, error = name .. " is not built yet" }
end

-- A hook's answer as a reply table: a table is passed on (ok defaults to true); (ok, reason) becomes
-- { ok = ok, error = reason }.
local function asReply(result: any, reason: any): Reply
	if type(result) == "table" then
		if result.ok == nil then
			result.ok = true
		end
		return result
	end
	return { ok = result ~= false, error = if reason ~= nil then tostring(reason) else nil }
end

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function pose(name: unknown, weight: unknown): Reply
	if name ~= nil and type(name) ~= "string" then
		return { ok = false, error = "pose name must be a string or nil" }
	end
	if weight ~= nil and (type(weight) ~= "number" or weight ~= weight) then
		return { ok = false, error = "weight must be a number or nil" }
	end
	local ok, reason = CharacterAnimController.setDebugPose(
		Players.LocalPlayer,
		name :: string?,
		if weight == nil then nil else math.clamp(weight :: number, 0, 1)
	)
	return { ok = ok, error = reason }
end

local function squeeze(): Reply
	local ok, reason = SqueezeController.playLocal()
	return { ok = ok, error = reason }
end

local function squeezePress(): Reply
	local ok, reason = SqueezeController.debugPress()
	return { ok = ok, error = reason }
end

local function squeezeHold(on: unknown): Reply
	if type(on) ~= "boolean" then
		return { ok = false, error = "squeezeHold needs true or false" }
	end
	local ok, reason = SqueezeController.debugHold(on)
	return { ok = ok, error = reason }
end

local function grip(): Reply
	local reply = GripController.debugState()
	reply.ok = true
	reply.heldToasts = NotifyController.heldCount()
	reply.nameplates = NameplateController.debugState()
	reply.squeeze = SqueezeController.debugState()
	return reply
end

local function gripIdle(): Reply
	return { ok = GripController.debugIdle() }
end

-- Part 5: the lobby screens' state (HUD, Squishies, Settings) and the sound mix, for Studio play checks.
local function ui(): Reply
	return {
		ok = true,
		hud = HudController.debugState(),
		inventory = InventoryController.debugState(),
		settings = SettingsController.debugState(),
		sound = SoundController.debugState(),
		heldToasts = NotifyController.heldCount(),
	}
end

local function state(): Reply
	local player = Players.LocalPlayer
	local zone = WorldBinder.currentZone()
	local aim = ThrowController.getAimState()
	return {
		ok = true,
		equipped = player:GetAttribute(ATTR_EQUIPPED),
		held = HeldSquishyController.debugState(),
		layers = CharacterAnimController.debugState(),
		squeeze = SqueezeController.debugState(),
		controls = {
			blocked = ControlsController.isBlocked(),
			blockReasons = ControlsController.blockReasons(),
			contexts = ControlsController.activeContexts(),
			actions = ControlsController.boundActions(),
			preferredInput = ControlsController.preferredInput().Name,
		},
		aim = { state = aim.state, reason = aim.reason, readyAt = aim.readyAt, progress = aim.progress },
		practiceZone = PracticeController.isInZone(),
		autoDriver = AutoDriver.state(),
		cleanupLive = Cleanup.liveCount(),
		cachedTemplates = SquishyCache.templateCount(),
		audioZone = if zone then zone.zoneId else nil,
		gripLevel = GripController.level(),
	}
end

-- §13.1 fallback: sends a client -> server remote by name with the remaining arguments (NetController's own checks
-- and token buckets apply).
local function sendRemote(name: string, ...: any): Reply
	local spec = Remotes.SPEC[name]
	if spec.kind == "RemoteFunction" then
		local result = NetController.invokeAsync(name, ...)
		return { ok = result.ok, result = result }
	end
	return { ok = NetController.fire(name, ...) }
end

local function fire(target: unknown, ...: any): Reply
	if type(target) == "string" then
		local spec = Remotes.SPEC[target]
		if spec ~= nil and spec.dir == "c2s" then
			return sendRemote(target, ...)
		end
	end
	return AutoDriver.fireOnce(target)
end

local function ult(target: unknown): Reply
	return AutoDriver.ultimateOnce(target)
end

local function auto(on: unknown): Reply
	if type(on) ~= "boolean" then
		return { ok = false, error = "auto needs true or false" }
	end
	AutoDriver.setAuto(on)
	return { ok = true }
end

local function drive(): Reply
	return AutoDriver.state()
end

-- §18.6: the Studio play log (SoundController.recent) and the mix state.
local function sounds(): Reply
	local recent = functionOf(SoundController, "recent")
	if recent == nil then
		return missing("SoundController.recent")
	end
	return { ok = true, recent = recent(), sound = SoundController.debugState() }
end

local function ripplePathB(on: unknown): Reply
	if type(on) ~= "boolean" then
		return { ok = false, error = "ripplePathB needs true or false" }
	end
	local force = functionOf(optionalModule("Controllers", "JellyRippleController"), "debugForcePathB")
	if force == nil then
		return missing("JellyRippleController.debugForcePathB")
	end
	return asReply(force(on))
end

local function ripplePoke(piece: unknown, face: unknown, u: unknown, v: unknown): Reply
	if type(piece) ~= "string" or (type(face) ~= "string" and not isNumber(face)) then
		return { ok = false, error = "ripplePoke needs a piece name and a face" }
	end
	if not isNumber(u) or not isNumber(v) then
		return { ok = false, error = "ripplePoke needs numbers u and v" }
	end
	local poke = functionOf(optionalModule("Controllers", "JellyRippleController"), "debugPoke")
	if poke == nil then
		return missing("JellyRippleController.debugPoke")
	end
	return asReply(poke(piece, face, u, v))
end

-- The surface under the screen centre (a cosmetic probe: the local character and client effects are ignored), else a
-- point ahead of the camera, facing it.
local function surfaceAhead(): (Vector3?, Vector3?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, nil
	end
	local frame = camera.CFrame
	local exclude: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	if fx then
		table.insert(exclude, fx)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(frame.Position, frame.LookVector * JUICE_PROBE_STUDS, params)
	if hit then
		return hit.Position, hit.Normal
	end
	return frame.Position + frame.LookVector * JUICE_AHEAD_STUDS, -frame.LookVector
end

local function juice(name: unknown, opts: unknown): Reply
	if name == COIN_FLIGHT then
		local amount = DEFAULT_COIN_FLIGHT
		if isNumber(opts) then
			amount = opts :: number
		elseif type(opts) == "table" and isNumber((opts :: any).amount) then
			amount = (opts :: any).amount
		end
		local fly = functionOf(HudController, "debugCoinFlight")
		if fly == nil then
			return missing("HudController.debugCoinFlight")
		end
		return asReply(fly(math.floor(amount)))
	end
	if type(name) ~= "string" or not VFX_JUICE[name] then
		return { ok = false, error = "juice needs splat, hitstop, punch, confetti, coinFlight or victim" }
	end
	local play = functionOf(VfxController, "debugJuice")
	if play == nil then
		return missing("VfxController.debugJuice")
	end
	local options: { [string]: any } = {}
	if type(opts) == "table" then
		for key, value in opts :: { [any]: any } do
			if type(key) == "string" then
				options[key] = value
			end
		end
	end
	if options.position == nil then
		local position, normal = surfaceAhead()
		options.position = position
		if options.normal == nil then
			options.normal = normal
		end
	end
	if options.squishyId == nil then
		options.squishyId = Players.LocalPlayer:GetAttribute(ATTR_EQUIPPED)
	end
	return asReply(play(name, options))
end

-- A feel-pass module's counters (counts(), else debugState()), or nil while it is not built.
local function feelCounters(folderName: string, name: string): any
	local module = optionalModule(folderName, name)
	local read = functionOf(module, "counts") or functionOf(module, "debugState")
	if read == nil then
		return nil
	end
	local ok, result = pcall(read)
	return if ok then result else tostring(result)
end

-- MeshQuota.count() (editable meshes held by the ripple skin and the knead shell), or nil while it is not built.
local function meshQuotaCount(): number?
	local count = functionOf(optionalModule("Anim", "MeshQuota"), "count")
	if count == nil then
		return nil
	end
	local ok, result = pcall(count)
	return if ok and type(result) == "number" then result else nil
end

local function countIn(root: Instance?, className: string?): number
	if root == nil then
		return 0
	end
	if className == nil then
		return #root:GetDescendants()
	end
	local n = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA(className) then
			n += 1
		end
	end
	return n
end

-- §10.11: the shared stage's viewport descendants (camera, model, props); -1 before the stage exists.
local function stageDescendants(): number
	if not ViewportStage.exists() then
		return -1
	end
	return #ViewportStage.get().viewport:GetDescendants()
end

local function counts(): Reply
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local clientFx = Workspace:FindFirstChild(CLIENT_FX)
	return {
		ok = true,
		playerGuiDescendants = countIn(playerGui, nil),
		viewports = countIn(playerGui, "ViewportFrame"),
		cleanupLive = Cleanup.liveCount(),
		clientFx = countIn(clientFx, nil),
		clientFxChildren = if clientFx then #clientFx:GetChildren() else 0,
		stageDescendants = stageDescendants(),
		schedulerEffects = Scheduler.count(),
		netCalls = NetController.callCounts(),
		projectiles = ProjectileRenderer.counts(),
		vfx = VfxController.counts(),
		throw = ThrowController.counts(),
		practice = PracticeController.counts(),
		meshQuota = meshQuotaCount(),
		splats = feelCounters("Controllers", "SplatController"),
		ripple = feelCounters("Controllers", "JellyRippleController"),
		ambient = feelCounters("Controllers", "AmbientController"),
	}
end

-- Part 7: boxes (BoxController) --------------------------------------------------------------------------------------

local function boxes(): Reply
	return asReply(BoxController.debugState())
end

local function openBox(boxId: unknown): Reply
	if type(boxId) ~= "string" then
		return { ok = false, error = "openBox needs a box id" }
	end
	return asReply(BoxController.debugOpen(boxId))
end

local function holdReveals(on: unknown): Reply
	if type(on) ~= "boolean" then
		return { ok = false, error = "holdReveals needs true or false" }
	end
	BoxController.debugHoldReveals(on)
	return { ok = true, held = on }
end

local function skipReveal(): Reply
	local skipped = BoxController.debugSkip()
	return { ok = skipped, error = if skipped then nil else "no reveal is running" }
end

-- Part 7: the other lanes' screens, looked up when the command runs.
local function screenState(command: string): Reply
	local name = SCREEN_STATES[command]
	local read = functionOf(optionalModule("Controllers", name), "debugState")
	if read == nil then
		return missing(name .. ".debugState")
	end
	return asReply(read())
end

-- Part 6: Inspect (InspectController) and the Collection displays (CollectionController) -----------------------------

-- A function of InspectController, or nil while it (or that function) is not built.
local function inspectFunction(name: string): ((...any) -> ...any)?
	return functionOf(optionalModule("Controllers", INSPECT_CONTROLLER), name)
end

-- InspectController.debugState(), or nil while it is not built (a failing read answers its error text).
local function inspectState(): any
	local read = inspectFunction("debugState")
	if read == nil then
		return nil
	end
	local ok, result = pcall(read)
	return if ok then result else tostring(result)
end

local function openInspect(id: unknown, source: unknown): Reply
	if type(id) ~= "string" then
		return { ok = false, error = "openInspect needs a squishy id" }
	end
	if source ~= nil and type(source) ~= "string" then
		return { ok = false, error = "openInspect source must be a string or nil" }
	end
	local open = inspectFunction("open")
	if open == nil then
		return missing(INSPECT_CONTROLLER .. ".open")
	end
	local opened, reason = open(id, { source = source or DEBUG_SOURCE })
	return {
		ok = opened == true,
		error = if opened ~= true and reason ~= nil then tostring(reason) else nil,
		state = inspectState(),
	}
end

local function closeInspect(reason: unknown): Reply
	if reason ~= nil and type(reason) ~= "string" then
		return { ok = false, error = "closeInspect reason must be a string or nil" }
	end
	local close = inspectFunction("close")
	if close == nil then
		return missing(INSPECT_CONTROLLER .. ".close")
	end
	local closed, why = close(reason or DEBUG_SOURCE)
	return {
		ok = closed == true,
		error = if closed ~= true and why ~= nil then tostring(why) else nil,
		state = inspectState(),
	}
end

local function inspect(): Reply
	local read = inspectFunction("debugState")
	if read == nil then
		return missing(INSPECT_CONTROLLER .. ".debugState")
	end
	return asReply(read())
end

local function inspectSqueeze(): Reply
	local squeezePreview = inspectFunction("squeeze")
	if squeezePreview == nil then
		return missing(INSPECT_CONTROLLER .. ".squeeze")
	end
	return asReply(squeezePreview())
end

local function inspectSelect(id: unknown): Reply
	if type(id) ~= "string" then
		return { ok = false, error = "inspectSelect needs a squishy id" }
	end
	local selectSquishy = inspectFunction("select")
	if selectSquishy == nil then
		return missing(INSPECT_CONTROLLER .. ".select")
	end
	return asReply(selectSquishy(id))
end

local function collection(): Reply
	local read = functionOf(optionalModule("Controllers", COLLECTION_CONTROLLER), "debugState")
	if read == nil then
		return missing(COLLECTION_CONTROLLER .. ".debugState")
	end
	return asReply(read())
end

-- Squishy overhaul: rig poses, the reveal preview and the rig stress stands ------------------------------------------

-- Shows `id` in Inspect (open, or select while open) and freezes its model in `pose` (nil lets it live again).
local function rigPose(id: unknown, pose: unknown): Reply
	if type(id) ~= "string" then
		return { ok = false, error = "rigPose needs a squishy id" }
	end
	if pose ~= nil and type(pose) ~= "table" then
		return { ok = false, error = "rigPose pose must be a table or nil" }
	end
	local freeze = inspectFunction("debugPose")
	local open, selectSquishy = inspectFunction("open"), inspectFunction("select")
	if freeze == nil or open == nil or selectSquishy == nil then
		return missing(INSPECT_CONTROLLER .. ".debugPose")
	end
	local state = inspectState()
	local isOpen = type(state) == "table" and state.phase == "Open"
	if not (isOpen and state.squishyId == id) then
		local shown = if isOpen then selectSquishy(id) else open(id, { source = DEBUG_SOURCE })
		if shown ~= true then
			return { ok = false, error = `Inspect could not show {id}`, state = inspectState() }
		end
	end
	local frozen: { [string]: any }? = nil
	if type(pose) == "table" then
		local raw = pose :: { [any]: any }
		local values: { [string]: any } = {}
		for _, key in { "squash", "blink", "sections" } do
			if isNumber(raw[key]) then
				values[key] = raw[key]
			end
		end
		if type(raw.face) == "string" then
			values.face = raw.face
		end
		frozen = values
	end
	return { ok = freeze(frozen) == true, state = inspectState() }
end

local function revealPreview(id: unknown): Reply
	if type(id) ~= "string" then
		return { ok = false, error = "revealPreview needs a squishy id" }
	end
	local preview = functionOf(BoxController, "debugRevealPreview")
	if preview == nil then
		return missing("BoxController.debugRevealPreview")
	end
	return asReply(preview(id))
end

local function rigStress(n: unknown, opts: unknown): Reply
	if not isNumber(n) then
		return { ok = false, error = "rigStress needs a number of models (0 removes them)" }
	end
	local options: RigStress.Options = {}
	if type(opts) == "table" then
		local raw = opts :: { [any]: any }
		options.squeeze = raw.squeeze == true
		options.detail = if type(raw.detail) == "string" then raw.detail else nil
	end
	return asReply(RigStress.set(n :: number, options))
end

-- Opens (open true or nil) or closes (false) a registered screen through UIController, as its own buttons do.
local function screen(name: unknown, open: unknown): Reply
	if type(name) ~= "string" or not UIController.isRegistered(name) then
		return { ok = false, error = "screen needs a registered screen name" }
	end
	if open ~= nil and type(open) ~= "boolean" then
		return { ok = false, error = "screen open must be true, false or nil" }
	end
	local done = if open == false then UIController.close(name, DEBUG_SOURCE) else UIController.open(name)
	return { ok = done, open = UIController.isOpen(name), modals = UIController.openModals() }
end

-- First person: Roblox's own zoom into the head in the lobby (spec 2026-10-11 §3.8, §8 check 7) --------------------

local function lobbyZoom(on: unknown): Reply
	if on ~= nil and type(on) ~= "boolean" then
		return { ok = false, error = "lobbyZoom needs true, false or nil" }
	end
	local fp = optionalModule("Controllers", "FirstPersonController")
	local look, isActive = functionOf(fp, "look"), functionOf(fp, "isActive")
	if look == nil or isActive == nil then
		return missing("FirstPersonController.look")
	end
	local player = Players.LocalPlayer
	if on == true and lobbyZoomSaved == nil then
		if isActive() then
			return { ok = false, error = "first person is on (a duel or the throw box): it owns the zoom" }
		end
		local camera = Workspace.CurrentCamera
		lobbyZoomSaved = {
			min = player.CameraMinZoomDistance,
			max = player.CameraMaxZoomDistance,
			distance = if camera
				then (camera.CFrame.Position - camera.Focus.Position).Magnitude
				else player.CameraMaxZoomDistance,
		}
		player.CameraMaxZoomDistance = LOBBY_ZOOM_STUDS
	elseif on == false and lobbyZoomSaved ~= nil then
		local saved = lobbyZoomSaved
		lobbyZoomSaved = nil
		player.CameraMaxZoomDistance = saved.max
		player.CameraMinZoomDistance = math.clamp(saved.distance, saved.min, math.max(saved.min, saved.max))
		for _ = 1, LOBBY_ZOOM_RESTORE_FRAMES do
			RunService.RenderStepped:Wait()
		end
		player.CameraMinZoomDistance = saved.min
	end
	local shown = functionOf(optionalModule("Controllers", "ViewmodelController"), "isShown")
	return { ok = true, zoomed = lobbyZoomSaved ~= nil, look = look(), shown = if shown then shown() else nil }
end

-- Part 8: the layout audit (Studio/LayoutAudit) ----------------------------------------------------------------------

-- True when opening Inspect now sends nothing: OnboardingController's Inspect listener sends OnboardingStep "inspect"
-- unless a replay runs (then it marks the replay instead), the step was sent or is done, or the profile is not ready.
local function inspectSafe(): (boolean, string?)
	local read = functionOf(optionalModule("Controllers", ONBOARDING_CONTROLLER), "debugState")
	if read == nil then
		return true, nil -- nothing listens
	end
	local okRead, state = pcall(read)
	if not okRead or type(state) ~= "table" then
		return false, "the onboarding state could not be read"
	end
	if state.replay == true then
		return false, "an onboarding replay is running (opening Inspect marks its step)"
	end
	if state.inspectSent == true or not StateController.isProfileReady() then
		return true, nil
	end
	local done = functionOf(optionalModule("UI", ONBOARDING_FORMAT), "done")
	if done == nil then
		return false, "OnboardingFormat.done is not built"
	end
	local okDone, set = pcall(done, StateController.get(ONBOARDING_FIELD))
	if okDone and type(set) == "table" and set[ONBOARDING_INSPECT_STEP] == true then
		return true, nil
	end
	return false, "its first open would send the onboarding step (OnboardingStep inspect)"
end

local function layoutAudit(opts: unknown): Reply
	local open = inspectFunction("open")
	local deps: LayoutAudit.Deps = {
		ui = (UIController :: any) :: LayoutAudit.UIDeps,
		playerGui = function(): Instance?
			return Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		end,
		isLobbyLocked = StateController.isLobbyLocked,
		equipped = function(): string?
			return StateController.equipped()
		end,
		textScale = function(): number
			return Theme.textSize("Body") / Config.UI.TextSize.Body
		end,
		openInspect = if open
			then function(id: string): boolean
				return open(id, { source = DEBUG_SOURCE }) == true
			end
			else nil,
		inspectedId = function(): string?
			local state = inspectState()
			return if type(state) == "table" and type(state.squishyId) == "string" then state.squishyId else nil
		end,
		inspectSafe = inspectSafe,
		-- A reveal runs, is open or waits in the queue (it would start when Inspect closes, then close with an ack).
		revealBusy = function(): boolean
			local okState, box = pcall(BoxController.debugState)
			if not okState or type(box) ~= "table" then
				return true -- unknown: do not risk it
			end
			return box.reveal ~= nil or box.revealOpen == true or (type(box.queue) == "table" and #box.queue > 0)
		end,
		-- The left column plan (HudFormat.leftColumnPlan): false when no layout can end above the line.
		columnFits = function(): boolean?
			return HudController.columnPlan().fits
		end,
		-- Touch input as the HUD reads it (its narrow rules: the thumbstick zone).
		touch = function(): boolean
			return ControlsController.preferredInput() == Enum.PreferredInput.Touch
		end,
	}
	return LayoutAudit.run(opts, deps)
end

local COMMANDS: { [string]: (...any) -> Reply } = {
	layoutAudit = layoutAudit,
	openInspect = openInspect,
	closeInspect = closeInspect,
	inspect = inspect,
	inspectSqueeze = inspectSqueeze,
	inspectSelect = inspectSelect,
	collection = collection,
	rigPose = rigPose,
	revealPreview = revealPreview,
	rigStress = rigStress,
	screen = screen,
	-- First person (looked up at run time, like the other lanes' modules).
	firstPerson = function(on: unknown): Reply
		local fp = optionalModule("Controllers", "FirstPersonController")
		local setEnabled, isEnabled = functionOf(fp, "setEnabled"), functionOf(fp, "isEnabled")
		if setEnabled == nil or isEnabled == nil then
			return missing("FirstPersonController")
		end
		if on ~= nil and type(on) ~= "boolean" then
			return { ok = false, error = "firstPerson needs true, false or nil" }
		end
		if on ~= nil then
			setEnabled(on)
		end
		local mode, look = functionOf(fp, "mode"), functionOf(fp, "look")
		local shown = functionOf(optionalModule("Controllers", "ViewmodelController"), "isShown")
		return {
			ok = true,
			enabled = isEnabled(),
			mode = if mode then mode() else nil,
			active = if mode then mode() ~= nil else nil,
			look = if look then look() else nil,
			shown = if shown then shown() else nil,
		}
	end,
	lobbyZoom = lobbyZoom,
	-- Physics upgrade (2026-10-28): MoveFxController's live state; with a moment name, that Config.MoveFx moment on the
	-- own character first (then `signal`, e.g. "landHard"), for photos and checks without a real jump.
	moveFx = function(moment: unknown, signal: unknown): Reply
		local mfx = optionalModule("Controllers", "MoveFxController")
		local debugState, actorFor = functionOf(mfx, "debugState"), functionOf(mfx, "actorFor")
		if debugState == nil or actorFor == nil then
			return missing("MoveFxController")
		end
		if type(moment) == "string" then
			local feel = optionalModule("Anim", "FeelFx")
			local play = functionOf(feel, "play")
			local events = require(ReplicatedStorage.Shared.Config.MoveFx).moments[moment]
			local player = Players.LocalPlayer
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if play == nil or events == nil or root == nil then
				return { ok = false, error = "no such moment, or no character" }
			end
			local run = play(events, actorFor(player, character, root))
			if type(signal) == "string" then
				run:signal(signal)
			end
		end
		return debugState()
	end,
	vmPose = function(name: unknown): Reply
		local viewmodel = optionalModule("Controllers", "ViewmodelController")
		local pose, read = functionOf(viewmodel, "debugPose"), functionOf(viewmodel, "debugState")
		if pose == nil or read == nil then
			return missing("ViewmodelController.debugPose")
		end
		if name ~= nil and type(name) ~= "string" then
			return { ok = false, error = "vmPose needs a pose name or nil" }
		end
		return { ok = pose(name) == true, state = read() }
	end,
	vmTouchGui = function(on: unknown): Reply
		local viewmodel = optionalModule("Controllers", "ViewmodelController")
		local set, read = functionOf(viewmodel, "setTouchGuiFallback"), functionOf(viewmodel, "debugState")
		if set == nil or read == nil then
			return missing("ViewmodelController.setTouchGuiFallback")
		end
		if type(on) ~= "boolean" then
			return { ok = false, error = "vmTouchGui needs true or false" }
		end
		set(on)
		return { ok = true, state = read() }
	end,
	vmInspect = function(t: unknown): Reply
		local viewmodel = optionalModule("Controllers", "ViewmodelController")
		local freeze, play = functionOf(viewmodel, "debugInspect"), functionOf(viewmodel, "inspect")
		local read = functionOf(viewmodel, "debugState")
		if freeze == nil or play == nil or read == nil then
			return missing("ViewmodelController.debugInspect")
		end
		if t == true then
			return { ok = play() == true, state = read() }
		elseif t ~= nil and type(t) ~= "number" then
			return { ok = false, error = "vmInspect needs a time in seconds, true or nil" }
		end
		return { ok = freeze(t) == true, state = read() }
	end,
	boxes = boxes,
	openBox = openBox,
	holdReveals = holdReveals,
	skipReveal = skipReveal,
	shop = function(): Reply
		return screenState("shop")
	end,
	quests = function(): Reply
		return screenState("quests")
	end,
	daily = function(): Reply
		return screenState("daily")
	end,
	onboarding = function(): Reply
		return screenState("onboarding")
	end,
	queue = function(): Reply
		return screenState("queue")
	end,
	pose = pose,
	squeeze = squeeze,
	squeezePress = squeezePress,
	squeezeHold = squeezeHold,
	grip = grip,
	gripIdle = gripIdle,
	ui = ui,
	state = state,
	fire = fire,
	ult = ult,
	auto = auto,
	drive = drive,
	counts = counts,
	sounds = sounds,
	ripplePathB = ripplePathB,
	ripplePoke = ripplePoke,
	juice = juice,
	-- Match HUD M4 (looked up at run time, like the other lanes' modules).
	matchHud = function(state: unknown, opts: unknown): Reply
		local show = functionOf(optionalModule("Controllers", "MatchHudController"), "debugShow")
		if show == nil then
			return missing("MatchHudController.debugShow")
		end
		if state ~= nil and type(state) ~= "string" then
			return { ok = false, error = "matchHud needs a state name or nil" }
		end
		return show(state, if type(opts) == "table" then opts else nil)
	end,
	matchHudState = function(): Reply
		local read = functionOf(optionalModule("Controllers", "MatchHudController"), "debugState")
		if read == nil then
			return missing("MatchHudController.debugState")
		end
		local state = read()
		state.ok = true
		return state
	end,
}

local function onInvoke(command: unknown, ...: any): Reply
	local handler = if type(command) == "string" then COMMANDS[command] else nil
	if handler == nil then
		return { ok = false, error = `unknown command {tostring(command)}` }
	end
	local ok, result = pcall(handler, ...)
	if not ok then
		log:warn(`command {command} failed:`, result)
		return { ok = false, error = tostring(result) }
	end
	return result
end

-- Lifecycle

function DebugHooks.init()
	if not (RunService:IsStudio() and Config.Debug.debugHooks) then
		return
	end
	local player = Players.LocalPlayer
	local playerScripts = player and player:FindFirstChildOfClass("PlayerScripts")
	if playerScripts == nil then
		log:warn("PlayerScripts not found; SD_DebugClient not created")
		return
	end
	local c = Cleanup.new()
	cleanup = c
	local existing = playerScripts:FindFirstChild(FUNCTION_NAME)
	if existing then
		existing:Destroy()
	end
	local bindable = c:add(Instance.new("BindableFunction"))
	bindable.Name = FUNCTION_NAME
	bindable.OnInvoke = onInvoke
	bindable.Parent = playerScripts
end

-- Not called by the bootstrap (the client lives for the session).
function DebugHooks.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return DebugHooks
