#!/bin/sh
# platform: host-agnostic
#   usage: local-backfill-report.sh [--notes NAME] REPO DIST SOURCE_SHA REPORT
#          The local-backfill evidence a release build hands publish-release.yml. Runs
#          check-local-backfills.sh, strict, on REPO, which must be the top of a git checkout whose
#          HEAD is SOURCE_SHA (a full commit sha) with no tracked file modified, and writes REPORT:
#          "source-sha<TAB>SOURCE_SHA", then one "asset<TAB><sha256><TAB><name>" per releasable
#          asset, sorted by name. Releasable is what release-assets.sh selects: every regular file
#          directly in DIST but the notes file (NAME, default RELEASE_NOTES.md) and SHA256SUMS. A
#          notes-only release has no asset records.
#          MAVERGREEN_CHECK_REPOSITORY passes through as the trusted identity. REPORT is uploaded as
#          the CI artifact local-backfill-report, never as a release asset, so it may not be
#          written into DIST. It is written only when every check passes.
#          Exit 0: written. 1: a policy finding. 2: a usage error, a source that is not SOURCE_SHA,
#          an asset name holding a tab or newline, or a check that could not run.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
die() { printf 'local-backfill-report: %s\n' "$*" >&2; exit 2; }
usage="usage: local-backfill-report.sh [--notes NAME] REPO DIST SOURCE_SHA REPORT"
notes=RELEASE_NOTES.md
case "${1:-}" in
  --notes) [ "$#" -ge 2 ] || die "$usage"; notes="$2"; shift 2 ;;
  -*) die "$usage" ;;
esac
[ "$#" -eq 4 ] || die "$usage"
repo="$1"; dist="$2"; sha="$3"; report="$4"
TAB="$(printf '\t')"
NL='
'

[ -d "$repo" ] || die "$repo is not a directory"
[ -d "$dist" ] || die "$dist is not a directory"
case "$sha" in *[!0-9a-f]*|'') die "the source must be a full commit sha, got '$sha'" ;; esac
[ "${#sha}" -eq 40 ] || die "the source must be a full 40-character commit sha, got '$sha'"
rdir="$(dirname "$report")"
[ -d "$rdir" ] || die "$rdir does not exist"
[ "$(cd "$rdir" && pwd -P)" != "$(cd "$dist" && pwd -P)" ] \
  || die "$report is inside $dist: the report is the local-backfill-report CI artifact, never a release asset"

top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" \
  || die "$repo is not a git checkout, and the evidence names a commit"
[ "$(cd "$top" && pwd -P)" = "$(cd "$repo" && pwd -P)" ] || die "$repo is not the top of its git checkout ($top is)"
head="$(git -C "$repo" rev-parse --verify -q 'HEAD^{commit}')" || die "$repo has no HEAD commit"
[ "$head" = "$sha" ] || die "$repo is checked out at $head, not at the build source $sha"
dirty="$(git -C "$repo" status --porcelain --untracked-files=no)" || die "git status failed in $repo"
[ -z "$dirty" ] || die "tracked files in $repo differ from $sha, so they are not the source the report names:
$dirty"

w="$(mktemp -d "${TMPDIR:-/tmp}/local-backfill-report.XXXXXX")"
trap 'rm -rf "$w"' EXIT
rc=0; sh "$SELF/check-local-backfills.sh" "$repo" || rc=$?
case "$rc" in
  0) ;;
  1) echo "local-backfill-report: $repo at $sha fails strict local-backfill policy; no report written" >&2; exit 1 ;;
  *) die "check-local-backfills.sh could not check $repo (exit $rc)" ;;
esac

: > "$w/rows"
for f in "$dist"/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  case "$b" in
    "$notes"|SHA256SUMS) continue ;;
    *"$TAB"*|*"$NL"*) die "an asset name in $dist holds a tab or a newline, which the report cannot record" ;;
  esac
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$f" > "$w/h"; else sha256sum < "$f" > "$w/h"; fi \
    || die "could not hash $f"
  h="$(awk 'NR == 1 { print $1 }' "$w/h")"
  case "$h" in *[!0-9a-f]*|'') die "could not hash $f" ;; esac
  [ "${#h}" -eq 64 ] || die "could not hash $f"
  printf 'asset\t%s\t%s\n' "$h" "$b" >> "$w/rows"
done
{ printf 'source-sha\t%s\n' "$sha"; LC_ALL=C sort -t "$TAB" -k 3 "$w/rows"; } > "$w/report"
mv "$w/report" "$report.tmp.$$" && mv "$report.tmp.$$" "$report" || die "could not write $report"
