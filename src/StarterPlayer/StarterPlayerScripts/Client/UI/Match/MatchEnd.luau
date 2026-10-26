--!strict
-- MatchEnd (client only). End screens round A (2026-10-26; owner: "Yes, build round A of the end screens like that. You
-- can make and upload the picture and sounds."; `S:n` = Diego's "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html" line
-- n: the markup S:232-330, the timeline S:727-912; `T:n` = its uploads/tdm-hud.js): a MatchHudController piece
-- ("finish") from the match's last squish (the first view with a win or draw outcome) until the session ends (the
-- server keeps the screen Config.Match.resultSeconds, owner: "Keep 8 seconds"). Every number is
-- Config.UI.Match.finish's.
-- * The title (S:249-256, S:791-806): VICTORY! drops in letter by letter, bounces and the "!" lands hardest (two rings,
--   two spinning sunbursts, sprinkles, a jolt, the boom, the jingle and the cheering bed); DEFEAT drops softly, then
--   deflates (the stinger, the deflate, the crowd's aww). Free for All (owner 2026-10-26): VICTORY! for 1st, else
--   "2ND PLACE" ... in DEFEAT's style. A draw reads DRAW, softly. A white flash and the final hit open it.
-- * Under it (S:257-266): the winner's crest, "STRAWBERRY WINS" and the score rolling up (Free for All: the winner's
--   squishes); at 2.2 s the winner's jelly wave sweeps across, the title shrinks into a banner on a plate at the top and
--   the pill (S:264, desktop) says the mode, the result and the map.
-- * The results (S:282-302, S:851-870): the bar rises: the VICTORY / DEFEAT chip (desktop), the Coins counting up, the
--   Grip bar filling (GripController's total), the win streak's flame lighting up when it grew (desktop); then
--   SCOREBOARD, LOBBY (back to the lobby now) and PLAY AGAIN (back and queued for the same mode, focused, pulsing).
-- * TAP TO SKIP (from 1 s; a tap, Space, Return or the gamepad's A) jumps to the results; SCOREBOARD opens the
--   scoreboard (S:305-330): both teams (Free for All: 1st-6th and 7th-12th) with each player's squishes, times squished,
--   best streak and Grip earned (outcome standings), MVP = the winning team's most squishes (ties: fewer times
--   squished, then the best streak; T:211); closed by its X, a tap outside, Escape or B.
-- * End screens round B1 (2026-10-26; owner: "Yes, build step 1 of round B like that. You can make and upload the
--   sounds."): at the podium cue (podium.at, S:824) or a skip, ctx.podium (MatchHudController: UI/Match/MatchPodium on
--   the real camera and world) shows the cake or the "good game" line behind this screen (MatchPodium.lineup: Team your
--   team, Free for All the top 6); its pose HITs ting (poseHit, higher for each ripple slot), the MVP's slam booms and
--   flashes the screen (S:890) and the crown clinks (crownDrop). With the results its name tags pop in over the
--   players' heads (S:269-280, 857-858): the name, the squishes (with SQ; phones: the number), the MVP's crown and MVP
--   tag (gold) and YOU (a lemon border); phones tag only the MVP and you; each frame over the heads, a tag that meets
--   another stacked above it, all under the pill (placePlates, S:893-910).
-- Roblox draws text at one scale, so the design's scale(sx, sy) frames are their even part sqrt(sx * sy) (as the kill
-- feed's). Under ReducedMotion only the fades play; the jelly is a colour fade and the sunbursts do not turn. The
-- killcam is a later round.
-- Pure (unit-tested): ordinal(n), resultOf(view, who), mvp(view, teamOf), columns(view, who),
-- gripBar(total, gained), streakLine(mine), plates(view, lineup, compact), placePlates(boxes, top, left, right).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local GripMath = require(Shared.GripMath)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local MatchHudFormat = require(UI.MatchHudFormat)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local Tweens = require(UI.Parent.Anim.Tweens)
local UiIdle = require(UI.Parent.Anim.UiIdle)
local MatchKit = require(script.Parent.MatchKit)
local MatchPodium = require(script.Parent.MatchPodium)

-- Types

export type Result = {
	kind: string, -- "victory" | "defeat" | "draw"
	title: string,
	line: string, -- under the title
	winScore: number?, -- TDM and draws: the winner's (or your team's) score; Free for All: the winner's squishes
	loseScore: number?, -- TDM and draws: the other team's
	winColor: Color3,
	loseColor: Color3?,
	look: MatchHudFormat.PlayerLook, -- the winner's colours (crest, jelly, the team sunburst)
	winnerName: string, -- the psub's result
}

export type Row = {
	userId: number,
	name: string,
	kos: number,
	knockedOut: number,
	bestStreak: number,
	grip: number?,
	you: boolean,
	mvp: boolean,
	look: MatchHudFormat.PlayerLook,
}

export type Column = {
	title: string,
	look: MatchHudFormat.PlayerLook,
	score: number?,
	res: string?, -- WIN / LOSS / DRAW
	rows: { Row },
}

-- One name tag (S:975).
export type Plate = { userId: number, name: string, kos: number, mvp: boolean, you: boolean }

-- A tag's box for placePlates (stage px): its centre x, its bottom y, its size.
export type PlateBox = { x: number, y: number, w: number, h: number }

type PlateMade = { userId: number, holder: Frame, posed: Posed, w: number, h: number }

type Posed = { holder: GuiObject, poser: Tweens.Poser, fades: { Tweens.FadeGroup } }

type Letter = { posed: Posed, bang: boolean }

type Spark = { frame: Frame, t0: number, ms: number, dx: number, dy: number, rot: number, w: number, h: number }

type Button = { root: TextButton, posed: Posed, pulse: Frame }

type Made = {
	layout: any,
	covers: { Frame | TextButton },
	stages: { Frame },
	scales: { UIScale },
	flash: Frame,
	stage: Frame,
	suns: { ImageLabel },
	rings: { Frame },
	jelly: Frame,
	jellyX: Frame,
	title: Posed,
	letters: { Letter },
	plate: Posed,
	sub: Posed,
	crest: Posed,
	rollWin: TextLabel?,
	rollLose: TextLabel?,
	psub: Posed?,
	sparkLayer: Frame,
	plateLayer: Frame,
	bar: Posed,
	coinText: TextLabel,
	gripText: TextLabel,
	gripLevel: TextLabel,
	gripFill: Frame,
	gripInner: number,
	flame: Posed?,
	buttons: { Button },
	skip: Posed,
	catcher: TextButton,
	loops: { UiIdle.Handle },
}

-- Constants

local CFG = Config.UI.Match.finish
local TEXT = Strings.matchHud.finish
local TEAM_NAMES = Config.Match.teamNames
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Colors.inkUI
local MEASURE_MARGIN_PX = 2
local SUN_A_KEY = "img.end.sun18"
local SUN_B_KEY = "img.end.sun14"
local COIN_KEY = "img.coin"
local GRIP_KEY = "img.icon.grip"
local FLAME_KEY = "img.icon.flame"
local CLOSE_KEY = "img.icon.close"
local SOUND = {
	finalHit = "match.end.finalHit",
	slowmo = "match.end.slowmo",
	letterPop = "match.end.letterPop",
	titleBoom = "match.end.titleBoom",
	victory = "match.end.victory",
	cheer = "match.end.cheer",
	defeat = "match.end.defeat",
	deflate = "match.end.deflate",
	aww = "match.end.aww",
	jellyWipe = "match.end.jellyWipe",
	coinTick = "match.end.coinTick",
	gripFill = "match.end.gripFill",
	streak = "match.end.streak",
	tab = "ui.click", -- S:930 snd.tab(): the scoreboard opens (the game's tab click)
	poseHit = "match.end.poseHit",
	mvpSlam = "match.end.mvpSlam",
	crownDrop = "match.end.crownDrop",
}
local PODIUM = CFG.podium
local PLATES = CFG.plates
-- S:990-991 bumps along the jelly's leading edge and its drips (y %, height, width share).
local DRIPS = { { 10, 18, 1 }, { 26, 12, 0.7 }, { 44, 22, 1.2 }, { 61, 14, 0.8 }, { 77, 20, 1 }, { 90, 12, 0.6 } }
local BUMPS = 9
local NEUTRAL_LOOK = MatchHudFormat.playerLook(nil, nil, nil)
local SKIP_KEYS: { [Enum.KeyCode]: boolean } =
	{ [Enum.KeyCode.Space] = true, [Enum.KeyCode.Return] = true, [Enum.KeyCode.ButtonA] = true }
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.Escape] = true, [Enum.KeyCode.ButtonB] = true }

-- Module table

local MatchEnd = {}

-- Public: pure --------------------------------------------------------------------------------------------------------

function MatchEnd.ordinal(n: number): string
	return TEXT.ordinal[n] or Strings.format(TEXT.ordinalN, { n = n })
end

local function teamScoreColor(team: string?): Color3
	return if team == TEAM_NAMES[2] then Palette.MatchTeamBlueScore else Palette.MatchTeamRedScore
end

local function otherTeam(team: string?): string
	return if team == TEAM_NAMES[1] then TEAM_NAMES[2] else TEAM_NAMES[1]
end

local function teamLabel(team: string): string
	return string.upper(Strings.match.team[string.lower(team)] or team)
end

-- What the screen says for the local player (see the header). who(userId) -> { name, look } (MatchKit.who).
function MatchEnd.resultOf(view: any, who: (userId: number) -> any): Result
	local outcome = view.outcome
	local you = view.you
	local scores = view.teamScore
	local standings = outcome.standings or {}
	if outcome.kind == "draw" then
		local mine = you.team or TEAM_NAMES[1]
		local tdm = view.mode == "tdm"
		return {
			kind = "draw",
			title = TEXT.draw,
			line = TEXT.drawLine,
			winScore = if tdm and scores then scores[mine] else nil,
			loseScore = if tdm and scores then scores[otherTeam(mine)] else nil,
			winColor = teamScoreColor(mine),
			loseColor = teamScoreColor(otherTeam(mine)),
			look = if tdm then MatchHudFormat.playerLook("tdm", mine, nil) else NEUTRAL_LOOK,
			winnerName = TEXT.drawLine,
		}
	end
	if view.mode == "tdm" then
		local winner = outcome.winnerTeam or TEAM_NAMES[1]
		local won = you.team == winner
		local name = teamLabel(winner)
		return {
			kind = if won then "victory" else "defeat",
			title = if won then TEXT.victory else TEXT.defeat,
			line = Strings.format(TEXT.teamWins, { team = name }),
			winScore = if scores then scores[winner] else nil,
			loseScore = if scores then scores[otherTeam(winner)] else nil,
			winColor = teamScoreColor(winner),
			loseColor = teamScoreColor(otherTeam(winner)),
			look = MatchHudFormat.playerLook("tdm", winner, nil),
			winnerName = Strings.format(TEXT.teamWins, { team = name }),
		}
	end
	local winnerId = outcome.winnerUserId
	local won = winnerId ~= nil and winnerId == you.userId
	local place: number? = nil
	local winnerKos: number? = nil
	for index, standing in standings do
		if standing.userId == you.userId then
			place = index
		end
		if standing.userId == winnerId then
			winnerKos = standing.kos
		end
	end
	local winner = if winnerId then who(winnerId) else nil
	local winnerName = if winner then string.upper(winner.name) else ""
	local title = if won
		then TEXT.victory
		elseif place then Strings.format(TEXT.place, { place = MatchEnd.ordinal(place) })
		else TEXT.defeat
	return {
		kind = if won then "victory" else "defeat",
		title = title,
		line = if won then TEXT.youWin else Strings.format(TEXT.playerWins, { name = winnerName }),
		winScore = winnerKos,
		loseScore = nil,
		winColor = Palette.StickerCoinText,
		loseColor = nil,
		look = if winner then winner.look else NEUTRAL_LOOK,
		winnerName = Strings.format(TEXT.playerWins, { name = winnerName }),
	}
end

