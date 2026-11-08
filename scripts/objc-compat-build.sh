#!/bin/sh
# platform: macOS-only -- compiles a host-native helper with the pinned clang22 against the pinned host SDK
#   usage: objc-compat-build.sh --reader-driver OUT | --analyzer OUT
#          --analyzer builds the objc-compat analyzer (tools/objc-compat/main.m, its Foundation JSON
#          front end, plus every module); --reader-driver the test harness that prints the reader/
#          binding records (tests/fixtures/objc-api/reader-driver.c). Either is built at OUT from tools/objc-compat
#          plus the read-only Drydock core modules it reuses (mi_*, mfat_*, mx_*, mo_bind_observe,
#          mrb_*, mml_*). It needs neither git nor Xcode's Command Line Tools (a 10.9 build host has
#          neither unless they are installed):
#          - Drydock is GitHub's tarball of the pinned commit (components/objc-reader-drydock/version
#            DIGEST), fetched by scripts/fetch_pinned_source.sh and verified against the pin's
#            ARCHIVE_SHA256 (fail closed), then extracted fresh into a private directory for this
#            build alone and removed after it: no shared tree exists to go stale or be edited, and
#            nothing else is ever compiled as Drydock. The tarball's tree is exactly the commit's
#            (checked with git where git is, when the pin moves).
#          - The compiler is the pinned clang22 package (components/objc-reference-clang/version:
#            mavericks-clang-22-native on x86_64, -cross on arm64), fetched by
#            scripts/fetch_product_pkg.sh, verified against its release's SHA256SUMS and extracted,
#            never installed, under ${MAVERGREEN_BUILD_ROOT:-$TMPDIR/mavergreen-build}; it runs with
#            --no-default-config (none of the package's own link defaults) and an environment
#            emptied to PATH=/bin, so CPATH and friends cannot reach it, against the pinned SDK for
#            this host's arch (scripts/fetch_sdk.sh), and links with its own ld64.lld.
#            MAVERGREEN_OBJC_CLANG_PREFIX names an already-extracted package instead.
#          Output is cached under ${MAVERGREEN_OBJC_COMPAT_CACHE:-BUILD_ROOT/objc-compat} by a key over
#          every source byte, the pins, the compiler's identity, the SDK and the arch; the last line on
#          stderr also gives the host-independent source identity ("... source KEY ...") that reports
#          carry, and names the toolchain ("toolchain clang22 VERSION at PREFIX,").
#          MAVERGREEN_SOURCE_CACHE and MAVERGREEN_CODELOAD reach fetch_pinned_source.sh, and
#          MAVERGREEN_PKG_CACHE and MAVERGREEN_RELEASES fetch_product_pkg.sh. The git-era
#          MAVERGREEN_OBJC_READER_SRC and MAVERGREEN_OBJC_READER_DRYDOCK_REPO are retired: set, they fail.
#          Exit 0 built, 2 usage, 4 a prerequisite or bootstrap failure -- never a skip.
set -eu
# platform: globs below feed the source identity; their order follows LC_COLLATE, and some locales
#           (en_US.UTF-8 on a modern host) sort linkedit_order.h before linkedit.h. Byte order only.
LC_ALL=C
export LC_ALL
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)

usage() { echo "usage: objc-compat-build.sh --reader-driver OUT | --analyzer OUT" >&2; exit 2; }
die() { echo "objc-compat: $*" >&2; exit 4; }
[ $# -eq 2 ] && [ -n "$2" ] || usage
case "$1" in
  --reader-driver) WHAT=reader-driver ;;
  --analyzer) WHAT=analyzer ;;
  *) usage ;;
esac
OUT=$2

