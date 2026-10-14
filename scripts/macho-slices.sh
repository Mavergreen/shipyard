#!/bin/sh
# platform: host-agnostic
#   usage: [LIPO=<llvm-lipo>] [OTOOL=<llvm-otool>] macho-slices.sh FILE
#          Prints one line per distinct (arch, filetype, minos, sdk) in FILE: "<arch> <filetype> <minos> <sdk>",
#          "-" where a slice records no version load command (a kext), "?" for a missing field. A static
#          archive yields one line per distinct pair across its members. Exit 0 with lines; 1 if FILE is
#          not Mach-O; 2 on a usage error; 4 if a reader (LIPO or OTOOL) is missing or failed on a file
#          the other reader already read, which a caller must not mistake for 1. The readers are LLVM's
#          (lib/macho-tools.sh), so this reads the same on 10.9, modern macOS and Linux.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the ONE parser
#       of recorded versions, shared by the compat guard and artifact-facts.sh.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib/macho-tools.sh"
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "usage: macho-slices.sh FILE" >&2; exit 2; }
f="$1"
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/macho-slices.XXXXXX")"; trap 'rm -rf "$t"' EXIT
# platform: a bash 3.2 sh (10.9's, and this Mac's) reports a missing command inside $( ) under set -e as
#           status 1, not 127, so a reader that is not there is checked by name. A file that is not Mach-O is
#           exit 1; a reader that is missing, or fails on a file its sibling reader already read, is exit 4,
#           naming the reader and replaying its own error, so the guard fails closed instead of reading it
#           as "not Mach-O".
reader_died() { echo "macho-slices: $1 could not read $f" >&2; cat "$t/err" >&2; exit 4; }
: > "$t/err"
mach_tool LIPO || exit 4
mach_tool OTOOL || exit 4
command -v "$LIPO" >/dev/null 2>&1 || reader_died "$LIPO (not found)"
command -v "$OTOOL" >/dev/null 2>&1 || reader_died "$OTOOL (not found)"
# platform: llvm-lipo -info prints, as Apple's lipo does, either "Architectures in the fat file: F are: a b"
#           or "Non-fat file: F is architecture: a" -- with a trailing space, which xargs drops.
# platform: llvm-lipo 18 (Ubuntu's) segfaults on -info of a static archive, in IRObjectFile::getTargetTriple;
#           an archive's arch is read from its members' own headers instead, which is what lipo -info
#           reports for one anyway. Any other lipo exit above 1 is a reader that died, not a file that
#           is not Mach-O.
if [ "$(head -c 7 "$f")" = '!<arch>' ]; then
  info=archive
  "$OTOOL" -hv "$f" >"$t/ahv" 2>"$t/err" || reader_died "$OTOOL -hv"
  archs="$(awk '$1 ~ /^MH_MAGIC/ { print tolower($2) }' "$t/ahv" | sort -u | xargs)"
  [ -n "$archs" ] || exit 1
  case "$archs" in *" "*) echo "macho-slices: $f mixes the arches $archs, so its members' versions cannot be told apart" >&2; exit 4 ;; esac
else
  lrc=0; info="$("$LIPO" -info "$f" 2>"$t/err")" || lrc=$?
  [ "$lrc" -eq 0 ] || { [ "$lrc" -eq 1 ] || reader_died "$LIPO -info (exit $lrc)"; exit 1; }
  archs="$(printf '%s\n' "$info" | sed -n 's/.*: //p' | xargs)"
  [ -n "$archs" ] || exit 1
fi
for a in $archs; do
  s="$f"
  case "$info" in Architectures*) "$LIPO" -thin "$a" "$f" -output "$t/$a" >/dev/null 2>"$t/err" || reader_died "$LIPO -thin $a"; s="$t/$a" ;; esac
  # platform: `otool -hv` prints the header table; the filetype is the 5th column of its data row. An
  #           archive prints one table per member, and every member of one arch shares a filetype.
  hv="$("$OTOOL" -hv "$s" 2>"$t/err")" || reader_died "$OTOOL -hv"
  ft="$(printf '%s\n' "$hv" | awk '$1 ~ /^MH_MAGIC/ {print $5; exit}')"
  [ -n "$ft" ] || exit 1
  # platform: LC_VERSION_MIN_MACOSX carries "version" and "sdk". LC_BUILD_VERSION carries "sdk" BEFORE
  #           "minos", then a tools list whose "version" lines are the LINKER's version -- so minos is
  #           read only from "minos" there, and the pair is emitted when the load command ends.
  #           llvm-otool -l also prints the Mach header, as raw numbers, ahead of the load commands;
  #           none of it starts with "cmd", so the awk below never sees it.
  lc="$("$OTOOL" -l "$s" 2>"$t/err")" || reader_died "$OTOOL -l"
  printf '%s\n' "$lc" | awk -v a="$a" -v ft="$ft" '
    function flush() { if (inv) { print a, ft, (mn == "" ? "?" : mn), (sd == "" ? "?" : sd); seen = 1 } inv = 0 }
    $1 == "cmd" { flush(); if ($2 == "LC_VERSION_MIN_MACOSX" || $2 == "LC_BUILD_VERSION") { inv = 1; kind = $2; mn = ""; sd = "" } next }
    inv && kind == "LC_VERSION_MIN_MACOSX" && $1 == "version" { mn = $2; next }
    inv && kind == "LC_BUILD_VERSION" && $1 == "minos" { mn = $2; next }
    inv && $1 == "sdk" { sd = $2; next }
    END { flush(); if (!seen) print a, ft, "-", "-" }' | sort -u
done
