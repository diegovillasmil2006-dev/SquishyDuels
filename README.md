# Squishy Duels

The code of the Roblox game Squishy Duels (place `98945316226507`), synced into Studio with Rojo.

## First-time setup
1. Install [Git](https://git-scm.com/downloads) and [Rokit](https://github.com/rojo-rbx/rokit#installation).
2. Install the **Rojo 7.7.0** plugin in Roblox Studio (Creator Store, or `rojo plugin install`).
3. Download the code and its tools:
   ```bash
   git clone https://github.com/diegovillasmil2006-dev/SquishyDuels.git
   cd SquishyDuels
   rokit install
   ```

## Every time you work
1. **Get the latest code first:** `git pull`
2. **Start Rojo:** `rojo serve` (it uses port **34873**).
3. In Studio: Plugins → Rojo → type **34873** in the Port box → **Connect**.
   - "Could not sync because user X is already syncing" means the other person is connected. Wait until they finish.
   - If Rojo shows a long list of changes, click **Abort**: your copy is out of date. Run `git pull` and try again.
4. Edit the files in `src/`. Every save goes straight into Studio.
5. When you finish: **Disconnect** Rojo, then save your work to GitHub:
   ```bash
   git add -A
   git commit -m "What you changed"
   git push
   ```
   Tell the other person, so they `git pull` before they connect.

## Rules
- **Only one person syncs at a time.** Rojo enforces this in Team Create.
- **Never edit scripts directly in Studio.** Rojo overwrites them, and the change never reaches GitHub.
- The map (`Workspace`), `ServerStorage.SD_Templates` and `ReplicatedStorage.SD_ShapeLibrary` are not in this repo.
  Edit those in Studio as usual; Team Create saves them.

## Moving over from an old local folder
Your old Rojo folder is replaced by this repo. Before you delete it, copy anything that only exists there
(design docs, tool scripts, notes) into this repo and push it. Scripts already match: this repo was copied from Studio.
