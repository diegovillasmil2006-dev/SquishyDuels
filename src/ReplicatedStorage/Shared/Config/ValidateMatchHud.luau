--!strict
-- Config/ValidateMatchHud (Shared). Match HUD M4 (2026-10-16; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.1,
-- §1.5, §1.9): the Config.UI.Match part of Config.validate (the in-match screens' layer, MatchHudController), called
-- from Config/ValidateMatch with Config/init's own check helpers, so Config/init does not grow (it is near Roblox's
-- 200,000-character script Source limit). Pure: require(script)(h, UI) returns check(problems), which adds
-- human-readable problems through the helpers `h`.
-- The rules: Match is a table; its gui spec's displayOrder is a whole number >= 0 that no Config.UI.ScreenGuis entry
-- uses (the uniqueness Config/init checks inside that table; the controller-owned layers such as SD_Touch 12 keep
-- theirs in private constants, so ValidateMatchHud_Test pins those); every enabled switch is a boolean;
-- compact.fitMin is in (0, 1]. For the steps to come (v1 §1.1, §1.5), anywhere under Match: a field named `text` or
-- ending in `Text` names a Config.UI.TextSize kind (M's px are built as text kinds, never raw sizes), and a field
-- named `curve` or `wholeRun` names a Config.UI.curves entry.

type Problems = { string }

export type Helpers = {
	add: (problems: Problems, message: string) -> (),
	expect: (problems: Problems, ok: boolean, message: string) -> (),
	expectCount: (problems: Problems, path: string, value: unknown, min: number) -> (),
	expectBoolean: (problems: Problems, path: string, value: unknown) -> (),
	isNumber: (value: unknown) -> boolean,
	show: (value: unknown) -> string,
	sortedKeys: (tbl: any) -> { any },
}

return function(h: Helpers, UI: any): (problems: Problems) -> ()
	local add, expect, expectCount, expectBoolean = h.add, h.expect, h.expectCount, h.expectBoolean
	local isNumber, show, sortedKeys = h.isNumber, h.show, h.sortedKeys

	-- The text-kind and curve-name rules, on every field under `value` (stable order).
	local function walk(problems: Problems, path: string, value: any)
		for _, key in sortedKeys(value) do
			local child = value[key]
			local at = `{path}.{tostring(key)}`
			if type(child) == "table" then
				walk(problems, at, child)
			elseif type(key) == "string" and (key == "text" or string.sub(key, -4) == "Text") then
				expect(
					problems,
					type(child) == "string" and type(UI.TextSize[child]) == "number",
					`{at} must name a Config.UI.TextSize kind (got {show(child)})`
				)
			elseif key == "curve" or key == "wholeRun" then
				expect(
					problems,
					type(child) == "string" and UI.curves[child] ~= nil,
					`{at} must name a Config.UI.curves entry (got {show(child)})`
				)
			end
		end
	end

	return function(problems: Problems)
		local p = "Config.UI.Match"
		local m = UI.Match
		if type(m) ~= "table" then
			add(problems, `{p} must be a table`)
			return
		end
		local gui = m.gui
		if type(gui) ~= "table" then
			add(problems, `{p}.gui must be a ScreenGui spec (displayOrder, insets)`)
		else
			expectCount(problems, `{p}.gui.displayOrder`, gui.displayOrder, 0)
			for _, name in sortedKeys(UI.ScreenGuis) do
				expect(
					problems,
					UI.ScreenGuis[name].displayOrder ~= gui.displayOrder,
					`{p}.gui shares displayOrder {show(gui.displayOrder)} with Config.UI.ScreenGuis.{name}`
				)
			end
		end
		local enabled = m.enabled
		if type(enabled) ~= "table" then
			add(problems, `{p}.enabled must be a table of piece switches`)
		else
			for _, name in sortedKeys(enabled) do
				expectBoolean(problems, `{p}.enabled.{tostring(name)}`, enabled[name])
			end
		end
		local fitMin = if type(m.compact) == "table" then m.compact.fitMin else nil
		expect(
			problems,
			isNumber(fitMin) and (fitMin :: number) > 0 and (fitMin :: number) <= 1,
			`{p}.compact.fitMin must be a number in (0, 1] (got {show(fitMin)})`
		)
		walk(problems, p, m)
	end
end
