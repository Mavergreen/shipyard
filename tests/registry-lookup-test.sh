#!/bin/sh
# platform: host-agnostic -- plain sh against a stand-in product-name.sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-reglookup.XXXXXX")
trap 'rm -rf "$T"' EXIT
SELF="$T"
. "$HERE/../scripts/registry-lookup.sh"

cat > "$T/product-name.sh" <<'STUB'
echo "noise a successful lookup must not return" >&2
echo dev.mavergreen.x
STUB
registry_lookup identifier x || { echo "FAIL: a successful lookup with stderr noise reads as a failure"; exit 1; }
[ "$REG_V" = dev.mavergreen.x ] || { echo "FAIL: stderr leaked into the answer: $REG_V"; exit 1; }

cat > "$T/product-name.sh" <<'STUB'
echo "product-name.sh: cannot read the registry /nowhere" >&2
exit 2
STUB
rc=0; registry_lookup identifier x || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: an unreadable registry returns $rc, not 2"; exit 1; }
case "$REG_WHY" in *"cannot read the registry /nowhere"*) ;; *) echo "FAIL: the reason is lost: $REG_WHY"; exit 1 ;; esac

cat > "$T/product-name.sh" <<'STUB'
exit 1
STUB
rc=0; registry_lookup identifier x || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: an unregistered key returns $rc, not 1"; exit 1; }

echo "PASS: registry-lookup"
