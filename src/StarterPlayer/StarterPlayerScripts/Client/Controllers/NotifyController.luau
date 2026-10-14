--!strict
-- NotifyController (client only). DESIGN §2.4 ("toasts from Notify and Result reasons"), §2.8 (Notify(code, args?,
-- kind)), §2.10, §3.12 (server.restartSoon), §3.13 (data.* notices), §11.3, §17.2 / §17.7 (grip.* hold-back).
-- * Every Notify code with a Strings text becomes a UIController toast (UI/NotifyFormat words it): reason codes
--   (reason.<code>) and plain keys alike, e.g. server.restartSoon {time}, data.waitingOtherServer, data.loaded,
--   data.openedElsewhere, queue.*, duel.*, ult.*, grip.*. A code without a text is never shown (one warning per code).
--   This is the one place that shows Notify codes. Part 4's QueueController (queue.*, duel.*) and DuelController
--   (ult.*) still toast the same codes themselves: they word them exactly the same way (UI/NotifyFormat), this module
--   connects first (it inits earlier), and UIController re-arms a toast whose text is already up instead of stacking a
--   copy, so a message never shows twice and its sound plays once. Their own Notify listeners can be removed.
-- * Hold-back (§17.2, §17.7): grip.* toasts that arrive from Matched through Returning (StateController lobby lock) are
--   kept, at most Config.UI.Grip.heldToastsMax (3, newest kept), and shown as one merged toast once the lock ends.
--   Overlays fix (2026-10-09): quest.* toasts are held the same way ("Quest complete!" covered the duel result card on
--   a phone; the card lists the quest progress itself), and holdBack(key) -> release keeps holding them while a screen
--   needs it (DuelController: the result card, which stays up after the lock ends); they show once neither holds.
-- * route(prefix, handler) -> unroute: a feature that shows an area itself (a waypoint, its own card) takes those
--   codes; they are not toasted here. Notified(code, args, kind) fires for every known code, routed or not.
-- * show(code, args?, kind?) shows a client-side message the same way; showResult(result) shows a failed Result's
--   reason (with "No Coins were spent." only when the server said charged = false, §2.10).
-- * Sounds (§18.5.2 B5, §18.6): UIController.toast plays each toast's one sound (ui.toast; ui.error for a warn or
--   error toast). This module only passes the mapped key of a code in Config.Audio.toastSounds (grip.levelUp,
--   grip.rankUp -> ui.gripUnlock), so that key stays out of the duel-path files; a merged held
--   toast plays the mapped key of the newest held code that has one. Every key is silent until an id is approved.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local NotifyFormat = require(Client.UI.NotifyFormat)
local NetController = require(script.Parent.NetController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

export type Handler = (code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind) -> ()

type Route = { prefix: string, handler: Handler }

-- Constants

local HELD_MAX = Config.UI.Grip.heldToastsMax -- §17.7: at most 3 held toasts, merged into one
local TOAST_SOUNDS: { [string]: string } = Config.Audio.toastSounds -- code -> sound key (§18.6)

-- Module table

local NotifyController = {}

NotifyController.Notified = Signal.new() :: Signal.Signal<string, Types.NotifyArgs?, Types.NotifyKind>

-- Private

local log = Log.new("Notify")
local cleanup: Cleanup.Cleanup? = nil
local routes: { Route } = {}
local held: { string } = {}
local heldKind: Types.NotifyKind = "info"
local heldSound: string? = nil
local holds: { [{}]: string } = {} -- holdBack tokens (their keys, for debugging)
local warnedCodes: { [string]: boolean } = {}

-- True while held-back codes wait: the lobby lock, or a holdBack that is not released yet.
local function holding(): boolean
	return StateController.isLobbyLocked() or next(holds) ~= nil
end

-- `sound` is a code's mapped key (Config.Audio.toastSounds); nil lets UIController pick ui.toast / ui.error.
local function toast(text: string, kind: Types.NotifyKind, sound: string?)
	UIController.toast(text, kind, if sound then { sound = sound } else nil)
end

local function routeFor(code: string): Route?
	local best: Route? = nil
	for _, route in routes do
		if string.sub(code, 1, #route.prefix) == route.prefix and (best == nil or #route.prefix > #best.prefix) then
			best = route
		end
	end
	return best
end

local function flushHeld()
	local text = NotifyFormat.merge(held)
	held = {}
	if text then
		toast(text, heldKind, heldSound)
	end
	heldKind = "info"
	heldSound = nil
end

local function handle(code: unknown, args: unknown, kind: unknown)
	local text = NotifyFormat.textFor(code, args)
	if text == nil then
		local label = if type(code) == "string" then string.sub(code, 1, 64) else typeof(code)
		if not warnedCodes[label] then
			warnedCodes[label] = true
			log:warn(`Notify code without a text: {label}`)
		end
		return
	end
	local name = code :: string
	local cleanArgs: Types.NotifyArgs? = if type(args) == "table" then args :: any else nil
	-- (cast: the type checker widens a literal union imported through another module's alias)
	local toastKind: Types.NotifyKind = NotifyFormat.kindOf(kind) :: any
	NotifyController.Notified:fire(name, cleanArgs, toastKind)
	local route = routeFor(name)
	if route then
		local ok, err = pcall(function(): any
			route.handler(name, cleanArgs, toastKind)
			return nil
		end)
		if not ok then
			log:error(`route {route.prefix} failed:`, err)
		end
		return
	end
	local sound = TOAST_SOUNDS[name]
	if NotifyFormat.isHeldBack(name) and holding() then
		held = NotifyFormat.pushHeld(held, text, HELD_MAX)
		heldKind = toastKind
		heldSound = sound or heldSound
		return
	end
	toast(text, toastKind, sound)
end

-- Public -------------------------------------------------------------------------------------------------------------

-- Shows a message code exactly like a server Notify (routes and hold-back included). `args` takes any table (e.g.
-- {level = 5}); only its string and number values fill placeholders (UI/NotifyFormat).
function NotifyController.show(code: string, args: { [string]: any }?, kind: Types.NotifyKind?)
	handle(code, args, kind or "info")
end

-- Toasts a failed Result (§2.7) with its reason text; "No Coins were spent." is added only when charged == false.
-- Returns false for an ok Result (nothing shown).
function NotifyController.showResult(result: { [string]: any }, kind: Types.NotifyKind?): boolean
	if result.ok == true then
		return false
	end
	toast(NotifyFormat.resultText(result), NotifyFormat.kindOf(kind or "warn"))
	return true
end

-- Routes every code starting with `prefix` (e.g. "grip.") to `handler` instead of a toast. The longest matching
-- prefix wins. Returns a function that removes the route.
function NotifyController.route(prefix: string, handler: Handler): () -> ()
	assert(type(prefix) == "string" and prefix ~= "", "[SD][Notify] route needs a prefix")
	assert(type(handler) == "function", "[SD][Notify] route needs a handler")
	local entry: Route = { prefix = prefix, handler = handler }
	table.insert(routes, entry)
	return function()
		local index = table.find(routes, entry)
		if index then
			table.remove(routes, index)
		end
	end
end

-- How many held-back texts wait for the end of the match (debug).
function NotifyController.heldCount(): number
	return #held
end

-- Keeps holding the held-back codes (as during the lobby lock) until the returned release() is called, e.g. while the
-- duel result card shows. Once the lock has ended and no hold is left, the held texts show as one merged toast.
function NotifyController.holdBack(key: string): () -> ()
	local token = {}
	holds[token] = key
	return function()
		if holds[token] == nil then
			return
		end
		holds[token] = nil
		if not holding() and #held > 0 then
			flushHeld()
		end
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function NotifyController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(NetController.onNotify(function(code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind)
		handle(code, args, kind)
	end))
	c:add(StateController.LobbyLockChanged:connect(function(isLocked: boolean)
		if not isLocked and next(holds) == nil and #held > 0 then
			flushHeld()
		end
	end))
	c:add(function()
		table.clear(routes)
		table.clear(holds)
		held = {}
		heldSound = nil
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function NotifyController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return NotifyController
