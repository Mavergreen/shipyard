#!/bin/sh
# platform: host-agnostic
#   usage: NEEDS_JSON='<toJSON(needs)>' required-gate.sh
#          Exits 1 with one ::error::<job> <result> line per needed job whose result is not success
#          or skipped. Exits 2 when NEEDS_JSON is empty, malformed, or not an object of objects.
set -eu
# platform: CI-only (Linux and modern macOS runners), never the 10.9 build path, so python3 is available.
NEEDS_JSON="${NEEDS_JSON:-}" exec python3 -c '
import json, os, sys
def misconfigured(why):
    print("::error::required-gate: " + why)
    sys.exit(2)
raw = os.environ["NEEDS_JSON"].strip()
if not raw:
    misconfigured("the gate needs nothing -- wire every other job into needs:")
try:
    needs = json.loads(raw)
except ValueError:
    misconfigured("NEEDS_JSON is not valid JSON")
if not isinstance(needs, dict):
    misconfigured("NEEDS_JSON must be a JSON object keyed by job")
if not needs:
    misconfigured("the gate needs nothing -- wire every other job into needs:")
if not all(isinstance(v, dict) for v in needs.values()):
    misconfigured("every value in NEEDS_JSON must be an object")
bad = [(job, v.get("result")) for job, v in needs.items() if v.get("result") not in ("success", "skipped")]
for job, result in bad:
    print("::error::%s %s" % (job, result if result is not None else "no result"))
sys.exit(1 if bad else 0)
'
