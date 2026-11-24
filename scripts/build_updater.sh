#!/bin/sh
# platform: host-agnostic
#   usage: build_updater.sh --product SHORT --display-name NAME --confirm-title TITLE --confirm-body BODY
#                           --pubkey FILE --version VERSION --repo ROOT --arch x86_64|arm64 [--arch ...]
#                           (--icon ICNS | --generic-icon) --out-dir DIR
#                           [--log-prefix PREFIX] [--relaunch-marker PATH]
#          Builds SHORT's Sparkle updater, SHORT-updater.app, from shipyard's own updater sources
#          (updater/product/CMakeLists.txt, mavericks_add_updater_app) on Linux, a modern Mac and 10.9
#          alike: one configure per --arch through MavergreenToolchain.cmake with the clang22 release
#          ROOT/.mavergreen/ingredients/clang22 pins (through fetch_clang22.sh), x86_64 at minos 10.9 and
#          arm64 at minos 11.0. Two arches are merged by lipo-merge-tree.sh with llvm-lipo; which arches
#          to build is the product's decision, never this script's. ROOT is the product's repo: SHORT
#          must be declared in ROOT/.mavergreen/products/SHORT/, which derives the bundle id and feed.
#          --clang22-pin DIR, v1.0.859's form, is a deprecated alias for --repo: DIR/VERSION (or
#          DIR/version) names the clang22 release, and SHORT must be declared in the repo the current
#          directory is in (mg_dir). It says so on stderr; it goes when the maintainer retires it.
#          DIR/SHORT-updater.app is replaced, and its path is the only line on stdout; the build logs go
#          to stderr. CMAKE names the cmake (default: shipyard-cmake, else cmake). Work goes under
#          ${MAVERGREEN_BUILD_ROOT:-$TMPDIR/mavergreen-build} and is removed. Exit 1 on a failed build, 2 on a
#          usage error.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
SY="$(dirname "$SELF")"
. "$SELF/mavergreen-meta.sh"
usage() {
  echo "usage: build_updater.sh --product SHORT --display-name NAME --confirm-title TITLE --confirm-body BODY --pubkey FILE --version VERSION --repo ROOT --arch x86_64|arm64 [--arch ...] (--icon ICNS | --generic-icon) --out-dir DIR [--log-prefix PREFIX] [--relaunch-marker PATH]" >&2
  exit 2
}
die() { echo "build_updater: $*" >&2; exit 1; }
abs() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; }
cr=""; product=""; name=""; title=""; body=""; pubkey=""; version=""; pin=""; cpin=""; archs=""; icon=""; generic=""; out=""
logp=""; marker=""; have_logp=""; have_marker=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --generic-icon) generic=1; shift; continue ;;
    --*) [ "$#" -ge 2 ] || usage ;;
    *) usage ;;
  esac
  case "$1" in
    --product) product=$2 ;;
    --display-name) name=$2 ;;
    --confirm-title) title=$2 ;;
    --confirm-body) body=$2 ;;
    --pubkey) pubkey=$2 ;;
    --version) version=$2 ;;
    --repo) pin=$2 ;;
    --clang22-pin) cpin=$2 ;;
    --arch)
      case "$2" in x86_64|arm64) ;; *) echo "build_updater: --arch is x86_64 or arm64, not '$2'" >&2; usage ;; esac
      case " $archs " in *" $2 "*) echo "build_updater: --arch $2 given twice" >&2; usage ;; esac
      archs="$archs $2" ;;
    --icon) icon=$2 ;;
    --out-dir) out=$2 ;;
    --log-prefix) logp=$2; have_logp=1 ;;
    --relaunch-marker) marker=$2; have_marker=1 ;;
    *) usage ;;
  esac
  shift 2
done
[ -z "$pin" ] || [ -z "$cpin" ] || { echo "build_updater: pass --repo or --clang22-pin, not both" >&2; usage; }
[ -n "$pin$cpin" ] || { echo "build_updater: missing --repo" >&2; usage; }
for v in product name title body pubkey version archs out; do
  eval "[ -n \"\$$v\" ]" || { echo "build_updater: missing $v" >&2; usage; }
done
[ -n "$icon$generic" ] && { [ -z "$icon" ] || [ -z "$generic" ]; } \
  || { echo "build_updater: pass exactly one of --icon ICNS and --generic-icon" >&2; usage; }
