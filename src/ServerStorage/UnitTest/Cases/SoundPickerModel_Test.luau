--!strict
-- SoundPickerModel_Test: unit tests for StarterPlayerScripts.Client.Studio.SoundPickerModel (the Studio sound picker's
-- pure state). Server only (ServerStorage.UnitTest). Edit mode; no instances.
-- Contract (DESIGN §18.7, §18.10 L6): optional skips count as done, needsMore doesn't; the 37 keys in the 7 sections'
-- order, then spec phase 5's 10 moves keys in an 8th and the 16 Inspect showcase keys in a 9th (final polish
-- 2026-10-11); the 3-variant flow; undo; volume clamp and 0.1 steps; export/import round trip; an unknown key is reported;
-- only candidates whose preload is "Success" show.
-- The ids here are small made-up numbers (never real asset ids).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Model = t.requireClient("Studio/SoundPickerModel")
	local AssetTable = t.requireShared("AssetTable")
	local expect = t.expect

	local function candidate(id: number, preload: string?): { [string]: any }
		return {
			id = id,
			name = "Sample " .. tostring(id),
			creator = "Test",
			creatorType = "User",
			seconds = 0.3,
			publicDomain = true,
			assetTypeId = 3,
			query = "soft+squish",
			preload = preload or "Success",
			checkedAt = "2026-10-06",
			partner = false,
		}
	end

	local function entry(key: string, ids: { number }, extra: { [string]: any }?): { [string]: any }
		local list = {}
		for _, id in ids do
			table.insert(list, candidate(id))
		end
		local item: { [string]: any } = {
			key = key,
			section = "ignored",
			label = key,
			when = "when it happens",
			variantsWanted = 1,
			defaultVolume = 0.8,
			candidates = list,
		}
		if extra then
			for k, v in extra do
				item[k] = v
			end
		end
		return item
	end

	local function data(keys: { { [string]: any } }, decisions: { [string]: any }?, builtAt: string?): { [string]: any }
		return { version = 1, builtAt = builtAt or "round-1", keys = keys, decisions = decisions or {} }
	end

	t.test(
		"the order holds the 70 AssetTable sound keys in 10 sections of 5, 7, 6, 5, 4, 6, 4, 12, 16 and 5",
		function()
			local soundKeys: { [string]: boolean } = {}
			local count = 0
			for _, slot in AssetTable.all() do
				-- The knead's wax sounds (spec phase2-squeeze §3.10) are uploaded renders played by region, never
				-- picked; so are UI FINAL R2's two design renders (ui.pop, ui.levelTone: plan work/ui/PLAN.md §3) and
				-- the kill banner sheets (sfx.kill.*, 2026-10-16: original renders played by region).
				local render = slot.key == "ui.pop" or slot.key == "ui.levelTone" or string.sub(slot.key, 1, 9) == "sfx.kill."
				if slot.kind == "sound" and string.sub(slot.key, 1, 8) ~= "sfx.wax." and not render then
					soundKeys[slot.key] = true
					count += 1
				end
			end
			expect.equal(count, 70)
			expect.equal(#Model.ORDER, 70)
			local seen: { [string]: boolean } = {}
			local perSection = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
			for _, key in Model.ORDER do
				expect.truthy(soundKeys[key])
				expect.falsy(seen[key])
				seen[key] = true
				local section, runner = Model.infoOf(key)
				expect.truthy(runner)
				perSection[section] += 1
			end
			expect.deepEqual(perSection, { 5, 7, 6, 5, 4, 6, 4, 12, 16, 5 }) -- 8: + the 2026-10-15 overhaul's two
			expect.equal(Model.SECTION_COUNT, 10)
			expect.equal(Model.sectionName(1), "Squeezing")
			expect.equal(Model.sectionName(7), "Music and room sound")
			expect.equal(Model.ORDER[1], "sfx.squish")
			expect.equal(Model.ORDER[37], "amb.arena")
			expect.equal(Model.sectionName(8), "Dash and Epic ultimates") -- spec phase 5
			expect.equal(Model.ORDER[49], "sfx.ultBubblePop")
			expect.equal(Model.sectionName(9), "Inspect showcases") -- final polish 2026-10-11
			expect.equal(Model.ORDER[50], "sfx.inspect.flick")
			expect.equal(Model.ORDER[65], "sfx.inspect.blub")
			expect.equal(select(2, Model.infoOf("sfx.inspect.ring")), "plain")
			expect.equal(Model.sectionName(10), "Charge throw and catch") -- feature 1, 2026-10-11
			expect.equal(Model.ORDER[66], "sfx.chargeLoop")
			expect.equal(Model.ORDER[70], "sfx.crushBurst")
			expect.equal(select(2, Model.infoOf("sfx.catch")), "plain")
		end
	)

	t.test("keys load in the section order whatever the data order", function()
		local model, problems = Model.fromData(data({
			entry("amb.arena", { 1 }),
			entry("ui.click", { 2 }),
			entry("sfx.squish", { 3 }),
			entry("duel.go", { 4 }),
		}))
		expect.deepEqual(problems, {})
		expect.deepEqual(model:export().keys, { "sfx.squish", "ui.click", "duel.go", "amb.arena" })
		expect.equal(model:currentKey(), "sfx.squish")
		local done, total = model:progress()
		expect.equal(done, 0)
		expect.equal(total, 4)
	end)

	t.test("an unknown key is reported and left out", function()
		local model, problems = Model.fromData(data({
			entry("sfx.squish", { 1 }),
			entry("sfx.madeUp", { 2 }),
		}, { ["sfx.alsoMadeUp"] = { status = "skipped" } }))
		expect.equal(#problems, 2)
		expect.truthy(string.find(problems[1], "sfx.madeUp", 1, true))
		expect.truthy(string.find(problems[2], "sfx.alsoMadeUp", 1, true))
		local _, total = model:progress()
		expect.equal(total, 1)
		expect.deepEqual(model:problemList(), problems)
	end)

	t.test("only candidates whose preload is Success show; bad ids are reported", function()
		local raw = entry("sfx.squish", {})
		raw.candidates = {
			candidate(11, "Failure"),
			candidate(12),
			candidate(13, "Timeout"),
			{ id = 14, preload = "Success" },
			candidate(12), -- the same id twice shows once
			candidate(-5),
			candidate(2.5),
		}
		local model, problems = Model.fromData(data({ raw }))
		expect.equal(#problems, 2)
		local first, index, count = model:currentCandidate()
		expect.equal(count, 2)
		expect.equal(index, 1)
		expect.equal(first.id, 12)
		expect.equal(model:nextCandidate().id, 14)
		local ok = model:approve("sfx.squish", 11, 0.8)
		expect.falsy(ok)
	end)

	t.test("optional skips count as done; needsMore does not; a required key can't be skipped", function()
		local model = Model.fromData(data({
			entry("sfx.squish", { 1, 2 }),
			entry("sfx.pop", { 3 }),
			entry("ui.coin", { 4 }),
		}))
		expect.equal(model:currentKey(), "sfx.squish")
		local okSkip, reason = model:skip("sfx.squish")
		expect.falsy(okSkip)
		expect.equal(reason, "only optional keys can be skipped")
		expect.truthy(model:needsMore("sfx.squish", "tooLoud"))
		expect.equal(model:currentKey(), "sfx.pop")
		expect.truthy(model:skip("sfx.pop")) -- sfx.pop is optional in AssetTable
		local done, total = model:progress()
		expect.equal(done, 1)
		expect.equal(total, 3)
		expect.equal(model:currentKey(), "ui.coin")
		expect.falsy(model:needsMore("ui.coin", "tooQuiet")) -- unknown reason
		expect.truthy(model:approve("ui.coin", 4, 0.5))
		done = model:progress()
		expect.equal(done, 2)
		expect.equal(model:currentKey(), nil)
		expect.truthy(model:view().finished)
		expect.deepEqual(model:decision("sfx.squish"), { status = "needsMore", reason = "tooLoud", round = "round-1" })
	end)

	t.test("a key that wants 3 variants stays current until 3 are picked; picked ones are hidden", function()
		local model = Model.fromData(data({
			entry("sfx.squish", { 1, 2, 3, 4 }, { variantsWanted = 3 }),
			entry("sfx.squeezeRelease", { 5 }),
		}))
		expect.truthy(model:approve("sfx.squish", 1, 0.8))
		local view = model:view()
		expect.equal(view.key, "sfx.squish")
		expect.truthy(view.picking)
		expect.equal(view.picked, 1)
		expect.equal(view.variantsWanted, 3)
		expect.equal(view.count, 3) -- 1 is picked, so it is hidden
		expect.equal(view.candidate.id, 2)
		local done = model:progress()
		expect.equal(done, 1) -- approved at the first pick, so nothing is lost if Play stops
		expect.falsy(model:addVariant("sfx.squish", 1, 0.8)) -- already picked
		expect.falsy(model:approve("sfx.squeezeRelease", 5, 0.3)) -- finish the variants first
		expect.truthy(model:addVariant("sfx.squish", 2, 0.75))
		expect.equal(model:view().picked, 2)
		expect.equal(model:currentKey(), "sfx.squish")
		expect.truthy(model:addVariant("sfx.squish", 4, 0.9))
		expect.equal(model:currentKey(), "sfx.squeezeRelease")
		expect.deepEqual(model:decision("sfx.squish"), {
			status = "approved",
			picks = { { id = 1, volume = 0.8 }, { id = 2, volume = 0.75 }, { id = 4, volume = 0.9 } },
		})
	end)

	t.test("That's enough closes the variant flow with the picks it has", function()
		local model = Model.fromData(data({
			entry("sfx.throw", { 1, 2, 3 }, { variantsWanted = 3 }),
			entry("sfx.impactBoing", { 4 }),
		}))
		expect.truthy(model:approve("sfx.throw", 2, 0.6))
		expect.falsy(model:enough("sfx.impactBoing"))
		expect.truthy(model:enough("sfx.throw"))
		expect.equal(model:currentKey(), "sfx.impactBoing")
		expect.deepEqual(model:decision("sfx.throw").picks, { { id = 2, volume = 0.6 } })
	end)

	t.test("undo reverts the last decision change, back to the same candidate", function()
		local model = Model.fromData(data({
			entry("sfx.squish", { 1, 2, 3 }, { variantsWanted = 2 }),
			entry("sfx.squeezeRelease", { 5, 6 }),
		}))
		expect.equal(model:undo(), nil)
		expect.falsy(model:canUndo())
		model:nextCandidate()
		expect.truthy(model:approve("sfx.squish", 2, 0.8))
		expect.truthy(model:addVariant("sfx.squish", 1, 0.8))
		expect.equal(model:currentKey(), "sfx.squeezeRelease")
		model:nextCandidate()
		expect.truthy(model:needsMore("sfx.squeezeRelease", "wrongVibe"))
		expect.equal(model:undo(), "sfx.squeezeRelease")
		expect.equal(model:decision("sfx.squeezeRelease"), nil)
		local current, index = model:currentCandidate()
		expect.equal(current.id, 6) -- the cursor comes back where it was
		expect.equal(index, 2)
		expect.equal(model:undo(), "sfx.squish") -- the variant: the flow opens again with one pick
		local view = model:view()
		expect.equal(view.key, "sfx.squish")
		expect.truthy(view.picking)
		expect.equal(view.picked, 1)
		expect.equal(model:undo(), "sfx.squish") -- the approval itself
		expect.equal(model:decision("sfx.squish"), nil)
		expect.falsy(model:view().picking)
		expect.equal(model:currentCandidate().id, 2)
		expect.falsy(model:canUndo())
	end)

	t.test("volume: starts at the key's default, 0.1 steps on the grid, clamped to 0.1-1.5", function()
		expect.equal(Model.stepVolume(0.8, 1), 0.9)
		expect.equal(Model.stepVolume(0.8, -1), 0.7)
		expect.equal(Model.stepVolume(0.35, 1), 0.4)
		expect.equal(Model.stepVolume(0.35, -1), 0.3)
		expect.equal(Model.stepVolume(1.5, 1), 1.5)
		expect.equal(Model.stepVolume(0.1, -1), 0.1)
		expect.equal(Model.stepVolume(1.4, 3), 1.5)
		expect.equal(Model.clampVolume(9), 1.5)
		expect.equal(Model.clampVolume(0), 0.1)
		expect.equal(Model.clampVolume(0 / 0), 1)
		local model = Model.fromData(data({ entry("sfx.pop", { 1, 2 }, { defaultVolume = 0.35 }) }))
		expect.equal(model:volume(), 0.35)
		local v = 0
		for _ = 1, 20 do
			v = model:volumeStep(1)
		end
		expect.equal(v, 1.5)
		expect.equal(model:volume(), 1.5)
		model:nextCandidate()
		expect.equal(model:volume(), 0.35) -- each candidate keeps its own volume
		model:prevCandidate()
		expect.equal(model:volumeStep(-2), 1.3)
		local wild = Model.fromData(data({ entry("sfx.pop", { 1 }, { defaultVolume = 7 }) }))
		expect.equal(wild:volume(), 1.5)
	end)

	t.test("the cursor wraps both ways and Sound n of m follows it", function()
		local model = Model.fromData(data({ entry("ui.click", { 1, 2, 3 }) }))
		expect.equal(model:prevCandidate().id, 3)
		expect.equal(model:nextCandidate().id, 1)
		expect.equal(model:nextCandidate().id, 2)
		local view = model:view()
		expect.equal(view.index, 2)
		expect.equal(view.count, 3)
		expect.equal(view.candidate.seconds, 0.3)
	end)

	t.test("export and import round-trip; the next load resumes at the first unfinished key", function()
		local keys = {
			entry("sfx.squish", { 1, 2, 3 }, { variantsWanted = 3 }),
			entry("sfx.squeezeRelease", { 4 }),
			entry("sfx.pop", { 5 }),
			entry("ui.coin", { 6 }),
		}
		local model = Model.fromData(data(keys))
		model:approve("sfx.squish", 1, 0.8)
		model:addVariant("sfx.squish", 3, 0.7)
		model:enough("sfx.squish")
		model:needsMore("sfx.squeezeRelease", "tooLong")
		model:skip("sfx.pop")
		local exported = model:export()
		expect.equal(exported.version, 1)
		expect.equal(exported.builtAt, "round-1")
		expect.deepEqual(exported.keys, { "sfx.squish", "sfx.squeezeRelease", "sfx.pop", "ui.coin" })

		local again, problems = Model.fromData(data(keys, exported.decisions))
		expect.deepEqual(problems, {})
		expect.deepEqual(again:export(), exported)
		expect.equal(again:currentKey(), "ui.coin")
		local done, total = again:progress()
		expect.equal(done, 2)
		expect.equal(total, 4)

		-- A newer round (new candidates) makes the needsMore key to do again; approvals and skips stay.
		local nextRound = Model.fromData(data(keys, exported.decisions, "round-2"))
		expect.equal(nextRound:currentKey(), "sfx.squeezeRelease")
		expect.equal(nextRound:decision("sfx.squeezeRelease"), nil)
		expect.equal(nextRound:decision("sfx.pop").status, "skipped")
	end)

	t.test("malformed decisions are reported and ignored", function()
		local _, problems = Model.fromData(data({
			entry("sfx.squish", { 1 }),
			entry("ui.click", { 2 }),
			entry("sfx.pop", { 3 }),
			entry("ui.coin", { 4 }),
		}, {
			["sfx.squish"] = { status = "approved", picks = {} },
			["ui.click"] = { status = "skipped" }, -- not optional
			["sfx.pop"] = { status = "needsMore" }, -- no reason
			["ui.coin"] = { status = "maybe" },
		}))
		expect.equal(#problems, 4)
	end)

	t.test("bad data gives an empty model and a problem, never an error", function()
		local cases: { any } = { false, 42, "text", { version = 2, keys = {} }, { version = 1 } }
		table.insert(cases, 1, "nil")
		for _, bad in cases do
			local model, problems = Model.fromData(if bad == "nil" then nil else bad)
			expect.truthy(#problems >= 1)
			local done, total = model:progress()
			expect.equal(done, 0)
			expect.equal(total, 0)
			expect.equal(model:currentKey(), nil)
			expect.truthy(model:view().finished)
		end
	end)

	t.test("the panel texts", function()
		expect.equal(Model.progressText(7, 37), "7 of 37 done")
		expect.equal(Model.sectionText(1), "Part 1 of 10: Squeezing")
		expect.equal(Model.sectionText(7), "Part 7 of 10: Music and room sound")
		expect.equal(Model.sectionText(8), "Part 8 of 10: Dash and Epic ultimates") -- spec phase 5
		expect.equal(Model.sectionText(9), "Part 9 of 10: Inspect showcases") -- final polish 2026-10-11
		expect.equal(Model.sectionText(10), "Part 10 of 10: Charge throw and catch") -- feature 1, 2026-10-11
		expect.equal(Model.soundLine(2, 6, 0.3), "Sound 2 of 6 · 0.3 s")
		expect.equal(Model.soundLine(2, 6, nil), "Sound 2 of 6")
		expect.equal(Model.soundLine(1, 5, 83.7), "Sound 1 of 5 · 1:23")
		expect.equal(Model.variantText(1, 3), "Picked 1 of 3 for variety")
		expect.equal(Model.tabText(7, 37), "Sound picker 7/37")
		expect.equal(Model.volumeText(0.8), "80%")
		expect.equal(Model.volumeText(0.35), "35%")
		expect.equal(Model.volumeText(9), "150%")
		expect.equal(Model.clockText(23.9), "0:23")
		expect.equal(Model.clockText(-4), "0:00")
		expect.equal(Model.clockText(0 / 0), "0:00")
		expect.equal(Model.lengthText(0), "")
		expect.equal(Model.loopRole("music.lobby"), "the lobby music")
		expect.equal(Model.loopRole("amb.arena"), "the arena room sound")
		expect.equal(Model.loopRole("sfx.squish"), nil)
		for _, key in Model.ORDER do
			local _, runner = Model.infoOf(key)
			expect.equal(Model.loopRole(key) ~= nil, runner == "loop") -- every looping key has a role, and only those
		end
	end)

	t.test("JSON copies carry ids as digit strings and load back to the same decisions", function()
		local keys = {
			entry("sfx.squish", { 101, 202 }, { variantsWanted = 2 }),
			entry("sfx.squeezeRelease", { 303 }),
			entry("sfx.pop", { 404 }),
		}
		local model = Model.fromData(data(keys))
		model:approve("sfx.squish", 202, 0.7)
		model:addVariant("sfx.squish", 101, 0.9)
		model:needsMore("sfx.squeezeRelease", "notSquishy")
		model:skip("sfx.pop")
		local exported = model:export()
		local json = Model.jsonExport(exported)
		expect.deepEqual(json.decisions["sfx.squish"], {
			status = "approved",
			picks = { { id = "202", volume = 0.7 }, { id = "101", volume = 0.9 } },
		})
		expect.deepEqual(
			json.decisions["sfx.squeezeRelease"],
			{ status = "needsMore", reason = "notSquishy", round = "round-1" }
		)
		expect.deepEqual(json.keys, exported.keys)
		local again, problems = Model.fromData(data(keys, json.decisions))
		expect.deepEqual(problems, {})
		expect.deepEqual(again:export(), exported)

		expect.deepEqual(
			Model.jsonDecision("sfx.pop", model:decision("sfx.pop")),
			{ key = "sfx.pop", status = "skipped" }
		)
		expect.deepEqual(Model.jsonDecision("ui.coin", nil), { key = "ui.coin", status = "todo" })
	end)

	t.test("storyboards follow the real timings", function()
		local countdown = Model.storyboard("duel.countdownTick")
		local plays: { any } = {}
		for _, cue in countdown do
			if cue.kind == "play" then
				table.insert(plays, { at = cue.at, key = cue.key, pitch = cue.pitch })
			end
		end
		local expected: { any } = {
			{ at = 0, key = "duel.countdownTick", pitch = 1.0 },
			{ at = 1, key = "duel.countdownTick", pitch = 1.06 },
			{ at = 2, key = "duel.countdownTick", pitch = 1.12 },
			{ at = 3, key = "duel.go" },
		}
		expect.deepEqual(plays, expected)
		local dragon = Model.storyboard("sfx.dragonRoar")
		local chompAt = nil
		for _, cue in dragon do
			if cue.key == "sfx.dragonChomp" then
				chompAt = cue.at
			end
		end
		expect.near(chompAt, 0.9 + 110 / 260, 1e-9)
		local box = Model.storyboard("reveal.epic")
		local times: { [string]: { number } } = {}
		for _, cue in box do
			if cue.kind == "play" then
				times[cue.key] = times[cue.key] or {}
				table.insert(times[cue.key], cue.at)
			end
		end
		expect.equal(#times["box.shake"], 3)
		for i, at in { 0, 0.3, 0.6 } do
			expect.near(times["box.shake"][i], at, 1e-9)
		end
		expect.near(times["box.open"][1], 0.9, 1e-9)
		expect.near(times["reveal.epic"][1], 1.15, 1e-9)
		expect.equal(times["reveal.common"], nil) -- a reveal key plays itself, not the fallback
		local coin = Model.storyboard("ui.coin")
		expect.equal(#coin, 5)
		expect.near(coin[5].at, 0.4, 1e-9)
		expect.equal(Model.storyboard("sfx.squish"), nil)
		expect.equal(Model.storyboard("music.lobby"), nil)
		for _, key in Model.ORDER do
			local _, runner = Model.infoOf(key)
			local cues = Model.storyboard(key)
			expect.equal(cues ~= nil, runner == "storyboard")
			if cues then
				local ducks = 0
				for i, cue in cues do
					expect.truthy(i == 1 or cues[i - 1].at <= cue.at)
					if cue.kind == "duck" then
						ducks += 1
					elseif cue.kind == "unduck" then
						ducks -= 1
					end
				end
				expect.equal(ducks, 0) -- every duck is released
			end
		end
	end)
end
