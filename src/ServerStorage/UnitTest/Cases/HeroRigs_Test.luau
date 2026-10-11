--!strict
-- HeroRigs_Test: unit tests for StarterPlayerScripts.Client.Anim.HeroRigs (squishy overhaul spec 2026-10-09 §3.2
-- detail levels, §5): the hero rigs that animate outside the held models (the Inspect model, the box reveal's model),
-- which HeldSquishyController counts against Config.Vfx.Budgets.
-- Contract: set(owner, true) counts an owner once, however often it is called; set(owner, false) frees it (an owner
-- that holds nothing changes nothing); count() is the number of owners that hold one now.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local HeroRigs = t.requireClient("Anim/HeroRigs")
	local expect = t.expect

	t.test("an owner counts once while it holds a hero rig, and nothing after it lets go", function()
		local before = HeroRigs.count()
		local inspect, reveal = {}, {}
		HeroRigs.set(inspect, true)
		HeroRigs.set(inspect, true)
		expect.equal(HeroRigs.count(), before + 1)
		HeroRigs.set(reveal, true)
		expect.equal(HeroRigs.count(), before + 2)
		HeroRigs.set(inspect, false)
		HeroRigs.set(inspect, false)
		expect.equal(HeroRigs.count(), before + 1)
		HeroRigs.set({}, false) -- an owner that holds nothing
		expect.equal(HeroRigs.count(), before + 1)
		HeroRigs.set(reveal, false)
		expect.equal(HeroRigs.count(), before)
	end)
end
