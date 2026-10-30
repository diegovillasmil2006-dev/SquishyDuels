--!strict
-- HubFX_Test: unit tests for ReplicatedStorage.Shared.SquishyLobby.HubFX (Diego's FULL FINAL lobby motion), the part
-- the game changed. Server only (ServerStorage.UnitTest). Edit mode: eval is pure, the time is passed in.
-- Contract: a spin is wrapped to one turn (CFrame angles are float32, and t since HubFX.EPOCH is ~9e7 s, so a raw
-- spin * t moved in 2+ rad jumps): today's t gives an angle in [0, 2π) that advances by spin · dt, like a small t does.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local HubFX = t.requireShared("SquishyLobby/HubFX")
	local expect = t.expect
	local TAU = 2 * math.pi
	local TODAY = 1_793_400_000 - HubFX.EPOCH -- 2026-10-30, about 9.3e7 s

	t.test("a spin today stays within one turn and moves smoothly (the dragon at 0.22 rad/s, the coin at 1.6)", function()
		for _, spin in { 0.22, 1.6, -0.6, 2.2 } do
			local _, _, _, _, ry0 = HubFX.eval({ spin = spin }, TODAY)
			local _, _, _, _, ry1 = HubFX.eval({ spin = spin }, TODAY + 0.1)
			expect.truthy(ry0 >= 0 and ry0 < TAU)
			local step = (ry1 - ry0 + math.pi) % TAU - math.pi -- the shortest way round
			expect.near(step, spin * 0.1, 1e-6)
		end
		local _, _, _, _, _, rz0 = HubFX.eval({ spinZ = 0.55 }, TODAY)
		local _, _, _, _, _, rz1 = HubFX.eval({ spinZ = 0.55 }, TODAY + 0.1)
		expect.near((rz1 - rz0 + math.pi) % TAU - math.pi, 0.055, 1e-6)
	end)
end
