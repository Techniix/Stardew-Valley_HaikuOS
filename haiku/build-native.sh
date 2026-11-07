#!/bin/bash
# Build the native shims on Haiku. Run this on the Haiku machine.
#   ./build-native.sh [output-dir]      (default: ./libs next to this script)
#
# Needs gcc (pkgman install gcc haiku_devel) and SDL2 at runtime
# (pkgman install libsdl2 openal).

set -euo pipefail

HERE="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
SRC="${SDV_NATIVE_SRC:-"$HERE/native-src"}"
[ -d "$SRC" ] || SRC="$HERE/../build/src/native"
OUT="${1:-"$HERE/libs"}"

[ "$(uname -s)" = "Haiku" ] || echo "warning: not running on Haiku; output will not load there" >&2
command -v gcc >/dev/null || { echo "gcc not found: pkgman install gcc haiku_devel" >&2; exit 1; }

mkdir -p "$OUT"
cflags=(-shared -fPIC -O2 -s)

build_shim() {
  local source="$1" output="$2"; shift 2
  echo "  CC $output"
  gcc "${cflags[@]}" -o "$OUT/$output" "$SRC/$source" "$@"
}

# Haiku keeps dlopen/dlsym in libroot, so no -ldl.
# .NET probes both "name" and "libname.so" style names, so provide both.
build_shim imm32_shim.c libImm32.dll.so
build_shim user32_shim.c libuser32.dll.so
build_shim sdl2_clipboard_shim.c libSDL2.dll.so
build_shim steam_api64_stub.c libsteam_api64.so
build_shim sdkencryptedappticket64_stub.c libsdkencryptedappticket64.so

( cd "$OUT"
  ln -sf libImm32.dll.so Imm32.dll
  ln -sf libuser32.dll.so user32.dll
  ln -sf libSDL2.dll.so SDL2.dll )

echo "Native shims written to $OUT"
