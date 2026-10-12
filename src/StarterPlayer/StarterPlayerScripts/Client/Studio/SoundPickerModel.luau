--!strict
-- SoundPickerModel (client only, Studio only; pure: no instances, no engine calls). DESIGN §18.7.
-- The state of the Studio sound picker: the loaded keys in the §18.7 order, their candidates, the user's decisions,
-- the candidate cursor, per-candidate volumes and the undo history. SoundPicker draws it and plays the sounds.
-- It takes decoded tables in candidates.json's shape (§18.7); JSON decoding happens outside the model.
--
--   local model, problems = SoundPickerModel.fromData(data)   -- problems: unknown keys, bad ids, bad decisions
--   model:progress() -> done, total           approved and skipped (optional keys only) count; needsMore does not
--   model:currentKey() -> key?                the key whose variant flow is open, else the first key without a decision
--   model:currentCandidate() -> candidate?, index, count
--   model:nextCandidate() / prevCandidate()   move the cursor (wraps); candidates already picked for the key are hidden
--   model:volume() / volumeStep(steps)        the current candidate's volume, 0.1-1.5 in steps of 0.1
--   model:approve(key, id, volume)            the first pick; a key that wants variants then stays current
--   model:addVariant(key, id, volume)         another pick while the variant flow is open ("Pick another")
--   model:enough(key)                         closes the variant flow ("That's enough")
--   model:skip(key)                           optional keys only
--   model:needsMore(key, reason)              reason: one of REASONS; the next round searches again
--   model:undo() -> key?                      reverts the last decision change of this session
--   model:export() -> { version, builtAt, keys, decisions }
--   model:view() -> everything the panel shows
--   SoundPickerModel.storyboard(key, seconds?)   the sound-only "Try it in the game" timeline of a storyboard key
--   SoundPickerModel.progressText / sectionText / soundLine / variantText / tabText / volumeText / clockText /
--     lengthText / loopRole                      the panel's texts
--   SoundPickerModel.jsonExport(export) / jsonDecision(key, decision?)   copies with ids as digit strings (export
--                                                 command, Output backup line)
--
-- Only candidates whose `preload` is "Success" are kept (§18.7 step 4). Which keys may be skipped comes from
-- AssetTable's `optional` flag, never from the data (the data can't make a required key skippable).
-- Reading (§18.7 "the next round searches again"): a needsMore decision remembers the candidates.json `builtAt` it was
-- made in (`round`). A load with the same builtAt (Play restarted mid-round) keeps it, so the panel resumes after it; a
-- load from a newer round drops it, so that key is to do again with its new candidates.
-- The key lists below are Studio-only developer data (not player-facing text, §18.7 reading of §0.3 #6).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)

-- Types

export type Status = "approved" | "skipped" | "needsMore"
-- How "Try it in the game" plays a key (SoundPicker's runners).
export type Runner =
	"squeeze"
	| "pop"
	| "toast"
	| "button"
	| "screen"
	| "plain"
	| "target"
	| "backstop"
	| "ahead"
	| "storyboard"
	| "loop"

export type Pick = { id: number, volume: number }

export type Decision = {
	status: Status,
	picks: { Pick }?, -- approved: the main id first, then the variants
	reason: string?, -- needsMore: one of REASONS' codes
	round: string?, -- needsMore: the builtAt of the candidates it was made against
}

export type Candidate = {
	id: number,
	name: string,
	creator: string,
	seconds: number?,
	partner: boolean,
	publicDomain: boolean,
	query: string,
}

export type Entry = {
	key: string,
	section: number,
	runner: Runner,
	label: string,
	when: string,
	hint: string,
	group: string,
	spatial: boolean,
	optional: boolean,
	variantsWanted: number,
	defaultVolume: number,
	candidates: { Candidate },
}

export type Export = {
	version: number,
	builtAt: string,
	keys: { string },
	decisions: { [string]: Decision },
}

export type Cue = {
	at: number, -- seconds from the start
	kind: "play" | "duck" | "unduck",
	key: string?, -- play
	pitch: number?, -- play
	reason: string?, -- duck: a Config.Audio.Ducking reason
}

-- JSON-safe copies (jsonDecision / jsonExport): ids as digit strings, so no JSON tool rounds or reformats a big id.
export type JsonPick = { id: string, volume: number }
export type JsonDecision = {
	status: string, -- approved | skipped | needsMore; jsonDecision also uses "todo" (no decision, e.g. after an undo)
	picks: { JsonPick }?,
	reason: string?,
	round: string?,
}
export type JsonExport = {
	version: number,
	builtAt: string,
	keys: { string },
	decisions: { [string]: JsonDecision },
}

export type View = {
	finished: boolean,
	done: number,
	total: number,
	key: string?,
	section: number,
	sectionCount: number,
	sectionName: string,
	label: string,
	when: string,
	hint: string,
	runner: Runner?,
	candidate: Candidate?,
	index: number,
	count: number,
	volume: number,
	optional: boolean,
	variantsWanted: number,
	picked: number,
	picking: boolean, -- the variant flow of this key is open
	canUndo: boolean,
}

type Undo = {
	key: string,
	decision: Decision?,
	variantKey: string?,
	cursor: number,
}

type ModelData = {
	builtAt: string,
	entries: { Entry },
	byKey: { [string]: Entry },
	decisions: { [string]: Decision },
	volumes: { [string]: number }, -- "<key>#<id>" -> volume
	cursorKey: string?,
	cursor: number,
	variantKey: string?,
	history: { Undo },
	problems: { string },
}

-- Constants

local VERSION = 1
local SUCCESS = "Success"
local VOLUME_MIN = 0.1
local VOLUME_MAX = 1.5
local VOLUME_STEP = 0.1
local GRID_EPSILON = 1e-6
local MAX_VARIANTS = 5 -- reading: §14.2 asks for at most 3; a little slack, never unbounded
local MAX_HISTORY = 200
local MAX_EXACT_ID = 2 ^ 53

-- The 7 sections in the §18.7 order (5 + 7 + 6 + 5 + 4 + 6 + 4 = 37 keys), then spec phase 5's moves (10 keys), each
-- key with its "Try it" runner (the moves play as they will in the game: "plain").
local SECTIONS: { { name: string, keys: { { key: string, runner: Runner } } } } = {
	{
		name = "Squeezing",
		keys = {
			{ key = "sfx.squish", runner = "squeeze" },
			{ key = "sfx.squeezeRelease", runner = "squeeze" },
			{ key = "sfx.pop", runner = "pop" },
			{ key = "ui.coin", runner = "storyboard" },
			{ key = "ui.gripUnlock", runner = "toast" },
		},
	},
	{
		name = "Buttons",
		keys = {
			{ key = "ui.click", runner = "button" },
			{ key = "ui.hover", runner = "button" },
			{ key = "ui.back", runner = "screen" },
			{ key = "ui.open", runner = "screen" },
			{ key = "ui.error", runner = "button" },
			{ key = "ui.toast", runner = "toast" },
			{ key = "ui.purchase", runner = "plain" },
		},
	},
	{
		name = "Throws and hits",
		keys = {
			{ key = "sfx.throw", runner = "target" },
			{ key = "sfx.impactBoing", runner = "target" },
			{ key = "sfx.impactSoft", runner = "backstop" },
			{ key = "sfx.jellyWobble", runner = "backstop" },
			{ key = "ui.hitConfirm", runner = "target" },
			{ key = "sfx.elimination", runner = "ahead" },
		},
	},
	{
		name = "Duel moments",
		keys = {
			{ key = "duel.countdownTick", runner = "storyboard" },
			{ key = "duel.go", runner = "storyboard" },
			{ key = "duel.win", runner = "storyboard" },
			{ key = "duel.lose", runner = "storyboard" },
			{ key = "duel.draw", runner = "storyboard" },
		},
	},
	{
		name = "Dragon",
		keys = {
			{ key = "sfx.dragonTelegraph", runner = "storyboard" },
			{ key = "sfx.throwDragon", runner = "storyboard" },
			{ key = "sfx.dragonChomp", runner = "storyboard" },
			{ key = "sfx.dragonRoar", runner = "storyboard" },
		},
	},
	{
		name = "Gift boxes",
		keys = {
			{ key = "box.shake", runner = "storyboard" },
			{ key = "box.open", runner = "storyboard" },
			{ key = "reveal.common", runner = "storyboard" },
			{ key = "reveal.uncommon", runner = "storyboard" },
			{ key = "reveal.epic", runner = "storyboard" },
			{ key = "reveal.exclusive", runner = "storyboard" },
		},
	},
	{
		name = "Music and room sound",
		keys = {
			{ key = "music.lobby", runner = "loop" },
			{ key = "music.duel", runner = "loop" },
			{ key = "amb.lobby", runner = "loop" },
			{ key = "amb.arena", runner = "loop" },
		},
	},
	{
		name = "Dash and Epic ultimates",
		keys = {
			{ key = "sfx.dash", runner = "plain" },
			{ key = "sfx.dashPlant", runner = "plain" },
			{ key = "sfx.ultCharge.bird", runner = "plain" },
			{ key = "sfx.ultCharge.donut", runner = "plain" },
			{ key = "sfx.ultCharge.cloud_bunny", runner = "plain" },
			{ key = "sfx.ultCharge.cupcake_axolotl", runner = "plain" },
			{ key = "sfx.ultRelease", runner = "plain" },
			{ key = "sfx.ultRainDrop", runner = "plain" },
			{ key = "sfx.ultCloudHover", runner = "plain" },
			{ key = "sfx.ultBubblePop", runner = "plain" },
		},
	},
}

-- "None of these fit" reason chips (§18.7): stored code and the chip text.
local REASONS: { { code: string, text: string } } = {
	{ code = "tooLoud", text = "too loud" },
	{ code = "tooLong", text = "too long" },
	{ code = "notSquishy", text = "not squishy" },
	{ code = "wrongVibe", text = "wrong vibe" },
}

-- Storyboard timings (§18.7 "Try it in the game"), from the configs that drive the real moments.
local COUNTDOWN_PITCH = Config.Audio.countdownPitch
local COUNTDOWN_STEP_SECONDS = 1 -- 3-2-1 a second apart, then "Throw!"
local COUNTDOWN_TAIL_SECONDS = 1 -- reading: the countdown duck ends a second after "Throw!"
local JINGLE_DEFAULT_SECONDS = 4 -- §14.2: result jingles are 1-4 s
local JINGLE_MIN_SECONDS = 1
local JINGLE_MAX_SECONDS = 6
local JINGLE_TAIL_SECONDS = 0.5 -- reading: the result duck ends half a second after the jingle
local COIN_TICKS = 5 -- coin plays 5 ticks over 0.4 s so the batching can be heard
local COIN_SPAN_SECONDS = 0.4
local DRAGON = Config.Abilities.dragon_rush
local BOX = Config.Anim.boxReveal
local REVEAL_TAIL_SECONDS = 2.5 -- §14.2: reveals are 0.5-2.5 s; the box duck ends after the longest
local REVEAL_FALLBACK = "reveal.common" -- the reveal heard when a box key is auditioned
local TODO = "todo" -- jsonDecision's status for a key with no decision
local SECONDS_PER_MINUTE = 60
-- What a looping key plays as (the panel: "Playing as the lobby music: walk around · 0:23").
local LOOP_ROLES: { [string]: string } = {
	["music.lobby"] = "the lobby music",
	["music.duel"] = "the duel music",
	["amb.lobby"] = "the lobby room sound",
	["amb.arena"] = "the arena room sound",
}

-- Module table

local SoundPickerModel = {}

local ModelClass = {}
ModelClass.__index = ModelClass

export type Model = typeof(setmetatable({} :: ModelData, ModelClass))

-- Lookup tables (built once from SECTIONS; pure data).
local ORDER: { string } = {}
local INFO: { [string]: { index: number, section: number, runner: Runner } } = {}
local REASON_CODES: { [string]: boolean } = {}
for sectionIndex, section in SECTIONS do
	for _, item in section.keys do
		table.insert(ORDER, item.key)
		INFO[item.key] = { index = #ORDER, section = sectionIndex, runner = item.runner }
	end
end
for _, reason in REASONS do
	REASON_CODES[reason.code] = true
end

SoundPickerModel.VERSION = VERSION
SoundPickerModel.VOLUME_MIN = VOLUME_MIN
SoundPickerModel.VOLUME_MAX = VOLUME_MAX
SoundPickerModel.ORDER = table.freeze(table.clone(ORDER))
SoundPickerModel.REASONS = table.freeze(REASONS)
SoundPickerModel.SECTION_COUNT = #SECTIONS

-- Private: values -------------------------------------------------------------------------------------------------------

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A positive whole asset id (numbers, or digit strings as some JSON tools write big ids), else nil.
local function toId(value: unknown): number?
	local n: unknown = value
	if type(value) == "string" and string.match(value, "^%d+$") then
		n = tonumber(value)
	end
	if not isFinite(n) then
		return nil
	end
	local id = n :: number
	if id < 1 or id > MAX_EXACT_ID or math.floor(id) ~= id then
		return nil
	end
	return id
end

local function text(value: unknown, fallback: string): string
	return if type(value) == "string" then value else fallback
end

local function copyDecision(decision: Decision?): Decision?
	if decision == nil then
		return nil
	end
	local picks: { Pick }? = nil
	local source = decision.picks
	if source then
		local list: { Pick } = {}
		for _, pick in source do
			table.insert(list, { id = pick.id, volume = pick.volume })
		end
		picks = list
	end
	return { status = decision.status, picks = picks, reason = decision.reason, round = decision.round }
end

local function slotOf(key: string): AssetTable.AssetSlot?
	for _, slot in AssetTable.all() do
		if slot.kind == "sound" and slot.key == key then
			return slot
		end
	end
	return nil
end

-- Private: parsing --------------------------------------------------------------------------------------------------------

local function parseCandidates(key: string, raw: unknown, problems: { string }): { Candidate }
	local list: { Candidate } = {}
	if raw == nil then
		return list
	end
	if type(raw) ~= "table" then
		table.insert(problems, `{key}: candidates is not a list`)
		return list
	end
	local seen: { [number]: boolean } = {}
	for _, item in raw :: { any } do
		if type(item) ~= "table" or item.preload ~= SUCCESS then
			continue -- only candidates that loaded in a Play client show (§18.7 step 4)
		end
		local id = toId(item.id)
		if id == nil then
			table.insert(problems, `{key}: a candidate has a bad id`)
			continue
		end
		if seen[id] then
			continue
		end
		seen[id] = true
		table.insert(list, {
			id = id,
			name = text(item.name, ""),
			creator = text(item.creator, ""),
			seconds = if isFinite(item.seconds) and item.seconds > 0 then item.seconds else nil,
			partner = item.partner == true,
			publicDomain = item.publicDomain == true,
			query = text(item.query, ""),
		})
	end
	return list
end

local function parseEntry(raw: any, problems: { string }): Entry?
	if type(raw) ~= "table" or type(raw.key) ~= "string" then
		table.insert(problems, "a key entry has no key")
		return nil
	end
	local key: string = raw.key
	local info = INFO[key]
	local slot = slotOf(key)
	if info == nil or slot == nil then
		table.insert(problems, `unknown key {key}`)
		return nil
	end
	local wanted = if isFinite(raw.variantsWanted) then math.floor(raw.variantsWanted) else 1
	local volume = if isFinite(raw.defaultVolume) then raw.defaultVolume else slot.volume or 1
	local group: string = slot.group or "SFX"
	return {
		key = key,
		section = info.section,
		runner = info.runner,
		label = text(raw.label, key),
		when = text(raw.when, ""),
		hint = text(raw.hint, ""),
		group = group,
		spatial = slot.spatial == true,
		optional = slot.optional == true,
		variantsWanted = math.clamp(wanted, 1, MAX_VARIANTS),
		defaultVolume = SoundPickerModel.clampVolume(volume),
		candidates = parseCandidates(key, raw.candidates, problems),
	}
end

-- A decision from the data, checked; nil (with a problem when it is malformed) when it can't be used.
local function parseDecision(entry: Entry, raw: any, builtAt: string, problems: { string }): Decision?
	if type(raw) ~= "table" then
		table.insert(problems, `{entry.key}: a decision is not a table`)
		return nil
	end
	local status = raw.status
	if status == "approved" then
		local picks: { Pick } = {}
		local seen: { [number]: boolean } = {}
		if type(raw.picks) == "table" then
			for _, pick in raw.picks :: { any } do
				local id = if type(pick) == "table" then toId(pick.id) else nil
				if id == nil or seen[id] then
					table.insert(problems, `{entry.key}: an approved pick has a bad or repeated id`)
					return nil
				end
				seen[id] = true
				local volume = if isFinite(pick.volume) then pick.volume else entry.defaultVolume
				table.insert(picks, { id = id, volume = SoundPickerModel.clampVolume(volume) })
			end
		end
		if #picks == 0 then
			table.insert(problems, `{entry.key}: an approved decision has no picks`)
			return nil
		end
		return { status = "approved", picks = picks }
	elseif status == "skipped" then
		if not entry.optional then
			table.insert(problems, `{entry.key}: only optional keys can be skipped`)
			return nil
		end
		return { status = "skipped" }
	elseif status == "needsMore" then
		if type(raw.reason) ~= "string" or not REASON_CODES[raw.reason] then
			table.insert(problems, `{entry.key}: a needsMore decision has no known reason`)
			return nil
		end
		local round = text(raw.round, "")
		if round ~= builtAt then
			return nil -- an earlier round asked for more; this round's candidates are new, so it is to do again
		end
		return { status = "needsMore", reason = raw.reason, round = round }
	end
	table.insert(problems, `{entry.key}: unknown decision status {tostring(status)}`)
	return nil
end

-- Private: model helpers ------------------------------------------------------------------------------------------------

local function volumeKey(key: string, id: number): string
	return key .. "#" .. string.format("%d", id)
end

local function hasCandidate(entry: Entry, id: number): boolean
	for _, candidate in entry.candidates do
		if candidate.id == id then
			return true
		end
	end
	return false
end

local function pickedIds(self: Model, key: string): { [number]: boolean }
	local set: { [number]: boolean } = {}
	local decision = self.decisions[key]
	local picks = decision and decision.picks
	if picks then
		for _, pick in picks do
			set[pick.id] = true
		end
	end
	return set
end

-- The candidates the cursor moves over: every candidate, minus the ones already picked while the variant flow is open.
local function available(self: Model, entry: Entry): { Candidate }
	if self.variantKey ~= entry.key then
		return entry.candidates
	end
	local picked = pickedIds(self, entry.key)
	local list: { Candidate } = {}
	for _, candidate in entry.candidates do
		if not picked[candidate.id] then
			table.insert(list, candidate)
		end
	end
	return list
end

-- The key whose variant flow is open, else the first key (in order) with no decision; nil when every key is decided.
local function openKey(self: Model): string?
	if self.variantKey ~= nil then
		return self.variantKey
	end
	for _, entry in self.entries do
		if self.decisions[entry.key] == nil then
			return entry.key
		end
	end
	return nil
end

local function currentEntry(self: Model): Entry?
	local key = openKey(self)
	return if key then self.byKey[key] else nil
end

-- Keeps the cursor on the current key: back to the first candidate when the key changed, clamped otherwise.
local function syncCursor(self: Model)
	local entry = currentEntry(self)
	local key = if entry then entry.key else nil
	if key ~= self.cursorKey then
		self.cursorKey = key
		self.cursor = 1
	end
	local count = if entry then #available(self, entry) else 0
	if self.cursor > count then
		self.cursor = 1
	end
	if self.cursor < 1 then
		self.cursor = 1
	end
end

local function pushUndo(self: Model, key: string)
	table.insert(self.history, {
		key = key,
		decision = copyDecision(self.decisions[key]),
		variantKey = self.variantKey,
		cursor = self.cursor,
	})
	if #self.history > MAX_HISTORY then
		table.remove(self.history, 1)
	end
end

-- The common checks before a new decision on `key`. Returns the entry, or nil and a reason.
local function decidable(self: Model, key: string): (Entry?, string?)
	local entry = self.byKey[key]
	if entry == nil then
		return nil, "unknown key"
	end
	if self.variantKey ~= nil then
		return nil, `finish picking variants for {self.variantKey} first`
	end
	if self.decisions[key] ~= nil then
		return nil, "already decided"
	end
	return entry, nil
end

local function stepCursor(self: Model, delta: number): Candidate?
	syncCursor(self)
	local entry = currentEntry(self)
	if entry == nil then
		return nil
	end
	local list = available(self, entry)
	if #list == 0 then
		return nil
	end
	self.cursor = ((self.cursor - 1 + delta) % #list) + 1
	return list[self.cursor]
end

-- Public: pure helpers ----------------------------------------------------------------------------------------------------

-- A volume clamped to [0.1, 1.5]; a non-number gives 1.
function SoundPickerModel.clampVolume(volume: unknown): number
	if not isFinite(volume) then
		return 1
	end
	return math.clamp(volume :: number, VOLUME_MIN, VOLUME_MAX)
end

-- `steps` steps of 0.1 from `volume` on the 0.1 grid (0.35 + 1 step = 0.4), clamped to [0.1, 1.5].
function SoundPickerModel.stepVolume(volume: number, steps: number): number
	local tenths = SoundPickerModel.clampVolume(volume) / VOLUME_STEP
	local target: number
	if steps > 0 then
		target = math.floor(tenths + GRID_EPSILON) + math.floor(steps)
	elseif steps < 0 then
		target = math.ceil(tenths - GRID_EPSILON) - math.floor(-steps)
	else
		return SoundPickerModel.clampVolume(volume)
	end
	return math.clamp(target / 10, VOLUME_MIN, VOLUME_MAX)
end

-- The section (1-8) and runner of a key, or nil for a key outside the 47.
function SoundPickerModel.infoOf(key: string): (number?, Runner?)
	local info = INFO[key]
	if info == nil then
		return nil, nil
	end
	return info.section, info.runner
end

function SoundPickerModel.sectionName(section: number): string
	local entry = SECTIONS[section]
	return if entry then entry.name else ""
end

-- The sound-only storyboard of a key (§18.7 "Try it in the game"), in time order, or nil when its runner is not
-- "storyboard". `seconds` is the auditioned candidate's length (the result jingles' duck follows it).
function SoundPickerModel.storyboard(key: string, seconds: number?): { Cue }?
	local info = INFO[key]
	if info == nil or info.runner ~= "storyboard" then
		return nil
	end
	local cues: { Cue } = {}
	local function play(at: number, playKey: string, pitch: number?)
		table.insert(cues, { at = at, kind = "play", key = playKey, pitch = pitch })
	end
	local function duck(at: number, reason: string)
		table.insert(cues, { at = at, kind = "duck", reason = reason })
	end
	local function unduck(at: number)
		table.insert(cues, { at = at, kind = "unduck" })
	end
	local section = SECTIONS[info.section].name
	if key == "ui.coin" then
		for i = 0, COIN_TICKS - 1 do
			play(i * COIN_SPAN_SECONDS / (COIN_TICKS - 1), key)
		end
	elseif key == "duel.countdownTick" or key == "duel.go" then
		duck(0, "countdown")
		for i, pitch in COUNTDOWN_PITCH do
			play((i - 1) * COUNTDOWN_STEP_SECONDS, "duel.countdownTick", pitch)
		end
		local goAt = #COUNTDOWN_PITCH * COUNTDOWN_STEP_SECONDS
		play(goAt, "duel.go")
		unduck(goAt + COUNTDOWN_TAIL_SECONDS)
	elseif section == "Duel moments" then
		local length = if seconds and isFinite(seconds) then seconds else JINGLE_DEFAULT_SECONDS
		duck(0, "result")
		play(0, key)
		unduck(math.clamp(length, JINGLE_MIN_SECONDS, JINGLE_MAX_SECONDS) + JINGLE_TAIL_SECONDS)
	elseif section == "Dragon" then
		local telegraph = DRAGON.telegraphSeconds
		-- Reading: "chomp at length / 260 s" with the longest lane (maxLength studs at speed studs/s).
		local travel = DRAGON.maxLength / DRAGON.speed
		duck(0, "telegraph")
		play(0, "sfx.dragonTelegraph")
		play(0, "sfx.dragonRoar")
		unduck(telegraph)
		play(telegraph, "sfx.throwDragon")
		play(telegraph + travel, "sfx.dragonChomp")
	else -- Gift boxes: wobbles across the anticipation, the lid pop, then the reveal (§9.11 timings)
		local wobbles = math.max(BOX.anticipationWobbles, 1)
		local openAt = BOX.anticipationEndMs / 1000
		local revealAt = BOX.popEndMs / 1000
		duck(0, "boxReveal")
		for i = 0, wobbles - 1 do
			play(i * openAt / wobbles, "box.shake")
		end
		play(openAt, "box.open")
		play(revealAt, if string.sub(key, 1, 7) == "reveal." then key else REVEAL_FALLBACK)
		unduck(revealAt + REVEAL_TAIL_SECONDS)
	end
	table.sort(cues, function(a: Cue, b: Cue): boolean
		return a.at < b.at
	end)
	return cues
end

-- Public: panel texts (Studio-only developer text, §18.7) ------------------------------------------------------------

-- "7 of 37 done"
function SoundPickerModel.progressText(done: number, total: number): string
	return `{done} of {total} done`
end

-- "Part 1 of 7: Squeezing"
function SoundPickerModel.sectionText(section: number): string
	return `Part {section} of {#SECTIONS}: {SoundPickerModel.sectionName(section)}`
end

-- "0:23" (whole seconds, never negative)
function SoundPickerModel.clockText(seconds: number): string
	local whole = if isFinite(seconds) then math.max(math.floor(seconds), 0) else 0
	return string.format("%d:%02d", whole // SECONDS_PER_MINUTE, whole % SECONDS_PER_MINUTE)
end

-- A sound's length: "0.3 s" under a minute, "1:23" from a minute on; "" when unknown.
function SoundPickerModel.lengthText(seconds: number?): string
	if seconds == nil or not isFinite(seconds) or seconds <= 0 then
		return ""
	end
	if seconds < SECONDS_PER_MINUTE then
		return string.format("%.1f s", seconds)
	end
	return SoundPickerModel.clockText(seconds)
end

-- "Sound 2 of 6 · 0.3 s" ("Sound 2 of 6" when the length is unknown).
function SoundPickerModel.soundLine(index: number, count: number, seconds: number?): string
	local length = SoundPickerModel.lengthText(seconds)
	local line = `Sound {index} of {count}`
	return if length == "" then line else `{line} · {length}`
end

-- "Picked 1 of 3 for variety"
function SoundPickerModel.variantText(picked: number, wanted: number): string
	return `Picked {picked} of {wanted} for variety`
end

-- The hidden panel's tab: "Sound picker 7/37"
function SoundPickerModel.tabText(done: number, total: number): string
	return `Sound picker {done}/{total}`
end

-- "80%"
function SoundPickerModel.volumeText(volume: number): string
	return `{math.floor(SoundPickerModel.clampVolume(volume) * 100 + 0.5)}%`
end

-- What a music or ambience key plays as ("the lobby music"), or nil for a one-shot key.
function SoundPickerModel.loopRole(key: string): string?
	return LOOP_ROLES[key]
end

-- Public: JSON-safe copies ------------------------------------------------------------------------------------------------

local function jsonOf(decision: Decision?): JsonDecision
	if decision == nil then
		return { status = TODO }
	end
	local picks: { JsonPick }? = nil
	local source = decision.picks
	if source then
		local list: { JsonPick } = {}
		for _, pick in source do
			table.insert(list, { id = string.format("%d", pick.id), volume = pick.volume })
		end
		picks = list
	end
	return { status = decision.status, picks = picks, reason = decision.reason, round = decision.round }
end

-- One key's decision for the Output backup line ("[SD][SoundPicker] decision {json}"); status "todo" when it has none.
function SoundPickerModel.jsonDecision(key: string, decision: Decision?): JsonDecision & { key: string }
	local copy = jsonOf(decision)
	return {
		key = key,
		status = copy.status,
		picks = copy.picks,
		reason = copy.reason,
		round = copy.round,
	}
end

-- An export with every id as a digit string (fromData reads those back as numbers).
function SoundPickerModel.jsonExport(export: Export): JsonExport
	local decisions: { [string]: JsonDecision } = {}
	for key, decision in export.decisions do
		decisions[key] = jsonOf(decision)
	end
	return { version = export.version, builtAt = export.builtAt, keys = table.clone(export.keys), decisions = decisions }
end

-- Public: construction ------------------------------------------------------------------------------------------------

-- A model from decoded candidates.json data (§18.7). Returns the model and the problems found (unknown keys, bad ids,
-- malformed decisions); the bad parts are left out, the rest loads.
function SoundPickerModel.fromData(data: unknown): (Model, { string })
	local problems: { string } = {}
	local self: ModelData = {
		builtAt = "",
		entries = {},
		byKey = {},
		decisions = {},
		volumes = {},
		cursorKey = nil,
		cursor = 1,
		variantKey = nil,
		history = {},
		problems = problems,
	}
	local model = setmetatable(self, ModelClass)
	if type(data) ~= "table" then
		table.insert(problems, "the picker data is not a table")
		return model, problems
	end
	local raw = data :: any
	if raw.version ~= nil and raw.version ~= VERSION then
		table.insert(problems, `unsupported data version {tostring(raw.version)}`)
		return model, problems
	end
	self.builtAt = text(raw.builtAt, "")
	if type(raw.keys) == "table" then
		for _, item in raw.keys :: { any } do
			local entry = parseEntry(item, problems)
			if entry == nil then
				continue
			end
			if self.byKey[entry.key] then
				table.insert(problems, `{entry.key}: listed twice (the first one is kept)`)
				continue
			end
			self.byKey[entry.key] = entry
			table.insert(self.entries, entry)
		end
	else
		table.insert(problems, "the picker data has no keys list")
	end
	table.sort(self.entries, function(a: Entry, b: Entry): boolean
		return INFO[a.key].index < INFO[b.key].index
	end)
	if type(raw.decisions) == "table" then
		for key, decision in raw.decisions :: { [any]: any } do
			if type(key) ~= "string" or INFO[key] == nil then
				table.insert(problems, `a decision for unknown key {tostring(key)}`)
				continue
			end
			local entry = self.byKey[key]
			if entry == nil then
				continue -- a decision for a key this load does not carry (it stays in decisions.json)
			end
			local parsed = parseDecision(entry, decision, self.builtAt, problems)
			if parsed then
				self.decisions[key] = parsed
			end
		end
	end
	syncCursor(model)
	return model, problems
end

-- Public: model -----------------------------------------------------------------------------------------------------------

-- Done (approved, or skipped on an optional key) and the number of loaded keys.
function ModelClass.progress(self: Model): (number, number)
	local done = 0
	for _, entry in self.entries do
		local decision = self.decisions[entry.key]
		if decision and (decision.status == "approved" or decision.status == "skipped") then
			done += 1
		end
	end
	return done, #self.entries
end

-- The key on screen: the one whose variant flow is open, else the first key (in order) with no decision; nil = finished.
function ModelClass.currentKey(self: Model): string?
	return openKey(self)
end

function ModelClass.entry(self: Model, key: string): Entry?
	return self.byKey[key]
end

function ModelClass.decision(self: Model, key: string): Decision?
	return copyDecision(self.decisions[key])
end

-- The candidate under the cursor, its 1-based index and how many the cursor moves over.
function ModelClass.currentCandidate(self: Model): (Candidate?, number, number)
	syncCursor(self)
	local entry = currentEntry(self)
	if entry == nil then
		return nil, 0, 0
	end
	local list = available(self, entry)
	if #list == 0 then
		return nil, 0, 0
	end
	return list[self.cursor], self.cursor, #list
end

function ModelClass.nextCandidate(self: Model): Candidate?
	return stepCursor(self, 1)
end

function ModelClass.prevCandidate(self: Model): Candidate?
	return stepCursor(self, -1)
end

-- The current candidate's volume (its own once changed, else the key's default).
function ModelClass.volume(self: Model): number
	local candidate = self:currentCandidate()
	local entry = currentEntry(self)
	if candidate == nil or entry == nil then
		return if entry then entry.defaultVolume else 1
	end
	return self.volumes[volumeKey(entry.key, candidate.id)] or entry.defaultVolume
end

-- Moves the current candidate's volume by `steps` steps of 0.1 (clamped to [0.1, 1.5]) and returns it.
function ModelClass.volumeStep(self: Model, steps: number): number
	local candidate = self:currentCandidate()
	local entry = currentEntry(self)
	local volume = SoundPickerModel.stepVolume(self:volume(), steps)
	if candidate and entry then
		self.volumes[volumeKey(entry.key, candidate.id)] = volume
	end
	return volume
end

-- The first pick of `key`. A key that wants variants stays current ("Picked 1 of 3 for variety") until it has them all
-- or enough() is called.
function ModelClass.approve(self: Model, key: string, id: number, volume: number): (boolean, string?)
	local entry, reason = decidable(self, key)
	if entry == nil then
		return false, reason
	end
	if not hasCandidate(entry, id) then
		return false, "not a candidate of this key"
	end
	pushUndo(self, key)
	self.decisions[key] = {
		status = "approved",
		picks = { { id = id, volume = SoundPickerModel.clampVolume(volume) } },
	}
	if entry.variantsWanted > 1 and #entry.candidates > 1 then
		self.variantKey = key
	end
	syncCursor(self)
	return true, nil
end

-- Another pick while the variant flow of `key` is open. The flow closes when the key has all its variants or no
-- unpicked candidate is left.
function ModelClass.addVariant(self: Model, key: string, id: number, volume: number): (boolean, string?)
	local entry = self.byKey[key]
	local decision = self.decisions[key]
	if entry == nil or decision == nil or decision.picks == nil or self.variantKey ~= key then
		return false, "not picking variants for this key"
	end
	if not hasCandidate(entry, id) then
		return false, "not a candidate of this key"
	end
	if pickedIds(self, key)[id] then
		return false, "already picked"
	end
	pushUndo(self, key)
	local updated = copyDecision(decision) :: Decision
	local picks = updated.picks :: { Pick }
	table.insert(picks, { id = id, volume = SoundPickerModel.clampVolume(volume) })
	self.decisions[key] = updated
	if #picks >= entry.variantsWanted or #available(self, entry) == 0 then
		self.variantKey = nil
	end
	syncCursor(self)
	return true, nil
end

-- "That's enough": closes the variant flow of `key` with the picks it has.
function ModelClass.enough(self: Model, key: string): (boolean, string?)
	if self.variantKey ~= key then
		return false, "not picking variants for this key"
	end
	pushUndo(self, key)
	self.variantKey = nil
	syncCursor(self)
	return true, nil
end

-- Skips an optional key (counts as done; the game stays silent there).
function ModelClass.skip(self: Model, key: string): (boolean, string?)
	local entry, reason = decidable(self, key)
	if entry == nil then
		return false, reason
	end
	if not entry.optional then
		return false, "only optional keys can be skipped"
	end
	pushUndo(self, key)
	self.decisions[key] = { status = "skipped" }
	syncCursor(self)
	return true, nil
end

-- "None of these fit": the next round searches again (does not count as done).
function ModelClass.needsMore(self: Model, key: string, reason: string): (boolean, string?)
	local entry, why = decidable(self, key)
	if entry == nil then
		return false, why
	end
	if not REASON_CODES[reason] then
		return false, "unknown reason"
	end
	pushUndo(self, key)
	self.decisions[key] = { status = "needsMore", reason = reason, round = self.builtAt }
	syncCursor(self)
	return true, nil
end

-- Reverts the last decision change of this session. Returns the key it touched, or nil when there is nothing to undo.
function ModelClass.undo(self: Model): string?
	local last = table.remove(self.history)
	if last == nil then
		return nil
	end
	local restored = copyDecision(last.decision)
	if restored then
		self.decisions[last.key] = restored
	else
		self.decisions[last.key] = nil
	end
	self.variantKey = last.variantKey
	if openKey(self) == last.key then
		self.cursorKey = last.key
		self.cursor = last.cursor
	end
	syncCursor(self)
	return last.key
end

function ModelClass.canUndo(self: Model): boolean
	return #self.history > 0
end

-- The loaded keys and their decisions (copies), for decisions.json (§18.7 step 8). A loaded key missing from
-- `decisions` is still to do.
function ModelClass.export(self: Model): Export
	local keys: { string } = {}
	local decisions: { [string]: Decision } = {}
	for _, entry in self.entries do
		table.insert(keys, entry.key)
		local decision = copyDecision(self.decisions[entry.key])
		if decision then
			decisions[entry.key] = decision
		end
	end
	return { version = VERSION, builtAt = self.builtAt, keys = keys, decisions = decisions }
end

function ModelClass.problemList(self: Model): { string }
	return table.clone(self.problems)
end

-- Everything the panel shows for the current state.
function ModelClass.view(self: Model): View
	local done, total = self:progress()
	local entry = currentEntry(self)
	local candidate, index, count = self:currentCandidate()
	local decision = if entry then self.decisions[entry.key] else nil
	local picks = decision and decision.picks
	return {
		finished = entry == nil,
		done = done,
		total = total,
		key = if entry then entry.key else nil,
		section = if entry then entry.section else 0,
		sectionCount = #SECTIONS,
		sectionName = if entry then SoundPickerModel.sectionName(entry.section) else "",
		label = if entry then entry.label else "",
		when = if entry then entry.when else "",
		hint = if entry then entry.hint else "",
		runner = if entry then entry.runner else nil,
		candidate = candidate,
		index = index,
		count = count,
		volume = self:volume(),
		optional = if entry then entry.optional else false,
		variantsWanted = if entry then entry.variantsWanted else 1,
		picked = if picks then #picks else 0,
		picking = entry ~= nil and self.variantKey == entry.key,
		canUndo = #self.history > 0,
	}
end

return table.freeze(SoundPickerModel)
