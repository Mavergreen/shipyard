#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-cmake|shipyard-ctest|shipyard-cpack [ARG...]
#          Installed as <prefix>/shipyard/bin/shipyard-{cmake,ctest,cpack}; runs the cmake product's
#          <prefix>/cmake/bin/{cmake,ctest,cpack}. shipyard-cmake first appends <prefix>/shipyard to
#          CMAKE_PREFIX_PATH, so find_package(MavericksShipyard) finds it after any caller's entry.
#          Off Darwin, with no cmake product beside shipyard or a Mach-O one, it runs the first
#          {cmake,ctest,cpack} on PATH that is not a shipyard launcher or a link to one. SHIPYARD_LAUNCHER_HOST (linux or mac) replaces uname -s.
#          A tool that runs a launcher again before any other work (a stand-in cmake that execs
#          shipyard-cmake) is refused as a loop; MAVERGREEN_SHIPYARD_LAUNCHER_PID and
#          MAVERGREEN_SHIPYARD_LAUNCHER_DEPTH carry the guard. An unset or empty TMPDIR becomes /tmp.
# spec: 2026-10-09 C4
# platform: 10.9 has no realpath and no readlink -f, so links are followed one at a time.
resolve() {
  r="$1"
  case "$r" in */*) ;; *) r="./$r" ;; esac
  while [ -L "$r" ]; do
    link="$(readlink "$r")"
    case "$link" in
      /*) r="$link" ;;
      *) r="${r%/*}/$link" ;;
    esac
  done
}
resolve "$0"; self="$r"
case "${self##*/}" in
  shipyard-cmake) tool=cmake ;;
  shipyard-ctest) tool=ctest ;;
  shipyard-cpack) tool=cpack ;;
  *) echo "shipyard-launcher: install this as shipyard-cmake, shipyard-ctest or shipyard-cpack, not ${self##*/}" >&2; exit 2 ;;
esac
# platform: with CDPATH exported, cd searches it for a relative path and prints where it went.
bin="$(CDPATH= cd -P -- "${self%/*}" && pwd)"
shipyard="${bin%/*}"
exe="${shipyard%/*}/cmake/bin/$tool"
host="${SHIPYARD_LAUNCHER_HOST:-}"
[ -n "$host" ] || case "$(uname -s)" in Darwin) host=mac ;; *) host=linux ;; esac
# spec: tests/shipyard-launcher-test.sh -- the cmake product ships only Mach-O, so on Linux a
#       product beside shipyard runs only if it is not one; otherwise the host's cmake runs, as
#       MavericksShipyardConfig.cmake already accepts there.
macho() {
  case "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" in
    cffaedfe|cefaedfe|cafebabe|feedfacf|feedface) return 0 ;;
  esac
  return 1
}
if [ "$host" = linux ] && { [ ! -x "$exe" ] || macho "$exe"; }; then
  prod="$exe"; exe=""
  _ifs="$IFS"; IFS=:; set -f
  for d in $PATH; do
    [ -n "$d" ] && [ -x "$d/$tool" ] && [ ! -d "$d/$tool" ] || continue
    resolve "$d/$tool"
    case "${r##*/}" in shipyard-cmake|shipyard-ctest|shipyard-cpack) continue ;; esac
    ! cmp -s "$r" "$self" || continue
    exe="$d/$tool"; break
  done
  IFS="$_ifs"; set +f
  if [ -z "$exe" ]; then
    echo "shipyard-$tool: no $tool on PATH, and no Linux cmake product at ${prod%/*}: install your distribution's cmake package, then run this again." >&2
    exit 1
  fi
fi
if [ ! -x "$exe" ]; then
  echo "shipyard-$tool: shipyard needs the Mavergreen cmake product, which isn't installed: https://github.com/Mavergreen/cmake/releases/latest -- install it, then run this again." >&2
  exit 1
fi
depth="${MAVERGREEN_SHIPYARD_LAUNCHER_DEPTH:-0}"
case "$depth" in ''|*[!0-9]*) depth=0 ;; esac
if [ "${MAVERGREEN_SHIPYARD_LAUNCHER_PID:-}" = "$$" ] || [ "$depth" -ge 8 ]; then
  echo "shipyard-$tool: $exe runs a shipyard launcher again, a loop: a stand-in $tool must not exec shipyard-$tool, so put a real $tool first on PATH." >&2
  exit 1
fi
# spec: mavericks-presets.json -- MAVERICKS_BUILD_ROOT is $penv{TMPDIR}/mm-build, and GitHub's Linux
#       runners leave TMPDIR unset, which made it /mm-build.
[ -n "${TMPDIR:-}" ] || TMPDIR=/tmp
export TMPDIR
MAVERGREEN_SHIPYARD_LAUNCHER_PID=$$
MAVERGREEN_SHIPYARD_LAUNCHER_DEPTH=$((depth + 1))
export MAVERGREEN_SHIPYARD_LAUNCHER_PID MAVERGREEN_SHIPYARD_LAUNCHER_DEPTH
if [ "$tool" = cmake ]; then
  CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:+$CMAKE_PREFIX_PATH:}$shipyard"
  export CMAKE_PREFIX_PATH
fi
exec "$exe" "$@"
