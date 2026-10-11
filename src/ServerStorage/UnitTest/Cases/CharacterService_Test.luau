--!strict
-- CharacterService_Test: unit tests for ServerScriptService.Server.Services.CharacterService.
-- Server only (ServerStorage.UnitTest). Edit mode: no real players, so a fake player table stands in where only
-- `Character` / `Parent` are read; nothing is parented to the place and init() is never called.
-- Contract (DESIGN §2.3, §5.3):
--   * every BasePart of a character (nested ones too) goes into the characters' collision group, and parts added later
--     follow through the watcher; non-parts are untouched;
--   * getRoot / getHumanoid / isAlive answer nil / false without a character in the Workspace;
--   * teleportAsync refuses without a character, without yielding;
--   * Died is a signal.
-- The group name used is SD_Characters when this place has it registered (it is registered at runtime by
-- WorldService), else Default: an unregistered name is never written (the same rule as the SquishyBuilder).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

local PhysicsService = game:GetService("PhysicsService")

return function(t: Context)
	local expect = t.expect
	local CharacterService = t.requireServer("Services/CharacterService")
	local GROUP = if PhysicsService:IsCollisionGroupRegistered("SD_Characters") then "SD_Characters" else "Default"

	local function fakeCharacter(): (Model, { BasePart })
		local character = Instance.new("Model")
		character.Name = "FakeCharacter"
		local parts: { BasePart } = {}
		for _, name in { "HumanoidRootPart", "UpperTorso", "LeftFoot", "RightFoot" } do
			local part = Instance.new("Part")
			part.Name = name
			part.Parent = character
			table.insert(parts, part)
		end
		local accessory = Instance.new("Accessory")
		accessory.Parent = character
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Parent = accessory
		table.insert(parts, handle)
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		return character, parts
	end

	t.test("applyCollisionGroup puts every BasePart (nested too) in the group", function()
		local character, parts = fakeCharacter()
		local count = CharacterService.applyCollisionGroup(character, GROUP)
		expect.equal(count, #parts)
		for _, part in parts do
			expect.equal(part.CollisionGroup, GROUP)
		end
		character:Destroy()
	end)

	t.test("watchCollisionGroup also covers parts added later", function()
		local character = fakeCharacter()
		local connection = CharacterService.watchCollisionGroup(character, GROUP)
		local late = Instance.new("Part")
		late.Name = "LateAccessoryHandle"
		late.Parent = character
		task.wait() -- deferred events
		expect.equal(late.CollisionGroup, GROUP)
		connection:Disconnect()
		character:Destroy()
	end)

	t.test("no character in the Workspace: getRoot/getHumanoid nil, isAlive false, teleport refused", function()
		local character = fakeCharacter() -- never parented to the Workspace
		local withCharacter = { Character = character, Name = "Fake", Parent = nil } :: any
		local without = { Character = nil, Name = "Fake", Parent = nil } :: any
		for _, player in { withCharacter, without } do
			expect.equal(CharacterService.getRoot(player), nil)
			expect.equal(CharacterService.getHumanoid(player), nil)
			expect.equal(CharacterService.isAlive(player), false)
			local moved, reason = CharacterService.teleportAsync(player, CFrame.new(0, 5, 0))
			expect.equal(moved, false)
			expect.equal(reason, "noCharacter")
		end
		character:Destroy()
	end)

	t.test("Died is a signal", function()
		expect.equal(type(CharacterService.Died.connect), "function")
		expect.equal(type(CharacterService.Died.fire), "function")
	end)
end
