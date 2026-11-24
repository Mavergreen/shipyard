#!/bin/sh
# platform: host-agnostic
#   usage: cut-release.sh REPO [--ref REF] [--force REASON]
#          Dispatches Mavergreen/REPO's release.yml on REF (default main) and watches the run to its end.
#          Plainly by default, so the release decision publishes only changed content; --force passes
#          -f force_publish=REASON, publishing whatever changed, REASON in the notes. Refuses while a run
#          of release.yml on REF is queued or running. Exit 0 when a release appeared ("released <tag>:
#          <url>"), or when a plain dispatch's run passed and its log says "Not published: content
#          identical to <tag>."; 1 when the run failed, it refused, a forced run published nothing, or a
#          plain one published nothing and said no reason; 2 on a usage error, a blank REASON, or
#          --if-needed. Needs gh, authenticated.
# spec: SKILL.md "Cutting a release"
set -eu
org=Mavergreen
die() { echo "cut-release: $*" >&2; exit 1; }
usage() { echo "usage: cut-release.sh REPO [--ref REF] [--force REASON]" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || die "needs the gh CLI"
[ $# -ge 1 ] || usage
name=$1; shift
case "$name" in ''|*/*|.*|-*) usage ;; esac
ref=main; reason=""; forced=no
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || usage; ref=$2; shift 2 ;;
    --force) [ $# -ge 2 ] || usage; reason=$2; forced=yes; shift 2 ;;
    --if-needed) echo "cut-release: --if-needed is the default now; drop it" >&2; exit 2 ;;
    *) usage ;;
  esac
done
if [ "$forced" = yes ] && [ -z "$(printf '%s' "$reason" | tr -d '[:space:]')" ]; then
  echo "cut-release: --force needs a reason; it goes into the release notes" >&2; exit 2
fi
repo="$org/$name"; wf=release.yml
poll="${CUT_RELEASE_POLL:-5}"

inflight="$(gh run list -R "$repo" --workflow "$wf" --branch "$ref" --limit 20 \
  --json databaseId,status --jq '.[] | select(.status != "completed") | "\(.databaseId) \(.status)"')" \
  || die "could not list $repo's $wf runs"
[ -z "$inflight" ] || die "$repo's $wf already has a run on $ref that is not done; let it finish first:
$inflight"

before="$(gh release view -R "$repo" --json tagName --jq .tagName 2>/dev/null || :)"
since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$forced" = yes ]; then
  gh workflow run "$wf" -R "$repo" --ref "$ref" -f "force_publish=$reason" >/dev/null || die "could not dispatch $repo's $wf"
  echo "cut-release: dispatched $repo's $wf on $ref with force_publish=$reason"
else
  gh workflow run "$wf" -R "$repo" --ref "$ref" >/dev/null || die "could not dispatch $repo's $wf"
  echo "cut-release: dispatched $repo's $wf on $ref"
fi

run=""; n=0
while [ -z "$run" ] && [ "$n" -lt 24 ]; do
  sleep "$poll"; n=$((n + 1))
  run="$(gh run list -R "$repo" --workflow "$wf" --branch "$ref" --event workflow_dispatch --limit 5 \
    --json databaseId,createdAt --jq "[.[] | select(.createdAt >= \"$since\")][0].databaseId // \"\"")"
done
[ -n "$run" ] || die "dispatched, but found no new run of $wf on $ref; look at https://github.com/$repo/actions"
echo "cut-release: watching https://github.com/$repo/actions/runs/$run"
# platform: gh run watch gives up while a job waits long for a runner and exits non-zero, which read
#           as a failed release (python-315, 2026-10-19), so the run's own status is polled instead.
until [ "$(gh run view "$run" -R "$repo" --json status --jq .status)" = completed ]; do
  sleep "${CUT_RELEASE_WAIT:-60}"
done
concl="$(gh run view "$run" -R "$repo" --json conclusion --jq .conclusion)" || die "could not read run $run's conclusion"
if [ "$concl" != success ]; then
  gh run view "$run" -R "$repo" --json jobs \
    --jq '.jobs[] | select(.conclusion != "success" and .conclusion != "skipped") | "  \(.name): \(.conclusion)"' >&2 || :
  die "run $run ended $concl: https://github.com/$repo/actions/runs/$run"
fi

after="$(gh release view -R "$repo" --json tagName --jq .tagName 2>/dev/null || :)"
if [ -n "$after" ] && [ "$after" != "$before" ]; then
  echo "cut-release: released $after: https://github.com/$repo/releases/tag/$after"
  exit 0
fi
if [ "$forced" = no ]; then
  same="$(gh run view "$run" -R "$repo" --log 2>/dev/null | tr -d '\r' | sed -n 's/.*Not published: content identical to \([^ ]*\)\.$/\1/p' | head -n 1)" || same=""
  [ -z "$same" ] || { echo "cut-release: run $run passed; nothing published: content identical to $same"; exit 0; }
fi
die "run $run passed but published nothing (the latest release is still ${before:-none}); read the run's ver job for why"
