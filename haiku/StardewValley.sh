#!/bin/bash
# Stardew Valley launcher for Haiku (x86_64).
#
# Layout (next to this script):
#   gamedata/                 your own Stardew Valley files (Windows Steam or GOG build)
#   overrides/gamedata/       Haiku-patched MonoGame.Framework.dll, copied over gamedata
#   tools/MainlineGameDataPatcher/
#   dlls/StardewPatches.dll
#   libs/                     native shims built on Haiku (build-native.sh)
#   dotnet/                   .NET for Haiku, if installed by setup.sh
#   steam-depot/              pristine Steam download (get-game-steam.sh)
#   Mods/                     SMAPI mods; if any are present, the game starts through SMAPI
#   tools/SMAPIBundle/        bundled SMAPI
#   log.txt                   output of the last run

set -u

GAMEDIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
cd "$GAMEDIR" || exit 1
exec > >(tee "$GAMEDIR/log.txt") 2>&1

fail() {
  echo "ERROR: $*"
  if command -v alert >/dev/null 2>&1; then
    alert --stop "Stardew Valley: $*" "OK" >/dev/null
  fi
  exit 1
}

# --- .NET runtime -----------------------------------------------------------
# Haiku has no .NET 6 build; the game runs on whatever newer runtime is
# installed (trungnt2910/dotnet-builds), via rollForward=LatestMajor.
if [ -z "${DOTNET_ROOT:-}" ]; then
  if [ -x "$GAMEDIR/dotnet/dotnet" ]; then
    DOTNET_ROOT="$GAMEDIR/dotnet"
  elif [ -x "$HOME/.dotnet/dotnet" ]; then
    DOTNET_ROOT="$HOME/.dotnet"
  elif command -v dotnet >/dev/null 2>&1; then
    DOTNET_ROOT="$(dirname -- "$(readlink -f "$(command -v dotnet)")")"
  fi
fi
[ -n "${DOTNET_ROOT:-}" ] && [ -x "$DOTNET_ROOT/dotnet" ] \
  || fail "No .NET runtime found. Run ./setup.sh first."
export DOTNET_ROOT
DOTNET="$DOTNET_ROOT/dotnet"

# Haiku's networking stack has incomplete IPv6 support; .NET on Haiku needs this.
export DOTNET_SYSTEM_NET_DISABLEIPV6=1
# The patcher tool itself targets net6.0.
export DOTNET_ROLL_FORWARD=LatestMajor

runtime_version="$("$DOTNET" --list-runtimes 2>/dev/null | awk '/Microsoft.NETCore.App/ {print $2}' | sort -V | tail -n 1)"
[ -n "$runtime_version" ] || fail "The .NET install at $DOTNET_ROOT has no Microsoft.NETCore.App runtime."
echo "Using .NET runtime $runtime_version from $DOTNET_ROOT"

# --- native libraries ---------------------------------------------------------
# SDL2 and OpenAL come from HaikuPorts: pkgman install libsdl2 openal
export LIBRARY_PATH="$GAMEDIR/libs:%A/libs${LIBRARY_PATH:+:$LIBRARY_PATH}"

# --- game files -------------------------------------------------------------
if [ ! -f "$GAMEDIR/gamedata/Stardew Valley.dll" ]; then
  if [ -f "$GAMEDIR/gamedata/Stardew Valley.exe" ] || [ -f "$GAMEDIR/gamedata/StardewValley.exe" ]; then
    fail "These are the old compatibility-branch files. Copy the regular (mainline) 1.6 game files into gamedata/."
  fi
  fail "Missing game files. Run ./get-game-steam.sh to download them from Steam, or copy your Stardew Valley install (Windows Steam or GOG) into $GAMEDIR/gamedata/."
fi
if [ ! -f "$GAMEDIR/gamedata/Stardew Valley.deps.json" ] || [ ! -f "$GAMEDIR/gamedata/Stardew Valley.runtimeconfig.json" ]; then
  fail "Incomplete game files in gamedata/ (deps.json or runtimeconfig.json missing)."
fi

