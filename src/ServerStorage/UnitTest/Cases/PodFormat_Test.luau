--!strict
-- PodFormat_Test: unit tests for StarterPlayerScripts.Client.UI.PodFormat. Server only (ServerStorage.UnitTest).
-- Contract (Squish Pods HUD, 2026-11-03; H = "Squishy Duels In-Game HUD.dc.html"): the spin's slowing icon changes
-- (H:130); the dial's memory of the last grab (a K.O. drops a roll still spinning); its phase (rolling until the
-- landing, landed for the hold, then active while the power-up lasts, else idle); the tag and chip texts; the edge
-- colour and the glowing button of each power-up (H:186-189, owner: the touch Throw instead of Q).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Format = t.requireClient("UI/PodFormat")
	local expect = t.expect
	local POWER_UPS = {
		rollSeconds = 1.35,
		order = { "shield", "speed", "ultCharge" },
		kinds = { shield = { seconds = 6 }, speed = { seconds = 6 }, ultCharge = { ultFraction = 0.5 } },
	}

	t.test("rollSchedule: H:130's icon changes, slowing down, none in the last 30 ms", function()
		local times = Format.rollSchedule(1350)
		expect.equal(times[1], 42)
		for i = 2, #times do
			expect.truthy(times[i] - times[i - 1] >= times[i - 1] - (times[i - 2] or 0) - 1e-9)
		end
		expect.truthy(times[#times] < 1350 - 30)
		expect.equal(#Format.rollSchedule(0), 0)
	end)

	t.test("remember: a new roll replaces the memory; a K.O. drops one still spinning; a landing keeps it", function()
		local m = Format.remember({}, { power = "shield", landsAt = 101.35 }, true, 100)
		expect.deepEqual(m, { power = "shield", landsAt = 101.35 })
		expect.equal(Format.remember(m, { power = "shield", landsAt = 101.35 }, true, 100.5), m)
		expect.deepEqual(Format.remember(m, nil, false, 100.5), {}) -- knocked out mid-spin
		expect.equal(Format.remember(m, nil, true, 101.4), m) -- landed: kept for the landing and the timer
		-- the landing view came a hair before our clock reached it: land now
		expect.deepEqual(Format.remember(m, nil, true, 101.3), { power = "shield", landsAt = 101.3 })
	end)

	t.test("state: rolling, landed for the hold, active while the power-up lasts, else idle", function()
		local m = { power = "shield", landsAt = 101.35 }
		local rolling = Format.state(m, {}, 100.5, POWER_UPS)
		expect.equal(rolling.phase, "rolling")
		expect.near(rolling.since :: number, 0.5, 1e-9)
		local landed = Format.state(m, { shield = 107.35 }, 101.6, POWER_UPS)
		expect.equal(landed.phase, "landed")
		expect.equal(landed.power, "shield")
		expect.equal(landed.fraction, 1)
		local active = Format.state(m, { shield = 107.35 }, 104.35, POWER_UPS)
		expect.equal(active.phase, "active")
		expect.near(active.left :: number, 3, 1e-9)
		expect.near(active.fraction :: number, 0.5, 1e-9)
		expect.equal(Format.state(m, { shield = 107.35 }, 107.4, POWER_UPS).phase, "idle")
		-- an instant one: landed, then idle
		local ult = { power = "ultCharge", landsAt = 101.35 }
		expect.equal(Format.state(ult, {}, 101.5, POWER_UPS).phase, "landed")
		expect.equal(Format.state(ult, {}, 102.2, POWER_UPS).phase, "idle")
		-- a live power-up with no grab seen (the HUD came in late) still drains
		expect.equal(Format.state({}, { speed = 105 }, 102, POWER_UPS).power, "speed")
		expect.equal(Format.state({}, {}, 102, POWER_UPS).phase, "idle")
	end)

	t.test("texts: POD or whole seconds left; the chip names the power-up or the ult share", function()
		expect.equal(Format.tagText({ phase = "idle" }), "POD")
		expect.equal(Format.tagText({ phase = "rolling", power = "shield" }), "POD")
		expect.equal(Format.tagText({ phase = "active", power = "shield", left = 2.2, fraction = 0.4 }), "3s")
		expect.equal(Format.chipText("shield", POWER_UPS), "Shield!")
		expect.equal(Format.chipText("ultCharge", POWER_UPS), "+50% Ult!")
	end)

	t.test("keyed: the value between keyframes, each segment eased, held outside", function()
		local frames = { { 0, 0.55 }, { 0.6, 1.06 }, { 1, 1 } }
		local linear = function(x: number): number
			return x
		end
		expect.equal(Format.keyed(frames, -1, linear), 0.55)
		expect.near(Format.keyed(frames, 0.3, linear), 0.805, 1e-9)
		expect.near(Format.keyed(frames, 0.8, linear), 1.03, 1e-9)
		expect.equal(Format.keyed(frames, 2, linear), 1)
	end)

	t.test("looks: every kind has its colours and glyph; the edge and the glowing button by kind", function()
		for _, kind in { "shield", "speed", "throwBoost", "ultCharge", "dashBoost", "rapidThrow", "superJump" } do
			local look = Format.look(kind)
			expect.truthy(look and typeof(look.color) == "Color3" and typeof(look.bottom) == "Color3")
			expect.equal(look.icon, "img.pod." .. kind)
		end
		expect.equal(Format.look("nope"), nil)
		expect.truthy(Format.edgeColor("shield") ~= nil)
		expect.truthy(Format.edgeColor("superJump") ~= nil)
		expect.equal(Format.edgeColor("throwBoost"), nil)
		expect.equal(Format.glowButton("dashBoost"), "dash")
		expect.equal(Format.glowButton("rapidThrow"), "throw")
		expect.equal(Format.glowButton("throwBoost"), "throw")
		expect.equal(Format.glowButton("shield"), nil)
	end)
end
