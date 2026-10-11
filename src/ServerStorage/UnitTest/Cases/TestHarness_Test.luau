--!strict
-- TestHarness_Test: unit tests for ServerScriptService.Server.Studio.TestHarness (the dummy adapter only).
-- Server only (ServerStorage.UnitTest). Edit mode: no dummy is spawned (that needs Play, the avatar service and the
-- Workspace attribute SD_TestScenario); the adapter is built around an unparented rig and an unparented folder, so
-- nothing is parented into the place.
-- Contract (DESIGN §12 #21, §13.4 T2): the dummy is a Player-shaped table that is never a Player instance:
--   * kind "testDummy" + isTestDummy (what DuelService, CombatService, DuelRewards and Matchmaker look for);
--   * a negative userId, unique per dummy, equal to UserId;
--   * labelled with Strings.duel.testDummy ("TEST DUMMY (Studio)");
--   * Parent is its folder, never Players (no `Parent == Players` check can take it for a real player);
--   * the starter squishy; attributes round-trip; getRoot() is nil while the rig is outside the Workspace;
--   * the matchmaker drops it from the queue order (never in the real queue).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local TestHarness = t.requireServer("Studio/TestHarness")
	local Matchmaker = t.requireServer("Logic/Matchmaker")
	local Catalog = t.requireShared("Catalog")
	local Strings = t.requireShared("Strings")
	local Players = game:GetService("Players")

	-- An unparented rig with a root part and a Humanoid, plus an unparented folder for the dummy's Parent.
	local function makeRig(): (Model, Folder)
		local rig = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = rig
		rig.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = rig
		local folder = Instance.new("Folder")
		return rig, folder
	end

	t.test("the adapter is flagged, labelled and never a Player", function()
		local rig, folder = makeRig()
		local dummy = TestHarness.newDummy(rig, folder)
		expect.equal(dummy.kind, "testDummy")
		expect.equal(dummy.isTestDummy, true)
		expect.truthy(TestHarness.isDummy(dummy))
		expect.equal(dummy.Name, Strings.duel.testDummy)
		expect.equal(dummy.DisplayName, Strings.duel.testDummy)
		expect.equal(dummy.displayName, Strings.duel.testDummy)
		expect.truthy(typeof(dummy) ~= "Instance")
		expect.falsy(dummy:IsA("Player"))
		expect.equal(dummy.Parent, folder)
		expect.truthy(dummy.Parent ~= Players)
		expect.equal(dummy.Character, rig)
		expect.equal(dummy.squishyId, Catalog.starterId())
		expect.equal(dummy:GetNetworkPing(), 0)
		dummy:RequestStreamAroundAsync(Vector3.zero, 1) -- a no-op that must not throw
		local connection = dummy.CharacterAdded:Connect(function() end)
		connection:Disconnect()
		expect.falsy(connection.Connected)
		rig:Destroy()
		folder:Destroy()
	end)

	t.test("userIds are negative, unique and match UserId", function()
		local rigA, folderA = makeRig()
		local rigB, folderB = makeRig()
		local a = TestHarness.newDummy(rigA, folderA)
		local b = TestHarness.newDummy(rigB, folderB)
		expect.truthy(a.userId < 0)
		expect.truthy(b.userId < 0)
		expect.truthy(a.userId ~= b.userId)
		expect.equal(a.UserId, a.userId)
		expect.equal(b.UserId, b.userId)
		for _, instance in { rigA, folderA, rigB, folderB } :: { Instance } do
			instance:Destroy()
		end
	end)

	t.test("attributes round-trip; getRoot() is nil outside the Workspace", function()
		local rig, folder = makeRig()
		local dummy = TestHarness.newDummy(rig, folder)
		expect.equal(dummy:GetAttribute("SD_DuelPhase"), nil)
		dummy:SetAttribute("SD_DuelPhase", "Active")
		dummy:SetAttribute("SD_MatchId", "m-1")
		expect.equal(dummy:GetAttribute("SD_DuelPhase"), "Active")
		expect.equal(dummy:GetAttribute("SD_MatchId"), "m-1")
		expect.equal(dummy:getRoot(), nil)
		rig:Destroy()
		folder:Destroy()
	end)

	t.test("isDummy refuses look-alikes; the matchmaker drops the dummy from the queue order", function()
		expect.falsy(TestHarness.isDummy({ isTestDummy = true }))
		expect.falsy(TestHarness.isDummy({ kind = "testDummy" }))
		expect.falsy(TestHarness.isDummy(nil))
		local rig, folder = makeRig()
		local dummy = TestHarness.newDummy(rig, folder)
		local entry = Matchmaker.newEntry(dummy, 0)
		expect.equal(entry.isTestDummy, true)
		local real = Matchmaker.newEntry({ userId = 1 }, 1)
		local ordered = Matchmaker.order({ entry, real })
		expect.equal(#ordered, 1)
		expect.equal(ordered[1].userId, 1)
		rig:Destroy()
		folder:Destroy()
	end)
end
