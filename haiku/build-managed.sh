#!/bin/bash
# Build the platform-neutral (.NET) parts of the Haiku package and assemble
# haiku/out/StardewValley/. Works on Linux, and on Haiku with the .NET SDK.
#
#   ./haiku/build-managed.sh
#
# Uses the MonoGame fork (Producdevity/MonoGame, portmaster-stardew-mainline)
# as a sibling checkout at ../MonoGame, cloned automatically at the pinned
# commit below if missing. The Haiku patches in patches/monogame/ are applied
# to it if they are not already. Override with MONOGAME_ROOT=/path/to/MonoGame.

set -euo pipefail
unset CDPATH

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
MONOGAME_ROOT="${MONOGAME_ROOT:-"$ROOT/../MonoGame"}"
OUT="$ROOT/haiku/out/StardewValley"
WORK="$ROOT/haiku/out/work"

# SMAPI (LGPL-3.0) is bundled so mods work out of the box.
SMAPI_VERSION="${SMAPI_VERSION:-4.5.2}"
SMAPI_SHA256="${SMAPI_SHA256:-dd01ddca7b566bfe0d3b3d2d03833496abc56c53da976241f2ab443f5484acc4}"
SMAPI_TOOLKIT_FILES=(SMAPI.Toolkit.dll SMAPI.Toolkit.xml SMAPI.Toolkit.CoreInterfaces.dll SMAPI.Toolkit.CoreInterfaces.xml)

MONOGAME_REPO="https://github.com/Producdevity/MonoGame"
MONOGAME_COMMIT="3874df98675039d368e77dca50d9a00ac970537e"   # portmaster-stardew-mainline

for tool in dotnet git curl unzip zip sha256sum; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

if [ ! -d "$MONOGAME_ROOT/MonoGame.Framework" ]; then
  echo "== Cloning MonoGame fork into $MONOGAME_ROOT"
  git init -q "$MONOGAME_ROOT"
  git -C "$MONOGAME_ROOT" remote add origin "$MONOGAME_REPO"
  git -C "$MONOGAME_ROOT" fetch -q --depth 1 origin "$MONOGAME_COMMIT"
  git -C "$MONOGAME_ROOT" checkout -q FETCH_HEAD
fi
monogame_head="$(git -C "$MONOGAME_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$monogame_head" != "$MONOGAME_COMMIT" ]; then
  echo "warning: MonoGame checkout is at $monogame_head, expected $MONOGAME_COMMIT" >&2
fi

