--!strict
-- WorldBinder (client only). DESIGN §2.4, §7.6, §7.7, §1.6. Tag binders over the generated lobby, tolerant
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
-- Build plan Phase 6 removed the Jelly gates (SD_GripGate), the giant pads' pod signs (SD_GripSign) and lock decor
-- (SD_GripLock) with their binders and the Grip level source (setGripSource).

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

-- Constants

local ATTR_TEXT_KEY = "SD_TextKey"
local TAG_SIGN = "SD_Sign"
local TAG_AUDIO_ZONE = "SD_AudioZone"
local STAND_TAGS = {
	"SD_QuestBoard",
	"SD_DailyStand",
	"SD_BoxStand",
	"SD_ShopCounter",
	"SD_CollectionKiosk",
	"SD_CollectionPedestal",
	"SD_QueuePodium",
}
local ROOT_PART = "HumanoidRootPart"
local ZONE_CHECK_SECONDS = Config.Audio.zoneCheckSeconds -- §7.7: the HRP is checked every 0.25 s

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
local warnedKeys: { [string]: boolean } = {}

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

	-- Periodic check (a task loop, not frame events): audio zone 0.25 s.
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
	c:add(function()
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
