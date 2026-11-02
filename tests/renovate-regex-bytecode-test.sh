#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
caches() { find scripts -name __pycache__ -o -name '*.pyc'; }
[ -z "$(caches)" ] || { echo "FAIL renovate-regex-bytecode: scripts/ already holds bytecode, so this cannot tell who wrote it: $(caches)"; exit 1; }
unset PYTHONDONTWRITEBYTECODE
sh tests/renovate_preset.sh >/dev/null
rc=0; sh tests/renovate-captures-test.sh >/dev/null || rc=$?
[ "$rc" -eq 0 ] || [ "$rc" -eq 77 ]
sh scripts/shipyard-check --only renovate-suffix-versioning >/dev/null
[ -z "$(caches)" ] || { echo "FAIL renovate-regex-bytecode: importing renovate_regex wrote bytecode into scripts/: $(caches)"; caches | xargs rm -rf; exit 1; }
echo "PASS renovate-regex-bytecode"
