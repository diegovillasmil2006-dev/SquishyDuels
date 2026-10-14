--!strict
-- InventoryService (server only). DESIGN §2.3, §2.8 (EquipSquishy), §2.9 (SD_Equipped), §3.3, §3.13, §6.5, §12 #4, #6.
-- Owned squishies and the equipped one. Ownership itself is changed only by EconomyService (§2.3); this module reads
-- it, equips, and writes the replicated Player attribute SD_Equipped (server only) that every client uses for the held
-- squishy (§9.5).
-- * The free starter (Catalog.starterId(), "kitty_bread") is always owned (§3.3), and is what a player holds until
--   the profile loads, and whenever the saved choice is not owned or not in the Catalog (the fallback).
-- * getEquipped(p) never yields and never fails: CombatService, AbilityService, SqueezeService and DuelService read it
--   (DuelService snapshots it at Preparing; a match never reads it again).
-- * equip(p, id) / EquipSquishy (RF, §2.8) checks, in order: a Catalog id (net.invalid); not in a match or matched
--   (inventory.lockedInDuel: SD_MatchId or SD_DuelPhase set, which DuelService sets at the start of Preparing, the
--   moment the queue says Matched, §5.4); a profile (data.notReady while loading); owned (inventory.notOwned). An
--   OFFLINE / READONLY session (§3.13 "equip the starter") may equip only the starter (data.offline / data.readOnly
--   for anything else); its profile is an in-memory view DataService never saves (§3.9), so the choice is written
--   there directly. A READY session changes through DataService.mutate (the data port) and asks for a "soon" save.
--   Success sets profile.equipped and SD_Equipped, marks the state field and fires Equipped(p, id, oldId).
-- * Loaded / status changes: the profile's choice (sanitized) becomes SD_Equipped; a ready profile whose choice is not
--   owned or unknown is corrected to the starter (§3.3).
-- * Duplicate policy hooks (§6.5): isDuplicate(p, id) and duplicateRefund(boxId) for the box flow (Part 7; a refund
--   is a share of the box price since spec 2026-10-12 §8); the policy itself is EconomyService.duplicateRefund (the one
--   writer of Coins and ownership).
-- Collaborators are reached through `deps` (useDeps in tests; the defaults use StateService.dataPort()). A player who
-- left is never tracked again (a late StatusChanged, e.g. from a failed final save, would otherwise leave an entry).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local EconomyService = require(script.Parent.EconomyService)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)

-- Types

export type Deps = {
	data: StateService.DataPort,
	markDirty: (player: any, field: string) -> (),
}

-- Constants

local ATTR_EQUIPPED = "SD_Equipped"
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_PHASE = "SD_DuelPhase"
local REMOTE_EQUIP = "EquipSquishy"
local STATUS_READY = "ready"
local STATUS_OFFLINE = "offline"
local STATUS_READONLY = "readonly"
local SAVE_SOON = "soon"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_OFFLINE = "data.offline"
local CODE_READ_ONLY = "data.readOnly"
local CODE_NOT_OWNED = "inventory.notOwned"
local CODE_LOCKED = "inventory.lockedInDuel"

-- Module table

local InventoryService = {}

-- (player, squishyId, previousId) after every successful equip that changed the choice.
InventoryService.Equipped = Signal.new() :: Signal.Signal<Player, string, string>

-- Private

local log = Log.new("Inventory")
local deps: Deps? = nil
-- Player -> equipped squishy id this session (mirrors profile.equipped; the starter until the profile loads).
local equippedByPlayer: { [any]: string } = {}
local departed: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
	}
end

local function getDeps(): Deps
	local current = deps
	if current then
		return current
	end
	local created = defaultDeps()
	deps = created
	return created
end

local function setAttribute(player: any, id: string)
	if typeof(player) == "Instance" then
		player:SetAttribute(ATTR_EQUIPPED, id)
	end
end

local function attribute(player: any, name: string): any
	if typeof(player) == "Instance" then
		return player:GetAttribute(name)
	end
	return nil
end

local function ownsIn(profile: any, id: string): boolean
	if id == Catalog.starterId() then
		return true
	end
	if type(profile) ~= "table" or type(profile.owned) ~= "table" then
		return false
	end
	return profile.owned[id] ~= nil
end

-- The profile's choice when it is a Catalog id the profile owns, else the starter (§3.3 fallback).
local function sanitizedChoice(profile: any): string
	local id = if type(profile) == "table" then profile.equipped else nil
	if type(id) == "string" and Catalog.isValidId(id) and ownsIn(profile, id) then
		return id
	end
	return Catalog.starterId()
end

local function apply(player: any, id: string)
	equippedByPlayer[player] = id
	setAttribute(player, id)
end