-- T:211: the winning team's most squishes (ties: fewer times squished, then the best streak); Free for All: the
-- winner; nil for a draw. teamOf(userId) -> their team.
function MatchEnd.mvp(view: any, teamOf: (userId: number) -> string?): number?
	local outcome = view.outcome
	if outcome.kind ~= "win" then
		return nil
	end
	if view.mode ~= "tdm" then
		return outcome.winnerUserId
	end
	local best: any = nil
	for _, s in outcome.standings or {} do
		if teamOf(s.userId) == outcome.winnerTeam then
			if
				best == nil
				or s.kos > best.kos
				or (s.kos == best.kos and s.knockedOut < best.knockedOut)
				or (s.kos == best.kos and s.knockedOut == best.knockedOut and s.bestStreak > best.bestStreak)
			then
				best = s
			end
		end
	end
	return if best then best.userId else nil
end

-- The scoreboard's two columns (S:976-978): the winning team first (a draw: yours), its players by squishes then fewer
-- times squished; Free for All: the standings, 1st-6th and 7th-12th. who(userId) -> MatchKit.Who.
function MatchEnd.columns(view: any, who: (userId: number) -> any): { Column }
	local outcome = view.outcome
	local standings = outcome.standings or {}
	local mvp = MatchEnd.mvp(view, function(userId: number): string?
		return who(userId).team
	end)
	local function row(s: any): Row
		local w = who(s.userId)
		return {
			userId = s.userId,
			name = w.name,
			kos = s.kos,
			knockedOut = s.knockedOut,
			bestStreak = s.bestStreak,
			grip = s.grip,
			you = w.you,
			mvp = s.userId == mvp,
			look = w.look,
		}
	end
	if view.mode ~= "tdm" then
		local top, rest = {}, {}
		for index, s in standings do
			table.insert(if index <= CFG.board.rows then top else rest, row(s))
		end
		return {
			{ title = TEXT.ffaTop, look = NEUTRAL_LOOK, rows = top },
			{ title = TEXT.ffaRest, look = NEUTRAL_LOOK, rows = rest },
		}
	end
	local first = if outcome.kind == "win" then outcome.winnerTeam else view.you.team
	first = first or TEAM_NAMES[1]
	local out: { Column } = {}
	for _, team in { first, otherTeam(first) } do
		local rows = {}
		for _, s in standings do
			if who(s.userId).team == team then
				table.insert(rows, row(s))
			end
		end
		table.sort(rows, function(a: Row, b: Row): boolean
			if a.kos ~= b.kos then
				return a.kos > b.kos
			end
			return a.knockedOut < b.knockedOut
		end)
		local res = if outcome.kind == "draw"
			then TEXT.chipDraw
			elseif team == outcome.winnerTeam then TEXT.win
			else TEXT.loss
		table.insert(out, {
			title = teamLabel(team),
			look = MatchHudFormat.playerLook("tdm", team, nil),
			score = if view.teamScore then view.teamScore[team] else nil,
			res = res,
			rows = rows,
		})
	end
	return out
end

-- The results' Grip bar (S:291-292): the level now and the fill before and after the match's `gained` (shares of the
-- level; from 0 when it levelled up). nil without a total.
function MatchEnd.gripBar(total: number?, gained: number): (number?, number, number)
	if total == nil then
		return nil, 0, 0
	end
	local now = GripMath.progress(total)
	local to = if now.isMax or now.span <= 0 then 1 else now.into / now.span
	local before = GripMath.progress(math.max(total - math.max(gained, 0), 0))
	local from = if before.level == now.level and before.span > 0 then before.into / before.span else 0
	return now.level, math.clamp(from, 0, 1), math.clamp(to, 0, 1)
end

-- The streak pill's words and whether its flame lights (S:999, T:38-39): it grew -> "Win streak n", lit; it went to
-- 0 -> "Streak reset"; nil without a pay.
function MatchEnd.streakLine(mine: any): (string?, boolean)
	if type(mine) ~= "table" then
		return nil, false
	end
	if mine.streakAfter > mine.streakBefore then
		return Strings.format(TEXT.winStreak, { n = mine.streakAfter }), true
	elseif mine.streakAfter == 0 and mine.streakBefore > 0 then
		return TEXT.streakReset, false
	end
	return Strings.format(TEXT.winStreak, { n = mine.streakAfter }), false
end

-- The name tags (S:975): the podium's players in its order (phones: only the MVP and you), each one's name and
-- squishes; the MVP is the crowned one on the cake.
function MatchEnd.plates(view: any, lineup: MatchPodium.Lineup, compact: boolean): { Plate }
	local kos: { [number]: number } = {}
	for _, s in (type(view.outcome) == "table" and view.outcome.standings) or {} do
		kos[s.userId] = s.kos
	end
	local names: { [number]: string } = {}
	for _, p in view.players or {} do
		names[p.userId] = p.displayName
	end
	local you = type(view.you) == "table" and view.you.userId or nil
	local out: { Plate } = {}
	for _, userId in lineup.ids do
		local mvp = lineup.cake and userId == lineup.mvp
		local mine = userId == you
		if not compact or mvp or mine then
			table.insert(
				out,
				{ userId = userId, name = names[userId] or "", kos = kos[userId] or 0, mvp = mvp, you = mine }
			)
		end
	end
	return out
end

-- S:893-910: the tags' places (top-left, stage px) from their boxes. Lowest on the screen first; a tag that meets one
-- placed before it moves up over it (one row), a third back under; none reaches above `top`; each x kept in
-- left .. right.
function MatchEnd.placePlates(boxes: { PlateBox }, top: number, left: number, right: number): { Vector2 }
	local gap = PLATES.gap
	local order: { number } = {}
	for i in boxes do
		table.insert(order, i)
	end
	table.sort(order, function(a: number, b: number): boolean
		return boxes[a].y > boxes[b].y
	end)
	local ys: { [number]: number } = {}
	local rows: { [number]: number } = {}
	for n, i in order do
		local A = boxes[i]
		local y, row = A.y, 0
		for m = 1, n - 1 do
			local j = order[m]
			local B = boxes[j]
			local by = ys[j]
			if math.abs(A.x - B.x) < (A.w + B.w) / 2 + gap and y > by - B.h - gap and y - A.h < by + 2 then
				if rows[j] == 0 and row == 0 then
					y, row = by - B.h - gap, 1
				elseif row == 1 then
					y, row = by + A.h + gap, 0
				end
			end
		end
		if y - A.h < top then
			y = top + A.h
		end
		ys[i], rows[i] = y, row
	end
	local out: { Vector2 } = {}
	for i, b in boxes do
		out[i] = Vector2.new(math.clamp(b.x - b.w / 2, left, math.max(left, right - b.w)), ys[i] - b.h)
	end
	return out
end

-- Private: builders ---------------------------------------------------------------------------------------------------

local function frame(name: string, props: { [string]: any }): Frame
	local made: Frame =
		Create("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false })
	for property, value in props do
		if property ~= "Parent" then
			(made :: any)[property] = value
		end
	end
	made.Parent = props.Parent
	return made
end

local function picture(name: string, key: string, props: { [string]: any }): ImageLabel
	local made: ImageLabel = Create("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Image = AssetTable.image(key) or "",
		ScaleType = Enum.ScaleType.Fit,
		Active = false,
	})
	for property, value in props do
		if property ~= "Parent" then
			(made :: any)[property] = value
		end
	end
	made.Parent = props.Parent
	return made
end

local function key(at: number, color: Color3): ColorSequenceKeypoint
	return ColorSequenceKeypoint.new(at, color)
end

local function gradient(object: GuiObject, keys: { ColorSequenceKeypoint }, rotation: number?): UIGradient
	object.BackgroundColor3 = WHITE
	return Create("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(keys), Parent = object })
end

local function lookKeys(look: MatchHudFormat.PlayerLook): { ColorSequenceKeypoint }
	local keys = { key(0, look.top) }
	if look.mid then
		table.insert(keys, key(0.58, look.mid))
	end
	table.insert(keys, key(1, look.faceEnd))
	return keys
end

local function posed(holder: GuiObject): Posed
	return { holder = holder, poser = Tweens.poser(holder), fades = { Tweens.fadeGroup(holder) } }
end

-- A box with the design's ink border inside, its radius and its solid ink lip `lip` px lower (box-shadow 0 Npx 0).
-- The face and the lip follow the holder's size (a scaleX on the holder stretches both).
local function box(name: string, size: Vector2, radius: number, border: number, lip: number, z: number): (Frame, Frame)
	local holder = frame(name, { Size = UDim2.fromOffset(size.X, size.Y + lip), ZIndex = z })
	if lip > 0 then
		local under = frame("Lip", {
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, lip),
			Size = UDim2.new(1, 0, 1, -lip),
			ZIndex = z,
			Parent = holder,
		})
		Theme.corner(radius, under)
	end
	local face = frame("Face", {
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 1, -lip),
		ZIndex = z + 1,
		Parent = holder,
	})
	Theme.corner(radius, face)
	if border > 0 then
		MatchKit.inner(Theme.stroke(INK, border, face))
	end
	return holder, face
end

-- One title letter (S:251-254): its ink shadow, the face in `color` with the ink outline and the white gloss over its
-- top half, drawn at the kind's size and scaled to the layout's letter px; returns the holder (anchored at its bottom
-- middle: the design's transform-origin 50% 100%) and its width.
local function letter(char: string, color: Color3, L: any, z: number): (Frame, number)
	local kind = L.letterText
	local k = L.letter / Theme.textSize(kind)
	local w = math.ceil(Theme.textWidth(char, kind :: any)) + MEASURE_MARGIN_PX
	local h = math.ceil(Theme.lineHeight(kind :: any))
	local holder = frame("Letter", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(math.round(w * k), L.letter),
		ZIndex = z,
	})
	local glyph = frame("Glyph", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
		Parent = holder,
	})
	Create("UIScale", { Name = "Size", Scale = k, Parent = glyph })
	local function layer(name: string, y: number, c: Color3, outline: boolean, layerZ: number): TextLabel
		local label = Theme.label({
			Name = name,
			Text = char,
			AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, y),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = layerZ,
			Active = false,
			Parent = glyph,
		}, kind :: any, nil, c)
		Theme.noOutline(label)
		if outline then
			MatchKit.ink(label, L.letterStroke / 2 / k)
		end
		return label
	end
	layer("Shadow", L.letterShadow / k, INK, true, z)
	layer("Face", 0, color, true, z + 1)
	local gloss = layer("Gloss", 0, WHITE, false, z + 2)
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.46, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = gloss,
	})
	return holder, math.round(w * k)
end

-- A design button (S:298-300): the gradient face, its ink border, the inset top highlight, the ink lip, the stroked
-- label; a TextButton holder that takes the taps (and the gamepad's selection, its lemon ring).
local function button(name: string, words: string, stops: { Color3 }, padX: number, L: any, z: number): (Button, number)
	local B = L.bar
	local label, labelSize = MatchKit.line("Label", words, L.buttonText, nil, B.buttonStroke, z + 3)
	local size = Vector2.new(labelSize.X + 2 * padX, B.buttonH)
	local root: TextButton = Create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y + 4),
		ZIndex = z,
		Active = true,
		Selectable = true,
	})
	local ring = frame("SelectionRing", { Size = UDim2.fromScale(1, 1) })
	Theme.corner(B.buttonRadius + 4, ring)
	Theme.stroke(Palette.Lemon, 4, ring)
	root.SelectionImageObject = ring
	local pose = frame("Pose", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = root,
	})
	local pulse = frame("Pulse", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = pose,
	})
	local holder, face = box("Box", size, B.buttonRadius, B.buttonBorder, 4, z)
	holder.Parent = pulse
	gradient(face, { key(0, stops[1]), key(0.55, stops[2]), key(1, stops[3]) })
	local highlight = frame("Highlight", {
		BackgroundTransparency = 0.5,
		BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(B.buttonRadius / 2, B.buttonBorder),
		Size = UDim2.new(1, -B.buttonRadius, 0, 3),
		ZIndex = z + 2,
		Parent = face,
	})
	Theme.corner(2, highlight)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Parent = face
	return { root = root, posed = posed(pose), pulse = pulse }, size.X
end

-- Private: the layers --------------------------------------------------------------------------------------------------

local function stage(name: string, parent: GuiObject, z: number): (Frame, UIScale)
	local made = frame(name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = z,
		Parent = parent,
	})
	return made, Create("UIScale", { Parent = made })
