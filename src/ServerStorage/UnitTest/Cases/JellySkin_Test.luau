--!strict
-- JellySkin_Test: unit tests for StarterPlayerScripts.Client.Anim.JellySkin (the jelly ripple's skin layout and hit
-- math). Server only (ServerStorage.UnitTest). Pure: no instances, no EditableMesh.
-- Contract (DESIGN §18.3.4, §18.11 JellySkin_Test):
--   * counts equal the formulas and the built layouts, and stay under the Config caps at both qualities (High 5,368
--     vertices / 9,000 triangles, Low 2,488 / 3,728); walls left out when vertexColors is off;
--   * every triangle winds outward; outer rings are pinned (fixed faces wholly); every stripe edge is a grid row; on
--     the big wall faces stripe-band triangles are Cream and the rest the wall colour; side and top faces are one colour;
--   * side A is the point reflection of side B; the anchors widen the bounds by at least boundsMargin and hold what
--     every skinned piece can reach while it dents and jiggles (JellySkin.jiggleReach);
--   * findFace: the centre of B_Wall1's -Z face gives that face and (u, v); an edge with a diagonal normal gives no face
--     but the piece; a Cap top gives no face but the block; the floor gives nil; a point beyond the tolerance gives nil;
--     side A mirrors side B; classify sorts floor, round, face, edge and other hits (§18.3.4 step 2);
--   * rayFace from a lane end E (the sphere centre, R = 4 short of a wall face) along the lane for R +
--     rushProbeMarginStuds hits that face, and for R alone it does not;
--   * arenaFrame(PadA, PadB, floorY) round-trips WorldLayout points (every cover Body within 0.001 studs, also for a
--     yawed arena); the mismatch guard trips at 0.03 studs and a turned box of the same shape matches;
--   * arenaPiecesFor (phase 4 spec 2026-10-11 D9): Candy Court's pieces for "candy_court" or no arena id, none for any
--     other arena (its cover is not Candy Court's: no skin is built there).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local JellySkin = t.requireClient("Anim/JellySkin")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local RIPPLE = Config.Anim.jellyRipple
	local STRIPES = WorldLayout.Arena.wallStripes

	local function pieceNamed(pieces: { any }, name: string): any
		for _, piece in pieces do
			if piece.name == name then
				return piece
			end
		end
		error(`no piece {name}`)
	end

	local function vertex(layout: any, i: number): Vector3
		return Vector3.new(layout.px[i], layout.py[i], layout.pz[i])
	end

	-- A point on a piece's box face (layout space) at (u, v).
	local function facePoint(piece: any, name: string, u: number, v: number): (Vector3, Vector3)
		local center, normal, uAxis, vAxis = JellySkin.boxFaceFrame(piece, name)
		return center + uAxis * u + vAxis * v, normal
	end

	-- Counts --------------------------------------------------------------------------------------------------------

	t.test(
		"counts equal the formulas and the layouts, under the caps (High 5,368 / 9,000, Low 2,488 / 3,728)",
		function()
			local cases = {
				{ q = "High", v = 5368, t = 9000, maxV = RIPPLE.maxVerticesHigh, maxT = RIPPLE.maxTrianglesHigh },
				{ q = "Low", v = 2488, t = 3728, maxV = RIPPLE.maxVerticesLow, maxT = RIPPLE.maxTrianglesLow },
			}
			for _, case in cases do
				local quality, vertices, triangles, maxV, maxT = case.q, case.v, case.t, case.maxV, case.maxT
				local v, tri = JellySkin.counts(quality)
				expect.equal(v, vertices)
				expect.equal(tri, triangles)
				local layout = JellySkin.arenaLayout(quality)
				expect.equal(layout.vertexCount, vertices)
				expect.equal(layout.triangleCount, triangles)
				expect.truthy(vertices <= maxV and triangles <= maxT)
				-- vertexColors off: the walls are left out and the counts still follow the formulas.
				local nv, nt = JellySkin.counts(quality, { walls = false })
				local blocks = JellySkin.arenaLayout(quality, { walls = false })
				expect.equal(blocks.vertexCount, nv)
				expect.equal(blocks.triangleCount, nt)
				expect.equal(blocks.triColors, nil)
				for _, piece in blocks.pieces do
					expect.equal(piece.skinned, piece.kind == "block")
				end
			end
			-- Per piece at High: a wall 712 vertices, a block 624 (the swap-in writes, §18.3.4).
			local high = JellySkin.arenaLayout("High")
			expect.equal(pieceNamed(high.pieces, "B_Wall1").count, 712)
			expect.equal(pieceNamed(high.pieces, "B_Block1").count, 624)
			expect.equal(pieceNamed(high.pieces, "B_Gumdrop1").skinned, false)
		end
	)

	-- Layout ------------------------------------------------------------------------------------------------------

	t.test("every triangle winds outward and every outer ring is pinned", function()
		for _, layout in
			{ JellySkin.arenaLayout("High"), JellySkin.arenaLayout("Low"), JellySkin.backstopLayout("High") }
		do
			for k = 1, layout.triangleCount do
				local a, b, c = layout.tris[3 * k - 2], layout.tris[3 * k - 1], layout.tris[3 * k]
				local n = Vector3.new(layout.nx[a], layout.ny[a], layout.nz[a])
				local winding = (vertex(layout, b) - vertex(layout, a)):Cross(vertex(layout, c) - vertex(layout, a))
				if winding:Dot(n) <= 0 then
					error(`{layout.kind} {layout.quality}: triangle {k} winds inward`)
				end
			end
			for _, face in layout.faces do
				for k = 1, face.count do
					local row = (k - 1) // face.cols + 1
					local col = k - (row - 1) * face.cols
					local edge = col == 1 or col == face.cols or row == 1 or row == face.rows
					expect.equal(face.pinned[k], edge or not face.moves)
				end
			end
		end
	end)

	t.test("every stripe edge is a grid row; big faces carry Cream bands, side and top faces one colour", function()
		for _, quality in { "High", "Low" } do
			local layout = JellySkin.arenaLayout(quality)
			local tri = 0
			for _, face in layout.faces do
				local piece = layout.pieces[face.piece]
				local triangles = 2 * (face.cols - 1) * (face.rows - 1)
				if face.kind == "wallBig" then
					for _, height in STRIPES.heights do
						for _, edge in { height - STRIPES.thickness / 2, height + STRIPES.thickness / 2 } do
							local found = false
							for _, v in face.rowVs do
								if math.abs(v + face.height / 2 - edge) < 1e-9 then
									found = true
								end
							end
							if not found then
								error(`{quality} {piece.name} {face.name}: no grid row at stripe edge {edge}`)
							end
						end
					end
				end
				for row = 1, face.rows - 1 do
					local y0, y1 = face.rowVs[row] + face.height / 2, face.rowVs[row + 1] + face.height / 2
					local band = false
					for _, height in STRIPES.heights do
						if
							y0 >= height - STRIPES.thickness / 2 - 1e-9
							and y1 <= height + STRIPES.thickness / 2 + 1e-9
						then
							band = true
						end
					end
					local wanted = if face.kind == "wallBig" and band then "Cream" else piece.color
					for _ = 1, 2 * (face.cols - 1) do
						tri += 1
						if layout.triColors[tri] ~= wanted then
							error(`{quality} {piece.name} {face.name} row {row}: {layout.triColors[tri]} ~= {wanted}`)
						end
					end
				end
				expect.truthy(triangles >= 0)
			end
		end
	end)

	t.test("side A is the point reflection of side B", function()
		local layout = JellySkin.arenaLayout("High")
		local function key(p: Vector3): string
			return string.format("%.4f,%.4f,%.4f", p.X, p.Y, p.Z)
		end
		for _, piece in layout.pieces do
			if piece.name:sub(1, 2) ~= "B_" or not piece.skinned then
				continue
			end
			local mirror = pieceNamed(layout.pieces, "A_" .. piece.name:sub(3))
			expect.equal(mirror.count, piece.count)
			local set: { [string]: number } = {}
			for i = piece.first, piece.first + piece.count - 1 do
				local p = vertex(layout, i)
				local k = key(Vector3.new(-p.X, p.Y, -p.Z))
				set[k] = (set[k] or 0) + 1
			end
			for i = mirror.first, mirror.first + mirror.count - 1 do
				local k = key(vertex(layout, i))
				if (set[k] or 0) == 0 then
					error(`{mirror.name}: vertex {k} is not the reflection of a {piece.name} vertex`)
				end
				set[k] -= 1
			end
		end
	end)

	t.test(
		"the bounds anchors widen the rest bounds by boundsMargin and hold every piece's dent and jiggle reach",
		function()
			for _, layout in
				{ JellySkin.arenaLayout("High"), JellySkin.arenaLayout("Low"), JellySkin.backstopLayout("Low") }
			do
				local margin = Vector3.one * RIPPLE.boundsMargin
				local wantLow, wantHigh = layout.restMin - margin, layout.restMax + margin
				for _, piece in layout.pieces do
					if piece.skinned then
						local reachLow, reachHigh = JellySkin.jiggleReach(piece)
						wantLow, wantHigh = wantLow:Min(reachLow), wantHigh:Max(reachHigh)
						-- The reach covers the piece's rest box pushed out by clampOut, and never goes below its bottom.
						local half = piece.size / 2
						expect.truthy(reachHigh.X >= piece.base.X + half.X + RIPPLE.clampOut - 1e-6)
						expect.truthy(reachLow.Z <= piece.base.Z - half.Z - RIPPLE.clampOut + 1e-6)
						expect.near(reachLow.Y, piece.base.Y, 1e-6)
					end
				end
				expect.truthy((layout.boundsMin - wantLow).Magnitude < 1e-9)
				expect.truthy((layout.boundsMax - wantHigh).Magnitude < 1e-9)
				expect.truthy(layout.boundsMin.X <= layout.restMin.X - RIPPLE.boundsMargin + 1e-9)
				expect.truthy(layout.boundsMax.Y >= layout.restMax.Y + RIPPLE.boundsMargin - 1e-9)
				expect.equal(layout.anchorCount, 24)
				local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
				for i = layout.anchorFirst, layout.anchorFirst + layout.anchorCount - 1 do
					low, high = low:Min(vertex(layout, i)), high:Max(vertex(layout, i))
				end
				expect.truthy((low - layout.boundsMin).Magnitude < 1e-9 and (high - layout.boundsMax).Magnitude < 1e-9)
				expect.truthy(((layout.boundsMin + layout.boundsMax) / 2 - layout.center).Magnitude < 1e-9)
			end
		end
	)

	-- Phase 3 (the design lobby, D3): throws go toward +X now, so the face toward the thrower is "-X"; the name comes
	-- from WorldLayout.PracticeRange.throwDirection (the outward normal opposite the throws).
	t.test("the backstop's front face is the one the throws meet: opposite WorldLayout's throw direction", function()
		local front = JellySkin.backstopFront()
		local normal = JellySkin.faceNormalOf(front)
		expect.truthy((normal + WorldLayout.PracticeRange.throwDirection).Magnitude < 1e-6)
		expect.equal(front, "-X")
		expect.equal(JellySkin.frontFaceFor(Vector3.new(-1, 0, 0)), "+X") -- the old range (throws toward -X)
		expect.equal(JellySkin.frontFaceFor(Vector3.new(0, 0, 1)), "-Z")
	end)

	t.test("the backstop skin: a 35 x 13 front at High, 24 x 9 at Low, the other faces fixed corners", function()
		for _, case in { { q = "High", cols = 35, rows = 13 }, { q = "Low", cols = 24, rows = 9 } } do
			local layout = JellySkin.backstopLayout(case.q)
			local front = layout.faces[layout.faceOf[1][JellySkin.backstopFront()]]
			expect.equal(front.cols, case.cols)
			expect.equal(front.rows, case.rows)
			expect.truthy(front.moves)
			expect.equal(#layout.faces, 6)
			for _, face in layout.faces do
				if face ~= front then
					expect.falsy(face.moves)
					expect.equal(face.count, 4)
				end
			end
			expect.equal(layout.vertexCount, case.cols * case.rows + 20 + 24)
		end
	end)

	-- Hits ----------------------------------------------------------------------------------------------------------

	t.test("findFace: a face centre, an edge, a Cap top, the floor and a point too far", function()
		local layout = JellySkin.arenaLayout("High")
		local wall = pieceNamed(layout.pieces, "B_Wall1")
		local p, n = facePoint(wall, "-Z", 0, 0)
		local face, u, v, piece = JellySkin.findFace(layout, p, n)
		expect.truthy(face ~= nil)
		expect.equal(face.name, "-Z")
		expect.equal(face.piece, wall.index)
		expect.equal(piece, wall)
		expect.near(u, 0, 1e-9)
		expect.near(v, 0, 1e-9)
		-- Off-centre: (u, v) come back.
		local q = facePoint(wall, "-Z", 1.25, -2.5)
		local _, u2, v2 = JellySkin.findFace(layout, q, n)
		expect.near(u2, 1.25, 1e-9)
		expect.near(v2, -2.5, 1e-9)
		-- An edge with a diagonal normal: no face, but the piece.
		local corner = wall.center + Vector3.new(wall.size.X / 2, 0, -wall.size.Z / 2)
		local edgeFace, _, _, edgePiece = JellySkin.findFace(layout, corner, Vector3.new(1, 0, -1).Unit)
		expect.equal(edgeFace, nil)
		expect.equal(edgePiece, wall)
		-- A Cap top: no face (the Cap is not skinned), but the block.
		local block = pieceNamed(layout.pieces, "B_Block1")
		local capTop = Vector3.new(block.center.X, block.boundsMax.Y, block.center.Z)
		local capFace, _, _, capPiece = JellySkin.findFace(layout, capTop, Vector3.yAxis)
		expect.equal(capFace, nil)
		expect.equal(capPiece, block)
		-- The floor: nothing.
		local floorFace, _, _, floorPiece = JellySkin.findFace(layout, Vector3.new(0, 0, 30), Vector3.yAxis)
		expect.equal(floorFace, nil)
		expect.equal(floorPiece, nil)
		-- Beyond the tolerance in front of the face: nothing.
		local far = p + n * (JellySkin.PIECE_TOLERANCE + 0.1)
		local farFace, _, _, farPiece = JellySkin.findFace(layout, far, n)
		expect.equal(farFace, nil)
		expect.equal(farPiece, nil)
	end)

	t.test("findFace: side A mirrors side B", function()
		local layout = JellySkin.arenaLayout("High")
		for _, name in { "B_Wall1", "B_Wall2", "B_Block1", "B_Block2" } do
			local piece = pieceNamed(layout.pieces, name)
			for _, faceName in { "-Z", "+Z", "+X", "-X" } do
				local p, n = facePoint(piece, faceName, 0.75, 1.25)
				local face, u, v = JellySkin.findFace(layout, p, n)
				local mirrored, mu, mv, mirrorPiece =
					JellySkin.findFace(layout, Vector3.new(-p.X, p.Y, -p.Z), Vector3.new(-n.X, n.Y, -n.Z))
				expect.truthy(face ~= nil and mirrored ~= nil)
				expect.equal(mirrorPiece.name, "A_" .. name:sub(3))
				expect.near(mu, u, 1e-9)
				expect.near(mv, v, 1e-9)
			end
		end
	end)

	t.test("classify: floor, round, face, edge and other", function()
		local pieces = JellySkin.arenaPieces()
		local wall = pieceNamed(pieces, "B_Wall1")
		local gumdrop = pieceNamed(pieces, "B_Gumdrop1")
		expect.equal((JellySkin.classify(pieces, Vector3.new(3, 0.05, 30), Vector3.yAxis)), "floor")
		-- The Markings paint stands up to 0.06 above the floor; a point 0.3 up is not the floor.
		expect.equal((JellySkin.classify(pieces, Vector3.new(3, 0.3, 30), Vector3.yAxis)), "other")
		local side = gumdrop.center + Vector3.new(2.5, 0, 0)
		local class, piece = JellySkin.classify(pieces, side, Vector3.xAxis)
		expect.equal(class, "round")
		expect.equal(piece, gumdrop)
		local p, n = facePoint(wall, "+Z", -1, 2)
		local faceClass, facePiece, faceName, u, v = JellySkin.classify(pieces, p, n)
		expect.equal(faceClass, "face")
		expect.equal(facePiece, wall)
		expect.equal(faceName, "+Z")
		expect.near(u, -1, 1e-9)
		expect.near(v, 2, 1e-9)
		local corner = wall.center + Vector3.new(wall.size.X / 2, wall.size.Y / 2, 0)
		expect.equal((JellySkin.classify(pieces, corner, Vector3.new(1, 1, 0).Unit)), "edge")
		local rail = Vector3.new(WorldLayout.Arena.halfX, 1.5, 0)
		expect.equal((JellySkin.classify(pieces, rail, -Vector3.xAxis)), "other")
	end)

	t.test(
		"rayFace: from a lane end R short of a wall face, R + rushProbeMarginStuds reaches it, R alone does not",
		function()
			local layout = JellySkin.arenaLayout("High")
			local wall = pieceNamed(layout.pieces, "B_Wall1")
			local radius = 4
			local p, n = facePoint(wall, "-Z", 0.5, 1)
			local endpoint = p + n * radius -- the swept sphere's centre at contact
			local dir = -n
			local face, u, v, piece = JellySkin.rayFace(layout, endpoint, dir, radius + RIPPLE.rushProbeMarginStuds)
			expect.truthy(face ~= nil)
			expect.equal(face.name, "-Z")
			expect.equal(piece, wall)
			expect.near(u, 0.5, 1e-6)
			expect.near(v, 1, 1e-6)
			local short = JellySkin.rayFace(layout, endpoint, dir, radius - 0.5)
			expect.equal(short, nil)
			-- Glancing past the piece: nothing.
			local past =
				JellySkin.rayFace(layout, endpoint + Vector3.new(10, 0, 0), dir, radius + RIPPLE.rushProbeMarginStuds)
			expect.equal(past, nil)
		end
	)

	-- Frames and guards --------------------------------------------------------------------------------------------

	t.test("arenaFrame round-trips WorldLayout points (every cover Body within 0.001 studs, also yawed)", function()
		local pads = WorldLayout.Arena.pads
		for _, origin in
			{
				CFrame.identity,
				CFrame.new(400, 30, -250),
				CFrame.new(-120, 12.5, 88) * CFrame.Angles(0, math.rad(37), 0),
				CFrame.new(5, -3, 7) * CFrame.Angles(0, math.rad(180), 0),
			}
		do
			local padA = origin * CFrame.new(pads.A.position)
			local padB = origin * CFrame.new(pads.B.position)
			local floorY = origin.Y -- the arena's floor top is its origin's Y (WorldLayout floorTopY 0)
			local frame = JellySkin.arenaFrame(padA, padB, floorY)
			for _, piece in JellySkin.arenaPieces() do
				local world = origin:PointToWorldSpace(piece.center)
				local back = frame:PointToObjectSpace(world)
				if (back - piece.center).Magnitude > 0.001 then
					error(`{piece.name}: {back} ~= {piece.center}`)
				end
			end
		end
	end)

	t.test("the mismatch guard trips at 0.03 studs; a turned box of the same shape matches", function()
		local frame = CFrame.new(9, 4, 20)
		local size = Vector3.new(6, 8, 2.5)
		local limit = RIPPLE.mismatchStuds
		expect.near(JellySkin.boxMismatch(frame, size, frame, size), 0, 1e-9)
		expect.truthy(JellySkin.boxMismatch(frame * CFrame.new(0.03, 0, 0), size, frame, size) > limit)
		expect.truthy(JellySkin.boxMismatch(frame * CFrame.new(0, 0.01, 0), size, frame, size) <= limit)
		expect.truthy(JellySkin.boxMismatch(frame, size + Vector3.new(0, 0.06, 0), frame, size) > limit)
		-- ArenaBuilder's upright Cylinder: Size (height, d, d) turned 90° about Z is the box (d, height, d).
		local cylinder = CFrame.new(20, 3.75, 30) * CFrame.Angles(0, 0, math.rad(90))
		expect.truthy(
			JellySkin.boxMismatch(cylinder, Vector3.new(7.5, 5, 5), CFrame.new(20, 3.75, 30), Vector3.new(5, 7.5, 5))
				< 1e-6
		)
	end)

	t.test("arenaPiecesFor: Candy Court's pieces for candy_court or no id, none for a design arena (D9)", function()
		expect.equal(JellySkin.arenaPiecesFor(nil), JellySkin.arenaPieces())
		expect.equal(JellySkin.arenaPiecesFor("candy_court"), JellySkin.arenaPieces())
		expect.deepEqual(JellySkin.arenaPiecesFor("pinewood_camp"), {})
		expect.deepEqual(JellySkin.arenaPiecesFor("anything else"), {})
	end)

	t.test("impulseFor and wobblePitch follow §18.3.4 and §18.6", function()
		local speed, reach = JellySkin.impulseFor(1.0, false, false)
		expect.near(speed, RIPPLE.impulseSpeed, 1e-9)
		expect.near(reach, 4.0, 1e-9)
		speed, reach = JellySkin.impulseFor(0.8, false, false)
		expect.near(speed, RIPPLE.impulseSpeed * 0.85, 1e-9)
		expect.near(reach, 3.2, 1e-9)
		speed, reach = JellySkin.impulseFor(1.4, false, false)
		expect.near(speed, RIPPLE.impulseSpeed * 1.2, 1e-9)
		expect.near(reach, 5.0, 1e-9)
		speed, reach = JellySkin.impulseFor(nil, true, false)
		expect.near(speed, RIPPLE.rushImpulseSpeed, 1e-9)
		expect.near(reach, RIPPLE.rushImpulseRadius, 1e-9)
		speed = JellySkin.impulseFor(1.0, false, true)
		expect.near(speed, RIPPLE.impulseSpeed * RIPPLE.reducedImpulseScale, 1e-9)
		expect.near(JellySkin.wobblePitch(1.0), 1.05, 1e-9)
		expect.near(JellySkin.wobblePitch(10), 0.85, 1e-9)
		expect.near(JellySkin.wobblePitch(0), 1.1, 1e-9)
		-- The PadDent mapping: waveSpeed = 2 × the real speed, clamps [-clampIn, clampOut].
		local params = JellySkin.dentParams()
		expect.near(params.waveSpeed, 2 * RIPPLE.waveStudsPerSecond, 1e-9)
		expect.near(params.sinkDepth + params.clampExtra, RIPPLE.clampIn, 1e-9)
		expect.near(params.clampUp, RIPPLE.clampOut, 1e-9)
	end)
end
