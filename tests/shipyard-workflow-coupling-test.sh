#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
wf="$here/../.github/workflows"
SHIPYARD_CHECK_DIR="$here/../scripts"
. "$SHIPYARD_CHECK_DIR/lib/py.sh"

chk_py /dev/stdin "$wf" <<'PY'
import sys, os, yaml
wf = sys.argv[1]
bad = []

for name in ("ci.yml", "release.yml"):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    for job, spec in (d.get("jobs") or {}).items():
        for step in (spec.get("steps") or []):
            if "actions/checkout" in (step.get("uses") or ""):
                depth = (step.get("with") or {}).get("fetch-depth")
                if str(depth) != "0":
                    bad.append("%s job %s checks out with fetch-depth=%r; shipyard-version.sh "
                               "refuses a shallow clone (a --depth 1 clone would silently yield "
                               "1.0.1, colliding with a real tag) -- ci.yml once lacked this and "
                               "went red the moment the shallow guard landed, the failure surfacing "
                               "as \"installed package says '1.0', derived version is ''\", nowhere "
                               "near the checkout step" % (name, job, depth))

# Exactly one workflow may run the suite on a push to main.
def pushes_to_main(d):
    on = d.get("on") or d.get(True) or {}
    push = on.get("push")
    if not isinstance(push, dict):
        return False
    if "branches-ignore" in push:
        return "main" not in push["branches-ignore"]
    br = push.get("branches") or []
    return "main" in br or "**" in br

runners = []
for name in os.listdir(wf):
    if not name.endswith((".yml", ".yaml")):
        continue
    d = yaml.safe_load(open(os.path.join(wf, name)))
    if not pushes_to_main(d):
        continue
    body = open(os.path.join(wf, name)).read()
    # A job calling a LOCAL reusable workflow runs that workflow's steps in this one.
    for job in (d.get("jobs") or {}).values():
        u = str(job.get("uses", ""))
        if u.startswith("./.github/workflows/"):
            body += open(os.path.join(wf, os.path.basename(u))).read()
    if "run-repo-tests" in body:
        runners.append(name)

if len(runners) != 1:
    bad.append("%d workflows run the suite on a push to main (%s); exactly one must, or \"the repo "
               "is red\" and \"we published\" get decided by different workflows -- ci.yml once "
               "failed on four consecutive commits while release.yml published v1.0.126, .129, "
               ".130 and .131 from the same trees" % (len(runners), ", ".join(sorted(runners)) or "none"))

if bad:
    for b in bad:
        print("FAIL:", b)
    sys.exit(1)
print("ok: full-depth checkouts, and one suite-runner on main")
PY

chk_py /dev/stdin "$wf" <<'PY'
import os, re, sys, yaml
wf = sys.argv[1]
bad = []

# COMMANDS, not the file's text: both files' comments name these scripts, so a substring search over
# the text stays green after the invocation itself is deleted.
def cmds(name):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    out = []
    for spec in (d.get("jobs") or {}).values():
        for step in (spec.get("steps") or []):
            run = step.get("run") or ""
            lines = [l for l in run.splitlines() if not l.lstrip().startswith("#")]
            joined = re.sub(r"\\\s*\n\s*", " ", "\n".join(lines))
            out += [" ".join(l.split()) for l in joined.splitlines() if l.strip()]
    return out

ci, rel = cmds("ci.yml"), cmds("release.yml")
def has(cs, pat): return any(re.search(pat, c) for c in cs)

