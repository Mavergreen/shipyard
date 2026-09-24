#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Versioning" -- resolve-version.sh is the ONE way a repo learns its full version
#       at build time; VERSION is a build product, not an input (a committed copy drifts, as
#       container-tools proved building -mavericks.14 from a file saying .2).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/resolve-version.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/resolve-version-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT

new_repo() {  # $1 = dir, $2 = upstream version
  mkdir -p "$work/$1"
  printf '%s\n' "$2" > "$work/$1/UPSTREAM_VERSION"
}

new_repo a 1.5.2
out="$(MAVERICKS_ROOT="$work/a" MAVERICKS_TAGS="1.5.2-mavericks.1
1.5.2-mavericks.3" sh "$S")"
[ "$out" = "1.5.2-mavericks.3" ] || { echo "FAIL derive from tags: got '$out'"; exit 1; }
[ "$(cat "$work/a/VERSION")" = "1.5.2-mavericks.3" ] \
  || { echo "FAIL: a repo with no VERSION file must WRITE the derived one, so the rest of the build (cmake configure, the updater bundle) reads the same string"; exit 1; }

printf '9.9.9-mavericks.9\n' > "$work/a/VERSION"
out="$(MAVERICKS_ROOT="$work/a" MAVERICKS_TAGS="" sh "$S")"
[ "$out" = "9.9.9-mavericks.9" ] \
  || { echo "FAIL: an existing VERSION file is a build product from earlier in THIS build and must be reused as-is -- every job in a run must agree, and re-deriving could pick up a tag pushed mid-run; got '$out'"; exit 1; }

new_repo b 20260727
out="$(MAVERICKS_ROOT="$work/b" MAVERICKS_TAGS="20260727-mavericks.14" sh "$S" local)"
[ "$out" = "20260727-mavericks.15" ] || { echo "FAIL: local mode is a repackage of the shipped upstream (N+1, same upstream): got '$out'"; exit 1; }

new_repo c 2.0.0
out="$(MAVERICKS_ROOT="$work/c" MAVERICKS_TAGS="1.9.0-mavericks.7" sh "$S")"
[ "$out" = "2.0.0-mavericks.1" ] || { echo "FAIL: a brand-new upstream has no tags yet, so N=1: got '$out'"; exit 1; }

new_repo d 1.0.0
: > "$work/d/VERSION"
if out="$(MAVERICKS_ROOT="$work/d" MAVERICKS_TAGS="" sh "$S" 2>&1)"; then
  echo "FAIL: an EMPTY VERSION file must fail loudly rather than yield an empty version -- artifacts named '-mavericks.' with nothing in front would look almost right; got '$out'"; exit 1
fi
printf '%s\n' "$out" | grep -qi 'empty' || { echo "FAIL should say VERSION is empty: $out"; exit 1; }

mkdir -p "$work/e"
if out="$(MAVERICKS_ROOT="$work/e" MAVERICKS_TAGS="" sh "$S" 2>&1)"; then
  echo "FAIL missing UPSTREAM_VERSION should fail; got '$out'"; exit 1
fi
printf '%s\n' "$out" | grep -q 'UPSTREAM_VERSION' || { echo "FAIL: no UPSTREAM_VERSION and no VERSION should say which file is missing, not 'cannot open': $out"; exit 1; }

mkdir -p "$work/f/lines/127"
printf '1.27.0\n' > "$work/f/lines/127/UPSTREAM_VERSION"
out="$(MAVERICKS_ROOT="$work/f" MAVERICKS_UPSTREAM_FILE="$work/f/lines/127/UPSTREAM_VERSION" \
       MAVERICKS_TAGS="1.27.0-mavericks.2" sh "$S")"
[ "$out" = "1.27.0-mavericks.2" ] \
  || { echo "FAIL: a repo whose upstream isn't at the fixed UPSTREAM_VERSION path (container-tools, tailscale: components/<name>/version) needs MAVERICKS_UPSTREAM_FILE (the same override the shared version.sh already honors) to say which file to read: got '$out'"; exit 1; }

echo "PASS: resolve-version"
