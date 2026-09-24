#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Release workflow" -- the version is baked into pkgbuild --version, the pkg
#       filename, and the appcast's <sparkle:version>, so a tag collision must rebuild
#       (re-dispatch) and must never be relabeled. What the guard DECIDES is
#       tests/assert_tag_publishable.bats; this asserts only the wiring.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/publish-release.yml"

python3 - "$w" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = []
for job in wf["jobs"].values():
    steps += job.get("steps") or []
names = [s.get("name", "") for s in steps]

guard = [s for s in steps if "already" in (s.get("name") or "").lower() or "existing tag" in (s.get("name") or "").lower()]
if not guard:
    print("FAIL: no step guarding against an existing tag"); sys.exit(1)
g = guard[0]

body = g.get("run") or ""
for needle in ("assert_tag_publishable.sh",):
    if needle not in body:
        print("FAIL: the guard does not mention %r" % needle); sys.exit(1)

# It must run BEFORE the publish, or it guards nothing.
gi = steps.index(g)
pi = next(i for i, s in enumerate(steps) if "action-gh-release" in (s.get("uses") or ""))
if gi > pi:
    print("FAIL: the guard runs after the publish step"); sys.exit(1)
print("ok: publish is guarded by an existing-tag check at step %d, before publish at %d" % (gi, pi))
PY
echo "PASS: publish-tag-collision"
