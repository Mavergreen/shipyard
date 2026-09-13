#!/bin/sh
#   usage: check-comments.sh [path...]
#          with no paths, scans every tracked *.sh and *.yml
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(pwd)"
REASONS="$ROOT/comment-reasons"
# spec: 2026-09-12-comments-cite-a-reason task-1-brief.md -- opt-in via comment-reasons keeps
#       14 consumer repos green until each has swept; the path is the REPO's, never shipyard's
#       installed prefix, since consumers run this script from there.
[ -f "$REASONS" ] || exit 0
alt="$(tr '\n' '|' < "$REASONS" | sed 's/|$//')"

if [ "$#" -gt 0 ]; then files="$*"; else
  files="$(cd "$ROOT" && git ls-files '*.sh' '*.yml' | sed "s|^|$ROOT/|")"
fi

rc=0
for f in $files; do
  [ -f "$f" ] || continue
  awk -v FNAME="$f" -v ALT="$alt" '
    BEGIN { split(ALT, r, "|"); for (i in r) ok[r[i]] = 1 }

    # spec: 2026-09-12-comments-cite-a-reason task-1-brief.md -- a heredoc body is payload, not
    #       commentary: package-pkg.sh writes a whole script inside one. Track the terminator
    #       and skip until it closes.
    heredoc != "" {
      line = $0; sub(/^[ \t]+/, "", line)
      if (line == heredoc) heredoc = ""
      next
    }
    /<<-?[ ]*'"'"'?[A-Za-z_][A-Za-z0-9_]*'"'"'?/ {
      t = $0
      sub(/^.*<<-?[ ]*/, "", t); gsub(/'"'"'/, "", t)
      sub(/[ \t].*$/, "", t)
      if (t != "") { heredoc = t; next }
    }

    FNR == 1 && /^#!/ { next }
    !/^[ \t]*#/ { intag = 0; inusage = 0; next }

    /^[ \t]*#[ \t]*shellcheck/ { next }
    # spec: 2026-09-12-comments-cite-a-reason task-1-brief.md -- a continuation is recognized by
    #       indentation of its content past the label, not by the column of the leading "#":
    #       that character sits in column 1 for every left-margin comment, tag line and
    #       continuation alike, so comparing it never distinguishes them. What must be compared
    #       is where the text after "#" begins.
    /^[ \t]*#[ \t]*usage:/ { inusage = 1; match($0, /^[ \t]*#[ \t]*/); usecol = RLENGTH + 1; next }
    inusage == 1 {
      match($0, /^[ \t]*#[ \t]*/)
      if (RLENGTH + 1 > usecol) next
      inusage = 0
    }

    {
      line = $0
      sub(/^[ \t]*#[ \t]*/, "", line)
      tag = line; sub(/:.*$/, "", tag)
      if (line ~ /^[a-z][a-z0-9_-]*:/ && tag in ok) {
        intag = 1; match($0, /^[ \t]*#[ \t]*/); tagcol = RLENGTH + 1; next
      }
      if (intag == 1) {
        match($0, /^[ \t]*#[ \t]*/)
        if (RLENGTH + 1 > tagcol) next
      }
      intag = 0
      if (line ~ /^[a-z][a-z0-9_-]*:/)
        printf "%s:%d: %s\n    unknown reason \"%s\" -- propose a new reason to Amitai, do not invent a tag\n", FNAME, FNR, $0, tag
      else
        printf "%s:%d: %s\n    cite a reason: \"# platform: <a platform fact that bit us>\" or \"# spec: <where the decision lives>\"\n", FNAME, FNR, $0
      bad++
    }
    END { if (bad > 0) exit 1 }
  ' "$f" || rc=1
done
exit $rc
