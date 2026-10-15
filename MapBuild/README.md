# Squishy Duels map build (packed)

This folder holds the **complete** `SquishyDuels_MapBuild` folder (704 files, 652 MB) packed into one
`.tar.xz` archive (254 MB), split into 11 parts of at most 24 MB so every file fits GitHub's upload limits.
Nothing was removed. The archive is small because the textures embedded in the FBX and GLB files are byte-identical
copies of the PNGs, and the compressor stores each copy only once.

## Get the folder back

- **Windows:** double-click `JOIN_AND_EXTRACT.bat`. It uses the `copy` and `tar` commands built into Windows 10/11.
- **macOS / Linux / Git Bash:** `sh join_and_extract.sh`
- **By hand:** join the parts in order (`copy /b part1 + part2 + ...` or `cat *.0??`) into `SquishyDuels_MapBuild.tar.xz`,
  then extract it with `tar -xf`, 7-Zip, or Windows Explorer.

`SHA256SUMS.txt` lists the checksum of every part and of the joined archive.

## What is inside

- `SquishyDuels_Maps.blend`: the Blender file with all 6 maps
- `export/<MAP>/`: prop FBX + `_COL` collision FBX, `glb/`, `textures/` (BaseColor / Normal / Roughness / Metalness),
  `<MAP>_Layout.fbx`, `placements.json`, `MapAnimations_<MAP>.lua`
- `export/SH/`: shared spawn/power-up textures and particle sprites
- `export/MapLighting.lua`, `export/ROBLOX_IMPORT_GUIDE.md`
- `renders/`: hero render and 2048² top-down minimap for every map, plus check renders
- `scripts/`: the Blender Python that builds everything

Maps: Toy Box Clash (TBC), Sprinkle Factory (SPF), Bubble Bath Bay (BBB), Jelly Arcade (JAR), Sundae Plaza (SDP),
Pillow Fort Park (PFP).