PIN="$ROOT/components/objc-reader-drydock/version"
[ -r "$PIN" ] || die "missing pin $PIN"
REPO=$(sed -n 's/^REPO=//p' "$PIN")
REF=$(sed -n 's/^REF=//p' "$PIN")
DIGEST=$(sed -n 's/^DIGEST=//p' "$PIN")
ARCHIVE_SHA256=$(sed -n 's/^ARCHIVE_SHA256=//p' "$PIN")
printf '%s\n' "$DIGEST" | grep -Eq '^[0-9a-f]{40}$' || die "pin has no 40-hex DIGEST"
printf '%s\n' "$ARCHIVE_SHA256" | grep -Eq '^[0-9a-f]{64}$' || die "pin has no 64-hex ARCHIVE_SHA256"
[ -n "$REF" ] && [ -n "$REPO" ] || die "pin lacks REPO or REF"
[ -z "${MAVERGREEN_OBJC_READER_SRC:-}" ] && [ -z "${MAVERGREEN_OBJC_READER_DRYDOCK_REPO:-}" ] ||
  die "MAVERGREEN_OBJC_READER_SRC and MAVERGREEN_OBJC_READER_DRYDOCK_REPO are retired: Drydock comes only from its pinned, verified tarball"
BUILD_ROOT=${MAVERGREEN_BUILD_ROOT:-${TMPDIR:-/tmp}/mavergreen-build}
command -v shasum >/dev/null 2>&1 || die "shasum is required"

case "$(uname -m)" in
  x86_64) sdk_arch=x86_64; floor=10.9; short=clang22; flavor=native ;;
  arm64) sdk_arch=arm64; floor=11.0; short=clang22-cross; flavor=cross ;;
  *) die "unsupported host arch $(uname -m)" ;;
esac
CLANG_PIN="$ROOT/components/objc-reference-clang/version"
[ -r "$CLANG_PIN" ] || die "missing pin $CLANG_PIN"
CLANG_VERSION=$(tr -d '[:space:]' <"$CLANG_PIN")
[ -n "$CLANG_VERSION" ] || die "empty pin $CLANG_PIN"
if [ -n "${MAVERGREEN_OBJC_CLANG_PREFIX:-}" ]; then PREFIX=$MAVERGREEN_OBJC_CLANG_PREFIX
else
  PREFIX=$(sh "$ROOT/scripts/fetch_product_pkg.sh" --asset "mavericks-clang-22-$flavor-$CLANG_VERSION.pkg" "$short" "$CLANG_VERSION" \
           "$BUILD_ROOT/objc-reference-$short-$CLANG_VERSION") || die "cannot fetch and verify the pinned toolchain $short $CLANG_VERSION"
fi
[ -x "$PREFIX/bin/clang" ] || die "the toolchain $PREFIX has no bin/clang"

mkdir -p "$BUILD_ROOT/src" || die "cannot create $BUILD_ROOT/src"
PRIV=$(mktemp -d "$BUILD_ROOT/src/.drydock-$DIGEST.XXXXXX") || die "cannot create a private source directory"
trap 'rm -rf "$PRIV"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
SRC="$PRIV/drydock"
sh "$ROOT/scripts/fetch_pinned_source.sh" "$REPO" "$DIGEST" "$ARCHIVE_SHA256" "$SRC" 2>"$PRIV/fetch.log" ||
  { cat "$PRIV/fetch.log" >&2; die "cannot fetch and verify the pinned Drydock tarball ($DIGEST)"; }
[ "$(cat "$SRC/.mavergreen-source" 2>/dev/null)" = "$REPO $DIGEST $ARCHIVE_SHA256" ] || die "the Drydock tree at $SRC is not the pinned tarball's"

MODULES="image fat x86len ordinals uleb rebase objc_meth arch_names grow exports hdrref linkedit trie"
OURS="macho-reader binding reference report classify source-evidence provider"
if [ "$WHAT" = analyzer ]; then DRIVER="$ROOT/tools/objc-compat/main.m"; LINK="-framework Foundation"
else DRIVER="$ROOT/tests/fixtures/objc-api/reader-driver.c"; LINK=; fi
for m in $MODULES; do
  [ -f "$SRC/src/$m.c" ] || die "pinned Drydock lacks src/$m.c"
done
for f in "$ROOT/tools/objc-compat/report.h" "$DRIVER"; do [ -r "$f" ] || die "missing adapter source $f"; done
for m in $OURS; do [ -r "$ROOT/tools/objc-compat/$m.c" ] || die "missing adapter source tools/objc-compat/$m.c"; done

