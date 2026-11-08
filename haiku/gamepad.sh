#!/bin/bash
# Set up a game controller for Stardew Valley on Haiku.
#
#   ./gamepad.sh          list controllers; offer to map an unmapped one
#   ./gamepad.sh list     list controllers only
#   ./gamepad.sh map [N]  map controller N (default 0)
#   ./gamepad.sh test [N] show live input as the game sees it
#   ./gamepad.sh raw [N]  show raw values SDL reads (diagnostics)
#
# Haiku's SDL identifies controllers only by name, so they don't match SDL's
# built-in controller database and the game ignores them until mapped. The
# mapping is saved in gamecontrollerdb.txt here; StardewValley.sh loads it.
# Plug the controller in before running this and before starting the game.

set -euo pipefail

GAMEDIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
# shellcheck source=sdv-paths
source "$GAMEDIR/sdv-paths"
TOOL="$GAMEDIR/libs/sdv-gamepad"
DB="$DATADIR/gamecontrollerdb.txt"

if [ ! -x "$TOOL" ]; then
  echo "The gamepad tool isn't built. Run ./setup.sh (it needs the libsdl2_devel package)." >&2
  exit 1
fi

cmd="${1:-}"
index="${2:-0}"
case "$cmd" in
  map)  exec "$TOOL" map "$DB" "$index" ;;
  test) exec "$TOOL" test "$DB" "$index" ;;
  raw)  exec "$TOOL" raw "$index" ;;
  list) SDL_GAMECONTROLLERCONFIG_FILE="$DB" exec "$TOOL" list ;;
  "")
    export SDL_GAMECONTROLLERCONFIG_FILE="$DB"
    "$TOOL" list || exit 1
    echo
    read -r -p "Map a controller now? Enter its number, or press Enter to skip: " pick
    [ -n "$pick" ] || exit 0
    "$TOOL" map "$DB" "$pick" && "$TOOL" test "$DB" "$pick"
    ;;
  *) sed -n 2,13p "$0"; exit 2 ;;
esac
