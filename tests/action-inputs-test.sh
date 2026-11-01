#!/bin/sh
# platform: host-agnostic
#   usage: action-inputs-test.sh
#          No composite action's metadata outside runs: holds an expression. GitHub evaluates ${{ }}
#          in an input's description too, where needs, jobs and steps do not exist, and the action then
#          fails to load in every caller (required-gate, 2026-10-27). Exit 0 clean, 1 on failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here"/../.github/actions/*/action.yml <<'PY'
import sys, yaml
bad = []
for f in sys.argv[1:]:
    a = yaml.safe_load(open(f))
    for k in ("name", "description"):
        if "${{" in str(a.get(k, "")):
            bad.append("%s: %s holds an expression" % (f, k))
    for n, i in (a.get("inputs") or {}).items():
        if "${{" in str((i or {}).get("description", "")):
            bad.append("%s: input %s's description holds an expression" % (f, n))
if bad:
    print("FAIL: action-inputs:\n  " + "\n  ".join(bad)); sys.exit(1)
print("PASS: action-inputs")
PY
