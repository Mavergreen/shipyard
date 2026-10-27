#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/retry-release.yml"

python3 - "$w" <<'PY'
import sys, yaml
raw = open(sys.argv[1]).read()
wf = yaml.safe_load(raw)
def fail(m):
    print("FAIL: " + m); sys.exit(1)

on = wf.get("on", wf.get(True))
inputs = on["workflow_call"]["inputs"]
v = inputs.get("version") or fail("no version input")
if not v.get("required"): fail("version must be required")
r = inputs.get("release-workflow") or fail("no release-workflow input")
if r.get("default") != "release.yml": fail("release-workflow must default to release.yml")
if r.get("required"): fail("release-workflow must be optional")

job = list(wf["jobs"].values())
if len(job) != 1: fail("expected exactly one job")
job = job[0]
if job.get("permissions") != {"contents": "read", "actions": "write"}:
    fail("job permissions must be contents: read, actions: write, got %r" % job.get("permissions"))

steps = job["steps"]
dec = [s for s in steps if s.get("id") == "decide"]
if not dec: fail("no decide step")
if "retry-decision.sh" not in dec[0].get("run", ""): fail("decide step does not run retry-decision.sh")
if "github.event.inputs.reconcile" not in str(dec[0].get("env", {})): fail("decide step is not given github.event.inputs.reconcile")

disp = [s for s in steps if "gh workflow run" in (s.get("run") or "")]
if len(disp) != 1: fail("expected exactly one dispatch step")
d = disp[0]
cond = d.get("if") or ""
if "steps.decide.outputs.answer" not in cond or "'RETRY'" not in cond:
    fail("dispatch must be conditioned on the decision output being RETRY: %r" % cond)
if "-f reconcile=true" not in d["run"]: fail("dispatch must pass -f reconcile=true")
if "--ref main" not in d["run"]: fail("dispatch must use --ref main")
if "::notice::" not in d["run"]: fail("dispatch must say which version it lost")
if steps.index(d) < steps.index(dec[0]): fail("dispatch runs before the decision")

for s in steps:
    if "${{ inputs." in (s.get("run") or "") or "${{ github.event.inputs." in (s.get("run") or ""):
        fail("an input is interpolated into a run: script")
print("ok: retry-release dispatches only on RETRY, with reconcile=true")
PY
echo "PASS: retry-release-workflow"
