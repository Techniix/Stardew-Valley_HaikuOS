#!/bin/bash
# Download your own copy of Stardew Valley from Steam, directly on Haiku.
#
#   ./get-game-steam.sh            log in with username (+ password / Steam Guard prompts)
#   ./get-game-steam.sh --qr       log in by scanning a QR code with the Steam mobile app
#   ./get-game-steam.sh --update   same as above; re-downloads only changed files
#   SDV_MAX_DOWNLOADS=2 ./get-game-steam.sh   fewer parallel downloads (default 8),
#                                             if the download stalls
#
# Uses DepotDownloader (github.com/SteamRE/DepotDownloader, GPL-2.0), fetched on
# first use. It runs on the .NET runtime this port already needs (9.0+).
# Your password and Steam Guard code are typed straight into DepotDownloader;
# this script never sees or stores them. With "remember me", DepotDownloader
# keeps a Steam login token (not your password) in its own config folder.
#
# You must own Stardew Valley on Steam. The Windows depot is downloaded, since
# that's the build this port is tested against.

set -euo pipefail

GAMEDIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"

# Refuse to run from the Trash, e.g. a Terminal still sitting in a folder
# that was moved there after a newer package was unzipped elsewhere.
case "$GAMEDIR" in
  */trash/*|*/Trash/*)
    echo "This copy is in the Trash ($GAMEDIR)." >&2
    echo "You're probably in an old folder. cd to the new StardewValley folder and run it again." >&2
    exit 1 ;;
esac
[ -f "$GAMEDIR/VERSION" ] && echo "Stardew Valley for Haiku $(cat "$GAMEDIR/VERSION")"
APP_ID=413150

DD_VERSION="3.4.0"
DD_URL="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DD_VERSION}/DepotDownloader-framework.zip"
DD_SHA256="7419f65efb7eb16b6e56987ed1b76475f29c02475c0016166c84798388e796bc"
DD_DIR="$GAMEDIR/tools/DepotDownloader"

# Pristine Steam download; gamedata/ is a patched copy made from it, so
# updates never fight with the files the Haiku patcher changes.
DEPOT_DIR="$GAMEDIR/steam-depot"

use_qr=0
for arg in "$@"; do
  case "$arg" in
    --qr) use_qr=1 ;;
    --update) ;;
    -h|--help) sed -n 2,16p "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# --- .NET ---------------------------------------------------------------------
if [ -z "${DOTNET_ROOT:-}" ]; then
  for d in "$GAMEDIR/dotnet" "$HOME/.dotnet"; do
    [ -x "$d/dotnet" ] && DOTNET_ROOT="$d" && break
  done
  if [ -z "${DOTNET_ROOT:-}" ] && command -v dotnet >/dev/null 2>&1; then
    DOTNET_ROOT="$(dirname -- "$(readlink -f "$(command -v dotnet)")")"
  fi
fi
[ -n "${DOTNET_ROOT:-}" ] && [ -x "$DOTNET_ROOT/dotnet" ] || {
  echo "No .NET runtime found. Install .NET 9+ from github.com/trungnt2910/dotnet-builds or set DOTNET_ROOT." >&2
  exit 1
}
export DOTNET_ROOT DOTNET_SYSTEM_NET_DISABLEIPV6=1

newest_major="$("$DOTNET_ROOT/dotnet" --list-runtimes 2>/dev/null | awk '/Microsoft.NETCore.App/ {split($2,v,"."); print v[1]}' | sort -n | tail -n 1)"
if [ -z "$newest_major" ] || [ "$newest_major" -lt 9 ]; then
  echo "DepotDownloader needs .NET 9 or newer (found: ${newest_major:-none})." >&2
  exit 1
fi

# --- DepotDownloader ----------------------------------------------------------
if [ ! -f "$DD_DIR/DepotDownloader.dll" ] || [ "$(cat "$DD_DIR/.version" 2>/dev/null)" != "$DD_VERSION" ]; then
  echo "Fetching DepotDownloader $DD_VERSION..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --progress-bar "$DD_URL" -o "$tmp/dd.zip"
  actual="$(sha256sum "$tmp/dd.zip" | awk '{print $1}')"
  if [ "$actual" != "$DD_SHA256" ]; then
    echo "Checksum mismatch for DepotDownloader download (got $actual). Aborting." >&2
    exit 1
  fi
  rm -rf "$DD_DIR"
  mkdir -p "$DD_DIR"
  unzip -q "$tmp/dd.zip" -d "$DD_DIR"
  echo "$DD_VERSION" > "$DD_DIR/.version"
fi

# Haiku's .NET doesn't implement NetworkInterface.GetAllNetworkInterfaces(),
# which SteamKit2 calls after login to build a machine ID. Patch its fallback
# so it copes (idempotent; also fixes earlier installs).
DOTNET_ROLL_FORWARD=LatestMajor "$DOTNET_ROOT/dotnet" \
  "$GAMEDIR/tools/MainlineGameDataPatcher/MainlineGameDataPatcher.dll" \
  --patch-steamkit "$DD_DIR/SteamKit2.dll" \
  || { echo "Failed to patch SteamKit2 for Haiku." >&2; exit 1; }

# --- log in & download ----------------------------------------------------------
login_args=()
if [ "$use_qr" = 1 ]; then
  login_args=(-qr)
else
  saved_user_file="$GAMEDIR/tools/.steam-user"
  saved_user="$(cat "$saved_user_file" 2>/dev/null || true)"
  if [ -n "$saved_user" ]; then
    read -r -p "Steam username [$saved_user]: " steam_user
    steam_user="${steam_user:-$saved_user}"
  else
    read -r -p "Steam username: " steam_user
  fi
  [ -n "$steam_user" ] || { echo "No username given." >&2; exit 1; }
  login_args=(-username "$steam_user")

  read -r -p "Remember this Steam login on this computer? [Y/n] " remember
  case "${remember:-y}" in
    [Nn]*) ;;
    *) login_args+=(-remember-password); echo "$steam_user" > "$saved_user_file" ;;
  esac
  echo
  echo "DepotDownloader will now ask for your password and, if enabled,"
  echo "your Steam Guard code (or approve the login in the Steam app)."
fi

mkdir -p "$DEPOT_DIR"
echo
echo "Downloading Stardew Valley (Windows build, ~700 MB) into steam-depot/ ..."
dd_cmd=("$DOTNET_ROOT/dotnet" "$DD_DIR/DepotDownloader.dll"
  -app "$APP_ID" -os windows -osarch 64
  -dir "$DEPOT_DIR"
  -max-downloads "${SDV_MAX_DOWNLOADS:-8}"
  "${login_args[@]}")
[ -n "${SDV_DD_TEST_CMD:-}" ] && read -r -a dd_cmd <<< "$SDV_DD_TEST_CMD"   # test hook

# Downloads on Haiku can stall: no errors, no progress. DepotDownloader
# resumes cleanly, so a watchdog restarts it when steam-depot/ stops growing.
# It only arms once the size has changed during this attempt, so it never
# fires while you're typing a password or Steam Guard code.
STALL_SECONDS="${SDV_STALL_SECONDS:-180}"
POLL_SECONDS="${SDV_POLL_SECONDS:-15}"
MAX_ATTEMPTS="${SDV_MAX_ATTEMPTS:-6}"
state_dir="$(mktemp -d)"

depot_size() { du -sk "$DEPOT_DIR" 2>/dev/null | awk '{print $1}'; }

watchdog() {
  local last size armed=0 still=0
  last="$(depot_size)"
  while sleep "$POLL_SECONDS"; do
    [ -f "$state_dir/pid" ] || continue
    size="$(depot_size)"
    if [ "$size" != "$last" ]; then
      armed=1; still=0; last="$size"
    elif [ "$armed" = 1 ]; then
      still=$((still + POLL_SECONDS))
      if [ "$still" -ge "$STALL_SECONDS" ]; then
        touch "$state_dir/stalled"
        local pid; pid="$(cat "$state_dir/pid")"
        kill "$pid" 2>/dev/null
        # escalate if it ignores SIGTERM
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || return; sleep 1; done
        kill -KILL "$pid" 2>/dev/null
        return
      fi
    fi
  done
}

attempt=1
while :; do
  rm -f "$state_dir/pid" "$state_dir/stalled"
  watchdog &
  watchdog_pid=$!
  set +e
  # Foreground subshell keeps the terminal for prompts; exec keeps its PID.
  ( echo "$BASHPID" > "$state_dir/pid"; exec "${dd_cmd[@]}" )
  status=$?
  set -e
  kill "$watchdog_pid" 2>/dev/null; wait "$watchdog_pid" 2>/dev/null || true

  if [ -f "$state_dir/stalled" ] && [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
    attempt=$((attempt + 1))
    echo
    echo "Download stalled for ${STALL_SECONDS}s; restarting (attempt $attempt of $MAX_ATTEMPTS). It resumes where it left off."
    continue
  fi
  break
done
stalled=0; [ -f "$state_dir/stalled" ] && stalled=1
rm -rf "$state_dir"
if [ "$status" -ne 0 ]; then
  echo "DepotDownloader exited with status $status." >&2
  [ "$stalled" = 1 ] && echo "It kept stalling. Try: SDV_MAX_DOWNLOADS=2 ./get-game-steam.sh" >&2
  exit "$status"
fi

[ -f "$DEPOT_DIR/Stardew Valley.dll" ] || {
  echo "Download finished but 'Stardew Valley.dll' is missing. Is the Steam account the owner of the game?" >&2
  exit 1
}

# --- refresh gamedata/ from the pristine download --------------------------------
echo "Copying game files into gamedata/ ..."
rm -rf "$GAMEDIR/gamedata"
mkdir -p "$GAMEDIR/gamedata"
( cd "$DEPOT_DIR" && tar --exclude=./.DepotDownloader -cf - . ) | ( cd "$GAMEDIR/gamedata" && tar -xf - )
# Forces StardewValley.sh to re-patch on next launch.
rm -f "$GAMEDIR/gamedata/.haiku-patched"

echo
echo "Done. Start the game with ./StardewValley.sh"
