#!/bin/sh
# platform: host-agnostic
#   usage: install-action-sdk-cache-test.sh
#          install@v1 restores and saves the pinned-SDK cache on macOS, keyed on the content of the
#          sdk-pins.sh it ships, so a changed pin never reuses a stale SDK. Exit 0 clean, 1 on failure.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here/../.github/actions/install/action.yml" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
bad = []
key = [s for s in steps if s.get("id") == "mav-sdk-key"]
cache = [s for s in steps if "actions/cache@" in (s.get("uses") or "")]
if len(key) != 1:
    bad.append("expected exactly one step with id mav-sdk-key, got %d" % len(key))
if len(cache) != 1:
    bad.append("expected exactly one actions/cache step, got %d" % len(cache))
if key and cache:
    k, c = key[0], cache[0]
    if "sdk-pins.sh" not in (k.get("run") or ""):
        bad.append("the key step must hash the action's own scripts/sdk-pins.sh")
    for s, what in ((k, "key"), (c, "cache")):
        if "runner.os == 'macOS'" not in (s.get("if") or ""):
            bad.append("the %s step must run on macOS only (fetch_sdk.sh's cache lives in ~/Library)" % what)
    w = c.get("with") or {}
    if "Library/Caches/mavericks-sdk" not in str(w.get("path")):
        bad.append("the cache path must be fetch_sdk.sh's default, ~/Library/Caches/mavericks-sdk")
    if "steps.mav-sdk-key.outputs.key" not in str(w.get("key")):
        bad.append("the cache key must come from steps.mav-sdk-key.outputs.key")
    if steps.index(c) < steps.index(k):
        bad.append("the key step must run before the cache step")
for s in steps:
    if (s.get("uses") or "").startswith("./"):
        bad.append("install@v1 must contain no `uses: ./...` (R-P1-19)")
if bad:
    print("FAIL: install-action-sdk-cache:\n  " + "\n  ".join(bad)); sys.exit(1)
print("PASS: install-action-sdk-cache")
PY
