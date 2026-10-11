--!strict
-- IdleRig_Test: unit tests for StarterPlayerScripts.Client.Anim.IdleRig (squishy overhaul spec 2026-10-09 §3.2 "Idle
-- life"): the box reveal's and the Collection displays' breathing, blink and face lock through one SquishRig and the
-- model's SquishDeformer. Server only (ServerStorage.UnitTest). Builds real blueprint models (Art/SquishyBuilder with the
-- B fallback for rounded boxes) and never parents them.
-- Contract:
--   * breath(t, phase, reduced): the lobby breath (Config.Anim.held.lobbyIdle ampY, periodSeconds), one-sided like the
--     lobby breathers (S.Y in [1, 1 + ampY], S.X = S.Z = 1 - (S.Y - 1)/2, so the foot never lifts off its stand),
--     exactly (1, 1, 1) at its rest and under ReducedMotion;
--   * new() is nil for an id without a squishy motion row, and it attaches nothing and writes nothing until start();
--   * start(wow) attaches the deformer at the built pose and shows the wow face that long, then the normal face;
--   * blink = false never blinks (the Lavender silhouettes); blink = true blinks within the rig's 2-5 s;
--   * rest() puts every value back bit for bit, and step() picks up again;
--   * breathNow() is the breath shown now (S.Y = 1 + ampY × amount, the fade-in included) and whether it rises; 0 before
--     a start, at rest and under ReducedMotion;
--   * a "hero" life counts in Anim/HeroRigs from start() until handOff() or destroy(); a "near" one never;
--   * handOff() returns the rig, stops every write here and keeps the deformer attached for the next owner (Inspect);
--   * destroy() rests the model and detaches the deformer.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

type PartState = { cframe: CFrame, size: Vector3, transparency: number, scale: Vector3?, offset: Vector3? }

local FRAME = 1 / 60

-- The looks each face state hides (spec §3.2 table).
local HIDDEN: { [string]: { [string]: boolean } } = {
	normal = { squishEye = true, squishMouth = true, tongue = true },
	squish = { eye = true, eyeArc = true, shine = true, mouth = true },
	wow = { mouth = true, squishEye = true, tongue = true },
}