# Each of these is a step release.yml would otherwise run for the first time while publishing.
for pat, what in ((r"^sh tests/lib/build-updater\.sh --arch x86_64 --arch arm64 ", "build the universal updater with clang22 (tests/lib/build-updater.sh)"),
                  (r"^sh scripts/package-pkg\.sh ", "build the pkg (scripts/package-pkg.sh)"),
                  (r"^sh scripts/assert_pkg_installs_in_place\.sh ", "gate the pkg (scripts/assert_pkg_installs_in_place.sh)"),
                  # The merge's own result, asserted rather than assumed: lipo-merge-tree.sh's
                  # --require-archs covers every Mach-O in the tree, and this says out loud that the
                  # one binary the whole pkg exists to deliver came out with both slices.
                  (r'^case " \$archs " in \*" arm64 "\*\) ;; \*\) echo "::error::the merged updater has no arm64 slice',
                   "assert the merged updater carries an arm64 slice"),
                  # The Linux-specific half: clang22's Mach-O tools, and the runner's cmake for the payload.
                  (r'^echo "LIPO=\$CL/bin/llvm-lipo"$', "export clang22's llvm-lipo as LIPO"),
                  (r'^cmake -S \. -B "\$RUNNER_TEMP/payload-build"$', "configure the payload with the runner's cmake"),
                  (r'^DESTDIR=\S+ cmake --install "\$RUNNER_TEMP/payload-build" ', "install the payload with the runner's cmake")):
    if not has(rel, pat):
        bad.append("release.yml no longer does: %s" % what)
    elif not has(ci, pat):
        bad.append("ci.yml does not rehearse release.yml's packaging path: it never runs %s, so that "
                   "step's first real execution would be a push that is already publishing" % what)

# spec: SKILL.md "SDK pinning" -- the rehearsal has no appcast or notes, so it runs the SDK audit on the
# dist alone, and requires that the audit checked at least one Mach-O slice; a change that quietly drops
# either would only be caught for real at the release push.
if not has(ci, r'^sh scripts/audit-release-sdks\.sh --dist "?\$RUNNER_TEMP/dist"? '):
    bad.append("ci.yml no longer checks sdk-pin conformance on the rehearsed pkg "
               '(scripts/audit-release-sdks.sh --dist "$RUNNER_TEMP/dist")')
if not has(ci, r"^grep -q 'Mach-O slices\)' "):
    bad.append("ci.yml's SDK rehearsal no longer requires at least one checked Mach-O slice "
               "(grep -q 'Mach-O slices)' on the audit's output), so an empty dist would pass it")

# R-P1-22: no `codesign --deep`, in either workflow. The updater app carries Sparkle as a VERSIONED
# framework, and `--verify --deep` of such an app is ambiguous by design -- "bundle format is
# ambiguous (could be app or framework)" -- so it fails on every runner. `--deep --sign -` is worse
# than useless here: it replaces Sparkle's own signature with an ad-hoc one, to re-seal a bundle
# nothing ever sealed. lipo already preserves each slice's signature verbatim.
for name, cs in (("ci.yml", ci), ("release.yml", rel)):
    for c in cs:
        if re.search(r'\bcodesign\b.*--deep', c):
            bad.append("%s runs codesign --deep (%s); an app containing a versioned framework cannot "
                       "be verified that way, and there is no bundle seal here to re-create" % (name, c))

# ONE statement of what an installed shipyard must look like. Either workflow asserting it inline is
# how the two drift apart, and the fixture test then covers neither.
for name, cs in (("ci.yml", ci), ("release.yml", rel)):
    for pat, what in ((r"cmake version ", "the CMake version"),
                      (r"\benv -i\b", "the stripped-environment find_package probe"),
                      # The INSTALLED app specifically. `lipo -info` on the freshly merged bundle in
                      # $RUNNER_TEMP is the merge step logging what it produced, not a claim about
                      # what Installer put on the volume.
                      (r"^lipo -info .*/Library/Application Support/Mavergreen/", "the installed updater's architectures")):
        if has(cs, pat):
            bad.append("%s asserts %s inline; that belongs in scripts/assert-installed-shipyard.sh, "
                       "which both workflows and tests/assert-installed-shipyard-test.sh share" % (name, what))

# spec: 2026-10-09 C4 -- shipyard builds no CMake: install@v1 installs the cmake product, so no job
#       builds a tree or hands one in.
for name in ("ci.yml", "release.yml"):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    for job, spec in (d.get("jobs") or {}).items():
        for step in (spec.get("steps") or []):
            if str(step.get("uses", "")) == "./.github/actions/shipyard-cmake":
                bad.append("%s job %s still runs ./.github/actions/shipyard-cmake" % (name, job))
            if "cmake-tree" in (step.get("with") or {}):
                bad.append("%s job %s still passes cmake-tree to install@v1" % (name, job))
