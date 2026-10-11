--!strict
-- KeyText (client only). DESIGN §2.11 (no player-facing literals outside Strings), §11.1. Text by Strings key for
-- screens that name a key at run time (a key built from data, or one a later contracts change adds):
--   KeyText.get("settings.title")                     -> the text, formatted with args when given
--   KeyText.has("common.on")                          -> whether the key exists
--   KeyText.plural("inventory.x", n, args)             -> a { one, many } pair picked by n, then formatted
-- A missing key returns the key itself (so the gap is visible in a test play, never a blank label) and warns once
-- per key. Pure apart from that one warning.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

-- Module table

local KeyText = {}

-- Private

local log = Log.new("Text")
local warned: { [string]: boolean } = {}

local function missing(key: string): string
	if not warned[key] then
		warned[key] = true
		log:warn(`missing Strings key {key}`)
	end
	return key
end

local function node(key: string): any
	local current: any = Strings
	for segment in string.gmatch(key, "[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end
		current = current[segment]
	end
	return current
end

-- Public

function KeyText.has(key: string): boolean
	return Strings.resolve(key) ~= nil
end

function KeyText.get(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	if template == nil then
		return missing(key)
	end
	return Strings.format(template, args)
end

-- A count text stored as { one = ..., many = ... }; `n` picks the form and is also passed as {n} unless args has it.
function KeyText.plural(key: string, n: number, args: { [string]: any }?): string
	local pair = node(key)
	if type(pair) ~= "table" or type(pair.one) ~= "string" or type(pair.many) ~= "string" then
		return missing(key)
	end
	local values: { [string]: any } = if args then table.clone(args) else {}
	if values.n == nil then
		values.n = n
	end
	return Strings.format(Strings.plural(n, pair.one, pair.many), values)
end

return KeyText
