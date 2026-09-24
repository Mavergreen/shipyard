#!/bin/sh
# platform: host-agnostic
#   usage: linux-host-workflow-test.sh
#          The Linux job exists, runs the host-agnostic suites strictly on a Linux runner, and is
#          wired into both workflows -- ci.yml for branches and PRs, release.yml ahead of publish.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md check 22
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here/../.github/workflows" <<'PY'
import os, re, sys, yaml
wf = sys.argv[1]
bad = []
def load(n): return yaml.safe_load(open(os.path.join(wf, n)))

# COMMANDS, not text: a comment naming --strict-host must not count as running it.
def cmds(job):
    out = []
    for st in (job.get("steps") or []):
        run = st.get("run")
        if isinstance(run, str):
            out += [l.strip() for l in run.splitlines() if l.strip() and not l.strip().startswith("#")]
    return out

lh = load("linux-host.yml")
on = lh.get("on") or lh.get(True) or {}
if set(on) != {"workflow_call"}:
    bad.append("linux-host.yml must be reusable only (on: workflow_call), got %r" % sorted(on))
jobs = lh.get("jobs") or {}
if len(jobs) != 1:
    bad.append("linux-host.yml must define exactly one job, got %d" % len(jobs))
for name, job in jobs.items():
    ro = job.get("runs-on")
    if not (isinstance(ro, str) and ro.startswith("ubuntu-")):
        bad.append("linux-host.yml job %s must run on an ubuntu- runner, got %r" % (name, ro))
    # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md check 22 -- F2: called
    #       from release.yml this job otherwise inherits contents: write, a token it never needs
    #       to run apt and ~57 suites.
    perms = job.get("permissions")
    if perms != {"contents": "read"}:
        bad.append("linux-host.yml job %s must declare permissions: {contents: read}, got %r" % (name, perms))
    c = cmds(job)
    if "sh scripts/run-repo-tests.sh --strict-host" not in c:
        bad.append("linux-host.yml job %s never runs sh scripts/run-repo-tests.sh --strict-host" % name)
    if "sh scripts/check-family-conventions.sh" not in c:
        bad.append("linux-host.yml job %s never runs the conventions gate on Linux, where consumers run it" % name)

def callers(n):
    return [j for j, spec in (load(n).get("jobs") or {}).items()
            if spec.get("uses") == "./.github/workflows/linux-host.yml"]
if not callers("ci.yml"):
    bad.append("ci.yml has no job using ./.github/workflows/linux-host.yml -- branches and PRs never run on Linux")
rel = callers("release.yml")
if not rel:
    bad.append("release.yml has no job using ./.github/workflows/linux-host.yml -- a push to main never runs on Linux")
else:
    needs = (load("release.yml").get("jobs") or {}).get("publish", {}).get("needs") or []
    if not set(rel) & set(needs):
        bad.append("release.yml's publish does not need the Linux job (%s) -- a release could ship broken on Linux" % ", ".join(rel))

if bad:
    for b in bad: print("FAIL: " + b)
    sys.exit(1)
print("ok: the Linux job runs --strict-host and the gate, from ci.yml and ahead of release.yml's publish")
PY
