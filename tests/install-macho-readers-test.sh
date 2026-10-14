#!/bin/sh
# platform: host-agnostic
# spec: scripts/install-macho-readers.sh -- a runner with no family clang gets LLVM's readers from
#       Homebrew, named in $GITHUB_ENV rather than put on PATH, and an unreadable setup says so.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/install-macho-readers.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/install-readers-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/bin" "$w/llvm/bin"
ln -s "$(command -v dirname)" "$w/bin/dirname"
for t in otool lipo nm strings; do printf '#!/bin/sh\nexit 0\n' > "$w/llvm/bin/llvm-$t"; chmod +x "$w/llvm/bin/llvm-$t"; done
printf '#!/bin/sh\ncase "$1" in list) exit 1 ;; install) echo "$2" > "%s/installed" ;; --prefix) echo "%s/llvm" ;; esac\n' "$w" "$w" > "$w/bin/brew"
chmod +x "$w/bin/brew"

: > "$w/env"
env -u OTOOL -u LIPO -u NM -u STRINGS PATH="$w/bin" SHIPYARD_MACHO_DIRS="" GITHUB_ENV="$w/env" /bin/sh "$S" > "$w/out" 2>&1 || { echo "FAIL it should install and name the readers: $(cat "$w/out")"; exit 1; }
[ "$(cat "$w/installed")" = llvm ] || { echo "FAIL it should brew install llvm"; exit 1; }
for t in OTOOL:otool LIPO:lipo NM:nm STRINGS:strings; do
  grep -qx "${t%%:*}=$w/llvm/bin/llvm-${t#*:}" "$w/env" || { echo "FAIL \$GITHUB_ENV should name ${t%%:*}: $(cat "$w/env")"; exit 1; }
done
grep -q 'PATH' "$w/env" && { echo "FAIL it must not touch PATH: $(cat "$w/env")"; exit 1; }

rm "$w/installed"
rc=0; env PATH="$w/bin" OTOOL="$w/llvm/bin/llvm-otool" LIPO="$w/llvm/bin/llvm-lipo" NM="$w/llvm/bin/llvm-nm" STRINGS="$w/llvm/bin/llvm-strings" \
  SHIPYARD_MACHO_DIRS="" /bin/sh "$S" > "$w/out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$w/installed" ] || { echo "FAIL readers already named must not be reinstalled: $(cat "$w/out")"; exit 1; }

rm "$w/bin/brew"
rc=0; env -u OTOOL -u LIPO -u NM -u STRINGS PATH="$w/bin" SHIPYARD_MACHO_DIRS="" /bin/sh "$S" > "$w/out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL with no readers and no brew it should exit 1, got $rc"; exit 1; }
grep -q 'OTOOL, LIPO, NM and STRINGS' "$w/out" || { echo "FAIL it should name the variables to set: $(cat "$w/out")"; exit 1; }

echo "PASS: install-macho-readers"
