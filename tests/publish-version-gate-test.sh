#!/bin/sh
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Publishing a release" --
#       publish-release.yml re-checks the version and its notes before anything uploads.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/publish-release.yml"

python3 - "$w" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get("on", wf.get(True))
inputs = on["workflow_call"]["inputs"]
steps = []
for job in wf["jobs"].values():
    steps += job.get("steps") or []

def fail(msg):
    print("FAIL: " + msg); sys.exit(1)

def step_cmds(step):
    lines = [l for l in (step.get("run") or "").splitlines() if not l.lstrip().startswith("#")]
    joined = re.sub(r"\\\s*\n\s*", " ", "\n".join(lines))
    return [" ".join(l.split()) for l in joined.splitlines() if l.strip()]

p = inputs.get("product")
if not p or p.get("required") is not True:
    fail("the product input is missing or not required")
m = inputs.get("release-mode")
if not m or m.get("default") != "auto":
    fail("the release-mode input is missing or does not default to auto")

co = [s for s in steps
      if "actions/checkout" in (s.get("uses") or "")
      and "github.repository" in str((s.get("with") or {}).get("repository", ""))
      and str((s.get("with") or {}).get("fetch-depth")) == "0"
      and (s.get("with") or {}).get("path") == ".caller"]
if not co:
    fail("no checkout of github.repository with fetch-depth: 0 into .caller")

def disabled(s):
    return re.sub(r"\s+", "", str(s.get("if", ""))).lower() in ("false", "${{false}}")

gate = []
for i, s in enumerate(steps):
    cmds = step_cmds(s)
    if any(".shipyard/scripts/check-release-version.sh" in c and "--publishing yes" in c
           and "--notes-file" in c and "--root .caller" in c for c in cmds):
        gate.append(i)
if len(gate) != 1:
    fail("want exactly one step calling check-release-version.sh with --publishing yes, --notes-file "
         "and --root .caller (got %d)" % len(gate))
g = gate[0]
if "if" in steps[g] and steps[g]["if"] not in (None, True):
    fail("the version gate step has an if:")
if str(steps[g].get("continue-on-error", "")).lower() == "true":
    fail("the version gate step is continue-on-error")

dl = [i for i, s in enumerate(steps) if "actions/download-artifact" in (s.get("uses") or "")
      and (s.get("with") or {}).get("name")]
if not dl or g < dl[0]:
    fail("the version gate runs before the artifact download")
tag = [i for i, s in enumerate(steps) if any("assert_tag_publishable.sh" in c for c in step_cmds(s))]
if not tag or g > tag[0]:
    fail("the version gate does not run before the assert_tag_publishable.sh step")
pubs = [i for i, s in enumerate(steps) if "action-gh-release" in (s.get("uses") or "")]
if not pubs or g > pubs[0]:
    fail("the version gate does not run before the first publish")
if steps.index(co[0]) > g:
    fail("the .caller checkout comes after the version gate")

print("ok: the publish gate re-checks the version and notes before anything uploads")
PY
echo "PASS: publish-version-gate"
