--!strict
-- InventoryService_Test: unit tests for ServerScriptService.Server.Services.InventoryService.
-- Server only (ServerStorage.UnitTest). Folders stand in for Players (only SetAttribute / GetAttribute are used);
-- DataService is a fake data port and StateService a recorder (useDeps).
-- Contract (DESIGN §2.3, §2.8 EquipSquishy, §2.9, §3.3, §3.13, §6.5, §12 #4, #6):
--   * on join every player holds the free starter (Catalog.starterId() = "kitty_bread") and the server writes the
--     Player attribute SD_Equipped; getEquipped(p) returns it, and the starter for a player that is not tracked (or
--     left); once the profile loads, its (owned, known) choice is held, else the starter;
--   * owns: the starter always, other ids from the profile, unknown ids never;
--   * equip: net.invalid for a non-Catalog id, inventory.lockedInDuel while matched or in a match, data.notReady while
--     loading (or once the session takes no more changes), inventory.notOwned for an unowned squishy; OFFLINE /
--     READONLY may equip only the starter (no save); success sets profile.equipped (through DataService.mutate for a
--     ready profile) and SD_Equipped, marks the state field, saves "soon", fires Equipped;
--   * duplicate hooks (§6.5): isDuplicate follows ownership, duplicateRefund(boxId) a quarter of the box price (spec
--     2026-10-12 §8);
--   * end to end through a real DataService core (memory store and FakeDataStore): the equipped choice survives a
--     release and a reload on another server (acceptance 6, §13.3).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	profiles: { [any]: any },
	statuses: { [any]: string },
	frozen: { [any]: boolean },
	dirty: { string },
	saves: { string },
	mutations: number,
}

local NOW = 1_790_000_000

