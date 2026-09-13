#!/bin/sh
# spec: find_package(MavericksShipyard) has to work under WHATEVER cmake is on PATH, so discovery
#       cannot depend on the payload living in a directory that cmake happens to search.
#       CMAKE_SYSTEM_PREFIX_PATH is a property of the cmake BINARY -- it varies per machine and
#       can change under us -- so register-with-cmake.sh tells cmake where the payload is instead
#       of hoping it looks there. That is also what frees the payload to live in a product-owned
#       /usr/local/mavericks-shipyard instead of squatting in the shared /usr/local/share/cmake,
#       which pkgsrc and Homebrew also write into.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/register-with-cmake.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/register-with-cmake.XXXXXX")"; trap 'rm -rf "$work"' EXIT

payload="$work/payload"; mkdir -p "$payload"
home="$work/home"; mkdir -p "$home"
entry="$home/.cmake/packages/MavericksShipyard/mavericks-shipyard"

sh "$S" "$payload" "$home" >/dev/null || { echo "FAIL: registering a real payload should succeed"; exit 1; }
[ -f "$entry" ] || { echo "FAIL: no registry entry at $entry"; exit 1; }
[ "$(cat "$entry")" = "$payload" ] || { echo "FAIL: entry says '$(cat "$entry")', want '$payload'"; exit 1; }

second="$work/payload2"; mkdir -p "$second"
sh "$S" "$second" "$home" >/dev/null
[ "$(cat "$entry")" = "$second" ] || { echo "FAIL: writing again must REPLACE the path"; exit 1; }
[ "$(ls "$home/.cmake/packages/MavericksShipyard" | wc -l | tr -d ' ')" = "1" ] \
  || { echo "FAIL: the entry filename is fixed, so entries must not accumulate and no migration is ever needed -- an install simply points the one entry at itself"; exit 1; }

if sh "$S" "$work/nope" "$home" >/dev/null 2>&1; then
  echo "FAIL: a payload that is not there is a bug in the caller, not something to record -- a missing payload dir must be refused"; exit 1
fi

out="$(PATH=/nonexistent /bin/sh "$S" "$payload" "$home" 2>&1)" && { echo "FAIL: no cmake must be refused"; exit 1; }
printf '%s' "$out" | grep -qi 'cmake is not on PATH' || { echo "FAIL: shipyard's scripts half work without cmake, so the refusal must SAY cmake -- a real message a person acts on, not a crash; got: $out"; exit 1; }

echo "PASS: register-with-cmake"
