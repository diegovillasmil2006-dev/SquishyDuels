# Squishy Duels: TDM / FFA queue, Match Found and map vote

Open `Squishy Duels HUD.dc.html` in a browser (serve the folder locally, e.g. `npx serve`), press DUEL.

## What's new
- Mode picker under DUEL: Team Deathmatch 6v6 / Free for All (12).
- Queue bar with 12 slots (red/blue split + VS for TDM).
- Match Found cinematic: orb charge → flash + shockwaves + confetti + shake, emblem slam, letter-by-letter "MATCH FOUND!" banner, team roster slide-in with VS slam. Procedural SFX for every beat.
- Map vote: mode title on top, countdown ring, 3 floating map boards per mode. Each vote flies the player's squishy icon onto the map card; live counts; tie roulette; winner zoom + "LET'S GO!" + teleport toast.

## Files
- `Squishy Duels HUD.dc.html`: HUD (logic: startMatch, toVote, castVote, endVote, reveal).
- `uploads/hud-lib.js`: SFX (mfCharge, mfImpact, mfLetters, vsSlam, toss, voteLand, clockTick, roulette) and FX (converge, toss).
- `uploads/duel-maps.js`: map data + board art for vote cards.
- `Duels Map Concepts.dc.html`: map layouts reference.

Images/icons live in the main HUD repo upload (uploads/upgraded_v1, uploads/hud-icons, *.png); copy that `uploads` folder alongside if missing.
