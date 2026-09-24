#!/bin/sh
# platform: host-agnostic
#   usage: host-of.sh FILE
#          Prints FILE's declared host -- "host-agnostic" or "macOS-only" -- read from its header:
#          the lines before its first line of code, after any "#!" line. Exit 0 with the host
#          printed; 1 when the header declares none; 3 when it declares more than one; 2 when FILE
#          is not a readable file.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md check 22
set -eu
[ "$#" -eq 1 ] && [ -f "$1" ] && [ -r "$1" ] || { echo "usage: host-of.sh FILE (a readable file)" >&2; exit 2; }
awk '
  NR == 1 && /^#!/ { next }
  /^# platform: host-agnostic( -- .+)?$/ { n++; v = "host-agnostic"; next }
  /^# platform: macOS-only -- .+$/       { n++; v = "macOS-only"; next }
  /^[ \t]*#/ || /^[ \t]*$/ { next }
  { exit }
  END { if (n == 1) { print v; exit 0 } exit (n == 0 ? 1 : 3) }
' "$1"
