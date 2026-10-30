--!strict
-- PracticeService_Test: unit tests for the target bookkeeping of ServerScriptService.Server.Services.PracticeService.
-- Server only (ServerStorage.UnitTest). Edit mode: start() is never called; the "player" is a plain table key (no
-- session is open, because isPracticing needs a character in the lobby's SD_PracticeZone).
-- Contract (DESIGN §5.11, §6.8):
--   * a hit target stays down for Config.Combat.Practice.targetDownSeconds and cannot be hit meanwhile;
--   * an unknown target is never hit;
--   * the practice_hits quest counts each target at most once per Config.Economy.Quests.practiceTargetRepeatSeconds;
--   * a Dragon Rush rehearsal lane knocks a target down but never counts for the quest or the session stats;
--   * targets are the 4 PracticeTargets definitions (Squish Island's range, lobby bases spec §3); practice never pays
--     Coins (this service has no Coin path).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PracticeService = t.requireServer("Services/PracticeService")
	local PracticeTargets = t.requireShared("Practice/PracticeTargets")
	local Config = t.requireShared("Config")

	local DOWN = Config.Combat.Practice.targetDownSeconds
	local REPEAT = Config.Economy.Quests.practiceTargetRepeatSeconds

	type HitRecord = { targetId: string, t: number, countsForQuest: boolean }

	local function fresh(): { HitRecord }
		PracticeService.destroy()
		local hits: { HitRecord } = {}
		PracticeService.TargetHit:connect(function(_player: any, targetId: string, at: number, countsForQuest: boolean)
			table.insert(hits, { targetId = targetId, t = at, countsForQuest = countsForQuest })
		end)
		return hits
	end

	t.test("the targets are the PracticeTargets definitions", function()
		expect.equal(#PracticeService.targets(), #PracticeTargets.list())
		expect.equal(#PracticeService.targets(), 4)
	end)

	t.test("a hit knocks the target down for targetDownSeconds; a down target cannot be hit", function()
		fresh()
		local player: any = {}
		local id = PracticeTargets.list()[1].id
		expect.truthy(PracticeService.registerHit(player, id, 100))
		expect.truthy(PracticeService.isTargetDown(id, 100 + DOWN / 2))
		expect.falsy(PracticeService.registerHit(player, id, 100 + DOWN / 2))
		expect.falsy(PracticeService.isTargetDown(id, 100 + DOWN))
		expect.truthy(PracticeService.registerHit(player, id, 100 + DOWN))
		PracticeService.destroy()
	end)

	t.test("an unknown target is never hit", function()
		local hits = fresh()
		expect.falsy(PracticeService.registerHit({} :: any, "target_99", 100))
		expect.equal(#hits, 0)
		PracticeService.destroy()
	end)

	t.test("the quest counts a target at most once per practiceTargetRepeatSeconds", function()
		local hits = fresh()
		local player: any = {}
		local id = PracticeTargets.list()[2].id
		local first = 200
		local second = first + math.max(DOWN, REPEAT / 2) -- up again, but inside the quest window
		local third = first + math.max(DOWN, REPEAT) -- outside it
		expect.truthy(second < first + REPEAT)
		expect.truthy(PracticeService.registerHit(player, id, first))
		expect.truthy(PracticeService.registerHit(player, id, second))
		expect.truthy(PracticeService.registerHit(player, id, third))
		expect.equal(#hits, 3)
		expect.equal(hits[1].countsForQuest, true)
		expect.equal(hits[2].countsForQuest, false)
		expect.equal(hits[3].countsForQuest, true)
		-- Another player's hit on the same target is counted on its own.
		local other: any = {}
		expect.truthy(PracticeService.registerHit(other, id, third + DOWN))
		expect.equal(hits[4].countsForQuest, true)
		PracticeService.destroy()
	end)

	t.test("a Dragon Rush rehearsal lane knocks a target down but counts for nothing", function()
		local hits = fresh()
		local player: any = {}
		local id = PracticeTargets.list()[3].id
		expect.truthy(PracticeService.registerHit(player, id, 300, true))
		expect.truthy(PracticeService.isTargetDown(id, 300 + DOWN / 2))
		expect.equal(#hits, 1)
		expect.equal(hits[1].countsForQuest, false)
		expect.deepEqual(PracticeService.stats(player), { throws = 0, hits = 0, accuracy = 0 })
		-- The lane did not use up the quest window: a thrown hit right after counts.
		expect.truthy(PracticeService.registerHit(player, id, 300 + DOWN))
		expect.equal(hits[2].countsForQuest, true)
		PracticeService.destroy()
	end)

	t.test("practice hits are scored on the target's face: the contact point moves onto the face's plane", function()
		local bull = Vector3.new(1382, 7.6, -7.5)
		-- a dead-centre throw touches the ball 3.4 in front of the bullseye: on the face it is the bullseye
		local onFace = PracticeService.onFace(bull + Vector3.new(0, 0, 3.4), bull, Vector3.zAxis)
		expect.near((onFace - bull).Magnitude, 0, 1e-3)
		-- 0.8 to the side keeps its 0.8 (Diego's GREAT ring)
		onFace = PracticeService.onFace(bull + Vector3.new(0.8, 0, 2.9), bull, Vector3.zAxis)
		expect.near((onFace - bull).Magnitude, 0.8, 1e-3)
		-- a tipped face (a pop-up target going down): measured across that face
		local normal = Vector3.new(0, 1, 1).Unit
		onFace = PracticeService.onFace(bull + normal * 3, bull, normal)
		expect.near((onFace - bull).Magnitude, 0, 1e-3)
	end)
end
