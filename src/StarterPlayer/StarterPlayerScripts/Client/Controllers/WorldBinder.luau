--!strict
-- WorldBinder (client only). DESIGN §2.4, §7.6, §7.7, §17.6, §1.6. Tag binders over the generated lobby, tolerant
-- of streaming: every binder works from CollectionService (instances already streamed in, then the added/removed
-- signals), keeps one Cleanup per bound instance and cleans it when the instance streams out or is destroyed.
--
-- * Signs (`SD_Sign`): a static TextLabel carries SD_TextKey; its text is re-applied from Strings, so text edits need
--   no rebuild (§1.6). A tagged non-text instance has its keyed text descendants applied instead. A key that is
--   missing from Strings, or whose text still has {placeholders} (a live line's owner fills those), keeps the baked
--   text (one warning per missing key). Live lines have no SD_TextKey and are never touched here.
-- * Stands (`SD_QuestBoard`, `SD_DailyStand`, `SD_BoxStand`, `SD_ShopCounter`, `SD_CollectionKiosk`,
--   `SD_CollectionPedestal`, `SD_QueuePodium`): every ProximityPrompt under the stand is built disabled. It is
--   enabled on this client only while a UI handler is registered for that tag with registerStand(tag, handler)
--   (§7.6: a stand built before its feature exists is inert, never a dead button). Its ActionText is re-applied from
--   the prompt's SD_TextKey. Triggered by the local player -> handler(stand, prompt) in its own thread. Prompts only
--   open UI; every purchase or claim still goes through the server (§2.8).
-- * Audio zones: every Config.Audio.zoneCheckSeconds (0.25 s, §7.7) the local character's HumanoidRootPart is tested
--   against the lobby zones of WorldLayout.AudioZones plus every streamed-in `SD_AudioZone` volume (arena clones
--   carry theirs); the highest priority wins. currentZone() and the ZoneChanged signal expose it (SoundController
--   comes later).
-- * Grip gates (`SD_GripGate`) and pod signs (`SD_GripSign`): the pad is the WorldLayout.GiantPads entry whose
--   centre is nearest the instance (within MAX_PAD_MATCH_STUDS), so the tier comes from WorldLayout, never from the
--   GripTier attribute, which is for Verify only (§17.6, §17.10). The level source is GripController (Part 5): it
--   calls setGripSource({level, changed = GripController.LevelChanged}) from its init (it sits above this module, so
--   the call goes downward, §2.6). Until a source is registered, and while its level() is nil (no grip state yet),
--   nothing is changed: gates stay open exactly as built (CanCollide false) and each sign's `Live` label keeps its
--   baked "Needs Grip Lv X" text. With a level, every recheckSeconds (Config.Grip.Gate,
--   0.5 s), on stream-in and on a level change, a gate is a LOCAL barrier with a latch (gateShouldBlock): while the
--   viewer's level is below the pad's level, an open gate closes once the viewer's root is farther than gate radius +
--   antiTrapPadding from its axis (nobody is shut in), and a closed gate stays closed however close the viewer
--   presses against it (a root pressed on the wall is within radius + 1, so a plain distance test let players in);
--   it opens again only for a high enough level, or for a viewer whose root is inside the jelly radius (trapped).
--   Locked / open transparency from Config.Grip.Gate; the `Live` label shows grip.signLocked / grip.signOpen. Any
--   error in that pass opens every gate and stops the gate logic for the session (fail open, §17.6). The server
--   checks the level on every squeeze and tick anyway.

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

-- Types

-- A UI handler for a stand tag: called with the tagged stand and the prompt the local player triggered.
export type StandHandler = (stand: Instance, prompt: ProximityPrompt) -> ()

-- The audio zone the local character is in.
export type ZoneInfo = {
	zoneId: string,
	priority: number,
	musicKey: string,
	ambienceKey: string,
	musicMul: number,
}

-- A zone candidate for pickZone(): its info plus its box (centre frame and size).
export type ZoneCandidate = ZoneInfo & {
	cframe: CFrame,
	size: Vector3,
}

-- The Grip level of the viewer (GripController.level / LevelChanged, Part 5). level() returns nil while unknown.
export type GripSource = {
	level: () -> number?,
	changed: { connect: (self: any, handler: (...any) -> ()) -> any }?,
}

-- A Util/Cleanup as stored in records (its generic add<T>() trips the exact record comparison of the type checker).
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}