echo "== Applying Haiku MonoGame patches"
for patch in "$ROOT"/patches/monogame/*.patch; do
  if git -C "$MONOGAME_ROOT" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "   already applied: $(basename "$patch")"
  else
    git -C "$MONOGAME_ROOT" apply "$patch"
    echo "   applied: $(basename "$patch")"
  fi
done

echo "== Fetching MonoGame third-party sources"
MONOGAME_ROOT="$MONOGAME_ROOT" "$ROOT/build/scripts/bootstrap-monogame-thirdparty.sh"

echo "== Building MonoGame.Framework (DesktopGL, netstandard2.0)"
dotnet build "$MONOGAME_ROOT/MonoGame.Framework/MonoGame.Framework.DesktopGL.csproj" \
  -c Release -f netstandard2.0 -nologo -v quiet
framework_dll="$(find "$MONOGAME_ROOT/Artifacts/MonoGame.Framework/DesktopGL" -path '*Release/netstandard2.0/MonoGame.Framework.dll' | head -n 1)"
[ -f "$framework_dll" ] || { echo "MonoGame.Framework.dll not found after build" >&2; exit 1; }

echo "== Building StardewPatches and MainlineGameDataPatcher"
rm -rf "$WORK"
mkdir -p "$WORK"
dotnet build "$ROOT/build/src/StardewPatches.Mainline/StardewPatches.Mainline.csproj" \
  -c Release -nologo -v quiet -o "$WORK/patches"
dotnet publish "$ROOT/build/src/MainlineGameDataPatcher/MainlineGameDataPatcher.csproj" \
  -c Release -nologo -v quiet -o "$WORK/patcher"
dotnet publish "$ROOT/build/src/TraceReport/TraceReport.csproj" \
  -c Release -nologo -v quiet -o "$WORK/tracereport"
# TraceEvent ships Windows-only ETW helpers; they're of no use on Haiku.
rm -rf "$WORK"/tracereport/{amd64,arm64,x86,runtimes} "$WORK"/tracereport/*.pdb "$WORK/tracereport/TraceReport"

echo "== Fetching SMAPI $SMAPI_VERSION"
smapi_zip="$WORK/smapi.zip"
curl -fsSL "https://github.com/Pathoschild/SMAPI/releases/download/$SMAPI_VERSION/SMAPI-$SMAPI_VERSION-installer.zip" -o "$smapi_zip"
actual="$(sha256sum "$smapi_zip" | awk '{print $1}')"
[ "$actual" = "$SMAPI_SHA256" ] || { echo "SMAPI checksum mismatch: $actual" >&2; exit 1; }
curl -fsSL "https://raw.githubusercontent.com/Pathoschild/SMAPI/$SMAPI_VERSION/LICENSE.txt" -o "$WORK/LICENSE.SMAPI.txt"
unzip -oq "$smapi_zip" -d "$WORK/smapi-installer"
smapi_installer="$WORK/smapi-installer/SMAPI $SMAPI_VERSION installer"
# SMAPI's Linux payload is the right one: Haiku is a Unix and SMAPI treats it as Linux.
unzip -oq "$smapi_installer/internal/linux/install.dat" -d "$WORK/smapi-payload"
for f in StardewModdingAPI.dll StardewModdingAPI.runtimeconfig.json smapi-internal/0Harmony.dll \
         Mods/ConsoleCommands/manifest.json Mods/SaveBackup/manifest.json; do
  [ -e "$WORK/smapi-payload/$f" ] || { echo "SMAPI payload is missing $f" >&2; exit 1; }
done

echo "== Assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"/{gamedata,overrides/gamedata,tools/MainlineGameDataPatcher,dlls,libs,Mods,native-src,licenses}
cp "$framework_dll" "$OUT/overrides/gamedata/MonoGame.Framework.dll"
cp "$WORK/patches/StardewPatches.dll" "$OUT/dlls/StardewPatches.dll"
cp -R "$WORK/patcher/." "$OUT/tools/MainlineGameDataPatcher/"
mkdir -p "$OUT/tools/TraceReport" && cp -R "$WORK/tracereport/." "$OUT/tools/TraceReport/"
cp "$ROOT/haiku/StardewValley.sh" "$ROOT/haiku/build-native.sh" "$ROOT/haiku/setup.sh" "$ROOT/haiku/get-game-steam.sh" "$ROOT/haiku/gamepad.sh" "$OUT/"
cp "$ROOT"/build/src/native/*.c "$ROOT"/build/src/native/*.cpp "$OUT/native-src/"
cp "$ROOT/haiku/INSTALL.txt" "$OUT/"
mkdir -p "$OUT/tools" && cp "$ROOT/tools/udp-relay.py" "$OUT/tools/"
cp "$ROOT/LICENSE" "$OUT/licenses/LICENSE.Port.txt"
cp "$ROOT/haiku/licenses/LICENSE.TraceEvent.txt" "$OUT/licenses/"
for f in LICENSE.MonoGame.txt LICENSE.Mono.Cecil.txt; do
  cp "$ROOT/portmaster_stardewvalley_mainline/stardewvalleymainline/licenses/$f" "$OUT/licenses/"
done
# SMAPI bundle: copied into gamedata/ by the patcher when mods are installed.
mkdir -p "$OUT/tools/SMAPIBundle/game-root" "$OUT/tools/SMAPIBundle/default-mods"
cp -R "$WORK/smapi-payload/." "$OUT/tools/SMAPIBundle/game-root/"
rm -rf "$OUT/tools/SMAPIBundle/game-root/Mods"
for mod in ConsoleCommands SaveBackup; do
  cp -R "$WORK/smapi-payload/Mods/$mod" "$OUT/tools/SMAPIBundle/default-mods/$mod"
  for f in "${SMAPI_TOOLKIT_FILES[@]}"; do
    cp "$WORK/smapi-payload/smapi-internal/$f" "$OUT/tools/SMAPIBundle/default-mods/$mod/"
  done
done
cp "$smapi_installer/README.txt" "$OUT/tools/SMAPIBundle/README.SMAPI.txt"
cp "$WORK/LICENSE.SMAPI.txt" "$OUT/licenses/LICENSE.SMAPI.txt"
cp "$ROOT/portmaster_stardewvalley_mainline/stardewvalleymainline/licenses/LICENSE.Harmony.txt" "$OUT/licenses/"
cp "$ROOT/portmaster_stardewvalley_mainline/stardewvalleymainline/tools/smapi-common" "$OUT/tools/smapi-common"

chmod +x "$OUT"/*.sh
touch "$OUT/gamedata/.keep" "$OUT/Mods/.keep"
echo "haiku-$(git -C "$ROOT" rev-parse --short HEAD)" > "$OUT/VERSION" 2>/dev/null || echo unknown > "$OUT/VERSION"

( cd "$ROOT/haiku/out" && rm -f StardewValley-haiku.zip && zip -qr StardewValley-haiku.zip StardewValley )
echo "Done: $ROOT/haiku/out/StardewValley-haiku.zip"
