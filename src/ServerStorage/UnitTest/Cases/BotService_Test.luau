--!strict
-- BotService_Test: unit tests for ServerScriptService.Server.Services.BotService's turning (face), which the practice bot
-- and the match bots share. Server only (ServerStorage.UnitTest). A fake rig: no physics in Edit mode.
-- Contract (BotService.face): the root turns to the target on the flat and keeps its position; writing a humanoid
-- root's CFrame cancels its Humanoid:MoveTo (seen in Studio 2026-10-26: the bots never walked), so face gives the
-- humanoid its walk again (MoveTo its WalkToPoint).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BotService = t.requireServer("Services/BotService")

	t.test("face turns the root to the target on the flat and gives the humanoid its walk again", function()
		local goal = Vector3.new(0, 3, 20)
		local walks: { Vector3 } = {}
		local humanoid = {
			WalkToPoint = goal,
			MoveTo = function(_self: any, point: Vector3)
				table.insert(walks, point)
			end,
		}
		local rig = {
			FindFirstChildOfClass = function(_self: any, className: string): any
				return if className == "Humanoid" then humanoid else nil
			end,
		}
		local root: any = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0), Parent = rig }
		BotService.face(root, Vector3.new(10, 50, 0))
		expect.near(root.CFrame.LookVector.X, 1, 1e-6) -- toward the target, level
		expect.near(root.CFrame.LookVector.Y, 0, 1e-6)
		expect.near((root.CFrame.Position - Vector3.new(0, 3, 0)).Magnitude, 0, 1e-6)
		expect.deepEqual(walks, { goal })
	end)

	t.test("face on a root with no humanoid only turns it", function()
		local root: any = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0), Parent = nil }
		BotService.face(root, Vector3.new(0, 3, -10))
		expect.near(root.CFrame.LookVector.Z, -1, 1e-6)
	end)
end
