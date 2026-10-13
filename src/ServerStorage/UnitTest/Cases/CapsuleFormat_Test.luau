--!strict
-- CapsuleFormat_Test: StarterPlayerScripts.Client.UI.CapsuleFormat (the capsule card, the owner's squeeze pop and the
-- swap list; build plan Phase 5). Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (lobby bases spec 2026-10-11 §5.3, §9; progression spec 2026-10-12 §3-§7; every number from CapsuleMath and
-- Format.coins, every text from Strings):
--   * an open capsule: the squishy (Tap to swap for the owner), "{tier} · Lv {level}", the squeeze time now -> next
--     (only when the next level is faster: at an evolve), Coins/h and Grip/h now -> next, and one Upgrade button with
--     the price; at an evolve level (10, 20 .. 90) the next tier's look and its Grip gate, and the button says Evolve;
--   * the button's states, the first that applies: the top level (Top level!, no button), a capsule remote running
--     (pending), the next level's Grip gate ("Needs Grip Lv N"), paused (profile loading / offline / read-only / a save
--     pending), not enough Coins (the missing amount), else ready; the price is only shown, the server checks it;
--   * an empty capsule says to put a squishy in and still upgrades;
--   * a locked slot: "Locked" and "Unlock · {price}" for the next slot only ("Unlock capsule N first" otherwise);
--   * a visitor sees the same card read-only: "Only {name} can upgrade this.", no button, no swap;
--   * popTexts: "+N Coins" / "+N Grip" for the owner only (squeezes × the capsule's Coins and Grip), nothing for a
--     visitor or an empty capsule;
--   * swapList: the owned squishies, the strongest first, each with its "x{n} power", the one in this capsule marked,
--     one in another capsule with "In capsule N" (it moves);
--   * phone first: the card fits a 667×375 phone, and its widest button and every word fit the card at the largest
--     text (0.6 em a letter, generous, as DailyFormat_Test).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CapsuleFormat = t.requireClient("UI/CapsuleFormat")
	local Layout = t.requireClient("UI/Layout")
	local CapsuleMath = t.requireShared("CapsuleMath")
	local Config = t.requireShared("Config")
	local Format = t.requireShared("Util/Format")
	local Strings = t.requireShared("Strings")
	local UI = Config.UI
	local READY = { status = "ready", persisted = true, savePending = false }

	local function s(key: string, args: { [string]: any }?): string
		local template = Strings.resolve(key)
		assert(template ~= nil, `missing Strings key {key}`)
		return Strings.format(template, args)
	end

	local function perHour(amount: number, level: number): string
		return Format.coins(math.floor(amount * 3600 / (CapsuleMath.seconds(level) :: number)))
	end

	local function own(capsules: any, slot: number, extra: { [string]: any }?): any
		local input: { [string]: any } =
			{ slot = slot, capsules = capsules, own = true, coins = 1e6, gripLevel = 100, status = READY }
		if extra then
			for key, value in extra do
				input[key] = value
			end
		end
		return CapsuleFormat.card(input)
	end

	local KITTY = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }

	t.test(
		"an owner's capsule: the squishy, tier and level, speed, Coins/h and Grip/h, Upgrade with the price",
		function()
			local card = own(KITTY, 1, { coins = 5000 })
			expect.equal(card.title, "Capsule 1")
			expect.equal(card.locked, false)
			expect.equal(card.squishyId, "kitty_bread")
			expect.equal(card.squishyName, "Kitty Bread")
			expect.equal(card.swapText, Strings.capsule.swap)
			expect.equal(card.tierText, "Foam · Lv 1")
			expect.equal(card.speedText, "Squeezes every 4.0 s") -- Lv 2 is still Foam: just as fast
			local coins1, coins2 =
				CapsuleMath.capsuleCoins("kitty_bread", 1), CapsuleMath.capsuleCoins("kitty_bread", 2)
			expect.equal(
				card.coinsText,
				s("capsule.coinsHourNext", { coins = perHour(coins1, 1), next = perHour(coins2, 2) })
			)
			expect.equal(card.coinsText, "Coins/h: 9,000 → 9,900")
			local grip1, grip2 = CapsuleMath.power(1) :: number, CapsuleMath.power(2) :: number
			expect.equal(
				card.gripText,
				s("capsule.gripHourNext", { grip = perHour(grip1, 1), next = perHour(grip2, 2) })
			)
			expect.equal(card.evolveText, nil)
			expect.equal(card.emptyText, nil)
			expect.equal(card.action, "upgrade")
			expect.equal(card.price, CapsuleMath.price(1))
			expect.equal(card.buttonText, "Upgrade · 1,000")
			expect.equal(card.state, "ready")
			expect.equal(card.reason, nil)
			expect.equal(card.visitorText, nil)
			expect.equal(card.maxText, nil)
		end
	)

	t.test("not enough Coins: the missing amount, never a Coin Store or Robux", function()
		local card = own(KITTY, 1, { coins = 400 })
		expect.equal(card.state, "needCoins")
		expect.equal(card.missing, 600)
		expect.equal(card.reason, Strings.format(Strings.common.needCoins.many, { missing = "600" }))
		local one = own(KITTY, 1, { coins = 999 })
		expect.equal(one.reason, Strings.format(Strings.common.needCoins.one, { missing = "1" }))
	end)

	t.test("an evolve level previews the next tier and its Grip gate; the button says Evolve", function()
		local capsules = { slots = 1, list = { { level = 10, squishyId = "kitty_bread" } } }
		local card = own(capsules, 1)
		expect.equal(card.tierText, "Foam · Lv 10")
		expect.equal(card.evolveText, s("capsule.evolveTo", { tier = "Jelly", level = 10 }))
		expect.equal(card.speedText, "Squeezes every 4.0 s → 3.5 s")
		expect.equal(card.action, "evolve")
		expect.equal(card.price, 28000) -- spec 2026-10-12 §5: 10 -> 11 is the 28K evolve
		expect.equal(card.buttonText, "Evolve · 28,000")
		local coins10, coins11 =
			CapsuleMath.capsuleCoins("kitty_bread", 10), CapsuleMath.capsuleCoins("kitty_bread", 11)
		expect.equal(
			card.coinsText,
			s("capsule.coinsHourNext", { coins = perHour(coins10, 10), next = perHour(coins11, 11) })
		)
		-- Only at the evolve levels: never at Lv 11 or 99.
		for _, level in { 11, 55, 99 } do
			local other = own({ slots = 1, list = { { level = level, squishyId = "kitty_bread" } } }, 1)
			expect.equal(other.evolveText, nil)
			expect.equal(other.action, "upgrade")
		end
		for tier = 1, 9 do
			local level = tier * 10
			local next = own({ slots = 1, list = { { level = level, squishyId = "toast" } } }, 1)
			local key = Config.Grip.Capsule.Tiers[tier + 1].key
			local gate = CapsuleMath.gripLevelFor(level + 1)
			expect.equal(next.evolveText, s("capsule.evolveTo", { tier = s("capsule.tier." .. key), level = gate }))
		end
	end)

	t.test("the next level's Grip gate: Needs Grip Lv N until the player has it", function()
		local capsules = { slots = 1, list = { { level = 10, squishyId = "kitty_bread" } } }
		local locked = own(capsules, 1, { gripLevel = 9 })
		expect.equal(locked.state, "gripLocked")
		expect.equal(locked.reason, "Needs Grip Lv 10")
		expect.equal(own(capsules, 1, { gripLevel = 10 }).state, "ready")
		-- Inside a tier there is no gate.
		expect.equal(own(KITTY, 1, { gripLevel = 1 }).state, "ready")
	end)

	t.test("the top level: Top level!, no button, no next values", function()
		local capsules = { slots = 1, list = { { level = 100, squishyId = "dragon" } } }
		local card = own(capsules, 1)
		expect.equal(card.state, "max")
		expect.equal(card.maxText, Strings.capsule.max)
		expect.equal(card.action, nil)
		expect.equal(card.buttonText, nil)
		expect.equal(card.price, 0)
		expect.equal(card.tierText, "Royal · Lv 100")
		expect.equal(card.speedText, "Squeezes every 1.3 s")
		expect.equal(
			card.coinsText,
			s("capsule.coinsHour", { coins = perHour(CapsuleMath.capsuleCoins("dragon", 100), 100) })
		)
		expect.equal(card.gripText, s("capsule.gripHour", { grip = perHour(CapsuleMath.power(100) :: number, 100) }))
		expect.equal(card.evolveText, nil)
		expect.equal(own(capsules, 1, { pending = true }).state, "max") -- nothing to wait for
	end)

	t.test("paused while the profile is not ready or a save is pending; pending while a call runs", function()
		expect.equal(
			own(KITTY, 1, { status = { status = "loading", persisted = true, savePending = false } }).reason,
			Strings.common.loading
		)
		local offline = own(KITTY, 1, { status = { status = "offline", persisted = false, savePending = false } })
		expect.equal(offline.state, "paused")
		expect.equal(offline.reason, Strings.reasonText("data.offline"))
		local readonly = own(KITTY, 1, { status = { status = "readonly", persisted = false, savePending = false } })
		expect.equal(readonly.reason, Strings.reasonText("data.readOnly"))
		local saving = own(KITTY, 1, { status = { status = "ready", persisted = true, savePending = true } })
		expect.equal(saving.state, "paused")
		expect.equal(saving.reason, Strings.reasonText("capsule.paused"))
		-- A running call wins over the Grip gate and the Coins.
		local evolve = { slots = 1, list = { { level = 10, squishyId = "kitty_bread" } } }
		expect.equal(own(evolve, 1, { pending = true, gripLevel = 1, coins = 0 }).state, "pending")
		-- No data status (a server without profiles): not paused.
		expect.equal(own(KITTY, 1, { status = false }).state, "ready")
	end)

	t.test("an empty capsule asks for a squishy and can still be upgraded", function()
		local card = own({ slots = 1, list = { { level = 3 } } }, 1)
		expect.equal(card.squishyId, nil)
		expect.equal(card.squishyName, nil)
		expect.equal(card.emptyText, Strings.capsule.empty)
		expect.equal(card.swapText, Strings.capsule.swap)
		expect.equal(card.coinsText, nil)
		expect.equal(card.gripText, nil)
		expect.equal(card.state, "ready")
		expect.equal(card.action, "upgrade")
	end)

	t.test("a locked slot: Locked, Unlock · {price} for the next slot only", function()
		local card = own(KITTY, 2, { coins = 5000 })
		expect.equal(card.locked, true)
		expect.equal(card.lockedText, Strings.capsule.locked)
		expect.equal(card.title, "Capsule 2")
		expect.equal(card.action, "unlock")
		expect.equal(card.price, CapsuleMath.slotPrice(2))
		expect.equal(
			card.buttonText,
			s("base.unlockPrice", { coins = Format.coins(CapsuleMath.slotPrice(2) :: number) })
		)
		expect.equal(card.buttonText, "Unlock · 2,500")
		expect.equal(card.state, "ready")
		expect.equal(card.tierText, nil)
		expect.equal(card.swapText, nil)
		expect.equal(own(KITTY, 2, { coins = 100 }).state, "needCoins")
		local skipped = own(KITTY, 3)
		expect.equal(skipped.state, "notNext")
		expect.equal(skipped.reason, "Unlock capsule 2 first")
		expect.equal(skipped.price, CapsuleMath.slotPrice(3))
	end)

	t.test("a visitor sees the same card, read-only", function()
		local capsules = { slots = 1, list = { { level = 5, squishyId = "toast" } } }
		local card = CapsuleFormat.card({ slot = 1, capsules = capsules, own = false, ownerName = "Mia" })
		expect.equal(card.state, "visitor")
		expect.equal(card.visitorText, "Only Mia can upgrade this.")
		expect.equal(card.swapText, nil)
		expect.equal(card.action, nil)
		expect.equal(card.buttonText, nil)
		expect.equal(card.tierText, "Foam · Lv 5")
		expect.equal(card.squishyName, "Toast")
		local lockedCard = CapsuleFormat.card({ slot = 3, capsules = capsules, own = false, ownerName = "Mia" })
		expect.equal(lockedCard.locked, true)
		expect.equal(lockedCard.state, "visitor")
		expect.equal(lockedCard.visitorText, "Only Mia can upgrade this.")
		expect.equal(lockedCard.buttonText, nil)
	end)

	t.test("the squeeze pop: +N Coins +N Grip for the owner only", function()
		local coins, grip = CapsuleFormat.popTexts(true, 2, { level = 1, squishyId = "kitty_bread" })
		expect.equal(coins, s("common.coinsGain", { coins = "20" }))
		expect.equal(grip, s("grip.popup", { n = "20" }))
		local dragonCoins, dragonGrip = CapsuleFormat.popTexts(true, 1, { level = 11, squishyId = "dragon" })
		expect.equal(dragonCoins, s("common.coinsGain", { coins = Format.coins(64 * 68) }))
		expect.equal(dragonGrip, s("grip.popup", { n = "68" }))
		-- Visitors see the squash and a sparkle, never the numbers.
		local visitorCoins, visitorGrip = CapsuleFormat.popTexts(false, 2, { level = 1, squishyId = "kitty_bread" })
		expect.equal(visitorCoins, nil)
		expect.equal(visitorGrip, nil)
		expect.equal((CapsuleFormat.popTexts(true, 1, { level = 4 })), nil) -- an empty capsule never squeezes
		expect.equal((CapsuleFormat.popTexts(true, 0, { level = 1, squishyId = "toast" })), nil)
		expect.equal((CapsuleFormat.popTexts(true, 1, nil)), nil)
	end)

	t.test("the swap list: owned squishies, the strongest first, where each one sits now", function()
		local owned = { kitty_bread = {}, toast = {}, butter = {}, dragon = {} }
		local capsules =
			{ slots = 2, list = { { level = 1, squishyId = "kitty_bread" }, { level = 1, squishyId = "butter" } } }
		local list = CapsuleFormat.swapList(owned, capsules, 1)
		local ids = {}
		for _, entry in list do
			table.insert(ids, entry.id)
		end
		expect.deepEqual(ids, { "dragon", "butter", "kitty_bread", "toast" })
		expect.equal(list[1].name, "Dragon")
		expect.equal(list[1].note, nil)
		-- Each row's capsule power ("x{n} power"), the choice that matters.
		expect.equal(list[1].power, s("capsule.power", { n = CapsuleMath.squishyPower("dragon") }))
		expect.equal(list[4].power, s("capsule.power", { n = CapsuleMath.squishyPower("toast") }))
		expect.equal(list[2].note, s("capsule.inCapsule", { slot = 2 })) -- it moves out of capsule 2
		expect.equal(list[3].here, true)
		expect.equal(list[3].note, nil)
		expect.equal(list[4].here, false)
		expect.deepEqual(CapsuleFormat.swapList(nil, capsules, 1), {})
		expect.deepEqual(CapsuleFormat.swapList({ not_a_squishy = {} }, capsules, 1), {})
	end)

	t.test(
		"phone first: the card fits a 667×375 phone; its widest button and every word fit at the largest text",
		function()
			local LARGEST = UI.PreferredTextScale.Largest
			local PADDING, SCROLLBAR = 20, 6 -- Theme.Padding.large, the body's scroll bar
			for _, actual in { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
				local scale = Layout.uiScale(actual.Y)
				local width = CapsuleFormat.cardWidth(actual.X, scale)
				expect.truthy(width <= UI.Capsule.cardWidth)
				expect.truthy(width + 2 * UI.Capsule.cardMargin <= actual.X / scale + 1e-6)
				local content = width - 2 * PADDING - SCROLLBAR
				-- The widest button label (the biggest price a two-digit price can show) and the reasons under it.
				for _, text in
					{
						s("capsule.upgrade", { coins = "999.99M" }),
						s("capsule.evolve", { coins = "999.99M" }),
						s("base.unlockPrice", { coins = "1.50M" }),
					}
				do
					local letters = utf8.len(text) :: number
					expect.truthy(letters * 0.6 * UI.TextSize.Button * LARGEST + 2 * 24 <= content)
				end
				-- Every word of every card text wraps between words, never inside one.
				local texts = {
					s("capsule.needGrip", { level = 100 }),
					s("capsule.unlockFirst", { slot = 4 }),
					s("capsule.evolveTo", { tier = "Marshmallow", level = 90 }),
					s("capsule.coinsHourNext", { coins = "999.99M", next = "999.99M" }),
					s("capsule.visitor", { name = "Squishmaster" }),
					Strings.capsule.empty,
				}
				for _, tier in Config.Grip.Capsule.Tiers do
					table.insert(texts, s("capsule.tierLevel", { tier = s("capsule.tier." .. tier.key), level = 100 }))
				end
				for _, text in texts do
					for word in string.gmatch(text, "%S+") do
						local letters = utf8.len(word) :: number
						expect.truthy(letters * 0.6 * UI.TextSize.H2 * LARGEST <= content)
					end
				end
			end
			expect.equal(CapsuleFormat.cardWidth(1920, 1.25), UI.Capsule.cardWidth)
			expect.equal(CapsuleFormat.cardWidth(0 / 0, 1), CapsuleFormat.cardWidth(1280, 1)) -- never NaN
		end
	)
end
