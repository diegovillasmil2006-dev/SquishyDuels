--!strict
-- ModalStack (client only, pure). DESIGN §11.1, §10.3: the order of the open modal screens for UIController.
-- At most `max` modals are open at once (Config.UI.modalStackMax = 2, e.g. Inspect over Squishies, Shop or Boxes).
--   push(name, closesWhenCovered?)
--                 opens `name` on top. Already in the stack: everything above it closes and it becomes the top.
--                 A full stack first closes its top (the newest), so the opener underneath stays (Inspect over Shop,
--                 then Boxes: Inspect closes, Boxes goes over Shop). Part 6 (DESIGN §10.10 "another top-level screen
--                 opening" closes Inspect): a top for which closesWhenCovered(top) is true closes first too, so nothing
--                 ever opens over it (Inspect alone, then Shop: Inspect closes, Shop opens alone). Returns the names
--                 that must close, top first.
--   remove(name)  takes `name` out and returns the names above it (they close too, top first), plus `name`.
--   ModalStack.backTarget(handlerOrder?, topOrder?)
--                 what Back answers (Part 6 review): "handler" (the newest UIController.pushBack handler) when it came
--                 after the top modal opened, "modal" (close the top modal) when that modal is the newer layer, "none"
--                 when there is neither. The orders are one increasing counter shared by pushBack and modal opens.
-- No instances: unit-tested in Edit mode.

-- Types

export type BackTarget = "handler" | "modal" | "none"

export type ModalStack = {
	push: (self: ModalStack, name: string, closesWhenCovered: ((name: string) -> boolean)?) -> { string },
	remove: (self: ModalStack, name: string) -> { string },
	top: (self: ModalStack) -> string?,
	contains: (self: ModalStack, name: string) -> boolean,
	list: (self: ModalStack) -> { string },
	size: (self: ModalStack) -> number,
}

type Data = {
	_max: number,
	_names: { string },
}

-- Module tables

local StackClass = {}
StackClass.__index = StackClass

local ModalStack = {}

-- Private

-- Pops everything above index `keep` (exclusive), newest first.
local function popAbove(self: Data, keep: number): { string }
	local closed = {}
	for i = #self._names, keep + 1, -1 do
		table.insert(closed, self._names[i])
		self._names[i] = nil
	end
	return closed
end

-- Methods

function StackClass.push(self: Data, name: string, closesWhenCovered: ((name: string) -> boolean)?): { string }
	local index = table.find(self._names, name)
	if index then
		return popAbove(self, index)
	end
	local closed = {}
	if closesWhenCovered then
		while #self._names > 0 and closesWhenCovered(self._names[#self._names]) do
			table.insert(closed, table.remove(self._names) :: string)
		end
	end
	while #self._names >= self._max do
		table.insert(closed, table.remove(self._names) :: string)
	end
	table.insert(self._names, name)
	return closed
end

function StackClass.remove(self: Data, name: string): { string }
	local index = table.find(self._names, name)
	if index == nil then
		return {}
	end
	return popAbove(self, index - 1)
end

function StackClass.top(self: Data): string?
	return self._names[#self._names]
end

function StackClass.contains(self: Data, name: string): boolean
	return table.find(self._names, name) ~= nil
end

-- Bottom first.
function StackClass.list(self: Data): { string }
	return table.clone(self._names)
end

function StackClass.size(self: Data): number
	return #self._names
end

-- Public

function ModalStack.new(max: number): ModalStack
	assert(type(max) == "number" and max >= 1, "[SD][ModalStack] max must be >= 1")
	local data: Data = { _max = math.floor(max), _names = {} }
	return setmetatable(data, StackClass) :: any
end

-- What Back answers: the newest back handler (opened at `handlerOrder`) or the top modal (opened at `topOrder`),
-- whichever is the newer layer; nil means there is none of that kind.
function ModalStack.backTarget(handlerOrder: number?, topOrder: number?): BackTarget
	if handlerOrder ~= nil and (topOrder == nil or handlerOrder > topOrder) then
		return "handler"
	end
	return if topOrder ~= nil then "modal" else "none"
end

return ModalStack
