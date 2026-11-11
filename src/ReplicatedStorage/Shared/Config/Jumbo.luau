--!strict
-- Config/Jumbo (big job item 10, 2026-11-10; the owner 2026-10-18: "there are some items that mutate your pets
-- forever", like Steal an Egg). Required directly (Config/init is near Roblox's 200,000-character limit). The one
-- forever item for a start, all of it Claude's call (the old money paper is lost; vault page "Big job 2026-11" > My
-- calls): a squishy made JUMBO (PenItem.mut = 1; a squishy saved before has no `mut`) is drawn `scale` times as big
-- and earns `mult` times its Coins, for good: it never comes off, it survives selling and buying back, and a fused
-- squishy is Jumbo when one of the three was. Bought and used at once in the MY PEN window; the price grows with
-- every Jumbo squishy the player owns (`first` x `growth` each: 5M, 40M, 320M ... 671T), at most `max` of them, so
-- the whole pen can at most double.

return {
	mult = 2,
	scale = 1.3,
	first = 5_000_000,
	growth = 8,
	max = 10,
}
