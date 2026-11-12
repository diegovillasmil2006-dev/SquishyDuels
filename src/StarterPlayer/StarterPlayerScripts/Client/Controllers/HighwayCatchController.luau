--!strict
-- HighwayCatchController (client only). Rework Option A, the catch (owner 2026-11-12 "Yes, build it"; the rules on the
-- vault page "Plan - Rework from top games 2026-11", step 1; the look on Claude Design's catch canvas, step 2). The
-- server decides every catch (HighwayService: HighwayLanded's `catch` and `meter`); this module draws it. Driven by
-- HighwayThrowController (its deps.catch), never by itself; Config.Economy.Catch has the numbers.
-- * The CATCH meter (UI/CatchHud in SD_Highway) shows during a launch (the throw controller's setShown; not on the
--   deck, where it would cover the quest tracker) while no card shows: the saved highway's miss over need
--   (StateController "highway"), "{have}/{total} here" for the zone the squishy flies in (else the last landing's,
--   else the furthest zone reached), SURE CATCH! when the next catch is sure (the first catch ever, the meter full, or
--   a flight in a zone new to the player: then the chip "Your first catch here is sure!" too).
-- * prepare(plan) (the release, and each boost's new plan): wild.count wild squishies of the landing zone's box (its
--   pen copies, wild.scale bigger) stand beside the lane around where the throw will stop, facing it.
-- * landed(id) (the drawn landing): each gets a "!" (alertSeconds), then runs to runTo studs from the squishy
--   (runSeconds, bobbing).
-- * result(landing) (HighwayLanded): with a catch, the wild one of that kind (else the nearest, swapped to it) hops up
--   into a bubble in its rarity's colour (a beam from Rare up) as the card slides in (sounds: catch, rare). A landing
--   of no drawn scene (an older throw, or after the shot ended) shows the card alone, then the fly.
-- * finish() (the shot ends, the camera back): the bubble leaves the world and flies to the HUD's Squishies button,
--   "+1" (sound: home); the others go staySeconds after the landing.
-- ReducedMotion: no run, no hop; the bubble and the card, the "+1" at once.
-- Public: setShown(on), flying(biome), prepare(plan), landed(id), result(landing), finish(), debugState(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local CatchMath = require(Shared.CatchMath)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local HighwayMath = require(Shared.HighwayMath)
local Palette = require(Shared.Art.Palette)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local CatchHud = require(Client.UI.CatchHud)
local HudController = require(script.Parent.HudController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

type Wild = {
	model: Model,
	kind: string,
	home: Vector3, -- its pivot standing beside the lane
	stop: Vector3, -- its pivot after the run (runTo studs from the landing)
	height: number,
	alert: BillboardGui?,
}

export type DebugState = {
	shown: boolean,
	wild: number,
	planId: number?,
	landed: boolean,
	caught: string?,
	bubble: boolean,
	beam: boolean,
	card: boolean,
}

-- Constants

local C = Config.Economy.Catch
local W = C.wild
local UI = C.ui
local GUI = "SD_Highway"
local CLIENT_FX = "SD_ClientFx"
local FOLDER = "SD_Catch"
local REFRESH_SECONDS = 0.2 -- the meter's texts at most this often
local RAY_UP = 60
local RAY_LENGTH = 160
local RAY_TRIES = 4
local CLEAR = 0.95 -- a part at least this transparent is no ground (the deck's invisible walls)

-- Module table

local HighwayCatchController = {}

-- Private

local hud: CatchHud.Hud? = nil
local effect: Scheduler.Handle? = nil
local shown = false
local refreshedAt = -math.huge
local lastZone: number? = nil -- the zone of the last landing's meter (this session)
local flightZone: number? = nil -- the zone the own squishy flies in now
local baseBiome = 1 -- the saved furthest zone when the flight began
local scene = {
	id = nil :: number?,
	wild = {} :: { Wild },
	landing = nil :: Vector3?, -- world point where it stops
	landedAt = nil :: number?, -- os.clock() of the drawn landing
	catch = nil :: Types.HighwayCatch?,
	caught = nil :: Wild?,
	hopAt = nil :: number?,
	bubble = nil :: BasePart?,
	bubbleSize = 0, -- studs across, before the wobble
	beam = nil :: BasePart?,
	removeAt = nil :: number?,
	finished = false,
}

local function clock(): number
	return os.clock()
end

local function play(key: string, at: Vector3?)
	pcall(SoundController.play, key, if at then { at = at } else nil)
end

local function saved(): { [string]: any }
	local h = StateController.get("highway")
	return if type(h) == "table" then h else {}
end

local function number(v: any, default: number): number
	return if type(v) == "number" and v == v then v else default
end

local function folder(): Instance
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	if fx == nil then
		local made = Instance.new("Folder")
		made.Name = CLIENT_FX
		made.Parent = Workspace
		fx = made
	end
	local own = (fx :: Instance):FindFirstChild(FOLDER)
	if own == nil then
		local made = Instance.new("Folder")
		made.Name = FOLDER
		made.Parent = fx
		own = made
	end
	return own :: Instance
end

local function ensureHud(): CatchHud.Hud?
	if hud == nil and Players.LocalPlayer ~= nil then
		hud = CatchHud.new({
			gui = UIController.screenGui(GUI, Config.UI.Highway.gui),
			scale = UIController.scale,
		})
	end
	return hud
end

-- The ground's height under a world point (the first solid, visible part a ray from above meets), else nil.
local function groundAt(point: Vector3): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { folder().Parent :: Instance }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	for _ = 1, RAY_TRIES do
		params.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(point + Vector3.new(0, RAY_UP, 0), Vector3.new(0, -RAY_LENGTH, 0), params)
		if hit == nil then
			return nil
		end
		local part = hit.Instance
		if not (part:IsA("BasePart") and part.Transparency >= CLEAR) then
			return hit.Position.Y
		end
		table.insert(skip, part)
	end
	return nil
end

local function zoneOf(studs: number): number
	return CatchMath.zoneOf(studs, math.huge)
end

local function rarityColor(kind: string): Color3
	local def = Catalog.get(kind)
	local style = if def then RarityStyle.get(def.rarity) else nil
	return if style then style.color else Color3.new(1, 1, 1)
end

local function rank(kind: string): number
	local def = Catalog.get(kind)
	return if def then Rarity.index(def.rarity) or 1 else 1
end

-- A wild squishy's model: its pen copy wild.scale bigger, nothing to touch.
local function spawnModel(kind: string): (Model, number)
	local model = SquishyCache.clonePen(kind)
	model:ScaleTo(model:GetScale() * W.scale)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
		end
	end
	local _, size = model:GetBoundingBox()
	model.Parent = folder()
	return model, size.Y
end

local function facing(at: Vector3, toward: Vector3): CFrame
	local flat = Vector3.new(toward.X, at.Y, toward.Z)
	if (flat - at).Magnitude < 1e-3 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, flat)
end

local function alertOf(model: Model, height: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "CatchAlert"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(W.alertPx, W.alertPx)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height * 0.75, 0)
	gui.Enabled = false
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundColor3 = Color3.new(1, 1, 1)
	mark.Text = "!"
	mark.TextScaled = true
	mark.Font = Enum.Font.FredokaOne
	mark.TextColor3 = Palette.StickerInk
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mark
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = mark.TextColor3
	stroke.Thickness = 3
	stroke.Parent = mark
	Instance.new("UIScale").Parent = mark
	mark.Parent = gui
	gui.Parent = model.PrimaryPart or model
	return gui
end

local function removeBubble()
	local bubble, beam = scene.bubble, scene.beam
	scene.bubble, scene.beam = nil, nil
	if bubble then
		bubble:Destroy()
	end
	if beam then
		beam:Destroy()
	end
end

local function clearScene()
	removeBubble()
	for _, wild in scene.wild do
		wild.model:Destroy()
	end
	table.clear(scene.wild)
	scene.id, scene.landing, scene.landedAt, scene.catch, scene.caught = nil, nil, nil, nil, nil
	scene.hopAt, scene.removeAt, scene.finished = nil, nil, false
end

-- The card for a catch (its "in this zone" counts the catch even before the state shows it).
local function showCard(catch: Types.HighwayCatch, zone: number)
	local h = ensureHud()
	if h == nil then
		return
	end
	local owned = StateController.owned()
	local have, total = CatchMath.have(owned, CatchMath.boxFor(zone) or "")
	if catch.new and owned[catch.kind] == nil then
		have = math.min(have + 1, total)
	end
	local view = CatchHud.cardView(catch.kind, catch.new, have, total)
	if view then
		h:showCard(view)
	end
end

local function fly(kind: string)
	local h = ensureHud()
	if h then
		h:fly(kind, rarityColor(kind), HudController.element("squishies"))
		play(C.sounds.home)
	end
end

-- The caught one: the wild one of that kind, else the nearest to the landing (swapped to the caught kind).
local function chooseCaught(kind: string): Wild?
	local landing = scene.landing
	local best: Wild? = nil
	for _, wild in scene.wild do
		if wild.kind == kind then
			return wild
		end
		if
			landing ~= nil
			and (best == nil or (wild.stop - landing).Magnitude < ((best :: Wild).stop - landing).Magnitude)
		then
			best = wild
		end
	end
	local chosen = best
	if chosen ~= nil then
		local cf = chosen.model:GetPivot()
		chosen.model:Destroy()
		local model, height = spawnModel(kind)
		model:PivotTo(cf)
		chosen.model, chosen.kind, chosen.height, chosen.alert = model, kind, height, nil
	end
	return chosen
end

local function startHop(now: number)
	local catch = scene.catch :: Types.HighwayCatch
	local wild = scene.caught
	scene.hopAt = now
	showCard(catch, lastZone or 1)
	play(C.sounds.catch, if wild then wild.model:GetPivot().Position else nil)
	if rank(catch.kind) >= 3 then
		play(C.sounds.rare)
	end
	if wild == nil then
		return
	end
	if wild.alert then
		wild.alert.Enabled = false
	end
	local color = rarityColor(catch.kind)
	local _, size = wild.model:GetBoundingBox()
	local bubble = Instance.new("Part")
	bubble.Name = "CatchBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.Glass
	bubble.Color = Color3.new(1, 1, 1)
	bubble.Transparency = UI.bubble.transparency
	scene.bubbleSize = math.max(size.X, size.Y, size.Z) * UI.bubble.scale
	bubble.Size = Vector3.one * scene.bubbleSize
	bubble.Anchored, bubble.CanCollide, bubble.CanTouch, bubble.CanQuery, bubble.CastShadow =
		true, false, false, false, false
	bubble.CFrame = wild.model:GetPivot()
	local glow = Instance.new("Highlight")
	glow.FillTransparency = 1
	glow.OutlineColor = color
	glow.OutlineTransparency = 0
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = bubble
	bubble.Parent = folder()
	scene.bubble = bubble
	if rank(catch.kind) >= 3 then
		local beam = Instance.new("Part")
		beam.Name = "CatchBeam"
		beam.Shape = Enum.PartType.Cylinder
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = UI.beam.transparency
		beam.Size = Vector3.new(UI.beam.height, UI.beam.width, UI.beam.width)
		beam.Anchored, beam.CanCollide, beam.CanTouch, beam.CanQuery, beam.CastShadow =
			true, false, false, false, false
		local base = wild.stop
		beam.CFrame = CFrame.new(base + Vector3.new(0, UI.beam.height / 2 - wild.height / 2, 0))
			* CFrame.Angles(0, 0, math.pi / 2)
		beam.Parent = folder()
		scene.beam = beam
	end
end

-- One frame of the scene: the "!", the run, the hop, the bubble's wobble, the clean-up.
local function step(_dt: number, _now: number): boolean
	local now = clock()
	local reduced = Tweens.reducedMotion()
	local landedAt = scene.landedAt
	local landing = scene.landing
	if landedAt ~= nil and landing ~= nil then
		local t = now - landedAt
		for index, wild in scene.wild do
			if wild ~= scene.caught or scene.hopAt == nil then
				local alertAt = W.alertSeconds + (index - 1) * 0.04
				local alert = wild.alert
				local alertOn = t >= alertAt and t < alertAt + W.alertHoldSeconds and scene.hopAt == nil
				if alert and alert.Enabled and not alertOn then
					alert.Enabled = false
				elseif alert and alertOn then
					if not alert.Enabled then
						alert.Enabled = true
						if index == 1 then
							play(C.sounds.alert)
						end
					end
					local mark = alert:FindFirstChild("Mark")
					local scale = mark and mark:FindFirstChildOfClass("UIScale")
					if scale then
						local u = math.clamp((t - alertAt) / 0.35, 0, 1)
						scale.Scale = if reduced then 1 else 0.4 + 0.6 * (1 + 0.15 * math.sin(u * math.pi)) * u
					end
				end
				if not reduced then
					local u = math.clamp((t - W.alertSeconds) / W.runSeconds, 0, 1)
					local e = 1 - (1 - u) * (1 - u)
					local at = wild.home:Lerp(wild.stop, e)
					at += Vector3.new(0, math.abs(math.sin(u * math.pi * 3)) * wild.height * W.bobShare * (1 - u), 0)
					wild.model:PivotTo(facing(at, landing))
				end
			end
		end
		local catch = scene.catch
		local ready = landedAt + (if reduced then 0 else W.alertSeconds + W.runSeconds)
		if catch ~= nil and scene.hopAt == nil and now >= ready then
			startHop(now)
		end
		local caught, hopAt = scene.caught, scene.hopAt
		if caught ~= nil and hopAt ~= nil then
			local u = if reduced then 1 else math.clamp((now - hopAt) / W.hopSeconds, 0, 1)
			local up = W.hopStuds * (1 - (1 - u) * (1 - u))
			local at = caught.stop + Vector3.new(0, up, 0)
			local turn = if reduced then 0 else (now - hopAt) * 1.5
			caught.model:PivotTo(facing(at, landing) * CFrame.Angles(0, turn, 0))
			local bubble = scene.bubble
			if bubble then -- the design's wobble (ctWobble, 1.2 s): a ball part keeps one size, so it breathes
				local wob = if reduced then 0 else 0.04 * math.sin((now - hopAt) * math.pi * 2 / 1.2)
				bubble.Size = Vector3.one * scene.bubbleSize * (1 + wob)
				bubble.CFrame = CFrame.new(at)
			end
			local beam = scene.beam
			if beam then
				local pulse = if reduced then 0 else 0.2 * (0.5 + 0.5 * math.sin(now * 5))
				beam.Transparency = UI.beam.transparency - pulse
			end
		end
	end
	local removeAt = scene.removeAt
	if removeAt ~= nil and now >= removeAt then
		clearScene()
	end
	if scene.id == nil and #scene.wild == 0 then
		effect = nil
		return false
	end
	return true
end

local function ensureEffect()
	if effect == nil then
		effect = Scheduler.default():add(step, "render")
	end
end

local function refreshMeter(force: boolean)
	local h = hud
	if h == nil then
		return
	end
	local now = clock()
	if not force and now - refreshedAt < REFRESH_SECONDS then
		return
	end
	refreshedAt = now
	local state = saved()
	local miss = number(state.miss, 0)
	local need = number(state.need, 0)
	local caught = number(state.caught, 0)
	local zone = flightZone or lastZone or math.clamp(number(state.biome, 1), 1, #Config.Economy.Highway.starts)
	local newZone = flightZone ~= nil and flightZone > baseBiome
	local sure = newZone or caught <= 0 or (need > 0 and miss + 1 >= need)
	local have, total = CatchMath.have(StateController.owned(), CatchMath.boxFor(zone) or "")
	h:setMeter(CatchHud.meterView(miss, need, have, total, sure))
	h:setChip(newZone)
end

-- Public -------------------------------------------------------------------------------------------------------------

-- Every frame from the throw controller: the meter shows while `on` (a launch).
function HighwayCatchController.setShown(on: boolean)
	if on ~= shown then
		shown = on
		if not on then
			local h = hud
			if h then
				h:setMeter(nil)
				h:setChip(false)
			end
			return
		end
		ensureHud()
		refreshMeter(true)
		return
	end
	if on then
		refreshMeter(false)
	end
end

-- The zone the own squishy flies in now (nil: no flight).
function HighwayCatchController.flying(biome: number?)
	local zone = if biome then math.min(biome, #Config.Economy.Highway.starts) else nil
	if zone ~= flightZone then
		flightZone = zone
		refreshMeter(true)
	end
end

-- The release (and a boost's new plan): the wild ones stand around where it will stop.
function HighwayCatchController.prepare(plan: Types.HighwayPlan)
	if Players.LocalPlayer == nil then
		return
	end
	local boosted = scene.id == plan.id
	clearScene()
	if not boosted then
		baseBiome = math.max(1, number(saved().biome, 1))
	end
	local endAt = HighwayMath.planAt(plan, plan.landsAt)
	local landing = WorldLayout.highwayCFrame(endAt.X, endAt.Y, endAt.Z).Position
	local box = Boxes.get(CatchMath.boxFor(zoneOf(plan.studs)) or "")
	if box == nil or #box.items == 0 then
		return
	end
	local rng = Random.new(plan.id)
	local kinds: { string } = {}
	for _, item in box.items do
		table.insert(kinds, item.id)
	end
	for i = #kinds, 2, -1 do
		local j = rng:NextInteger(1, i)
		kinds[i], kinds[j] = kinds[j], kinds[i]
	end
	scene.id = plan.id
	scene.landing = landing
	for i = 1, W.count do
		local kind = kinds[(i - 1) % #kinds + 1]
		local side = if i % 2 == 0 then 1 else -1
		local x = side * rng:NextNumber(W.sideMin, W.sideMax)
		local d = endAt.Z + rng:NextNumber(-W.behind, W.ahead)
		local point = WorldLayout.highwayCFrame(x, 0, d).Position
		local model, height = spawnModel(kind)
		local ground = groundAt(point) or point.Y
		local home = Vector3.new(point.X, ground + height / 2, point.Z)
		local away = Vector3.new(home.X - landing.X, 0, home.Z - landing.Z)
		local stop = home
		if away.Magnitude > W.runTo then
			local flat = Vector3.new(landing.X, 0, landing.Z) + away.Unit * W.runTo
			stop = Vector3.new(flat.X, (groundAt(flat) or ground) + height / 2, flat.Z)
		end
		model:PivotTo(facing(home, landing))
		local wild: Wild = { model = model, kind = kind, home = home, stop = stop, height = height, alert = nil }
		wild.alert = alertOf(model, height)
		table.insert(scene.wild, wild)
	end
	ensureEffect()
end

-- The drawn landing of plan `id`: the "!" and the run.
function HighwayCatchController.landed(id: number)
	if scene.id ~= id or scene.landedAt ~= nil then
		return
	end
	local now = clock()
	scene.landedAt = now
	scene.removeAt = now + W.staySeconds
	ensureEffect()
end

-- HighwayLanded: the meter's zone, and a catch's bubble and card (see the header).
function HighwayCatchController.result(landing: Types.HighwayLanding)
	local meter = landing.meter
	if type(meter) == "table" and type(meter.zone) == "number" then
		lastZone = meter.zone
	end
	refreshMeter(true)
	local catch = landing.catch
	if type(catch) ~= "table" or type(catch.kind) ~= "string" or Catalog.get(catch.kind) == nil then
		return
	end
	local zone = if type(meter) == "table" and type(meter.zone) == "number" then meter.zone else zoneOf(landing.studs)
	if scene.id ~= landing.id or scene.finished or #scene.wild == 0 then
		showCard(catch, zone) -- no drawn scene for it: the card, then home
		fly(catch.kind)
		return
	end
	scene.catch = catch
	scene.caught = chooseCaught(catch.kind)
	lastZone = zone
	ensureEffect()
end

-- The shot ends (the camera back): the bubble flies home; the others stay until removeAt.
function HighwayCatchController.finish()
	flightZone = nil
	refreshMeter(true)
	if scene.id == nil or scene.finished then
		return
	end
	scene.finished = true
	local catch = scene.catch
	if catch ~= nil then
		if scene.hopAt == nil then
			showCard(catch, lastZone or 1) -- the result came too late for the hop: the card now
		end
		local caught = scene.caught
		if caught then
			local index = table.find(scene.wild, caught)
			if index then
				table.remove(scene.wild, index)
			end
			caught.model:Destroy()
			scene.caught = nil
		end
		removeBubble()
		local h = hud
		if h then
			h:hideCard() -- Home: the bubble flies, the card goes
		end
		fly(catch.kind)
	end
	if scene.removeAt == nil then
		scene.removeAt = clock()
	end
end

function HighwayCatchController.debugState(): DebugState
	local h = hud
	return {
		shown = shown,
		wild = #scene.wild,
		planId = scene.id,
		landed = scene.landedAt ~= nil,
		caught = if scene.catch then (scene.catch :: Types.HighwayCatch).kind else nil,
		bubble = scene.bubble ~= nil,
		beam = scene.beam ~= nil,
		card = h ~= nil and h:cardShowing(),
	}
end

-- Leak checks and tests: everything drawn goes.
function HighwayCatchController.destroy()
	clearScene()
	local handle = effect
	effect = nil
	if handle then
		handle:disconnect()
	end
	local h = hud
	hud = nil
	if h then
		h:destroy()
	end
	shown, flightZone, lastZone, refreshedAt = false, nil, nil, -math.huge
end

return HighwayCatchController