case "$product" in *[!a-z0-9-]*|-*) echo "build_updater: '$product' is not a product short name" >&2; usage ;; esac
[ -f "$pubkey" ] || die "no public key file $pubkey"
if [ -n "$cpin" ]; then
  echo "build_updater: --clang22-pin is deprecated; pass --repo ROOT, the repo whose .mavergreen/ingredients/clang22 pins clang22" >&2
  cv="$(sed -n 1p "$cpin/VERSION" 2>/dev/null || sed -n 1p "$cpin/version" 2>/dev/null || :)"
  [ -n "$cv" ] || die "$cpin holds no VERSION or version naming a clang22 release"
  md="$(mg_dir)" || die "--clang22-pin needs the current directory in a repo with .mavergreen/; pass --repo ROOT"
  MAVERGREEN_REPO_ROOT="${md%/.mavergreen}"; export MAVERGREEN_REPO_ROOT
  [ -d "$md/products/$product" ] || die "$MAVERGREEN_REPO_ROOT declares no product $product in .mavergreen/products/"
  cr="$(mktemp -d "${TMPDIR:-/tmp}/build-updater-pin.XXXXXX")" || die "cannot make a directory for the clang22 pin"
  trap 'rm -rf "$cr"' EXIT
  mkdir -p "$cr/.mavergreen/ingredients" && cp -R "$SY/.mavergreen/ingredients/clang22" "$cr/.mavergreen/ingredients/" \
    && printf '%s\n' "$cv" > "$cr/.mavergreen/ingredients/clang22/VERSION" \
    || die "cannot write the clang22 pin under $cr from $SY/.mavergreen/ingredients/clang22"
  pin="$cr"
else
  [ -d "$pin/.mavergreen/products/$product" ] || die "$pin declares no product $product in .mavergreen/products/"
  pin="$(cd "$pin" && pwd)"; MAVERGREEN_REPO_ROOT="$pin"; export MAVERGREEN_REPO_ROOT
fi
[ -z "$icon" ] || [ -f "$icon" ] || die "no icon $icon"
pubkey="$(abs "$pubkey")"; [ -z "$icon" ] || icon="$(abs "$icon")"

CMAKE="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
CL="$(MAVERGREEN_REPO_ROOT="$pin" sh "$SELF/fetch_clang22.sh" "$pin")" || die "could not fetch the clang22 that $pin/.mavergreen/ingredients/clang22 pins"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
export LIPO OTOOL NM STRINGS
_tmp="${TMPDIR:-/tmp}"
root="${MAVERGREEN_BUILD_ROOT:-${_tmp%/}/mavergreen-build}"
mkdir -p "$root" "$out" || die "cannot make $root or $out"
out="$(cd "$out" && pwd)"
work="$(mktemp -d "$root/$product-updater.XXXXXX")" || die "cannot make a work directory under $root"
trap 'rm -rf "$work" ${cr:+"$cr"}' EXIT

cm() {
  case "$2" in *']==]'*) die "$1 holds ']==]', which the updater's arguments file cannot quote" ;; esac
  printf 'set(UPDATER_%s [==[%s]==])\n' "$1" "$2"
}
{
  cm PRODUCT "$product"; cm DISPLAY_NAME "$name"; cm CONFIRM_TITLE "$title"; cm CONFIRM_BODY "$body"
  cm PUBKEY_FILE "$pubkey"; cm VERSION "$version"; cm ICON "$icon"
  [ -z "$have_logp" ] || cm LOG_PREFIX "$logp"
  [ -z "$have_marker" ] || cm RELAUNCH_MARKER "$marker"
} > "$work/args.cmake"

app="$product-updater.app"
for a in $archs; do
  case "$a" in x86_64) floor=10.9 ;; arm64) floor=11.0 ;; esac
  "$CMAKE" -S "$SY/updater/product" -B "$work/$a" -DUPDATER_ARGS_FILE="$work/args.cmake" \
    -DCMAKE_TOOLCHAIN_FILE="$SY/MavergreenToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES="$a" \
    -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET="$a-apple-macos$floor" \
    -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld >&2 \
    || die "the $a updater of $product did not configure"
  "$CMAKE" --build "$work/$a" -v >&2 || die "the $a updater of $product did not build"
  [ -d "$work/$a/$app" ] || die "the $a build made no $app"
done
rm -rf "${out:?}/$app"
case "$archs" in
  " x86_64" | " arm64") cp -R "$work/${archs# }/$app" "$out/$app" || die "cannot copy $app to $out" ;;
  *) sh "$SELF/lipo-merge-tree.sh" --a "$work/x86_64/$app" --b "$work/arm64/$app" \
       --out "$out/$app" --require-archs "x86_64 arm64" >&2 || die "could not merge the x86_64 and arm64 updaters" ;;
esac
printf '%s\n' "$out/$app"
