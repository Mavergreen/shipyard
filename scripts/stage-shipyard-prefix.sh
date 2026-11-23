#!/bin/sh
# platform: host-agnostic
#   usage: stage-shipyard-prefix.sh --stage DIR --build DIR [--prefix P] [--version V]
#          Configures this checkout in --build and installs it under DESTDIR=--stage with --prefix P
#          (default /usr/local/mavergreen/shipyard), so the presets name P's toolchain file. Prints
#          the staged prefix, DIR/P. --version sets SHIPYARD_FULL_VERSION; without it CMakeLists.txt
#          derives one. CMAKE names the cmake to run (default cmake). The one staging of shipyard's
#          prefix: the pkg (release.yml, ci.yml) and install@v1 on Linux both start from it.
# spec: tests/linux-shipyard-prefix-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"; SRC="${SELF%/*}"
ST=""; B=""; P=/usr/local/mavergreen/shipyard; V=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage|--build|--prefix|--version)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "stage-shipyard-prefix: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --stage) ST="${2%/}"; shift 2 ;;
    --build) B="${2%/}"; shift 2 ;;
    --prefix) P="${2%/}"; shift 2 ;;
    --version) V="$2"; shift 2 ;;
    *) echo "stage-shipyard-prefix: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$ST" ] && [ -n "$B" ] || { echo "usage: stage-shipyard-prefix.sh --stage DIR --build DIR [--prefix P] [--version V]" >&2; exit 2; }
case "$P" in /*) : ;; *) echo "stage-shipyard-prefix: --prefix must be absolute: $P" >&2; exit 2 ;; esac
CM="${CMAKE:-cmake}"
command -v "$CM" > /dev/null 2>&1 || { echo "stage-shipyard-prefix: no $CM to stage shipyard with" >&2; exit 1; }
set -- -S "$SRC" -B "$B"
[ -z "$V" ] || set -- "$@" "-DSHIPYARD_FULL_VERSION=$V"
"$CM" "$@" >&2 || { echo "stage-shipyard-prefix: configuring $SRC failed" >&2; exit 1; }
DESTDIR="$ST" "$CM" --install "$B" --prefix "$P" >&2 || { echo "stage-shipyard-prefix: installing into $ST$P failed" >&2; exit 1; }
printf '%s\n' "$ST$P"
