--!strict
-- CollectionController (client only). DESIGN §7.6 (the Collection row and "Collection display per player"), §7.7 (the
-- lobby SurfaceGui budget), §8.1 #8 (collection display scale 2.5), §8.3 (model slots), §9.1 #5 (client-only parts
-- under Workspace.SD_ClientFx), §9.12 (ReducedMotion). Part 6. Each player sees their own collection on the 8
-- pedestals of the Collection stand:
--   * One Folder Workspace.SD_ClientFx/SD_Collection holds every display (created once in start(), so the Inspect leak
--     test's SD_ClientFx child count stays the same whatever is built).
--   * Every Config.Inspect.Collection.checkSeconds: for each streamed-in part tagged WorldLayout.Collection.pedestalTag
--     (attribute Slot 1-8), the distance from the local HumanoidRootPart (else the camera) decides through
--     CollectionFormat.shouldBuild: a display is built within WorldLayout.Collection.buildStuds (60) and removed once
--     it is more than Config.Inspect.Collection.hysteresisStuds past that radius.
--   * Build: SquishyCache.clone(CollectionFormat.squishyForSlot(slot), "World", WorldLayout.Collection.squishyScale)
--     (a model slot replaces the blueprint, §8.3), its bottom on the pedestal top, face toward -X
--     (CollectionFormat.restCFrame; the pivot's height above the model's bottom is measured once per build from
--     GetBoundingBox). Owned -> full colour. Not owned -> a Lavender silhouette of this client's clone only
--     (silhouette(): every BasePart Lavender, MeshPart TextureID and FileMesh TextureId cleared, Decals and Textures
--     hidden, SurfaceAppearances removed).
--   * Nameplate: ONE BillboardGui per display, never a SurfaceGui (the lobby already uses 26 of its 30), parented to
--     the model's Root: a Cream plate (CollectionFormat.PLATE_TOKEN) with the squishy's name and Owned / Not owned yet
--     in Ink (CollectionFormat.plate), Config.Inspect.Collection.nameplateSizeStuds wide and tall,
--     nameplateOffsetStuds above the model's top, MaxDistance = buildStuds, LightInfluence 0, not AlwaysOnTop.
--   * Motion: every built display within buildStuds (at the last check) sways by CollectionFormat.swayAngle(now,
--     phaseOf(slot), Config.Inspect.Collection.swayDeg, swayPeriodSeconds, Tweens.reducedMotion()) about its rest
--     pivot, within ±swayDeg of the -X facing so its face stays toward the aisle, always the rest pose times the angle
--     of the clock, never added up; one kept past buildStuds by the margin holds still (§7.6 "built/animated only
--     within 60 studs"); under ReducedMotion one write back to the rest pose, then nothing.
--   * StateController.changed("owned") and Loaded rebuild only the displays whose ownership changed (one past
--     buildStuds is removed instead, and built again on the next check in range). The owned set is the one shown
--     (reveal holds included), so a display never spoils a box reveal.
--   * A pedestal that streams out or loses its tag takes its display with it.
--   * Idle life (squishy overhaul spec 2026-10-09 §3.2, the lowest priority of the deforming rigs): every display has an
--     Anim/IdleRig (it blinks only when owned, never as a Lavender silhouette). Each frame the nearest displays within
--     Config.Inspect.Collection.idleStuds, at most min(setIdleSlots(n), idleMax), breathe and blink (pickIdle); the
--     others rest. n = the rig slots HeldSquishyController leaves; it answers how many it uses (the rest go to the
--     Ambient breathers). None under ReducedMotion. The deformer attaches on a display's first slot. The idle stepping
--     and its writes run in the "SD_Rigs" profiler scope (spec §5).
-- Readings (DESIGN silent; Part 6):
--   * The nameplate's texts are TextScaled under a cap of their Theme size (UITextSizeConstraint), as the world signs
--     of §7.7 are: a stud-sized BillboardGui grows and shrinks with distance, so a fixed TextSize would overflow
--     far away. FontFace, TextSize (the cap) and the Ink colour come from UI/Theme. Foam UI restyle (spec 2026-10-09;
--     the plate stays Cream, §7.7): the plate's outline is the InkUI bar stroke, the texts InkUI, "Not owned yet" Ink2.
--   * A FileMesh SpecialMesh's TextureId is cleared too (a slot model's textured mesh would hide the Lavender colour).
--   * All 8 displays of a pass are built in that pass (first time: 8 template builds at scale 2.5).
-- Only this client's own Workspace.SD_ClientFx parts change; SquishyCache builds them CanCollide/CanTouch/CanQuery
-- false in the SD_Cosmetic group, so nothing here can touch competitive state. No remote is sent. The pedestals'
-- Inspect prompts are WorldBinder stands that InspectController registers; the kiosk is InventoryController's.
-- One Scheduler render effect; the only connections are the CollectionService tag signals and the two StateController
-- signals. Everything is in one Cleanup; destroy() (tests, leak checks) removes the folder.

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local CollectionFormat = require(Client.UI.CollectionFormat)
local Create = require(Client.UI.Create)
local IdleRig = require(Client.Anim.IdleRig)
local Scheduler = require(Client.Anim.Scheduler)
local SquishyCache = require(Client.Models.SquishyCache)
local Theme = require(Client.UI.Theme)
local Tweens = require(Client.Anim.Tweens)
local StateController = require(script.Parent.StateController)

-- Types

type Display = {
	slot: number,
	id: string,
	owned: boolean,
	pedestal: BasePart,
	model: Model,
	top: Vector3, -- the pedestal's top centre
	lift: number, -- the pivot's height above the model's bottom
	phase: number, -- CollectionFormat.phaseOf(slot)
	nameplate: BillboardGui,
	status: string, -- the plate's status text
	atRest: boolean, -- the last write was the rest pose (ReducedMotion)
	inRange: boolean, -- within buildStuds at the last distance check (only these turn, §7.6)
	life: IdleRig.IdleRig?, -- breathing and blink (nil without a motion row)
}

export type DebugState = {
	ok: boolean,
	started: boolean,
	builtCount: number,
	built: { [number]: { id: string, owned: boolean, status: string } },
	builtList: { { slot: number, id: string, owned: boolean, status: string } },
	pedestals: number, -- tagged pedestals streamed in
	nameplates: number, -- BillboardGuis under the folder
	surfaceGuis: number, -- always 0 (§7.7 budget)
	folderChildren: number,
	nearestStuds: number?,
	reduced: boolean,
	idleSlots: number, -- setIdleSlots(n)
	idle: number, -- displays breathing and blinking this frame
}

-- Constants

local LAYOUT = WorldLayout.Collection
local DISPLAY = Config.Inspect.Collection
local TAG = LAYOUT.pedestalTag
local ATTR_SLOT = WorldLayout.Attributes.Slot
local ATTR_DISPLAY_SLOT = "SD_CollectionSlot"
local CLIENT_FX = "SD_ClientFx"
local FOLDER_NAME = "SD_Collection"
local MODEL_PREFIX = "Display"
local PLATE_NAME = "Nameplate"
local ROOT_PART = "HumanoidRootPart"
local PROFILE_RIGS = "SD_Rigs" -- the profiler scope of rig stepping and writes (spec §5)
local BUILD_MODE: SquishyCache.Mode = "World"
-- The plate's layout inside the BillboardGui, in fractions of its size (it scales with distance).
local PLATE_INSET = 0.06
local TITLE_HEIGHT = 0.5
local STATUS_HEIGHT = 0.32
local TITLE_KIND: Theme.TextKind = "H2"
local STATUS_KIND: Theme.TextKind = "Small"

-- Module table

local CollectionController = {}

-- Private

local log = Log.new("Collection")
local cleanup: Cleanup.Cleanup? = nil
local folder: Folder? = nil
local pedestalBySlot: { [number]: BasePart } = {}
local slotOfPart: { [BasePart]: number } = {}
local displays: { [number]: Display } = {}
local lastCheck = -math.huge
local nearestStuds: number? = nil
local wasReduced = false
local warned: { [string]: boolean } = {}
local idleSlots = math.huge -- rig slots left by the held models (setIdleSlots)
local idleUse = math.huge -- the slots setIdleSlots answered it uses: no more until its next call
local idleCount = 0
local idleDistances: { [number]: number } = {} -- reused every frame (no per-frame tables)
local idlePicked: { [number]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		log:warn(message)
	end
end

local function paletteColor(token: string, fallback: Color3): Color3
	local value = (Palette :: any)[token]
	return if typeof(value) == "Color3" then value else fallback
end

local function ensureFolder(): Folder
	local current = folder
	if current and current.Parent ~= nil then
		return current
	end
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	if fx == nil then
		local created = Instance.new("Folder")
		created.Name = CLIENT_FX
		created.Parent = Workspace
		fx = created
	end
	local existing = (fx :: Instance):FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = fx
	folder = made
	return made
end

local function topOf(part: BasePart): Vector3
	return (part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)).Position
end

-- Where distances are measured from: the local HumanoidRootPart, else the camera; nil when there is neither.
local function origin(): Vector3?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild(ROOT_PART)
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function swaying(reduced: boolean): boolean
	return not reduced and DISPLAY.swayDeg > 0
end

local function place(display: Display, now: number, reduced: boolean)
	local angle = CollectionFormat.swayAngle(now, display.phase, DISPLAY.swayDeg, DISPLAY.swayPeriodSeconds, reduced)
	display.model:PivotTo(CollectionFormat.restCFrame(display.top, display.lift, angle))
end

local function removeDisplay(slot: number)
	local display = displays[slot]
	if display == nil then
		return
	end
	displays[slot] = nil
	local life = display.life
	if life then
		life:destroy()
	end
	display.model:Destroy() -- the nameplate goes with it
end

local function buildDisplay(slot: number, pedestal: BasePart, now: number)
	local id = CollectionFormat.squishyForSlot(slot)
	if id == nil then
		return
	end
	local owned = StateController.owns(id)
	local model = SquishyCache.clone(id, BUILD_MODE, LAYOUT.squishyScale)
	model.Name = MODEL_PREFIX .. slot
	model:SetAttribute(ATTR_DISPLAY_SLOT, slot)
	if not owned then
		CollectionController.silhouette(model)
	end
	local boxFrame, boxSize = model:GetBoundingBox()
	local lift, topAbovePivot = CollectionController.lift(model:GetPivot(), boxFrame, boxSize)
	local plate = CollectionFormat.plate(id, owned)
	local nameplate = CollectionController.nameplate(plate, topAbovePivot)
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	nameplate.Parent = anchor or model
	local reduced = Tweens.reducedMotion()
	local display: Display = {
		slot = slot,
		id = id,
		owned = owned,
		pedestal = pedestal,
		model = model,
		top = topOf(pedestal),
		lift = lift,
		phase = CollectionFormat.phaseOf(slot),
		nameplate = nameplate,
		status = plate.status,
		atRest = not swaying(reduced),
		inRange = true, -- built only within buildStuds
		-- No blink on a Lavender silhouette (spec 2026-10-09 §3.2).
		life = IdleRig.new(model, id, { blink = owned, phase = CollectionFormat.phaseOf(slot), seed = slot }),
	}
	place(display, now, reduced)
	model.Parent = ensureFolder()
	displays[slot] = display
end

-- Builds a display, logging (once per slot) instead of stopping the render effect when anything fails.
local function tryBuild(slot: number, pedestal: BasePart, now: number)
	local ok = xpcall(buildDisplay, function(err: any)
		warnOnce(`build{slot}`, `could not build the display of pedestal {slot}: {tostring(err)}`)
	end, slot, pedestal, now)
	if not ok then
		removeDisplay(slot)
	end
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or slotOfPart[instance] ~= nil then
		return
	end
	if not instance:IsDescendantOf(Workspace) then
		return
	end
	local slot = instance:GetAttribute(ATTR_SLOT)
	if type(slot) ~= "number" or CollectionFormat.squishyForSlot(slot) == nil then
		warnOnce(
			`slot:{instance:GetFullName()}`,
			`{instance:GetFullName()} has no valid {ATTR_SLOT} ({tostring(slot)})`
		)
		return
	end
	local current: BasePart? = pedestalBySlot[slot]
	if current ~= nil and current ~= instance then
		warnOnce(`dup{slot}`, `two pedestals with {ATTR_SLOT} {slot}; only {current:GetFullName()} shows a squishy`)
		return
	end
	pedestalBySlot[slot] = instance
	slotOfPart[instance] = slot
	lastCheck = -math.huge -- the next frame checks the distances
end

local function untrack(instance: Instance)
	local slot = slotOfPart[instance :: any]
	if slot == nil then
		return
	end
	slotOfPart[instance :: any] = nil
	if pedestalBySlot[slot] == instance then
		pedestalBySlot[slot] = nil
	end
	removeDisplay(slot)
end

local function checkDistances(now: number)
	local from = origin()
	local nearest = math.huge
	local slots: { number } = {}
	for slot in pedestalBySlot do
		table.insert(slots, slot)
	end
	for _, slot in slots do
		local part: BasePart? = pedestalBySlot[slot]
		if part == nil then
			continue
		end
		if part.Parent == nil then
			removeDisplay(slot) -- streaming out: the tag signal untracks it
			continue
		end
		local distance = if from then (part.Position - from).Magnitude else math.huge
		nearest = math.min(nearest, distance)
		local display: Display? = displays[slot]
		if display and display.model.Parent == nil then
			removeDisplay(slot) -- its folder was removed from outside: built again below when in range
			display = nil
		end
		local built = display ~= nil
		if CollectionFormat.shouldBuild(distance, built) then
			if display then
				display.inRange = distance <= LAYOUT.buildStuds
			else
				tryBuild(slot, part, now)
			end
		elseif built then
			removeDisplay(slot)
		end
	end
	nearestStuds = if nearest < math.huge then nearest else nil
end

-- Rebuilds the displays whose ownership changed (StateController.changed("owned"), Loaded).
local function reconcile()
	local changed: { number } = {}
	for slot, display in displays do
		if StateController.owns(display.id) ~= display.owned then
			table.insert(changed, slot)
		end
	end
	local now = os.clock()
	for _, slot in changed do
		local display = displays[slot]
		if display then
			local pedestal = display.pedestal
			removeDisplay(slot)
			-- Rebuilt only within buildStuds; one kept past it by the margin comes back on the next check in range.
			if display.inRange and pedestal.Parent ~= nil and pedestalBySlot[slot] == pedestal then
				tryBuild(slot, pedestal, now)
			end
		end
	end
end

-- The idle life (spec 2026-10-09 §3.2): the picked displays breathe and blink, the others rest.
local function stepIdle(dt: number, reduced: boolean)
	local from = origin()
	table.clear(idleDistances)
	if from then
		for slot, display in displays do
			if display.life then
				idleDistances[slot] = (display.top - from).Magnitude
			end
		end
	end
	CollectionController.pickIdle(idleDistances, idleUse, reduced, idlePicked)
	idleCount = 0
	for slot, display in displays do
		local life = display.life
		if life == nil then
			continue
		end
		if idlePicked[slot] then
			idleCount += 1
			life:start()
			life:step(dt)
		else
			life:rest()
		end
	end
end

local function step(dt: number, now: number): boolean
	if now - lastCheck >= DISPLAY.checkSeconds then
		lastCheck = now
		checkDistances(now)
	end
	local reduced = Tweens.reducedMotion()
	wasReduced = reduced
	local moving = swaying(reduced)
	for _, display in displays do
		if moving then
			if display.inRange then -- §7.6: animated only within buildStuds (one kept by the margin holds still)
				display.atRest = false
				place(display, now, reduced)
			end
		elseif not display.atRest then
			display.atRest = true
			place(display, now, reduced)
		end
	end
	debug.profilebegin(PROFILE_RIGS)
	stepIdle(dt, reduced)
	debug.profileend()
	return true
end

-- Public: helpers (pure on the instances they are given; unit-tested in Edit mode)

-- The unowned look on this client's own clone (§7.6): every BasePart takes the silhouette colour (default
-- Palette[CollectionFormat.SILHOUETTE_TOKEN], Lavender), MeshPart TextureIDs and FileMesh TextureIds are cleared,
-- Decals and Textures are hidden and SurfaceAppearances are removed. Never call it on a shared template.
function CollectionController.silhouette(model: Instance, color: Color3?)
	local tint = color or paletteColor(CollectionFormat.SILHOUETTE_TOKEN, Palette.Lavender)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = tint
			if descendant:IsA("MeshPart") then
				descendant.TextureID = ""
			end
		elseif descendant:IsA("SpecialMesh") then
			descendant.TextureId = ""
		elseif descendant:IsA("Decal") then -- Texture is a Decal too
			descendant.Transparency = 1
		elseif descendant:IsA("SurfaceAppearance") then
			descendant:Destroy()
		end
	end
