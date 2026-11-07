#!/bin/bash
# Build the platform-neutral (.NET) parts of the Haiku package and assemble
# haiku/out/StardewValley/. Works on Linux, and on Haiku with the .NET SDK.
#
#   ./haiku/build-managed.sh
#
# Expects the MonoGame fork as a sibling checkout (../MonoGame), on the
# portmaster-stardew-mainline branch of Producdevity/MonoGame. The Haiku
# patches in patches/monogame/ are applied to it if they are not already.
# Override with MONOGAME_ROOT=/path/to/MonoGame.

set -euo pipefail
unset CDPATH

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
MONOGAME_ROOT="${MONOGAME_ROOT:-"$ROOT/../MonoGame"}"
OUT="$ROOT/haiku/out/StardewValley"
WORK="$ROOT/haiku/out/work"

command -v dotnet >/dev/null || { echo "dotnet SDK not found" >&2; exit 1; }
[ -d "$MONOGAME_ROOT/MonoGame.Framework" ] || {
  echo "MonoGame fork not found at $MONOGAME_ROOT" >&2
  echo "git clone -b portmaster-stardew-mainline https://github.com/Producdevity/MonoGame \"$MONOGAME_ROOT\"" >&2
  exit 1
}

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

echo "== Assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"/{gamedata,overrides/gamedata,tools/MainlineGameDataPatcher,dlls,libs,Mods,native-src,licenses}
cp "$framework_dll" "$OUT/overrides/gamedata/MonoGame.Framework.dll"
cp "$WORK/patches/StardewPatches.dll" "$OUT/dlls/StardewPatches.dll"
cp -R "$WORK/patcher/." "$OUT/tools/MainlineGameDataPatcher/"
cp "$ROOT/haiku/StardewValley.sh" "$ROOT/haiku/build-native.sh" "$ROOT/haiku/setup.sh" "$ROOT/haiku/get-game-steam.sh" "$OUT/"
cp "$ROOT"/build/src/native/*.c "$OUT/native-src/"
cp "$ROOT/haiku/INSTALL.txt" "$OUT/"
cp "$ROOT/LICENSE" "$OUT/licenses/LICENSE.Port.txt"
for f in LICENSE.MonoGame.txt LICENSE.Mono.Cecil.txt; do
  cp "$ROOT/portmaster_stardewvalley_mainline/stardewvalleymainline/licenses/$f" "$OUT/licenses/"
done
chmod +x "$OUT"/*.sh
touch "$OUT/gamedata/.keep" "$OUT/Mods/.keep"

( cd "$ROOT/haiku/out" && rm -f StardewValley-haiku.zip && zip -qr StardewValley-haiku.zip StardewValley )
echo "Done: $ROOT/haiku/out/StardewValley-haiku.zip"
