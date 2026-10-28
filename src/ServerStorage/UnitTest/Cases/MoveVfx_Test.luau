--!strict
-- MoveVfx_Test: unit tests for StarterPlayerScripts.Client.Anim.MoveVfx and Anim.Afterimage's pure helpers, and the
-- library MoveVfx plays, ReplicatedStorage.SD_MoveVfx (made by SDTools.Builders.MoveVfxBuilder, tuned in VFX Studio;
-- 2026-10-15 dash + double jump overhaul). Server only (ServerStorage.UnitTest). The library checks read the place's
-- library as it is.
-- Contract:
--   * trailColor: white -> tint, or tint -> white when tintFirst;
--   * Afterimage.fadeAt: the start value at 0, fully transparent at the end, never past it;
--   * the library: every template the controllers play, an invisible anchored Part each; every texture an engine
--     rbxasset (no uploads); every SD_Role "while" or none, every SD_Tint "team" or none; a burst's particles at most
--     Config.Vfx.Budgets.liveParticlesPerEffect (its EmitCounts); the speed lines' streak emitters all there;
--   * the builder makes the same template set (a reset brings every template back).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TEMPLATES = {
	"Dash/Start",
	"Dash/Body",
	"Dash/Skid",
	"Dash/Plant",
	"Dash/SpeedLines",
	"DoubleJump/Burst",
	"DoubleJump/Body",
	"DoubleJump/FootTrail",
	"DoubleJump/Land",
}
local BURSTS = { "Dash/Start", "Dash/Plant", "DoubleJump/Burst", "DoubleJump/Land" }

return function(t: Context)
	local expect = t.expect
	local MoveVfx = t.requireClient("Anim/MoveVfx")
	local Afterimage = t.requireClient("Anim/Afterimage")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")

	local function find(root: Instance, path: string): Instance?
		local node: Instance? = root
		for name in string.gmatch(path, "[^/]+") do
			node = if node then node:FindFirstChild(name) else nil
		end
		return node
	end

	t.test("trailColor and the ghost fade", function()
		local tint = Palette.DashGlowMint
		local after = MoveVfx.trailColor(tint, false)
		expect.equal(after.Keypoints[1].Value, Palette.White)
		expect.equal(after.Keypoints[#after.Keypoints].Value, tint)
		local first = MoveVfx.trailColor(tint, true)
		expect.equal(first.Keypoints[1].Value, tint)
		expect.near(Afterimage.fadeAt(0, 0.45, 0.3), 0.45, 1e-9)
		expect.near(Afterimage.fadeAt(0.3, 0.45, 0.3), 1, 1e-9)
		expect.near(Afterimage.fadeAt(9, 0.45, 0.3), 1, 1e-9)
		expect.truthy(Afterimage.fadeAt(0.15, 0.45, 0.3) < 0.8)
		expect.equal(Afterimage.fadeAt(0.1, 0.45, 0), 1)
	end)

	t.test("the library has every template, engine textures only, within the particle budget", function()
		local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SD_MoveVfx")
		expect.truthy(lib ~= nil)
		if lib == nil then
			return
		end
		for _, path in TEMPLATES do
			local template = find(lib, path)
			expect.truthy(template ~= nil and template:IsA("BasePart"))
			if template and template:IsA("BasePart") then
				expect.truthy(template.Anchored and template.Transparency == 1 and not template.CanCollide)
			end
		end
		local feel = lib:FindFirstChild("Feel") -- the physics upgrade's templates: FeelFx_Test checks them
		for _, d in lib:GetDescendants() do
			if feel and d:IsDescendantOf(feel) then
				continue
			end
			if d:IsA("ParticleEmitter") then
				expect.truthy(string.sub(d.Texture, 1, 11) == "rbxasset://")
				local role = d:GetAttribute("SD_Role")
				expect.truthy(role == nil or role == "while")
			end
			if d:IsA("ParticleEmitter") or d:IsA("Trail") then
				local tint = d:GetAttribute("SD_Tint")
				expect.truthy(tint == nil or tint == "team")
			end
		end
		local budget = Config.Vfx.Budgets.liveParticlesPerEffect
		for _, path in BURSTS do
			local template = find(lib, path)
			local total = 0
			if template then
				for _, d in template:GetDescendants() do
					if d:IsA("ParticleEmitter") and d:GetAttribute("SD_Role") == nil then
						local count = d:GetAttribute("EmitCount")
						total += if type(count) == "number" then count else 1
					end
				end
			end
			expect.truthy(total > 0 and total <= budget)
		end
		local lines = find(lib, "Dash/SpeedLines")
		local streaks = 0
		if lines then
			for _, d in lines:GetDescendants() do
				if d:IsA("ParticleEmitter") and d:GetAttribute("SD_Role") == "while" then
					streaks += 1
				end
			end
		end
		expect.equal(streaks, 8)
	end)

	t.test("the builder makes the same templates (a reset brings them all back)", function()
		local SDTools = game:GetService("ServerStorage"):FindFirstChild("SDTools")
		local builders = SDTools and SDTools:FindFirstChild("Builders")
		local module = builders and builders:FindFirstChild("MoveVfxBuilder")
		local throw = builders and builders:FindFirstChild("ThrowVfxBuilder")
		expect.truthy(module ~= nil and throw ~= nil)
		if module == nil or throw == nil then
			return
		end
		-- Fresh copies side by side (the builder requires its sibling), so the require cache never serves an old one.
		local holder = Instance.new("Folder")
		throw:Clone().Parent = holder
		local copy = module:Clone()
		copy.Parent = holder
		local built = (require :: any)(copy).build(nil)
		for _, path in TEMPLATES do
			expect.truthy(find(built, path) ~= nil)
		end
		built:Destroy()
		holder:Destroy()
	end)
end
