#!/bin/bash
# One-time setup for Stardew Valley on Haiku. Run it from Terminal:
#
#   ./setup.sh             interactive
#   ./setup.sh --yes       accept all defaults (still asks for your Steam login)
#   ./setup.sh --no-game   set everything up but don't download the game
#
# Steps:
#   1. install system packages from HaikuPorts (SDL2, OpenAL, gcc, .NET deps)
#   2. install .NET for Haiku (trungnt2910/dotnet-builds) into ./dotnet,
#      unless a .NET 9+ runtime is already installed
#   3. build the native shims (./libs)
#   4. download the game from Steam (get-game-steam.sh), or tell you where to copy it
#   5. add a Deskbar menu entry
#
# Safe to re-run: finished steps are skipped.

set -euo pipefail

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
cd "$GAMEDIR"

DOTNET_CHANNEL="10.0"
# Pinned revision of trungnt2910's installer script.
DOTNET_INSTALLER_URL="https://raw.githubusercontent.com/trungnt2910/dotnet-builds/28db594b9730d47e6817adc44bf1bee084707e4c/dotnet-install.sh"

assume_yes=0
get_game=1
for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    --no-game) get_game=0 ;;
    -h|--help) sed -n 2,18p "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ask() {  # ask "question" default(y/n)
  local answer
  if [ "$assume_yes" = 1 ]; then [ "$2" = y ]; return; fi
  read -r -p "$1 [$( [ "$2" = y ] && echo Y/n || echo y/N )] " answer
  answer="${answer:-$2}"
  [[ "$answer" =~ ^[Yy] ]]
}

[ "$(uname -s)" = "Haiku" ] || { echo "This script must be run on Haiku." >&2; exit 1; }
arch="$(getarch 2>/dev/null || uname -m)"
[ "$arch" = "x86_64" ] || { echo "Only x86_64 Haiku is supported (this is $arch)." >&2; exit 1; }

# --- 1. packages ----------------------------------------------------------------
step "1/5 System packages"
packages=(
  libsdl2 openal                                   # used by MonoGame
  libsdl2_devel                                    # to build the gamepad tool
  gcc haiku_devel                                  # to build the native shims
  gmp krb5 libiconv llvm12_libunwind mpfr          # needed by .NET on Haiku
  jq curl unzip                                    # used by the installers
)
if [ "$PACKAGED" = 1 ]; then
  echo "Installed as a Haiku package: pkgman already installed what it needs."
else
  echo "Installing: ${packages[*]}"
  pkgman install -y "${packages[@]}"
fi

# --- 2. .NET ------------------------------------------------------------------------
step "2/5 .NET runtime"
find_dotnet() {
  for d in "${DOTNET_ROOT:-}" "$GAMEDIR/dotnet" "$HOME/.dotnet"; do
    [ -n "$d" ] && [ -x "$d/dotnet" ] && { echo "$d"; return; }
  done
  command -v dotnet >/dev/null 2>&1 && dirname -- "$(readlink -f "$(command -v dotnet)")"
}
newest_major() {
  "$1/dotnet" --list-runtimes 2>/dev/null \
    | awk '/Microsoft.NETCore.App/ {split($2,v,"."); print v[1]}' | sort -n | tail -n 1
}

dotnet_root="$(find_dotnet || true)"
major="$( [ -n "$dotnet_root" ] && newest_major "$dotnet_root" || true )"
if [ -n "$major" ] && [ "$major" -ge 9 ]; then
  echo ".NET $major found in $dotnet_root, skipping."
