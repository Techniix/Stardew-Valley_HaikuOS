#!/bin/bash
# Download your own copy of Stardew Valley from Steam, directly on Haiku.
#
#   ./get-game-steam.sh            log in with username (+ password / Steam Guard prompts)
#   ./get-game-steam.sh --qr       log in by scanning a QR code with the Steam mobile app
#   ./get-game-steam.sh --update   same as above; re-downloads only changed files
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
"$DOTNET_ROOT/dotnet" "$DD_DIR/DepotDownloader.dll" \
  -app "$APP_ID" -os windows -osarch 64 \
  -dir "$DEPOT_DIR" \
  "${login_args[@]}"

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