cache_dir = {"macos-": "~/Library/Caches/mavergreen-clang22", "ubuntu-": "~/.cache/mavergreen-clang22"}
for name in ("ci.yml", "release.yml"):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    for job, spec in (d.get("jobs") or {}).items():
        host = [h for h in cache_dir if str(spec.get("runs-on", "")).startswith(h)]
        if not host:
            continue
        want = cache_dir[host[0]]
        steps = spec.get("steps") or []
        fetching = [i for i, st in enumerate(steps)
                    if re.search(r"(^|\n|\$\()\s*sh (tests/lib/build-updater|scripts/run-repo-tests|scripts/fetch_clang22)\.sh\b", str(st.get("run", "")))]
        if not fetching:
            continue
        cached = [i for i, st in enumerate(steps) if str(st.get("uses", "")).startswith("actions/cache@")
                  and str((st.get("with") or {}).get("path", "")).strip() == want
                  and "hashFiles('.mavergreen/ingredients/clang22/VERSION')" in str((st.get("with") or {}).get("key", ""))]
        if not cached or cached[0] > fetching[0]:
            bad.append("%s job %s fetches clang22 (~2 GB, unpacked) with no actions/cache of %s keyed on "
                       "hashFiles('.mavergreen/ingredients/clang22/VERSION') before it, so every run downloads and "
                       "expands it again" % (name, job, want))
# Linux has no shipyard-cmake.
for name in ("ci.yml", "release.yml"):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    for job, spec in (d.get("jobs") or {}).items():
        if not str(spec.get("runs-on", "")).startswith("ubuntu-"):
            continue
        for step in (spec.get("steps") or []):
            if re.search(r"(^|[\s;|&(=])shipyard-c(make|test|pack)\b", str(step.get("run") or "")):
                bad.append("%s job %s runs shipyard-cmake/ctest/cpack on ubuntu, where install@v1 provides none" % (name, job))
if os.path.exists(os.path.join(wf, "..", "actions", "shipyard-cmake")):
    bad.append(".github/actions/shipyard-cmake still exists")

if bad:
    for b in bad:
        print("FAIL:", b)
    sys.exit(1)
print("ok: ci.yml rehearses the packaging path release.yml only ever runs while publishing, and "
      "neither builds CMake")
PY
chk_py /dev/stdin "$wf" <<'PY'
import fnmatch, os, sys, yaml
wf = sys.argv[1]
branch = "flag-day"

def runs_on_push(name, branch):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    push = ((d.get("on") or d.get(True) or {})).get("push")
    if not isinstance(push, dict):
        return False
    if "branches-ignore" in push:
        return not any(fnmatch.fnmatchcase(branch, g) for g in push["branches-ignore"])
    if "branches" in push:
        return any(fnmatch.fnmatchcase(branch, g) for g in push["branches"])
    return True

bad = []
if not runs_on_push("ci.yml", branch):
    bad.append("ci.yml does not run on a push to %s" % branch)
if runs_on_push("release.yml", branch):
    bad.append("release.yml runs on a push to %s; only main may publish" % branch)
if bad:
    for b in bad:
        print("FAIL:", b)
    sys.exit(1)
print("ok: a push to flag-day runs ci.yml and not release.yml")
PY

chk_py /dev/stdin "$wf" "$here/../.github/actions/install/action.yml" <<'PY'
import os, re, sys, yaml
wf, install = sys.argv[1], sys.argv[2]
bad = []

def steps(name):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    return [(job, st) for job, spec in (d.get("jobs") or {}).items() for st in (spec.get("steps") or [])]

def runs(st):
    return "\n".join(l for l in (st.get("run") or "").splitlines() if not l.lstrip().startswith("#"))

def shipyard_check_calls(name):
    return [st for _, st in steps(name) if re.search(r"shipyard-check\b", runs(st))]

