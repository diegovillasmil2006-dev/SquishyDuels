--!strict
-- HoldSqueeze_Test: unit tests for StarterPlayerScripts.Client.Anim.HoldSqueeze (first-person spec 2026-10-10 §3.5,
-- §3.7). Server only (ServerStorage.UnitTest). Pure: real SquishRigs, no instances.
-- Contract: begin presses on the rig's own axis at once; an end before releaseStartMs (by the rig's own clock) calls
-- endPress, so a quick press is exactly a tap; a later end calls release (it pops from where it is); the mashing cap: a
-- press before the running squeeze's pop end merges (no restart), so 20 presses a second give at most 3 squeezes a
-- second, well under Inspect's 8-a-second preview cap; finish does nothing when the rig is not in a press.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FINE = 1 / 240
local FRAME = 1 / 60

-- Kitty Bread's row (Common, foam) and Mochi Fox's (Uncommon, mochi).
local KITTY = {
	squeeze = { depth = 0.6, widen = 0.72, kRel = 34, cRel = 8.5 },
	feel = "foam",
	flight = { style = "tumble" },
}
local MOCHI = {
	squeeze = { depth = 0.55, widen = 0.8, kRel = 26, cRel = 8 },
	feel = "mochi",
	flight = { style = "tumble", pulse = 1.15 },
}

return function(t: Context)
	local HoldSqueeze = t.requireClient("Anim/HoldSqueeze")
	local SquishRig = t.requireClient("Anim/SquishRig")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local SQUISH = SquishRig.EVENTS.squish

	local function newRig(motion: any, rarity: string?, axis: string?): (any, any)
		local rig = SquishRig.new(motion, { rarity = rarity, seed = 3, blink = false, axis = axis :: any })
		return rig, SquishRig.newOut()
	end

	local function stepBoth(a: any, aOut: any, b: any, bOut: any, seconds: number)
		for _ = 1, math.floor(seconds / FINE + 0.5) do
			a:step(FINE, aOut)
			b:step(FINE, bOut)
			expect.equal(aOut.S, bOut.S)
			expect.equal(aOut.events, bOut.events)
			expect.equal(aOut.face, bOut.face)
		end
	end

	t.test("begin presses at once on the rig's own axis", function()
		local rig, out = newRig(KITTY, "Common", "Z")
		rig:setAxis("Y") -- the owner's axis (first person and Inspect: Y), switched at rest
		expect.truthy(HoldSqueeze.begin(rig))
		expect.equal(rig:elapsedMs(), 0)
		for _ = 1, 30 do
			rig:step(FRAME, out)
		end
		expect.truthy(out.S.Y < 0.75 and out.S.Z > 1.1)
		expect.near(out.pressAmount, 1, 0.05) -- still held: the press stays at depth
	end)

	t.test("an end before the release start is exactly a tap; a later end pops from where it is", function()
		for _, rarity in { "Common", "Uncommon" } do
			for _, endMs in { 20, 150, 300 } do
				local a, aOut = newRig(MOCHI, rarity)
				local b, bOut = newRig(MOCHI, rarity)
				a:tap()
				expect.truthy(HoldSqueeze.begin(b))
				stepBoth(a, aOut, b, bOut, endMs / 1000)
				expect.truthy((b:elapsedMs() :: number) < b.timing.releaseStartMs)
				HoldSqueeze.finish(b)
				stepBoth(a, aOut, b, bOut, 1.5)
			end
			-- Let go after the release start: release(), compared with a twin that presses and releases by hand.
			local c, cOut = newRig(MOCHI, rarity)
			local d, dOut = newRig(MOCHI, rarity)
			c:press()
			expect.truthy(HoldSqueeze.begin(d))
			stepBoth(c, cOut, d, dOut, 0.6)
			c:release()
			HoldSqueeze.finish(d)
			stepBoth(c, cOut, d, dOut, 1.2)
		end
	end)

	t.test("the mashing cap: 20 presses a second give at most 3 squeezes a second", function()
		for _, rarity in { "Common", "Uncommon", "Epic", "Exclusive" } do
			local rig, out = newRig(KITTY, rarity)
			local starts: { number } = {}
			local squishes = 0
			local time = 0
			local steps = math.floor(10 / FINE + 0.5)
			for step = 1, steps do
				-- 20 presses a second (one every 12 steps of 1/240 s), each held 25 ms (6 steps).
				if step % 12 == 1 then
					if HoldSqueeze.begin(rig) then
						table.insert(starts, time)
					end
				elseif step % 12 == 7 then
					HoldSqueeze.finish(rig)
				end
				rig:step(FINE, out)
				time += FINE
				if bit32.btest(out.events, SQUISH) then
					squishes += 1
				end
			end
			-- No two squeezes start closer than the pop end; any one second holds at most 3.
			for i = 2, #starts do
				expect.truthy(starts[i] - starts[i - 1] >= rig.timing.popEndMs / 1000 - 1e-6)
			end
			for i = 4, #starts do
				expect.truthy(starts[i] - starts[i - 3] > 1)
			end
			expect.truthy(#starts >= 20 and #starts <= 30) -- about 2.6 (Common) or 2.3 a second over 10 s
			expect.equal(squishes, #starts)
		end
		-- One preview per squeeze stays far under Inspect's cap.
		expect.equal(Config.Inspect.Preview.maxPerSecond, 8)
	end)

	t.test("a press before the pop end merges; finish does nothing outside a press", function()
		local rig, out = newRig(KITTY)
		rig:tap() -- an automatic tap (a countdown beat)
		for _ = 1, 12 do
			rig:step(FRAME, out)
		end
		local before = rig:elapsedMs()
		expect.falsy(HoldSqueeze.begin(rig)) -- merged: the running squeeze carries on
		expect.equal(rig:elapsedMs(), before)
		local twin, twinOut = newRig(KITTY)
		twin:tap()
		for _ = 1, 12 do
			twin:step(FRAME, twinOut)
		end
		HoldSqueeze.finish(rig) -- the merged press's end: the tap timeline is untouched
		for _ = 1, 90 do
			rig:step(FRAME, out)
			twin:step(FRAME, twinOut)
			expect.equal(out.S, twinOut.S)
		end
		-- A windup's hold took over: finish leaves it alone.
		local held, heldOut = newRig(KITTY)
		held:hold(0.9)
		HoldSqueeze.finish(held)
		held:step(FRAME, heldOut)
		expect.near(heldOut.S.Y, 0.9, 1e-4)
		-- At rest: nothing.
		local idle = newRig(KITTY)
		HoldSqueeze.finish(idle)
		expect.equal(idle:elapsedMs(), nil)
	end)
end
