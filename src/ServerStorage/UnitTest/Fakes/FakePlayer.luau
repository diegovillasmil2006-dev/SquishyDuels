--!strict
-- FakePlayer: a plain-table stand-in for a Player in service unit tests. Server only (ServerStorage.UnitTest; never
-- required at runtime). Tests run in Edit mode with no real players, so services take whatever player value they are
-- given and read only these members:
--   UserId, Name, DisplayName       (Name defaults to "Tester<userId>", DisplayName to Name)
--   Parent                          the Players service while "in game"; set it to nil to simulate a player who left
--   :GetAttribute(name)             -> the value set with SetAttribute (nil when unset)
--   :SetAttribute(name, value)      stores a value (nil removes it); the server-written SD_* attributes in tests
--   :GetAttributes()                -> a copy of every attribute
--   :IsA(className)                 -> true for "Player" and "Instance"
-- There is no GetAttributeChangedSignal (and no other Instance API): code that needs signals takes them injected.
--   local p = FakePlayer.new(42, "Ana")
--   p:SetAttribute("SD_DuelPhase", "Active")

-- Types

export type FakePlayer = {
	UserId: number,
	Name: string,
	DisplayName: string,
	Parent: any,
	GetAttribute: (self: FakePlayer, name: string) -> any,
	SetAttribute: (self: FakePlayer, name: string, value: any) -> (),
	GetAttributes: (self: FakePlayer) -> { [string]: any },
	IsA: (self: FakePlayer, className: string) -> boolean,
}

-- Constants

local CLASSES = { Player = true, Instance = true }

-- Module table

local FakePlayer = {}

-- Public

function FakePlayer.new(userId: number, name: string?): FakePlayer
	assert(type(userId) == "number" and userId == math.floor(userId), "FakePlayer.new: userId must be a whole number")
	local playerName = if name ~= nil then name else `Tester{userId}`
	local attributes: { [string]: any } = {}
	local player: FakePlayer = {
		UserId = userId,
		Name = playerName,
		DisplayName = playerName,
		Parent = game:GetService("Players"),
		GetAttribute = function(_self: FakePlayer, attributeName: string): any
			return attributes[attributeName]
		end,
		SetAttribute = function(_self: FakePlayer, attributeName: string, value: any)
			attributes[attributeName] = value
		end,
		GetAttributes = function(_self: FakePlayer): { [string]: any }
			return table.clone(attributes)
		end,
		IsA = function(_self: FakePlayer, className: string): boolean
			return CLASSES[className] == true
		end,
	}
	return player
end

return FakePlayer
