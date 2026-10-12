--!strict
-- SoundController (client only). DESIGN §2.4, §11.9 (audio mixing), §14 (asset slots), §7.7 (audio zones), §9.14,
-- and the feel pass sound wiring (§18.6) and Studio auditions (§18.7).
-- Every sound the client plays goes through here; every id comes from AssetTable (a slot whose id is nil plays
-- nothing: silent, and in Studio one warning per missing key at start, Config.Debug.warnMissingAssets). Studio only
-- by DESIGN §14.1 ("A nil id = silent/procedural feature + one warning in Studio"), which §11.9's "one warning per key
-- at startup" and §2.4 follow; live players' consoles stay clean while every id is still PENDING.
--
-- * SoundGroups Music, SFX, UI, Ambient are created under SoundService at runtime (init). SoundGroup.Volume defaults
--   to 0.5 (V), so it is always set: groupVolume = Config.Audio.Groups[g].maxVolume × slider / 100, the slider being
--   settings.music (Music) or settings.sfx (SFX, UI, Ambient), read from StateController (local overrides included, so
--   a Settings slider is heard at once). Music also carries the product of the active ducks (below), ramped over
--   Ducking.rampMs.
-- * play(key, options): a one-shot. Rules, in order (each refusal is one result in the Studio log, recent()):
--   1. the key is a sound slot ("noId" otherwise; AssetTable warns once);
--   2. the per-key cooldown ("cooldown"; cooldownMs by category: squeeze 90, coin 60 with the coin batch of
--      coinBatchSeconds, impact 50, uiClick 40, throw 60, wobble 80, pop 60, hover 60, hitConfirm 50, error 250).
--      Reading (§18.6 "other players' sounds −1, dropped first"): other players' sounds (priority below 0) keep their
--      own cooldown per key (cooldownKey), so another player's squish never silences the local player's own;
--   3. another player's sound (options.other = "squeeze" | "throw"; options.otherPlayer is the old alias for
--      "squeeze") only within its Spatial.others*Studs of the camera and at most others*Max at once (othersAllowed;
--      "distance" / "caps"); any other 3D one-shot farther than Spatial.maxDistance from the camera is skipped
--      ("distance");
--   4. the key has something to play: an approved id, a variant or a Studio audition ("noId"; the ask still arms the
--      cooldown, so the Studio log shows the real cadence before any id exists, §18.11 sound wiring check 3);
--   5. the voice caps (VoiceCaps: SFX 10 total and 3 per key, UI 4, Ambient 2, Music 1 / 2 during a crossfade;
--      Config.Audio.perKeyCap overrides the per-key cap, e.g. sfx.jellyWobble 2): when full, the oldest non-looping
--      voice of no higher priority is stopped with a stealFadeMs fade, otherwise the new sound is dropped (admit, pure;
--      "caps"). Other players' sounds default to priority -1, so they are dropped first (§18.6).
--   Then "played". The pitch is 1 ± the key's variance (pitchVariance; options.variance overrides it, e.g. the squeeze
--   streak's ±1%) times options.pitch, clamped to [pitchMin, pitchMax] (pitchFor). options.group overrides the slot's
--   group (Inspect plays sfx.squish on UI). A 3D slot played with options.at (a position, part or attachment) plays
--   from an Attachment in Workspace.Terrain at that point (RollOffMode InverseTapered, min/max distance from
--   Config.Audio.Spatial); every other sound is 2D.
-- * Variants (§18.6): AssetTable.soundChoices(key) lists the slot's id and its variants, each with its own volume;
--   pickVariant never repeats the last pick of a key when there are two or more.
-- * playTracked(key, options) -> stop(fadeMs?)?: a one-shot that can be stopped early (the Dragon telegraph, stopped
--   with Config.Audio.trackedStopFadeMs on a cancel); nil when nothing started.
-- * Spec phase2-squeeze §3.9 (Inspect's knead, Controllers/KneadAudio): the Wax group (Config.Audio.Groups.Wax, the SFX
--   slider, a CompressorSoundEffect from its `compressor`; VoiceCaps.Wax), options.region (only that part of the file
--   plays: Sound.PlaybackRegion) and options.timePosition, and playLoop(key, options) -> Loop?: a looped voice whose
--   volume the caller sets every frame (setVolume) and stops (stop); feature 1 (2026-10-11): and its pitch (setPitch,
--   the charge tone).
-- * Pooling: Sound instances are reused per key; a finished voice goes back to its key's pool.
-- * Stuck voices: a one-shot leaves on Sound.Ended, a steal or a stop. Reading (DESIGN is silent): a Sound whose
--   asset never loads never fires Ended, so every play attempt first drops the one-shots past their longest possible
--   life (voiceExpired: not loaded VOICE_LOAD_SECONDS after the start, or older than that plus their length at their
--   speed plus VOICE_END_SLACK_SECONDS); no timer or connection is added for it.
-- * Music and ambience: setMusic(key?) / setAmbience(key?) crossfade over crossfadeSeconds (looped voices). The lobby's
--   audio zones drive them once a zone source is set (setZoneSource: WorldBinder.currentZone + ZoneChanged; WorldBinder
--   is a higher layer, so the HUD wires it, reading): the zone's musicKey and ambienceKey, and its musicMul as the
--   "zone" duck.
-- * Ducking (§11.9, §18.6): duck(reason, mult?) -> release; the default multipliers are Config.Audio.Ducking[reason]
--   (boxReveal 0.5, countdown 0.6, result 0.6, inspect 0.8, knockout 0.5, telegraph 0.8). duckFor(reason, seconds?)
--   releases itself after `seconds` (default Ducking[reason .. "Seconds"], e.g. knockoutSeconds 0.6). Countdown and
--   Result are applied here from the duel view; the others are called by their owners.
-- * Studio auditions (§18.7; only while Config.Debug.soundPicker, which is false outside Studio): audition(key, id?,
--   volume?) makes a candidate id the only choice of that key (playable through every real code path), id = nil
--   drops it, clearAuditions() drops all. Reading: the candidate enters through the one choice function that play,
--   playTracked and the music/ambience crossfade all use, so slotOf keeps returning the real slot (its group and 3D
--   flag). The content string comes from AssetTable.contentIdFor. Re-auditioning, or clearing, the music or ambience
--   key that is playing restarts its crossfade. hasAnyIn, missingKeys and the startup warnings ignore auditions.
-- * Studio log (§18.6): recent() returns the last Config.Audio.recentLogSize play attempts {key, t, result}; the debug
--   hooks expose it as SD_DebugClient:Invoke("sounds"). Reading: kept only in Studio (Config.Debug.isStudio).
-- Reading (§11.9 "UI/Inspect sounds are local (SoundService:PlayLocalSound)"): a Sound created by this LocalScript never
-- replicates, so Sound:Play() on it is already local; :Play() is kept for every group because PlayLocalSound gives no
-- handle to stop a voice (the caps need one).
-- The rules (admit, groupVolume, categoryOf, cooldownSeconds, cooldownKey, voiceExpired, pitchVariance, pitchFor,
-- pickVariant, othersAllowed, otherKindOf, audible, resolveGroup, auditionAllowed, duckProduct, duelDucks,
-- missingKeys) are pure and unit-tested in Edit mode.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local StateController = require(script.Parent.StateController)

