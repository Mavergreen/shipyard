#!/bin/sh
# platform: host-agnostic
#   usage: build_universal.sh --source DIR --out DIR [--x86_64-preset NAME] [--arm64-preset NAME]
#          Builds the CMake project at --source twice, once per preset (x86_64 at minos 10.9, arm64 at
#          minos 11.0), installs each into its own staging directory, and merges the two trees into
#          --out with lipo-merge-tree.sh --require-archs "x86_64 arm64": identical files are copied,
#          Mach-O files lipo'd, and any other difference refuses the merge. The presets default to
#          the names products give them: --x86_64-preset to x86_64, --arm64-preset to arm64. --out
#          must not exist; it is left absent on failure. CMAKE names the cmake (default:
#          shipyard-cmake, else cmake). An unset TMPDIR becomes /tmp, and an unset
#          MAVERICKS_BUILD_ROOT becomes $TMPDIR/mm-build, where the presets put each build directory.
#          Build logs go to stderr; --out's path is the only line on stdout. Exit 0 on success, 1 on
#          a failed build or merge, 2 on a usage error or an existing --out.
# platform: a modern host builds both slices; a 10.9 host cannot build arm64, so there it fails at
#           the arm64 configure.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
SY="$(dirname "$SELF")"
usage() {
  echo "usage: build_universal.sh --source DIR --out DIR [--x86_64-preset NAME] [--arm64-preset NAME]" >&2
  exit 2
}
die() { echo "build_universal: $*" >&2; exit 1; }
src=""; out=""; xp=x86_64; ap=arm64
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage
  case "$1" in
    --source) src=$2 ;;
    --out) out=$2 ;;
    --x86_64-preset) xp=$2 ;;
    --arm64-preset) ap=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$src" ] && [ -n "$out" ] || usage
[ -d "$src" ] || { echo "build_universal: no source directory $src" >&2; usage; }
[ ! -e "$out" ] && [ ! -L "$out" ] || { echo "build_universal: $out already exists" >&2; exit 2; }
src="$(cd "$src" && pwd)"
case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac

CMAKE="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
[ -n "${TMPDIR:-}" ] || TMPDIR=/tmp
[ -n "${MAVERICKS_BUILD_ROOT:-}" ] || MAVERICKS_BUILD_ROOT="${TMPDIR%/}/mm-build"
export TMPDIR MAVERICKS_BUILD_ROOT
CL="$(sh "$SELF/fetch_clang22.sh" "$SY/components/clang22")" || die "could not fetch the pinned clang22"
LIPO="$CL/bin/llvm-lipo"
export LIPO
work="$(mktemp -d "${TMPDIR%/}/universal.XXXXXX")" || die "cannot make a work directory under $TMPDIR"
trap 'rm -rf "$work"' EXIT

for pair in "x86_64 $xp" "arm64 $ap"; do
  arch="${pair% *}"; preset="${pair#* }"
  rc=0
  ( cd "$src" && "$CMAKE" --preset "$preset" ) > "$work/$arch.configure" 2>&1 || rc=$?
  cat "$work/$arch.configure" >&2
  [ "$rc" -eq 0 ] || die "the $arch preset '$preset' did not configure"
  bdir="$(sed -n 's/^-- Build files have been written to: //p' "$work/$arch.configure" | tail -n 1)"
  [ -n "$bdir" ] && [ -d "$bdir" ] || die "the $arch configure named no build directory"
  "$CMAKE" --build "$bdir" >&2 || die "the $arch preset '$preset' did not build"
  "$CMAKE" --install "$bdir" --prefix "$work/$arch" >&2 || die "the $arch preset '$preset' did not install"
done

sh "$SELF/lipo-merge-tree.sh" --a "$work/x86_64" --b "$work/arm64" --out "$out" \
  --require-archs "x86_64 arm64" >&2 || die "could not merge the x86_64 and arm64 builds into $out"
printf '%s\n' "$out"
