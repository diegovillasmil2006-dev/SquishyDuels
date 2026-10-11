# Squishy Duels

The snapshot history of the Roblox game Squishy Duels (place `98945316226507`).

## How it works
- Both of us prompt our own Claude Code at the same time. Claude edits the game directly in Studio (Team Create).
- After every prompt that changed the game, Claude saves a **snapshot** here and uploads it to GitHub automatically.
- If something breaks, tell Claude **"go back to before ..."** or **"undo the last change"**. It shows you the recent
  snapshots, asks which one, and puts the game back.

## Setting up a computer (once)
1. Install [Git](https://git-scm.com/downloads) and [Node.js](https://nodejs.org) (the LTS version).
2. Download this repo and tell Git your name:
   ```bash
   git clone https://github.com/diegovillasmil2006-dev/SquishyDuels.git
   cd SquishyDuels
   git config user.name "Your name"
   git config user.email "you@example.com"
   ```
3. Make sure your Claude Code is connected to Roblox Studio (the Roblox Studio MCP server), with Squishy Duels open.
4. Always open Claude Code **in this folder**. That is what turns on the automatic snapshots.

## Rules
- Work on different parts of the game at the same time (for example: one on the HUD, one on the map).
- Don't edit the same script at the same moment as the other person.
- Snapshots don't cover terrain or game settings. For those, Roblox keeps its own Version History in Creator Hub.
