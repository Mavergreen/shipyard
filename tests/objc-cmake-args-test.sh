#!/bin/sh
# platform: host-agnostic
#   usage: objc-cmake-args-test.sh
#          objc_cmake passes each ObjC configure argument to cmake as one word, so a ROOT whose path
#          has a space still names its toolchain file.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/objc-cmake-args.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/a b"; ln -s "$root" "$w/a b/root"
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$w/cmake"; chmod +x "$w/cmake"
. "$here/lib/objc-cmake-args.sh"
CMAKE="$w/cmake"
objc_cmake_args "$w/a b/root"
out="$(objc_cmake -S "$w/src" -B "$w/b")"
printf '%s\n' "$out" | grep -qxF -- "-DCMAKE_TOOLCHAIN_FILE=$w/a b/root/MavergreenToolchain.cmake" \
  || { echo "FAIL: the toolchain file did not reach cmake as one argument:"; printf '%s\n' "$out" | sed 's/^/    | /'; exit 1; }
printf '%s\n' "$out" | grep -qxF -- "-S" || { echo "FAIL: the caller's own arguments did not reach cmake"; exit 1; }
echo "PASS: objc-cmake-args"
