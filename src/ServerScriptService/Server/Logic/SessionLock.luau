--!strict
-- SessionLock (server only, pure). The session-lock decision table of DESIGN §3.7, used inside DataService's
-- UpdateAsync transforms (so it never yields and touches nothing but its arguments).
--
-- The lock lives in the key's metadata: `{ lock = { o = <owner>, t = <unix seconds> } }` (< 120 chars; limit 300).
-- Owner = (game.JobId ~= "" and game.JobId or "studio") .. "/" .. nonce, nonce = 8 hex chars of a GUID made once
-- per player session before the first load attempt (owner(), nonceFrom()).
--
-- evaluate(lock, now, me, staleAfter, held):
--   stored lock               | held = false (load)          | held = true (save)
--   none                      | "free"    -> acquire         | "lost"
--   o == me                   | "mine"    -> proceed (a "failed" write that actually succeeded) | "mine" -> write
--   other, now - t >= stale   | "stale"   -> take over (the caller logs it) | "lost"
--   other, fresh              | "foreign" -> abort and retry | "lost"
-- Readings (malformed metadata, which only a bug or a hand edit can produce):
--   * a lock that is not a table counts as none;
--   * a table whose `o` is not a non-empty string, or whose `t` is not a finite number, counts as another owner's
--     stale lock (it can never be ours, and it must not block the player forever);
--   * a lock stamped more than `staleAfter` seconds in the future counts as stale too (a broken clock or a forged
--     stamp would otherwise block the key until that time).

-- Types

export type Lock = { o: string, t: number }
export type Decision = "free" | "mine" | "stale" | "foreign" | "lost"

-- Constants

local NONCE_LENGTH = 8
local STUDIO_JOB = "studio" -- owner prefix when game.JobId is empty (Studio Play, §3.7)

-- Module table

local SessionLock = {}

-- Private

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Public

-- The decision for the stored `lock` (the metadata's `lock` field, any value) at `now` (unix seconds) for owner `me`.
-- `held = false` when loading (acquiring), `true` when saving (the session already holds the lock).
function SessionLock.evaluate(lock: unknown, now: number, me: string, staleAfter: number, held: boolean): Decision
	if type(lock) ~= "table" then
		return if held then "lost" else "free"
	end
	local owner = (lock :: any).o
	local stamp = (lock :: any).t
	if type(owner) == "string" and owner ~= "" and owner == me then
		return "mine"
	end
	if held then
		return "lost"
	end
	if type(owner) ~= "string" or owner == "" or not isFinite(stamp) then
		return "stale"
	end
	local age = now - (stamp :: number)
	if age >= staleAfter or age < -staleAfter then
		return "stale"
	end
	return "foreign"
end

-- A fresh lock for `me` stamped at `now`.
function SessionLock.newLock(me: string, now: number): Lock
	return { o = me, t = now }
end

-- The owner string for this server and this player session: "<JobId or studio>/<nonce>".
function SessionLock.owner(jobId: string?, nonce: string): string
	local job = if type(jobId) == "string" and jobId ~= "" then jobId else STUDIO_JOB
	return job .. "/" .. nonce
end

-- The first 8 hex characters of a GUID (dashes removed, lower case), e.g. from HttpService:GenerateGUID(false).
function SessionLock.nonceFrom(guid: string): string
	local hex = string.lower((string.gsub(guid, "[^%x]", "")))
	if #hex < NONCE_LENGTH then
		hex ..= string.rep("0", NONCE_LENGTH - #hex)
	end
	return string.sub(hex, 1, NONCE_LENGTH)
end

return SessionLock
