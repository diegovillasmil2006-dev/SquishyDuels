--!strict
-- ThrowVfx_Test: unit tests for StarterPlayerScripts.Client.Anim.ThrowVfx's pure helpers (VFX Studio's emit contract)
-- and the library it plays, ReplicatedStorage.SD_ThrowVfx (made by SDTools.Builders.ThrowVfxBuilder, tuned in VFX
-- Studio). Server only (ServerStorage.UnitTest). The library checks read the place's library as it is.
-- Contract:
--   * emitPlan: VFX Studio's defaults (no delay, Emit(1), no duration), its attributes, our multiplier rounded with at
--     least 1 for a template that asked for particles, 0 kept;
--   * feelAllowed: no list = every toy, else the named feels only; scaleSequence and tintSequence;
--   * the library: a Trails/<id> template for every Catalog squishy with at least one Trail and one flight emitter, the
--     seven bursts, every texture an engine rbxasset (no uploads), every SD_Feels name a real feel.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local BURSTS = { "Release", "Bounce", "Land", "Skid", "Settle", "Poof", "HandSwoosh" }

return function(t: Context)
	local expect = t.expect
	local ThrowVfx = t.requireClient("Anim/ThrowVfx")

	t.test("emitPlan follows VFX Studio's contract", function()
		local d, c, u = ThrowVfx.emitPlan({}, 1)
		expect.equal(d, 0)
		expect.equal(c, 1)
		expect.equal(u, 0)
		d, c, u = ThrowVfx.emitPlan({ EmitDelay = 0.2, EmitCount = 9, EmitDuration = 0 }, 1)
		expect.equal(d, 0.2)
		expect.equal(c, 9)
		expect.equal(u, 0)
		_, c = ThrowVfx.emitPlan({ EmitCount = 9 }, 0.5)
		expect.equal(c, 5)
		_, c = ThrowVfx.emitPlan({ EmitCount = 1 }, 0.25)
		expect.equal(c, 1)
		_, c = ThrowVfx.emitPlan({ EmitCount = 0 }, 1)
		expect.equal(c, 0)
		d, _, u = ThrowVfx.emitPlan({ EmitDelay = -1, EmitDuration = 1.5 }, 1)
		expect.equal(d, 0)
		expect.equal(u, 1.5)
	end)

	t.test("feelAllowed, scaleSequence and tintSequence", function()
		expect.equal(ThrowVfx.feelAllowed(nil, "foam"), true)
		expect.equal(ThrowVfx.feelAllowed("", nil), true)
		expect.equal(ThrowVfx.feelAllowed("jelly,mochi", "mochi"), true)
		expect.equal(ThrowVfx.feelAllowed("jelly, mochi", "foam"), false)
		expect.equal(ThrowVfx.feelAllowed("jelly", nil), false)
		local seq = ThrowVfx.scaleSequence(NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1, 0.5),
			NumberSequenceKeypoint.new(1, 2, 0),
		}), 2)
		expect.near(seq.Keypoints[1].Value, 2, 1e-6)
		expect.near(seq.Keypoints[1].Envelope, 1, 1e-6)
		expect.near(seq.Keypoints[2].Value, 4, 1e-6)
		local accent = Color3.fromRGB(200, 100, 50)
		local tint = ThrowVfx.tintSequence(accent)
		expect.truthy(tint.Keypoints[1].Value == accent)
		local last = tint.Keypoints[#tint.Keypoints].Value
		expect.truthy(last.R > accent.R and last.G > accent.G and last.B > accent.B)
	end)

	t.test("the library has every squishy's trail and the seven bursts, engine textures only", function()
		local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SD_ThrowVfx")
		expect.truthy(lib ~= nil)
		if lib == nil then
			return
		end
		local Catalog = t.requireShared("Catalog")
		local Config = t.requireShared("Config")
		local trails = lib:FindFirstChild("Trails")
		local bursts = lib:FindFirstChild("Bursts")
		expect.truthy(trails ~= nil and bursts ~= nil)
		for _, def in Catalog.list() do
			local template = trails and trails:FindFirstChild(def.id)
			expect.truthy(template ~= nil and template:IsA("BasePart"))
			if template then
				local ribbons, flight = 0, 0
				for _, d in template:GetDescendants() do
					if d:IsA("Trail") then
						ribbons += 1
					elseif d:IsA("ParticleEmitter") and d:GetAttribute("SD_Role") == "flight" then
						flight += 1
					end
				end
				expect.truthy(ribbons >= 1 and flight >= 1)
			end
		end
		for _, name in BURSTS do
			expect.truthy(bursts ~= nil and bursts:FindFirstChild(name) ~= nil)
		end
		for _, d in lib:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				expect.truthy(string.sub(d.Texture, 1, 11) == "rbxasset://")
				local feels = d:GetAttribute("SD_Feels")
				if type(feels) == "string" then
					for name in string.gmatch(feels, "[^,%s]+") do
						expect.truthy(Config.Anim.rig.feels[name] ~= nil)
					end
				end
			end
		end
	end)
end
