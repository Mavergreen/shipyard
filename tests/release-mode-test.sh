#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Versioning" -- release-mode.sh exists because container-tools built one .pkg
#       from two jobs that disagreed (build-macos resolved -mavericks.15, build-iso .14, same run,
#       same commit); every job in one run must answer identically, not guess per-job.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-mode.sh"

got() { printf '%s' "$(env "$@" sh "$S")"; }

out="$(got GITHUB_EVENT_NAME=workflow_dispatch LOCAL_RELEASE=true)"
[ "$out" = local ] || { echo "FAIL dispatch+local_release should be local: '$out'"; exit 1; }

out="$(got GITHUB_EVENT_NAME=workflow_dispatch LOCAL_RELEASE=false)"
[ "$out" = auto ] || { echo "FAIL: a plain dispatch is not a repackage, should be auto: '$out'"; exit 1; }

out="$(got GITHUB_EVENT_NAME=workflow_dispatch)"
[ "$out" = auto ] || { echo "FAIL: an unset LOCAL_RELEASE is not a repackage either, should be auto: '$out'"; exit 1; }

out="$(got GITHUB_EVENT_NAME=push LOCAL_RELEASE=true)"
[ "$out" = auto ] || { echo "FAIL: a push is never a repackage, should be auto even with the input set: '$out'"; exit 1; }

out="$(got GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag)"
[ "$out" = auto ] || { echo "FAIL: a tag build takes its version from the tag so the mode is irrelevant -- still answer auto rather than inventing a third value the callers would have to handle: '$out'"; exit 1; }

out="$(got PATH="$PATH")"
[ "$out" = auto ] || { echo "FAIL: no event at all (a developer running it by hand) should be auto, the safe answer that never invents a new N: '$out'"; exit 1; }

echo "PASS: release-mode"
