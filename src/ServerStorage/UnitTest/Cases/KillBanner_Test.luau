--!strict
-- KillBanner_Test: unit tests for the kill banners (2026-10-16, VillasmilGaming: Valorant-style kill banners, kill
-- sounds and kill effects): Shared.Art.KillStyle, Client.UI.KillBannerFormat, Client.Anim.KillVfx's pure helpers,
-- Client.Controllers.KillBannerController's pure helpers, the kill VFX library ReplicatedStorage.SD_KillVfx (made by
-- SDTools.Builders.KillVfxBuilder for the VFX Studio plugin) and the Config they read. Server only
-- (ServerStorage.UnitTest), Edit mode. The library checks read the place's library as it is.
-- Contract:
--   * KillStyle: standard first, six sets; every colour a Palette token, every picture an AssetTable image key with an
--     id, every sound an AssetTable sound key; each custom set names its squishy; resolve falls back to standard;
--   * tierFor: 1..6, every streak past 6 is 6 (the 6k banner repeats until the player is knocked out);
--   * setFor: a Common / Uncommon squishy -> standard, a squishy above Uncommon -> its own set, unknown -> standard;
--   * slots: k ornaments for k K.O.s (k <= 5) at slotAngles, the newest last; at 6 all five plus the crown pieces
--     (count per side, mirrored), which are the newest;
--   * the sound regions sit in the sheet's slots and never overlap; discPx stays between its bounds;
--   * pose: the medallion pops past 1 and settles to 1, holds, then shrinks and fades; a replaced banner never starts
--     from 0 (no blink); ornaments appear before the newest pops; every piece is gone at the end; ReducedMotion keeps
--     scale 1 and only fades;
--   * duel streak: +1 per K.O. dealt, 0 when knocked out or a duel is lost; matchKill takes the highest of the
--     player's K.O.s in a batch and notices their own K.O.;
--   * KillVfx: tierAllows, bannerRadius;
--   * the library: a Banner and a Kill template for every set, invisible anchored Parts, every emitter's texture an
--     engine file or an AssetTable img.kill.* id, banner emitters LockedToPart with SD_MinTier in 1..6, at most
--     Config.Vfx.Budgets.liveParticlesPerEffect particles per template (all its tiers at once), and the builder makes
--     the same template set (a reset brings every template back).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(t: Context)
	local expect = t.expect
	local KillStyle = t.requireShared("Art/KillStyle")
	local Palette = t.requireShared("Art/Palette")
	local AssetTable = t.requireShared("AssetTable")
	local Catalog = t.requireShared("Catalog")
	local Rarity = t.requireShared("Rarity")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local Format = t.requireClient("UI/KillBannerFormat")
	local KillVfx = t.requireClient("Anim/KillVfx")
	local Controller = t.requireClient("Controllers/KillBannerController")
	local CFG = Config.UI.KillBanner
	local AUDIO = Config.Audio.killBanner

	local function imageKnown(key: string?)
		expect.truthy(type(key) == "string" and AssetTable.image(key :: string) ~= nil)
	end

	t.test("KillStyle: six sets, Palette colours, pictures with ids, a sound sheet each", function()
		expect.equal(KillStyle.IDS[1], KillStyle.STANDARD)
		expect.equal(#KillStyle.IDS, 6)
		for _, id in KillStyle.IDS do
			local style = KillStyle.get(id)
			expect.truthy(style ~= nil)
			if style == nil then
				continue
			end
			expect.equal(style.id, id)
			for _, token in { style.disc, style.ring, style.glow, style.frame.tint, style.crownFrame.tint } do
				expect.equal(typeof(Palette[token]), "Color3")
			end
			imageKnown(style.frame.image)
			imageKnown(style.crownFrame.image)
			for _, piece in { style.ornament, style.crown } do
				if piece.donut or piece.bubble then
					expect.equal(piece.image, nil)
				else
					imageKnown(piece.image)
				end
				if piece.tint then
					expect.equal(typeof(Palette[piece.tint]), "Color3")
				end
				expect.truthy(piece.size > 0 and piece.size < 1)
			end
			expect.truthy(#AssetTable.soundChoices(style.sound) > 0)
			expect.equal(style.bannerVfx, "Banner/" .. id)
			expect.equal(style.killVfx, "Kill/" .. id)
			expect.truthy(Strings.resolve(style.nameKey) ~= nil)
			if id == KillStyle.STANDARD then
				expect.equal(style.squishyId, nil)
				imageKnown(style.centerImage)
			else
				expect.truthy(Catalog.get(style.squishyId) ~= nil)
			end
		end
		expect.equal(KillStyle.resolve("dragon_blaze"), "dragon_blaze")
		expect.equal(KillStyle.resolve("epic_pending"), KillStyle.STANDARD)
		expect.equal(KillStyle.resolve(nil), KillStyle.STANDARD)
		expect.equal(KillStyle.resolve(42), KillStyle.STANDARD)
		expect.equal(KillStyle.get("nope"), nil)
	end)

	t.test("tierFor: 1 to 6, and every K.O. past the 6th is the 6k banner", function()
		expect.equal(CFG.tiers, 6)
		expect.equal(Format.tierFor(1), 1)
		expect.equal(Format.tierFor(5), 5)
		expect.equal(Format.tierFor(6), 6)
		expect.equal(Format.tierFor(7), 6)
		expect.equal(Format.tierFor(42), 6)
		expect.equal(Format.tierFor(0), 1)
		expect.equal(Format.tierFor(-3), 1)
		expect.equal(Format.tierFor(nil), 1)
		expect.equal(Format.tierFor(0 / 0), 1)
		expect.equal(Format.tierFor(2.7), 2)
	end)

	t.test("setFor: Common and Uncommon share standard, every squishy above Uncommon has its own", function()
		local uncommon = Rarity.index("Uncommon")
		local seen: { [string]: boolean } = {}
		for _, def in Catalog.list() do
			local set = Format.setFor(def.id)
			if Rarity.index(def.rarity) <= uncommon then
				expect.equal(set, KillStyle.STANDARD)
			else
				expect.truthy(set ~= KillStyle.STANDARD)
				expect.falsy(seen[set])
				seen[set] = true
				expect.equal(KillStyle.get(set).squishyId, def.id)
			end
		end
		expect.equal(Format.setFor("not_a_squishy"), KillStyle.STANDARD)
		expect.equal(Format.setFor(nil), KillStyle.STANDARD)
	end)

	t.test("slots: one ornament per K.O. up to 5, the 6k crown on top of all five", function()
		for tier = 1, 5 do
			local slots = Format.slots(tier)
			expect.equal(#slots, tier)
			for i, slot in slots do
				expect.equal(slot.kind, "ornament")
				expect.equal(slot.angle, CFG.slotAngles[i])
				expect.equal(slot.order, i)
				expect.equal(slot.newest, i == tier)
			end
		end
		local six = Format.slots(6, 3, 20)
		expect.equal(#six, 5 + 6)
		local crowns, left, right = 0, 0, 0
		for i, slot in six do
			if i <= 5 then
				expect.equal(slot.kind, "ornament")
				expect.falsy(slot.newest)
			else
				expect.equal(slot.kind, "crown")
				expect.truthy(slot.newest)
				crowns += 1
				if slot.angle < 0 then
					left += slot.angle
				else
					right += slot.angle
				end
			end
		end
		expect.equal(crowns, 6)
		expect.near(left, -right, 1e-9) -- mirrored
		expect.near(right / 3, CFG.crownAngle, 1e-9) -- fanned around the crown angle
		expect.deepEqual(Format.slots(9, 1, 0), Format.slots(6, 1, 0)) -- past 6: the same banner
	end)

	t.test("sound regions sit in their slots; the disc stays in its bounds", function()
		expect.equal(AUDIO.tiers, CFG.tiers)
		expect.truthy(AUDIO.soundSeconds > 0 and AUDIO.soundSeconds <= AUDIO.slotSeconds)
		local lastFinish = -1
		for tier = 1, AUDIO.tiers do
			local start, finish = Format.soundRegion(tier)
			expect.near(start, (tier - 1) * AUDIO.slotSeconds, 1e-9)
			expect.truthy(finish > start and start >= lastFinish)
			lastFinish = finish
		end
		local a6, b6 = Format.soundRegion(6)
		local a9, b9 = Format.soundRegion(9)
		expect.equal(a9, a6)
		expect.equal(b9, b6)
		expect.equal(Format.discPx(1080), CFG.discPx)
		expect.equal(Format.discPx(0), CFG.discMinPx)
		expect.equal(Format.discPx(0 / 0), CFG.discMinPx)
		local phone = Format.discPx(375)
		expect.truthy(phone >= CFG.discMinPx and phone <= CFG.discPx)
		expect.truthy(Format.centerYShare(true) < Format.centerYShare(false))
		expect.truthy(Format.centerYShare(false) < 0.9)
	end)

	t.test("pose: pop, settle, hold, shrink; a replaced banner never blinks; ReducedMotion only fades", function()
		local slots = Format.slots(3)
		local total = Format.totalSeconds()
		expect.near(total, CFG.introSeconds + CFG.holdSeconds + CFG.outroSeconds, 1e-9)
		local start = Format.pose(0, slots, false, false, 3)
		expect.near(start.medScale, 0, 1e-9)
		local peak = 0
		for i = 0, 40 do
			peak = math.max(peak, Format.pose(CFG.introSeconds * i / 40, slots, false, false, 3).medScale)
		end
		expect.truthy(peak > 1.1 and peak <= CFG.popScale + 1e-6)
		local hold = Format.pose(CFG.introSeconds + CFG.holdSeconds / 2, slots, false, false, 3)
		expect.near(hold.medScale, 1, 1e-9)
		expect.near(hold.medFade, 0, 1e-9)
		expect.near(hold.flashFade, 1, 1e-9)
		for _, piece in hold.pieces do
			expect.near(piece.scale, 1, 1e-9)
			expect.near(piece.fade, 0, 1e-9)
		end
		-- the older ornaments are out before the newest pops
		local early = Format.pose(CFG.newestAt - 0.01, slots, false, false, 3)
		expect.truthy(early.pieces[1].scale > 0)
		expect.near(early.pieces[3].scale, 0, 1e-9)
		local newestPeak = 0
		for i = 0, 40 do
			newestPeak = math.max(newestPeak, Format.pose(CFG.newestAt + 0.2 * i / 40, slots, false, false, 3).pieces[3].scale)
		end
		expect.truthy(newestPeak > 1.3)
		local done = Format.pose(total + 0.01, slots, false, false, 3)
		expect.truthy(done.done)
		expect.near(done.medFade, 1, 1e-9)
		for _, piece in done.pieces do
			expect.truthy(piece.fade >= 0.999 or piece.scale <= 0.001)
		end
		expect.falsy(Format.pose(total - 0.05, slots, false, false, 3).done)
		-- replaced: starts visible at replaceFromScale
		local again = Format.pose(0, slots, true, false, 3)
		expect.near(again.medScale, CFG.replaceFromScale, 1e-9)
		expect.near(again.medFade, 0, 1e-9)
		-- the crown frame only at 6
		expect.near(Format.pose(1, slots, false, false, 3).crownFrameFade, 1, 1e-9)
		expect.near(Format.pose(1, Format.slots(6), false, false, 6).crownFrameFade, 0, 1e-9)
		-- ReducedMotion
		for _, at in { 0.01, 0.5, 1.2, total - 0.01 } do
			local pose = Format.pose(at, slots, false, true, 3)
			expect.equal(pose.medScale, 1)
			expect.equal(pose.frameTurn, 0)
			expect.equal(pose.flashFade, 1)
			for _, piece in pose.pieces do
				expect.equal(piece.scale, 1)
			end
		end
		expect.near(Format.pose(1, slots, false, true, 3).medFade, 0, 1e-9)
		expect.truthy(Format.pose(total, slots, false, true, 3).done)
	end)

	t.test("streaks: duel +1 per K.O., 0 when knocked out or a duel is lost; a match batch's best", function()
		expect.equal(Controller.nextDuelStreak(0, "dealt"), 1)
		expect.equal(Controller.nextDuelStreak(6, "dealt"), 7)
		expect.equal(Controller.nextDuelStreak(7, "knockedOut"), 0)
		expect.equal(Controller.nextDuelStreak(3, "lost"), 0)
		local ME, THEM, OTHER = 11, 22, 33
		local best, out = Controller.matchKill({
			{ kind = "ko", victim = THEM, by = ME, streak = 4 },
			{ kind = "ko", victim = OTHER, by = ME, streak = 5 },
			{ kind = "ko", victim = OTHER, by = THEM, streak = 9 },
		}, ME)
		expect.equal(best, 5)
		expect.falsy(out)
		best, out = Controller.matchKill({ { kind = "ko", victim = ME, by = THEM, streak = 2 } }, ME)
		expect.equal(best, nil)
		expect.truthy(out)
		best, out = Controller.matchKill({ { kind = "ko", victim = THEM, cause = "storm" }, { kind = "other" } }, ME)
		expect.equal(best, nil)
		expect.falsy(out)
		best = Controller.matchKill({ { kind = "ko", victim = THEM, by = ME } }, ME)
		expect.equal(best, 1) -- an older server without streaks: a 1k banner
	end)

	t.test("KillVfx: the tier gate and the banner's radius", function()
		expect.truthy(KillVfx.tierAllows(nil, 1))
		expect.truthy(KillVfx.tierAllows(3, 3))
		expect.falsy(KillVfx.tierAllows(3, 2))
		expect.truthy(KillVfx.tierAllows(6, 6))
		expect.truthy(KillVfx.tierAllows("x", 1))
		-- a 108 px disc on a 1080 px viewport, FOV 70°, 3.2 studs out: (54 / 1080) of the view's height there
		local radius = KillVfx.bannerRadius(108, 1080, 70, 3.2)
		expect.near(radius, 54 / 1080 * 2 * 3.2 * math.tan(math.rad(35)), 1e-9)
		expect.equal(KillVfx.bannerRadius(0, 1080, 70, 3.2), 0)
		expect.equal(KillVfx.bannerRadius(108, 0, 70, 3.2), 0)
		expect.truthy(Config.Vfx.KillFx.burstDepthStuds > 0.5)
	end)

	local function find(root: Instance, path: string): Instance?
		local node: Instance? = root
		for name in string.gmatch(path, "[^/]+") do
			node = if node then node:FindFirstChild(name) else nil
		end
		return node
	end

	local function particles(template: Instance): number
		local count = 0
		for _, d in template:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				local asked = d:GetAttribute("EmitCount")
				local duration = d:GetAttribute("EmitDuration")
				if type(duration) == "number" and duration > 0 then
					count += math.ceil(d.Rate * duration)
				else
					count += if type(asked) == "number" then asked else 1
				end
			end
		end
		return count
	end

	local function checkLibrary(lib: Instance)
		local allowed: { [string]: boolean } = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "image" and string.sub(slot.key, 1, 9) == "img.kill." then
				allowed[AssetTable.image(slot.key)] = true
			end
		end
		for _, id in KillStyle.IDS do
			local style = KillStyle.get(id)
			for _, path in { style.bannerVfx, style.killVfx } do
				local template = find(lib, path)
				expect.truthy(template ~= nil and template:IsA("BasePart"))
				if template and template:IsA("BasePart") then
					expect.truthy(template.Anchored and template.Transparency == 1 and not template.CanCollide)
					expect.truthy(particles(template) <= Config.Vfx.Budgets.liveParticlesPerEffect)
					local banner = string.sub(path, 1, 7) == "Banner/"
					local emitters = 0
					for _, d in template:GetDescendants() do
						if d:IsA("ParticleEmitter") then
							emitters += 1
							expect.truthy(string.sub(d.Texture, 1, 11) == "rbxasset://" or allowed[d.Texture] == true)
							expect.falsy(d.Enabled)
							local minTier = d:GetAttribute("SD_MinTier")
							expect.truthy(minTier == nil or (type(minTier) == "number" and minTier >= 1 and minTier <= 6))
							if banner then
								expect.truthy(d.LockedToPart)
							else
								expect.equal(minTier, nil)
							end
						end
					end
					expect.truthy(emitters > 0)
				end
			end
		end
	end

	t.test("the library: a banner burst and a kill effect for every set, within the budget", function()
		local lib = ReplicatedStorage:FindFirstChild("SD_KillVfx")
		expect.truthy(lib ~= nil)
		if lib then
			checkLibrary(lib)
		end
	end)

	t.test("the builder makes every template (a reset brings them back)", function()
		local builders = ServerStorage:FindFirstChild("SDTools")
		local module = builders and builders:FindFirstChild("Builders")
		module = module and module:FindFirstChild("KillVfxBuilder")
		expect.truthy(module ~= nil and module:IsA("ModuleScript"))
		if module == nil then
			return
		end
		local Builder = require(module:Clone() :: any) :: any
		local root = Builder.build(nil, AssetTable)
		checkLibrary(root)
		root:Destroy()
	end)
end
