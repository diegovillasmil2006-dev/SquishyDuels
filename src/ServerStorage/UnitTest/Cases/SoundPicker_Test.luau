--!strict
-- SoundPicker_Test: unit tests for the pure merge of StarterPlayerScripts.Client.Studio.SoundPicker (the Studio sound
-- picker's "load" command). Server only (ServerStorage.UnitTest). Edit mode: init() is not called (no BindableFunction,
-- no panel, nothing plays).
-- Contract (DESIGN §18.7 steps 6 and 8, the L6 readings): tools/mcp/sound-picker.mjs injects candidates.json in chunks
-- of 10 keys, the first with reset = true. Every chunk adds its keys; the model is built from the decisions of the keys
-- loaded so far only (no "decision for unknown key" for a later chunk's key); this Play session's own decisions (and
-- undos) win over the injected files for every chunk of the same round; another builtAt starts a new round.
-- The ids here are small made-up numbers (never real asset ids).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SoundPicker = t.requireClient("Studio/SoundPicker")
	local expect = t.expect

	local function approved(id: number): { [string]: any }
		return { status = "approved", picks = { { id = id, volume = 0.8 } } }
	end

	local function chunk(keys: { string }, decisions: { [string]: any }?, reset: boolean?, builtAt: string?): any
		local list = {}
		for _, key in keys do
			table.insert(list, { key = key, candidates = {} })
		end
		return { version = 1, builtAt = builtAt or "round-1", reset = reset, keys = list, decisions = decisions or {} }
	end

	local function keysOf(state: any): { string }
		local list = {}
		for _, item in state.keys do
			table.insert(list, item.key)
		end
		return list
	end

	t.test("chunks add their keys; a later chunk's decision waits until its key is loaded", function()
		local file = { ["sfx.squish"] = approved(11), ["ui.click"] = approved(33) }
		local state, known, skipped = SoundPicker.mergeLoad(nil, chunk({ "sfx.squish", "sfx.pop" }, file, true), nil)
		expect.deepEqual(keysOf(state), { "sfx.squish", "sfx.pop" })
		expect.deepEqual(known, { ["sfx.squish"] = approved(11) })
		expect.deepEqual(skipped, {})
		local state2, known2 = SoundPicker.mergeLoad(state, chunk({ "ui.click" }, file, false), nil)
		expect.equal(state2, state) -- the same round goes on
		expect.deepEqual(keysOf(state2), { "sfx.squish", "sfx.pop", "ui.click" })
		expect.deepEqual(known2, { ["sfx.squish"] = approved(11), ["ui.click"] = approved(33) })
	end)

	t.test(
		"a re-inject in the same Play session: its own decisions and undos win over the files in every chunk",
		function()
			local round = SoundPicker.mergeLoad(nil, chunk({ "sfx.squish", "sfx.pop", "ui.click" }, {}, true), nil)
			-- The panel's export: squish approved, pop undone (listed with no decision), click approved.
			local exported = {
				version = 1,
				builtAt = "round-1",
				keys = { "sfx.squish", "sfx.pop", "ui.click" },
				decisions = { ["sfx.squish"] = approved(11), ["ui.click"] = approved(44) },
			}
			local file = {
				["sfx.pop"] = approved(22),
				["ui.click"] = { status = "skipped" },
				["ui.hover"] = approved(55),
			}
			local state, known = SoundPicker.mergeLoad(round, chunk({ "sfx.squish", "sfx.pop" }, file, true), exported)
			expect.deepEqual(keysOf(state), { "sfx.squish", "sfx.pop" })
			expect.deepEqual(known, { ["sfx.squish"] = approved(11) }) -- pop's undo beats the file
			-- The next chunk of the same inject: the model now holds only the first chunk's keys.
			local partial = {
				version = 1,
				builtAt = "round-1",
				keys = { "sfx.squish", "sfx.pop" },
				decisions = { ["sfx.squish"] = approved(11) },
			}
			local state2, known2 = SoundPicker.mergeLoad(state, chunk({ "ui.click", "ui.hover" }, file, false), partial)
			expect.deepEqual(keysOf(state2), { "sfx.squish", "sfx.pop", "ui.click", "ui.hover" })
			expect.deepEqual(known2, {
				["sfx.squish"] = approved(11),
				["ui.click"] = approved(44), -- the session's pick, not the file's skip
				["ui.hover"] = approved(55), -- never in the session: the file's
			})
		end
	)

	t.test("another builtAt starts a new round from the files alone", function()
		local round = SoundPicker.mergeLoad(nil, chunk({ "sfx.squish" }, { ["sfx.squish"] = approved(11) }, true), nil)
		local state, known = SoundPicker.mergeLoad(round, chunk({ "sfx.pop" }, {}, false, "round-2"), nil)
		expect.equal(state.builtAt, "round-2")
		expect.deepEqual(keysOf(state), { "sfx.pop" })
		expect.deepEqual(known, {})
	end)

	t.test("a key sent again replaces its entry in place; an entry without a key is reported", function()
		local raw = chunk({ "sfx.squish", "sfx.pop" }, {}, true)
		table.insert(raw.keys, { label = "no key" })
		local state, _, skipped = SoundPicker.mergeLoad(nil, raw, nil)
		expect.deepEqual(skipped, { "a key entry has no key" })
		local again = { version = 1, builtAt = "round-1", keys = { { key = "sfx.squish", label = "new" } } }
		local state2 = SoundPicker.mergeLoad(state, again, nil)
		expect.deepEqual(keysOf(state2), { "sfx.squish", "sfx.pop" })
		expect.equal(state2.keys[1].label, "new")
	end)
end
