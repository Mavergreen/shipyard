#!/bin/sh
# platform: host-agnostic
#   usage: local-backfill-deviations.sh REPO
#          Reads the local-backfill exceptions from deviations.sh's parse of REPO/INGREDIENTS.md and
#          prints one record per entry:
#            exception<TAB>path<TAB>symbols<TAB>decision<TAB>evidence<TAB>revisit<TAB>reason
#            invalid<TAB>scope<TAB>what is wrong
#          An entry is "- local-backfill:<path>: <concrete reason>; symbols=<a,b>; decision=<the
#          maintainer's decision>; evidence=<where it was reviewed>; revisit=<exit condition>".
#          path is one literal repo-relative file. symbols are comma-separated names. Each labeled
#          field appears once and is not blank; no other lowercase label is accepted. A reason saying
#          Recaulk already provides the code is refused: then the copy goes, not the rule.
#          Whether path is classified local-backfill is check-local-backfills.sh's to decide.
#          Exit 0: every entry valid. 1: some entry invalid. 2: deviations.sh refused the section.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -eq 1 ] && [ -d "$1" ] || { echo "usage: local-backfill-deviations.sh REPO" >&2; exit 2; }
parsed="$(sh "$SELF/deviations.sh" "$1")" || exit 2
printf '%s\n' "$parsed" | LC_ALL=C awk '
  function trim(s) { sub(/^[ ;]+/, "", s); sub(/[ ;]+$/, "", s); return s }
  function bad(msg) { printf "invalid\t%s\t%s\n", scope, msg; nbad++ }
  $1 != "local-backfill" { next }
  {
    scope = $2; r = $0; sub(/^[^ ]+ [^ ]+ /, "", r)
    if (scope == "*") { bad("a bare exemption excuses nothing: name one file, \"- local-backfill:<path>: <reason>; symbols=...; decision=...; evidence=...; revisit=...\""); next }
    if (scope ~ /[*?]|\[/) { bad("a wildcard scope; an exception names exactly one file"); next }
    if (scope ~ /^\// || ("/" scope "/") ~ /\/(\.|\.\.)?\// || scope ~ /\/$/) { bad("the scope must be a literal repo-relative file path"); next }
    if (r ~ /\t/) { bad("a tab in the reason"); next }
    split("", val); split("", seen); n = 0; pre = ""; cur = ""; rest = " " r; ok = 1
    while (match(rest, /[ ;][a-z][a-z_-]*=/)) {
      head = substr(rest, 1, RSTART); label = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
      if (n == 0) pre = head; else val[cur] = val[cur] head
      if (label != "symbols" && label != "decision" && label != "evidence" && label != "revisit") {
        if (label ~ /^approv/) bad("\"" label "=\" is a self-asserted switch: approval is maintainer review, recorded as decision= and evidence=")
        else bad("unknown label \"" label "=\"; the labels are symbols=, decision=, evidence=, revisit=")
        ok = 0
      }
      if (label in seen) { bad("\"" label "=\" appears more than once"); ok = 0 }
      seen[label] = 1; cur = label; n++
    }
    if (n == 0) pre = rest; else val[cur] = val[cur] rest
    if (!ok) next
    pre = trim(pre)
    if (pre == "") { bad("no concrete reason before the labeled fields"); next }
    lr = tolower(pre)
    if (lr ~ /recaulk/ && lr ~ /already|provide|supplie|implement/) {
      bad("\"" pre "\": Recaulk already provides it is no reason to keep a copy; delete it and link Recaulk, or fix Recaulk"); next }
    split("symbols decision evidence revisit", need, " ")
    for (i = 1; i <= 4; i++) {
      v = (need[i] in val) ? trim(val[need[i]]) : ""
      if (!(need[i] in val)) { bad("no " need[i] "= field"); ok = 0 }
      else if (v == "") { bad("a blank " need[i] "= field"); ok = 0 }
      val[need[i]] = v
    }
    if (!ok) next
    ns = split(val["symbols"], s, ",")
    for (i = 1; i <= ns; i++) if (s[i] !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { bad("symbols=: \"" s[i] "\" is not a name"); ok = 0 }
    if (!ok) next
    printf "exception\t%s\t%s\t%s\t%s\t%s\t%s\n", scope, val["symbols"], val["decision"], val["evidence"], val["revisit"], pre
  }
  END { exit nbad ? 1 : 0 }'