end

local function build(ctx: MatchHudFormat.Context, view: any, result: Result, onSkip: () -> ()): Made
	local L = CFG.layouts[if ctx.compact() then "phone" else "desktop"]
	local z0 = CFG.z
	local margin = CFG.margin
	local loops: { UiIdle.Handle } = {}
	local covers: { Frame | TextButton } = {}
	local stages, scales = {}, {}
	local victory = result.kind == "victory"

	local flash = frame("EndFlash", {
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
		ZIndex = z0,
		Parent = ctx.root,
	})
	table.insert(covers, flash)
	local main, mainScale = stage("End", ctx.root, z0 + 1)
	table.insert(stages, main)
	table.insert(scales, mainScale)

	-- The sunbursts and rings behind the title (S:234-237).
	local suns: { ImageLabel } = {}
	for index, spec in
		{ { SUN_A_KEY, L.sun, Palette.Lemon }, { SUN_B_KEY, L.sunB, result.look.mid or result.look.faceEnd } }
	do
		table.insert(
			suns,
			picture(if index == 1 then "SunA" else "SunB", spec[1], {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, L.titleY),
				Size = UDim2.fromOffset(spec[2], spec[2]),
				ImageColor3 = spec[3],
				ImageTransparency = 1,
				ScaleType = Enum.ScaleType.Stretch,
				ZIndex = z0 + 1,
				Parent = main,
			})
		)
	end
	local rings: { Frame } = {}
	for index, color in { WHITE, Palette.Lemon } do
		local ring = frame(if index == 1 then "Ring1" else "Ring2", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, L.titleY),
			Size = UDim2.fromOffset(L.ring, L.ring),
			Visible = false,
			ZIndex = z0 + 1,
			Parent = main,
		})
		Theme.corner(L.ring / 2, ring)
		MatchKit.inner(Theme.stroke(color, L.ringBorder, ring))
		Create("UIScale", { Name = "Grow", Parent = ring })
		table.insert(rings, ring)
	end

	-- The jelly wave (S:239-248), twice the stage wide; under ReducedMotion a colour fade (jellyX).
	local jellyColor = result.look.mid or result.look.faceEnd
	local J = L.jelly
	local jelly = frame("Jelly", {
		Position = UDim2.new(0, -2 * L.width, -0.06, 0),
		Size = UDim2.new(0, 2 * L.width, 1.12, 0),
		Visible = false,
		ZIndex = z0 + 2,
		Parent = main,
	})
	local body = frame("Body", {
		BackgroundTransparency = 0,
		BackgroundColor3 = jellyColor,
		Position = UDim2.fromOffset(J.tail, 0),
		Size = UDim2.new(1, -J.tail - J.edge, 1, 0),
		ZIndex = z0 + 2,
		Parent = jelly,
	})
	frame("Shade", {
		BackgroundTransparency = 0.88,
		BackgroundColor3 = INK,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.22),
		ZIndex = z0 + 3,
		Parent = body,
	})
	local bumpSize = math.round(L.height * 0.2)
	for i = 0, BUMPS - 1 do
		local bump = frame("Bump", {
			BackgroundTransparency = 0,
			BackgroundColor3 = jellyColor,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, i * 0.125, -math.round(L.height * 0.1)),
			Size = UDim2.fromOffset(bumpSize, bumpSize),
			ZIndex = z0 + 2,
			Parent = jelly,
		})
		Theme.corner(bumpSize / 2, bump)
	end
	for _, d in DRIPS do
		local w = math.round(J.tail * 0.95 * d[3] + 30)
		local hh = math.round(d[2] * (if ctx.compact() then 0.9 else 1.8))
		local drip = frame("Drip", {
			BackgroundTransparency = 0,
			BackgroundColor3 = jellyColor,
			Position = UDim2.new(0, math.round(J.tail - J.tail * 0.95 * d[3]), d[1] / 100, 0),
			Size = UDim2.fromOffset(w, hh),
			ZIndex = z0 + 2,
			Parent = jelly,
		})
		Theme.corner(hh / 2, drip)
	end
	local shine = frame("Shine", {
		BackgroundTransparency = 0.7,
		BackgroundColor3 = WHITE,
		Position = UDim2.new(0, J.highlightL, 0.12, 0),
		Size = UDim2.new(1, -J.highlightL - J.highlightR, 0.04, 0),
		ZIndex = z0 + 3,
		Parent = jelly,
	})
	Theme.corner(999, shine)
	for _, b in { { 0.4, 0.3, J.bubble, 0.75 }, { 0.62, 0.62, J.bubble2, 0.8 } } do
		local bubble = frame("Bubble", {
			BackgroundTransparency = b[4],
			BackgroundColor3 = WHITE,
			Position = UDim2.fromScale(b[1], b[2]),
			Size = UDim2.fromOffset(b[3], b[3]),
			ZIndex = z0 + 3,
			Parent = jelly,
		})
		Theme.corner(b[3] / 2, bubble)
	end
	local jellyX = frame("JellyX", {
		BackgroundColor3 = jellyColor,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
		Visible = false,
		ZIndex = z0 + 2,
		Parent = main,
	})

	-- The title (S:249-256): the plate behind, the letters on one line (no gaps), the title's centre at titleY.
	local fill = if victory then Palette.Lemon else Palette.MatchEndDefeatLetter
	local letters: { Letter } = {}
	local holders: { Frame } = {}
	local widths: { number } = {}
	local total = 0
	local chars = {}
	for _, code in utf8.codes(result.title) do
		table.insert(chars, utf8.char(code))
	end
	for index, char in chars do
		local bang = victory and index == #chars
		local holder, w = letter(char, if bang and char == "!" then Palette.MatchTeamRedScore else fill, L, z0 + 5)
		table.insert(holders, holder)
		table.insert(widths, w)
		total += w
	end
	local title = frame("Title", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, L.titleY),
		Size = UDim2.fromOffset(total, L.letter),
		ZIndex = z0 + 4,
		Parent = main,
	})
	local P = L.plate
	local plateSize = Vector2.new(total + 2 * P.pad, L.letter - P.top - P.bottom)
	local plateHolder, plateFace = box("Plate", plateSize, plateSize.Y / 2, P.border, P.shadow, z0 + 4)
	plateHolder.AnchorPoint = Vector2.new(0.5, 0)
	plateHolder.Position = UDim2.new(0.5, 0, 0, P.top)
	plateHolder.Parent = title
	gradient(
		plateFace,
		if victory
			then { key(0, Palette.MatchIntroTitle2), key(1, Palette.Lemon) }
			else { key(0, Palette.MatchIntroTitleEnd), key(1, Palette.MatchEndLilac) }
	)
	local gloss = frame("Gloss", {
		BackgroundTransparency = 0.55,
		BackgroundColor3 = WHITE,
		Position = UDim2.fromScale(0.06, 0.09),
		Size = UDim2.fromScale(0.88, 0.24),
		ZIndex = z0 + 5,
		Parent = plateFace,
	})
	Theme.corner(999, gloss)
	local x = 0
	for index, holder in holders do
		holder.Position = UDim2.fromOffset(math.round(x + widths[index] / 2), L.letter)
		holder.Parent = title
		x += widths[index]
		table.insert(letters, { posed = posed(holder), bang = victory and index == #holders })
	end

	-- Under the title (S:257-262): the crest, "X WINS", the rolling score.
	local subH = math.max(L.crest, math.ceil(Theme.lineHeight(L.numText :: any)))
	local sub = frame("Sub", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, L.subY),
		ZIndex = z0 + 4,
		Parent = main,
	})
	local crest = frame("Crest", { Size = UDim2.fromOffset(L.crest, L.crest), ZIndex = z0 + 4, Parent = sub })
	local crestInner = L.crest - 2 * L.crestIn
	local crestBox, crestFace = box(
		"Shape",
		Vector2.new(crestInner, crestInner),
		if victory then 14 else crestInner / 2,
		L.crestBorder,
		3,
		z0 + 4
	)
	crestBox.AnchorPoint = Vector2.new(0.5, 0.5)
	crestBox.Position = UDim2.fromScale(0.5, 0.5)
	crestBox.Rotation = if victory then 45 else 0
	crestBox.Parent = crest
	gradient(crestFace, lookKeys(result.look))
	local disc = frame("Disc", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Frosting,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.38, 0.38),
		ZIndex = z0 + 6,
		Parent = crest,
	})
	Theme.corner(999, disc)
	Theme.stroke(INK, 2, disc)
	local words, wordsSize = MatchKit.line("Line", result.line, L.subText, nil, L.subStroke, z0 + 4)
	local parts: { { object: GuiObject, w: number } } =
		{ { object = crest, w = L.crest }, { object = words, w = wordsSize.X } }
	local rollWin: TextLabel? = nil
	local rollLose: TextLabel? = nil
	if result.winScore then
		local final = tostring(result.winScore)
		local win, winSize = MatchKit.line("Win", final, L.numText, result.winColor, L.subStroke, z0 + 4)
		rollWin = win
		table.insert(parts, { object = win, w = winSize.X })
		if result.loseScore then
			local dash, dashSize = MatchKit.line("Dash", "–", L.numText, nil, L.subStroke, z0 + 4)
			local lose, loseSize =
				MatchKit.line("Lose", tostring(result.loseScore), L.numText, result.loseColor, L.subStroke, z0 + 4)
			rollLose = lose
			table.insert(parts, { object = dash, w = dashSize.X })
			table.insert(parts, { object = lose, w = loseSize.X })
		end
	end
	local sx = 0
	for index, part in parts do
		part.object.AnchorPoint = Vector2.new(0, 0.5)
		part.object.Position = UDim2.new(0, sx, 0.5, 0)
		part.object.Parent = sub
		sx += part.w + (if index == 1 then L.subGap elseif index == 2 then L.subGap else 6)
	end
	sub.Size = UDim2.fromOffset(sx, subH)

	-- The pill (S:263-265, desktop only).
	local psub: Posed? = nil
	if L.showPsub then
		local modeLine = string.upper(Strings.match.mode[view.mode] or "")
		local rules = Config.Match.Modes[view.mode]
		local players = if rules then rules.maxPlayers else #view.players
		local size = Strings.format(
			Strings.matchHud.intro.size[view.mode] or Strings.matchHud.intro.size.ffa,
			{ n = if view.mode == "tdm" then players // 2 else players }
		)
		local score = if result.winScore and result.loseScore
			then `{result.winScore}–{result.loseScore}`
			elseif result.winScore then tostring(result.winScore)
			else nil
		local resultLine = if score
			then Strings.format(TEXT.psubScore, { line = result.winnerName, score = score })
			else result.winnerName
		local words2 = Strings.format(
			TEXT.psub,
			{ mode = modeLine, size = size, result = resultLine, map = string.upper(view.mapName or "") }
		)
		local label, labelSize = MatchKit.spaced("Text", words2, L.psubText, Palette.Frosting, nil, 0.04, z0 + 5)
		local pillSize = Vector2.new(labelSize.X + 2 * L.psubPad, L.psubH)
		local holder, face = box("Psub", pillSize, L.psubH / 2, L.psubBorder, 3, z0 + 4)
		face.BackgroundColor3 = Palette.MatchIntroCard
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, L.psubTop)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Parent = face
		holder.Parent = main
		psub = posed(holder)
	end

	local sparkLayer = frame("Sprinkles", { Size = UDim2.fromScale(1, 1), ZIndex = z0 + 6, Parent = main })
	local plateLayer = frame("Plates", { Size = UDim2.fromScale(1, 1), ZIndex = z0 + 6, Parent = main })

	-- The results bar (S:282-302).
	local B = L.bar
	local mine = view.outcome.mine
	local coinsFinal = Strings.format(TEXT.gain, { n = Format.coins(if mine then mine.coins else 0) })
	local streakWords = MatchEnd.streakLine(mine)
	local stageW = L.width
	local barW = math.min(B.maxWidth, stageW - B.sideRoom)
	local inner = barW - 2 * B.pad - (if B.panel then 2 * B.border else 0)
	local barHolder, barFace = box(
		"Bar",
		Vector2.new(barW, B.height),
		B.radius,
		if B.panel then B.border else 0,
		if B.panel then B.shadow else 0,
		z0 + 7
	)
	barHolder.AnchorPoint = Vector2.new(0.5, 1)
	barHolder.Position = UDim2.new(0.5, 0, 1, -B.bottom)
	barHolder.Parent = main
	if B.panel then
		barFace.BackgroundColor3 = Palette.MatchIntroCard
	else
		barFace.BackgroundTransparency = 1
		local lip = barHolder:FindFirstChild("Lip")
		if lip then
			lip:Destroy()
		end
	end
	local row = frame("Row", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, B.pad + (if B.panel then B.border else 0), 0.5, 0),
		Size = UDim2.fromOffset(inner, B.height),
		ZIndex = z0 + 8,
		Parent = barFace,
	})
	local pieces: { { object: GuiObject, w: number, h: number } } = {}
	if B.chip then
		local chipLabel, chipSize = MatchKit.line(
			"Label",
			if result.kind == "victory"
				then TEXT.chipVictory
				elseif result.kind == "defeat" then TEXT.chipDefeat
				else TEXT.chipDraw,
			L.chipText,
			nil,
			6,
			z0 + 10
		)
		local chipHolder, chipFace = box("Chip", Vector2.new(chipSize.X + 32, B.buttonH), 18, 4, 0, z0 + 8)
		gradient(
			chipFace,
			if result.kind == "victory"
				then { key(0, Palette.MatchIntroTitle2), key(1, Palette.Lemon) }
				else { key(0, Palette.MatchIntroTitleEnd), key(1, Palette.MatchEndLilac) }
		)
		chipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		chipLabel.Position = UDim2.fromScale(0.5, 0.5)
		chipLabel.Parent = chipFace
		table.insert(pieces, { object = chipHolder, w = chipSize.X + 32, h = B.buttonH })
	end
	-- The Coins pill.
	local coinText, coinSize =
		MatchKit.line("Coins", coinsFinal, L.rewText, Palette.StickerCoinText, B.rewStroke, z0 + 10)
	local coinW = math.max(B.coinMin, coinSize.X)
	local coinPillW = B.pillBorder + 4 + B.icon + 4 + coinW + B.pillPad + B.pillBorder
	local coinHolder, coinFace = box("CoinPill", Vector2.new(coinPillW, B.pillH), B.pillH / 2, B.pillBorder, 0, z0 + 8)
	coinFace.BackgroundColor3 = Palette.MatchEndPill
	picture("Icon", COIN_KEY, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, B.pillBorder + 4, 0.5, 0),
		Size = UDim2.fromOffset(B.icon, B.icon),
		ZIndex = z0 + 10,
		Parent = coinFace,
	})
	coinText.AnchorPoint = Vector2.new(0, 0.5)
	coinText.Position = UDim2.new(0, B.pillBorder + 8 + B.icon, 0.5, 0)
	coinText.Size = UDim2.fromOffset(coinW, coinText.Size.Y.Offset)
	coinText.TextXAlignment = Enum.TextXAlignment.Left
	coinText.Text = Strings.format(TEXT.gain, { n = 0 })
	coinText.Parent = coinFace
	table.insert(pieces, { object = coinHolder, w = coinPillW, h = B.pillH })
	-- The Grip box (its width set below: the room left, between gripMin and gripMax).
	local gripHolder, gripFace = box("Grip", Vector2.new(B.gripMin, B.pillH), B.pillH / 2, B.gripBorder, 0, z0 + 8)
	gripFace.BackgroundTransparency = if B.gripBorder > 0 then 0 else 1
	gripFace.BackgroundColor3 = Palette.MatchIntroCard
	picture("Icon", GRIP_KEY, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, B.gripPadL, 0.5, 0),
		Size = UDim2.fromOffset(B.icon, B.icon),
		ZIndex = z0 + 10,
		Parent = gripFace,
	})
	local column = frame("Column", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, B.gripPadL + B.icon + 6, 0.5, 0),
		Size = UDim2.new(1, -(B.gripPadL + B.icon + 6 + B.gripPadR), 0, Theme.textSize(L.gripText) + 3 + B.gripBarH),
		ZIndex = z0 + 9,
		Parent = gripFace,
	})
	local gripLevel = MatchKit.line(
		"Level",
		Strings.format(TEXT.gripLevel, { level = 1 }),
		L.gripText,
		Palette.Frosting,
		nil,
		z0 + 10
	)
	gripLevel.AnchorPoint = Vector2.new(0, 0.5)
	gripLevel.Position = UDim2.new(0, 0, 0, Theme.textSize(L.gripText) / 2)
	gripLevel.TextXAlignment = Enum.TextXAlignment.Left
	gripLevel.Parent = column
	local gripText = MatchKit.line(
		"Gain",
		Strings.format(TEXT.gain, { n = Format.coins(if mine then mine.grip else 0) }),
		L.gripText,
		Palette.StickerMintTop,
		nil,
		z0 + 10
	)
	gripText.AnchorPoint = Vector2.new(1, 0.5)
	gripText.Position = UDim2.new(1, 0, 0, Theme.textSize(L.gripText) / 2)
	gripText.TextXAlignment = Enum.TextXAlignment.Right
	gripText.Text = Strings.format(TEXT.gain, { n = 0 })
	gripText.Parent = column
	local trough = frame("Trough", {
		BackgroundTransparency = 0.4,
		BackgroundColor3 = Palette.MatchEndShade,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, B.gripBarH),
		ClipsDescendants = true,
		ZIndex = z0 + 9,
		Parent = column,
	})
	Theme.corner(B.gripBarH / 2, trough)
	MatchKit.inner(Theme.stroke(INK, 2, trough))
	local gripFill = frame("Fill", {
		BackgroundTransparency = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = z0 + 10,
		Parent = trough,
	})
	Theme.corner(B.gripBarH / 2, gripFill)
	gradient(gripFill, { key(0, Palette.StickerGripTop), key(1, Palette.StickerGripEnd) })
	local gripPiece = { object = gripHolder :: GuiObject, w = B.gripMin, h = B.pillH }
	table.insert(pieces, gripPiece)
	-- The win streak's pill (desktop).
	local flame: Posed? = nil
	if B.streak and streakWords then
		local words3, wordsSize3 = MatchKit.line("Text", streakWords, L.streakText, nil, nil, z0 + 10)
		local w = B.pillBorder + 4 + B.icon + 4 + wordsSize3.X + B.pillPad + B.pillBorder
		local holder, face = box("Streak", Vector2.new(w, B.pillH), B.pillH / 2, B.pillBorder, 0, z0 + 8)
		face.BackgroundColor3 = Palette.MatchEndPill
		local flameHolder = frame("Flame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, B.pillBorder + 4 + B.icon / 2, 0.5, -3),
			Size = UDim2.fromOffset(B.icon, B.icon),
			ZIndex = z0 + 10,
			Parent = face,
		})
		picture("Icon", FLAME_KEY, { Size = UDim2.fromScale(1, 1), ZIndex = z0 + 10, Parent = flameHolder })
		words3.AnchorPoint = Vector2.new(0, 0.5)
		words3.Position = UDim2.new(0, B.pillBorder + 8 + B.icon, 0.5, 0)
		words3.TextXAlignment = Enum.TextXAlignment.Left
		words3.Parent = face
		flame = posed(flameHolder)
		table.insert(pieces, { object = holder, w = w, h = B.pillH })
	end
	-- The buttons (S:297-301), at the bar's right end.
	local buttons: { Button } = {}
	local buttonsW = 0
	local specs = {
		{
			"Scoreboard",
			TEXT.scoreboard,
			{ Palette.MatchIntroTitleEnd, Palette.MatchEndLilac, Palette.MatchEndLilacEnd },
			B.buttonPad,
		},
		{
			"Lobby",
			TEXT.lobby,
			{ Palette.StickerCyanTop, Palette.StickerCyanMid, Palette.StickerCyanEnd },
			B.buttonPad,
		},
		{
			"PlayAgain",
			TEXT.again,
			{ Palette.StickerGreenTop, Palette.StickerGreenMid, Palette.StickerGreenEnd },
			B.buttonPadAgain,
		},
	}
	for index, spec in specs do
		local made, w = button(spec[1], spec[2], spec[3], spec[4], L, z0 + 8)
		table.insert(buttons, made)
		buttonsW += w + (if index > 1 then B.buttonGap else 0)
	end
	-- Lay the row out: the rewards from the left, the buttons from the right; the Grip box takes the room left.
	local fixed = 0
	for _, piece in pieces do
		if piece ~= gripPiece then
			fixed += piece.w
		end
	end
	local gaps = (#pieces - 1) * B.rewardGap + (if B.chip then B.gap - B.rewardGap else 0) + B.gap
	local gripW = math.clamp(inner - buttonsW - fixed - gaps, B.gripMin, B.gripMax)
	gripPiece.w = gripW
	gripHolder.Size = UDim2.fromOffset(gripW, B.pillH)
	local px = 0
	for index, piece in pieces do
		piece.object.AnchorPoint = Vector2.new(0, 0.5)
		piece.object.Position = UDim2.new(0, px, 0.5, 0)
		piece.object.Parent = row
		px += piece.w + (if index == 1 and B.chip then B.gap else B.rewardGap)
	end
	local bx = inner
	for index = #buttons, 1, -1 do
		local b = buttons[index]
		local w = b.root.Size.X.Offset
		b.root.AnchorPoint = Vector2.new(0, 0.5)
		b.root.Position = UDim2.new(0, bx - w, 0.5, 2)
		b.root.Parent = row
		bx -= w + B.buttonGap
	end

	-- TAP TO SKIP (S:303) and the tap catcher over the whole screen until the results.
	local skipLabel, skipSize = MatchKit.spaced("Text", TEXT.skip, L.skipText, Palette.Frosting, nil, 0.06, z0 + 12)
	local skipHolder = frame("Skip", {
		BackgroundTransparency = 0.4,
		BackgroundColor3 = INK,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(skipSize.X + 24, 28),
		ZIndex = z0 + 11,
		Parent = main,
	})
	Theme.corner(14, skipHolder)
	MatchKit.inner(Theme.stroke(Palette.Frosting, 2, skipHolder, 0.5))
	skipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	skipLabel.Position = UDim2.fromScale(0.5, 0.5)
	skipLabel.Parent = skipHolder
	local catcher: TextButton = Create("TextButton", {
		Name = "SkipCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
		ZIndex = z0 + 2,
		Active = true,
		Selectable = false,
		Visible = false,
		Parent = ctx.root,
	})
	catcher.Activated:Connect(onSkip)
	table.insert(covers, catcher)

	return {
		layout = L,
		covers = covers,
		stages = stages,
		scales = scales,
		flash = flash,
		stage = main,
		suns = suns,
		rings = rings,
		jelly = jelly,
		jellyX = jellyX,
		title = posed(title),
		letters = letters,
		plate = posed(plateHolder),
		sub = posed(sub),
		crest = posed(crest),
		rollWin = rollWin,
		rollLose = rollLose,
		psub = psub,
		sparkLayer = sparkLayer,
		plateLayer = plateLayer,
		bar = posed(barHolder),
		coinText = coinText,
		gripText = gripText,
		gripLevel = gripLevel,
		gripFill = gripFill,
		gripInner = gripW - (B.gripPadL + B.icon + 6 + B.gripPadR),
		flame = flame,
		buttons = buttons,
		skip = posed(skipHolder),
		catcher = catcher,
		loops = loops,
	}
end

local function fit(made: Made, canvas: Vector2)
	local L = made.layout
	local k = if canvas.X > 0 and canvas.Y > 0
		then math.max(0.05, math.min(canvas.X / L.width, canvas.Y / L.height))
		else 1
	local size = Vector2.new(math.max(canvas.X / k, L.width), math.max(canvas.Y / k, L.height))
	for index, s in made.stages do
		s.Size = UDim2.fromOffset(math.round(size.X), math.round(size.Y))
		made.scales[index].Scale = k
	end
end

-- The scoreboard (S:305-330), built when it first opens: its backdrop over the screen and its panel on a stage.
local function board(ctx: MatchHudFormat.Context, view: any, L: any, onClose: () -> ()): { Frame | TextButton }
	local Bd = L.board
	local z = CFG.z + 30
	local backdrop: TextButton = Create("TextButton", {
		Name = "BoardBackdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.MatchEndShade,
		BackgroundTransparency = 1 - CFG.board.backdropAlpha,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * CFG.margin, 1, 2 * CFG.margin),
		ZIndex = z,
		Active = true,
		Selectable = false,
		Parent = ctx.root,
	})
	backdrop.Activated:Connect(onClose)
	local holder = stage("BoardStage", ctx.root, z + 1) -- fitted by the caller, as the main stage
	local columns = MatchEnd.columns(view, function(userId: number): any
		return MatchKit.who(ctx, view, userId)
	end)
	local colW = (Bd.width - 2 * Bd.pad - 2 * Bd.border - Bd.gap) / 2
	local rowsN = 0
	for _, column in columns do
		rowsN = math.max(rowsN, #column.rows)
	end
	local smallH = math.ceil(Theme.lineHeight(L.boardText :: any))
	local titleH = 44
	local height = 2 * Bd.border
		+ 2 * Bd.pad
		+ titleH
		+ Bd.gap
		+ Bd.head
		+ Bd.rowGap
		+ smallH
		+ Bd.rowGap
		+ rowsN * (Bd.row + Bd.rowGap)
	local panelHolder, panel = box("Board", Vector2.new(Bd.width, height), Bd.radius, Bd.border, Bd.shadow, z + 1)
	panel.BackgroundColor3 = Palette.MatchIntroCard
	panelHolder.AnchorPoint = Vector2.new(if Bd.left then 0 else 0.5, 0)
	panelHolder.Position = if Bd.left then UDim2.fromOffset(Bd.left, Bd.top) else UDim2.new(0.5, 0, 0, Bd.top)
	panelHolder.Parent = holder
	local inset = Bd.border + Bd.pad
	local heading = MatchKit.spaced("Title", TEXT.scoreboard, L.boardTitleText, nil, Bd.titleStroke, 0.06, z + 3)
	heading.AnchorPoint = Vector2.new(0, 0.5)
	heading.Position = UDim2.fromOffset(inset, inset + titleH / 2)
	heading.Parent = panel
	local close: TextButton = Create("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.MatchEndPill,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -inset, 0, inset),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = z + 3,
		Active = true,
		Selectable = true,
		Parent = panel,
	})
	Theme.corner(12, close)
	MatchKit.inner(Theme.stroke(INK, 3, close))
	picture("Icon", CLOSE_KEY, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(24, 24),
		ZIndex = z + 4,
		Parent = close,
	})
	close.Activated:Connect(onClose)
	-- The columns: the head bar, the column titles, the rows.
	local fixed = 0
	for _, w in Bd.cols do
		fixed += w
	end
	local rowInner = colW - 16
	local nameW = rowInner - fixed - 5 * 6
	local xs, cx = {}, 8 -- each cell's left edge in a row (padding 0 8, gap 6)
	for _, w in Bd.cols do
		table.insert(xs, cx)
		cx += (if w == 0 then nameW else w) + 6
	end
	local function widthOf(index: number): number
		local w = Bd.cols[index]
		return if w == 0 then nameW else w
	end
	for c, column in columns do
		local x0 = inset + (c - 1) * (colW + Bd.gap)
		local y = inset + titleH + Bd.gap
		local headHolder, headFace = box("Head", Vector2.new(colW, Bd.head), 10, 2, 0, z + 2)
		headHolder.Position = UDim2.fromOffset(x0, y)
		headHolder.Parent = panel
		gradient(headFace, lookKeys(column.look))
		local name = MatchKit.spaced("Name", column.title, L.boardText, nil, 3, 0.08, z + 4)
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.new(0, 10, 0.5, 0)
		name.Parent = headFace
		local right = colW - 10
		if column.res then
			local resLabel, resSize = MatchKit.line("Res", column.res, L.boardText, Palette.Frosting, nil, z + 5)
			local chip = frame("ResChip", {
				BackgroundTransparency = 0,
				BackgroundColor3 = INK,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(0, right, 0.5, 0),
				Size = UDim2.fromOffset(resSize.X + 12, 20),
				ZIndex = z + 4,
				Parent = headFace,
			})
			Theme.corner(6, chip)
			resLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			resLabel.Position = UDim2.fromScale(0.5, 0.5)
			resLabel.Parent = chip
			right -= resSize.X + 12 + 8
		end
		if column.score then
			local scoreLabel = MatchKit.line("Score", tostring(column.score), L.boardText, nil, 3, z + 4)
			scoreLabel.AnchorPoint = Vector2.new(1, 0.5)
			scoreLabel.Position = UDim2.new(0, right, 0.5, 0)
			scoreLabel.Parent = headFace
		end
		y += Bd.head + Bd.rowGap
		local titles = { "", TEXT.cols.name, TEXT.cols.squishes, TEXT.cols.squished, TEXT.cols.best, TEXT.cols.grip }
		for index, words in titles do
			if words ~= "" then
				local label = MatchKit.line("Col", words, L.boardText, Palette.MatchEndMuted, nil, z + 3)
				local align = if index == 2 then 0 elseif index == 6 then 1 else 0.5
				label.AnchorPoint = Vector2.new(align, 0)
				label.Position = UDim2.fromOffset(x0 + xs[index] + widthOf(index) * align, y)
				label.TextXAlignment = if index == 2
					then Enum.TextXAlignment.Left
					elseif index == 6 then Enum.TextXAlignment.Right
					else Enum.TextXAlignment.Center
				label.Parent = panel
			end
		end
		y += smallH + Bd.rowGap
		for _, r in column.rows do
			local rowFrame = frame("Row", {
				BackgroundTransparency = if r.you then 0.84 else 0.95,
				BackgroundColor3 = if r.you then Palette.Lemon else Palette.Frosting,
				Position = UDim2.fromOffset(x0, y),
				Size = UDim2.fromOffset(colW, Bd.row),
				ZIndex = z + 2,
				Parent = panel,
			})
			Theme.corner(10, rowFrame)
			if r.you then
				MatchKit.inner(Theme.stroke(Palette.Lemon, 2, rowFrame))
			end
			local headBox = MatchKit.head({
				name = "Head",
				who = MatchKit.who(ctx, view, r.userId),
				size = Bd.headSize,
				border = 2,
				radius = 8,
				z = z + 3,
			})
			headBox.AnchorPoint = Vector2.new(0, 0.5)
			headBox.Position = UDim2.new(0, xs[1], 0.5, 0)
			headBox.Parent = rowFrame
			local fg = if r.you then Palette.Lemon else Palette.Frosting
			local tagW = 0
			if r.mvp then
				local tagLabel, tagSize = MatchKit.line("Mvp", TEXT.mvp, L.boardText, INK, nil, z + 5)
				local tag = frame("MvpTag", {
					BackgroundTransparency = 0,
					BackgroundColor3 = Palette.Lemon,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0, xs[2] + nameW, 0.5, 0),
					Size = UDim2.fromOffset(tagSize.X + 10, 18),
					ZIndex = z + 4,
					Parent = rowFrame,
				})
				Theme.corner(5, tag)
				tagLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				tagLabel.Position = UDim2.fromScale(0.5, 0.5)
				tagLabel.Parent = tag
				tagW = tagSize.X + 15
			end
			local clipped = MatchHudFormat.clipText(r.name, nameW - tagW, function(s: string): number
				return Theme.textWidth(s, L.boardText :: any)
			end)
			local nameLabel = MatchKit.line("Name", clipped, L.boardText, fg, nil, z + 4)
			nameLabel.AnchorPoint = Vector2.new(0, 0.5)
			nameLabel.Position = UDim2.new(0, xs[2], 0.5, 0)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = rowFrame
			local values = {
				{ tostring(r.kos), Palette.StickerCoinText, 0.5 },
				{ tostring(r.knockedOut), Palette.MatchTeamRedTop, 0.5 },
				{ tostring(r.bestStreak), Palette.Frosting, 0.5 },
				{
					if r.grip then Strings.format(TEXT.gain, { n = Format.coins(r.grip) }) else TEXT.noGrip,
					Palette.StickerMintTop,
					1,
				},
			}
			for index, value in values do
				local cell = index + 2
				local label = MatchKit.line("Value", value[1], L.boardText, value[2], nil, z + 4)
				label.AnchorPoint = Vector2.new(value[3], 0.5)
				label.Position = UDim2.new(0, xs[cell] + widthOf(cell) * value[3], 0.5, 0)
				label.TextXAlignment = if value[3] == 1 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
				label.Parent = rowFrame
			end
			y += Bd.row + Bd.rowGap
		end
	end
	return { backdrop, holder, panelHolder }