else
  [ -n "$major" ] && echo "Found .NET $major, but 9 or newer is needed."
  echo "Installing .NET $DOTNET_CHANNEL for Haiku into $GAMEDIR/dotnet (~200 MB)..."
  installer="$(mktemp)"
  curl -fsSL "$DOTNET_INSTALLER_URL" -o "$installer"
  mkdir -p "$GAMEDIR/dotnet"
  bash "$installer" --channel "$DOTNET_CHANNEL" --install-dir "$GAMEDIR/dotnet"
  rm -f "$installer"
  dotnet_root="$GAMEDIR/dotnet"
  major="$(newest_major "$dotnet_root")"
  [ -n "$major" ] || { echo ".NET install failed: no runtime in $dotnet_root" >&2; exit 1; }
  echo ".NET $major installed."
fi
export DOTNET_ROOT="$dotnet_root"

# --- 3. native shims ------------------------------------------------------------------
step "3/5 Native shims"
if [ "$PACKAGED" = 1 ]; then
  echo "Included in the package."
elif [ -f "$GAMEDIR/libs/.built" ] && [ -z "$(find "$GAMEDIR/native-src" -newer "$GAMEDIR/libs/.built" -print -quit)" ]; then
  echo "Already built, skipping."
else
  "$GAMEDIR/build-native.sh" "$GAMEDIR/libs"
fi

# --- 4. game files ---------------------------------------------------------------------
step "4/5 Game files"
if [ -f "$DATADIR/gamedata/Stardew Valley.dll" ]; then
  echo "Game files already present in gamedata/."
  if [ "$get_game" = 1 ] && [ -d "$DATADIR/steam-depot" ] && ask "Check Steam for a game update?" n; then
    "$GAMEDIR/get-game-steam.sh" --update
  fi
elif [ "$get_game" = 1 ] && ask "Download Stardew Valley from Steam now? (you must own it)" y; then
  if ask "Log in with a QR code from the Steam mobile app instead of a password?" n; then
    "$GAMEDIR/get-game-steam.sh" --qr
  else
    "$GAMEDIR/get-game-steam.sh"
  fi
else
  echo "Copy your Stardew Valley 1.6 folder (the one with 'Stardew Valley.dll',"
  echo "Windows build from Steam or GOG) into:"
  echo "  $DATADIR/gamedata/"
fi

# --- gamepad (optional) ---------------------------------------------------------
if [ -x "$GAMEDIR/libs/sdv-gamepad" ]; then
  step "Gamepad (optional)"
  if SDL_GAMECONTROLLERCONFIG_FILE="$DATADIR/gamecontrollerdb.txt" \
      "$GAMEDIR/libs/sdv-gamepad" list 2>/dev/null | grep -q "NOT mapped"; then
    echo "A controller is connected but not set up for games yet."
    if ask "Map it now? (takes about a minute)" y; then
      "$GAMEDIR/gamepad.sh" || true
    else
      echo "You can do it later with ./gamepad.sh"
    fi
  else
    echo "No unmapped controller connected. Run ./gamepad.sh any time to set one up."
  fi
fi

# --- 5. Deskbar ----------------------------------------------------------------------------
step "5/5 Deskbar entry"
menu_dir="$(finddir B_USER_SETTINGS_DIRECTORY 2>/dev/null || echo "$HOME/config/settings")/deskbar/menu/Applications"
entry="$menu_dir/Stardew Valley"
if [ "$PACKAGED" = 1 ]; then
  echo "The package already adds Stardew Valley to the Deskbar."
elif [ -L "$entry" ] && [ "$(readlink "$entry")" != "$GAMEDIR/StardewValley.sh" ]; then
  # Left over from an older copy (moved, replaced or in the Trash).
  ln -sf "$GAMEDIR/StardewValley.sh" "$entry"
  echo "Deskbar entry pointed at an old copy; updated it to this folder."
elif [ -e "$entry" ]; then
  echo "Already in the Deskbar menu."
elif ask "Add Stardew Valley to the Deskbar Applications menu?" y; then
  mkdir -p "$menu_dir"
  ln -sf "$GAMEDIR/StardewValley.sh" "$menu_dir/Stardew Valley"
  echo "Added."
fi

echo
echo "Setup complete. Start the game from the Deskbar or with ./StardewValley.sh"