end

-- From a model's pivot and its bounding box (model:GetBoundingBox(), oriented like the pivot): the pivot's height
-- above the model's bottom, and the model's top above its pivot.
function CollectionController.lift(pivot: CFrame, boxFrame: CFrame, boxSize: Vector3): (number, number)
	local centerY = pivot:PointToObjectSpace(boxFrame.Position).Y
	local half = boxSize.Y / 2
	return half - centerY, half + centerY
end

-- The nameplate of one display (unparented): a stud-sized BillboardGui with a Cream plate, the title and the status.
function CollectionController.nameplate(plate: CollectionFormat.Plate, topAbovePivot: number): BillboardGui
	local size = DISPLAY.nameplateSizeStuds
	local gui: BillboardGui = Create("BillboardGui", {
		Name = PLATE_NAME,
		Size = UDim2.fromScale(size.X, size.Y), -- a BillboardGui's Scale is in studs
		StudsOffsetWorldSpace = Vector3.new(0, topAbovePivot + DISPLAY.nameplateOffsetStuds, 0),
		MaxDistance = LAYOUT.buildStuds,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ClipsDescendants = false,
		Active = false,
		ResetOnSpawn = false,
	})
	local panel: Frame = Create("Frame", {
		Name = "Plate",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = paletteColor(CollectionFormat.PLATE_TOKEN, Theme.Colors.cream),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = gui,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.25, 0), Parent = panel })
	-- Candy UI (2026-10-11): world plates keep the light foam look and its inks (Theme.Colors.worldInk*).
	Theme.stroke(Theme.Colors.worldInk, Theme.Stroke.bar, panel)
	local function line(
		name: string,
		text: string,
		kind: Theme.TextKind,
		y: number,
		height: number,
		color: Color3
	): TextLabel
		local label: TextLabel = Create("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(PLATE_INSET, y),
			Size = UDim2.fromScale(1 - 2 * PLATE_INSET, height),
			Text = text,
		})
		Theme.text(label, kind, nil, color)
		label.TextScaled = true
		Create("UITextSizeConstraint", { MaxTextSize = math.max(1, math.floor(Theme.textSize(kind))), Parent = label })
		label.Parent = panel
		return label
	end
	line("Title", plate.title, TITLE_KIND, PLATE_INSET, TITLE_HEIGHT, Theme.Colors.worldInk)
	-- Foam restyle: "Not owned yet" in Ink2 (still >= 4.5:1 on Cream), "Owned" in InkUI.
	local statusColor = if plate.owned then Theme.Colors.worldInk else Theme.Colors.worldInk2
	line("Status", plate.status, STATUS_KIND, PLATE_INSET + TITLE_HEIGHT, STATUS_HEIGHT, statusColor)
	return gui
