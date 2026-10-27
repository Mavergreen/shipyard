#!/bin/sh
# platform: host-agnostic
#   usage: required-checks.sh [DIR]
#          Prints, one per line and sorted, the check contexts branch protection should require for the
#          clone at DIR (default .): "<job name or key> / conventions" for each job in a tracked workflow that
#          uses family-conventions.yml, and "required (<stem>)" for each tracked workflow triggered by
#          pull_request, and "ingredients-settled" for a workflow whose every job uses Mavergreen/shipyard's
#          ingredients-settled.yml (such a workflow needs no gate job; one with other jobs still does).
#          A workflow whose every job uses family-conventions.yml needs no gate job either; its own
#          "<name> / conventions" context is the check. Tracked means listed by git ls-files .github/workflows. Exits 1, naming the file,
#          when a workflow does not parse, or a pull_request workflow has no job "required" named
#          "required (<stem>)". Exits 2 on a usage error or when git cannot list DIR.
# spec: SKILL.md "Creating a family repo"
set -eu
[ $# -le 1 ] || { echo "usage: required-checks.sh [DIR]" >&2; exit 2; }
dir="${1:-.}"
files="$(git -C "$dir" ls-files .github/workflows)" || { echo "required-checks: cannot list $dir's workflows" >&2; exit 2; }
cd "$dir"
printf '%s\n' "$files" | python3 -c '
import os, sys, yaml
bad = False
out = []
for path in sys.stdin.read().split("\n"):
    stem, ext = os.path.splitext(os.path.basename(path))
    if ext not in (".yml", ".yaml"):
        continue
    try:
        with open(path) as f:
            doc = yaml.safe_load(f)
    except (OSError, yaml.YAMLError) as e:
        print("required-checks: %s: cannot parse: %s" % (path, str(e).replace("\n", " ")), file=sys.stderr)
        bad = True
        continue
    if not isinstance(doc, dict):
        print("required-checks: %s: not a workflow mapping" % path, file=sys.stderr)
        bad = True
        continue
    on = doc["on"] if "on" in doc else doc.get(True)
    if isinstance(on, dict):
        on = list(on)
    elif isinstance(on, str):
        on = [on]
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        jobs = {}
    for key, job in jobs.items():
        if isinstance(job, dict) and str(job.get("uses", "")).split("@")[0].endswith("family-conventions.yml"):
            out.append("%s / conventions" % (job.get("name") or key))
    if jobs and all(
            isinstance(j, dict) and str(j.get("uses", "")).startswith("Mavergreen/shipyard/.github/workflows/ingredients-settled.yml@")
            for j in jobs.values()):
        out.append("ingredients-settled")
        continue
    if jobs and all(
            isinstance(j, dict) and str(j.get("uses", "")).split("@")[0].endswith("family-conventions.yml")
            for j in jobs.values()):
        continue
    if isinstance(on, list) and "pull_request" in on:
        want = "required (%s)" % stem
        gate = jobs.get("required")
        if not isinstance(gate, dict) or gate.get("name") != want:
            print("required-checks: %s: a pull_request workflow needs a job \"required\" named \"%s\"" % (path, want), file=sys.stderr)
            bad = True
        else:
            out.append(want)
if bad:
    sys.exit(1)
for c in sorted(set(out)):
    print(c)
'
