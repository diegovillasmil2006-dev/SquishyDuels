--!strict
-- ChargeFx_Test: unit tests for StarterPlayerScripts.Client.Anim.ChargeFx (feature 1, 2026-10-11: the charge's and the
-- crush's effect parts in the first-person overlay; design: the combat-effects page "Squishy Combat FP v2.html",
-- html:191-196, 508-514, 559). Server only (ServerStorage.UnitTest). The parts go into an unparented Folder.
-- Contract:
--   * a ring grows 1 - (1 - t)^3 of the way and fades (1 - t)^1.4 over its seconds (squishy-lib-v2.js:326), then goes;
--   * the orbit: seven pieces round the toy at (cos a·r, sin 2a·wave, sin a·r) (design: html:195);
--   * glow / outline / orbit make their parts once and hide them when off; clear() hides everything and drops the
--     rings; destroy() removes every part; every part is anchored and takes no collision, touch or query.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-6
local U = 0.5 -- studs per du (any)

return function(t: Context)
	local ChargeFx = t.requireClient("Anim/ChargeFx")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local CHARGE = Config.FirstPerson.charge
	local ACCENT = Color3.fromRGB(240, 120, 160)
	local AT = Vector3.new(0, -0.2, -0.6)

	local function named(folder: Instance, name: string): { BasePart }
		local list: { BasePart } = {}
		for _, child in folder:GetChildren() do
			if child.Name == name and child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
		return list
	end

	t.test("a ring grows 1 - (1 - t)^3 and fades (1 - t)^1.4 over its seconds", function()
		local share, opacity = ChargeFx.ringSample(0, 0.4)
		expect.near(share, 0, EPS)
		expect.near(opacity, 1, EPS)
		share, opacity = ChargeFx.ringSample(0.2, 0.4)
		expect.near(share, 1 - 0.5 ^ 3, EPS)
		expect.near(opacity, 0.5 ^ 1.4, EPS)
		share, opacity = ChargeFx.ringSample(0.4, 0.4)
		expect.near(share, 1, EPS)
		expect.near(opacity, 0, EPS)
		share, opacity = ChargeFx.ringSample(1, 0)
		expect.near(share, 1, EPS)
		expect.near(opacity, 0, EPS)
	end)

	t.test("the orbit: pieces round the centre at the radius, waving in height", function()
		local offsets = ChargeFx.orbitOffsets(7, 2, 0.5)
		expect.equal(#offsets, 7)
		expect.near((offsets[1] - Vector3.new(2, 0, 0)).Magnitude, 0, EPS)
		for i, offset in offsets do
			local a = (i - 1) / 7 * 2 * math.pi
			expect.near(Vector3.new(offset.X, 0, offset.Z).Magnitude, 2, EPS)
			expect.near(offset.Y, math.sin(2 * a) * 0.5, EPS)
		end
	end)

	t.test("glow, outline and orbit make their parts once and hide them when off", function()
		local folder = Instance.new("Folder")
		local fx = ChargeFx.new(folder, U)
		fx:glow(AT, 0.1, ACCENT, 0.3)
		fx:glow(AT, 0.12, ACCENT, 0.2)
		local glow = named(folder, "ChargeGlow")
		expect.equal(#glow, 1)
		expect.near(glow[1].Transparency, 0.8, 1e-4)
		expect.near(glow[1].Size.X, 2 * 0.12 * U, 1e-4)
		expect.truthy(glow[1].Anchored)
		expect.falsy(glow[1].CanCollide)
		expect.falsy(glow[1].CanQuery)
		expect.falsy(glow[1].CanTouch)
		fx:glow(AT, 0.12, ACCENT, 0)
		expect.equal(glow[1].Transparency, 1)
		fx:outline(AT, 0.1, true)
		expect.equal(#named(folder, "ChargeOutline"), 1)
		fx:outline(AT, 0.1, false)
		expect.equal(named(folder, "ChargeOutline")[1].Transparency, 1)
		fx:orbit(AT, 0.1, 0.5, 1, { ACCENT, Color3.new(1, 1, 1) }, true)
		fx:orbit(AT, 0.1, 0.9, 0.8, { ACCENT }, true)
		local pieces = named(folder, "ChargeOrbit")
		expect.equal(#pieces, CHARGE.orbitCount)
		for _, piece in pieces do
			expect.equal(piece.Transparency, 0)
		end
		fx:orbit(AT, 0.1, 0.9, 0.8, { ACCENT }, false)
		for _, piece in pieces do
			expect.equal(piece.Transparency, 1)
		end
		fx:destroy()
		expect.equal(#folder:GetChildren(), 0)
		folder:Destroy()
	end)

	t.test("rings live their seconds; clear drops them and hides the rest; destroy removes every part", function()
		local folder = Instance.new("Folder")
		local fx = ChargeFx.new(folder, U)
		fx:ring(AT, ACCENT, 0.07, 0.1, 0.4)
		fx:ring(AT, ACCENT, 0.06, 0.12, 0.25)
		expect.equal(fx:ringCount(), 2)
		fx:step(0.3)
		expect.equal(fx:ringCount(), 1) -- the 0.25 s one is gone
		fx:step(0.2)
		expect.equal(fx:ringCount(), 0)
		expect.equal(#named(folder, "ChargeRing"), 0)
		fx:ring(AT, ACCENT, 0.07, 0.1, 0.4)
		fx:glow(AT, 0.1, ACCENT, 0.3)
		fx:clear()
		expect.equal(fx:ringCount(), 0)
		expect.equal(named(folder, "ChargeGlow")[1].Transparency, 1)
		fx:destroy()
		expect.equal(#folder:GetChildren(), 0)
		folder:Destroy()
	end)
end