# --- vanilla or SMAPI? -------------------------------------------------------
# Same rule as the PortMaster port: SMAPI starts automatically when Mods/
# contains anything besides SMAPI's own ConsoleCommands/SaveBackup.
# SDV_FORCE_SMAPI=1 forces SMAPI, SDV_VANILLA=1 forces the unmodded game.
mkdir -p "$GAMEDIR/Mods"
# shellcheck source=/dev/null
source "$GAMEDIR/tools/smapi-common"
launch_mode="$(sdv_smapi_determine_mode "$GAMEDIR/Mods")"
[ "${SDV_VANILLA:-0}" = 1 ] && launch_mode=vanilla
echo "Launch mode: $launch_mode"

patcher_args=(
  --game-dir "$GAMEDIR/gamedata"
  --overlay-dir "$GAMEDIR/overrides/gamedata"
  --mods-dir "$GAMEDIR/Mods"
  --profile desktop
  --runtime-target ".NETCoreApp,Version=v6.0/haiku-x64"
  --framework-version "$runtime_version"
  --roll-forward LatestMajor
)
entry_assembly="Stardew Valley.dll"
patch_assembly="$GAMEDIR/dlls/StardewPatches.dll"
if [ "$launch_mode" = smapi ]; then
  patcher_args+=(
    --smapi-bundle-dir "$GAMEDIR/tools/SMAPIBundle/game-root"
    --smapi-patch-assembly "$GAMEDIR/dlls/StardewPatches.dll"
  )
  entry_assembly="StardewModdingAPI.dll"
  patch_assembly="$GAMEDIR/gamedata/smapi-internal/StardewPatches.dll"
fi

# --- patch game files (once per game/port update or mode switch) ------------
# The patcher also fixes up mod assemblies, so re-run it when Mods/ changes.
stamp="$GAMEDIR/gamedata/.haiku-patched"
needs_patch=0
[ -f "$stamp" ] || needs_patch=1
[ "$needs_patch" = 0 ] && [ "$(cat "$stamp" 2>/dev/null)" != "$launch_mode $runtime_version" ] && needs_patch=1
[ "$needs_patch" = 0 ] && [ -n "$(find "$GAMEDIR/Mods" -newer "$stamp" -print -quit 2>/dev/null)" ] && needs_patch=1

# Refresh SMAPI's built-in mods only after the change check above, since
# copying them updates their timestamps.
if [ "$launch_mode" = smapi ]; then
  sdv_smapi_sync_default_mods "$GAMEDIR/tools/SMAPIBundle/default-mods" "$GAMEDIR/Mods"
fi
for f in "$GAMEDIR/gamedata/Stardew Valley.deps.json" \
         "$GAMEDIR/overrides/gamedata/MonoGame.Framework.dll" \
         "$GAMEDIR/tools/MainlineGameDataPatcher/MainlineGameDataPatcher.dll"; do
  [ "$needs_patch" = 1 ] && break
  [ "$f" -nt "$stamp" ] && needs_patch=1
done

if [ "$needs_patch" = 1 ] || [ "${SDV_FORCE_PATCH:-0}" = 1 ]; then
  echo "Patching game files for Haiku..."
  "$DOTNET" "$GAMEDIR/tools/MainlineGameDataPatcher/MainlineGameDataPatcher.dll" "${patcher_args[@]}" \
    || fail "Patching the game files failed. See log.txt."
  echo "$launch_mode $runtime_version" > "$stamp"
fi

# --- run --------------------------------------------------------------------
export MONOGAME_PATCH="$patch_assembly"
if [ "$launch_mode" = smapi ]; then
  export SMAPI_MODS_PATH="$GAMEDIR/Mods"
  # Keep SMAPI's console output in this terminal / log.txt instead of
  # letting it try to open a Linux terminal emulator.
  export SMAPI_USE_CURRENT_SHELL=true
else
  unset SMAPI_MODS_PATH SMAPI_USE_CURRENT_SHELL
fi
cd "$GAMEDIR/gamedata" || exit 1
"$DOTNET" "$entry_assembly" "$@"
status=$?
echo "Stardew Valley exited with status $status."
exit $status
