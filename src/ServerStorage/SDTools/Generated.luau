--!strict
-- Generated: root markers, root lookup and the undoable swap of the edit-time generators (DESIGN §1.7, §2.9).
-- Server only, Edit mode only (ServerStorage.SDTools); runtime code never requires it.
-- A generated root carries the tag SD_Generated and the attributes SD_GeneratorId (string), SD_GeneratorVersion
-- (integer >= 1) and SD_BuiltAt (UTC ISO 8601 text, readable in the Properties window).
-- swap() removes old roots with `Parent = nil` (undoable from the command bar; one undo step under MCP), never
-- :Destroy(). Untagged instances, and roots of another generator, are never touched: swap() refuses them before
-- changing anything, and rolls back if a change fails half way.
-- Also holds the build contract every builder follows (BuildContext, BuildResult).
-- No requires: the unit test clones this one module.

local CollectionService = game:GetService("CollectionService")

-- Types

-- What Main hands a builder. `scratch` is a Util/Cleanup that Main cleans after the build: temporary inputs go in
-- it, and so does the new root until the swap has parented it.
export type BuildContext = {
	scratch: any,
	Shared: Instance,
}

-- What a builder returns. `root` is the new, marked, UNPARENTED tree when ok; `error` says why when not.
export type BuildResult = {
	ok: boolean,
	root: Instance?,
	warnings: { string },
	error: string?,
}

export type RootInfo = {
	generatorId: string,
	version: number,
	builtAt: string,
}

-- Constants

local TAG = "SD_Generated"
local ATTR_ID = "SD_GeneratorId"
local ATTR_VERSION = "SD_GeneratorVersion"
local ATTR_BUILT_AT = "SD_BuiltAt"
local ID_PATTERN = "^[a-z_]+$"
local MAX_ID_LENGTH = 24
local MAX_VERSION = 2 ^ 31 - 1

-- Module table

local Generated = {}
Generated.TAG = TAG
Generated.ATTR_ID = ATTR_ID
Generated.ATTR_VERSION = ATTR_VERSION
Generated.ATTR_BUILT_AT = ATTR_BUILT_AT

-- Private

local function isValidId(value: unknown): boolean
	return type(value) == "string" and #value <= MAX_ID_LENGTH and string.match(value, ID_PATTERN) ~= nil
end

local function isValidVersion(value: unknown): boolean
	return type(value) == "number" and value >= 1 and value <= MAX_VERSION and value == math.floor(value)
end

local function describe(instance: Instance): string
	return if instance.Parent == nil then instance.Name .. " (unparented)" else instance:GetFullName()
end

-- Public

-- The marker of a generated root, or nil when `instance` is not one (untagged, or tagged with invalid attributes).
function Generated.info(instance: Instance): RootInfo?
	if not instance:HasTag(TAG) then
		return nil
	end
	local id = instance:GetAttribute(ATTR_ID)
	local version = instance:GetAttribute(ATTR_VERSION)
	if type(id) ~= "string" or not isValidId(id) or type(version) ~= "number" or not isValidVersion(version) then
		return nil
	end
	local builtAt = instance:GetAttribute(ATTR_BUILT_AT)
	return {
		generatorId = id,
		version = version,
		builtAt = if type(builtAt) == "string" then builtAt else "",
	}
end

-- True when `instance` is a generated root of `generatorId`.
function Generated.isRoot(instance: Instance, generatorId: string): boolean
	local info = Generated.info(instance)
	return info ~= nil and info.generatorId == generatorId
end

