--!strict
-- MeshQuota (client only; no instances, connections or clock reads). DESIGN §18.3.4, §18.9: at most
-- Config.Vfx.Budgets.editableMeshes (2) editable meshes per client, shared by the jelly ripple's skin (1: the arena
-- skin or the practice backstop skin, never both) and Inspect's knead shell (1, spec phase2-squeeze §3.2: key
-- "soft"; the giant pads' 3 went with them, build plan Phase 6). A module asks for a slot before it
-- creates an EditableMesh and gives it back when that mesh is destroyed; a refused slot means path B for that key.
--
--   MeshQuota.tryAcquire(key) -> boolean   true = the key holds a slot (a key already held answers true and takes no
--                                          second slot); false = every slot is taken
--   MeshQuota.release(key)                 frees the key's slot (an unknown key does nothing)
--   MeshQuota.count() -> number            slots held now (leak checks: back to the baseline after a duel)
--   MeshQuota.holds(key) -> boolean, MeshQuota.limit() -> number, MeshQuota.keys() -> { string } (sorted)
-- The module functions use one quota shared by every module of this client, with the Config limit. MeshQuota.new(limit)
-- makes a private quota with the same methods (unit tests).
-- Keys are plain strings chosen by the owner: the ripple uses "arena" and "backstop".

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

type QuotaData = {
	_limit: number,
	_held: { [string]: boolean },
	_count: number,
}

-- Module tables

local QuotaClass = {}
QuotaClass.__index = QuotaClass

export type Quota = typeof(setmetatable({} :: QuotaData, QuotaClass))

local MeshQuota = {}

-- Quota methods

-- Takes a slot for `key` when one is free. A key that already holds a slot answers true without taking another.
function QuotaClass.tryAcquire(self: Quota, key: string): boolean
	assert(type(key) == "string" and key ~= "", "[SD][MeshQuota] key must be a non-empty string")
	if self._held[key] then
		return true
	end
	if self._count >= self._limit then
		return false
	end
	self._held[key] = true
	self._count += 1
	return true
end

-- Frees the slot of `key`; a key that holds none is ignored.
function QuotaClass.release(self: Quota, key: string)
	if self._held[key] then
		self._held[key] = nil
		self._count -= 1
	end
end

function QuotaClass.count(self: Quota): number
	return self._count
end

function QuotaClass.holds(self: Quota, key: string): boolean
	return self._held[key] == true
end

function QuotaClass.limit(self: Quota): number
	return self._limit
end

-- The keys holding a slot, sorted (debug output).
function QuotaClass.keys(self: Quota): { string }
	local list: { string } = {}
	for key in self._held do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- Public

-- A private quota of `limit` slots (an integer >= 0).
function MeshQuota.new(limit: number): Quota
	assert(type(limit) == "number" and limit >= 0 and limit % 1 == 0, "[SD][MeshQuota] limit must be an integer >= 0")
	local data: QuotaData = { _limit = limit, _held = {}, _count = 0 }
	return setmetatable(data, QuotaClass)
end

-- The client's shared quota, made on first use (no work at require time).
local sharedQuota: Quota? = nil

local function default(): Quota
	local quota = sharedQuota
	if quota == nil then
		local made = MeshQuota.new(Config.Vfx.Budgets.editableMeshes)
		sharedQuota = made
		return made
	end
	return quota
end

function MeshQuota.tryAcquire(key: string): boolean
	return default():tryAcquire(key)
end

function MeshQuota.release(key: string)
	default():release(key)
end

function MeshQuota.count(): number
	return default():count()
end

function MeshQuota.holds(key: string): boolean
	return default():holds(key)
end

function MeshQuota.limit(): number
	return default():limit()
end

function MeshQuota.keys(): { string }
	return default():keys()
end

return MeshQuota