return function(t: Context)
	local InventoryService = t.requireServer("Services/InventoryService")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect

	local function fakePlayer(name: string): any
		local player = Instance.new("Folder")
		player.Name = name
		return player
	end

	-- Fresh sessions and a data port with no profile until a case adds one.
	local function setup(): World
		local w: World = { profiles = {}, statuses = {}, frozen = {}, dirty = {}, saves = {}, mutations = 0 }
		InventoryService.useDeps({
			data = {
				getProfile = function(player: any): any?
					return w.profiles[player]
				end,
				status = function(player: any): string
					return w.statuses[player] or "loading"
				end,
				persisted = function(_player: any): boolean
					return true
				end,
				savePending = function(_player: any): boolean
					return false
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				-- Like DataService.mutate: READY sessions only, and none once the final leave snapshot is taken.
				mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
					if w.statuses[player] ~= "ready" or w.frozen[player] then
						return false, "data.notReady"
					end
					w.mutations += 1
					return true, fn(w.profiles[player])
				end,
				requestSave = function(_player: any, reason: string)
					table.insert(w.saves, reason)
				end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			markDirty = function(_player: any, field: string)
				table.insert(w.dirty, field)
			end,
		})
		return w
	end

	local function withProfile(w: World, player: any, status: string, owned: { string }, equipped: string?): any
		local profile = { owned = {}, equipped = equipped or Catalog.starterId() }
		for _, id in owned do
			profile.owned[id] = { at = 1, src = "box" }
		end
		w.profiles[player] = profile
		w.statuses[player] = status
		return profile
	end

	-- Join and fallback (the Part 2 contract, kept) -------------------------------------------------------------------

	t.test("the starter is kitty_bread", function()
		expect.equal(Catalog.starterId(), "kitty_bread")
	end)

	t.test("playerAdded equips the starter and writes SD_Equipped", function()
		setup()
		local player = fakePlayer("A")
		InventoryService.playerAdded(player)
		expect.equal(player:GetAttribute("SD_Equipped"), Catalog.starterId())
		expect.equal(InventoryService.getEquipped(player), Catalog.starterId())
		InventoryService.playerRemoving(player)
		player:Destroy()
	end)

	t.test("getEquipped falls back to the starter for an untracked or departed player", function()
		setup()
		local stranger = fakePlayer("B")
		expect.equal(InventoryService.getEquipped(stranger), Catalog.starterId())
		InventoryService.playerAdded(stranger)
		InventoryService.playerRemoving(stranger)
		expect.equal(InventoryService.getEquipped(stranger), Catalog.starterId())
		stranger:Destroy()
	end)

	-- Loading the profile ---------------------------------------------------------------------------------------------

	t.test("once the profile loads, its owned choice is held and replicated", function()
		local w = setup()
		local player = fakePlayer("C")
		InventoryService.playerAdded(player)
		withProfile(w, player, "ready", { "toast" }, "toast")
		InventoryService.refresh(player) -- DataService.Loaded
		expect.equal(InventoryService.getEquipped(player), "toast")
		expect.equal(player:GetAttribute("SD_Equipped"), "toast")
		player:Destroy()
	end)

	t.test("a saved choice that is not owned or not in the Catalog falls back to the starter", function()
		local w = setup()
		local player = fakePlayer("D")
		local profile = withProfile(w, player, "ready", {}, "dragon")
		InventoryService.refresh(player)
		expect.equal(InventoryService.getEquipped(player), Catalog.starterId())
		expect.equal(profile.equipped, Catalog.starterId())
		profile.owned.unicorn = { at = 1, src = "grant" }
		profile.equipped = "unicorn"
		InventoryService.refresh(player)
		expect.equal(InventoryService.getEquipped(player), Catalog.starterId())
		player:Destroy()
	end)

	t.test("owns: the starter always, other ids from the profile, unknown ids never", function()
		local w = setup()
		local player = fakePlayer("E")
		expect.truthy(InventoryService.owns(player, Catalog.starterId())) -- even before the profile loads
		expect.falsy(InventoryService.owns(player, "toast"))
		withProfile(w, player, "ready", { "toast", "unicorn" })
		expect.truthy(InventoryService.owns(player, "toast"))
		expect.falsy(InventoryService.owns(player, "dragon"))
		expect.falsy(InventoryService.owns(player, "unicorn")) -- kept in the profile, ignored (§3.3)
		expect.falsy(InventoryService.owns(player, 42))
		expect.deepEqual(InventoryService.ownedIds(player), { "kitty_bread", "toast" })
		player:Destroy()
	end)

	-- Equip -----------------------------------------------------------------------------------------------------------

	t.test("equip an owned squishy: profile, SD_Equipped, state field, soon save, Equipped signal", function()
		local w = setup()
		local player = fakePlayer("F")
		local profile = withProfile(w, player, "ready", { "butter" })
		InventoryService.playerAdded(player)
		local fired: { any } = {}
		local connection = InventoryService.Equipped:connect(function(p: any, id: string, previous: string)
			table.insert(fired, { p = p, id = id, previous = previous })
		end)
		local result = InventoryService.equip(player, "butter")
		connection:disconnect()
		expect.equal(result.ok, true)
		expect.equal(result.data, nil) -- Result<nil> (§2.8)
		expect.equal(w.mutations, 1)
		expect.equal(profile.equipped, "butter")
		expect.equal(player:GetAttribute("SD_Equipped"), "butter")
		expect.equal(InventoryService.getEquipped(player), "butter")
		expect.deepEqual(w.dirty, { "equipped" })
		expect.deepEqual(w.saves, { "soon" })
		expect.deepEqual(fired, { { p = player, id = "butter", previous = Catalog.starterId() } })
		-- Equipping it again changes nothing and saves nothing.
		local again = InventoryService.equip(player, "butter")
		expect.equal(again.ok, true)
		expect.deepEqual(w.saves, { "soon" })
		player:Destroy()
	end)

	t.test("equip refuses unowned and unknown squishies (§12 #4)", function()
		local w = setup()
		local player = fakePlayer("G")
		local profile = withProfile(w, player, "ready", {})
		InventoryService.playerAdded(player)
		local unowned = InventoryService.equip(player, "dragon")
		expect.equal(unowned.ok, false)
		expect.equal(unowned.reason, "inventory.notOwned")
		local unknown = InventoryService.equip(player, "unicorn")
		expect.equal(unknown.reason, "net.invalid")
		expect.equal(InventoryService.equip(player, 7).reason, "net.invalid")
		expect.equal(profile.equipped, Catalog.starterId())
		expect.equal(player:GetAttribute("SD_Equipped"), Catalog.starterId())
		expect.equal(#w.saves, 0)
		player:Destroy()
	end)

	t.test("equip is locked while matched or in a match (SD_MatchId / SD_DuelPhase)", function()
		local w = setup()
		local player = fakePlayer("H")
		withProfile(w, player, "ready", { "toast" })
		InventoryService.playerAdded(player)
		player:SetAttribute("SD_MatchId", "some-match")
		player:SetAttribute("SD_DuelPhase", "Preparing")
		expect.equal(InventoryService.equip(player, "toast").reason, "inventory.lockedInDuel")
		player:SetAttribute("SD_MatchId", "")
		player:SetAttribute("SD_DuelPhase", "Returning")
		expect.equal(InventoryService.equip(player, "toast").reason, "inventory.lockedInDuel")
		player:SetAttribute("SD_DuelPhase", "")
		expect.equal(InventoryService.equip(player, "toast").ok, true)
		player:Destroy()
	end)

	t.test("loading refuses; OFFLINE / READONLY may equip only the starter, never saved", function()
		local w = setup()
		local player = fakePlayer("I")
		InventoryService.playerAdded(player)
		expect.equal(InventoryService.equip(player, "toast").reason, "data.notReady")
		local profile = withProfile(w, player, "offline", { "toast" }, "toast")
		expect.equal(InventoryService.equip(player, "toast").reason, "data.offline")
		w.statuses[player] = "readonly"
		expect.equal(InventoryService.equip(player, "toast").reason, "data.readOnly")
		local starter = InventoryService.equip(player, Catalog.starterId())
		expect.equal(starter.ok, true)
		expect.equal(profile.equipped, Catalog.starterId())
		expect.equal(#w.saves, 0)
		player:Destroy()
	end)

	t.test("a ready session that takes no more changes (being released) refuses the equip", function()
		local w = setup()
		local player = fakePlayer("L")
		local profile = withProfile(w, player, "ready", { "toast" })
		InventoryService.playerAdded(player)
		w.frozen[player] = true
		local fired = 0
		local connection = InventoryService.Equipped:connect(function()
			fired += 1
		end)
		local result = InventoryService.equip(player, "toast")
		connection:disconnect()
		expect.equal(result.reason, "data.notReady")
		expect.equal(profile.equipped, Catalog.starterId())
		expect.equal(player:GetAttribute("SD_Equipped"), Catalog.starterId())
		expect.equal(fired, 0)
		expect.equal(#w.saves, 0)
		player:Destroy()
	end)

	t.test("a status change after the player left tracks nothing again", function()
		local w = setup()
		local player = fakePlayer("N")
		withProfile(w, player, "ready", { "toast" }, "toast")
		InventoryService.playerAdded(player)
		expect.equal(InventoryService.getEquipped(player), "toast")
		InventoryService.playerRemoving(player)
		InventoryService.refresh(player) -- e.g. StatusChanged from a failed final save
		expect.equal(InventoryService.getEquipped(player), Catalog.starterId()) -- untracked: the starter
		InventoryService.playerAdded(player) -- rejoin
		expect.equal(InventoryService.getEquipped(player), "toast")
		player:Destroy()
	end)

	t.test("a corrected ready choice goes through mutate and marks equipped", function()
		local w = setup()
		local player = fakePlayer("M")
		withProfile(w, player, "ready", {}, "dragon")
		InventoryService.refresh(player)
		expect.equal(w.mutations, 1)
		expect.deepEqual(w.dirty, { "equipped" })
		player:Destroy()
	end)

	-- Duplicate hooks (§6.5) ------------------------------------------------------------------------------------------

	t.test("duplicate hooks follow ownership and the box's refund", function()
		local w = setup()
		local player = fakePlayer("J")
		withProfile(w, player, "ready", { "bird" })
		expect.truthy(InventoryService.isDuplicate(player, "bird"))
		expect.falsy(InventoryService.isDuplicate(player, "donut"))
		expect.equal(InventoryService.duplicateRefund("sweet"), 112_500_000) -- 25% of 450,000,000
		expect.equal(InventoryService.duplicateRefund("unicorn"), 0)
		player:Destroy()
	end)

	t.test("isLocked reads the server-written duel attributes", function()
		setup()
		local player = fakePlayer("K")
		expect.falsy(InventoryService.isLocked(player))
		player:SetAttribute("SD_DuelPhase", "Active")
		expect.truthy(InventoryService.isLocked(player))
		expect.falsy(InventoryService.isLocked({ UserId = 3 })) -- a non-Instance (the test dummy) is never locked here
		player:Destroy()
	end)

	-- End to end through a real DataService core ----------------------------------------------------------------------

	-- A DataService core on `store` with a fixed clock and no real waits (spawn / defer run at once).
	local function newCore(store: any, nonce: string): any
		local DataService = t.requireServer("Services/DataService")
		return DataService.newCore({
			now = function(): number
				return NOW
			end,
			wait = function(_seconds: number) end,
			random = function(): number
				return 0
			end,
			storeFor = function(_userId: number): any
				return store
			end,
			jobId = "inventory-test",
			newNonce = function(): string
				return nonce
			end,
			notify = function() end,
			spawn = function(fn: () -> ())
				fn()
			end,
			defer = function(fn: () -> ())
				fn()
			end,
		})
	end

	-- The DataService core as InventoryService's data port, with a quiet state recorder.
	local function useCore(core: any)
		local StateService = t.requireServer("Services/StateService")
		InventoryService.useDeps({
			data = StateService.portFrom(core),
			markDirty = function(_player: any, _field: string) end,
		})
	end

	local function equipRoundTrip(store: any)
		-- A plain table player: DataService reads UserId; SD_Equipped is only written on real Instances.
		local player = { UserId = 5150 }
		local first = newCore(store, "1111aaaa")
		expect.equal(first.loadAsync(player), "ready")
		useCore(first)
		InventoryService.playerAdded(player)
		expect.equal(InventoryService.getEquipped(player), Catalog.starterId())
		local owned = first.mutate(player, function(profile: any): any
			profile.owned.toast = { at = NOW, src = "shop" }
			return nil
		end)
		expect.truthy(owned)
		expect.equal(InventoryService.equip(player, "toast").ok, true)
		expect.truthy(first.releaseAsync(player))
		InventoryService.playerRemoving(player)

		-- Another server loads the same key: the saved choice is held again.
		local second = newCore(store, "2222bbbb")
		expect.equal(second.loadAsync(player), "ready")
		useCore(second)
		InventoryService.playerAdded(player)
		expect.equal(second.getProfile(player).equipped, "toast")
		expect.equal(InventoryService.getEquipped(player), "toast")
		second.releaseAsync(player)
		InventoryService.playerRemoving(player)
		InventoryService.useDeps(nil)
	end

	t.test("memory mode end to end: the equipped squishy survives a release and a reload", function()
		local InMemoryAdapter = t.requireServer("Data/InMemoryAdapter")
		equipRoundTrip(InMemoryAdapter.new("Memory"))
	end)

	t.test("datastore path end to end (FakeDataStore): the equipped squishy survives, UpdateAsync only", function()
		local FakeDataStore = t.requireFake("FakeDataStore")
		local store = FakeDataStore.new("PlayerData_v1_STUDIO")
		equipRoundTrip(store)
		expect.equal(store.forbiddenCalls, 0)
	end)
end