-- Marks `root` as the root of a generated tree. `builtAt` defaults to now (UTC ISO 8601). Returns `root`.
-- Errors on an invalid id (lower-case letters and "_", at most 24) or version (integer >= 1) without changing root.
function Generated.mark(root: Instance, generatorId: string, version: number, builtAt: string?): Instance
	if typeof(root) ~= "Instance" then
		error("Generated.mark: root must be an Instance", 2)
	end
	if not isValidId(generatorId) then
		error(string.format("Generated.mark: invalid generator id %s", tostring(generatorId)), 2)
	end
	if not isValidVersion(version) then
		error(string.format("Generated.mark: invalid version %s (integer >= 1)", tostring(version)), 2)
	end
	if builtAt ~= nil and type(builtAt) ~= "string" then
		error("Generated.mark: builtAt must be a string", 2)
	end
	root:AddTag(TAG)
	root:SetAttribute(ATTR_ID, generatorId)
	root:SetAttribute(ATTR_VERSION, version)
	root:SetAttribute(ATTR_BUILT_AT, builtAt or DateTime.now():ToIsoDate())
	return root
end

-- The generated roots of `generatorId`, sorted by full name. Without `scope`: every root in the place (instances
-- outside the DataModel, such as a new unparented tree, are never returned). With `scope`: the roots among the
-- descendants of `scope` (used by tests on in-memory folders). A root inside another root of the same generator
-- is left out: removing the outer one removes it too.
function Generated.findRoots(generatorId: string, scope: Instance?): { Instance }
	if not isValidId(generatorId) then
		error(string.format("Generated.findRoots: invalid generator id %s", tostring(generatorId)), 2)
	end
	local candidates: { Instance } = if scope then scope:GetDescendants() else CollectionService:GetTagged(TAG)
	local found: { [Instance]: boolean } = {}
	for _, instance in candidates do
		if Generated.isRoot(instance, generatorId) and (scope ~= nil or instance:IsDescendantOf(game)) then
			found[instance] = true
		end
	end
	local roots: { Instance } = {}
	for instance in found do
		local nested = false
		local ancestor = instance.Parent
		while ancestor do
			if found[ancestor] then
				nested = true
				break
			end
			ancestor = ancestor.Parent
		end
		if not nested then
			table.insert(roots, instance)
		end
	end
	table.sort(roots, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return roots
end

-- Replaces `oldRoots` with `newRoot`: every old root gets `Parent = nil` (undoable; it is not destroyed), then
-- `newRoot` is parented to `parent`. Returns how many old roots were removed from a parent.
-- Refuses (errors, nothing changed) when: newRoot is not marked or is already parented; an old root is not a
-- generated root of newRoot's generator (untagged instances are never touched); `parent` is inside a root.
-- `newRoot` appearing in `oldRoots` is skipped. If a change fails half way, the earlier changes are rolled back.
function Generated.swap(oldRoots: { Instance }, newRoot: Instance, parent: Instance): number
	local info = Generated.info(newRoot)
	if info == nil then
		error("Generated.swap: the new root is not marked (call Generated.mark first)", 2)
	end
	if newRoot.Parent ~= nil then
		error("Generated.swap: the new root must be built unparented", 2)
	end
	if parent == newRoot or parent:IsDescendantOf(newRoot) then
		error("Generated.swap: parent is inside the new root", 2)
	end

	local toRemove: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, old in oldRoots do
		if old == newRoot or seen[old] then
			continue
		end
		seen[old] = true
		if not Generated.isRoot(old, info.generatorId) then
			error(
				string.format(
					"Generated.swap: %s is not a generated root of %q; it was left untouched",
					describe(old),
					info.generatorId
				),
				2
			)
		end
		if parent == old or parent:IsDescendantOf(old) then
			error(string.format("Generated.swap: parent is inside the old root %s", describe(old)), 2)
		end
		if old.Parent ~= nil then
			table.insert(toRemove, old)
		end
	end

	local previousParents: { Instance } = {}
	local applied = 0
	local ok, err = pcall(function()
		for index, old in toRemove do
			previousParents[index] = old.Parent :: Instance
			old.Parent = nil
			applied = index
		end
		newRoot.Parent = parent
	end)
	if not ok then
		pcall(function()
			newRoot.Parent = nil
		end)
		for index = applied, 1, -1 do
			pcall(function()
				toRemove[index].Parent = previousParents[index]
			end)
		end
		error("Generated.swap: failed and was rolled back: " .. tostring(err), 2)
	end
	return #toRemove
end

return Generated
