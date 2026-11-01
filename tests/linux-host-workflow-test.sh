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
alljobs = lh.get("jobs") or {}
vm = {n: j for n, j in alljobs.items()
      if any(str(st.get("uses", "")).startswith("Mavergreen/mavericks-vm@") for st in (j.get("steps") or []))}
jobs = {n: j for n, j in alljobs.items() if n not in vm}
if len(jobs) != 1:
    bad.append("linux-host.yml must define exactly one strict-host job besides its 10.9 job, got %d" % len(jobs))
if len(vm) != 1:
    bad.append("linux-host.yml must define one job that launches the Linux-built updater on 10.9 with "
               "Mavergreen/mavericks-vm, got %d" % len(vm))
for name, job in vm.items():
    needs = job.get("needs") or []
    needs = [needs] if isinstance(needs, str) else needs
    if not set(needs) & set(jobs):
        bad.append("linux-host.yml's 10.9 job %s must need the job that builds the updater" % name)
    steps = job.get("steps") or []
    dl = [st for st in steps if str(st.get("uses", "")).startswith("actions/download-artifact@")
          and (st.get("with") or {}).get("name") == "shipyard-updater-linux"]
    run = " ".join(str((st.get("with") or {}).get("run", "")) for st in steps
                   if str(st.get("uses", "")).startswith("Mavergreen/mavericks-vm@"))
    if not dl or "sh tests/lib/launch-updater.sh " not in run or "shipyard-updater-linux.tar" not in run:
        bad.append("linux-host.yml's 10.9 job %s must download shipyard-updater-linux and run "
                   "tests/lib/launch-updater.sh on its shipyard-updater-linux.tar in the guest" % name)
    if (job.get("permissions") or {}).get("packages") != "write":
        bad.append("linux-host.yml's 10.9 job %s needs packages: write, for mavericks-vm's shared guest cache" % name)
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

for name, job in jobs.items():
    steps = job.get("steps") or []
    at = [i for i, st in enumerate(steps) if str(st.get("uses", "")).startswith("actions/setup-node@")]
    use = [i for i, st in enumerate(steps) if "renovate-config-validator" in str(st.get("run", ""))]
    node = steps[at[0]].get("with", {}).get("node-version") if at else None
    if not use or not at or at[0] > use[0] or str(node) != "24":
        bad.append("linux-host.yml job %s must set up node 24 before the Renovate validator, which needs ^24.11.0" % name)

for name, job in jobs.items():
    steps = job.get("steps") or []
    strict = [i for i, st in enumerate(steps) if "--strict-host" in str(st.get("run", ""))]
    out = str(((steps[strict[0]].get("env") or {}) if strict else {}).get("UPDATER_TEST_OUT", ""))
    up = [st for st in steps[strict[0] + 1:] if strict and str(st.get("uses", "")).startswith("actions/upload-artifact@")]
    path = str((up[0].get("with") or {}).get("path", "")) if up else ""
    if not out or not up or path != out.rstrip("/") + "/shipyard-updater-linux.tar":
        bad.append("linux-host.yml job %s must set UPDATER_TEST_OUT on the --strict-host step and then upload "
                   "UPDATER_TEST_OUT/shipyard-updater-linux.tar, the Linux-built updater a Mac-built one is compared with" % name)
    elif str((up[0].get("with") or {}).get("if-no-files-found", "")) != "error":
        bad.append("linux-host.yml job %s must upload the Linux-built updater with if-no-files-found: error, "
                   "or a test that never built it uploads nothing and passes" % name)

def callers(n):
    return [j for j, spec in (load(n).get("jobs") or {}).items()
            if spec.get("uses") == "./.github/workflows/linux-host.yml"]
for n in ("ci.yml", "release.yml"):
    for j in callers(n):
        spec = load(n)["jobs"][j]
        sec = spec.get("secrets")
        if not isinstance(sec, dict) or set(sec) != {"MAVERICKS_VM_KEY"} \
           or (spec.get("permissions") or {}).get("packages") != "write":
            bad.append("%s's %s must pass MAVERICKS_VM_KEY alone (never secrets: inherit, which would hand "
                       "the signing key to the test suites) and grant packages: write, or the 10.9 job "
                       "cannot open its guest" % (n, j))
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
