--!strict
-- NearFade_Test: unit tests for StarterPlayerScripts.Client.Anim.NearFade (first-person spec 2026-10-10 §3.10).
-- Server only (ServerStorage.UnitTest). Pure: numbers only.
-- Contract: the near fade is 0 beyond 4.5 studs from the camera, 1 inside 2.5, linear between; the local caster's
-- Rush head is clear until it has travelled 3 studs and solid at 8; fades combine as their max (one never lowers
-- another); a Highlight transparency moves toward 1 by the near fade; the local player's own projectile gets no near
-- fade in its first 0.2 s (it starts at the hand on purpose); in third person the Rush head keeps its end fade alone.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TOLERANCE = 1e-6

return function(t: Context)
	local NearFade = t.requireClient("Anim/NearFade")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local band = Config.FirstPerson.nearFade
	local rush = Config.FirstPerson.rushFadeIn

	t.test("the near fade is 0 beyond 4.5 studs, 1 inside 2.5, linear between", function()
		expect.equal(band.from, 2.5)
		expect.equal(band.to, 4.5)
		expect.equal(NearFade.amount(4.5), 0)
		expect.equal(NearFade.amount(10), 0)
		expect.equal(NearFade.amount(math.huge), 0)
		expect.equal(NearFade.amount(2.5), 1)
		expect.equal(NearFade.amount(1), 1)
		expect.equal(NearFade.amount(0), 1)
		expect.near(NearFade.amount(3.5), 0.5, TOLERANCE)
		expect.near(NearFade.amount(3), 0.75, TOLERANCE)
		expect.near(NearFade.amount(4), 0.25, TOLERANCE)
		-- Monotonic: nearer never fades less.
		local previous = 1
		for i = 0, 60 do
			local fade = NearFade.amount(i / 10)
			expect.truthy(fade <= previous + TOLERANCE)
			expect.truthy(fade >= 0 and fade <= 1)
			previous = fade
		end
		-- A bad distance (no camera yet) never hides anything.
		expect.equal(NearFade.amount(0 / 0), 0)
	end)

	t.test("the caster's Rush head is clear until 3 studs travelled and solid at 8", function()
		expect.equal(rush.from, 3)
		expect.equal(rush.to, 8)
		expect.equal(NearFade.rushFadeIn(0), 1)
		expect.equal(NearFade.rushFadeIn(3), 1)
		expect.near(NearFade.rushFadeIn(5.5), 0.5, TOLERANCE)
		expect.equal(NearFade.rushFadeIn(8), 0)
		expect.equal(NearFade.rushFadeIn(60), 0)
		expect.equal(NearFade.rushFadeIn(-1), 1)
	end)

	t.test("a Highlight transparency moves toward 1 by the near fade", function()
		expect.near(NearFade.toward(0.15, 0), 0.15, TOLERANCE)
		expect.near(NearFade.toward(0.15, 1), 1, TOLERANCE)
		expect.near(NearFade.toward(0.15, 0.5), 0.575, TOLERANCE)
		expect.near(NearFade.toward(1, 0.3), 1, TOLERANCE)
		expect.near(NearFade.toward(0.5, 0.5), 0.75, TOLERANCE) -- the impact flash's peak, half faded
	end)

	t.test("the own projectile gets no near fade in its first 0.2 s; every other one always does", function()
		expect.equal(NearFade.OWN_GRACE_SECONDS, 0.2)
		expect.equal(NearFade.projectile(3.5, true, 0), 0)
		expect.equal(NearFade.projectile(3.5, true, 0.19), 0)
		expect.near(NearFade.projectile(3.5, true, 0.2), 0.5, TOLERANCE)
		expect.near(NearFade.projectile(3.5, true, 1), 0.5, TOLERANCE)
		expect.near(NearFade.projectile(3.5, false, 0), 0.5, TOLERANCE)
		expect.equal(NearFade.projectile(2, false, 0.05), 1) -- another player's practice throw starting beside you
		expect.equal(NearFade.projectile(9, false, 0.05), 0)
	end)

	t.test("the Rush head: its end fade alone in third person; in first person the max of the three", function()
		-- Third person: exactly today's (the end fade only), for the caster and the target alike.
		for _, isCaster in { true, false } do
			expect.equal(NearFade.rushHead(0, 0, 1, isCaster, false), 0)
			expect.equal(NearFade.rushHead(0.4, 1, 1, isCaster, false), 0.4)
		end
		-- First person, the caster: fully clear right after the release (whatever the distance), solid by 8 studs.
		expect.equal(NearFade.rushHead(0, 0, 6, true, true), 1)
		expect.near(NearFade.rushHead(0, 5.5, 7.5, true, true), 0.5, TOLERANCE)
		expect.equal(NearFade.rushHead(0, 8, 10, true, true), 0)
		-- First person, the target (or anyone else): only the near fade, from the camera.
		expect.equal(NearFade.rushHead(0, 0, 20, false, true), 0)
		expect.near(NearFade.rushHead(0, 50, 3.5, false, true), 0.5, TOLERANCE)
		expect.equal(NearFade.rushHead(0, 50, 2, false, true), 1)
		-- The combine is a max: no fade ever lowers another.
		expect.near(NearFade.rushHead(0.9, 5.5, 3.5, true, true), 0.9, TOLERANCE) -- end fade wins
		expect.near(NearFade.rushHead(0.2, 5.5, 4, true, true), 0.5, TOLERANCE) -- caster fade-in wins
		expect.near(NearFade.rushHead(0.2, 7, 3, true, true), 0.75, TOLERANCE) -- near fade wins
		for _, endFade in { 0, 0.3, 1 } do
			for _, travelled in { 0, 4, 9 } do
				for _, distance in { 1, 3, 6 } do
					for _, isCaster in { true, false } do
						local fade = NearFade.rushHead(endFade, travelled, distance, isCaster, true)
						expect.truthy(fade >= endFade - TOLERANCE)
						expect.truthy(fade >= NearFade.amount(distance) - TOLERANCE)
						if isCaster then
							expect.truthy(fade >= NearFade.rushFadeIn(travelled) - TOLERANCE)
						end
						expect.truthy(fade <= 1 + TOLERANCE)
					end
				end
			end
		end
	end)
end
