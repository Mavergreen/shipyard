#!/bin/sh
# platform: host-agnostic -- reads Mach-O through NM, LIPO and OTOOL (clang22's llvm-nm, llvm-lipo and llvm-otool off macOS)
#   usage: [NM=<nm>] [LIPO=<lipo>] [OTOOL=<otool>] macho-cxxabi.sh FILE
#          Prints, per slice of FILE, "<arch> defines <symbol> <visible|hidden>" for each symbol it defines
#          that matches scripts/cxxabi-machinery.txt, whether exported or not (a private external, or a
#          non-external symbol of a linked image, is hidden), and "<arch> loads <path>" for each dylib it
#          loads or re-exports whose basename starts libc++abi. A static archive is read through all its
#          members. An old toolchain's "<symbol>.eh" frame label counts as <symbol>.
#          Exit 0; 1 if FILE is not Mach-O; 2 on a usage error; 4 if a reader is missing or failed.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "usage: macho-cxxabi.sh FILE" >&2; exit 2; }
f="$1"
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/macho-cxxabi.XXXXXX")"; trap 'rm -rf "$t"' EXIT
reader_died() { echo "macho-cxxabi: $1 could not read $f" >&2; cat "$t/err" >&2; exit 4; }
: > "$t/err"
for _r in "${NM:-nm}" "${LIPO:-lipo}" "${OTOOL:-otool}"; do
  command -v "$_r" >/dev/null 2>&1 || reader_died "$_r (not found)"
done
info="$("${LIPO:-lipo}" -info "$f" 2>/dev/null)" || exit 1
archs="$(printf '%s\n' "$info" | sed -n 's/.*: //p' | xargs)"
[ -n "$archs" ] || exit 1
for a in $archs; do
  s="$f"
  case "$info" in Architectures*) "${LIPO:-lipo}" -thin "$a" "$f" -output "$t/$a" >/dev/null 2>"$t/err" || reader_died "${LIPO:-lipo} -thin $a"; s="$t/$a" ;; esac
  "${NM:-nm}" -Um "$s" > "$t/nm" 2>"$t/err" || reader_died "${NM:-nm} -Um"
  awk '/^[0-9a-f ]*\(/ && !/\):$/ {
         n = $0; sub(/ \(for [^)]*\)$/, "", n); sub(/.* /, "", n); sub(/\.eh$/, "", n)
         print n, ((/ external / && !/ private external /) ? "visible" : "hidden") }' "$t/nm" \
    | grep -E -f "$SELF/cxxabi-machinery.txt" | LC_ALL=C sort -u | sed "s/^/$a defines /"
  "${OTOOL:-otool}" -l "$s" > "$t/l" 2>"$t/err" || reader_died "${OTOOL:-otool} -l"
  awk -v a="$a" '
    $1 == "cmd" { load = ($2 ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD|LOAD_UPWARD)_DYLIB$/); next }
    load && $1 == "name" {
      p = $0; sub(/^[ \t]*name[ \t]+/, "", p); sub(/ \(offset [0-9]+\)$/, "", p)
      b = p; sub(/.*\//, "", b)
      if (index(b, "libc++abi") == 1) print a " loads " p
      load = 0
    }' "$t/l" | LC_ALL=C sort -u
done
