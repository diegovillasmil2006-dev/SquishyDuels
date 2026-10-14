--!strict
-- Remotes: the one client/server remote contract (DESIGN §2.7, §2.8, §17.10). Shared.
-- `SPEC` and `names` are pure data; `createServer` is server only (NetService.init); `waitClientAsync` is for the
-- client (NetController.connectAsync). The folder lives at ReplicatedStorage.SD_Remotes, outside `Shared`, because
-- Rojo `$path` nodes delete unknown children. Per-remote rate limits live in Config.Net, keyed by the same names.
-- Grip (§17.2 rule 5, §17.9 #1): there is no Grip remote. Grip comes only from an accepted SqueezeRequest and from the
-- server's own capsule ticks; the client never says "I am on a pad" or "I am idle" (the idle card is
-- client only, and a queued client's idleness is ReportIdle). The capsule remotes (Phase 3) only buy and fill the
-- caller's own capsules: the server checks them with CapsuleMath and never takes a price or a Grip amount from them.
-- TrainerUpgrade went with the trainers (build plan Phase 6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Kind = "RemoteEvent" | "RemoteFunction"
export type Dir = "c2s" | "s2c"
-- Who receives a server -> client remote.
export type Audience = "owner" | "oneOrAll" | "participants" | "participantsOrNearby"
-- Expected argument type. Plain types are checked with typeof and finiteness; the named ids are strings checked
-- against the §2.7 patterns by Util/Validate. Handlers still receive `unknown` and narrow (§2.11).
export type ArgType =
	"integer"
	| "number" -- finite, |x| < Config.Net.maxAbsNumber (1e6)
	| "serverTime" -- a workspace:GetServerTimeNow() timestamp: finite, |x| < Config.Net.maxAbsServerTime
	| "coins" -- a whole Coin amount in [0, Config.Economy.maxCoins] (prices reach the trillions, spec 2026-10-12 §6)
	| "boolean"
	| "string"
	| "table"
	| "Vector3"
	| "squishyId"
	| "boxId"
	| "bundleKey"
	| "passKey"
	| "requestId"
	| "revealRequestId" -- requestId GUID, or "daily:<n>" (AckReveal only)
	| "questId"
	| "stepId"
	| "reasonCode" -- dotted code from §2.10 (text under Strings.reason)
	| "messageCode" -- a §2.10 reason code or any other Strings key; Strings.reasonText resolves both
export type ArgSpec = {
	name: string,
	type: ArgType,
	optional: boolean?,
}
export type RemoteSpec = {
	kind: Kind,
	dir: Dir,
	maxArgs: number?, -- c2s only: calls with select("#", ...) > maxArgs are dropped
	args: { ArgSpec },
	audience: Audience?, -- s2c only
}

local FOLDER_NAME = "SD_Remotes"

local Remotes = {}
Remotes.FOLDER_NAME = FOLDER_NAME

-- Private ---------------------------------------------------------------------------------------------------------

local function arg(name: string, argType: ArgType, optional: boolean?): ArgSpec
	local spec: ArgSpec = { name = name, type = argType, optional = optional }
	return table.freeze(spec)
end

-- Client -> server. maxArgs is the declared argument count (no C->S remote has optional arguments).
local function c2s(kind: Kind, args: { ArgSpec }): RemoteSpec
	local spec: RemoteSpec = { kind = kind, dir = "c2s", maxArgs = #args, args = table.freeze(args) }
	return table.freeze(spec)
end

-- Server -> client. Always a RemoteEvent: the server never calls InvokeClient (§2.7).
local function s2c(audience: Audience, args: { ArgSpec }): RemoteSpec
	local spec: RemoteSpec = { kind = "RemoteEvent", dir = "s2c", args = table.freeze(args), audience = audience }
	return table.freeze(spec)
end

local function newRemote(kind: Kind): Instance
	if kind == "RemoteFunction" then
		return Instance.new("RemoteFunction")
	end
	return Instance.new("RemoteEvent")
end

-- Keeps the first Folder named SD_Remotes and destroys any other instance with that name (never duplicates).
local function claimExistingFolder(): Instance?
	local kept: Instance? = nil
	for _, child in ReplicatedStorage:GetChildren() do
		if child.Name == FOLDER_NAME then
			if kept == nil and child.ClassName == "Folder" then
				kept = child
			else
				child:Destroy()
			end
		end
	end
	return kept
end

-- Finds `name` under `parent`, waiting (event-driven) until `deadline` (an os.clock() value) at most.
local function waitChildAsync(parent: Instance, name: string, deadline: number): Instance?
	local child = parent:FindFirstChild(name)
	if child then
		return child
	end
	local left = deadline - os.clock()
	if left <= 0 then
		return nil
	end
	return parent:WaitForChild(name, left)
end

-- Public ----------------------------------------------------------------------------------------------------------

-- Keyed by remote name; order and wording follow the §2.8 tables. RemoteFunctions return Result<T> (§2.7).
local SPEC: { [string]: RemoteSpec } = table.freeze({
	-- Client -> server
	RequestSnapshot = c2s("RemoteFunction", {}), -- data: Snapshot or { status = "loading" }
	-- Owned, in the Catalog, profile ready, not matched or in a match -> profile.equipped, SD_Equipped, save "soon".
	EquipSquishy = c2s("RemoteFunction", { arg("squishyId", "squishyId") }),
	QueueJoin = c2s("RemoteFunction", {}), -- data: { position }
	QueueLeave = c2s("RemoteEvent", {}),
	DuelForfeit = c2s("RemoteEvent", {}),
	ReportIdle = c2s("RemoteEvent", {}),
	ThrowRequest = c2s("RemoteEvent", {
		arg("seq", "integer"),
		arg("aimDir", "Vector3"),
		arg("originHint", "Vector3"),
		-- workspace:GetServerTimeNow() at the press (§5.6): Unix seconds, far above the 1e6 bound of "number".
		arg("clientTime", "serverTime"),
	}),
	UltimateRequest = c2s("RemoteEvent", {
		arg("seq", "integer"),
		arg("aimDir", "Vector3"),
		arg("clientTime", "serverTime"),
	}),
	-- Spec phase 5 (DashService, Logic/DashRules): the dash's flat unit direction only; the server decides whether it is
	-- legal and where it ends (the client predicts the same end with Shared/DashMath).
	DashRequest = c2s("RemoteEvent", {
		arg("seq", "integer"),
		arg("dir", "Vector3"),
		arg("clientTime", "serverTime"),
	}),
	-- Feature 1 (2026-10-11; CombatService): the charge throw's start, the press time only (validated like ThrowRequest's
	-- clientTime, §5.6 #7); the next ThrowRequest's charge is measured from it by the server, never sent by the client.
	ChargeStart = c2s("RemoteEvent", { arg("clientTime", "serverTime") }),
	-- Feature 1: the catch press; the server opens the catch window at the validated press time (Logic/CatchRules).
	CatchRequest = c2s("RemoteEvent", { arg("clientTime", "serverTime") }),
	-- §6.3 (Logic/SqueezeRules). No argument (spec 2026-10-11 §5, squeeze anywhere): the server finds the pad under the
	-- player's own root position; the tier always comes from the server's WorldLayout, never from the client.
	SqueezeRequest = c2s("RemoteEvent", {}), -- reply: SqueezeResult
	BoxOpen = c2s("RemoteFunction", { arg("boxId", "boxId"), arg("requestId", "requestId") }), -- data: BoxResult
	AckReveal = c2s("RemoteEvent", { arg("requestId", "revealRequestId") }),
	ShopBuy = c2s("RemoteFunction", {
		arg("squishyId", "squishyId"),
		arg("expectedPrice", "coins"), -- compared only, never charged (Dragon costs 1.1T, above the 1e6 "integer" bound)
		arg("requestId", "requestId"),
	}),
	QuestClaim = c2s("RemoteFunction", { arg("questId", "questId") }),
	QuestSwap = c2s("RemoteFunction", { arg("questId", "questId") }),
	DailyClaim = c2s("RemoteFunction", {}), -- data: Types.DailyClaimResult
	-- Capsules (lobby spec 2026-10-11 §6, Phase 3; CapsuleService): only the caller's own capsules, so no remote takes
	-- a base, plot or player id. slot = 1..#Config.Grip.Capsule.slotPrices; expectedPrice is compared, never charged.
	-- data: Types.CapsuleResult {capsules, charged, savePending}.
	CapsuleUpgrade = c2s("RemoteFunction", { arg("slot", "integer"), arg("expectedPrice", "coins") }),
	CapsuleUnlock = c2s("RemoteFunction", { arg("slot", "integer"), arg("expectedPrice", "coins") }),
	CapsuleSet = c2s("RemoteFunction", { arg("slot", "integer"), arg("squishyId", "squishyId") }),
	PromptCoinBundle = c2s("RemoteEvent", { arg("bundleKey", "bundleKey") }),
	PromptGamePass = c2s("RemoteEvent", { arg("passKey", "passKey") }),
	PolicyRetry = c2s("RemoteEvent", {}),
	SetSettings = c2s("RemoteEvent", { arg("settings", "table") }), -- only keys music, sfx, cameraShake, showTips
	OnboardingStep = c2s("RemoteEvent", { arg("stepId", "stepId") }),
	-- Batch 3 (FriendDuelService): Rematch on the duel result card. No argument: the server takes the opponent from its
	-- own MatchEnded record (the offer) and starts nothing until both players asked.
	RematchRequest = c2s("RemoteEvent", {}),

	-- Server -> client
	-- The only state channel (Types.StateDeltaFields, incl. `grip` from Part 5): one monotonic `v` per player.
	StateDelta = s2c("owner", { arg("v", "integer"), arg("fields", "table"), arg("full", "boolean", true) }),
	-- Notify also carries notices that are not §2.10 reason codes, e.g. the restart notice `server.restartSoon` (§3.12),
	-- `data.loaded` and the Grip toasts (Types.GripNotifyCode). `kind` is Types.NotifyKind.
	Notify = s2c("oneOrAll", { arg("code", "messageCode"), arg("args", "table", true), arg("kind", "string") }),
	-- Types.SqueezeResultPayload {ok, coins, total, limit, reason?, nextAt, grip, gripTotal, doubled}; nextAt is a
	-- server time (GetServerTimeNow scale). A flood-guard drop gets no reply (§6.3 step 1).
	SqueezeResult = s2c("owner", { arg("result", "table") }),
	-- Payload tables are typed in Types (QueueStatusPayload / QueueCountsPayload, DuelStateView, ThrowStartedPayload,
	-- ThrowImpactPayload, UltimateEventPayload, UltimateChargePayload, DuelResultPayload). The practice range has no
	-- remote of its own: it uses ThrowRequest / UltimateRequest, ThrowStarted / ThrowImpact / UltimateEvent to nearby
	-- players (Config.Combat.Projectile.practiceBroadcastStuds) and StateDelta.practice (§5.11).
	-- Owner on change; a count-only board payload to all players (<= Config.Net.Broadcast.queueStatusMaxHz).
	QueueStatus = s2c("oneOrAll", { arg("status", "table") }),
	-- The match state channel: a full view on every phase change, each participant its own you/opponent view.
	DuelState = s2c("participants", { arg("state", "table") }),
	-- Participants incl. the thrower; practice: nearby players.
	ThrowStarted = s2c("participantsOrNearby", { arg("throw", "table") }),
	-- Owner = the thrower. nextThrowAt is a server time (GetServerTimeNow), hence serverTime.
	ThrowRejected = s2c(
		"owner",
		{ arg("seq", "integer"), arg("reason", "reasonCode"), arg("nextThrowAt", "serverTime") }
	),
	ThrowImpact = s2c("participantsOrNearby", { arg("impact", "table") }),
	UltimateEvent = s2c("participantsOrNearby", { arg("event", "table") }),
	-- Types.DashStartedPayload (spec phase 5): participants incl. the dasher; practice: nearby players.
	DashStarted = s2c("participantsOrNearby", { arg("dash", "table") }),
	-- Types.CatchEventPayload (feature 1): a catch ("caught": the catcher crushes the thrower's toy) and its burst
	-- ("burst": the thrower loses a life), to the two duelists.
	CatchEvent = s2c("participants", { arg("event", "table") }),
	-- <= Config.Net.Broadcast.ultimateChargeMaxHz.
	UltimateCharge = s2c("participants", { arg("charge", "table") }),
	-- Each participant gets its own result.
	DuelResult = s2c("participants", { arg("result", "table") }),
} :: { [string]: RemoteSpec })

Remotes.SPEC = SPEC

-- Remote names for one direction, sorted.
function Remotes.names(dir: Dir): { string }
	local list = {}
	for name, spec in SPEC do
		if spec.dir == dir then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

-- Server only, and only while the game runs: refusing Edit mode keeps SD_Remotes out of the live Team Create place
-- (§1.5: runtime-owned). Idempotent: reuses the folder and every child whose name and class match SPEC; destroys
-- duplicates, wrong-class instances and names not in SPEC; creates what is missing. A new folder is filled before it
-- is parented, so clients never see a partial set.
function Remotes.createServer(): { [string]: Instance }
	assert(RunService:IsServer() and RunService:IsRunning(), "[SD][Remotes] createServer runs only on a running server")

	local existing = claimExistingFolder()
	local folder: Instance
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
	end

	local remotes: { [string]: Instance } = {}
	for _, child in folder:GetChildren() do
		local spec: RemoteSpec? = SPEC[child.Name]
		if spec and not remotes[child.Name] and child.ClassName == spec.kind then
			remotes[child.Name] = child
		else
			child:Destroy() -- not in SPEC, wrong class, or a duplicate
		end
	end
	for name, spec in SPEC do
		if not remotes[name] then
			local remote = newRemote(spec.kind)
			remote.Name = name
			remote.Parent = folder
			remotes[name] = remote
		end
	end

	if existing == nil then
		folder.Parent = ReplicatedStorage
	end
	return remotes
end

-- Client. Waits until SD_Remotes holds every SPEC remote, `timeout` seconds in total. Returns nil on timeout, or if
-- an instance has the wrong class (the caller then shows `error.connect`).
function Remotes.waitClientAsync(timeout: number): { [string]: Instance }?
	local deadline = os.clock() + timeout
	local folder = waitChildAsync(ReplicatedStorage, FOLDER_NAME, deadline)
	if folder == nil or folder.ClassName ~= "Folder" then
		return nil
	end
	local remotes: { [string]: Instance } = {}
	for name, spec in SPEC do
		local remote = waitChildAsync(folder, name, deadline)
		if remote == nil or remote.ClassName ~= spec.kind then
			return nil
		end
		remotes[name] = remote
	end
	return remotes
end

return Remotes
