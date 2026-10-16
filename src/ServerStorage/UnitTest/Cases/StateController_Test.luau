--!strict
-- StateController_Test: the pure reducers of StarterPlayerScripts.Client.Controllers.StateController. Server only
-- (ServerStorage.UnitTest). Edit mode: init() and loadSnapshotAsync() are never called (no LocalPlayer, no remotes).
-- Contract (DESIGN §2.7, §2.8, §5.4):
--   * profile: a full Snapshot / StateDelta loads and replaces every field; older or repeated versions are ignored;
--     a partial delta merges; the changed field names are reported (sorted);
--   * QueueStatus: an owner update needs a valid state; a payload without `state` only updates the board counts;
--   * duel view: a new match id starts a fresh view, a match never goes back a phase, ThrowImpact sets the victim's
--     lives (never below 0), UltimateCharge sets ultReady only for a squishy with an ultimate at its chargeMax, and a
--     cleared SD_DuelPhase ends the view after Result/Returning/Cancelled/Void or once it is stale;
--   * the lobby is locked from Matched through Returning;
--   * Part 5 profile fields (§2.8, §3.2, §11.6, §17.10): coins, equipped, policy, dataStatus (with the server's banner
--     key), settings (clamped, defaults filled) and the table fields are checked before they are stored; a value of
--     the wrong shape keeps the old one; an identical resend is no change; new squishies are tracked per session;
--   * reveal holds (Part 7 review fix, §9.11): a held box result's refund is left out of the shown Coins and its new
--     squishy out of owned; only an unseen entry that first appears in a partial state is held, and seeing it or a
--     full state ends the hold;
--   * FFA/TDM v1 (2026-10-15, SPEC C4/C5): the 12-player match view (reduceMatch) starts from a MatchState with a
--     mode and a DuelPhase-named phase, takes the own name and squishy from the players, never goes back a phase,
--     keeps what a later state of the same match leaves out (a `you` without a userId changes only its own fields),
--     stores UltimateCharge for anyone (ultReady at chargeMax) and ends like the duel view (and at once when
--     SD_MatchId no longer names it); isEnemy / enemyIds: FFA
--     everyone else, TDM the other team, never oneself or a stranger; matchSide: TDM Blue "B", else "A"; a match view
--     locks the lobby; a "match:" id is a match id.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local StateController = t.requireClient("Controllers/StateController")
	local Config = t.requireShared("Config")

	local function emptyStore()
		return { v = 0, loaded = false, fields = {} }
	end

	local function duelState(matchId: string, phase: string, overrides: { [string]: any }?)
		local o: { [string]: any } = overrides or {}
		return {
			matchId = matchId,
			phase = phase,
			phaseEndsAt = 1000,
			you = {
				userId = 1,
				displayName = "Me",
				squishyId = o.youSquishy or "kitty_bread",
				side = "A",
				lives = o.youLives or 3,
				ultReady = false,
				isTestDummy = false,
			},
			opponent = {
				userId = 2,
				displayName = "Them",
				squishyId = o.opponentSquishy or "dragon",
				side = "B",
				lives = o.opponentLives or 3,
				ultReady = false,
				isTestDummy = o.dummy == true,
			},
			arena = { slot = 1, floorY = 0, zones = {}, pads = {} },
			rules = { Lives = 3 },
		}
	end

	local function stateEvent(raw: any, now: number?)
		return { kind = "state", state = raw, now = now or 0 }
	end

	t.test("profile: a full snapshot loads; older and repeated deltas are ignored; partial deltas merge", function()
		local store = emptyStore()
		local s1, changed1 = StateController.reduceProfile(store, 5, { coins = 10, equipped = "kitty_bread" }, true)
		expect.equal(s1.loaded, true)
		expect.equal(s1.v, 5)
		expect.deepEqual(changed1, { "coins", "equipped" })

		local s2, changed2 = StateController.reduceProfile(s1, 4, { coins = 99 }, false)
		expect.equal(s2, s1)
		expect.equal(#changed2, 0)
		local s3 = StateController.reduceProfile(s1, 5, { coins = 99 }, false)
		expect.equal(s3, s1) -- the same v again is a repeat

		local s4, changed4 = StateController.reduceProfile(s1, 6, { coins = 12 }, false)
		expect.equal(s4.fields.coins, 12)
		expect.equal(s4.fields.equipped, "kitty_bread")
		expect.deepEqual(changed4, { "coins" })
		expect.equal(s1.fields.coins, 10) -- the old store is never modified

		local s5, changed5 = StateController.reduceProfile(s4, 7, { coins = 12 }, true)
		expect.equal(s5.fields.equipped, nil) -- a full snapshot replaces everything
		expect.deepEqual(changed5, { "equipped" })
	end)

	t.test("profile: a partial delta never marks the store loaded; invalid input is ignored", function()
		local partial = StateController.reduceProfile(emptyStore(), 1, { coins = 1 }, false)
		expect.equal(partial.loaded, false)
		expect.equal(partial.fields.coins, 1)
		local store = emptyStore()
		expect.equal(StateController.reduceProfile(store, 0 / 0, { coins = 1 }, true), store)
		expect.equal(StateController.reduceProfile(store, 2, "nope" :: any, true), store)
	end)

	t.test("queue: owner updates need a valid state; count-only payloads update the board counts only", function()
		local counts = { searching = 0, duelsInProgress = 0, arenasFree = 6 }
		local idle = {
			state = "Idle",
			searching = 0,
			duelsInProgress = 0,
			arenasFree = 6,
		}
		local view, newCounts, kind = StateController.reduceQueue(idle, counts, {
			state = "Searching",
			position = 2,
			joinedAt = 1.8e9,
			searching = 3,
			duelsInProgress = 1,
			arenasFree = 5,
		})
		expect.equal(kind, "owner")
		expect.equal(view.state, "Searching")
		expect.equal(view.position, 2)
		expect.equal(view.joinedAt, 1.8e9)
		expect.equal(view.searching, 3)
		expect.deepEqual(newCounts, { searching = 3, duelsInProgress = 1, arenasFree = 5 })

		local view2, counts2, kind2 =
			StateController.reduceQueue(view, newCounts, { searching = 4, duelsInProgress = 2, arenasFree = 4 })
		expect.equal(kind2, "counts")
		expect.equal(view2.state, "Searching")
		expect.equal(view2.position, 2)
		expect.equal(view2.searching, 4)
		expect.deepEqual(counts2, { searching = 4, duelsInProgress = 2, arenasFree = 4 })

		local view3, _, kind3 = StateController.reduceQueue(view2, counts2, { state = "Lost" })
		expect.equal(kind3, "invalid")
		expect.equal(view3, view2)
		local _, _, kind4 = StateController.reduceQueue(view2, counts2, "nope")
		expect.equal(kind4, "invalid")
		local _, _, kind5 = StateController.reduceQueue(view2, counts2, {})
		expect.equal(kind5, "invalid")

		-- Bad numbers keep the previous counts; a position below 1 is dropped.
		local view6, counts6 = StateController.reduceQueue(view2, counts2, {
			state = "Searching",
			position = 0,
			searching = -1,
			duelsInProgress = 0 / 0,
			arenasFree = 3,
		})
		expect.equal(view6.position, nil)
		expect.deepEqual(counts6, { searching = 4, duelsInProgress = 2, arenasFree = 3 })
	end)

	t.test("lobby lock: from Matched through the end of the duel view", function()
		local base = { searching = 0, duelsInProgress = 0, arenasFree = 6 }
		local function q(state: string)
			return { state = state, searching = base.searching, duelsInProgress = 0, arenasFree = 6 }
		end
		expect.equal(StateController.lobbyLocked(q("Idle"), nil), false)
		expect.equal(StateController.lobbyLocked(q("Searching"), nil), false)
		expect.equal(StateController.lobbyLocked(q("Matched"), nil), true)
		local view = StateController.reduceDuel(nil, stateEvent(duelState("m1", "Returning")))
		expect.truthy(view)
		expect.equal(StateController.lobbyLocked(q("Idle"), view), true)
	end)

	t.test("duel: a new match starts a fresh view; phases never go back; positioned from Positioning", function()
		local v1 = StateController.reduceDuel(nil, stateEvent(duelState("m1", "Preparing"), 10))
		expect.equal(v1.matchId, "m1")
		expect.equal(v1.phase, "Preparing")
		expect.equal(v1.positioned, false)
		expect.equal(v1.receivedAt, 10)
		expect.equal(v1.opponent.displayName, "Them")

		local v2 = StateController.reduceDuel(v1, stateEvent(duelState("m1", "Positioning"), 11))
		expect.equal(v2.phase, "Positioning")
		expect.equal(v2.positioned, true)
		local v3 = StateController.reduceDuel(v2, stateEvent(duelState("m1", "Preparing"), 12))
		expect.equal(v3, v2) -- backwards: ignored
		local v4 = StateController.reduceDuel(v2, stateEvent(duelState("m1", "Cancelled"), 13))
		expect.equal(v4.phase, "Cancelled")
		expect.equal(v4.positioned, true)

		local other = StateController.reduceDuel(v4, stateEvent(duelState("m2", "Preparing"), 14))
		expect.equal(other.matchId, "m2")
		expect.equal(other.positioned, false)
	end)

	t.test("duel: malformed DuelState payloads are ignored", function()
		local good = StateController.reduceDuel(nil, stateEvent(duelState("m1", "Active")))
		local missingId = duelState("m1", "Active")
		missingId.matchId = nil :: any
		expect.equal(StateController.reduceDuel(good, stateEvent(missingId)), good)
		local badPhase = duelState("m1", "Dancing")
		expect.equal(StateController.reduceDuel(good, stateEvent(badPhase)), good)
		local badSide = duelState("m1", "Active")
		badSide.opponent.side = "C"
		expect.equal(StateController.reduceDuel(good, stateEvent(badSide)), good)
		local badTime = duelState("m1", "Active")
		badTime.phaseEndsAt = 0 / 0
		expect.equal(StateController.reduceDuel(nil, stateEvent(badTime)), nil)
		expect.equal(StateController.reduceDuel(nil, stateEvent("nope")), nil)
	end)

	t.test("duel: ThrowImpact sets the victim's lives and invulnerability; other impacts change nothing", function()
		local view = StateController.reduceDuel(nil, stateEvent(duelState("m1", "Active")))
		local hit = StateController.reduceDuel(view, {
			kind = "impact",
			impact = { kind = "player", victimId = 2, livesLeft = 2, invulnUntil = 50, projId = 1 },
		})
		expect.equal(hit.opponent.lives, 2)
		expect.equal(hit.opponent.invulnUntil, 50)
		expect.equal(hit.you.lives, 3)
		expect.equal(view.opponent.lives, 3) -- the old view is untouched

		local selfHit = StateController.reduceDuel(hit, {
			kind = "impact",
			impact = { kind = "player", victimId = 1, livesLeft = -4 },
		})
		expect.equal(selfHit.you.lives, 0)

		local wall = { kind = "impact", impact = { kind = "geometry", projId = 2 } }
		expect.equal(StateController.reduceDuel(selfHit, wall), selfHit)
		local stranger = { kind = "impact", impact = { kind = "player", victimId = 99, livesLeft = 0 } }
		expect.equal(StateController.reduceDuel(selfHit, stranger), selfHit)
		expect.equal(StateController.reduceDuel(nil, wall), nil)

		-- Lives and invulnerability survive the next DuelState of the same match only as the server sends them.
		local nextPhase =
			StateController.reduceDuel(hit, stateEvent(duelState("m1", "SuddenDeath", { opponentLives = 2 })))
		expect.equal(nextPhase.opponent.lives, 2)
		expect.equal(nextPhase.opponent.invulnUntil, 50)
	end)

	t.test("duel: UltimateCharge marks ultReady at chargeMax, only for a squishy with an ultimate", function()
		local chargeMax = Config.Abilities.dragon_rush.chargeMax
		local view = StateController.reduceDuel(nil, stateEvent(duelState("m1", "Active")))
		local half =
			StateController.reduceDuel(view, { kind = "charge", charge = { ownerId = 2, charge = chargeMax / 2 } })
		expect.equal(half.opponent.ultReady, false)
		expect.equal(half.charges[2], chargeMax / 2)
		local full = StateController.reduceDuel(half, { kind = "charge", charge = { ownerId = 2, charge = chargeMax } })
		expect.equal(full.opponent.ultReady, true)
		-- Kitty Bread has no ultimate: never ready, whatever the payload says.
		local mine = StateController.reduceDuel(full, { kind = "charge", charge = { ownerId = 1, charge = chargeMax } })
		expect.equal(mine.you.ultReady, false)
		expect.equal(StateController.reduceDuel(mine, { kind = "charge", charge = { ownerId = 2 } }), mine)
		-- Charges are kept across phase changes of the same match.
		local later = StateController.reduceDuel(full, stateEvent(duelState("m1", "SuddenDeath")))
		expect.equal(later.charges[2], chargeMax)
	end)

	t.test("duel: a cleared SD_DuelPhase ends the view after the end phases or once it is stale", function()
		local result = StateController.reduceDuel(nil, stateEvent(duelState("m1", "Result"), 100))
		expect.equal(StateController.reduceDuel(result, { kind = "cleared", now = 100 }), nil)
		local fresh = StateController.reduceDuel(nil, stateEvent(duelState("m2", "Preparing"), 100))
		expect.equal(StateController.reduceDuel(fresh, { kind = "cleared", now = 100.2 }), fresh)
		expect.equal(StateController.reduceDuel(fresh, { kind = "cleared", now = 105 }), nil)
		expect.equal(StateController.reduceDuel(nil, { kind = "cleared", now = 1 }), nil)
	end)

	t.test("DuelResult payloads: a match id and a known outcome", function()
		expect.equal(StateController.isValidResult({ matchId = "m1", outcome = "win" }), true)
		expect.equal(StateController.isValidResult({ matchId = "m1", outcome = "void" }), true)
		expect.equal(StateController.isValidResult({ matchId = "m1", outcome = "lose" }), false)
		expect.equal(StateController.isValidResult({ outcome = "win" }), false)
		expect.equal(StateController.isValidResult(nil), false)
	end)

	-- Part 5: the profile fields of §2.8 / §17.10 --------------------------------------------------------------------

	t.test("fields: coins become a whole number >= 0; a bad value is never stored", function()
		local norm = StateController.normalizeField
		local ok, coins = norm("coins", 12.7)
		expect.equal(ok, true)
		expect.equal(coins, 12)
		expect.equal((norm("coins", -1)), false)
		expect.equal((norm("coins", 0 / 0)), false)
		expect.equal((norm("coins", math.huge)), false)
		expect.equal((norm("coins", "5")), false)
		expect.equal((norm("coins", nil)), false)

		-- A partial delta with a bad coins value keeps the old value and reports nothing changed for it.
		local s1 = StateController.reduceProfile(emptyStore(), 1, { coins = 40 }, true)
		local s2, changed = StateController.reduceProfile(s1, 2, { coins = -3, equipped = "toast" }, false)
		expect.equal(s2.fields.coins, 40)
		expect.equal(s2.fields.equipped, "toast")
		expect.deepEqual(changed, { "equipped" })
	end)

	t.test("fields: equipped, policy and the table fields need their shape", function()
		local norm = StateController.normalizeField
		expect.equal((norm("equipped", "")), false)
		expect.equal((norm("equipped", 3)), false)
		expect.equal((norm("policy", "eligible")), true)
		expect.equal((norm("policy", "maybe")), false)
		for _, field in
			{ "owned", "stats", "squeezeLimit", "quests", "daily", "onboarding", "grip", "practice", "capsules" }
		do
			expect.equal((norm(field, "nope")), false)
			expect.equal((norm(field, {})), true)
		end
		-- Unknown fields from a newer server are kept as sent.
		local ok, value = norm("somethingNew", 5)
		expect.equal(ok, true)
		expect.equal(value, 5)
	end)

	t.test("fields: settings are clamped and filled from Config.Data defaults", function()
		local defaults = Config.Data.DefaultSettings
		local ok, settings =
			StateController.normalizeField("settings", { music = 140.6, sfx = -5, cameraShake = false })
		expect.equal(ok, true)
		expect.deepEqual(settings, {
			music = Config.Data.settingsMax,
			sfx = Config.Data.settingsMin,
			cameraShake = false,
			showTips = defaults.showTips,
		})
		local _, rounded = StateController.normalizeField("settings", { music = 42.5, sfx = 0 / 0 })
		expect.equal(rounded.music, 43)
		expect.equal(rounded.sfx, defaults.sfx)
		expect.equal((StateController.normalizeField("settings", true)), false)
	end)

	t.test("fields: dataStatus keeps its status, booleans and a banner key that has a text", function()
		local ok, status = StateController.normalizeField(
			"dataStatus",
			{ status = "ready", persisted = false, savePending = 1, banner = "data.studioMemory" }
		)
		expect.equal(ok, true)
		expect.deepEqual(
			status,
			{ status = "ready", persisted = false, savePending = false, banner = "data.studioMemory" }
		)
		local _, noBanner = StateController.normalizeField("dataStatus", { status = "offline", banner = "data.nope" })
		expect.deepEqual(noBanner, { status = "offline", persisted = true, savePending = false })
		expect.equal((StateController.normalizeField("dataStatus", { status = "sleeping" })), false)
		expect.equal((StateController.normalizeField("dataStatus", "ready")), false)
	end)

	t.test("fields: an identical resend is not a change and keeps the old table", function()
		local owned = { kitty_bread = { at = 1, src = "starter" } }
		local s1 = StateController.reduceProfile(emptyStore(), 1, { owned = owned, coins = 0 }, true)
		local again = { kitty_bread = { at = 1, src = "starter" } }
		local s2, changed = StateController.reduceProfile(s1, 2, { owned = again }, false)
		expect.equal(#changed, 0)
		expect.equal(s2.fields.owned, s1.fields.owned)
		expect.equal(s2.v, 2)
		local more = { kitty_bread = { at = 1, src = "starter" }, toast = { at = 5, src = "box" } }
		local s3, changed3 = StateController.reduceProfile(s2, 3, { owned = more }, false)
		expect.deepEqual(changed3, { "owned" })
		expect.equal(s3.fields.owned.toast.src, "box")
	end)

	t.test("deepEqual: plain data by value", function()
		local eq = StateController.deepEqual
		expect.equal(eq({ a = 1, b = { c = 2 } }, { a = 1, b = { c = 2 } }), true)
		expect.equal(eq({ a = 1 }, { a = 1, b = 2 }), false)
		expect.equal(eq({ a = 1, b = 2 }, { a = 1 }), false)
		expect.equal(eq({ 1, 2, 3 }, { 1, 2, 3 }), true)
		expect.equal(eq({ 1, 2 }, { 2, 1 }), false)
		expect.equal(eq("x", "x"), true)
		expect.equal(eq(nil, {}), false)
	end)

	t.test("new squishies: the first owned set is the baseline; later ids are new until seen", function()
		local track = StateController.trackNewOwned
		local tracker = { baseline = nil, fresh = {} }
		local t1 = track(tracker, { kitty_bread = {}, toast = {} }, true)
		expect.deepEqual(t1.fresh, {})
		local t2 = track(t1, { kitty_bread = {}, toast = {}, dragon = {} }, false)
		expect.deepEqual(t2.fresh, { dragon = true })
		expect.deepEqual(t1.fresh, {}) -- the input tracker is never modified
		-- A later full snapshot (data recovery) re-baselines without marking anything new, and keeps what is still new.
		local t3 = track(t2, { kitty_bread = {}, toast = {}, dragon = {}, donut = {} }, true)
		expect.deepEqual(t3.fresh, { dragon = true })
		-- An id that is no longer owned is no longer new.
		local t4 = track(t3, { kitty_bread = {} }, false)
		expect.deepEqual(t4.fresh, {})
		-- A partial update before any full snapshot also only sets the baseline.
		local t5 = track({ baseline = nil, fresh = {} }, { kitty_bread = {} }, false)
		expect.deepEqual(t5.fresh, {})
		expect.equal(track(t5, "nope", false), t5)
	end)

	-- Reveal holds (Part 7 review fix, §9.11 "no fake-outs"): the StateDelta carrying a box result arrives before its
	-- reveal plays, so the shown Coins and owned leave the held results out until BoxController releases them.

	local function boxEntry(req: string, squishy: string, dup: boolean, refund: number): any
		return {
			req = req,
			box = "snack",
			squishy = squishy,
			dup = dup,
			refund = refund,
			cost = 400,
			at = 0,
			seen = false,
		}
	end

	t.test("reveal holds: a held duplicate's refund and a held new squishy are hidden; nothing else is", function()
		local hide = StateController.hideHeldReveals
		local owned = { kitty_bread = { src = "starter" }, toast = { src = "box" }, dragon = { src = "box" } }
		local unseen = {
			boxEntry("R1", "toast", true, 100), -- a duplicate: 1000 - 400 + 100 = 700 on the server
			boxEntry("R2", "dragon", false, 0), -- a new squishy
			boxEntry("R3", "kitty_bread", true, 50), -- not held: shown as it is
		}
		-- Review scenario: 1000 Coins, a 400 box gives an owned Common (refund 100): the pill must show 600 (the spend),
		-- not 700 (which says "duplicate" before the reveal); the new squishy is not owned yet.
		local coins, shownOwned = hide(700, owned, unseen, { R1 = true, R2 = true })
		expect.equal(coins, 600)
		expect.deepEqual(shownOwned, { kitty_bread = { src = "starter" }, toast = { src = "box" } })
		expect.truthy(owned.dragon ~= nil) -- the input is not changed
		-- Only what is held: R1 alone keeps the owned table as it is (the same table).
		local coins1, owned1 = hide(700, owned, unseen, { R1 = true })
		expect.equal(coins1, 600)
		expect.equal(owned1, owned)
		-- Nothing held, no unseen list, a malformed entry: unchanged values (the same tables).
		local c0, o0 = hide(700, owned, unseen, {})
		expect.equal(c0, 700)
		expect.equal(o0, owned)
		local c2, o2 = hide(700, owned, nil, { R1 = true })
		expect.equal(c2, 700)
		expect.equal(o2, owned)
		local malformed: { any } = { "junk" :: any, { req = 5 } :: any }
		local c3, o3 = hide(700, owned, malformed, { R1 = true })
		expect.equal(c3, 700)
		expect.equal(o3, owned)
		-- The shown Coins never go below 0; a missing Coins value stays missing.
		expect.equal((hide(30, owned, unseen, { R1 = true })), 0)
		expect.equal((hide(nil, owned, unseen, { R1 = true })), nil)
	end)

	t.test("reveal holds: only a result that first appears in a partial state is held; seen or full ends it", function()
		local step = StateController.revealHoldStep
		local before = { boxEntry("R1", "toast", true, 100) }
		local after = { boxEntry("R1", "toast", true, 100), boxEntry("R2", "dragon", false, 0) }
		-- A new unseen entry in a partial delta after the first full state starts a hold.
		local start, stop = step({}, before, after, false, true)
		expect.deepEqual(start, { "R2" })
		expect.deepEqual(stop, {})
		-- Already held: not started twice.
		start, stop = step({ R2 = true }, before, after, false, true)
		expect.deepEqual(start, {})
		expect.deepEqual(stop, {})
		-- The first load and any full state (rejoin replay, data recovery) hold nothing and end every hold.
		start, stop = step({}, nil, after, true, false)
		expect.deepEqual(start, {})
		start, stop = step({ R1 = true, R2 = true }, before, after, true, true)
		expect.deepEqual(start, {})
		expect.deepEqual(stop, { "R1", "R2" })
		-- A partial state before the first full one holds nothing.
		start = step({}, nil, after, false, false)
		expect.deepEqual(start, {})
		-- AckReveal made it seen (it left the unseen list): the hold ends.
		start, stop = step({ R2 = true }, after, before, false, true)
		expect.deepEqual(start, {})
		expect.deepEqual(stop, { "R2" })
	end)

	-- FFA/TDM v1 (2026-10-15): the 12-player match view ------------------------------------------------------------

	local function matchState(matchId: string, phase: string, overrides: { [string]: any }?): any
		local o: { [string]: any } = overrides or {}
		return {
			matchId = matchId,
			mode = o.mode or "ffa",
			mapCode = "JAR",
			mapName = "Jelly Arcade",
			phase = phase,
			matchPhase = o.matchPhase or phase,
			phaseEndsAt = 1000,
			activeStartedAt = o.activeStartedAt,
			you = {
				userId = 1,
				team = o.youTeam,
				alive = o.alive ~= false,
				respawnAt = o.respawnAt,
				protectUntil = 0,
				stormBar = o.stormBar or 0,
				out = false,
			},
			players = o.players or {
				{
					userId = 1,
					displayName = "Me",
					squishyId = "kitty_bread",
					team = o.youTeam,
					kos = 2,
					knockedOut = 1,
					alive = true,
					ultReady = false,
				},
				{
					userId = 2,
					displayName = "Two",
					squishyId = "dragon",
					team = o.twoTeam,
					kos = 5,
					knockedOut = 0,
					alive = true,
					ultReady = false,
				},
				{
					userId = 3,
					displayName = "Three",
					squishyId = "kitty_bread",
					team = o.threeTeam,
					kos = 0,
					knockedOut = 3,
					alive = false,
					ultReady = false,
				},
			},
			teamLives = o.teamLives,
			koTarget = if o.mode == "tdm" then nil else 25,
			arena = {
				floorY = 0,
				bounds = { cframe = CFrame.new(7500, 42.5, 0), size = Vector3.new(200, 115, 200) },
				centre = Vector3.new(7500, 0, 0),
			},
			storm = o.storm,
		}
	end

	t.test("match: a new match starts a fresh view; you takes its name and squishy; phases never go back", function()
		local v1 = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Positioning"), 10))
		expect.truthy(v1)
		expect.equal(v1.matchId, "match:a")
		expect.equal(v1.mode, "ffa")
		expect.equal(v1.mapCode, "JAR")
		expect.equal(v1.phase, "Positioning")
		expect.equal(v1.matchPhase, "Positioning")
		expect.equal(v1.receivedAt, 10)
		expect.equal(v1.you.displayName, "Me")
		expect.equal(v1.you.squishyId, "kitty_bread")
		expect.equal(#v1.players, 3)
		expect.equal(v1.players[2].kos, 5)
		expect.equal(v1.players[3].alive, false)
		expect.equal(v1.koTarget, 25)
		expect.equal(v1.arena.bounds.size, Vector3.new(200, 115, 200))
		expect.equal(v1.arena.centre, Vector3.new(7500, 0, 0))
		-- Overtime keeps the DuelPhase name Active (SPEC D1); the real phase is matchPhase.
		local v2 = StateController.reduceMatch(v1, stateEvent(matchState("match:a", "Active"), 11))
		local v3 = StateController.reduceMatch(
			v2,
			stateEvent(matchState("match:a", "Active", { matchPhase = "Overtime" }), 12)
		)
		expect.equal(v3.phase, "Active")
		expect.equal(v3.matchPhase, "Overtime")
		expect.equal(StateController.reduceMatch(v3, stateEvent(matchState("match:a", "Countdown"), 13)), v3)
		-- Another match id: a fresh view.
		local other = StateController.reduceMatch(v3, stateEvent(matchState("match:b", "Positioning"), 14))
		expect.equal(other.matchId, "match:b")
		expect.equal(other.matchPhase, "Positioning")
	end)

	t.test("match: malformed MatchState payloads and DuelState-shaped ones are ignored", function()
		local good = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Active")))
		expect.equal(StateController.reduceMatch(nil, stateEvent(duelState("m1", "Active"))), nil) -- no mode
		expect.equal(StateController.reduceMatch(good, stateEvent(matchState("match:a", "Dancing"))), good)
		local badMode = matchState("match:c", "Active", { mode = "ctf" })
		expect.equal(StateController.reduceMatch(nil, stateEvent(badMode)), nil)
		local noYou = matchState("match:c", "Active")
		noYou.you = nil
		expect.equal(StateController.reduceMatch(nil, stateEvent(noYou)), nil)
		local badTime = matchState("match:c", "Active")
		badTime.phaseEndsAt = 0 / 0
		expect.equal(StateController.reduceMatch(nil, stateEvent(badTime)), nil)
		expect.equal(StateController.reduceMatch(good, stateEvent("nope")), good)
		-- A malformed player entry is skipped, the rest are kept.
		local junk = matchState("match:d", "Active")
		table.insert(junk.players, { userId = "x" })
		table.insert(junk.players, "junk")
		expect.equal(#StateController.reduceMatch(nil, stateEvent(junk)).players, 3)
	end)

	t.test(
		"match: a later state of the same match keeps what it leaves out; a partial you changes its fields",
		function()
			local v1 = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Active"), 10))
			-- The storm bar alone (no userId in you, no players, no phase): only that field moves.
			local bar =
				StateController.reduceMatch(v1, stateEvent({ matchId = "match:a", you = { stormBar = 0.4 } }, 11))
			expect.equal(bar.phase, "Active")
			expect.equal(bar.mode, "ffa")
			expect.equal(bar.players, v1.players)
			expect.near(bar.you.stormBar, 0.4, 1e-9)
			expect.equal(bar.you.alive, true)
			expect.equal(bar.you.squishyId, "kitty_bread")
			expect.equal(bar.koTarget, 25)
			expect.equal(bar.receivedAt, 11)
			-- A full you replaces the old one: knocked out with a respawn time, then standing again (no respawnAt).
			local ko = StateController.reduceMatch(
				bar,
				stateEvent(matchState("match:a", "Active", { alive = false, respawnAt = 503 }), 12)
			)
			expect.equal(ko.you.alive, false)
			expect.equal(ko.you.respawnAt, 503)
			expect.equal(ko.you.stormBar, 0)
			local back = StateController.reduceMatch(ko, stateEvent(matchState("match:a", "Active"), 13))
			expect.equal(back.you.alive, true)
			expect.equal(back.you.respawnAt, nil)
			-- A partial you with nothing before it is not a view.
			expect.equal(
				StateController.reduceMatch(nil, stateEvent({ matchId = "match:z", you = { stormBar = 1 } })),
				nil
			)
		end
	)

	t.test("match: UltimateCharge is kept for anyone and marks ultReady at chargeMax", function()
		local chargeMax = Config.Abilities.dragon_rush.chargeMax
		local view = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Active")))
		local full =
			StateController.reduceMatch(view, { kind = "charge", charge = { ownerId = 2, charge = chargeMax } })
		expect.equal(full.charges[2], chargeMax)
		expect.equal(full.players[2].ultReady, true)
		expect.equal(view.players[2].ultReady, false) -- the old view is untouched
		local mine =
			StateController.reduceMatch(full, { kind = "charge", charge = { ownerId = 1, charge = chargeMax } })
		expect.equal(mine.players[1].ultReady, false) -- Kitty Bread has no ultimate
		expect.equal(mine.charges[1], chargeMax)
		expect.equal(StateController.reduceMatch(mine, { kind = "charge", charge = { ownerId = 2 } }), mine)
		expect.equal(StateController.reduceMatch(nil, { kind = "charge", charge = { ownerId = 2, charge = 1 } }), nil)
		local later = StateController.reduceMatch(full, stateEvent(matchState("match:a", "Result")))
		expect.equal(later.charges[2], chargeMax)
	end)

	t.test("match: a cleared SD_DuelPhase ends the view after the end phases or once it is stale", function()
		local returning = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Returning"), 100))
		expect.equal(StateController.reduceMatch(returning, { kind = "cleared", now = 100 }), nil)
		local fresh = StateController.reduceMatch(nil, stateEvent(matchState("match:b", "Positioning"), 100))
		expect.equal(StateController.reduceMatch(fresh, { kind = "cleared", now = 100.2 }), fresh)
		expect.equal(StateController.reduceMatch(fresh, { kind = "cleared", now = 105 }), nil)
		expect.equal(StateController.reduceMatch(nil, { kind = "cleared", now = 1 }), nil)
		-- Review fix: SD_MatchId cleared too (a /leave mid-match: no final Returning view) ends even a fresh view;
		-- SD_MatchId still naming the match keeps the stale rule.
		local live = StateController.reduceMatch(nil, stateEvent(matchState("match:c", "Active"), 100))
		expect.equal(StateController.reduceMatch(live, { kind = "cleared", now = 100.2, matchId = "" }), nil)
		expect.equal(StateController.reduceMatch(live, { kind = "cleared", now = 100.2, matchId = "match:c" }), live)
		expect.equal(StateController.reduceMatch(live, { kind = "cleared", now = 100.2, matchId = "match:other" }), nil)
	end)

	t.test("match: enemies are everyone else in FFA and the other team in TDM, never oneself or a stranger", function()
		local ffa = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Active")))
		expect.equal(StateController.isEnemy(ffa, 2), true)
		expect.equal(StateController.isEnemy(ffa, 3), true) -- knocked out is still an enemy (aim skips the fallen)
		expect.equal(StateController.isEnemy(ffa, 1), false)
		expect.equal(StateController.isEnemy(ffa, 99), false)
		expect.equal(StateController.isEnemy(nil, 2), false)
		expect.deepEqual(StateController.enemyIds(ffa), { 2, 3 })
		local tdm = StateController.reduceMatch(
			nil,
			stateEvent(matchState("match:t", "Active", {
				mode = "tdm",
				youTeam = "Red",
				twoTeam = "Blue",
				threeTeam = "Red",
				teamLives = { Red = 40, Blue = 39 },
			}))
		)
		expect.equal(tdm.you.team, "Red")
		expect.equal(tdm.teamLives.Blue, 39)
		expect.equal(StateController.isEnemy(tdm, 2), true)
		expect.equal(StateController.isEnemy(tdm, 3), false) -- a teammate
		expect.deepEqual(StateController.enemyIds(tdm), { 2 })
		expect.deepEqual(StateController.enemyIds(nil), {})
		expect.equal(StateController.matchParticipant(tdm, 3).displayName, "Three")
		expect.equal(StateController.matchParticipant(tdm, 99), nil)
	end)

	t.test("match: matchSide gives TDM's second team the B side, everyone else A, a stranger nil", function()
		local names = { "Red", "Blue" }
		local tdm = StateController.reduceMatch(
			nil,
			stateEvent(matchState("match:t", "Active", { mode = "tdm", youTeam = "Red", twoTeam = "Blue" }))
		)
		expect.equal(StateController.matchSide(tdm, 1, names), "A")
		expect.equal(StateController.matchSide(tdm, 2, names), "B")
		expect.equal(StateController.matchSide(tdm, 99, names), nil)
		local ffa = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Active")))
		expect.equal(StateController.matchSide(ffa, 2, names), "A")
		expect.equal(StateController.matchSide(nil, 2, names), nil)
	end)

	t.test("lobby lock: a match view locks the lobby too; match ids", function()
		local idle = { state = "Idle", searching = 0, duelsInProgress = 0, arenasFree = 6 }
		local view = StateController.reduceMatch(nil, stateEvent(matchState("match:a", "Positioning")))
		expect.equal(StateController.lobbyLocked(idle :: any, nil, view), true)
		expect.equal(StateController.lobbyLocked(idle :: any, nil, nil), false)
		expect.equal(StateController.lobbyLocked(idle :: any, nil), false) -- the duel-only call still works
		expect.equal(StateController.isMatchId("match:1234"), true)
		expect.equal(StateController.isMatchId("1234-abcd"), false)
		expect.equal(StateController.isMatchId(nil), false)
	end)
end
