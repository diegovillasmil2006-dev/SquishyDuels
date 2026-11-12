--!strict
-- PortalService_Test: unit tests for ServerScriptService.Server.Services.PortalService's pure part (Diego's FULL FINAL
-- lobby portals). Server only (ServerStorage.UnitTest). Edit mode: start() is never called.
-- Contract (zip src/server/PracticePortal.server.luau:133-135): the arena height check rescues a body inside the box
-- round the arena centre (|dx| < 80, |dz| < 90) more than 25 studs under its floor; never anyone outside that box (the
-- lobby, the highway) and never anyone on or just under the floor. Audit row 40: nearTrigger counts a touch only with
-- the body's root within the margin of the trigger's (turned) box.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local PortalService = t.requireServer("Services/PortalService")
	local expect = t.expect
	local CENTER = Vector3.new(1400, 2, 0) -- Diego's PracticeArena.Markers.ArenaCenter
	local FLOOR = CENTER.Y

	t.test("the arena height check: inside the box and more than 25 under the floor", function()
		expect.equal(PortalService.fellOff(Vector3.new(1400, -30, 0), CENTER, FLOOR), true)
		expect.equal(PortalService.fellOff(Vector3.new(1479, -30, 89), CENTER, FLOOR), true)
		expect.equal(PortalService.fellOff(Vector3.new(1400, -22.9, 0), CENTER, FLOOR), false) -- 24.9 under: not yet
		expect.equal(PortalService.fellOff(Vector3.new(1400, 5, 0), CENTER, FLOOR), false) -- on the island
		expect.equal(PortalService.fellOff(Vector3.new(1480, -30, 0), CENTER, FLOOR), false) -- outside the box
		expect.equal(PortalService.fellOff(Vector3.new(0, -30, 0), CENTER, FLOOR), false) -- the lobby
		expect.equal(PortalService.fellOff(Vector3.new(0, 2, -265), CENTER, FLOOR), false) -- the highway's deck
	end)

	t.test("a portal touch counts only near the trigger (audit row 40)", function()
		local box = CFrame.new(10, 5, 0) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(8, 10, 2)
		expect.equal(PortalService.nearTrigger(Vector3.new(10, 5, 0), box, size, 10), true) -- inside
		expect.equal(PortalService.nearTrigger(Vector3.new(10, 5, 14), box, size, 10), true) -- 10 past the 4 half-width
		expect.equal(PortalService.nearTrigger(Vector3.new(10, 5, 14.1), box, size, 10), false)
		expect.equal(PortalService.nearTrigger(Vector3.new(10, 21, 0), box, size, 10), false) -- 11 above the top
		expect.equal(PortalService.nearTrigger(Vector3.new(500, 5, 0), box, size, 10), false) -- across the map
	end)
end
