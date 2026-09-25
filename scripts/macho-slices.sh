#!/bin/sh
# platform: macOS-only -- lipo and otool read the Mach-O slices
#   usage: macho-slices.sh FILE
#          Prints one line per distinct (arch, filetype, minos, sdk) in FILE: "<arch> <filetype> <minos> <sdk>",
#          "-" where a slice records no version load command (a kext), "?" for a missing field. A static
#          archive yields one line per distinct pair across its members. Exit 0 with lines; 1 if FILE is
#          not Mach-O; 2 on a usage error.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the ONE parser
#       of recorded versions, shared by the compat guard and artifact-facts.sh.
set -eu
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "usage: macho-slices.sh FILE" >&2; exit 2; }
f="$1"
# platform: `lipo -info` exists on every macOS; -archs does not exist on 10.9. It prints either
#           "Architectures in the fat file: F are: a b" or "Non-fat file: F is architecture: a".
info="$(lipo -info "$f" 2>/dev/null)" || exit 1
archs="$(printf '%s\n' "$info" | sed -n 's/.*: //p' | xargs)"
[ -n "$archs" ] || exit 1
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/macho-slices.XXXXXX")"; trap 'rm -rf "$t"' EXIT
for a in $archs; do
  s="$f"
  case "$info" in Architectures*) lipo -thin "$a" "$f" -output "$t/$a" >/dev/null 2>&1 || exit 1; s="$t/$a" ;; esac
  # platform: `otool -hv` prints the header table; the filetype is the 5th column of its data row. An
  #           archive prints one table per member, and every member of one arch shares a filetype.
  ft="$(otool -hv "$s" 2>/dev/null | awk '$1 ~ /^MH_MAGIC/ {print $5; exit}')"
  [ -n "$ft" ] || exit 1
  # platform: LC_VERSION_MIN_MACOSX carries "version" and "sdk". LC_BUILD_VERSION carries "sdk" BEFORE
  #           "minos", then a tools list whose "version" lines are the LINKER's version -- so minos is
  #           read only from "minos" there, and the pair is emitted when the load command ends.
  otool -l "$s" 2>/dev/null | awk -v a="$a" -v ft="$ft" '
    function flush() { if (inv) { print a, ft, (mn == "" ? "?" : mn), (sd == "" ? "?" : sd); seen = 1 } inv = 0 }
    $1 == "cmd" { flush(); if ($2 == "LC_VERSION_MIN_MACOSX" || $2 == "LC_BUILD_VERSION") { inv = 1; kind = $2; mn = ""; sd = "" } next }
    inv && kind == "LC_VERSION_MIN_MACOSX" && $1 == "version" { mn = $2; next }
    inv && kind == "LC_BUILD_VERSION" && $1 == "minos" { mn = $2; next }
    inv && $1 == "sdk" { sd = $2; next }
    END { flush(); if (!seen) print a, ft, "-", "-" }' | sort -u
done
