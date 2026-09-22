#!/bin/sh
#   usage: MAVERICKS_NOTES_LINE=<line> release-notes-file.sh <TAG> <FULL_VERSION> [PRODUCT_NAME]
#          Back-compat wrapper delegating to the generator, release-notes.sh: six repos still call
#          this positional signature from their release.yml. The PRODUCT argument here is the
#          family's older prose phrase ("Mavericks OpenSSH"); the generator wants the bare noun, so a
#          leading "Mavericks " / trailing " for Mavericks" is stripped when present. A repo shipping
#          one line of several (golang: --line 1.26, the prefix its tags carry) scopes the baseline
#          through MAVERICKS_NOTES_LINE (forwarded to the generator's --line) rather than a new
#          positional argument, since the positional signature itself is unchanged.
# spec: tests/release-notes-file-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"

TAG="${1:?release-notes-file: TAG required}"
FULL="${2:?release-notes-file: FULL version required}"
PRODUCT="${3:-ModernMavericks}"
PRODUCT="${PRODUCT#Mavericks }"
PRODUCT="${PRODUCT% for Mavericks}"

out="$(mktemp "${TMPDIR:-/tmp}/release-notes-file.XXXXXX")"
trap 'rm -f "$out"' EXIT
sh "$SELF/release-notes.sh" --tag "$TAG" --version "$FULL" --product "$PRODUCT" \
   --min-os 10.9.5 --out "$out" ${MAVERICKS_NOTES_LINE:+--line "$MAVERICKS_NOTES_LINE"} >&2
trap - EXIT
printf '%s\n' "$out"
