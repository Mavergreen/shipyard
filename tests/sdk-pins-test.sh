#!/bin/sh
# platform: host-agnostic
#   usage: sdk-pins-test.sh
#          The family's SDK rule, pins and content exemption, exercised on their exit statuses.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/sdk-pins.sh"
yes() { mav_sdk_rule "$@" >/dev/null || { echo "FAIL: should comply: $*"; exit 1; }; }
no()  { if mav_sdk_rule "$@" >/dev/null; then echo "FAIL: should violate: $*"; exit 1; fi; }

yes x86_64 EXECUTE 10.9 10.9
no  x86_64 EXECUTE 10.9 26.5      # the audit's blind spot: minos right, SDK the runner's
no  x86_64 EXECUTE 10.13 10.9
yes arm64 EXECUTE 11.0 11.3
no  arm64 EXECUTE 11.0 26.5
no  arm64 EXECUTE 26.0 26.5       # clang-cross today
yes x86_64 DYLIB 10.9 10.9
yes x86_64 KEXTBUNDLE - -         # kexts record no version (spec D6)
no  arm64 KEXTBUNDLE - -
yes x86_64 OBJECT 10.9 n/a        # a 10.9-SDK archive member cannot record its SDK
no  x86_64 OBJECT 10.7 n/a
no  x86_64 EXECUTE 10.9 n/a       # only an OBJECT gets the n/a allowance
no  i386 OBJECT 10.7 26.5
no  arm64e OBJECT 11.0 26.5
why="$(mav_sdk_rule x86_64 EXECUTE 10.9 26.5 || true)"
printf '%s' "$why" | grep -q 'sdk 26.5' || { echo "FAIL: a violation must say what was recorded: $why"; exit 1; }

set -- $(mav_sdk_pin arm64)
[ "$2" = cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4 ] || { echo "FAIL: arm64 pin sha: $2"; exit 1; }
[ "$4" = MacOSX11.3.sdk ] || { echo "FAIL: arm64 sdk dir: $4"; exit 1; }
set -- $(mav_sdk_pin x86_64)
[ "$2" = fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0 ] || { echo "FAIL: x86_64 pin sha: $2"; exit 1; }
if mav_sdk_pin i386 >/dev/null; then echo "FAIL: i386 has no pin"; exit 1; fi

mav_sdk_exempt_sha256 4ea4718635b69a7746078674aba2af31249d20e3155010bd06f1e9d5487c94b2 || { echo "FAIL: Sparkle fileop is exempt"; exit 1; }
if mav_sdk_exempt_sha256 0000000000000000000000000000000000000000000000000000000000000000; then echo "FAIL: arbitrary bytes are not exempt"; exit 1; fi
if mav_sdk_exempt_sha256 ''; then echo "FAIL: an empty digest is not exempt"; exit 1; fi

echo "PASS: sdk-pins"