end

-- One name tag (S:272-277), its inner holder posed for the pop (from its bottom middle): the pill with its ink lip (the
-- MVP's gold, else the dark plate; yours with a lemon border), the MVP's crown, the name (cut with "…" past the tag's
-- max width), the squishes chip, and the MVP tag over it (YOU over that: S:276-277 draws it last). Text is the
-- `plates.text` kind scaled to the design's px.
local function plateOf(p: Plate, L: any, parent: Frame, z: number): PlateMade
	local P = L.plates
	local kind = PLATES.text
	local function words(name: string, str: string, px: number, color: Color3, em: number?): (GuiObject, Vector2)
		local object: GuiObject, size: Vector2
		if em then
			object, size = MatchKit.spaced(name, str, kind, color, nil, em, z + 4)
		else
			object, size = MatchKit.line(name, str, kind, color, nil, z + 4)
		end
		Theme.noOutline(object)
		for _, d in object:GetDescendants() do
			if d:IsA("TextLabel") then
				Theme.noOutline(d)
			end
		end
		local k = px / Theme.textSize(kind)
		Create("UIScale", { Scale = k, Parent = object })
		return object, size * k
	end
	local fg = if p.mvp then INK else Palette.Frosting
	local chipFg = if p.mvp then Palette.Lemon else Palette.StickerCoinText
	local num, numSize = words("Num", tostring(p.kos), P.chip, chipFg)
	local unit: GuiObject?, unitSize = nil, Vector2.zero
	if P.unit then
		unit, unitSize = words("Unit", TEXT.plateUnit, P.chipLabel, chipFg, 0.04)
	end
	local chipW = math.ceil(numSize.X + (if unit then P.unitGap + unitSize.X else 0)) + 2 * P.chipPad
	local crownW = if p.mvp then P.crownW + P.gap else 0
	local maxW = if p.mvp then P.mvpMaxW else P.maxW
	local room = maxW - 2 * (P.border + P.pad) - crownW - P.gap - chipW
	local k = P.name / Theme.textSize(kind)
	local shown = p.name
	if Theme.textWidth(shown, kind :: any) * k > room then
		local chars = {}
		for _, code in utf8.codes(p.name) do
			table.insert(chars, utf8.char(code))
		end
		repeat
			table.remove(chars)
			shown = table.concat(chars) .. "…"
		until #chars == 0 or Theme.textWidth(shown, kind :: any) * k <= room
	end
	local nameLabel, nameSize = words("Name", shown, P.name, fg)
	local w = math.ceil(2 * (P.border + P.pad) + crownW + nameSize.X + P.gap + chipW)
	local h = P.height
	local holder =
		frame("Plate", { Size = UDim2.fromOffset(w, h + P.lip), ZIndex = z, Visible = false, Parent = parent })
	local inner = frame("Pop", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
	})
	local tag, face = box("Tag", Vector2.new(w, h), P.radius, P.border, P.lip, z)
	tag.Parent = inner
	if p.mvp then
		gradient(face, { key(0, Palette.MatchIntroTitle2), key(1, Palette.Lemon) })
	else
		face.BackgroundColor3 = Palette.MatchIntroCard
	end
	if p.you then
		local stroke = face:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Palette.Lemon
		end
	end
	local x = P.border + P.pad
	if p.mvp then
		-- S:273: the crown icon: a band and three diamonds, each ink-bordered on cream
		local icon = frame("Crown", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, x, 0.5, 0),
			Size = UDim2.fromOffset(P.crownW, P.crownH),
			ZIndex = z + 3,
			Parent = face,
		})
		local function piece(name: string, pos: UDim2, size: UDim2, rot: number)
			local made = frame(name, {
				BackgroundTransparency = 0,
				BackgroundColor3 = Palette.MatchIntroTitle2,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = pos,
				Size = size,
				Rotation = rot,
				ZIndex = z + 3,
				Parent = icon,
			})
			Theme.corner(3, made)
			MatchKit.inner(Theme.stroke(INK, 2, made))
		end
		piece("Band", UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.45), 0)
		piece("Left", UDim2.fromScale(0.04 + 0.15, 0.7), UDim2.fromScale(0.3, 0.42), 45)
		piece("Middle", UDim2.fromScale(0.35 + 0.15, 0.64), UDim2.fromScale(0.3, 0.44), 45)
		piece("Right", UDim2.fromScale(1 - 0.04 - 0.15, 0.7), UDim2.fromScale(0.3, 0.42), 45)
		x += P.crownW + P.gap
	end
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0, x, 0.5, 0)
	nameLabel.Parent = face
	local chip = frame("Chip", {
		BackgroundTransparency = if p.mvp then 0 else P.chipAlpha,
		BackgroundColor3 = if p.mvp then INK else Palette.Frosting,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(P.border + P.pad), 0.5, 0),
		Size = UDim2.fromOffset(chipW, P.chipH),
		ZIndex = z + 3,
		Parent = face,
	})
	Theme.corner(P.chipH / 2, chip)
	num.AnchorPoint = Vector2.new(0, 0.5)
	num.Position = UDim2.new(0, P.chipPad, 0.5, 0)
	num.Parent = chip
	if unit then
		unit.AnchorPoint = Vector2.new(0, 0.5)
		unit.Position = UDim2.new(0, P.chipPad + numSize.X + P.unitGap, 0.5, 0)
		unit.Parent = chip
	end
	for _, spec in { { p.mvp, TEXT.mvp, INK, Palette.Lemon, 0.08 }, { p.you, TEXT.plateYou, Palette.Lemon, INK, 0.06 } } do
		if spec[1] then
			local label, size = words("Text", spec[2], P.tag, spec[4], spec[5])
			local pill = frame(if spec[2] == TEXT.mvp then "MvpTag" else "YouTag", {
				BackgroundTransparency = 0,
				BackgroundColor3 = spec[3],
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, -P.tagTop),
				Size = UDim2.fromOffset(math.ceil(size.X) + 2 * P.tagPad, P.tagH),
				ZIndex = z + 5,
				Parent = inner,
			})
			Theme.corner(7, pill)
			MatchKit.inner(Theme.stroke(INK, 2, pill))
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.ZIndex = z + 6
			label.Parent = pill
		end
	end
	return { userId = p.userId, holder = holder, posed = posed(inner), w = w, h = h }
