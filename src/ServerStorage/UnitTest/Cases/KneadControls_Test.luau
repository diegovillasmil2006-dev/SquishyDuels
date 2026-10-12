--!strict
-- KneadControls_Test: the knead's Inspect actions in StarterPlayerScripts.Client.Controllers.ControlsController (spec
-- phase2-squeeze §3.6). Server only (ServerStorage.UnitTest). Pure lookups. Contract:
--   * InspectPalms = Q and ButtonL1, InspectRewax = W and ButtonR1, both in the Inspect context;
--   * no other Inspect action takes Q, W, L1 or R1 (F / ButtonX stay InspectSqueeze, the thumb crunch while kneading).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Controls = t.requireClient("Controllers/ControlsController")
	local expect = t.expect

	t.test("the knead's Inspect keys: Q / L1 palms, W / R1 re-wax", function()
		expect.equal(Controls.contextOf("InspectPalms"), "Inspect")
		expect.equal(Controls.contextOf("InspectRewax"), "Inspect")
		expect.deepEqual(Controls.inputsOf("InspectPalms"), { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 })
		expect.deepEqual(Controls.inputsOf("InspectRewax"), { Enum.KeyCode.W, Enum.KeyCode.ButtonR1 })
		expect.deepEqual(Controls.inputsOf("InspectSqueeze"), { Enum.KeyCode.F, Enum.KeyCode.ButtonX })
	end)

	t.test("no other Inspect action takes the knead's keys", function()
		local taken = { Enum.KeyCode.Q, Enum.KeyCode.W, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }
		for _, action in
			{
				"InspectRotateKeys",
				"InspectZoomIn",
				"InspectZoomOut",
				"InspectWheel",
				"InspectSqueeze",
				"InspectReset",
				"InspectStick",
				"InspectZoomTriggers",
			}
		do
			for _, key in taken do
				expect.equal(table.find(Controls.inputsOf(action) :: { any }, key), nil)
			end
		end
	end)
end
