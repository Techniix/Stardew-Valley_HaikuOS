#!/bin/bash
# Stardew Valley launcher for Haiku (x86_64).
#
# Layout (next to this script; for a package install, the writable parts
# (gamedata, steam-depot, Mods, logs) live in the user's data folder
# instead, see sdv-paths):
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
# shellcheck source=sdv-paths
source "$GAMEDIR/sdv-paths"

# Refuse to run from the Trash, e.g. a Terminal still sitting in a folder
# that was moved there after a newer package was unzipped elsewhere.
case "$GAMEDIR" in
  */trash/*|*/Trash/*)
    echo "This copy is in the Trash ($GAMEDIR)." >&2
    echo "You're probably in an old folder. cd to the new StardewValley folder and run it again." >&2
    exit 1 ;;
esac
[ -f "$GAMEDIR/VERSION" ] && echo "Stardew Valley for Haiku $(cat "$GAMEDIR/VERSION")"
cd "$DATADIR" || exit 1
exec > >(tee "$DATADIR/log.txt") 2>&1

# "Please wait" notice. The game keeps its window hidden until it has applied
# its saved size and mode, so without this nothing seems to happen for a few
# seconds. MonoGame creates MONOGAME_WINDOW_SHOWN_FILE once the window is on
# screen; a background watcher then takes the notice down.
# SDV_NO_LAUNCH_NOTICE=1 turns it off.
notice_id="sdv-launch-$$"
launch_notice() {  # <timeout seconds> <text>
  notify --type information --group "Stardew Valley" --title "Stardew Valley" \
    --messageID "$notice_id" --timeout "$1" "$2" >/dev/null 2>&1 || true
}
launch_notice_start() {
  [ "${SDV_NO_LAUNCH_NOTICE:-0}" = 1 ] && return 0
  command -v notify >/dev/null 2>&1 || return 0
  shown_file="$(mktemp -u "${TMPDIR:-/tmp}/sdv-window-shown.XXXXXX")"
  export MONOGAME_WINDOW_SHOWN_FILE="$shown_file"
  launch_notice 90 "Launching Stardew Valley: please wait..."
  (
    # Up to 90 s; stop early if the launcher itself is gone.
    i=0
    while [ ! -e "$shown_file" ] && [ "$i" -lt 900 ] && kill -0 "$$" 2>/dev/null; do
      sleep 0.1
      i=$((i + 1))
    done
    rm -f "$shown_file"
    launch_notice 1 "Launching Stardew Valley: please wait..."
  ) &
  notice_watcher=$!
}
launch_notice_stop() {  # the game exited or setup failed: take the notice down
  [ -n "${notice_watcher:-}" ] || return 0
  # If the watcher already finished, the notice is gone; don't bring it back.
  if kill "$notice_watcher" 2>/dev/null; then
    launch_notice 1 "Launching Stardew Valley: please wait..."
  fi
  wait "$notice_watcher" 2>/dev/null || true
  notice_watcher=
  rm -f "${shown_file:-}"
  unset MONOGAME_WINDOW_SHOWN_FILE
}

fail() {
  launch_notice_stop
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
if [ ! -f "$DATADIR/gamedata/Stardew Valley.dll" ]; then
  if [ -f "$DATADIR/gamedata/Stardew Valley.exe" ] || [ -f "$DATADIR/gamedata/StardewValley.exe" ]; then
    fail "These are the old compatibility-branch files. Copy the regular (mainline) 1.6 game files into $DATADIR/gamedata/."
  fi
  # Started from the Deskbar before setup: open setup in a Terminal window.
  if [ ! -t 0 ] && command -v Terminal >/dev/null 2>&1; then
    echo "No game files yet; opening setup in Terminal."
    Terminal -t "Stardew Valley setup" "$GAMEDIR/setup.sh" &
    exit 0
  fi
  fail "Missing game files. Run $GAMEDIR/setup.sh (or get-game-steam.sh) to download them from Steam, or copy your Stardew Valley install (Windows Steam or GOG) into $DATADIR/gamedata/."
fi
if [ ! -f "$DATADIR/gamedata/Stardew Valley.deps.json" ] || [ ! -f "$DATADIR/gamedata/Stardew Valley.runtimeconfig.json" ]; then
  fail "Incomplete game files in gamedata/ (deps.json or runtimeconfig.json missing)."
fi
launch_notice_start

# --- vanilla or SMAPI? -------------------------------------------------------
# Same rule as the PortMaster port: SMAPI starts automatically when Mods/
# contains anything besides SMAPI's own ConsoleCommands/SaveBackup.
# SDV_FORCE_SMAPI=1 forces SMAPI, SDV_VANILLA=1 forces the unmodded game.
mkdir -p "$DATADIR/Mods"
# shellcheck source=/dev/null
source "$GAMEDIR/tools/smapi-common"
launch_mode="$(sdv_smapi_determine_mode "$DATADIR/Mods")"
[ "${SDV_VANILLA:-0}" = 1 ] && launch_mode=vanilla
echo "Launch mode: $launch_mode"

patcher_args=(
  --game-dir "$DATADIR/gamedata"
  --overlay-dir "$GAMEDIR/overrides/gamedata"
  --mods-dir "$DATADIR/Mods"
  --profile desktop
  --runtime-target ".NETCoreApp,Version=v6.0/haiku-x64"
  --framework-version "$runtime_version"
  --roll-forward LatestMajor
  --no-network-interfaces   # Haiku's .NET lacks NetworkInformation (multiplayer)
  --fast-guid               # Haiku's Guid.NewGuid() is slow; it froze tool swings
)
entry_assembly="Stardew Valley.dll"
patch_assembly="$GAMEDIR/dlls/StardewPatches.dll"
if [ "$launch_mode" = smapi ]; then
  patcher_args+=(
    --smapi-bundle-dir "$GAMEDIR/tools/SMAPIBundle/game-root"
    --smapi-patch-assembly "$GAMEDIR/dlls/StardewPatches.dll"
  )
  entry_assembly="StardewModdingAPI.dll"
  patch_assembly="$DATADIR/gamedata/smapi-internal/StardewPatches.dll"
fi

# --- patch game files (once per game/port update or mode switch) ------------
# The patcher also fixes up mod assemblies, so re-run it when Mods/ changes.
stamp="$DATADIR/gamedata/.haiku-patched"
needs_patch=0
[ -f "$stamp" ] || needs_patch=1
[ "$needs_patch" = 0 ] && [ "$(cat "$stamp" 2>/dev/null)" != "$launch_mode $runtime_version" ] && needs_patch=1
[ "$needs_patch" = 0 ] && [ -n "$(find "$DATADIR/Mods" -newer "$stamp" -print -quit 2>/dev/null)" ] && needs_patch=1

# Refresh SMAPI's built-in mods only after the change check above, since
# copying them updates their timestamps.
if [ "$launch_mode" = smapi ]; then
  sdv_smapi_sync_default_mods "$GAMEDIR/tools/SMAPIBundle/default-mods" "$DATADIR/Mods"
fi
for f in "$DATADIR/gamedata/Stardew Valley.deps.json" \
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

# --- audio ------------------------------------------------------------------
# Haiku's media kit has a race: if an app's audio node gets its time source
# switched while its playback thread is using the old one, the old
# BTimeSource is freed under it and the game segfaults in
# BTimeSource::GetTime as audio starts. It's timing-dependent and varies by
# system, so nothing is done up front. If the game crashes, the launcher
# offers to restart the media services (which has made it go away) or to
# play without sound.
#   SDV_RESTART_MEDIA=1   restart media services before every launch
#   SDV_NO_AUDIO=1        no sound (OpenAL null output), avoids the media kit
media_helper="$GAMEDIR/libs/sdv-media-helper"

restart_media() {
  if [ ! -x "$media_helper" ]; then
    echo "Media helper not built (run ./setup.sh); restart media services in Preferences > Media."
    return 1
  fi
  echo "Restarting media services (other apps' sound pauses briefly)..."
  "$media_helper" --restart
}

if [ "${SDV_NO_AUDIO:-0}" = 1 ]; then
  export ALSOFT_DRIVERS=null
  echo "Audio disabled (SDV_NO_AUDIO=1)."
elif [ "${SDV_RESTART_MEDIA:-0}" = 1 ]; then
  restart_media || true
fi

# --- run --------------------------------------------------------------------
export MONOGAME_PATCH="$patch_assembly"
# Frame-time profiling built into the MonoGame fork. SDV_PROFILE=1 writes
# per-second stats, every frame slower than SDV_SLOW_FRAME_MS (default
# 25 ms here, i.e. a missed 60 Hz frame and then some) with GC counts, and
# how long each content (asset) load took.
#
# SDV_TRACE=1 also records a .NET CPU-sampling trace (EventPipe) and, after
# the game exits, writes logs/trace-report.txt: what the game's main thread
# was doing during the slow frames. Startup is slower while tracing, and the
# trace grows by a few MB per second, so keep traced sessions short.
trace_file=""
if [ "${SDV_TRACE:-0}" = 1 ]; then
  SDV_PROFILE=1
  trace_file="$DATADIR/logs/trace.nettrace"
fi
if [ "${SDV_PROFILE:-0}" = 1 ]; then
  mkdir -p "$DATADIR/logs"
  export SDV_PERF_LOG="$DATADIR/logs/perf-latest.csv"
  export SDV_SLOW_FRAME_LOG="$DATADIR/logs/slow-frame-latest.csv"
  export SDV_CONTENT_PROFILE_LOG="$DATADIR/logs/content-load-latest.csv"
  export SDV_SLOW_FRAME_MS="${SDV_SLOW_FRAME_MS:-25}"
  rm -f "$SDV_PERF_LOG" "$SDV_SLOW_FRAME_LOG" "$SDV_CONTENT_PROFILE_LOG" "$DATADIR/logs/trace-report.txt"
  echo "Frame profiling on: logs/perf-latest.csv, logs/slow-frame-latest.csv, logs/content-load-latest.csv"
fi
if [ -n "$trace_file" ]; then
  rm -f "$trace_file"
  export DOTNET_EnableEventPipe=1
  export DOTNET_EventPipeOutputPath="$trace_file"
  # Write as it goes: quitting the game ends the process with SIGKILL.
  export DOTNET_EventPipeOutputStreaming=1
  # CPU samples of every managed thread (~1 ms) plus method names (JIT, loader).
  export DOTNET_EventPipeConfig="Microsoft-DotNETCore-SampleProfiler:0:5,Microsoft-Windows-DotNETRuntime:0x18:5"
  # Precompiled framework code is only named in end-of-trace events, which a
  # SIGKILL loses; JIT everything so every method is named as it loads.
  export DOTNET_ReadyToRun=0
  echo "CPU tracing on: logs/trace.nettrace (report: logs/trace-report.txt)"
fi

# First-chance exception log (written by StardewPatches.dll). Keeps the real
# cause when the game wraps an error. SDV_EXCEPTION_LOG=0 turns it off.
if [ "${SDV_EXCEPTION_LOG:-}" = 0 ]; then
  unset SDV_EXCEPTION_LOG
else
  export SDV_EXCEPTION_LOG="$DATADIR/logs/exceptions.txt"
fi
if [ "$launch_mode" = smapi ]; then
  export SMAPI_MODS_PATH="$DATADIR/Mods"
  # Keep SMAPI's console output in this terminal / log.txt instead of
  # letting it try to open a Linux terminal emulator.
  export SMAPI_USE_CURRENT_SHELL=true
else
  unset SMAPI_MODS_PATH SMAPI_USE_CURRENT_SHELL
fi
cd "$DATADIR/gamedata" || exit 1
# SDL2 on Haiku chdir()s to the executable's folder (here: dotnet/) when TERM
# is unset, i.e. when started from Deskbar/Tracker. The game opens some
# content with paths relative to the working directory, so that breaks
# loading ("Could not load Data\BigCraftables asset!"). Setting TERM keeps
# SDL from changing directory. See SDL src/main/haiku/SDL_BeApp.cc.
export TERM="${TERM:-dumb}"

# Controller mappings recorded by ./gamepad.sh (Haiku's SDL backend needs them).
# Without a mapping SDL doesn't treat a device as a gamepad, so
# SDV_NO_GAMEPAD=1 (no mappings at all) makes the game ignore controllers.
if [ "${SDV_NO_GAMEPAD:-0}" = 1 ]; then
  unset SDL_GAMECONTROLLERCONFIG SDL_GAMECONTROLLERCONFIG_FILE
  echo "Controllers disabled (SDV_NO_GAMEPAD=1)."
elif [ -f "$DATADIR/gamecontrollerdb.txt" ]; then
  export SDL_GAMECONTROLLERCONFIG_FILE="$DATADIR/gamecontrollerdb.txt"
fi

retried=0
while :; do
  log_start=$(wc -l < "$DATADIR/log.txt" 2>/dev/null || echo 0)
  "$DOTNET" "$entry_assembly" "$@"
  status=$?
  launch_notice_stop
  echo "Stardew Valley exited with status $status."

  # An unhandled .NET exception means the game itself failed; any media kit
  # crash in the debug report is then a side effect of the process dying.
  sleep 1  # let tee flush
  game_error="$(tail -n +"$((log_start + 1))" "$DATADIR/log.txt" 2>/dev/null \
    | grep -m1 -A1 "^Unhandled exception" | tr '\n' ' ' | cut -c1-300)"
  if [ "$status" -gt 128 ] && [ -n "$game_error" ]; then
    echo "The game failed with an error; see log.txt and logs/exceptions.txt."
    command -v alert >/dev/null 2>&1 && alert --stop "Stardew Valley stopped with an error:

$game_error

Details are in log.txt and logs/exceptions.txt in the game folder. Please include both in a bug report." "OK" >/dev/null
    break
  fi

  # 137 = SIGKILL: killed on purpose (Deskbar/Team Monitor/kill), not a
  # crash. Don't offer crash workarounds.
  # Quitting from the game's own menu also ends with 137.
  if [ "$status" -eq 137 ]; then
    echo "Stardew Valley exited (SIGKILL: quit from the game menu, or killed)."
    break
  fi

  # > 128 means killed by a signal, e.g. a segfault terminated from the
  # Haiku debugger dialog. Offer the media-kit workarounds once.
  if [ "$status" -le 128 ] || [ "$retried" = 1 ] || [ "${ALSOFT_DRIVERS:-}" = null ] \
     || ! command -v alert >/dev/null 2>&1; then
    break
  fi
  retried=1
  alert --warning "Stardew Valley crashed.

If the debug report showed BTimeSource::GetTime, this is a known Haiku media kit bug in the audio code. Restarting the media services may help; playing without sound avoids it." \
    "Quit" "Play without sound" "Restart media & retry" >/dev/null
  choice=$?
  case "$choice" in
    2) restart_media || break ;;
    1) export ALSOFT_DRIVERS=null; echo "Retrying without sound." ;;
    *) break ;;
  esac
done

if [ -n "$trace_file" ] && [ -s "$trace_file" ]; then
  # Tracing settings must not apply to the report tool itself.
  unset DOTNET_EnableEventPipe DOTNET_EventPipeOutputPath DOTNET_EventPipeOutputStreaming \
        DOTNET_EventPipeConfig DOTNET_ReadyToRun
  echo "Summarising the trace (this can take a minute)..."
  if "$DOTNET" "$GAMEDIR/tools/TraceReport/TraceReport.dll" "$trace_file" \
       "$DATADIR/logs/slow-frame-latest.csv" > "$DATADIR/logs/trace-report.txt" 2>&1; then
    echo "Wrote logs/trace-report.txt"
  else
    echo "Trace summary failed; see logs/trace-report.txt"
  fi
elif [ -n "$trace_file" ]; then
  echo "No trace was recorded (this .NET build may not support EventPipe)."
fi
exit "$status"
