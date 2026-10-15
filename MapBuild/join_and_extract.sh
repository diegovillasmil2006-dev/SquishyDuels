#!/bin/sh
# Joins the parts back into one archive and extracts it (macOS / Linux / Git Bash).
set -e
cd "$(dirname "$0")"
cat SquishyDuels_MapBuild.tar.xz.[0-9][0-9][0-9] > SquishyDuels_MapBuild.tar.xz
tar -xJf SquishyDuels_MapBuild.tar.xz
echo "Done: SquishyDuels_MapBuild/ extracted"