type Stand = {
	tag: string,
	instance: Instance,
	prompts: { ProximityPrompt },
}

type GatePart = {
	part: BasePart,
	pad: any, -- WorldLayout GiantPad
	builtTransparency: number,
	builtCanCollide: boolean,
}

type PodSign = {
	instance: Instance,
	pad: any,
	live: TextLabel?,
	bakedText: string?,
}

-- The Config.Grip fields this module reads (Config.Grip lands with Part 3's Grip data; read defensively).
type GripPadConfig = { level: number, coinBonus: number, gripPercent: number }
type GripGateConfig = {
	lockedTransparency: number,
	openTransparency: number,
	antiTrapPadding: number,
	recheckSeconds: number,
}

-- Constants

local ATTR_TEXT_KEY = "SD_TextKey"
local TAG_SIGN = "SD_Sign"
local TAG_AUDIO_ZONE = "SD_AudioZone"
local TAG_GRIP_GATE = "SD_GripGate"
local TAG_GRIP_SIGN = "SD_GripSign"
local STAND_TAGS = {
	"SD_QuestBoard",
	"SD_DailyStand",
	"SD_BoxStand",
	"SD_ShopCounter",
	"SD_CollectionKiosk",
	"SD_CollectionPedestal",
	"SD_QueuePodium",
}
local LIVE_LABEL = "Live"
local ROOT_PART = "HumanoidRootPart"
local ZONE_CHECK_SECONDS = Config.Audio.zoneCheckSeconds -- §7.7: the HRP is checked every 0.25 s
local DEFAULT_GATE_RECHECK_SECONDS = 0.5 -- §17.6, used only if Config.Grip.Gate is missing
-- A gate or pod sign binds to the giant pad whose centre is this close (horizontally): a gate sits on its pad centre,
-- a pod sign about 8 studs in front of it, and pads are at least 20 studs apart.
local MAX_PAD_MATCH_STUDS = 12

-- Module table

local WorldBinder = {}

-- Fired with (zone, previous) when the local character's audio zone changes (nil = outside every zone).
WorldBinder.ZoneChanged = Signal.new() :: Signal.Signal<ZoneInfo?, ZoneInfo?>

-- Private

local log = Log.new("WorldBinder")
local cleanup: Cleanup.Cleanup? = nil
local handlers: { [string]: StandHandler } = {}
local stands: { [string]: { [Instance]: Stand } } = {}
local zoneParts: { [BasePart]: boolean } = {}
local currentZone: ZoneInfo? = nil
local gates: { [BasePart]: GatePart } = {}
local podSigns: { [Instance]: PodSign } = {}
local gripSource: GripSource? = nil
local gripSourceConnection: any = nil
local gateLogicFailed = false
local warnedKeys: { [string]: boolean } = {}

local function gripConfig(): any
	return (Config :: any).Grip
end

local function isTextObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

-- The Strings text for a sign/prompt key, or nil (missing key: one warning; a template with placeholders: nil).
local function staticText(key: unknown): string?
	if type(key) ~= "string" or key == "" then
		return nil
	end
	local text = Strings.resolve(key)
	if text == nil then
		if not warnedKeys[key] then
			warnedKeys[key] = true
			log:warn(`no Strings text for SD_TextKey {key}; keeping the baked text`)
		end
		return nil
	end
	if string.find(text, "{%w+}") then
		return nil
	end
	return text
end

local function applyTextTo(instance: Instance)
	if not isTextObject(instance) then
		return
	end
	local text = staticText(instance:GetAttribute(ATTR_TEXT_KEY))
	if text ~= nil then
		local label = instance :: any
		if label.Text ~= text then
			label.Text = text
		end
	end
end

-- Calls onAdded(instance, cleanup) for every instance with `tag` (now and when it streams in); the per-instance
-- cleanup runs when it streams out, is untagged or the binder is destroyed.
local function bindTag(c: Trove, tag: string, onAdded: (Instance, Trove) -> ())
	local bound: { [Instance]: Trove } = {}
	local function added(instance: Instance)
		if bound[instance] then
			return
		end
		local ic = Cleanup.new()
		bound[instance] = ic :: any
		local ok, err = pcall(function(): any
			onAdded(instance, ic :: any)
			return nil
		end)
		if not ok then
			log:error(`{tag} binder failed on {instance:GetFullName()}:`, err)
		end
	end
	local function removed(instance: Instance)
		local ic = bound[instance]
		if ic then
			bound[instance] = nil
			ic:clean()
		end
	end
	c:add(CollectionService:GetInstanceAddedSignal(tag):Connect(added))
	c:add(CollectionService:GetInstanceRemovedSignal(tag):Connect(removed))
	c:add(function()
		for instance in table.clone(bound) do
			removed(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		added(instance)
	end
end

-- Signs -------------------------------------------------------------------------------------------------------------

local function bindSign(instance: Instance, ic: Trove)
	if isTextObject(instance) then
		applyTextTo(instance)
		ic:add(instance:GetAttributeChangedSignal(ATTR_TEXT_KEY):Connect(function()
			applyTextTo(instance)
		end))
		return
	end
	-- A tagged container: its keyed text descendants (now and when they arrive).
	for _, descendant in instance:GetDescendants() do
		applyTextTo(descendant)
	end
	ic:add(instance.DescendantAdded:Connect(applyTextTo))
end

-- Stands ------------------------------------------------------------------------------------------------------------

local function refreshPrompt(tag: string, prompt: ProximityPrompt)
	local text = staticText(prompt:GetAttribute(ATTR_TEXT_KEY))
	if text ~= nil and prompt.ActionText ~= text then
		prompt.ActionText = text
	end
	local enabled = handlers[tag] ~= nil
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

local function refreshStands(tag: string)
	local list = stands[tag]
	if list == nil then
		return
	end
	for _, stand in list do
		for _, prompt in stand.prompts do
			refreshPrompt(tag, prompt)
		end
	end
end

local function bindStand(tag: string, instance: Instance, ic: Trove)
	local list = stands[tag]
	if list == nil then
		list = {}
		stands[tag] = list
	end
	local stand: Stand = { tag = tag, instance = instance, prompts = {} }
	list[instance] = stand
	ic:add(function()
		local current = stands[tag]
		if current and current[instance] == stand then
			current[instance] = nil
		end
	end)
	local function addPrompt(candidate: Instance)
		if not candidate:IsA("ProximityPrompt") or table.find(stand.prompts, candidate) then
			return
		end
		local prompt = candidate :: ProximityPrompt
		table.insert(stand.prompts, prompt)
		refreshPrompt(tag, prompt)
		ic:add(prompt.Triggered:Connect(function(player: Player)
			local handler = handlers[tag]
			if handler == nil or player ~= Players.LocalPlayer then
				return
			end
			task.spawn(function()
				local ok, err = pcall(function(): any
					handler(instance, prompt)
					return nil
				end)
				if not ok then
					log:error(`stand handler for {tag} failed:`, err)
				end
			end)
		end))
		ic:add(prompt.Destroying:Connect(function()
			local index = table.find(stand.prompts, prompt)
			if index then
				table.remove(stand.prompts, index)
			end
		end))
	end
	addPrompt(instance)
	for _, descendant in instance:GetDescendants() do
		addPrompt(descendant)
	end
	ic:add(instance.DescendantAdded:Connect(addPrompt))
end

-- Audio zones -------------------------------------------------------------------------------------------------------

local function zoneFromPart(part: BasePart): ZoneCandidate?
	local zoneId = part:GetAttribute("ZoneId")
	if type(zoneId) ~= "string" then
		return nil
	end
	local priority = part:GetAttribute("Priority")
	local musicKey = part:GetAttribute("MusicKey")
	local ambienceKey = part:GetAttribute("AmbienceKey")
	local musicMul = part:GetAttribute("MusicMul")
	return {
		zoneId = zoneId,
		priority = if type(priority) == "number" then priority else 0,
		musicKey = if type(musicKey) == "string" then musicKey else "",
		ambienceKey = if type(ambienceKey) == "string" then ambienceKey else "",
		musicMul = if type(musicMul) == "number" then musicMul else 1,
		cframe = part.CFrame,
		size = part.Size,
	}
end

local function zoneCandidates(): { ZoneCandidate }
	local list: { ZoneCandidate } = {}
	for _, zone in WorldLayout.AudioZones do
		table.insert(list, {
			zoneId = zone.zoneId,
			priority = zone.priority,
			musicKey = zone.musicKey,
			ambienceKey = zone.ambienceKey,
			musicMul = zone.musicMul,
			cframe = CFrame.new(zone.position),
			size = zone.size,
		})
	end
	for part in zoneParts do
		local candidate = zoneFromPart(part)
		if candidate then
			table.insert(list, candidate)
		end
	end
	return list
end

local function localRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function updateZone()
	local root = localRoot()
	local zone: ZoneInfo? = nil
	if root then
		local picked = WorldBinder.pickZone(zoneCandidates(), root.Position)
		if picked then
			zone = {
				zoneId = picked.zoneId,
				priority = picked.priority,
				musicKey = picked.musicKey,
				ambienceKey = picked.ambienceKey,
				musicMul = picked.musicMul,
			}
		end
	end
	local previous = currentZone
	local previousId = if previous then previous.zoneId else nil
	local nextId = if zone then zone.zoneId else nil
	if previousId ~= nextId then
		currentZone = zone
		WorldBinder.ZoneChanged:fire(zone, previous)
	end
end

-- Grip gates and pod signs ------------------------------------------------------------------------------------------

-- The WorldLayout giant pad for a gate or sign at `position` (see WorldBinder.padNear), or nil.
local function padFor(position: Vector3?): any
	if position == nil then
		return nil
	end
	return WorldBinder.padNear(position)
end

local function viewerLevel(): number?
	local source = gripSource
	if source == nil then
		return nil
	end
	local ok, level = pcall(source.level)
	if ok and type(level) == "number" then
		return level
	end
	return nil
end

local function openAllGates()
	for _, gate in gates do
		gate.part.CanCollide = gate.builtCanCollide
		gate.part.Transparency = gate.builtTransparency
	end
end

local function restoreSigns()
	for _, sign in podSigns do
		if sign.live and sign.bakedText ~= nil then
			sign.live.Text = sign.bakedText
		end
	end
end

local function updateGrip()
	if gateLogicFailed then
		return
	end
	local level = viewerLevel()
	local grip = gripConfig()
	if level == nil or type(grip) ~= "table" or type(grip.Pads) ~= "table" then
		openAllGates()
		restoreSigns()
		return
	end
	local gateConfig: GripGateConfig? = grip.Gate
	local root = localRoot()
	local ok, err = pcall(function(): any
		for _, gate in gates do
			local padConfig: GripPadConfig? = grip.Pads[gate.pad.tier]
			local required = if padConfig then padConfig.level else math.huge
			local distance = if root
				then WorldLayout.horizontalDistance(root.Position, gate.pad.gate.position)
				else math.huge
			local padding = if gateConfig then gateConfig.antiTrapPadding else 1
			local block = WorldBinder.gateShouldBlock(
				level,
				required,
				distance,
				gate.pad.gate.diameter / 2,
				padding,
				gate.part.CanCollide
			)
			local locked = level < required
			gate.part.CanCollide = block
			if gateConfig then
				gate.part.Transparency = if locked then gateConfig.lockedTransparency else gateConfig.openTransparency
			end
		end
		for _, sign in podSigns do
			local live = sign.live
			if live then
				local text = WorldBinder.podSignText(level, sign.pad.tier)
				if text ~= nil and live.Text ~= text then
					live.Text = text
				end
			end
		end
		return nil
	end)
	if not ok then
		gateLogicFailed = true
		log:error("Grip gate pass failed; every gate stays open for this session:", err)
		openAllGates()
	end
end

local function bindGate(instance: Instance, ic: Trove)
	if not instance:IsA("BasePart") then
		return
	end
	local part = instance :: BasePart
	local pad = padFor(part.Position)
	if pad == nil then
		log:warn(`{part:GetFullName()} is tagged {TAG_GRIP_GATE} but stands on no giant pad; left as built`)
		return
	end
	gates[part] = {
		part = part,
		pad = pad,
		builtTransparency = part.Transparency,
		builtCanCollide = part.CanCollide,
	}
	ic:add(function()
		gates[part] = nil
	end)
	if gripSource then
		updateGrip()
	end
end

local function bindPodSign(instance: Instance, ic: Trove)
	local position = if instance:IsA("BasePart")
		then instance.Position
		elseif instance:IsA("Model") then instance:GetPivot().Position
		else nil
	local pad = padFor(position)
	if pad == nil then
		log:warn(`{instance:GetFullName()} is tagged {TAG_GRIP_SIGN} but stands by no giant pad; left as built`)
		return
	end
	local sign: PodSign = { instance = instance, pad = pad, live = nil, bakedText = nil }
	local function findLive(candidate: Instance)
		if sign.live == nil and candidate.Name == LIVE_LABEL and candidate:IsA("TextLabel") then
			sign.live = candidate
			sign.bakedText = candidate.Text
			if gripSource then
				updateGrip()
			end
		end
	end
	for _, descendant in instance:GetDescendants() do
		findLive(descendant)
	end
	ic:add(instance.DescendantAdded:Connect(findLive))
	podSigns[instance] = sign
	ic:add(function()
		podSigns[instance] = nil
	end)
end

-- Public ------------------------------------------------------------------------------------------------------------

-- Registers the UI handler of a stand tag (one per tag; a new one replaces the old). Its prompts are enabled on this
-- client while a handler is registered. Returns a function that unregisters this handler.
function WorldBinder.registerStand(tag: string, handler: StandHandler): () -> ()
	assert(table.find(STAND_TAGS, tag) ~= nil, `[SD][WorldBinder] {tag} is not a stand tag`)
	assert(type(handler) == "function", "[SD][WorldBinder] handler must be a function")
	handlers[tag] = handler
	refreshStands(tag)
	return function()
		if handlers[tag] == handler then
			handlers[tag] = nil
			refreshStands(tag)
		end
	end
end

-- True while a handler is registered for the stand tag.
function WorldBinder.isStandRegistered(tag: string): boolean
	return handlers[tag] ~= nil
end

-- The stand tags this binder manages.
function WorldBinder.standTags(): { string }
	return table.clone(STAND_TAGS)
end

-- The local character's current audio zone (nil outside every zone or before the first check).
function WorldBinder.currentZone(): ZoneInfo?
	return currentZone
end

-- Pure: the highest-priority zone whose box contains `position` (ties: the first listed), or nil.
function WorldBinder.pickZone(candidates: { ZoneCandidate }, position: Vector3): ZoneCandidate?
	local best: ZoneCandidate? = nil
	for _, candidate in candidates do
		local p = candidate.cframe:PointToObjectSpace(position)
		local half = candidate.size / 2
		local inside = math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
		if inside and (best == nil or candidate.priority > (best :: ZoneCandidate).priority) then
			best = candidate
		end
	end
	return best
end

-- Pure: whether a jelly gate blocks the viewer next (§17.6), given whether it blocks now. Never for a high enough
-- level. A closed gate stays closed while the viewer's root is at or outside the jelly radius, however close it
-- presses (a root against the wall is within radius + padding, so a plain distance test let players walk in); it
-- opens only for a root inside the radius (a viewer somehow shut in). An open gate closes only once the root is
-- farther than radius + padding from the axis, so it never closes on someone standing in its wall (anti-trap).
function WorldBinder.gateShouldBlock(
	level: number,
	requiredLevel: number,
	distanceFromAxis: number,
	radius: number,
	padding: number,
	blockingNow: boolean?
): boolean
	if level >= requiredLevel then
		return false
	end
	if blockingNow then
		return distanceFromAxis >= radius
	end
	return distanceFromAxis > radius + padding
end

-- Pure: the WorldLayout giant pad whose centre is horizontally nearest `position`, if within MAX_PAD_MATCH_STUDS
-- (gates and pod signs; the tier then comes from WorldLayout, never from an attribute), else nil.
function WorldBinder.padNear(position: Vector3): any
	local best, bestDistance = nil, MAX_PAD_MATCH_STUDS
	for _, key in WorldLayout.GiantPadKeys do
		local pad = WorldLayout.GiantPads[key]
		local distance = WorldLayout.horizontalDistance(pad.center, position)
		if distance <= bestDistance then
			best, bestDistance = pad, distance
		end
	end
	return best
end

-- The `Live` line of a pod sign for this viewer level and GripTier (grip.signLocked / grip.signOpen), or nil when
-- Config.Grip or the Strings texts are missing (the baked text then stays).
function WorldBinder.podSignText(level: number, tier: number): string?
	local grip = gripConfig()
	local pad = if type(grip) == "table" and type(grip.Pads) == "table" then grip.Pads[tier] else nil
	if pad == nil then
		return nil
	end
	if level < pad.level then
		local template = Strings.resolve("grip.signLocked")
		return if template then Strings.format(template, { level = pad.level, have = level }) else nil
	end
	local template = Strings.resolve("grip.signOpen")
	return if template then Strings.format(template, { coins = pad.coinBonus, mult = pad.gripPercent / 100 }) else nil
end

-- Part 5 hook: the viewer's Grip level source. nil (the default) keeps gates open and pod signs baked.
function WorldBinder.setGripSource(source: GripSource?)
	if gripSourceConnection then
		local connection = gripSourceConnection
		gripSourceConnection = nil
		if type(connection) == "table" and type(connection.disconnect) == "function" then
			connection:disconnect()
		elseif typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
	gripSource = source
	if source and source.changed then
		gripSourceConnection = source.changed:connect(function()
			updateGrip()
		end)
	end
	updateGrip()
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function WorldBinder.init()
	local c = Cleanup.new()
	cleanup = c
	local trove = c :: any

	bindTag(trove, TAG_SIGN, bindSign)
	for _, tag in STAND_TAGS do
		bindTag(trove, tag, function(instance: Instance, ic: Trove)
			bindStand(tag, instance, ic)
		end)
	end
	bindTag(trove, TAG_AUDIO_ZONE, function(instance: Instance, ic: Trove)
		if instance:IsA("BasePart") then
			zoneParts[instance] = true
			ic:add(function()
				zoneParts[instance :: BasePart] = nil
			end)
		end
	end)
	bindTag(trove, TAG_GRIP_GATE, bindGate)
	bindTag(trove, TAG_GRIP_SIGN, bindPodSign)

	-- Periodic checks (task loops, not frame events): audio zone 0.25 s, Grip gates recheckSeconds.
	c:add(task.spawn(function()
		while true do
			local ok, err = pcall(function(): any
				updateZone()
				return nil
			end)
			if not ok then
				log:error("audio zone check failed:", err)
			end
			task.wait(ZONE_CHECK_SECONDS)
		end
	end))
	local grip = gripConfig()
	local recheck = if type(grip) == "table" and type(grip.Gate) == "table"
		then grip.Gate.recheckSeconds
		else DEFAULT_GATE_RECHECK_SECONDS
	c:add(task.spawn(function()
		while true do
			task.wait(recheck)
			if gripSource then
				updateGrip()
			end
		end
	end))
	c:add(function()
		WorldBinder.setGripSource(nil)
		currentZone = nil
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function WorldBinder.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return WorldBinder
