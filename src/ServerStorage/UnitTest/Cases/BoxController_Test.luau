--!strict
-- BoxController_Test: unit tests for StarterPlayerScripts.Client.Controllers.BoxController. Server only
-- (ServerStorage.UnitTest). Edit mode: init() is never called (no screens, no remotes), so a reveal never plays here;
-- the reveal's words, timings and odds are UI/BoxFormat's (BoxFormat_Test), its idle life Anim/IdleRig's (IdleRig_Test).
-- Contract (squishy overhaul spec 2026-10-09 §6 Studio check 3):
--   * debugRevealPreview(id) refuses an unknown squishy; for a known one it queues a local preview reveal (source
--     "preview": no remote, no grant, nothing to acknowledge) of a box that holds it, as a new squishy with no refund.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local BoxController = t.requireClient("Controllers/BoxController")
	local Boxes = t.requireShared("Boxes")
	local expect = t.expect

	t.test("debugRevealPreview refuses an unknown squishy", function()
		for _, id in { "no_such_squishy", 42, false, "gift_box" } :: { any } do
			local result = BoxController.debugRevealPreview(id)
			expect.equal(result.ok, false)
			expect.equal(type(result.error), "string")
		end
		expect.equal(BoxController.debugRevealPreview(nil).ok, false)
	end)

	t.test("debugRevealPreview queues a local preview of a box that holds the squishy", function()
		for _, id in { "mochi_fox", "kitty_bread" } do
			local result = BoxController.debugRevealPreview(id)
			expect.equal(result.ok, true)
			expect.equal(result.squishyId, id)
			local rows = Boxes.containing(id)
			local box = if #rows > 0 then rows[1].boxId else "snack"
			expect.equal(result.boxId, box)
			expect.equal(result.playing, false) -- Edit mode: the reveal screen is not registered
			expect.equal(result.queued, true) -- it waits in the reveal queue
			expect.equal(string.sub(result.requestId, 1, 8), "preview:")
		end
	end)
end
