#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/ingredients-settled.yml"

python3 - "$w" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]).read())
def fail(m):
    print("FAIL: " + m); sys.exit(1)

on = wf.get("on", wf.get(True))
mode = on["workflow_call"]["inputs"].get("mode") or fail("no mode input")
if not mode.get("required"): fail("mode must be required")

jobs = list(wf["jobs"].values())
if len(jobs) != 1: fail("expected exactly one job")
job = jobs[0]
perms = job.get("permissions", wf.get("permissions"))
if perms != {"contents": "read", "statuses": "write", "pull-requests": "read"}:
    fail("wrong permissions: %r" % perms)
if job["runs-on"] != "ubuntu-latest": fail("Linux runners only")

cond = job.get("if") or ""
if "github.event.pull_request.head.repo.full_name == github.repository" not in cond:
    fail("a fork pull request must skip: %r" % cond)
if "inputs.mode == 'sweep'" not in cond: fail("the sweep must not be skipped by the fork test")

steps = job["steps"]
co = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout")]
if len(co) != 1 or co[0].get("with", {}).get("fetch-depth") != 0:
    fail("checkout must use fetch-depth: 0")
if not any("actions/install@" in str(s.get("uses", "")) for s in steps): fail("shipyard is not installed")

pr = [s for s in steps if s.get("if") == "inputs.mode == 'pr'"]
sw = [s for s in steps if s.get("if") == "inputs.mode == 'sweep'"]
if len(pr) != 1 or len(sw) != 1: fail("need one pr step and one sweep step")
if "headRefOid" not in sw[0]["run"] or "baseRefOid" not in sw[0]["run"] or "labels" not in sw[0]["run"]:
    fail("sweep must read each PR's own head, base and labels")
if "renovate/" not in sw[0]["run"]: fail("sweep must select renovate/* branches")
if "isCrossRepository" not in sw[0]["run"]: fail("sweep must skip fork PRs")

for s in pr + sw:
    r = s["run"]
    if "ingredients-settled.sh" not in r: fail("step does not run ingredients-settled.sh")
    if "context=ingredients-settled" not in r: fail("status context must be ingredients-settled")
    if "statuses/" not in r: fail("step does not post a commit status")
    for st in ("success", "pending", "failure"):
        if "state=" + st not in r: fail("missing state " + st)
    if "0) state=success" not in r or "1) state=pending" not in r or "*) state=failure" not in r:
        fail("exit codes must map 0 success, 1 pending, anything else failure")
    if "[:140]" not in r or "grep -v '^::'" not in r: fail("description must skip :: lines and be trimmed to 140 characters")
    if "GH_TOKEN" not in str(s.get("env", {})): fail("step needs GH_TOKEN")

last = steps[-1]
if last.get("if") != "failure() && inputs.mode == 'pr'": fail("last step must post failure when the job fails in pr mode: %r" % last.get("if"))
if "state=failure" not in last["run"] or "context=ingredients-settled" not in last["run"]: fail("failure step must post failure to ingredients-settled")
if "github.event.pull_request.head.sha" not in str(last.get("env", {})) or "GH_TOKEN" not in str(last.get("env", {})): fail("failure step needs head sha and GH_TOKEN in env")
if "SHIPYARD" in str(last): fail("failure step must not depend on the install step")
if "</dev/null" not in sw[0]["run"]: fail("sweep loop commands must read /dev/null")

for s in steps:
    r = s.get("run") or ""
    if "gh run rerun" in r or "gh workflow run" in r: fail("no re-runs or dispatches")
    if "${{" in r: fail("an expression is interpolated into a run: script")
print("ok: ingredients-settled posts the status in both modes and skips fork PRs")
PY
echo "PASS: ingredients-settled-workflow"