# family-conventions.yml runs shipyard-check and nothing else: the gate script is reached only through it.
fc = [runs(st) for _, st in steps("family-conventions.yml") if st.get("run")]
if not any(re.search(r"shipyard-check\s*$", r, re.M) for r in fc):
    bad.append("family-conventions.yml no longer runs shipyard-check")
if any("check-family-conventions" in r or "check-artifact-conformance" in r for r in fc):
    bad.append("family-conventions.yml runs a check script directly; it runs shipyard-check and nothing else")
pi = [st for _, st in steps("preset-icons.yml") if re.search(r"shipyard-check\s+--only\s+preset-icon", runs(st))]
if not pi:
    bad.append("preset-icons.yml no longer runs shipyard-check --only preset-icon")
if any("check-preset-icons" in runs(st) for _, st in steps("preset-icons.yml")):
    bad.append("preset-icons.yml runs check-preset-icons.sh directly")

# Each workflow that hands shipyard-check a dist gives it the version, the repo and the arch set it reads.
for name in ("ci.yml", "release.yml"):
    calls = [st for st in shipyard_check_calls(name) if re.search(r"shipyard-check\s+--dist\b", runs(st))]
    if not calls:
        bad.append("%s never runs shipyard-check --dist" % name)
    for st in calls:
        for var in ("SHIPYARD_CHECK_VERSION", "SHIPYARD_CHECK_REPO", "MAVERICKS_ALLOW_ARCHS"):
            if var not in (st.get("env") or {}) and var not in runs(st):
                bad.append("%s runs shipyard-check --dist without %s" % (name, var))
    if any("check-artifact-conformance" in runs(st) for _, st in steps(name)):
        bad.append("%s calls check-artifact-conformance.sh directly instead of through shipyard-check --dist" % name)

# Shipyard's own conventions run through the same command, in linux-host.yml, which both ci.yml and
# release.yml call.
if not any(re.search(r"shipyard-check\s*$", runs(st), re.M) for _, st in steps("linux-host.yml")):
    bad.append("linux-host.yml no longer runs shipyard-check (the checkout checks) on shipyard itself")
for name in ("ci.yml", "release.yml"):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    if not any(str(spec.get("uses", "")) == "./.github/workflows/linux-host.yml" for spec in (d.get("jobs") or {}).values()):
        bad.append("%s no longer calls linux-host.yml, where shipyard-check runs on shipyard itself" % name)
for name in ("ci.yml", "release.yml", "linux-host.yml"):
    if any("check-family-conventions.sh" in runs(st) for _, st in steps(name)):
        bad.append("%s runs the gate script directly; CI and developers run shipyard-check" % name)

# install@v1 puts shipyard-check on PATH where it installs scripts without the pkg.
act = yaml.safe_load(open(install))
if not any("runner.os != 'macOS'" in str(st.get("if", "")) and re.search(r"ln -sf \S*shipyard-check\S* ", str(st.get("run", "")))
           for st in (act.get("runs") or {}).get("steps") or []):
    bad.append("install@v1 no longer exports shipyard-check on Linux")

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md, the `bash32-parse` row -- the
#       reusable macOS path every pkg-building product runs carries the check, so no repo wires it.
mac32 = [st for st in (act.get("runs") or {}).get("steps") or []
         if "runner.os == 'macOS'" in str(st.get("if", "")) and re.search(r'shipyard-check"?\s+--only\s+bash32-parse', str(st.get("run", "")))]
if not mac32:
    bad.append("install@v1 has no macOS step running shipyard-check --only bash32-parse")
elif any("inputs.source" in str(st.get("if", "")) for st in mac32):
    bad.append("install@v1 runs bash32-parse for one source only; every macOS job needs it")

def jobs_calling(name, script):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    return [j for j, spec in (d.get("jobs") or {}).items()
            if any(script in runs(st) for st in (spec.get("steps") or []))]

script = "scripts/push-tag-with-token.sh"
if not jobs_calling("release.yml", script):
    bad.append("release.yml's major-tag job no longer moves the tag through %s" % script)
