#!/bin/sh
# platform: host-agnostic
#   usage: [LIPO=<llvm-lipo>] [OTOOL=<llvm-otool>] macho-loads.sh FILE
#          Prints "<arch> dylib <path>" for each LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB and
#          LC_LOAD_UPWARD_DYLIB in FILE, "<arch> rpath <path>" for each LC_RPATH, and "<arch> id <path>"
#          for an LC_ID_DYLIB, per slice of a fat
#          file. A static archive prints nothing. Exit 0; 1 if FILE is not Mach-O; 2 on a usage error; 4 if
#          a reader (LIPO or OTOOL) is missing or failed, as macho-slices.sh does.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/macho-tools.sh"
. "$SELF/lib/pkg-tree.sh"
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "usage: macho-loads.sh FILE" >&2; exit 2; }
f="$1"
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/macho-loads.XXXXXX")"; trap 'rm -rf "$t"' EXIT
reader_died() { echo "macho-loads: $1 could not read $f" >&2; cat "$t/err" >&2; exit 4; }
: > "$t/err"
mach_tool LIPO || exit 4
mach_tool OTOOL || exit 4
command -v "$LIPO" >/dev/null 2>&1 || reader_died "$LIPO (not found)"
command -v "$OTOOL" >/dev/null 2>&1 || reader_died "$OTOOL (not found)"
[ "$(head -c 7 "$f")" != '!<arch>' ] || exit 0
lrc=0; info="$("$LIPO" -info "$f" 2>"$t/err")" || lrc=$?
[ "$lrc" -eq 0 ] || { [ "$lrc" -eq 1 ] && ! af_fat_macho "$f" || reader_died "$LIPO -info (exit $lrc)"; exit 1; }
archs="$(printf '%s\n' "$info" | sed -n 's/.*: //p' | xargs)"
[ -n "$archs" ] || exit 1
for a in $archs; do
  s="$f"
  case "$info" in Architectures*) "$LIPO" -thin "$a" "$f" -output "$t/$a" >/dev/null 2>"$t/err" || reader_died "$LIPO -thin $a"; s="$t/$a" ;; esac
  lc="$("$OTOOL" -l "$s" 2>"$t/err")" || reader_died "$OTOOL -l"
  printf '%s\n' "$lc" | awk -v a="$a" '
    $1 == "cmd" { k = ""
      if ($2 == "LC_LOAD_DYLIB" || $2 == "LC_LOAD_WEAK_DYLIB" || $2 == "LC_REEXPORT_DYLIB" || $2 == "LC_LOAD_UPWARD_DYLIB") k = "dylib"
      else if ($2 == "LC_RPATH") k = "rpath"
      else if ($2 == "LC_ID_DYLIB") k = "id"
      next }
    (k == "dylib" || k == "id") && $1 == "name" || k == "rpath" && $1 == "path" {
      v = $0; sub(/^[ \t]*(name|path) /, "", v); sub(/ \(offset [0-9]+\)$/, "", v)
      print a, k, v; k = "" }'
done
