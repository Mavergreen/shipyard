#!/bin/sh
# platform: host-agnostic
#   usage: check-local-backfills.sh [--report] REPO
#          Rule local-backfill: a product other than Recaulk ships no family-authored OS/API
#          backfill. Joins scan-local-backfills.sh's candidates with REPO/compatibility-inventory.tsv
#          and the local-backfill exceptions in REPO/INGREDIENTS.md (local-backfill-deviations.sh),
#          and prints one "local-backfill: <path>[:<line>]: <finding>" line per policy finding.
#          A finding is: a candidate no inventory row classifies; an inventory row or symbol no
#          candidate matches; a candidate classified local-backfill with no valid exception naming
#          its file and symbol; an invalid exception, or one naming no local-backfill row; an
#          upstream row on a patch, or one whose reason cites no pin and unchanged origin.
#          MAVERGREEN_CHECK_REPOSITORY is the trusted identity, supplied by the caller and never read
#          from REPO. Exactly Mavergreen/recaulk owns its backfills: its candidates need no
#          classification and its local-backfill rows no exception; every other finding stands.
#          Unset or anything else is not Recaulk. Only source is judged: binaries and what they
#          link are never read.
#          Exit 0: no finding, or --report. 1: a finding. 2: the scan, the inventory or the
#          deviation section could not be read, in either mode.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
usage="usage: check-local-backfills.sh [--report] REPO"
report=0
case "${1:-}" in
  --report) report=1; shift ;;
  -*) echo "$usage" >&2; exit 2 ;;
esac
[ "$#" -eq 1 ] || { echo "$usage" >&2; exit 2; }
[ -d "$1" ] || { echo "check-local-backfills: $1 is not a directory" >&2; exit 2; }
repo="$1"
recaulk=0
[ "${MAVERGREEN_CHECK_REPOSITORY:-}" != Mavergreen/recaulk ] || recaulk=1

w="$(mktemp -d "${TMPDIR:-/tmp}/check-local-backfills.XXXXXX")"
trap 'rm -rf "$w"' EXIT
sh "$SELF/scan-local-backfills.sh" "$repo" > "$w/candidates" || exit 2
sh "$SELF/scan-local-backfills.sh" --inventory "$repo" > "$w/inventory" 2>/dev/null || exit 2
rc=0; sh "$SELF/local-backfill-deviations.sh" "$repo" > "$w/exceptions" || rc=$?
[ "$rc" -le 1 ] || exit 2

LC_ALL=C awk -F '\t' -v recaulk="$recaulk" '
  function say(where, msg) { print "local-backfill: " where ": " msg; n++ }
  function ispatch(p) { return p ~ /\.(patch|diff)$/ || (p in patchy) }
  FILENAME == ARGV[1] {
    rows++; rpath[rows] = $1; rkind[rows] = $2; rsyms[rows] = $3; rwhy[rows] = $4
    ns = split($3, s, ",")
    for (i = 1; i <= ns; i++) kind[$1 SUBSEP s[i]] = $2
    if ($2 == "local-backfill") { lbpath[$1] = 1; if ($3 != "-") lbnamed[$1] = 1 }
    next
  }
  FILENAME == ARGV[2] {
    if ($1 == "invalid") { say($2, "invalid exception: " $3); next }
    if ($2 in exc) { dupexc[$2] = 1; next }
    exc[$2] = 1; ns = split($3, s, ",")
    for (i = 1; i <= ns; i++) excsym[$2 SUBSEP s[i]] = 1
    next
  }
  {
    p = $1; ln = $2; cat = $3; sym = $4; at = p ":" ln
    if (cat == "patch-definition") patchy[p] = 1
    if ((p SUBSEP sym) in kind) k = kind[p SUBSEP sym]
    else k = ""
    if (k != "") used[p SUBSEP sym] = 1
    if (k == "") {
      if (!recaulk) say(at, cat " " sym ": unclassified candidate -- add a compatibility-inventory.tsv row (path, kind, symbols, reason) naming " (sym == "-" ? "\"-\"" : sym) "; kinds: local-backfill, product-adaptation, upstream, test-only")
      next
    }
    if (k != "local-backfill" || recaulk) next
    if (p in dupexc) { say(at, cat " " sym ": more than one local-backfill exception names this file; keep one"); next }
    if ((p in exc) && (sym == "-" || ((p SUBSEP sym) in excsym))) next
    say(at, cat " " sym ": a local backfill ships only with an exception -- move it to Recaulk (src/backfills/ or src/overrides/) or upstream to macports-legacy-support, delete it if obsolete, or declare \"- local-backfill:" p ": <reason>; symbols=" (sym == "-" ? "<API>" : sym) "; decision=...; evidence=...; revisit=...\" in INGREDIENTS.md")
  }
  END {
    for (i = 1; i <= rows; i++) {
      p = rpath[i]; ns = split(rsyms[i], s, ",")
      for (j = 1; j <= ns; j++) if (!((p SUBSEP s[j]) in used))
        say(p, "inventory row (" rkind[i] ", " (s[j] == "-" ? "no symbol" : s[j]) ") matches no candidate -- remove it, or correct its path or symbols")
      if (rkind[i] == "upstream") {
        if (ispatch(p)) say(p, "classified upstream, but a patch is a local modification of upstream code -- classify what it adds")
        else {
          lw = tolower(rwhy[i])
          if (lw !~ /pin/ || lw !~ /unmodified|unchanged/)
            say(p, "an upstream row must cite the pin and say the source is unmodified (\"<upstream> <version> at the commit pinned in <pin file>, unmodified\"); an edited vendored file is a local modification")
        }
      }
    }
    for (p in exc) {
      if (!(p in lbpath)) { say(p, "exception matches no local-backfill row in compatibility-inventory.tsv"); continue }
      if (!(p in lbnamed)) continue
      for (k in excsym) {
        split(k, ks, SUBSEP)
        if (ks[1] == p && kind[k] != "local-backfill") say(p, "exception names symbol " ks[2] ", which no local-backfill row for this file classifies")
      }
    }
  }' "$w/inventory" "$w/exceptions" "$w/candidates" > "$w/findings" || exit 2
cat "$w/findings"
[ -s "$w/findings" ] || exit 0
count="$(wc -l < "$w/findings" | tr -d ' ')"
if [ "$report" -eq 1 ]; then
  echo "check-local-backfills: --report: $count findings, not enforced; publication runs strict" >&2
  exit 0
fi
echo "check-local-backfills: $count findings; see shipyard's explain/local-backfill.md" >&2
exit 1