if not jobs_calling("ci.yml", script):
    bad.append("ci.yml has no job rehearsing %s, so the major-tag push would first run on main" % script)
ci = yaml.safe_load(open(os.path.join(wf, "ci.yml")))
for j in jobs_calling("ci.yml", script):
    spec = ci["jobs"][j]
    if "flag-day" not in str(spec.get("if", "")):
        bad.append("ci.yml job %s pushes a tag but is not limited to flag-day" % j)
    if (spec.get("permissions") or {}).get("contents") != "write":
        bad.append("ci.yml job %s needs job-level permissions: contents: write" % j)
    for st in spec.get("steps") or []:
        if "actions/checkout" in str(st.get("uses", "")) and str((st.get("with") or {}).get("persist-credentials")).lower() != "false":
            bad.append("ci.yml job %s checks out with credentials, so it would not rehearse the askpass push" % j)
    dels = [st for st in spec.get("steps") or [] if "--delete" in runs(st)]
    if not dels or any(st.get("if") != "always()" for st in dels):
        bad.append("ci.yml job %s must delete its rehearsal tag under if: always()" % j)

if bad:
    for b in bad:
        print("FAIL:", b)
    sys.exit(1)
print("ok: CI and developers run the same shipyard-check")
PY

chk_py /dev/stdin "$wf/ci.yml" <<'PY'
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1])).get("jobs") or {}
g = jobs.get("required") or {}
bad = []
if g.get("name") != "required (ci)":
    bad.append("ci.yml has no job \"required\" named \"required (ci)\", the one check branch protection requires")
else:
    needs = g.get("needs") or []
    needs = [needs] if isinstance(needs, str) else needs
    others = sorted(j for j in jobs if j != "required")
    if sorted(needs) != others:
        bad.append("required (ci) must need every other ci.yml job %r, not %r" % (others, sorted(needs)))
    if str(g.get("if", "")).strip() not in ("always()", "${{ always() }}"):
        bad.append("required (ci) must run if: always(), or a failed job skips it and a skipped check passes")
    if not str(g.get("runs-on", "")).startswith("ubuntu-"):
        bad.append("required (ci) must run on ubuntu, not %r" % g.get("runs-on"))
    if g.get("permissions") != {"contents": "read"}:
        bad.append("required (ci) must grant only contents: read, as linux does, not %r" % g.get("permissions"))
    steps = g.get("steps") or []
    if not any(str(st.get("uses", "")) == "./.github/actions/required-gate"
               and "toJSON(needs)" in str((st.get("with") or {}).get("needs", "")) for st in steps):
        bad.append("required (ci) must run ./.github/actions/required-gate with needs: toJSON(needs), the gate this commit ships")
for b in bad:
    print("FAIL:", b)
sys.exit(1 if bad else 0)
PY
checks="$(sh "$here/../scripts/required-checks.sh" "$here/..")" || { echo "FAIL: required-checks.sh refuses this repo's workflows"; exit 1; }
printf '%s\n' "$checks" | grep -qx 'required (ci)' || { echo "FAIL: required-checks.sh does not list required (ci): $checks"; exit 1; }
echo "ok: required (ci) gates every ci.yml job"
mac="$(grep -rnE 'macos-' "$here/../.github" --include='*.yml' --include='*.yaml' | grep -E 'runs-on|os:' || :)"
[ -z "$mac" ] || { printf '%s\n' "$mac"; echo "FAIL: shipyard runs no job on a macos-* runner; every job above must move to ubuntu"; exit 1; }
echo "ok: no job in .github runs on a macos-* runner"
vm="$(grep -rnE 'Mavergreen/mavericks-vm@|MAVERICKS_VM_KEY' "$here/../.github" || :)"
[ -z "$vm" ] || { printf '%s\n' "$vm"; echo "FAIL: shipyard's CI and release run no 10.9 VM job; its on-target tests are in tests/maintainer-tests, run by hand"; exit 1; }
echo "ok: no 10.9 VM job and no MAVERICKS_VM_KEY in .github"
echo "PASS: shipyard-workflow-coupling"