end

-- Private: the letters' tracks -----------------------------------------------------------------------------------------

type Key = { at: number, alpha: number, y: number, sx: number, sy: number, rot: number, ease: string? }

-- A @keyframes run with the design's whole-run easing `whole` and each segment's own easing (S:797: the fall's), at u
-- in 0..1: { alpha, y, scale (the even part of sx, sy), rot }.
local function keyed(frames: { Key }, u: number, whole: string): (number, number, number, number)
	local w = Tweens.curve(whole)(math.clamp(u, 0, 1))
	local from, to = frames[1], frames[#frames]
	for index = 1, #frames - 1 do
		if w <= frames[index + 1].at then
			from, to = frames[index], frames[index + 1]
			break
		end
	end
	local span = to.at - from.at
	local k = if span > 0 then math.clamp((w - from.at) / span, 0, 1) else 1
	if from.ease then
		k = Tweens.curve(from.ease)(k)
	end
	local function lerp(a: number, b: number): number
		return a + (b - a) * k
	end
	local sx, sy = lerp(from.sx, to.sx), lerp(from.sy, to.sy)
	return lerp(from.alpha, to.alpha), lerp(from.y, to.y), math.sqrt(math.max(sx * sy, 0)), lerp(from.rot, to.rot)
end

local function rest(at: number): Key
	return { at = at, alpha = 1, y = 0, sx = 1, sy = 1, rot = 0 }
end

-- Public --------------------------------------------------------------------------------------------------------------

function MatchEnd.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local made: Made? = nil
	local result: Result? = nil
	local frozen: any = nil -- the view the screen reads (the Result freeze)
	local startAt: number? = nil -- os.clock of the last squish's view
	local skippedAt: number? = nil
	local resultsAt: number? = nil
	local fast = false
	local played: { [string]: boolean } = {}
	local sparks: { Spark } = {}
	local cheer: any = nil -- the crowd's cheering bed (a SoundController loop)
	local cheerAt = 0 -- it fades in from here over cheerFadeMs
	local cheerFadeMs = 0
	local bangAt: number? = nil -- the "!" landed
	local boardParts: { Instance }? = nil
	local boardPosed: Posed? = nil
	local boardAt = 0
	local interactive = false
	local gripTo, gripFrom = 0, 0
	local connections: { RBXScriptConnection } = {}
	local finished = false
	local podium: MatchPodium.Podium? = nil -- round B1: the 3D scene behind the screen
	local podiumTried = false
	local podiumLineup: MatchPodium.Lineup? = nil
	local slamAt: number? = nil -- the MVP's slam (its screen flash)
	local slamStrong = false
	local plateMade: { PlateMade }? = nil
	local platesAt = 0

	local function play(name: string, opts: { [string]: any }?)
		ctx.play(name, opts)
	end

	local function endPodium()
		local pod = podium
		podium = nil
		if pod then
			local ok, err = pcall(pod.destroy, pod)
			if not ok then
				warn(`[SD][MatchEnd] the podium did not close cleanly: {err}`)
			end
		end
	end

	local function once(name: string, fn: () -> ())
		if not played[name] then
			played[name] = true
			fn()
		end
	end

	local function closeBoard()
		local parts = boardParts
		boardParts = nil
		boardPosed = nil
		if parts then
			for _, part in parts do
				part:Destroy()
			end
		end
	end

	local function teardown()
		endPodium()
		plateMade = nil
		closeBoard()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		local current = made
		made = nil
		if current then
			local selected = GuiService.SelectedObject
			for _, b in current.buttons do
				if selected == b.root then
					GuiService.SelectedObject = nil
				end
			end
			for _, handle in current.loops do
				handle:remove()
			end
			for _, cover in current.covers do
				cover:Destroy()
			end
			for _, s in current.stages do
				s:Destroy()
			end
		end
		local bed = cheer
		cheer = nil
		if bed then
			pcall(bed.stop, bed, CFG.cheer.outMs)
		end
	end

	local function startCheer(fadeMs: number)
		if cheer == nil and ctx.loop then
			cheer = ctx.loop(SOUND.cheer)
			cheerAt = os.clock()
			cheerFadeMs = fadeMs
		end
	end

	local function skip()
		local at = startAt
		if at == nil or resultsAt ~= nil or os.clock() - at < CFG.skip.at then
			return
		end
		skippedAt = os.clock()
		resultsAt = skippedAt
		fast = true
		if result and result.kind == "victory" then
			startCheer(CFG.cheer.skipInMs)
		end
		local pod = podium
		if pod then
			pod:skip()
		end
	end

	-- Round B1: the podium's moments (S:887-892).
	local function onPodiumEvent(name: string, data: { [string]: any })
		if name == "poseHit" then
			local steps = PODIUM.poseSteps
			local slot = math.max(0, data.slot or 0)
			play(SOUND.poseHit, { pitch = 2 ^ (steps[slot % #steps + 1] / 12) })
		elseif name == "mvpSlam" then
			play(SOUND.mvpSlam)
			slamAt = os.clock()
			slamStrong = data.strong == true
		elseif name == "crown" then
			play(SOUND.crownDrop)
		end
	end

	-- Round B1: the podium at its cue (or a skip): the lineup, then ctx.podium's scene (none in tests).
	local function startPodium(r: Result, reduced: boolean)
		local make = ctx.podium
		local view = frozen
		if make == nil or view == nil then
			return
		end
		local function who(userId: number): any
			return MatchKit.who(ctx, view, userId)
		end
		local function teamOf(userId: number): string?
			return who(userId).team
		end
		local lineup = MatchPodium.lineup(view, teamOf, MatchEnd.mvp(view, teamOf))
		if lineup == nil then
			return
		end
		local ok, made = pcall(make, {
			view = view,
			lineup = lineup,
			who = who,
			kind = r.kind,
			preview = ctx.preview,
			compact = ctx.compact(),
			reduced = reduced,
			look = r.look.top,
			onEvent = onPodiumEvent,
		})
		if not ok then
			warn(`[SD][MatchEnd] the podium did not start: {made}`)
		elseif made then
			podium = made
			podiumLineup = lineup
			if skippedAt then
				made:skip()
			end
		end
	end

	local function openBoard()
		if boardParts ~= nil or not interactive or frozen == nil then
			return
		end
		local current = made
		if current == nil then
			return
		end
		play(SOUND.tab, nil)
		local parts = board(ctx, frozen, current.layout, closeBoard)
		boardParts = parts
		boardAt = os.clock()
		boardPosed = posed(parts[3] :: Frame)
		-- Fit the board's stage as the main one.
		local stageFrame = parts[2] :: Frame
		local scale = stageFrame:FindFirstChildOfClass("UIScale") :: UIScale
		stageFrame.Size = current.stage.Size
		scale.Scale = current.scales[1].Scale
	end

	local function act(action: string)
		if not interactive then
			return
		end
		if action == "board" then
			openBoard()
			return
		end
		local f = ctx.act
		if f and frozen then
			f(if action == "again" then "again" else "leave", frozen.mode)
		end
	end

	local function pose(p: Posed, alpha: number?, motion: Tweens.Pose)
		if alpha then
			for _, fade in p.fades do
				fade:setAlpha(alpha)
			end
		end
		p.poser:set(motion)
	end

	local function track(
		p: Posed,
		frames: any,
		t: number,
		ms: number,
		curve: string?,
		wholeRun: string?,
		reduced: boolean
	)
		local at = MatchHudFormat.trackPose(frames, t, ms, curve, wholeRun, reduced, FADE_MS)
		local alpha = at.alpha
		local motion = table.clone(at)
		motion.alpha = nil
		pose(p, alpha, motion)
	end

	-- Round B1: the name tags over the heads (S:893-910), each frame from the podium's anchors; they pop in one after
	-- another (S:858).
	local function renderPlates(m: Made, clock: number, reduced: boolean)
		local list, pod = plateMade, podium
		if list == nil or pod == nil then
			return
		end
		local at: { [number]: Vector3 } = {}
		for _, a in pod:anchors() do
			at[a.userId] = a.at
		end
		local camera = workspace.CurrentCamera
		local stageFrame = m.stage
		local origin, abs = stageFrame.AbsolutePosition, stageFrame.AbsoluteSize
		if abs.X <= 0 or abs.Y <= 0 then
			return
		end
		local width = stageFrame.Size.X.Offset
		local sx, sy = width / abs.X, stageFrame.Size.Y.Offset / abs.Y
		local boxes: { PlateBox } = {}
		local shown: { PlateMade } = {}
		for _, p in list do
			local world = at[p.userId]
			local visible = false
			if world then
				local point = camera:WorldToScreenPoint(world)
				if point.Z > 0 then
					table.insert(boxes, {
						x = (point.X - origin.X) * sx,
						y = (point.Y - origin.Y) * sy - PLATES.below,
						w = p.w,
						h = p.h,
					})
					table.insert(shown, p)
					visible = true
				end
			end
			p.holder.Visible = visible
		end
		local L = m.layout
		-- S:899 keeps them under the pill; phones draw no pill (S:264), so there they keep under its top only (the
		-- pill's height would push the MVP's tag down over its crown).
		local top = L.psubTop + (if L.showPsub then L.psubH else 0) + PLATES.clear
		local places = MatchEnd.placePlates(boxes, top, PLATES.edge, width - PLATES.edge)
		for i, p in shown do
			p.holder.Position = UDim2.fromOffset(math.round(places[i].X), math.round(places[i].Y))
		end
		for i, p in list do
			local delay = if fast then 0 else (i - 1) * PLATES.stepMs / 1000
			track(p.posed, {
				{ at = 0, alpha = 0, y = PLATES.rise, scale = PLATES.from },
				{ at = 1, alpha = 1, y = 0, scale = 1 },
			}, clock - platesAt - delay, PLATES.popMs, "introSlam", nil, reduced)
		end
	end

	local function sparksAt(m: Made, clock: number)
		for index = #sparks, 1, -1 do
			local s = sparks[index]
			local u = (clock - s.t0) / (s.ms / 1000)
			if u >= 1 then
				s.frame:Destroy()
				table.remove(sparks, index)
			else
				local w = Tweens.curve("sparks")(math.clamp(u, 0, 1))
				local x, y, rot, scale, alpha
				if w < 0.4 then
					local k = w / 0.4
					x, y, rot, scale, alpha = s.dx * 0.7 * k, s.dy * 0.7 * k, s.rot * 0.5 * k, 0.4 + 0.7 * k, 1
				else
					local k = (w - 0.4) / 0.6
					x = s.dx * 0.7 + (s.dx * 0.3) * k
					y = s.dy * 0.7 + (s.dy * 0.3 + m.layout.sprinkles.fall) * k
					rot = s.rot * 0.5 + s.rot * 0.5 * k
					scale = 1.1 - 0.4 * k
					alpha = 1 - k
				end
				s.frame.Position = UDim2.new(0.5, math.round(x), 0, m.layout.titleY + math.round(y))
				s.frame.Rotation = rot
				s.frame.Size =
					UDim2.fromOffset(math.max(1, math.round(s.w * scale)), math.max(1, math.round(s.h * scale)))
				s.frame.BackgroundTransparency = 1 - alpha
				local stroke = s.frame:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = 1 - alpha
				end
			end
		end
	end

	local function sprinkle(m: Made, clock: number)
		local S = m.layout.sprinkles
		local r = result :: Result
		local colors = {
			r.look.mid or r.look.faceEnd,
			r.look.top,
			Palette.Lemon,
			WHITE,
			Palette.StickerMintTop,
		}
		local rng = Random.new()
		for i = 1, S.n do
			local w = S.w * (0.8 + rng:NextNumber() * 0.4)
			local h = w * 3
			local spark = frame("Sprinkle", {
				BackgroundTransparency = 0,
				BackgroundColor3 = colors[(i - 1) % #colors + 1],
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, m.layout.titleY),
				Size = UDim2.fromOffset(w, h),
				ZIndex = CFG.z + 6,
				Parent = m.sparkLayer,
			})
			Theme.corner(w, spark)
			Theme.stroke(INK, S.outline, spark)
			local a = rng:NextNumber() * math.pi * 2
			local v = S.v * (0.45 + rng:NextNumber() * 0.75)
			table.insert(sparks, {
				frame = spark,
				t0 = clock,
				ms = 1100 + rng:NextNumber() * 400,
				dx = math.cos(a) * v,
				dy = math.sin(a) * v * 0.7 - S.up,
				rot = (rng:NextNumber() - 0.5) * 720,
				w = w,
				h = h,
			})
		end
	end

	local function bang(m: Made, clock: number, reduced: boolean)
		play(SOUND.titleBoom)
		play(SOUND.victory)
		startCheer(CFG.cheer.inMs)
		if not reduced then
			UiFx.jolt(m.stage, CFG.bang.jolt * m.scales[1].Scale)
			sprinkle(m, clock)
		end
		bangAt = clock
	end

	-- The title's part of the timeline at t (seconds from the last squish); `settled` = skipped: everything at its end.
	local function renderTitle(m: Made, r: Result, t: number, clock: number, reduced: boolean, settled: boolean)
		local L = m.layout
		local victory = r.kind == "victory"
		local defeat = r.kind == "defeat"
		local Lt = CFG.letters
		local n = #m.letters
		-- The flash (S:736, victory only).
		local F = CFG.flash
		local flashAlpha = 0
		if victory and not settled then
			local ms, peak, at = F.ms, F.peak, F.at
			if reduced then
				ms, peak, at = F.softMs, F.softPeak, F.softAt
			end
			local u = t / (ms / 1000)
			if u >= 0 and u < 1 then
				local e = Tweens.curve("easeOut")(u)
				flashAlpha = if e < at then peak * e / at else peak * (1 - (e - at) / (1 - at))
			end
		end
		-- Round B1: the MVP's slam flashes the screen too (S:890; its keyframes linear).
		local slam = slamAt
		if slam then
			local Fs = PODIUM.flash
			local ms, peak, at = Fs.softMs, Fs.softPeak, Fs.softAt
			if slamStrong then
				ms, peak, at = Fs.ms, Fs.peak, Fs.at
			end
			local u = (clock - slam) / (ms / 1000)
			if u >= 0 and u < 1 then
				flashAlpha = math.max(flashAlpha, if u < at then peak * u / at else peak * (1 - (u - at) / (1 - at)))
			end
		end
		m.flash.BackgroundTransparency = 1 - flashAlpha
		if not settled then
			once("finalHit", function()
				play(SOUND.finalHit)
			end)
			if t >= CFG.slowmoAt then
				once("slowmo", function()
					play(SOUND.slowmo)
				end)
			end
		end
		-- The letters (S:791-806).
		local deflate = CFG.deflate
		for index, l in m.letters do
			local i = index - 1
			local bangLetter = victory and index == n
			local t0 = Lt.at + i * Lt.stepS
			local ms = if victory
				then (if bangLetter then Lt.bangMs else Lt.ms)
				elseif reduced then Lt.reducedMs
				else Lt.defeatMs
			local land = if bangLetter then Lt.bangLand else Lt.land
			local lt = if settled then math.huge else t - t0
			local alpha, y, scale, rot
			if reduced then
				local u = math.clamp(lt / (Lt.reducedMs / 1000), 0, 1)
				alpha, y, scale, rot = Tweens.curve("easeOut")(u), 0, 0.9 + 0.1 * Tweens.curve("easeOut")(u), 0
			elseif victory then
				alpha, y, scale, rot = keyed({
					{
						at = 0,
						alpha = 0,
						y = -L.drop * (if bangLetter then Lt.bangDrop else 1),
						sx = 0.9,
						sy = 1.15,
						rot = 0,
						ease = "endFall",
					},
					{ at = land, alpha = 1, y = 0, sx = 1.35, sy = 0.62, rot = 0 },
					{ at = land + 0.17, alpha = 1, y = -L.bounce, sx = 0.88, sy = 1.14, rot = 0 },
					{ at = land + 0.3, alpha = 1, y = 0, sx = 1.04, sy = 0.97, rot = 0 },
					rest(1),
				}, lt / (ms / 1000), "ring")
			else
				alpha, y, scale, rot = keyed({
					{ at = 0, alpha = 0, y = -L.drop * 0.55, sx = 1, sy = 1, rot = 0, ease = "endSoftFall" },
					{ at = 0.6, alpha = 1, y = 0, sx = 1.12, sy = 0.9, rot = 0 },
					rest(1),
				}, lt / (ms / 1000), "beat")
			end
			if defeat then
				-- S:804 the deflate, after the drop (its last frame stays: fill forwards).
				local dt = if settled then math.huge else t - deflate.at - i * deflate.stepMs / 1000
				if dt >= 0 then
					local u = dt / (deflate.ms / 1000)
					if reduced then
						local k = Tweens.curve("endDeflate")(math.clamp(u, 0, 1))
						scale = 1 + (math.sqrt(0.86) - 1) * k
					else
						local _, dy, ds, dr = keyed({
							rest(0),
							{ at = 0.18, alpha = 1, y = L.sag * 0.4, sx = 1.04, sy = 1.04, rot = 0 },
							{
								at = 1,
								alpha = 1,
								y = L.sag,
								sx = 1.07,
								sy = 0.7,
								rot = if i % 2 == 1 then 4 else -4,
							},
						}, u, "endDeflate")
						y, scale, rot = dy, ds, dr
					end
				end
			end
			pose(l.posed, alpha, { y = y, scale = scale, rot = rot })
			-- Each letter's pop when it lands (S:799), the "!" with its bang (S:828).
			local popAt = t0 + (if reduced then 0.1 elseif victory then ms / 1000 * land else Lt.defeatPopS)
			if not settled and t >= popAt then
				once("pop" .. index, function()
					local steps = Lt.pentatonic
					play(SOUND.letterPop, { pitch = 2 ^ (steps[math.clamp(index, 1, #steps)] / 12) })
					if bangLetter then
						bang(m, clock, reduced)
					end
				end)
			end
		end
		if defeat and not settled then
			if t >= deflate.stingerAt then
				once("defeat", function()
					play(SOUND.defeat)
				end)
			end
			if t >= deflate.at then
				once("deflate", function()
					play(SOUND.deflate)
				end)
			end
			if t >= deflate.awwAt then
				once("aww", function()
					play(SOUND.aww)
				end)
			end
		end
		-- The bang's rings and sunbursts (S:830-837), from the "!" landing.
		local Bg = CFG.bang
		local wipeT = t - CFG.wipe.at
		for index, ring in m.rings do
			local bt = if bangAt and not settled
				then clock - bangAt - (if index == 2 then Bg.ring2DelayMs / 1000 else 0)
				else -1
			local ms = if index == 1 then Bg.ringMs else Bg.ring2Ms
			local u = bt / (ms / 1000)
			ring.Visible = u >= 0 and u < 1 and not (reduced and index == 2)
			if ring.Visible then
				local e = Tweens.curve("ring")(u)
				local grow = ring:FindFirstChild("Grow") :: UIScale
				grow.Scale = 0.2 + (if index == 1 then 1.4 else 1.7) * e
				local stroke = ring:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = e
				end
			end
		end
		for index, sun in m.suns do
			local alpha = 0
			local scale = 1
			if bangAt and not settled then
				local u = (clock - bangAt) / (Bg.sunMs / 1000)
				local e = Tweens.curve("beat")(math.clamp(u, 0, 1))
				alpha = if reduced then 0.45 * math.clamp(u, 0, 1) else Bg.sunAlpha * e
				scale = if reduced then 1 else 0.3 + 0.7 * e
				if wipeT >= 0 then
					alpha *= 1 - math.clamp(wipeT / (CFG.wipe.sunOutMs / 1000), 0, 1)
				end
				if not reduced then
					local spin = if index == 1 then Bg.spinA else -Bg.spinB
					sun.Rotation = ((clock - bangAt) / math.abs(spin) * 360 * math.sign(spin)) % 360
				end
			end
			sun.ImageTransparency = 1 - alpha
			local side = if index == 1 then L.sun else L.sunB
			sun.Size = UDim2.fromOffset(math.round(side * scale), math.round(side * scale))
		end
		-- The sub line (S:810-811) and its rolling score.
		local S = CFG.sub
		local subT = t - (if victory then S.at else S.defeatAt)
		if settled or wipeT >= CFG.wipe.subOutMs / 1000 then
			pose(m.sub, 0, {})
		else
			local inK = math.clamp(subT / (S.ms / 1000), 0, 1)
			local e = Tweens.curve("easeOut")(inK)
			local outK = if wipeT >= 0 then math.clamp(wipeT / (CFG.wipe.subOutMs / 1000), 0, 1) else 0
			pose(m.sub, if subT < 0 then 0 else e * (1 - outK), { y = if reduced then 0 else S.rise * (1 - e) })
			local ct = subT / (S.crestMs / 1000)
			if reduced then
				pose(m.crest, nil, {})
			else
				local _, _, cs, cr = keyed({
					{ at = 0, alpha = 1, y = 0, sx = 0, sy = 0, rot = -30 },
					{ at = 0.6, alpha = 1, y = 0, sx = 1.2, sy = 1.2, rot = 6 },
					rest(1),
				}, ct, "beat")
				pose(m.crest, nil, { scale = if subT < 0 then 0 else cs, rot = cr })
			end
			local step = math.clamp(math.floor(subT / S.rollStepS), 0, S.rollSteps)
			if r.winScore and m.rollWin then
				m.rollWin.Text = tostring(math.round(r.winScore * step / S.rollSteps))
			end
			if r.loseScore and m.rollLose then
				m.rollLose.Text = tostring(math.round(r.loseScore * step / S.rollSteps))
			end
			if subT >= 0 then
				for j = 0, step, 2 do
					once("roll" .. j, function()
						play(SOUND.coinTick, { pitch = 2 ^ ((j % 8) / 24) })
					end)
				end
			end
		end
		-- The jelly wave, the title into its banner, the plate (S:812-821).
		local W = CFG.wipe
		local stageW = m.stage.Size.X.Offset
		if not settled and wipeT >= 0 then
			once("jelly", function()
				play(SOUND.jellyWipe)
			end)
		end
		if reduced then
			m.jelly.Visible = false
			local u = if settled then 1 else wipeT / (W.reducedMs / 1000)
			m.jellyX.Visible = u > 0 and u < 1
			local a = if u < 0.45 then u / 0.45 elseif u < 0.55 then 1 else 1 - (u - 0.55) / 0.45
			m.jellyX.BackgroundTransparency = 1 - math.clamp(a, 0, 1)
		else
			m.jellyX.Visible = false
			local u = if settled then 1 else wipeT / (W.ms / 1000)
			m.jelly.Visible = u > 0 and u < 1
			local jw = 2 * stageW
			local e = Tweens.curve("endJelly")(math.clamp(u, 0, 1))
			m.jelly.Size = UDim2.new(0, jw, 1.12, 0)
			m.jelly.Position = UDim2.new(0, math.round(-jw + (stageW + jw) * e), -0.06, 0)
		end
		local toY = L.bannerY - L.titleY
		local bu = if settled then 1 else wipeT / (W.ms / 1000)
		-- The title's own fade is only the ReducedMotion jump (else each letter keeps its own: the title's fade group
		-- would show them all at once).
		if reduced then
			local a = if bu < 0.45 then 1 - bu / 0.45 elseif bu < 0.55 then 0 else (bu - 0.55) / 0.45
			local there = bu >= 0.5
			local fade = if bu >= 0 and bu <= 1 then math.clamp(a, 0, 1) else nil
			pose(m.title, fade, { y = if there then toY else 0, scale = if there then L.bannerK else 1 })
		else
			local e = if bu <= 0 then 0 else Tweens.curve("endBanner")(math.clamp(bu, 0, 1))
			pose(m.title, nil, { y = toY * e, scale = 1 + (L.bannerK - 1) * e })
		end
		local pt = if settled then math.huge else wipeT - W.plateDelayS
		track(m.plate, {
			{ at = 0, alpha = 0, sx = 0.6 },
			{ at = 1, alpha = 1, sx = 1 },
		}, pt, W.plateMs, "introSlam", nil, reduced)
		local psub = m.psub
		if psub then
			local P = CFG.psub
			track(psub, {
				{ at = 0, alpha = 0, y = -P.rise },
				{ at = 1, alpha = 1, y = 0 },
			}, if settled then math.huge else t - P.at, P.ms, "easeOut", nil, reduced)
		end
		-- TAP TO SKIP (from 1 s until the results).
		local K = CFG.skip
		local inSkip = math.clamp((t - K.at) / (K.ms / 1000), 0, 1)
		local outSkip = if resultsAt then math.clamp((clock - (resultsAt :: number)) / (K.outMs / 1000), 0, 1) else 0
		pose(m.skip, inSkip * (1 - outSkip), {})
		m.catcher.Visible = resultsAt == nil and t >= K.at
	end

	-- The results (S:851-870) from resultsAt.
	local function renderResults(m: Made, clock: number, reduced: boolean)
		local at = resultsAt
		if at == nil then
			pose(m.bar, 0, {})
			for _, b in m.buttons do
				pose(b.posed, 0, {})
			end
			return
		end
		local R = CFG.results
		local rt = clock - at
		local B = m.layout.bar
		track(m.bar, {
			{ at = 0, alpha = 0, y = B.height * 1.2 },
			{ at = 1, alpha = 1, y = 0 },
		}, rt, if fast then R.fastBarMs else R.barMs, nil, "coinFlip", reduced)
		local mine = frozen and frozen.outcome.mine
		-- The Coins count up (16 steps), a tick each.
		local C = R.coins
		local c0 = if fast then C.fastAt else C.at
		local cms = (if fast then C.fastMs else C.ms) / 1000
		local cstep = math.clamp(math.floor((rt - c0) / cms * C.steps), 0, C.steps)
		local coins = if mine then mine.coins else 0
		m.coinText.Text = Strings.format(TEXT.gain, { n = Format.coins(math.round(coins * cstep / C.steps)) })
		for j = 1, cstep do
			once("coin" .. j, function()
				play(SOUND.coinTick, { pitch = 2 ^ ((j % 8) / 24) })
			end)
		end
		-- The Grip bar fills, its +N counting.
		local G = R.grip
		local g0 = c0 + (if fast then G.fastAfter else G.after)
		local gms = (if fast then G.fastMs else G.ms) / 1000
		local gu = (rt - g0) / gms
		if gu >= 0 then
			once("grip", function()
				local gained = if mine then mine.grip else 0
				local level, from, to = MatchEnd.gripBar(if ctx.gripTotal then ctx.gripTotal() else nil, gained)
				gripFrom, gripTo = from, to
				if level then
					m.gripLevel.Text = Strings.format(TEXT.gripLevel, { level = level })
				end
				play(SOUND.gripFill)
			end)
		end
		local ge = Tweens.curve("endFill")(math.clamp(gu, 0, 1))
		local share = gripFrom + (gripTo - gripFrom) * (if gu < 0 then 0 else ge)
		m.gripFill.Size = UDim2.new(0, math.round(m.gripInner * share), 1, 0)
		local gstep = math.clamp(math.floor(gu * G.steps), 0, G.steps)
		local grip = if mine then mine.grip else 0
		m.gripText.Text = Strings.format(TEXT.gain, { n = Format.coins(math.round(grip * gstep / G.steps)) })
		-- The streak's flame (S:864).
		local flame = m.flame
		if flame then
			local Fl = R.flame
			local _, ignite = MatchEnd.streakLine(mine)
			local ft = rt - (if fast then Fl.fastAt else Fl.at)
			if ignite then
				local alpha = Fl.dim + (1 - Fl.dim) * math.clamp(ft / (Fl.ms / 1000), 0, 1)
				local scale = 1
				if not reduced and ft >= 0 then
					local _, _, s = keyed({
						{ at = 0, alpha = 1, y = 0, sx = 0.4, sy = 0.4, rot = 0 },
						{ at = 0.55, alpha = 1, y = 0, sx = 1.45, sy = 1.45, rot = 0 },
						rest(1),
					}, ft / (Fl.ms / 1000), "beat")
					scale = s
				end
				pose(flame, if ft < 0 then Fl.dim else alpha, { scale = scale })
				if ft >= 0 then
					once("streak", function()
						play(SOUND.streak)
					end)
				end
			else
				pose(flame, Fl.dim, {})
			end
		end
		-- The buttons pop in, then take taps; PLAY AGAIN focused (a gamepad) and pulsing.
		local Bt = R.buttons
		local b0 = if fast then Bt.fastAt else Bt.at
		for index, b in m.buttons do
			local bt = rt - b0 - (index - 1) * Bt.stepS
			track(b.posed, {
				{ at = 0, alpha = 0, scale = 0.6 },
				{ at = 0.6, alpha = 1, scale = 1.08 },
				{ at = 1, alpha = 1, scale = 1 },
			}, bt, Bt.ms, nil, "beat", reduced)
		end
		if rt >= b0 + Bt.focusS and not interactive then
			interactive = true
			if UserInputService.GamepadEnabled then
				pcall(function()
					GuiService.SelectedObject = m.buttons[#m.buttons].root
				end)
			end
		end
		local flameAt = if fast then R.flame.fastAt else R.flame.at
		if rt >= math.max(b0 + Bt.pulseS, flameAt + Bt.pulseAfterFlameS) then
			once("pulse", function()
				local again = m.buttons[#m.buttons]
				local P = R.pulse
				local handle = UiIdle.addFrames(again.pulse, {
					{ at = 0, scale = 1 },
					{ at = 0.5, scale = P.scale },
					{ at = 1, scale = 1 },
				}, { periodS = P.periodS, curve = "easeInOut" })
				if handle then
					table.insert(m.loops, handle)
				end
			end)
		end
	end

	-- The scoreboard: its backdrop fades in (sdFade .2 s), the panel rises (smRise .3 s, S:307-308).
	local function renderBoard(clock: number, reduced: boolean)
		local parts = boardParts
		local p = boardPosed
		if parts == nil or p == nil then
			return
		end
		local backdrop = parts[1] :: TextButton
		local u = math.clamp((clock - boardAt) / 0.2, 0, 1)
		backdrop.BackgroundTransparency = 1 - CFG.board.backdropAlpha * u
		track(p, {
			{ at = 0, alpha = 0, y = 40, scale = 0.8 },
			{ at = 1, alpha = 1, y = 0, scale = 1 },
		}, clock - boardAt, CFG.board.ms, "rise", nil, reduced)
	end

	local piece = {}

	function piece.update(_self: any, view: any, _now: number)
		if finished then
			return
		end
		local clock = os.clock()
		if startAt == nil then
			local outcome = view.outcome
			if outcome == nil or (outcome.kind ~= "win" and outcome.kind ~= "draw") then
				return
			end
			frozen = ctx.result() or view
			result = MatchEnd.resultOf(frozen, function(userId: number): any
				return MatchKit.who(ctx, frozen, userId)
			end)
			startAt = clock
			local built = build(ctx, frozen, result :: Result, skip)
			made = built
			fit(built, ctx.canvas())
			for _, b in built.buttons do
				local name = b.root.Name
				table.insert(
					connections,
					b.root.Activated:Connect(function()
						act(if name == "Scoreboard" then "board" elseif name == "Lobby" then "leave" else "again")
					end)
				)
			end
			table.insert(
				connections,
				UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
					if boardParts and CLOSE_KEYS[input.KeyCode] then
						closeBoard()
					elseif boardParts == nil and SKIP_KEYS[input.KeyCode] and resultsAt == nil then
						skip()
					end
				end)
			)
		end
		local m = made
		local r = result
		if m == nil or r == nil then
			return
		end
		local reduced = ctx.reduced()
		local t = clock - (startAt :: number)
		if resultsAt == nil then
			local due = if r.kind == "victory" then CFG.results.at else CFG.results.defeatAt
			if t >= due then
				resultsAt = (startAt :: number) + due
			end
		end
		-- Round B1: the podium from its cue (or a skip), stepped before anything reads the camera.
		if not podiumTried and (t >= PODIUM.at or skippedAt ~= nil) then
			podiumTried = true
			startPodium(r, reduced)
		end
		local pod = podium
		if pod then
			local ok, err = pcall(pod.step, pod, clock)
			if not ok then
				warn(`[SD][MatchEnd] the podium stopped: {err}`)
				endPodium()
			end
		end
		renderTitle(m, r, t, clock, reduced, skippedAt ~= nil)
		renderResults(m, clock, reduced)
		if resultsAt and podium and podiumLineup and plateMade == nil then
			local made2: { PlateMade } = {}
			for _, p in MatchEnd.plates(frozen, podiumLineup :: MatchPodium.Lineup, ctx.compact()) do
				table.insert(made2, plateOf(p, m.layout, m.plateLayer, CFG.z + 6))
			end
			plateMade = made2
			platesAt = resultsAt :: number
		end
		renderPlates(m, clock, reduced)
		sparksAt(m, clock)
		local bed = cheer
		if bed then
			pcall(bed.setVolume, bed, math.clamp((clock - cheerAt) / math.max(cheerFadeMs / 1000, 1e-3), 0, 1))
		end
		renderBoard(clock, reduced)
	end

	function piece.layout(_self: any)
		local current = made
		if current then
			fit(current, ctx.canvas())
			local parts = boardParts
			if parts then
				local stageFrame = parts[2] :: Frame
				stageFrame.Size = current.stage.Size
				local scale = stageFrame:FindFirstChildOfClass("UIScale")
				if scale then
					scale.Scale = current.scales[1].Scale
				end
			end
		end
	end

	function piece.destroy(_self: any)
		finished = true
		for _, s in sparks do
			s.frame:Destroy()
		end
		table.clear(sparks)
		teardown()
	end

	return piece :: any
end

return MatchEnd
