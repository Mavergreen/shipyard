#!/bin/sh
# platform: host-agnostic
#   usage: install-action-linux-version-test.sh
#          Off macOS, install@v1 exports SHIPYARD_VERSION, resolved from the ref the caller pinned, so
#          build-base-component.sh can name the base's version where the action's checkout has no .git
#          and no installed config (ed25519's Linux packaging, 2026-10-27). Exit 0 clean, 1 on failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here/../.github/actions/install/action.yml" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
off = [s for s in steps if "inputs.source == 'release'" in (s.get("if") or "") and "runner.os != 'macOS'" in (s.get("if") or "")]
bad = []
if len(off) != 1:
    bad.append("expected one release step off macOS, got %d" % len(off))
else:
    r = off[0].get("run") or ""
    if "resolve-action-version.sh" not in r:
        bad.append("the off-macOS step must resolve the pinned ref with resolve-action-version.sh")
    if "SHIPYARD_VERSION=$ver" not in r:
        bad.append("the off-macOS step must export SHIPYARD_VERSION=$ver to GITHUB_ENV")
if bad:
    print("FAIL: install-action-linux-version:\n  " + "\n  ".join(bad)); sys.exit(1)
print("PASS: install-action-linux-version")
PY
