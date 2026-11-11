--!strict
-- Config/Christmas (big job item 11, 2026-11-10; the owner: "the Christmas event, built but switched off until I say
-- so in December"). Required directly (Config/init is near Roblox's 200,000-character limit). Claude's design, in the
-- game's current look (vault page "Big job 2026-11" > My calls).
-- The event is ON only while the experience config `event_christmas` (Creator Hub > Configs) holds an END date that
-- has not passed: a text like 2027-01-06T00:00:00Z (UTC) or Unix seconds, read like `next_update`
-- (Shared/UpdateClock.parse). No config, an empty or broken one, or a past date = OFF: nothing of the event shows.
-- The server puts the end on Workspace as the attribute SD_ChristmasUntil (Unix seconds); Shared/Seasons reads it.
-- While it is on: the shop sells the two seasonal squishies (Catalog `event = "christmas"`) at `prices` (the Soft and
-- Sweet boxes' Rare and Epic: Pando's and Cloud Bunny's), snow falls round the player in the lobby, and the event
-- pill says how long is left. They are SEASONAL,
-- not exclusive: they come back every Christmas and the shop says so. A squishy bought stays and works all year.

return {
	event = "christmas",
	config = "event_christmas",
	attribute = "SD_ChristmasUntil",
	prices = {
		gingersnap_elk = 3_750_000,
		peppermint_puffin = 1_800_000_000,
	} :: { [string]: number },
	-- Snow while the event is on (Controllers/EventController): ONE emitter that follows the camera (the lobby design's
	-- rule for constant effects), `heightStuds` above it over an `areaStuds` square; only while the lobby HUD shows,
	-- none on low graphics or under ReducedMotion. Soft white flakes: `rate` a second, each `sizeStuds` across,
	-- falling `speed` studs a second for `lifetime` seconds with a slow sideways `drift`.
	snow = {
		heightStuds = 24,
		areaStuds = 70,
		rate = 26,
		sizeStuds = { 0.2, 0.42 },
		speed = { 6, 9 },
		lifetime = { 5, 7 },
		spreadDeg = 10,
		drift = Vector3.new(0.9, 0, 0.5),
	},
}
