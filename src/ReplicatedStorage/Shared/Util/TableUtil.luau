--!strict
-- TableUtil (shared). Helpers for plain data tables (no metatables, no cycles): profiles, Config, Strings.

-- Module table

local TableUtil = {}

-- Public

-- Deep copy of tables (keys are reused, values copied). Metatables and frozen state are not copied.
function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: { [any]: any } do
		copy[key] = TableUtil.deepCopy(item)
	end
	return copy :: any
end

-- Freezes value and every table inside it (table.freeze), then returns value.
-- A table that is already frozen is treated as fully frozen and not entered (this also stops cycles).
function TableUtil.deepFreeze<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local t = value :: { [any]: any }
	if not table.isfrozen(t) then
		table.freeze(t)
	end
	for _, item in t do
		if type(item) == "table" and not table.isfrozen(item) then
			TableUtil.deepFreeze(item)
		end
	end
	return value
end

-- Fills missing string-keyed fields of target from template, recursively, and returns target (mutated).
-- Filled values are deep copies, so target never shares tables with template. Fields already present in
-- target (even with another type) and fields unknown to template are kept unchanged.
-- Only string keys are filled, so array contents (e.g. lists in defaults) are never merged into target.
function TableUtil.reconcile<T>(target: T, template: { [any]: any }): T
	local t = target :: any
	for key, default in template do
		if type(key) == "string" then
			local current = t[key]
			if current == nil then
				t[key] = TableUtil.deepCopy(default)
			elseif type(current) == "table" and type(default) == "table" then
				TableUtil.reconcile(current, default)
			end
		end
	end
	return target
end

return TableUtil
