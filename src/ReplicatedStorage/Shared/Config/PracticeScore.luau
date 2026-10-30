--!strict
-- Config.PracticeScore: Diego's practice score box, TIME! card and hit pop (FULL FINAL lobby zip, reference-preview
-- "Hub Props.html" CSS .score :49-56, .result :57-61, .pop :62-65 and keyframes pop :65; owner 2026-10-30 "Yes, add
-- them"). Base px under the HUD's UIScale; colours are in Art/Palette (Practice*). Its own file: Config/UI.luau is at
-- Roblox's script size limit.

return table.freeze({
	-- .score: padding 10px 16px, border 3px, radius 16px, min-width 150px, box-shadow 0 4px 0.
	box = table.freeze({
		width = 150 + 2 * 16 + 2 * 3,
		padX = 16,
		padY = 10,
		border = 3,
		radius = 16,
		shadow = 4,
		labelSize = 12, -- .s (uppercase)
		labelLine = 15,
		scoreSize = 36, -- .n, line-height 1
		timeSize = 22, -- .t
		barTop = 8, -- .timebar margin-top
		barHeight = 8,
		barRadius = 4,
		comboTop = 6, -- .combo margin-top
		comboSize = 15,
		comboLine = 18, -- min-height
	}),
	-- .result: padding 22px 34px, border 4px, radius 22px, box-shadow 0 8px 0; .h 40px (6px stroke), .n 56px
	-- (line-height 1.1), .s 15px; scale .8 -> 1 in .45s cubic-bezier(.2,1.5,.4,1), opacity in .3s.
	card = table.freeze({
		padX = 34,
		padY = 22,
		border = 4,
		radius = 22,
		shadow = 8,
		titleSize = 40,
		titleStroke = 6,
		titleLine = 48,
		scoreSize = 56,
		scoreLine = 62,
		subSize = 15,
		subLine = 19,
		fromScale = 0.8,
		scaleSeconds = 0.45,
		fadeSeconds = 0.3,
	}),
	-- .pop: 28px (big: 40px, a 100-point hit), 5px stroke, small line 18px; 0.9s: from scale .5 at its centre, 25% scale
	-- 1.2 risen 40% of its height, to scale 1 risen 120% and gone.
	pop = table.freeze({
		size = 28,
		bigSize = 40,
		smallSize = 18,
		stroke = 5,
		seconds = 0.9,
		peakAt = 0.25,
		fromScale = 0.5,
		peakScale = 1.2,
		peakRise = 0.4,
		endRise = 1.2,
		bigPoints = 100,
	}),
	cardDisplayOrder = 14, -- over the practice reticle (13)
})
