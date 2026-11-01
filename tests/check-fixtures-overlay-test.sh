#!/bin/sh
# platform: host-agnostic
#   usage: check-fixtures-overlay-test.sh
#          A fixture is the shared _base/ with its own files laid over it, minus the paths its DELETE lists.
# spec: tests/check-fixtures-run.sh -- fixture base overlays.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL $1"; exit 1; }
git --version >/dev/null 2>&1 || { echo "SKIP check-fixtures-overlay-test: needs git"; exit 0; }
work="$(mktemp -d "${TMPDIR:-/tmp}/fixtures-overlay.XXXXXX")"; trap 'rm -rf "$work"' EXIT
fx="$work/checks"
mkdir -p "$fx/_base/lines/126" "$fx/no-lines-dir/pass" "$fx/no-lines-dir/fail" \
  "$fx/value-file-line/pass" "$fx/value-file-line/fail/.mavergreen/upstream" "$fx/_base/.mavergreen/upstream"
: > "$fx/_base/lines/126/UPSTREAM_VERSION"
echo 1.0.0 > "$fx/_base/.mavergreen/upstream/VERSION"
printf 'git\n' > "$fx/no-lines-dir/fail/NEEDS"
printf 'git\n' > "$fx/no-lines-dir/pass/NEEDS"
printf 'lines/126/UPSTREAM_VERSION\nlines\n' > "$fx/no-lines-dir/pass/DELETE"
printf '.mavergreen/upstream/VERSION\n' > "$fx/value-file-line/pass/FILES"
echo v1.0.0 > "$fx/value-file-line/fail/.mavergreen/upstream/VERSION"
mkdir -p "$fx/_base/.github/workflows"; cp "$here/fixtures/checks/_base/.github/workflows/release.yml" "$fx/_base/.github/workflows/release.yml"

out="$(SHIPYARD_FIXTURES_DIR="$fx" sh "$here/check-fixtures-run.sh" --jobs 1 2>&1)" || fail "the overlay fixtures should pass:
$out"
case "$out" in
  *"4 fixtures, 4 ran, 0 skipped"*) ;;
  *) fail "expected 4 fixtures run against the scratch base, got: $out" ;;
esac
echo "PASS check-fixtures-overlay-test"
