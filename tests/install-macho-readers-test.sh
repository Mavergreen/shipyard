#!/bin/sh
# platform: host-agnostic
# spec: scripts/install-macho-readers.sh -- readers the seam finds (xcrun's included) cost no brew call; a
#       runner with none gets Homebrew's llvm named in $GITHUB_ENV, not on PATH; and with neither, a
#       warning and exit 0, because the script must never fail install@v1.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/install-macho-readers.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/install-readers-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/bin" "$w/llvm/bin" "$w/xc"
ln -s "$(command -v dirname)" "$w/bin/dirname"
for t in otool lipo nm strings; do
  printf '#!/bin/sh\nexit 0\n' > "$w/llvm/bin/llvm-$t"; chmod +x "$w/llvm/bin/llvm-$t"
done
printf '#!/bin/sh\ncase "$1" in list) exit 1 ;; install) echo "$2" > "%s/installed" ;; --prefix) echo "%s/llvm" ;; esac\n' "$w" "$w" > "$w/brew"
chmod +x "$w/brew"
run() {  # $@ = extra PATH dirs; sets rc, output in $w/out, env in $w/env
  : > "$w/env"; rc=0
  env -u OTOOL -u LIPO -u NM -u STRINGS PATH="$w/bin" SHIPYARD_MACHO_DIRS="" GITHUB_ENV="$w/env" /bin/sh "$S" > "$w/out" 2>&1 || rc=$?
}

cp "$w/brew" "$w/bin/brew"
run
[ "$rc" -eq 0 ] && [ "$(cat "$w/installed")" = llvm ] || { echo "FAIL with brew and no readers it should brew install llvm: $(cat "$w/out")"; exit 1; }
for t in OTOOL:otool LIPO:lipo NM:nm STRINGS:strings; do
  grep -qx "${t%%:*}=$w/llvm/bin/llvm-${t#*:}" "$w/env" || { echo "FAIL \$GITHUB_ENV should name ${t%%:*}: $(cat "$w/env")"; exit 1; }
done
grep -q PATH "$w/env" && { echo "FAIL it must not touch PATH"; exit 1; }

rm -f "$w/installed"
for t in otool lipo nm strings; do cp "$w/llvm/bin/llvm-$t" "$w/bin/llvm-$t-18"; done
run
[ "$rc" -eq 0 ] && [ ! -e "$w/installed" ] || { echo "FAIL readers the seam finds must not call brew: $(cat "$w/out")"; exit 1; }
grep -qx "OTOOL=$w/bin/llvm-otool-18" "$w/env" || { echo "FAIL it should export what the seam found: $(cat "$w/env")"; exit 1; }

rm -f "$w/bin"/llvm-*
printf '#!/bin/sh\necho "brew called" > "%s/installed"; exit 1\n' "$w" > "$w/bin/brew"; chmod +x "$w/bin/brew"
printf '#!/bin/sh\ncase "$1 $2" in "-f llvm-"*) echo "%s/llvm/bin/$2" ;; esac\n' "$w" > "$w/bin/xcrun"; chmod +x "$w/bin/xcrun"
run
[ "$rc" -eq 0 ] && [ ! -e "$w/installed" ] || { echo "FAIL xcrun providing the readers must mean no brew call: $(cat "$w/out")"; exit 1; }
grep -qx "OTOOL=$w/llvm/bin/llvm-otool" "$w/env" || { echo "FAIL xcrun's reader should be exported: $(cat "$w/env")"; exit 1; }

rm -f "$w/bin/brew" "$w/bin/xcrun" "$w/installed"
run
[ "$rc" -eq 0 ] || { echo "FAIL with no readers and no brew it must still exit 0, got $rc"; exit 1; }
grep -q '^::warning::.*OTOOL' "$w/out" || { echo "FAIL it should warn naming the variable: $(cat "$w/out")"; exit 1; }
[ ! -s "$w/env" ] || { echo "FAIL nothing should be exported: $(cat "$w/env")"; exit 1; }

echo "PASS: install-macho-readers"
