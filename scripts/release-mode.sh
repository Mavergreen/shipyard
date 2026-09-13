#!/bin/sh
#   usage: VER="$(sh "$SHIPYARD_SCRIPTS/resolve-version.sh" "$(sh "$SHIPYARD_SCRIPTS/release-mode.sh")")"
#          Prints the version mode for THIS run: "local" (a repackage, N+1) or "auto" (the shipped N).
#          env in: GITHUB_EVENT_NAME, LOCAL_RELEASE (the workflow's local_release input, as a string)
# spec: tests/release-mode-test.sh -- every job in one run must answer identically; a push, even one
#       carrying the input by accident, must not invent a new N.
set -eu

if [ "${GITHUB_EVENT_NAME:-}" = workflow_dispatch ] && [ "${LOCAL_RELEASE:-}" = true ]; then
  echo local
else
  echo auto
fi