return function(t: Context)
	local IdleRig = t.requireClient("Anim/IdleRig")
	local SquishDeformer = t.requireClient("Anim/SquishDeformer")
	local Builder = t.requireShared("Art/SquishyBuilder")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local LOBBY = Config.Anim.held.lobbyIdle

	local function build(id: string): Model
		return Builder.build(id, "Viewport", 1, { roundedBox = false })
	end

	local function snapshot(model: Model): { [BasePart]: PartState }
		local states: { [BasePart]: PartState } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				local mesh = descendant:FindFirstChildWhichIsA("DataModelMesh")
				states[descendant] = {
					cframe = descendant.CFrame,
					size = descendant.Size,
					transparency = descendant.Transparency,
					scale = if mesh then mesh.Scale else nil,
					offset = if mesh then mesh.Offset else nil,
				}
			end
		end
		return states
	end

	-- The first part whose state differs from `before` (nil when every value is back bit for bit).
	local function firstChange(before: { [BasePart]: PartState }): string?
		for part, state in before do
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if
				part.CFrame ~= state.cframe
				or part.Size ~= state.size
				or part.Transparency ~= state.transparency
				or (mesh ~= nil and (mesh.Scale ~= state.scale or mesh.Offset ~= state.offset))
			then
				return part.Name
			end
		end
		return nil
	end

	local function faceOf(model: Model): string?
		for state, hidden in HIDDEN do
			local matches = true
			for _, descendant in model:GetDescendants() do
				local look = descendant:GetAttribute("SD_Look")
				if descendant:IsA("BasePart") and type(look) == "string" then
					local wanted = if hidden[look] then 1 else 0
					if descendant.Transparency ~= wanted then
						matches = false
						break
					end
				end
			end
			if matches then
				return state
			end
		end
		return nil
	end

	t.test("breath: the one-sided lobby breath, exactly 1 at rest and under ReducedMotion", function()
		expect.equal(IdleRig.breath(0, 0, false), Vector3.one)
		expect.equal(IdleRig.breath(1.3, 0.4, true), Vector3.one)
		local top = 0
		for i = 0, 120 do
			local time = i * LOBBY.periodSeconds / 120
			local S = IdleRig.breath(time, 0.25, false)
			expect.truthy(S.Y >= 1 - 1e-6 and S.Y <= 1 + LOBBY.ampY + 1e-6)
			expect.near(S.X, 1 - (S.Y - 1) / 2, 1e-5)
			expect.near(S.Z, S.X, 1e-9)
			top = math.max(top, S.Y)
		end
		expect.near(top, 1 + LOBBY.ampY, 1e-3) -- reaches its full swell once a period
		-- One breath every lobbyIdle.periodSeconds.
		local a = IdleRig.breath(0.7, 0.1, false)
		local b = IdleRig.breath(0.7 + LOBBY.periodSeconds, 0.1, false)
		expect.near(a.Y, b.Y, 1e-5)
	end)

	t.test("new: nil without a squishy motion row; nothing is attached or written until start()", function()
		local gift = Builder.build("gift_box", "Viewport", 1, { roundedBox = false })
		expect.equal(IdleRig.new(gift, "gift_box"), nil)
		expect.equal(IdleRig.new(gift, "no_such_squishy"), nil)
		gift:Destroy()
		local model = build("kitty_bread")
		local base = snapshot(model)
		local life = IdleRig.new(model, "kitty_bread", { blink = true, seed = 3 })
		expect.truthy(life ~= nil)
		life:step(FRAME)
		life:step(FRAME)
		expect.falsy(life:isStarted())
		expect.equal(SquishDeformer.get(model), nil)
		expect.equal(firstChange(base), nil)
		life:destroy()
		model:Destroy()
	end)

	t.test("start(wow): the wow face for that long, then the normal face", function()
		local model = build("kitty_bread")
		local life = IdleRig.new(model, "kitty_bread", { blink = false, seed = 1 })
		life:start(IdleRig.REVEAL_WOW_SECONDS)
		expect.truthy(life:isStarted())
		expect.truthy(SquishDeformer.get(model) ~= nil)
		local time = 0
		while time < IdleRig.REVEAL_WOW_SECONDS - 0.05 do
			life:step(FRAME)
			time += FRAME
			expect.equal(faceOf(model), "wow")
		end
		while time < IdleRig.REVEAL_WOW_SECONDS + 0.05 do
			life:step(FRAME)
			time += FRAME
		end
		expect.equal(faceOf(model), "normal")
		-- A second start does not show the wow again.
		life:start(IdleRig.REVEAL_WOW_SECONDS)
		life:step(FRAME)
		expect.equal(faceOf(model), "normal")
		life:destroy()
		model:Destroy()
	end)

	t.test("blink = false never blinks; blink = true blinks within the rig's interval", function()
		local still = build("toast")
		local quiet = IdleRig.new(still, "toast", { blink = false, seed = 5 })
		quiet:start()
		local model = build("toast")
		local life = IdleRig.new(model, "toast", { blink = true, seed = 5 })
		life:start()
		local blinked = false
		local time = 0
		while time < Config.Anim.rig.blink.maxSeconds + 1 do
			quiet:step(FRAME)
			life:step(FRAME)
			time += FRAME
			expect.equal(quiet.out.blink, 1)
			blinked = blinked or life.out.blink < 1
		end
		expect.truthy(blinked)
		quiet:destroy()
		life:destroy()
		still:Destroy()
		model:Destroy()
	end)

	t.test("rest() puts every value back bit for bit; step() picks up again", function()
		local model = build("mochi_fox")
		local base = snapshot(model)
		local life = IdleRig.new(model, "mochi_fox", { blink = true, detail = "hero", seed = 2 })
		life:start(IdleRig.REVEAL_WOW_SECONDS)
		for _ = 1, 40 do
			life:step(FRAME)
		end
		expect.truthy(firstChange(base) ~= nil) -- breathing and the wow face
		life:rest()
		expect.equal(firstChange(base), nil)
		expect.truthy((SquishDeformer.get(model) :: any):isResting())
		for _ = 1, 40 do
			life:step(FRAME)
		end
		expect.truthy(firstChange(base) ~= nil)
		life:destroy()
		model:Destroy()
	end)

	t.test("the breath fades in from a start and from a rest, whatever its phase (no jump)", function()
		local model = build("toast")
		-- Half a period in: without the fade the breath would start at its full swell.
		local life = IdleRig.new(model, "toast", { blink = false, phase = 0.5, seed = 7 })
		life:start()
		life:step(FRAME)
		expect.near(life.out.S.Y, 1, 2e-3)
		local top = 0
		for _ = 1, 120 do
			life:step(FRAME)
			top = math.max(top, life.out.S.Y)
		end
		expect.truthy(top > 1 + LOBBY.ampY * 0.5) -- then it breathes in full
		life:rest()
		life:step(FRAME)
		expect.near(life.out.S.Y, 1, 2e-3)
		life:destroy()
		model:Destroy()
	end)

	t.test("breathNow: the breath shown now as an amount (fade-in included) and whether it rises", function()
		local function breathText(life: any): string
			local amount, rising = life:breathNow()
			return `{amount}/{rising}`
		end
		local model = build("toast")
		local life = IdleRig.new(model, "toast", { blink = false, phase = 0.3, seed = 8 })
		expect.equal(breathText(life), "0/true") -- not started: the rest pose
		life:start()
		local lastY: number? = nil
		local lastRising: boolean? = nil
		for _ = 1, 200 do
			life:step(FRAME)
			local amount, rising = life:breathNow()
			-- The rig rests (no squeeze), so the shown S.Y is the breath alone.
			expect.near(life.out.S.Y, 1 + LOBBY.ampY * amount, 1e-5)
			if lastY ~= nil and math.abs(life.out.S.Y - lastY) > 1e-5 then
				expect.equal(life.out.S.Y > lastY, lastRising)
			end
			lastY, lastRising = life.out.S.Y, rising
		end
		life:rest()
		expect.equal(breathText(life), "0/true")
		life:destroy()
		local still = IdleRig.new(model, "toast", { blink = false, phase = 0.3, reduced = true, seed = 8 })
		still:start()
		still:step(FRAME * 30)
		expect.equal(breathText(still), "0/true") -- ReducedMotion: no breath
		still:destroy()
		model:Destroy()
	end)

	t.test("a hero life counts as a hero rig (HeroRigs) from start() until handOff() or destroy()", function()
		local HeroRigs = t.requireClient("Anim/HeroRigs")
		local before = HeroRigs.count()
		local model = build("mochi_fox")
		local hero = IdleRig.new(model, "mochi_fox", { detail = "hero", twist = "pivot", seed = 9 })
		expect.equal(HeroRigs.count(), before) -- nothing until it starts
		hero:start(IdleRig.REVEAL_WOW_SECONDS)
		hero:start(IdleRig.REVEAL_WOW_SECONDS)
		expect.equal(HeroRigs.count(), before + 1)
		local other = build("toast")
		local near = IdleRig.new(other, "toast", { seed = 10 })
		near:start()
		expect.equal(HeroRigs.count(), before + 1) -- a near life (the Collection) is not a hero
		local rig = hero:handOff()
		expect.equal(HeroRigs.count(), before) -- the next owner (Inspect) counts it from now on
		near:destroy()
		local again = IdleRig.new(other, "toast", { detail = "hero", seed = 11 })
		again:start()
		expect.equal(HeroRigs.count(), before + 1)
		again:destroy()
		expect.equal(HeroRigs.count(), before)
		local deformer = SquishDeformer.get(model)
		if deformer and rig then
			deformer:destroy()
		end
		model:Destroy()
		other:Destroy()
	end)

	t.test("handOff: returns the rig, writes nothing more here and keeps the deformer for the next owner", function()
		local model = build("butter")
		local life = IdleRig.new(model, "butter", { blink = true, twist = "pivot", seed = 4 })
		life:start(IdleRig.REVEAL_WOW_SECONDS)
		for _ = 1, 10 do
			life:step(FRAME)
		end
		local deformer = SquishDeformer.get(model)
		local rig = life:handOff()
		expect.truthy(rig ~= nil and type(rig.step) == "function")
		local held = snapshot(model)
		life:step(FRAME)
		life:rest()
		life:destroy()
		expect.equal(firstChange(held), nil)
		expect.equal(SquishDeformer.get(model), deformer)
		-- A second hand-off has nothing left to give.
		expect.equal(life:handOff(), nil)
		if deformer then
			deformer:destroy()
		end
		model:Destroy()
	end)

	t.test("destroy() rests the model and detaches the deformer", function()
		local model = build("cloud_bunny")
		local base = snapshot(model)
		local life = IdleRig.new(model, "cloud_bunny", { blink = true, detail = "near", seed = 6 })
		life:start()
		for _ = 1, 30 do
			life:step(FRAME)
		end
		life:destroy()
		expect.equal(firstChange(base), nil)
		expect.equal(SquishDeformer.get(model), nil)
		life:destroy() -- twice is safe
		model:Destroy()
	end)
end
