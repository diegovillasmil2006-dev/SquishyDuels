--!strict
-- HighwayController (client only). Access2 (owner 2026-10-18 "Both": a bridge to walk to the highway's launch deck,
-- plus a quick button): the HUD's HIGHWAY stand-in (HudFormat.NAV "highway", under Settings; not on phones until
-- Diego places it) opens the non-modal "highway" screen registered here, which sends GoHighway() once at a time
-- (NetController keeps Config.Net's limit too); the server (HighwayAccessService) moves the character onto a free
-- point of the deck (the bridge's walk beside it when the deck is full). An accepted trip shows
-- nothing (the camera follows the character); a refusal shows the server's reason alone as a toast (no Coins are ever
-- involved, so never "No Coins were spent"). In a duel UIController refuses the open (lobbyOnly) and the HUD hides.
-- Public: goAsync() -> boolean, init(), start(), destroy(), useDeps(overrides?) (tests).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Strings = require(ReplicatedStorage.Shared.Strings)
local NetController = require(script.Parent.NetController)
local UIController = require(script.Parent.UIController)

-- Types

type Deps = {
	invoke: (name: string) -> any, -- NetController.invokeAsync (never throws)
	toast: (text: string, kind: string) -> (), -- UIController.toast
}

-- Constants

local SCREEN = "highway" -- HudFormat.NAV's highway item opens it
local REMOTE = "GoHighway"
local GENERIC = "error.generic"
local TOAST_KIND = "warn"

-- Module table

local HighwayController = {}

-- Private

local function defaultDeps(): Deps
	return {
		invoke = function(name: string): any
			return NetController.invokeAsync(name)
		end,
		toast = function(text: string, kind: string)
			UIController.toast(text, kind :: any)
		end,
	}
end

local deps: Deps = defaultDeps()
local pending = false
local unregister: (() -> ())? = nil

-- Public

-- Sends GoHighway() unless one is in flight; true when the server took the trip.
function HighwayController.goAsync(): boolean
	if pending then
		return false
	end
	pending = true
	local reply = deps.invoke(REMOTE)
	pending = false
	if type(reply) == "table" and reply.ok == true then
		return true
	end
	local reason = if type(reply) == "table" then reply.reason else nil
	deps.toast(Strings.reasonText(if type(reason) == "string" and reason ~= "" then reason else GENERIC), TOAST_KIND)
	return false
end

-- Replaces dependencies (fields not given keep their defaults); nil restores every default.
function HighwayController.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	pending = false
end

-- Lifecycle

function HighwayController.init()
	if unregister then
		return
	end
	unregister = UIController.registerScreen(SCREEN, {
		modal = false,
		onOpen = function()
			HighwayController.goAsync()
		end,
	})
end

function HighwayController.start() end

-- Not called by the bootstrap (the client lives for the session); used by tests.
function HighwayController.destroy()
	local remove = unregister
	unregister = nil
	if remove then
		remove()
	end
end

return HighwayController
