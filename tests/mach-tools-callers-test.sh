#!/bin/sh
# platform: host-agnostic
#   usage: mach-tools-callers-test.sh
#          Off macOS, with no LIPO, OTOOL, NM or AR set, macho-cxxabi.sh, macho-slices.sh and
#          lipo-merge-tree.sh read Mach-O with an installed clang22's llvm- tools, or with no clang22 the
#          llvm- tools on PATH, never the lipo, otool or GNU ar on PATH.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts"
w="$(mktemp -d "${TMPDIR:-/tmp}/mach-tools-callers.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: mach-tools-callers: $1"; cat "$w/log" 2>/dev/null; exit 1; }
mkdir -p "$w/mg/clang22/bin" "$w/path" "$w/empty"
for t in llvm-nm llvm-otool llvm-lipo llvm-ar; do
  printf '#!/bin/sh\necho %s >> "%s/log"\nexit 1\n' "$t" "$w" > "$w/mg/clang22/bin/$t"; chmod +x "$w/mg/clang22/bin/$t"
done
for t in nm otool lipo ar; do
  printf '#!/bin/sh\necho host-%s >> "%s/log"\nexit 1\n' "$t" "$w" > "$w/path/$t"; chmod +x "$w/path/$t"
done
MG="$w/mg"
run() {
  : > "$w/log"
  ( unset NM LIPO OTOOL AR; SHIPYARD_MACH_HOST=Linux SHIPYARD_MG_PREFIX=$MG PATH="$w/path:$PATH"
    export SHIPYARD_MACH_HOST SHIPYARD_MG_PREFIX PATH; "$@" ) > "$w/out" 2>&1 || :
  if grep -q '^host-' "$w/log"; then fail "$* ran the host's $(sed -n 's/^host-//p' "$w/log" | head -n 1)"; fi
}
printf '!<arch>\n' > "$w/a.a"
run sh "$S/macho-cxxabi.sh" "$w/a.a"
grep -qx llvm-ar "$w/log" || fail "macho-cxxabi.sh read the archive with clang22's llvm-ar"
printf 'not mach-o' > "$w/f"
run sh "$S/macho-slices.sh" "$w/f"
grep -qx llvm-lipo "$w/log" || fail "macho-slices.sh read the file with clang22's llvm-lipo"
mkdir -p "$w/a" "$w/b"; printf a > "$w/a/x"; printf b > "$w/b/x"
run sh "$S/lipo-merge-tree.sh" --a "$w/a" --b "$w/b" --out "$w/o"
grep -qx llvm-lipo "$w/log" || fail "lipo-merge-tree.sh asked clang22's llvm-lipo whether a file is Mach-O"
cp "$w/mg/clang22/bin/"llvm-* "$w/path/"
MG="$w/empty"
run sh "$S/macho-cxxabi.sh" "$w/a.a"
grep -qx llvm-ar "$w/log" || fail "with no clang22, macho-cxxabi.sh read the archive with PATH's llvm-ar"
run sh "$S/macho-slices.sh" "$w/f"
grep -qx llvm-lipo "$w/log" || fail "with no clang22, macho-slices.sh read the file with PATH's llvm-lipo"
echo "PASS: mach-tools-callers"
