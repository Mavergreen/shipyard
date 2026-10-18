#!/bin/sh
# platform: host-agnostic
#   usage: cut-release.sh REPO [--ref REF] [--if-needed]
#          Cuts a release of Mavergreen/REPO by dispatching its release.yml on REF (default main), and
#          watches the run to its end. By default it asks for a publish: it passes whichever
#          publish-anyway input that release.yml declares (local_release, repackage or release) as
#          true, or dispatches plainly where it declares none. --if-needed dispatches plainly, so the
#          repo's own logic decides. Refuses while a run of release.yml on REF is queued or running.
#          Prints the tag and URL it published. Exit 0 when it published (or, with --if-needed, when the
#          run passed); 1 when the run failed, it refused, or a requested publish published nothing;
#          2 on a usage error. Needs gh, authenticated.
# spec: SKILL.md "Cutting a release"
set -eu
org=Mavergreen
die() { echo "cut-release: $*" >&2; exit 1; }
usage() { echo "usage: cut-release.sh REPO [--ref REF] [--if-needed]" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || die "needs the gh CLI"
[ $# -ge 1 ] || usage
name=$1; shift
case "$name" in ''|*/*|.*|-*) usage ;; esac
ref=main; mode=publish
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || usage; ref=$2; shift 2 ;;
    --if-needed) mode=if-needed; shift ;;
    *) usage ;;
  esac
done
repo="$org/$name"; wf=release.yml
poll="${CUT_RELEASE_POLL:-5}"

inflight="$(gh run list -R "$repo" --workflow "$wf" --branch "$ref" --limit 20 \
  --json databaseId,status --jq '.[] | select(.status != "completed") | "\(.databaseId) \(.status)"')" \
  || die "could not list $repo's $wf runs"
[ -z "$inflight" ] || die "$repo's $wf already has a run on $ref that is not done; let it finish first:
$inflight"

yml="$(gh api "repos/$repo/contents/.github/workflows/$wf?ref=$ref" --jq .content | base64 -d 2>/dev/null)" \
  || die "could not read $repo's .github/workflows/$wf at $ref"
inputs="$(printf '%s\n' "$yml" | awk '/^  workflow_dispatch:/ { on = 1; next } on && /^  [^ ]/ { exit }
  on && /^      [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { sub(/^ +/, ""); sub(/:.*/, ""); print }')"
printf '%s\n' "$yml" | grep -q '^  workflow_dispatch:' || die "$repo's $wf has no workflow_dispatch trigger"

field=""
if [ "$mode" = publish ]; then
  for i in local_release repackage release; do
    if printf '%s\n' "$inputs" | grep -qx "$i"; then field="$i=true"; break; fi
  done
fi

before="$(gh release view -R "$repo" --json tagName --jq .tagName 2>/dev/null || :)"
since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -n "$field" ]; then
  gh workflow run "$wf" -R "$repo" --ref "$ref" -f "$field" >/dev/null || die "could not dispatch $repo's $wf"
  echo "cut-release: dispatched $repo's $wf on $ref with -f $field"
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
if ! gh run watch "$run" -R "$repo" --exit-status >/dev/null 2>&1; then
  gh run view "$run" -R "$repo" --json jobs \
    --jq '.jobs[] | select(.conclusion != "success" and .conclusion != "skipped") | "  \(.name): \(.conclusion)"' >&2 || :
  die "run $run failed: https://github.com/$repo/actions/runs/$run"
fi

after="$(gh release view -R "$repo" --json tagName --jq .tagName 2>/dev/null || :)"
if [ -n "$after" ] && [ "$after" != "$before" ]; then
  echo "cut-release: released $after: https://github.com/$repo/releases/tag/$after"
  exit 0
fi
[ "$mode" = if-needed ] && { echo "cut-release: run $run passed and published nothing: none was needed"; exit 0; }
die "run $run passed but published nothing (the latest release is still ${before:-none}); read the run's ver job for why"
