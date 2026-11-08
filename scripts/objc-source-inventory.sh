#!/bin/sh
# platform: host-agnostic -- x86_64 Linux (Recaulk's release host) or a Mac; the receipt is the same on both
#   usage: objc-source-inventory.sh [--clang-prefix PREFIX] --inputs FILE --root DIR [--root DIR ...]
#                                   --unit LABEL [--unit LABEL ...] [--include LABELDIR ...] --output NEW_FILE
#          Writes the Objective-C source receipt (tools/objc-source-inventory.c header) for the
#          prepared provider source FILE lists (`SHA256  LABEL` lines, as Recaulk's build records
#          them), found under the --root directories, to NEW_FILE. PREFIX is the pinned clang
#          (components/objc-reference-clang), fetched through fetch_clang22.sh when not given; the
#          tool is built here against its libclang (on a Mac with /usr/bin/clang and the pinned host
#          SDK, on Linux with PREFIX's clang) and parses against the pinned floor SDK. Generation only: the
#          analyzer reads the receipt and never loads libclang. Nothing supplied is executed.
#          Exit 0 written, 2 usage or an existing destination, 4 a prerequisite, an unverifiable
#          input or a parse failure.
set -eu
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT CCC_OVERRIDE_OPTIONS
LC_ALL=C
export LC_ALL
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fail() { echo "objc-source-inventory: $*" >&2; exit 4; }
usage() { echo 'usage: objc-source-inventory.sh [--clang-prefix PREFIX] --inputs FILE --root DIR [--root DIR ...] --unit LABEL [--unit LABEL ...] [--include LABELDIR ...] --output NEW_FILE' >&2; exit 2; }
prefix=
n=0
for a in "$@"; do
  n=$((n + 1))
  # platform: odd positions are option names; the tool validates values and repeats.
  if [ $((n % 2)) = 1 ]; then
    case "$a" in --clang-prefix|--inputs|--root|--unit|--include|--output) ;; *) usage ;; esac
  fi
done
[ $((n % 2)) = 0 ] && [ "$n" -ge 8 ] || usage
remaining=$#
while [ "$remaining" -gt 0 ]; do
  case "$1" in
    --clang-prefix) [ -z "$prefix" ] || usage; prefix=$2; shift 2 ;;
    *) option=$1; value=$2; shift 2; set -- "$@" "$option" "$value" ;;
  esac
  remaining=$((remaining - 2))
done
case "$(uname -s)/$(uname -m)" in
  Darwin/x86_64) host=mac; arch=x86_64; floor=10.9; lib=libclang.dylib ;;
  Darwin/arm64) host=mac; arch=arm64; floor=11.0; lib=libclang.dylib ;;
  Linux/x86_64) host=linux; lib=libclang.so ;;
  *) fail "unsupported host: $(uname -s) $(uname -m)" ;;
esac
if [ -z "$prefix" ]; then
  prefix=$(sh "$HERE/fetch_clang22.sh" "$HERE/../components/objc-reference-clang") || fail 'cannot fetch the pinned reference clang'
fi
[ -x "$prefix/bin/clang" ] || fail "missing compiler: $prefix/bin/clang"
[ -r "$prefix/include/clang-c/Index.h" ] && [ -r "$prefix/lib/$lib" ] || fail 'missing libclang headers/library'
resource=$("$prefix/bin/clang" -print-resource-dir) || fail 'cannot query compiler resource directory'
[ -d "$resource/include" ] || fail "missing compiler resource directory: $resource"
# spec: tools/objc-source-inventory.c header -- the profile parses against the floor SDK Recaulk's build uses.
floor_sdk=$(sh "$HERE/fetch_sdk.sh" --arch x86_64) || fail 'cannot fetch the pinned floor SDK'
src="$HERE/../tools/objc-source-inventory.c"
if command -v sha256sum >/dev/null 2>&1; then tool_id=$(sha256sum "$src" | cut -c1-64); else tool_id=$(shasum -a 256 "$src" | cut -c1-64); fi
root=${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}
mkdir -p "$root" || fail 'cannot create build root'
build=$(mktemp -d "$root/objc-source-inventory.XXXXXX") || fail 'cannot create build directory'
trap 'rm -rf "$build"' EXIT
if [ "$host" = mac ]; then
  host_sdk=$(sh "$HERE/fetch_sdk.sh" --arch "$arch") || fail 'cannot fetch the pinned host SDK'
  env -i PATH=/usr/bin:/bin /usr/bin/clang -std=c99 -Wall -Wextra -Werror -arch "$arch" -mmacosx-version-min="$floor" \
    -isysroot "$host_sdk" -I"$prefix/include" "$src" \
    -L"$prefix/lib" -Xlinker -rpath -Xlinker "$prefix/lib" -lclang -o "$build/objc-source-inventory" || fail 'host producer build failed'
else
  # platform: the archive's libclang.so links LLVM statically and needs only glibc; the rpath finds it.
  env -i PATH=/usr/bin:/bin "$prefix/bin/clang" -std=c99 -Wall -Wextra -Werror -I"$prefix/include" "$src" \
    -L"$prefix/lib" -Wl,-rpath,"$prefix/lib" -lclang -o "$build/objc-source-inventory" || fail 'host producer build failed'
fi
rc=0
"$build/objc-source-inventory" --resource-dir "$resource" --sdk "$floor_sdk" --tool-id "$tool_id" "$@" || rc=$?
case "$rc" in 0|2|4) exit "$rc" ;; *) fail "producer failed (exit $rc)" ;; esac
