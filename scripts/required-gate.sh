#!/bin/sh
# platform: host-agnostic
#   usage: NEEDS_JSON='<toJSON(needs)>' required-gate.sh
#          Exits 1 with one ::error::<job> <result> line per needed job that failed or was cancelled;
#          skipped passes. Exits 2 when there is nothing to gate on.
set -eu
# platform: CI-only (Linux and modern macOS runners), never the 10.9 build path, so python3 is available.
NEEDS_JSON="${NEEDS_JSON:-}" exec python3 -c '
import json, os, sys
raw = os.environ["NEEDS_JSON"].strip()
needs = json.loads(raw) if raw else {}
if not needs:
    print("::error::the gate needs nothing -- wire every other job into needs:")
    sys.exit(2)
bad = [(job, v.get("result")) for job, v in needs.items() if v.get("result") in ("failure", "cancelled")]
for job, result in bad:
    print("::error::%s %s" % (job, result))
sys.exit(1 if bad else 0)
'
