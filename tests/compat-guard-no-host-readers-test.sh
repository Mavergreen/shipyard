#!/bin/sh
# platform: host-agnostic
#   usage: compat-guard-no-host-readers-test.sh
#          assert_binary_compatible.sh reads Mach-O through scripts/lib/mach-nm.sh, so with NM, OTOOL
#          and LIPO unexported and no nm, otool, lipo or strings on PATH (off macOS none reads Mach-O; on
#          macOS only nm is hidden, since Apple's lipo and otool are the macOS default) a clean tiny
#          binary passes and a post-10.9 import fails naming it. On a Mac whose lipo is a stub (no
#          Command Line Tools), PATH's lipo and otool are clang22's, as that Mac's guard runs would name.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
G="$here/../scripts/assert_binary_compatible.sh"
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/../components/clang22")"
S9="$(sh "$here/../scripts/fetch_sdk.sh")"
w="$(mktemp -d "${TMPDIR:-/tmp}/compat-noreaders.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cc() { "$CL/bin/clang" --no-default-config -w -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target x86_64-apple-macos10.9 -isysroot "$S9" -Wl,-platform_version,macos,10.9,10.9 "$@"; }
printf 'int main(void){return 0;}\n' > "$w/clean.c"
printf 'extern int mav_test_post109(void);\nint main(void){return mav_test_post109();}\n' > "$w/leak.c"
cc "$w/clean.c" -o "$w/clean"
cc -Wl,-undefined,dynamic_lookup "$w/leak.c" -o "$w/leak"
case "$(uname -s)" in
  Darwin) hide=nm ;;
  *) hide="nm otool lipo strings" ;;
esac
mkdir "$w/bin"
for d in /usr/bin /bin; do
  for f in "$d"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    n="${f##*/}"
    case " $hide " in *" $n "*) continue ;; esac
    [ -e "$w/bin/$n" ] || printf '#!/bin/sh\nexec %s "$@"\n' "$f" > "$w/bin/$n"
    chmod +x "$w/bin/$n"
  done
done
if [ "$(uname -s)" = Darwin ] && ! lipo -info "$w/clean" >/dev/null 2>&1; then
  for n in lipo otool; do printf '#!/bin/sh\nexec %s "$@"\n' "$CL/bin/llvm-$n" > "$w/bin/$n"; chmod +x "$w/bin/$n"; done
fi
# platform: a Linux without perl's shasum (ubuntu:24.04 base) still has sha256sum, which answers shasum -a 256 alike.
if [ ! -e "$w/bin/shasum" ]; then
  printf '#!/bin/sh\nshift 2\nexec sha256sum "$@"\n' > "$w/bin/shasum"; chmod +x "$w/bin/shasum"
fi
for n in $hide; do
  [ ! -e "$w/bin/$n" ] || { echo "FAIL: $n is still on the test PATH"; exit 1; }
done
run() { env -u LIPO -u NM -u OTOOL -u STRINGS PATH="$w/bin" "$@"; }
out="$(run sh "$G" "$w/clean" 2>&1)" || { echo "FAIL: a clean binary must pass with no host Mach-O readers:"; printf '%s\n' "$out" | sed 's/^/    | /'; exit 1; }
rc=0; out="$(run env MAVERICKS_POST_10_9_SYMBOLS=_mav_test_post109 sh "$G" "$w/leak" 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q _mav_test_post109 \
  || { echo "FAIL: a post-10.9 import must fail, naming it, with no host Mach-O readers (exit $rc):"; printf '%s\n' "$out" | sed 's/^/    | /'; exit 1; }
echo "PASS: compat-guard-no-host-readers"