SDK=$(sh "$ROOT/scripts/fetch_sdk.sh" --arch "$sdk_arch") || die "pinned SDK fetch failed"
[ -d "$SDK/usr/include/mach-o" ] || die "pinned SDK $SDK has no Mach-O headers"

# platform: env -i drops CPATH, C_INCLUDE_PATH, SDKROOT, MACOSX_DEPLOYMENT_TARGET and every other
#           variable that could steer the compiler away from the pinned SDK and sources; PATH=/bin
#           holds no compiler, linker or xcrun, so the driver can reach only its own bin (ld64.lld).
#           --no-default-config skips the package's clang.cfg, which adds its own SDK and libraries.
case "$PREFIX" in *[[:space:]]*) die "a toolchain path with whitespace is not supported" ;; esac
CC="env -i PATH=/bin $PREFIX/bin/clang --no-default-config"
# platform: the analyzer's own copy of the source-receipt tool: source-evidence.c refuses a receipt
#           whose `tool` line is not this file's SHA-256, so the file is part of the source identity.
INVENTORY="$ROOT/tools/objc-source-inventory.c"
[ -r "$INVENTORY" ] || die "missing $INVENTORY"
INVENTORY_SHA=$(shasum -a 256 "$INVENTORY" | cut -c1-64)
FLAGS="-std=c99 -O2 -arch $(uname -m) -isysroot $SDK -mmacosx-version-min=$floor -Wall -DOBJC_SOURCE_INVENTORY_SHA256=\"$INVENTORY_SHA\""
sources() {
  printf '%s\n' "$DIGEST" "$WHAT"
  for m in $OURS; do cat "$ROOT/tools/objc-compat/$m.c"; done
  cat "$ROOT/tools/objc-compat/report.h" "$DRIVER" "$INVENTORY"
  for m in $MODULES; do cat "$SRC/src/$m.c"; done
  cat "$SRC"/src/*.h
}
# platform: two identities. `key` names this host's binary (compiler, SDK, arch, flags too) and keys
#           the cache; `srckey` names only the sources and the Drydock pin, so a Mavericks and an
#           arm64 host building the same tree report the same analyzer (tests/objc-report-test.sh).
srckey=$(sources | shasum -a 256 | cut -c1-16)
key=$( {
  printf '%s\n' "$SDK" "$(uname -m)" "$FLAGS" "$LINK"
  $CC --version 2>&1
  sources
} | shasum -a 256 | cut -c1-16)
CACHE="${MAVERGREEN_OBJC_COMPAT_CACHE:-$BUILD_ROOT/objc-compat}/$key"
if [ ! -x "$CACHE/$WHAT" ]; then
  mkdir -p "$CACHE"
  tmp="$CACHE/$WHAT.tmp.$$"
  srcs="$DRIVER"
  for m in $OURS; do srcs="$srcs $ROOT/tools/objc-compat/$m.c"; done
  for m in $MODULES; do srcs="$srcs $SRC/src/$m.c"; done
  # platform: word splitting of $srcs is intended; none of these paths contain whitespace
  #           unless MAVERGREEN_BUILD_ROOT or the checkout does, which the quoted -I paths survive
  #           but this list would not -- refuse rather than mis-split.
  case "$ROOT$SRC" in *[[:space:]]*) die "source paths with whitespace are not supported" ;; esac
  # platform: $LINK is empty or "-framework Foundation"; its word splitting is intended.
  $CC $FLAGS -I"$ROOT/tools/objc-compat" -I"$SRC/src" $srcs $LINK -o "$tmp" 2>"$CACHE/build.log" ||
    { cat "$CACHE/build.log" >&2; rm -f "$tmp"; die "compile failed"; }
  mv "$tmp" "$CACHE/$WHAT"
fi
mkdir -p "$(dirname -- "$OUT")"
cp "$CACHE/$WHAT" "$OUT"
echo "objc-compat: $WHAT $key source $srckey (drydock $DIGEST, toolchain $short $CLANG_VERSION at $PREFIX, $(uname -m), $SDK)" >&2
