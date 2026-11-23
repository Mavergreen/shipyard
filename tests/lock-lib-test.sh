#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
L="$here/../scripts/mavergreen_fetch.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/lock-lib-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
. "$L"
command -v shipyard_lock_take >/dev/null 2>&1 || { echo "FAIL: mavergreen_fetch.sh defines no shipyard_lock_take"; exit 1; }

shipyard_lock_take "$w/a.lock" 0 || { echo "FAIL: a free lock must be taken at once"; exit 1; }
[ -f "$w/a.lock" ] || { echo "FAIL: a held lock is a regular file"; exit 1; }
[ "$shipyard_lock_waited" -eq 0 ] || { echo "FAIL: a free lock waits 0s, got $shipyard_lock_waited"; exit 1; }

if shipyard_lock_take "$w/a.lock" 0; then echo "FAIL: a held lock must not be taken twice"; exit 1; fi
if shipyard_lock_take "$w/a.lock" 1; then echo "FAIL: a lock still held after the wait must fail"; exit 1; fi
[ "$shipyard_lock_waited" -eq 1 ] || { echo "FAIL: waited must count the seconds waited, got $shipyard_lock_waited"; exit 1; }

shipyard_lock_release "$w/a.lock"
[ ! -e "$w/a.lock" ] || { echo "FAIL: release must remove the lock"; exit 1; }

shipyard_lock_take "$w/b.lock" 0
( sleep 1; shipyard_lock_release "$w/b.lock" ) &
shipyard_lock_take "$w/b.lock" 10 || { echo "FAIL: a lock released during the wait must be taken"; exit 1; }
wait
shipyard_lock_release "$w/b.lock"

mkdir "$w/c.lock"  # portability-ok: the lock directory an older shipyard leaves is this case's fixture
if shipyard_lock_take "$w/c.lock" 0; then echo "FAIL: an older shipyard's lock directory must count as held"; exit 1; fi
[ -d "$w/c.lock" ] || { echo "FAIL: a failed take must leave another holder's lock alone"; exit 1; }

# spec: scripts/mavergreen_fetch.sh -- uutils mkdir (Ubuntu 26.04) let several of 200 racers win; this lock must not.
round=1
while [ "$round" -le 5 ]; do
  rm -f "$w/r.lock" "$w"/win.*
  i=0
  while [ "$i" -lt 100 ]; do
    ( while [ ! -e "$w/go" ]; do :; done
      if shipyard_lock_take "$w/r.lock" 0; then : > "$w/win.$i"; fi ) &
    i=$((i + 1))
  done
  : > "$w/go"; wait; rm -f "$w/go"
  n="$(ls "$w" | grep -c '^win\.' || true)"
  [ "$n" -eq 1 ] || { echo "FAIL: round $round: $n of 100 racers took one lock"; exit 1; }
  round=$((round + 1))
done

echo "PASS: lock-lib"