-- Types

export type GroupName = "Music" | "SFX" | "UI" | "Ambient" | "Wax"

-- Another player's sound kind (§18.6): its own distance and count limits.
export type OtherKind = "squeeze" | "throw"

export type PlayOptions = {
	at: (Vector3 | BasePart | Attachment)?, -- 3D source (3D slots only)
	priority: number?, -- higher steals from lower when a group is full (default 0; other players' sounds -1)
	volume: number?, -- multiplies the chosen id's volume (default 1)
	pitch: number?, -- multiplies the random pitch; the result is clamped to [pitchMin, pitchMax]
	variance: number?, -- overrides the key's ± random pitch variance (the squeeze streak's ±1%)
	group: GroupName?, -- overrides the slot's group (Inspect plays on UI)
	other: OtherKind?, -- another player's sound: distance and count limits (othersAllowed)
	otherPlayer: boolean?, -- old alias for other = "squeeze"
	-- Spec phase2-squeeze §3.9 (the knead's wax sheets): play only this part of the file (Sound.PlaybackRegion, seconds)
	region: NumberRange?,
	timePosition: number?, -- start here (a loop's random start); default the region's start, else 0
}

-- A looped voice the caller drives (playLoop): Volume = the choice's volume × setVolume's; PlaybackSpeed = setPitch's,
-- clamped to [pitchMin, pitchMax] (feature 1, 2026-10-11: the charge tone rises with the charge).
export type Loop = {
	setVolume: (self: Loop, volume: number) -> (),
	setPitch: (self: Loop, pitch: number) -> (),
	stop: (self: Loop, fadeMs: number?) -> (),
}

-- One play attempt's outcome (the Studio log).
export type PlayResult = "played" | "noId" | "cooldown" | "caps" | "distance"

export type RecentEntry = {
	key: string,
	t: number, -- os.clock() of the attempt
	result: PlayResult,
}

-- What admit() needs to know about a playing voice.
export type VoiceInfo = {
	group: string,
	key: string,
	startedAt: number,
	looped: boolean,
	priority: number,
}

export type Caps = {
	SFX: number,
	SFXPerKey: number,
	UI: number,
	Ambient: number,
	Music: number,
	MusicDuringCrossfade: number,
}

-- A zone as WorldBinder reports it.
export type ZoneLike = { musicKey: string?, ambienceKey: string?, musicMul: number? }

type Choice = AssetTable.SoundChoice

type Voice = VoiceInfo & {
	sound: Sound,
	holder: Attachment?,
	other: OtherKind?,
	stopping: boolean,
	fade: Tween?,
	ended: RBXScriptConnection?, -- a one-shot's Ended listener (dropped when the voice goes, so a pooled Sound keeps none)
}

-- Constants

local AUDIO = Config.Audio
local GROUP_NAMES: { GroupName } = { "Music", "SFX", "UI", "Ambient", "Wax" } -- Wax: spec phase2-squeeze §3.9
local POOL_FOLDER = "SD_Sounds"
local HOLDER_NAME = "SD_SoundAt"
local MS = 1000
local MAX_VOLUME = 2 -- an audition volume is clamped to [0, 2] (AssetTable_Test's volume range)
local MAX_VARIANCE = 0.5 -- options.variance is clamped to [0, 0.5] (Config.validate's pitchVariance range)
local OTHER_PRIORITY = -1 -- other players' sounds drop first (§18.6)
local OTHER_COOLDOWN_SUFFIX = "#other" -- other players' sounds keep their own cooldown per key (cooldownKey)
-- Reading (DESIGN is silent): a one-shot that has not loaded this long after its start, or that is this much past its
-- end, is dropped (voiceExpired; the backstop to Sound.Ended, which never fires for an asset that fails to load).
local VOICE_LOAD_SECONDS = 5
local VOICE_END_SLACK_SECONDS = 0.5
-- Keys by cooldown / pitch category (§11.9: squeeze, coin, impact, UI click; §18.6: throw, wobble, pop, hover,
-- hitConfirm, error).
local CATEGORY: { [string]: string } = {
	["sfx.squish"] = "squeeze",
	["sfx.squeezeRelease"] = "squeeze",
	["ui.coin"] = "coin",
	["sfx.impactBoing"] = "impact",
	["sfx.impactSoft"] = "impact",
	["ui.click"] = "uiClick",
	["ui.back"] = "uiClick",
	["ui.open"] = "uiClick",
	["sfx.throw"] = "throw",
	["sfx.jellyWobble"] = "wobble",
	["sfx.pop"] = "pop",
	["ui.hover"] = "hover",
	["ui.hitConfirm"] = "hitConfirm",
	["ui.error"] = "error",
	-- Spec phase 5: the dash, and the Epic ultimates' drop and pop impacts.
	["sfx.dash"] = "dash",
	["sfx.dashPlant"] = "dash",
	["sfx.ultRainDrop"] = "impact",
	["sfx.ultBubblePop"] = "impact",
}
-- UI keys whose pitch never varies (§18.6 "Variation" 0 or fixed: the countdown ticks get their pitch from the
-- caller, Config.Audio.countdownPitch; jingles and reveals play as recorded). Every other UI key varies by ±ui.
local FIXED_PITCH: { [string]: boolean } = {
	["duel.countdownTick"] = true,
	["duel.go"] = true,
	["duel.win"] = true,
	["duel.lose"] = true,
	["duel.draw"] = true,
	["box.open"] = true,
	["reveal.common"] = true,
	["reveal.uncommon"] = true,
	["reveal.epic"] = true,
	["reveal.exclusive"] = true,
}
local DUCK_ZONE = "zone"
local DUCK_COUNTDOWN = "countdown"
local DUCK_RESULT = "result"
local DUCK_SECONDS_SUFFIX = "Seconds" -- duckFor's default length: Config.Audio.Ducking[reason .. "Seconds"]

-- Module table

local SoundController = {}

-- (groupName, volume) when a group's volume target changes.
SoundController.VolumeChanged = Signal.new() :: Signal.Signal<string, number>

-- Private

local log = Log.new("Sound")
local cleanup: Cleanup.Cleanup? = nil
local groups: { [string]: SoundGroup } = {}
local poolFolder: Folder? = nil
local slotsByKey: { [string]: AssetTable.AssetSlot } = {}
local pools: { [string]: { Sound } } = {}
local voices: { Voice } = {}
local lastPlayed: { [string]: number } = {}
local lastPick: { [string]: number } = {}
local ducks: { [string]: number } = {}
local duckSerial = 0
local duckTimers: { [thread]: boolean } = {}
local musicVoice: Voice? = nil
local ambienceVoice: Voice? = nil
local musicKey: string? = nil
local ambienceKey: string? = nil
local crossfading = false
local random = Random.new()
local groupTweens: { [string]: Tween } = {}
local indexed = false
local auditions: { [string]: Choice } = {}
local recentLog: { RecentEntry } = {}

-- The sound slot of a key (the index is built on first use, not at require time). Never an audition (see header).
local function slotOf(key: string): AssetTable.AssetSlot?
	if not indexed then
		indexed = true
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" then
				slotsByKey[slot.key] = slot
			end
		end
	end
	return slotsByKey[key]
end

local function clock(): number
	return os.clock()
end

local function isGroup(name: unknown): boolean
	return type(name) == "string" and AUDIO.Groups[name] ~= nil
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function targetVolume(name: string): number
	local mult = if name == "Music" then SoundController.duckProduct(ducks) else 1
	return SoundController.groupVolume(name, StateController.settings(), mult)
end

local function applyGroupVolume(name: string, ramp: boolean)
	local group: SoundGroup? = groups[name]
	if group == nil then
		return
	end
	local volume = targetVolume(name)
	local running = groupTweens[name]
	if running then
		running:Cancel()
		groupTweens[name] = nil
	end
	if ramp and AUDIO.Ducking.rampMs > 0 then
		local tween = TweenService:Create(
			group,
			TweenInfo.new(AUDIO.Ducking.rampMs / MS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Volume = volume }
		)
		groupTweens[name] = tween
		tween:Play()
	else
		group.Volume = volume
	end
	SoundController.VolumeChanged:fire(name, volume)
end

local function applyAllVolumes()
	for _, name in GROUP_NAMES do
		applyGroupVolume(name, false)
	end
end

local function cameraPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function positionOf(at: any): Vector3?
	if typeof(at) == "Vector3" then
		return at
	elseif typeof(at) == "Instance" then
		if at:IsA("BasePart") then
			return at.Position
		elseif at:IsA("Attachment") then
			return at.WorldPosition
		end
	end
	return nil
end

-- One play attempt in the Studio log (kept in Studio only, at most recentLogSize entries).
local function record(key: string, result: PlayResult)
	if not Config.Debug.isStudio then
		return
	end
	table.insert(recentLog, { key = key, t = clock(), result = result })
	local size = math.max(1, AUDIO.recentLogSize)
	while #recentLog > size do
		table.remove(recentLog, 1)
	end
end

local function removeVoice(voice: Voice)
	local index = table.find(voices, voice)
	if index then
		table.remove(voices, index)
	end
	if voice.fade then
		voice.fade:Cancel()
		voice.fade = nil
	end
	if voice.ended then
		voice.ended:Disconnect()
		voice.ended = nil
	end
	local sound = voice.sound
	pcall(function()
		sound:Stop()
	end)
	local folder = poolFolder
	if folder ~= nil and sound.Parent ~= nil then
		sound.Parent = folder -- out of the 3D holder before it goes
		local pool = pools[voice.key]
		if pool == nil then
			pool = {}
			pools[voice.key] = pool
		end
		table.insert(pool, sound)
	else
		sound:Destroy()
	end
	if voice.holder then
		voice.holder:Destroy()
		voice.holder = nil
	end
	if musicVoice == voice then
		musicVoice = nil
	end
	if ambienceVoice == voice then
		ambienceVoice = nil
	end
end

-- Fades a voice out over `ms`, then stops it and returns its Sound to the pool.
local function stopVoice(voice: Voice, ms: number)
	if voice.stopping then
		return
	end
	voice.stopping = true
	if ms <= 0 then
		removeVoice(voice)
		return
	end
	local tween = TweenService:Create(voice.sound, TweenInfo.new(ms / MS, Enum.EasingStyle.Linear), { Volume = 0 })
	voice.fade = tween
	tween.Completed:Once(function()
		if voice.fade == tween then
			voice.fade = nil
			removeVoice(voice)
		end
	end)
	tween:Play()
end

local function soundFor(key: string, contentId: string): Sound?
	local folder = poolFolder
	if folder == nil then
		return nil
	end
	local pool = pools[key]
	if pool and #pool > 0 then
		local sound = table.remove(pool) :: Sound
		if sound.Parent ~= nil then
			sound.SoundId = contentId
			return sound
		end
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = contentId
	sound.Parent = folder
	return sound
end

-- True when `key` has something to play: a Studio audition, or an approved id (and its variants).
local function playable(key: string): boolean
	return auditions[key] ~= nil or #AssetTable.soundChoices(key) > 0
end

-- The id (and volume) the next voice of `key` plays: the audition while one is set, else a variant pick that never
-- repeats the key's last pick. nil when there is nothing to play.
local function choiceFor(key: string): Choice?
	local audition = auditions[key]
	if audition then
		return audition
	end
	local choices = AssetTable.soundChoices(key)
	local index = SoundController.pickVariant(#choices, lastPick[key], random:NextNumber())
	if index < 1 then
		return nil
	end
	lastPick[key] = index
	return choices[index]
end

-- Starts a voice for `key` with `choice` in `groupName` (no rule checks). Returns it, or nil when it can't start.
local function startVoice(
	key: string,
	options: PlayOptions,
	looped: boolean,
	startVolume: number?,
	choice: Choice,
	groupName: string
): Voice?
	local slot = slotOf(key)
	if slot == nil then
		return nil
	end
	local sound = soundFor(key, choice.content)
	if sound == nil then
		return nil
	end
	local baseVolume = choice.volume * (options.volume or 1)
	sound.SoundGroup = groups[groupName]
	sound.Looped = looped
	sound.Volume = if startVolume ~= nil then startVolume else baseVolume
	local variance = SoundController.pitchVariance(key, groupName, options.variance)
	sound.PlaybackSpeed = SoundController.pitchFor(variance, random:NextNumber(), options.pitch)
	local holder: Attachment? = nil
	local position = if slot.spatial then positionOf(options.at) else nil
	if position then
		local attachment = Instance.new("Attachment")
		attachment.Name = HOLDER_NAME
		attachment.WorldPosition = position
		attachment.Parent = Workspace.Terrain
		holder = attachment
		local spatial = AUDIO.Spatial
		sound.RollOffMode = spatial.rollOffMode
		sound.RollOffMinDistance = spatial.minDistance
		sound.RollOffMaxDistance = spatial.maxDistance
		sound.Parent = attachment
	else
		sound.Parent = poolFolder
	end
	local voice: Voice = {
		group = groupName,
		key = key,
		startedAt = clock(),
		looped = looped,
		priority = options.priority or 0,
		sound = sound,
		holder = holder,
		other = SoundController.otherKindOf(options),
		stopping = false,
		fade = nil,
		ended = nil,
	}
	table.insert(voices, voice)
	if not looped then
		voice.ended = sound.Ended:Once(function()
			voice.ended = nil
			if table.find(voices, voice) then
				removeVoice(voice)
			end
		end)
	end
	-- Spec phase2-squeeze §3.9: a region of the file (the wax sheets), and where to start (a loop's random offset).
	local region = options.region
	sound.PlaybackRegionsEnabled = region ~= nil
	if region then
		sound.PlaybackRegion = region
	end
	sound.TimePosition = options.timePosition or (if region then region.Min else 0)
	sound:Play()
	return voice
end

-- The voices that are not fading out, and the same list as admit() reads it (same order, same indices).
local function liveVoices(): ({ Voice }, { VoiceInfo })
	local list: { Voice } = {}
	local infos: { VoiceInfo } = {}
	for _, voice in voices do
		if not voice.stopping then
			table.insert(list, voice)
			table.insert(infos, {
				group = voice.group,
				key = voice.key,
				startedAt = voice.startedAt,
				looped = voice.looped,
				priority = voice.priority,
			})
		end
	end
	return list, infos
end

-- Drops the one-shot voices past their longest possible life (header, "Stuck voices"). Walks backwards, since
-- removeVoice takes the voice out of `voices`.
local function sweepVoices(now: number)
	for index = #voices, 1, -1 do
		local voice = voices[index]
		if voice ~= nil and not voice.looped and not voice.stopping then
			local sound = voice.sound
			if
				SoundController.voiceExpired(
					now,
					voice.startedAt,
					sound.IsLoaded,
					sound.TimeLength,
					sound.PlaybackSpeed
				)
			then
				removeVoice(voice)
			end
		end
	end
end

-- Other players' live voices of one kind.
local function countOthers(kind: string): number
	local count = 0
	for _, voice in voices do
		if voice.other == kind and not voice.stopping then
			count += 1
		end
	end
	return count
end

-- One one-shot attempt through every rule of the header (no logging). Returns the voice (nil unless "played").
local function attempt(key: string, opts: PlayOptions): (Voice?, PlayResult)
	local slot = slotOf(key)
	if slot == nil then
		AssetTable.sound(key) -- warns once for an unknown key
		return nil, "noId"
	end
	local now = clock()
	sweepVoices(now)
	local kind = SoundController.otherKindOf(opts)
	local priority = opts.priority or (if kind ~= nil then OTHER_PRIORITY else 0)
	local bucket = SoundController.cooldownKey(key, priority)
	local wait = SoundController.cooldownSeconds(key)
	local last = lastPlayed[bucket]
	if last and now - last < wait then
		return nil, "cooldown"
	end
	local position = positionOf(opts.at)
	local from = cameraPosition()
	local distance = if position ~= nil and from ~= nil then (position - from).Magnitude else nil
	if kind ~= nil then
		local allowed, reason = SoundController.othersAllowed(kind, distance, countOthers(kind))
		if not allowed then
			return nil, (reason or "caps") :: PlayResult
		end
	elseif slot.spatial and not SoundController.audible(distance) then
		return nil, "distance"
	end
	if not playable(key) or poolFolder == nil then
		lastPlayed[bucket] = now -- the ask arms the cooldown (header rule 4)
		return nil, "noId" -- PENDING slot (warned once at start), or init() not run (Edit-mode tests)
	end
	local groupName = SoundController.resolveGroup(slot.group, opts.group)
	local live, infos = liveVoices()
	local allowed, victim = SoundController.admit(
		infos,
		groupName,
		key,
		priority,
		AUDIO.VoiceCaps :: any,
		crossfading,
		AUDIO.perKeyCap :: any
	)
	if not allowed then
		return nil, "caps"
	end
	if victim then
		stopVoice(live[victim], AUDIO.stealFadeMs)
	end
	lastPlayed[bucket] = now
	local choice = choiceFor(key)
	if choice == nil then
		return nil, "noId"
	end
	local startOpts = table.clone(opts)
	startOpts.priority = priority
	local voice = startVoice(key, startOpts, false, nil, choice, groupName)
	return voice, if voice then "played" else "noId"
end

-- Crossfades a looped slot (music or ambience). Returns the new voice (nil = silence).
local function crossfadeTo(current: Voice?, key: string?): Voice?
	local seconds = AUDIO.crossfadeSeconds
	if current then
		stopVoice(current, seconds * MS)
	end
	if key == nil then
		return nil
	end
	local slot = slotOf(key)
	if slot == nil then
		AssetTable.sound(key) -- warns once for an unknown key
		return nil
	end
	local choice = if playable(key) then choiceFor(key) else nil
	if choice == nil then
		return nil
	end
	crossfading = true
	local voice = startVoice(key, {}, true, 0, choice, SoundController.resolveGroup(slot.group, nil))
	if voice then
		local tween = TweenService:Create(
			voice.sound,
			TweenInfo.new(seconds, Enum.EasingStyle.Linear),
			{ Volume = choice.volume }
		)
		voice.fade = tween
		tween.Completed:Once(function()
			if voice.fade == tween then
				voice.fade = nil
			end
			crossfading = false
		end)
		tween:Play()
	else
		crossfading = false
	end
	return voice
end

-- Restarts the music or ambience crossfade when `key` is the one playing (an audition was set or cleared).
local function restartLoop(key: string)
	if key == musicKey then
		musicVoice = crossfadeTo(musicVoice, key)
	end
	if key == ambienceKey then
		ambienceVoice = crossfadeTo(ambienceVoice, key)
	end
end

local function setDuck(reason: string, mult: number?)
	if mult == nil then
		ducks[reason] = nil
	else
		ducks[reason] = mult
	end
	applyGroupVolume("Music", true)
end

local function applyDuelDucks()
	local wanted = SoundController.duelDucks(StateController.duel())
	for _, reason in { DUCK_COUNTDOWN, DUCK_RESULT } do
		if ducks[reason] ~= wanted[reason] then
			setDuck(reason, wanted[reason])
		end
	end
end

-- Public: pure rules ---------------------------------------------------------------------------------------------------

-- SoundGroup volume: maxVolume × slider / 100 × mult, clamped to [0, maxVolume].
function SoundController.groupVolume(groupName: string, settings: Types.Settings, mult: number?): number
	local group = AUDIO.Groups[groupName]
	if group == nil then
		return 0
	end
	local slider = (settings :: any)[group.slider]
	local value = if type(slider) == "number" and slider == slider then math.clamp(slider, 0, 100) else 0
	local m = if type(mult) == "number" and mult == mult then math.clamp(mult, 0, 1) else 1
	return group.maxVolume * value / 100 * m
end

-- The cooldown / pitch category of a sound key (squeeze, coin, impact, uiClick, throw, wobble, pop, hover,
-- hitConfirm, error), or nil.
function SoundController.categoryOf(key: string): string?
	return CATEGORY[key]
end

-- Seconds a key must wait after it last played (0 = no cooldown). Coins are batched to <= 1 per coinBatchSeconds.
function SoundController.cooldownSeconds(key: string): number
	local category = CATEGORY[key]
	if category == nil then
		return 0
	end
	local ms = (AUDIO.cooldownMs :: any)[category]
	local seconds = if type(ms) == "number" then ms / MS else 0
	if category == "coin" then
		seconds = math.max(seconds, AUDIO.coinBatchSeconds)
	end
	return seconds
end

-- The cooldown bucket of a play: the key itself, or key .. "#other" for another player's sound (priority below 0), so
-- other players' sounds and the local player's own never hold each other's cooldown (§18.6: others drop first).
function SoundController.cooldownKey(key: string, priority: number?): string
	return if isFiniteNumber(priority) and (priority :: number) < 0 then key .. OTHER_COOLDOWN_SUFFIX else key
end

-- Whether a one-shot voice started at `startedAt` is past its longest possible life at `now`: not loaded
-- VOICE_LOAD_SECONDS after its start, or loaded and older than that plus its length at `speed` (a missing or
-- non-positive speed counts as 1) plus VOICE_END_SLACK_SECONDS. Sound.Ended normally removes it long before.
function SoundController.voiceExpired(
	now: number,
	startedAt: number,
	isLoaded: boolean,
	timeLength: number?,
	speed: number?
): boolean
	local age = now - startedAt
	if not isFiniteNumber(age) then
		return false
	end
	local limit = VOICE_LOAD_SECONDS
	if isLoaded and isFiniteNumber(timeLength) and (timeLength :: number) > 0 then
		local rate = if isFiniteNumber(speed) and (speed :: number) > 0 then speed :: number else 1
		limit += (timeLength :: number) / rate + VOICE_END_SLACK_SECONDS
	end
	return age > limit
end

-- ± pitch variation fraction: `override` when given (clamped to [0, 0.5]); else the key's category variance
-- (squeeze, impact, throw, wobble, pop, hitConfirm); else 0 for the fixed-pitch UI keys; else "ui" for every other
-- UI sound; else 0.
function SoundController.pitchVariance(key: string, groupName: string?, override: number?): number
	if isFiniteNumber(override) then
		return math.clamp(override :: number, 0, MAX_VARIANCE)
	end
	local variance = AUDIO.pitchVariance :: { [string]: number }
	local category = CATEGORY[key]
	local byCategory = if category ~= nil then variance[category] else nil
	if type(byCategory) == "number" then
		return byCategory
	elseif FIXED_PITCH[key] then
		return 0
	elseif groupName == "UI" then
		return variance.ui
	end
	return 0
end

-- The playback pitch: (1 + (2·roll − 1) · variance) × mult, clamped to [pitchMin, pitchMax]. roll is in [0, 1];
-- a missing, non-positive or non-finite mult counts as 1.
function SoundController.pitchFor(variance: number, roll: number, mult: number?): number
	local r = if isFiniteNumber(roll) then math.clamp(roll, 0, 1) else 0.5
	local v = if isFiniteNumber(variance) then math.max(variance, 0) else 0
	local m = if isFiniteNumber(mult) and (mult :: number) > 0 then mult :: number else 1
	return math.clamp((1 + (2 * r - 1) * v) * m, AUDIO.pitchMin, AUDIO.pitchMax)
end

-- Which of `n` choices to play (1-based; 0 when n < 1) for a roll in [0, 1). With n >= 2 it never repeats `last`
-- (it rolls among the other n − 1), and every choice can come up.
function SoundController.pickVariant(n: number, last: number?, roll: number): number
	local count = if isFiniteNumber(n) then math.floor(n) else 0
	if count < 1 then
		return 0
	elseif count == 1 then
		return 1
	end
	local r = if isFiniteNumber(roll) then math.clamp(roll, 0, 1) else 0
	local avoid = if last ~= nil
			and isFiniteNumber(last)
			and last >= 1
			and last <= count
			and math.floor(last) == last
		then last
		else nil
	if avoid == nil then
		return math.min(math.floor(r * count) + 1, count)
	end
	local index = math.min(math.floor(r * (count - 1)) + 1, count - 1)
	return if index >= avoid then index + 1 else index
end

-- The other-player kind of a play (options.other, or "squeeze" for the old otherPlayer flag), or nil.
function SoundController.otherKindOf(options: PlayOptions?): OtherKind?
	if options == nil then
		return nil
	elseif options.other == "squeeze" or options.other == "throw" then
		return options.other
	elseif options.otherPlayer == true then
		return "squeeze"
	end
	return nil
end

-- Whether another player's sound of `kind` may play `distance` studs from the camera with `count` of that kind
-- already playing: squeezes within Spatial.othersSqueezeStuds (50), at most othersSqueezeMax (3); throws within
-- othersThrowStuds (60), at most othersThrowMax (3). Returns (false, "distance" | "caps") when not; an unknown
-- distance (no camera or no position) is too far.
function SoundController.othersAllowed(kind: string, distance: number?, count: number): (boolean, PlayResult?)
	local spatial = AUDIO.Spatial
	local studs: number, max: number
	if kind == "squeeze" then
		studs, max = spatial.othersSqueezeStuds, spatial.othersSqueezeMax
	elseif kind == "throw" then
		studs, max = spatial.othersThrowStuds, spatial.othersThrowMax
	else
		return false, "caps"
	end
	if distance == nil or not isFiniteNumber(distance) or distance > studs then
		return false, "distance"
	end
	if count >= max then
		return false, "caps"
	end
	return true, nil
end

-- Whether a 3D one-shot `distance` studs from the camera is played (<= Spatial.maxDistance; nil = unknown, played).
function SoundController.audible(distance: number?): boolean
	return distance == nil or distance <= AUDIO.Spatial.maxDistance
end

-- The group a sound plays in: a valid override, else the slot's group, else SFX.
function SoundController.resolveGroup(slotGroup: string?, override: string?): string
	if isGroup(override) then
		return override :: string
	elseif isGroup(slotGroup) then
		return slotGroup :: string
	end
	return "SFX"
end

-- Whether an audition of `key` (id = nil drops it) is taken: only while `enabled` (Config.Debug.soundPicker), for a
-- sound slot key, with a positive integer id or nil.
function SoundController.auditionAllowed(enabled: boolean, key: string, id: number?): boolean
	if enabled ~= true or type(key) ~= "string" or slotOf(key) == nil then
		return false
	end
	return id == nil or AssetTable.contentIdFor(id) ~= nil
end

-- The product of every active duck multiplier, clamped to [0, 1] (1 with no duck).
function SoundController.duckProduct(active: { [string]: number }): number
	local product = 1
	for _, mult in active do
		if type(mult) == "number" and mult == mult then
			product *= math.clamp(mult, 0, 1)
		end
	end
	return product
end

-- The duel ducks for a duel view: countdown during Countdown, result during Result (§11.9).
function SoundController.duelDucks(view: { phase: any }?): { [string]: number }
	local wanted: { [string]: number } = {}
	if view then
		if view.phase == "Countdown" then
			wanted[DUCK_COUNTDOWN] = AUDIO.Ducking.countdown
		elseif view.phase == "Result" then
			wanted[DUCK_RESULT] = AUDIO.Ducking.result
		end
	end
	return wanted
end

-- Whether a new sound may play in `groupName`, and which playing voice (an index into `playing`) to stop for it.
-- Returns (true, nil) with room, (true, index) when the oldest stealable voice makes room, (false, nil) to drop it.
-- A voice is stealable when it is not looping and its priority is not above the new one. A key listed in `perKeyCap`
-- (Config.Audio.perKeyCap) is capped at that many voices in any group; any other SFX key at caps.SFXPerKey.
function SoundController.admit(
	playing: { VoiceInfo },
	groupName: string,
	key: string,
	priority: number,
	caps: Caps,
	crossfade: boolean?,
	perKeyCap: { [string]: number }?
): (boolean, number?)
	local groupCap: number
	if groupName == "Music" then
		groupCap = if crossfade then caps.MusicDuringCrossfade else caps.Music
	else
		groupCap = (caps :: any)[groupName] or caps.SFX
	end
	local override = if perKeyCap ~= nil then perKeyCap[key] else nil
	local keyCap: number? = if type(override) == "number"
		then override
		elseif groupName == "SFX" then caps.SFXPerKey
		else nil
	local inGroup, sameKey = 0, 0
	for _, voice in playing do
		if voice.group == groupName then
			inGroup += 1
			if voice.key == key then
				sameKey += 1
			end
		end
	end
	local function oldest(sameKeyOnly: boolean): number?
		local best: number? = nil
		for index, voice in playing do
			if
				voice.group == groupName
				and not voice.looped
				and voice.priority <= priority
				and (not sameKeyOnly or voice.key == key)
				and (best == nil or voice.startedAt < playing[best].startedAt)
			then
				best = index
			end
		end
		return best
	end
	if keyCap ~= nil and sameKey >= keyCap then
		local victim = oldest(true)
		return victim ~= nil, victim
	end
	if inGroup >= groupCap then
		local victim = oldest(false)
		return victim ~= nil, victim
	end
	return true, nil
end

-- The sound keys of `slots` without an id, sorted.
function SoundController.missingKeys(slots: { AssetTable.AssetSlot }): { string }
	local keys: { string } = {}
	for _, slot in slots do
		if slot.kind == "sound" and slot.id == nil then
			table.insert(keys, slot.key)
		end
	end
	table.sort(keys)
	return keys
end

-- Public: playback -----------------------------------------------------------------------------------------------------

-- Plays a one-shot. Returns true when a voice started (false: no id, cooldown, distance, caps).
function SoundController.play(key: string, options: PlayOptions?): boolean
	local voice, result = attempt(key, options or {})
	record(key, result :: PlayResult)
	return voice ~= nil
end

-- Plays a one-shot that can be stopped early. Returns stop(fadeMs?) (default Config.Audio.trackedStopFadeMs; a no-op
-- once the voice has ended), or nil when nothing started.
function SoundController.playTracked(key: string, options: PlayOptions?): ((fadeMs: number?) -> ())?
	local voice, result = attempt(key, options or {})
	record(key, result :: PlayResult)
	if voice == nil then
		return nil
	end
	local started: Voice = voice
	return function(fadeMs: number?)
		if table.find(voices, started) ~= nil and not started.stopping then
			local ms = if isFiniteNumber(fadeMs) then math.max(fadeMs :: number, 0) else AUDIO.trackedStopFadeMs
			stopVoice(started, ms)
		end
	end
end

-- Spec phase2-squeeze §3.9: a looped voice the caller drives (the knead's wax beds): the key's chosen id in its group
-- (options.group overrides), from options.timePosition, at options.volume (default 0) × the choice's volume; no
-- cooldown. nil (logged like a play) when the key has nothing to play or the group is full of voices it may not steal.
-- The handle's setVolume(v) sets choice volume × v; stop(fadeMs?) fades it out (default trackedStopFadeMs).
function SoundController.playLoop(key: string, options: PlayOptions?): Loop?
	local opts: PlayOptions = options or {}
	local slot = slotOf(key)
	if slot == nil then
		AssetTable.sound(key) -- warns once for an unknown key
		record(key, "noId")
		return nil
	end
	if not playable(key) or poolFolder == nil then
		record(key, "noId")
		return nil
	end
	local groupName = SoundController.resolveGroup(slot.group, opts.group)
	local priority = opts.priority or 0
	local live, infos = liveVoices()
	local allowed, victim = SoundController.admit(
		infos,
		groupName,
		key,
		priority,
		AUDIO.VoiceCaps :: any,
		crossfading,
		AUDIO.perKeyCap :: any
	)
	if not allowed then
		record(key, "caps")
		return nil
	end
	if victim then
		stopVoice(live[victim], AUDIO.stealFadeMs)
	end
	local choice = choiceFor(key)
	if choice == nil then
		record(key, "noId")
		return nil
	end
	local startOpts = table.clone(opts)
	startOpts.priority = priority
	local level = choice.volume
	local voice = startVoice(key, startOpts, true, level * (opts.volume or 0), choice, groupName)
	record(key, if voice then "played" else "noId")
	if voice == nil then
		return nil
	end
	local started: Voice = voice
	local loop = {} :: Loop
	function loop.setVolume(_: Loop, volume: number)
		if table.find(voices, started) ~= nil and not started.stopping and isFiniteNumber(volume) then
			started.sound.Volume = level * math.max(volume, 0)
		end
	end
	function loop.setPitch(_: Loop, pitch: number)
		if table.find(voices, started) ~= nil and not started.stopping and isFiniteNumber(pitch) then
			started.sound.PlaybackSpeed = math.clamp(pitch, AUDIO.pitchMin, AUDIO.pitchMax)
		end
	end
	function loop.stop(_: Loop, fadeMs: number?)
		if table.find(voices, started) ~= nil and not started.stopping then
			local ms = if isFiniteNumber(fadeMs) then math.max(fadeMs :: number, 0) else AUDIO.trackedStopFadeMs
			stopVoice(started, ms)
		end
	end
	return loop
end

-- Crossfades the music to `key` (nil = silence). Same key: no change.
function SoundController.setMusic(key: string?)
	if key == musicKey then
		return
	end
	musicKey = key
	musicVoice = crossfadeTo(musicVoice, key)
end

-- Crossfades the ambience loop to `key` (nil = silence). Same key: no change.
function SoundController.setAmbience(key: string?)
	if key == ambienceKey then
		return
	end
	ambienceKey = key
	ambienceVoice = crossfadeTo(ambienceVoice, key)
end

-- Applies an audio zone: its music, its ambience and its music multiplier (the "zone" duck).
function SoundController.applyZone(zone: ZoneLike?)
	local music = if zone and type(zone.musicKey) == "string" and zone.musicKey ~= "" then zone.musicKey else nil
	local ambience = if zone
			and type(zone.ambienceKey) == "string"
			and zone.ambienceKey ~= ""
		then zone.ambienceKey
		else nil
	SoundController.setMusic(music)
	SoundController.setAmbience(ambience)
	local mul = if zone and type(zone.musicMul) == "number" then zone.musicMul else nil
	if ducks[DUCK_ZONE] ~= mul then
		setDuck(DUCK_ZONE, mul)
	end
end

-- Follows a zone source (WorldBinder.currentZone and WorldBinder.ZoneChanged). Returns a function that stops it.
function SoundController.setZoneSource(
	current: () -> ZoneLike?,
	changed: { connect: (self: any, handler: (...any) -> ()) -> any }
): () -> ()
	local connection = changed:connect(function(zone: any)
		SoundController.applyZone(zone)
	end)
	SoundController.applyZone(current())
	local c = cleanup
	if c then
		c:add(connection)
	end
	return function()
		connection:disconnect()
	end
end

-- Ducks the music by `mult` (default Config.Audio.Ducking[reason]) until the returned release is called.
function SoundController.duck(reason: string, mult: number?): () -> ()
	local value = mult or (AUDIO.Ducking :: any)[reason]
	if type(value) ~= "number" then
		log:warn(`unknown duck reason {tostring(reason)}`)
		return function() end
	end
	duckSerial += 1
	local id = reason .. "#" .. tostring(duckSerial)
	setDuck(id, value)
	local released = false
	return function()
		if not released then
			released = true
			setDuck(id, nil)
		end
	end
end

-- Ducks the music by Config.Audio.Ducking[reason] for `seconds` (default Ducking[reason .. "Seconds"], e.g. the
-- knockout's 0.6 s), then releases it. Returns the release, for an early stop.
function SoundController.duckFor(reason: string, seconds: number?): () -> ()
	local length = if seconds ~= nil then seconds else (AUDIO.Ducking :: any)[reason .. DUCK_SECONDS_SUFFIX]
	if not isFiniteNumber(length) or length <= 0 then
		log:warn(`duckFor {tostring(reason)}: no length`)
		return function() end
	end
	local release = SoundController.duck(reason)
	local timer: thread? = nil
	local function stop()
		local running = timer
		if running ~= nil then
			timer = nil
			duckTimers[running] = nil
			if coroutine.running() ~= running then
				pcall(task.cancel, running)
			end
		end
		release()
	end
	local thread = task.delay(length, stop)
	timer = thread
	duckTimers[thread] = true
	return stop
end

-- Studio (§18.7): makes candidate `id` the only choice of `key` at `volume` (default the slot's volume, clamped to
-- [0, 2]); id = nil drops that key's audition. Only while Config.Debug.soundPicker; returns whether it was taken.
-- Re-auditioning the music or ambience key that is playing restarts its crossfade.
function SoundController.audition(key: string, id: number?, volume: number?): boolean
	if not SoundController.auditionAllowed(Config.Debug.soundPicker, key, id) then
		return false
	end
	if id == nil then
		auditions[key] = nil
	else
		local slot = slotOf(key) :: AssetTable.AssetSlot
		local level = if isFiniteNumber(volume) then math.clamp(volume :: number, 0, MAX_VOLUME) else slot.volume or 1
		auditions[key] = table.freeze({
			id = id,
			content = AssetTable.contentIdFor(id) :: string,
			volume = level,
		})
	end
	restartLoop(key)
	return true
end

-- Drops every audition; a music or ambience key that was auditioned and is playing crossfades back to its slot.
function SoundController.clearAuditions()
	local keys: { string } = {}
	for key in auditions do
		table.insert(keys, key)
	end
	table.sort(keys)
	table.clear(auditions)
	for _, key in keys do
		restartLoop(key)
	end
end

-- The Studio log: the last Config.Audio.recentLogSize play attempts, oldest first (copies).
function SoundController.recent(): { RecentEntry }
	local list: { RecentEntry } = {}
	for _, entry in recentLog do
		table.insert(list, table.clone(entry))
	end
	return list
end

-- True when `key` can make a sound now (an approved id, or a Studio audition).
function SoundController.hasSound(key: string): boolean
	return slotOf(key) ~= nil and playable(key)
end

-- True when any sound slot of these groups has an id (Settings: "No music yet" / "No sound effects yet"). Ignores
-- auditions.
function SoundController.hasAnyIn(groupNames: { string }): boolean
	for _, slot in AssetTable.all() do
		if slot.kind == "sound" and slot.group and table.find(groupNames, slot.group) and slot.id ~= nil then
			return true
		end
	end
	return false
end

-- The current target volume of a group (debug, tests in Play).
function SoundController.volumeOf(groupName: string): number
	return if isGroup(groupName) then targetVolume(groupName) else 0
end

-- Small table for Studio debug hooks (stuck one-shots are dropped first, so the voice counts are honest).
function SoundController.debugState(): { [string]: any }
	sweepVoices(clock())
	local perGroup: { [string]: number } = {}
	for _, voice in voices do
		perGroup[voice.group] = (perGroup[voice.group] or 0) + 1
	end
	local auditioned = 0
	for _ in auditions do
		auditioned += 1
	end
	return {
		voices = perGroup,
		music = musicKey,
		ambience = ambienceKey,
		duck = SoundController.duckProduct(ducks),
		auditions = auditioned,
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function SoundController.init()
	local c = Cleanup.new()
	cleanup = c
	for _, name in GROUP_NAMES do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = targetVolume(name)
		-- Spec phase2-squeeze §3.9: a group's bus compressor (the Wax group's: the design's wax bus).
		local spec = AUDIO.Groups[name].compressor
		if spec then
			local compressor = Instance.new("CompressorSoundEffect")
			compressor.Threshold = spec.threshold
			compressor.Ratio = spec.ratio
			compressor.Attack = spec.attack
			compressor.Release = spec.release
			compressor.GainMakeup = spec.makeup
			compressor.Parent = group
		end
		group.Parent = SoundService
		groups[name] = group
		c:add(group)
	end
	local folder = Instance.new("Folder")
	folder.Name = POOL_FOLDER
	folder.Parent = SoundService
	poolFolder = folder
	c:add(folder)

	c:add(StateController.changed("settings"):connect(function()
		applyAllVolumes()
	end))
	c:add(StateController.DuelChanged:connect(function()
		applyDuelDucks()
	end))
	c:add(function()
		for thread in duckTimers do
			pcall(task.cancel, thread)
		end
		table.clear(duckTimers)
		for _, voice in table.clone(voices) do
			removeVoice(voice)
		end
		for _, tween in groupTweens do
			tween:Cancel()
		end
		table.clear(groupTweens)
		table.clear(groups)
		table.clear(pools)
		table.clear(ducks)
		table.clear(lastPlayed)
		table.clear(lastPick)
		table.clear(auditions)
		table.clear(recentLog)
		poolFolder = nil
		musicVoice, ambienceVoice, musicKey, ambienceKey = nil, nil, nil, nil
		crossfading = false
	end)
	applyAllVolumes()
end

function SoundController.start()
	if Config.Debug.warnMissingAssets then
		for _, key in SoundController.missingKeys(AssetTable.all()) do
			log:warn(`no approved sound id for {key}: silent (DESIGN §14.2)`)
		end
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function SoundController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return SoundController
