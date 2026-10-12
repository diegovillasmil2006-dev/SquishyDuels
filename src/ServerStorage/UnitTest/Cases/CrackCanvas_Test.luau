--!strict
-- CrackCanvas_Test: unit tests for StarterPlayerScripts.Client.Anim.CrackCanvas, the crack lines drawn into the knead
-- shell's colour atlas (spec phase2-squeeze §1.14, §3.4). Server only (ServerStorage.UnitTest). The pure drawing plan
-- only (the EditableImage itself is engine-only). Contract (design: squish.js:86-93; Config.Wax.lines, .canvas):
--   * the line colour is the part's × 0.38, the halo's min(colour × 1.1 + 0.08, 1);
--   * a change draws its halo across the line (offsets 0, ±1 at the halo's alpha, ±2 at half of it; across = the
--     other axis than the segment's main one), then the line; each blend only adds what is missing since the
--     previous step: (new - previous) / (1 - previous), as a transparency of 1 - that;
--   * the fill: the whole image in the first part's colour, then each part's tile (its UV rectangle in pixels, one
--     pixel wider each side) in its own colour.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local CrackCanvas = t.requireClient("Anim/CrackCanvas")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local LINES = Config.Wax.lines
	local CANVAS = Config.Wax.canvas

	local function near3(a: Color3, b: Color3)
		expect.near(a.R, b.R, 1e-6)
		expect.near(a.G, b.G, 1e-6)
		expect.near(a.B, b.B, 1e-6)
	end

	t.test("the colours: the line darkens to 0.38, the halo whitens to min(c·1.1 + 0.08, 1)", function()
		local base = Color3.new(0.9, 0.5, 0.2)
		near3(CrackCanvas.lineColor(base), Color3.new(0.9 * 0.38, 0.5 * 0.38, 0.2 * 0.38))
		near3(CrackCanvas.haloColor(base), Color3.new(1, 0.5 * 1.1 + 0.08, 0.2 * 1.1 + 0.08))
		expect.equal(LINES.lineDarken, 0.38)
	end)

	t.test("stepAlpha: only what is missing since the previous step", function()
		expect.near(CrackCanvas.stepAlpha(0.5, 0), 0.5, 1e-12)
		expect.near(CrackCanvas.stepAlpha(0.5, 0.25), (0.5 - 0.25) / 0.75, 1e-12)
		-- Two steps add up to the new alpha: 1 - (1 - 0.25)(1 - step) = 0.5.
		local step = CrackCanvas.stepAlpha(0.5, 0.25)
		expect.near(1 - (1 - 0.25) * (1 - step), 0.5, 1e-12)
		expect.equal(CrackCanvas.stepAlpha(0.25, 0.5), 0)
		expect.equal(CrackCanvas.stepAlpha(1, 1), 0)
	end)

	t.test("a change's plan: the halo across the line, then the line, at the stepped alphas", function()
		local base = Color3.new(0.8, 0.6, 0.4)
		-- A mostly horizontal segment from uv (0.1, 0.2) to (0.3, 0.21) on a 100 px atlas, octave 1, 0 -> 0.5.
		local change = {
			segment = 1,
			octave = 1,
			part = 1,
			u0 = 0.1,
			v0 = 0.2,
			u1 = 0.3,
			v1 = 0.21,
			alpha = 0.5,
			previous = 0,
			line = 0.5 * LINES.lineAlpha,
			halo = 0.5 * LINES.haloWhiten,
		}
		local ops = CrackCanvas.ops(change, base, 100)
		local offsets = CANVAS.haloOffsets
		expect.equal(#ops, 1 + 2 * #offsets + 1)
		-- The halo ops first: offset 0, then ±1, then ±2 (across = y for a horizontal line).
		local halo = CrackCanvas.haloColor(base)
		expect.near(ops[1].from.X, 10, 1e-6)
		expect.near(ops[1].from.Y, 20, 1e-6)
		expect.near(ops[1].to.X, 30, 1e-6)
		expect.near(ops[1].to.Y, 21, 1e-6)
		near3(ops[1].color, halo)
		expect.near(ops[1].transparency, 1 - change.halo, 1e-9)
		expect.near(ops[2].from.Y - ops[1].from.Y, offsets[1], 1e-6)
		expect.near(ops[3].from.Y - ops[1].from.Y, -offsets[1], 1e-6)
		expect.near(ops[2].from.X, ops[1].from.X, 1e-6)
		local outer = ops[2 * #offsets]
		expect.near(math.abs(outer.from.Y - ops[1].from.Y), offsets[#offsets], 1e-6)
		expect.near(outer.transparency, 1 - change.halo * CANVAS.haloFalloff, 1e-9)
		-- The line last, over its own halo.
		local line = ops[#ops]
		near3(line.color, CrackCanvas.lineColor(base))
		expect.near(line.transparency, 1 - change.line, 1e-9)
		expect.near(line.from.Y, 20, 1e-6)
		-- A vertical segment's halo goes across in x.
		local vertical = CrackCanvas.ops({
			segment = 2,
			octave = 2,
			part = 1,
			u0 = 0.5,
			v0 = 0.1,
			u1 = 0.51,
			v1 = 0.4,
			alpha = 0.75,
			previous = 0.5,
			line = 0.75 * LINES.lineAlpha * LINES.octave2Line,
			halo = 0.75 * LINES.haloWhiten * LINES.octave2Halo,
		}, base, 100)
		expect.near(vertical[2].from.X - vertical[1].from.X, offsets[1], 1e-6)
		expect.near(vertical[2].from.Y, vertical[1].from.Y, 1e-6)
		-- 0.5 -> 0.75: only the missing part is blended.
		local lineNow = 0.75 * LINES.lineAlpha * LINES.octave2Line
		local lineBefore = 0.5 * LINES.lineAlpha * LINES.octave2Line
		expect.near(vertical[#vertical].transparency, 1 - CrackCanvas.stepAlpha(lineNow, lineBefore), 1e-9)
	end)

	t.test("the fill: the image in the first part's colour, then each tile one pixel wider", function()
		local shell = {
			parts = {
				{ tile = { 0.1, 0.1, 0.4, 0.3 } },
				{ tile = { 0.5, 0.1, 0.9, 0.6 } },
			},
		}
		local colors = { Color3.new(1, 0, 0), Color3.new(0, 0, 1) }
		local fills = CrackCanvas.fills(shell :: any, colors, 200)
		expect.equal(#fills, 3)
		expect.equal(fills[1].position, Vector2.zero)
		expect.equal(fills[1].size, Vector2.new(200, 200))
		expect.equal(fills[1].color, colors[1])
		expect.equal(fills[2].position, Vector2.new(19, 19))
		expect.equal(fills[2].size, Vector2.new(62, 42))
		expect.equal(fills[3].color, colors[2])
		expect.equal(fills[3].position, Vector2.new(99, 19))
		expect.equal(fills[3].size, Vector2.new(82, 102))
	end)
end
