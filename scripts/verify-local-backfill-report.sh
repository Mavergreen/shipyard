#!/bin/sh
# platform: host-agnostic
#   usage: verify-local-backfill-report.sh [--notes-only] REPORT REPO DIST SOURCE_SHA [NOTES]
#          publish-release.yml's local-backfill gate. REPORT is the build's local-backfill-report
#          artifact; REPO is the caller checked out at SOURCE_SHA, the commit being released; DIST and
#          NOTES (default RELEASE_NOTES.md) are what release-assets.sh, given the same --notes-only,
#          selects from. The report is evidence, never authority: this recomputes it with
#          local-backfill-report.sh, which reruns strict policy on REPO, and refuses unless the
#          report names SOURCE_SHA and records exactly the selected assets, each with its SHA256.
#          Exit 0: the evidence holds. 1: refused (absent, malformed, stale or mismatched evidence,
#          or a source that fails strict policy). 2: a usage error, or a check that could not run.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
usage="usage: verify-local-backfill-report.sh [--notes-only] REPORT REPO DIST SOURCE_SHA [NOTES]"
refuse() { printf '::error::local-backfill evidence: %s\n' "$*"; exit 1; }
only=
case "${1:-}" in
  --notes-only) only=--notes-only; shift ;;
  -*) echo "$usage" >&2; exit 2 ;;
esac
[ "$#" -eq 4 ] || [ "$#" -eq 5 ] || { echo "$usage" >&2; exit 2; }
report="$1"; repo="$2"; dist="$3"; sha="$4"; notes="${5:-RELEASE_NOTES.md}"

[ -s "$report" ] || refuse "no local-backfill report: the build that made these assets must run local-backfill-report.sh and upload the report as the local-backfill-report artifact; a release with none is refused"

LC_ALL=C awk -F '\t' '
  function bad(msg) { printf "::error::local-backfill evidence: %s line %d: %s\n", FILENAME, FNR, msg; err = 1; exit 1 }
  /\r/ { bad("malformed: carriage return") }
  FNR == 1 {
    if (NF != 2 || $1 != "source-sha" || $2 !~ /^[0-9a-f]+$/ || length($2) != 40)
      bad("malformed: the first line must be source-sha<TAB><40-hex commit>")
    next
  }
  {
    if (NF != 3 || $1 != "asset") bad("malformed: want asset<TAB><sha256><TAB><name>")
    if ($2 !~ /^[0-9a-f]+$/ || length($2) != 64) bad("malformed: \"" $2 "\" is not a SHA256")
    if ($3 == "" || $3 == "." || $3 == ".." || $3 ~ /\// || $3 ~ /[\001-\037\177]/)
      bad("unsafe asset path \"" $3 "\": an asset is a plain file name in the release")
    if (prev != "" && $3 <= prev) bad("malformed: asset names must be sorted and unique (\"" $3 "\" after \"" prev "\")")
    prev = $3
  }
  END { exit err }' "$report" || exit 1

claimed="$(sed -n '1s/^source-sha	//p' "$report")"
[ "$claimed" = "$sha" ] \
  || refuse "the report was made at $claimed, but the build source being released is $sha: stale evidence"

w="$(mktemp -d "${TMPDIR:-/tmp}/verify-local-backfill-report.XXXXXX")"
trap 'rm -rf "$w"' EXIT
sh "$SELF/release-assets.sh" $only "$dist" "$notes" > "$w/selected" \
  || refuse "release-assets.sh refuses $dist (above)"

rc=0; sh "$SELF/local-backfill-report.sh" --notes "$notes" "$repo" "$dist" "$sha" "$w/expected" || rc=$?
case "$rc" in
  0) ;;
  1) refuse "$repo at $sha fails strict local-backfill policy (findings above); the report does not change that" ;;
  *) echo "verify-local-backfill-report: could not recompute the evidence for $repo at $sha (exit $rc)" >&2; exit 2 ;;
esac

sed 's|.*/||' "$w/selected" | LC_ALL=C sort > "$w/selected-names"
sed -n '2,$p' "$w/expected" | cut -f3 > "$w/expected-names"
cmp -s "$w/selected-names" "$w/expected-names" \
  || refuse "release-assets.sh selects $(tr '\n' ' ' < "$w/selected-names")but the recomputed evidence covers $(tr '\n' ' ' < "$w/expected-names")"

if ! cmp -s "$w/expected" "$report"; then
  LC_ALL=C awk -F '\t' '
    FNR == 1 { next }
    FILENAME == ARGV[1] { want[$3] = $2; next }
    { got[$3] = $2 }
    END {
      for (n in want) {
        if (!(n in got)) printf "::error::local-backfill evidence: asset %s is not in the report\n", n
        else if (got[n] != want[n]) printf "::error::local-backfill evidence: asset %s has SHA256 %s, but the report records %s\n", n, want[n], got[n]
      }
      for (n in got) if (!(n in want)) printf "::error::local-backfill evidence: the report lists %s, which is absent from the release assets\n", n
    }' "$w/expected" "$report"
  refuse "the report does not record exactly the assets being released"
fi
echo "local-backfill evidence: $sha holds strict policy, and the report records its $(wc -l < "$w/expected-names" | tr -d ' ') assets exactly"
