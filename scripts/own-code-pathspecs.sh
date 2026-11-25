#!/bin/sh
# platform: host-agnostic
#   usage: own-code-pathspecs.sh [--root DIR] [--pins]
#          Prints, one per line, the git pathspecs that separate a repo's own code from its pins. By
#          default the :(exclude,...) pathspecs removing everything that is not own code:
#          UPSTREAM_VERSION, components/*/version, ingredients/**, .github/**, tests/**,
#          release-notes/**, top-level *.md, each file declared-state.sh names, and each INGREDIENTS.md
#          "## Conformance deviations" "- self-upstream-exclude:<glob>: <reason>". With --pins, the
#          positive pathspecs of the pins instead: UPSTREAM_VERSION, components/*/version,
#          ingredients/**, each declared-state file, and each ingredient-pins.sh path (run from DIR).
#          Exit 2 when declared-state.sh or deviations.sh refuses.
# spec: scripts/self-upstream-version.sh -- the one list its version and the release-notes checks share.
# spec: tests/own-code-pathspecs-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "usage: own-code-pathspecs.sh [--root DIR] [--pins]" >&2; exit 2; }

ROOT="."; PINS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="${2%/}"; shift 2 ;;
    --pins) PINS=1; shift ;;
    *) echo "own-code-pathspecs: unknown option $1" >&2; usage ;;
  esac
done

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/own-code-pathspecs.XXXXXX")"; trap 'rm -rf "$work"' EXIT

if ! sh "$SELF/declared-state.sh" "$ROOT" > "$work/decl" 2>"$work/err"; then
  cat "$work/err" >&2
  echo "own-code-pathspecs: $ROOT/INGREDIENTS.md has a malformed \"## Declared state\" declaration" >&2
  exit 2
fi

if [ "$PINS" = 1 ]; then
  printf '%s\n' ':(glob)UPSTREAM_VERSION' ':(glob)components/*/version' ':(glob)ingredients/**'
  cut -f2 "$work/decl" | sed 's/:.*//; s/^/:(literal)/'
  _rc=0
  (cd "$ROOT" && sh "$SELF/ingredient-pins.sh") > "$work/pins" 2>"$work/err" || _rc=$?
  if [ "$_rc" != 0 ]; then
    cat "$work/err" >&2
    echo "own-code-pathspecs: ingredient-pins.sh failed in $ROOT" >&2
    exit 2
  fi
  sed 's/:.*//; s/^/:(literal)/' "$work/pins"
  exit 0
fi

for p in UPSTREAM_VERSION 'components/*/version' 'ingredients/**' '.github/**' 'tests/**' 'release-notes/**' '*.md'; do
  printf ':(exclude,glob)%s\n' "$p"
done
cut -f2 "$work/decl" | sed 's/:.*//; s/^/:(exclude,literal)/'

if ! sh "$SELF/deviations.sh" "$ROOT" > "$work/devs" 2>"$work/err"; then
  cat "$work/err" >&2
  echo "own-code-pathspecs: $ROOT/INGREDIENTS.md declares a conformance deviation that deviations.sh refuses (it says why, above)" >&2
  exit 2
fi
while read -r check glob _; do
  [ "$check" = self-upstream-exclude ] || continue
  printf ':(exclude,glob)%s\n' "$glob"
done < "$work/devs"