-- Writes profile.equipped: through mutate for a READY session (saved later), directly on the never-saved in-memory
-- view of an OFFLINE / READONLY one. Returns true when the profile now holds `id`.
local function writeChoice(player: any, status: string, id: string): boolean
	local data = getDeps().data
	if status == STATUS_READY then
		return (data.mutate(player, function(profile: any): any
			profile.equipped = id
			return nil
		end))
	end
	local profile = data.getProfile(player)
	if type(profile) == "table" then
		profile.equipped = id
		return true
	end
	return false
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- True while the player is matched or in a match (Matched through Returning, §5.4), from the server-written
-- attributes.
function InventoryService.isLocked(player: any): boolean
	local matchId, phase = attribute(player, ATTR_MATCH_ID), attribute(player, ATTR_PHASE)
	return (type(matchId) == "string" and matchId ~= "") or (type(phase) == "string" and phase ~= "")
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Uses these collaborators (nil = the real ones) and forgets every session (tests).
function InventoryService.useDeps(newDeps: Deps?)
	deps = newDeps
	equippedByPlayer = {}
	departed = setmetatable({}, { __mode = "k" }) :: any
end

-- True when the player owns the squishy (the starter always). Unknown ids are never owned.
function InventoryService.owns(player: any, id: unknown): boolean
	if type(id) ~= "string" or not Catalog.isValidId(id) then
		return false
	end
	return ownsIn(getDeps().data.getProfile(player), id)
end

-- The owned Catalog ids in Catalog order (the starter always first among them; ids missing from the Catalog are
-- kept in the profile but ignored, §3.3).
function InventoryService.ownedIds(player: any): { string }
	local profile = getDeps().data.getProfile(player)
	local list: { string } = {}
	for _, def in Catalog.list() do
		if ownsIn(profile, def.id) then
			table.insert(list, def.id)
		end
	end
	return list
end

-- The squishy the player holds now: the session's choice, else the starter. Never yields.
function InventoryService.getEquipped(player: any): string
	return equippedByPlayer[player] or Catalog.starterId()
end

-- §6.5 hooks for the box flow: is this squishy a duplicate for the player, and what does a duplicate from that box
-- refund.
function InventoryService.isDuplicate(player: any, id: string): boolean
	return InventoryService.owns(player, id)
end

function InventoryService.duplicateRefund(boxId: string): number
	return EconomyService.duplicateRefund(boxId)
end

-- Equips `id` (EquipSquishy, §2.8: Result<nil>). Returns NetService.ok() or NetService.err(code). Never yields.
function InventoryService.equip(player: any, id: unknown): any
	if type(id) ~= "string" or not Catalog.isValidId(id) then
		return NetService.err(CODE_INVALID)
	end
	if InventoryService.isLocked(player) then
		return NetService.err(CODE_LOCKED)
	end
	local d = getDeps()
	local status = d.data.status(player)
	local profile = d.data.getProfile(player)
	if status == STATUS_OFFLINE or status == STATUS_READONLY then
		if id ~= Catalog.starterId() then
			return NetService.err(if status == STATUS_OFFLINE then CODE_OFFLINE else CODE_READ_ONLY)
		end
	elseif status ~= STATUS_READY or profile == nil then
		return NetService.err(CODE_NOT_READY)
	elseif not ownsIn(profile, id) then
		return NetService.err(CODE_NOT_OWNED)
	end
	local previous = InventoryService.getEquipped(player)
	if not writeChoice(player, status, id) and status == STATUS_READY then
		return NetService.err(CODE_NOT_READY) -- the session stopped taking changes (it is being released)
	end
	apply(player, id)
	if previous ~= id then
		d.markDirty(player, "equipped")
		if status == STATUS_READY then
			d.data.requestSave(player, SAVE_SOON)
		end
		InventoryService.Equipped:fire(player, id, previous)
	end
	return NetService.ok()
end

-- Applies the profile's (sanitized) choice to SD_Equipped; the starter without a profile. Called on Loaded and on
-- status changes (an OFFLINE session that loaded later, §3.13).
function InventoryService.refresh(player: any)
	if departed[player] then
		return
	end
	local data = getDeps().data
	local profile = data.getProfile(player)
	if profile == nil then
		if equippedByPlayer[player] == nil then
			apply(player, Catalog.starterId())
		end
		return
	end
	local id = sanitizedChoice(profile)
	if profile.equipped ~= id then
		log:info(`equipped {tostring(profile.equipped)} is not owned or unknown; using {id}`)
		if writeChoice(player, data.status(player), id) then
			getDeps().markDirty(player, "equipped")
		end
	end
	apply(player, id)
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function InventoryService.init()
	NetService.onInvoke(REMOTE_EQUIP, function(player: Player, id: string): any
		return InventoryService.equip(player, id)
	end)
	local data = getDeps().data
	data.onLoaded(InventoryService.refresh)
	data.onStatusChanged(InventoryService.refresh)
end

-- Joins: the starter (or an already loaded profile's choice) at once. Never yields (§2.6 rule 5).
function InventoryService.playerAdded(player: Player)
	departed[player] = nil
	InventoryService.refresh(player)
end

function InventoryService.playerRemoving(player: Player)
	equippedByPlayer[player] = nil
	departed[player] = true
end

-- Not called by the bootstrap; used by leak checks.
function InventoryService.destroy()
	equippedByPlayer = {}
	InventoryService.Equipped:disconnectAll()
end

return InventoryService