end

-- Which displays breathe and blink (spec 2026-10-09 §3.2 idle life): the nearest within
-- Config.Inspect.Collection.idleStuds, at most min(slots, idleMax); none under ReducedMotion or without slots.
-- `distances` by slot (NaN never picked); fills and returns `out` (slot -> true), so the per-frame call makes no table.
function CollectionController.pickIdle(
	distances: { [number]: number },
	slots: number,
	reduced: boolean,
	out: { [number]: boolean }
): { [number]: boolean }
	table.clear(out)
	local count = if slots == slots then math.min(math.floor(slots), DISPLAY.idleMax) else 0
	if reduced or count <= 0 then
		return out
	end
	for _ = 1, count do
		local best: number?, bestDistance = nil, math.huge
		for slot, distance in distances do
			if not out[slot] and distance <= DISPLAY.idleStuds and distance < bestDistance then
				best, bestDistance = slot, distance
			end
		end
		if best == nil then
			break
		end
		out[best] = true
	end
	return out
end

-- How many displays may run their idle life (breathing + blink), given by HeldSquishyController from the rigs it has
-- left over (spec 2026-10-09 §3.2 detail levels; Collection first, then the Ambient breathers). Answers how many it
-- uses (pickIdle on the last frame's distances) and takes no more until the next call, so HeldSquishyController gives
-- the rest to the breathers and no slot is counted twice. Until it calls, every display within idleStuds may (still at
-- most idleMax).
function CollectionController.setIdleSlots(n: number): number
	idleSlots = if n == n then math.max(0, math.floor(n)) else 0
	local used = 0
	for _ in CollectionController.pickIdle(idleDistances, idleSlots, wasReduced, idlePicked) do
		used += 1
	end
	idleUse = used
	return used
end

-- Small table for Studio debug hooks (SD_DebugClient "collection") and the L3 run.
function CollectionController.debugState(): DebugState
	local built: { [number]: { id: string, owned: boolean, status: string } } = {}
	local builtList: { { slot: number, id: string, owned: boolean, status: string } } = {}
	local count = 0
	for slot, display in displays do
		count += 1
		built[slot] = { id = display.id, owned = display.owned, status = display.status }
		table.insert(builtList, { slot = slot, id = display.id, owned = display.owned, status = display.status })
	end
	table.sort(builtList, function(a, b)
		return a.slot < b.slot
	end)
	local pedestals = 0
	for _ in pedestalBySlot do
		pedestals += 1
	end
	local nameplates, surfaceGuis, children = 0, 0, 0
	local current = folder
	if current and current.Parent ~= nil then
		children = #current:GetChildren()
		for _, descendant in current:GetDescendants() do
			if descendant:IsA("BillboardGui") then
				nameplates += 1
			elseif descendant:IsA("SurfaceGui") then
				surfaceGuis += 1
			end
		end
	end
	return {
		ok = true,
		started = cleanup ~= nil,
		builtCount = count,
		built = built,
		builtList = builtList,
		pedestals = pedestals,
		nameplates = nameplates,
		surfaceGuis = surfaceGuis,
		folderChildren = children,
		nearestStuds = if nearestStuds then math.floor(nearestStuds * 10 + 0.5) / 10 else nil,
		reduced = wasReduced,
		idleSlots = idleSlots,
		idle = idleCount,
	}
end

-- Lifecycle

function CollectionController.start()
	if cleanup ~= nil then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	ensureFolder()
	c:add(CollectionService:GetInstanceAddedSignal(TAG):Connect(track))
	c:add(CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack))
	for _, instance in CollectionService:GetTagged(TAG) do
		track(instance)
	end
	c:add(StateController.changed("owned"):connect(reconcile))
	c:add(StateController.Loaded:connect(reconcile))
	c:add(Scheduler.add(step, "render"))
	c:add(function()
		for slot in table.clone(displays) do
			removeDisplay(slot)
		end
		table.clear(pedestalBySlot)
		table.clear(slotOfPart)
		local current = folder
		folder = nil
		if current then
			current:Destroy()
		end
		lastCheck = -math.huge
		nearestStuds = nil
		wasReduced = false
		idleCount = 0
		table.clear(idleDistances)
		table.clear(idlePicked)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function CollectionController.destroy()
	local c = cleanup
	if c then
		cleanup = nil
		c:clean()
	end
end

return CollectionController
