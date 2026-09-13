#!/bin/sh
# spec: SKILL.md "Release notes" section, "A failed upload must not strand a draft" -- the golang
#       1.26.8-mavericks.3 incident and the retry design this asserts are documented there.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/publish-release.yml"

python3 - "$w" <<'PY'
import sys, yaml
steps = []
for job in yaml.safe_load(open(sys.argv[1]))["jobs"].values():
    steps += job.get("steps") or []
def fail(msg):
    print("FAIL: " + msg); sys.exit(1)
def cleans(s):
    return "delete-draft-release.sh" in (s.get("run") or "")

pubs = [i for i, s in enumerate(steps) if "action-gh-release" in (s.get("uses") or "")]
if len(pubs) < 2:
    fail("one publish attempt: a failed upload strands a draft with no tag")
first = steps[pubs[0]]
for i in pubs:
    s = steps[i]
    if s.get("with") != first.get("with"):
        fail("publish attempt %r has different inputs from the first" % s.get("name"))
    if not s.get("id"):
        fail("publish attempt %r has no id, so nothing can ask whether it failed" % s.get("name"))
for i in pubs[:-1]:
    if steps[i].get("continue-on-error") is not True:
        fail("attempt %r is not continue-on-error: its failure ends the job before any retry" % steps[i].get("name"))
if steps[pubs[-1]].get("continue-on-error"):
    fail("the last attempt is continue-on-error: a publish that never happened would go green")

for prev, cur in zip(pubs, pubs[1:]):
    cond = "steps.%s.outcome == 'failure'" % steps[prev]["id"]
    if cond not in (steps[cur].get("if") or ""):
        fail("attempt %r does not run only when %r failed" % (steps[cur].get("name"), steps[prev]["id"]))
    between = steps[prev + 1:cur]
    if not any(cleans(s) and cond in (s.get("if") or "") for s in between):
        fail("no draft cleanup, gated on %r failing, before attempt %r" % (steps[prev]["id"], steps[cur].get("name")))

after = steps[pubs[-1] + 1:]
final = [s for s in after if cleans(s) and "failure()" in (s.get("if") or "")]
if not final:
    fail("nothing removes the draft when the last attempt fails")
if "exit 1" not in final[0]["run"]:
    fail("the final cleanup does not fail the job: a deleted draft must not read as a publish")
print("ok: %d publish attempts, each retry after a draft cleanup, and a final cleanup that fails" % len(pubs))
PY
echo "PASS: publish-retry"
