#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
wf="$here/../.github/workflows"

python3 - "$wf" <<'PY'
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

python3 - "$wf" <<'PY'
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
            lines = [l for l in (step.get("run") or "").splitlines() if not l.lstrip().startswith("#")]
            joined = re.sub(r"\\\s*\n\s*", " ", "\n".join(lines))
            out += [" ".join(l.split()) for l in joined.splitlines() if l.strip()]
    return out

ci, rel = cmds("ci.yml"), cmds("release.yml")
def has(cs, pat): return any(re.search(pat, c) for c in cs)

# Each of these is a step release.yml would otherwise run for the first time while publishing.
# The two install-smoke lines carry their failure plumbing INTO the pattern. Both run under `set -eu`
# with the failure caught, so the installer log can be dumped before the step dies -- and `|| true` in
# place of `|| bad=1` turns the whole smoke into decoration while every other assertion stays green
# (R-P1-20). A pattern that stops at the command name cannot see that.
for pat, what in ((r"^sh tests/lib/build-updater\.sh --arch x86_64 --arch arm64 ", "build the universal updater with clang22 (tests/lib/build-updater.sh)"),
                  (r"^sh scripts/package-pkg\.sh ", "build the pkg (scripts/package-pkg.sh)"),
                  (r"^sh scripts/assert_pkg_installs_in_place\.sh ", "gate the pkg (scripts/assert_pkg_installs_in_place.sh)"),
                  (r"^sudo installer -pkg .* \|\| bad=1$", "install the pkg on the runner, recording failure (sudo installer ... || bad=1)"),
                  (r"^sh scripts/assert-installed-shipyard\.sh --cmake-version \"\$\(sed 's/-mavericks\\\.\.\*//' components/cmake/version\)\" .* \|\| bad=1$",
                   "assert the install against the Kitware part of components/cmake/version, recording failure "
                   "(scripts/assert-installed-shipyard.sh ... || bad=1)"),
                  # The merge's own result, asserted rather than assumed: lipo-merge-tree.sh's
                  # --require-archs covers every Mach-O in the tree, and this says out loud that the
                  # one binary the whole pkg exists to deliver came out with both slices.
                  (r'^case " \$archs " in \*" arm64 "\*\) ;; \*\) echo "::error::the merged updater has no arm64 slice',
                   "assert the merged updater carries an arm64 slice")):
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
for name in ("ci.yml", "release.yml"):
    d = yaml.safe_load(open(os.path.join(wf, name)))
    for job, spec in (d.get("jobs") or {}).items():
        if not str(spec.get("runs-on", "")).startswith("macos-"):
            continue
        steps = spec.get("steps") or []
        fetching = [i for i, st in enumerate(steps)
                    if re.search(r"(^|\n)\s*sh (tests/lib/build-updater|scripts/run-repo-tests)\.sh\b", str(st.get("run", "")))]
        if not fetching:
            continue
        cached = [i for i, st in enumerate(steps) if str(st.get("uses", "")).startswith("actions/cache@")
                  and str((st.get("with") or {}).get("path", "")).strip() == "~/Library/Caches/mavergreen-clang22"
                  and "hashFiles('components/clang22/version')" in str((st.get("with") or {}).get("key", ""))]
        if not cached or cached[0] > fetching[0]:
            bad.append("%s job %s fetches clang22 (the ~2 GB clang22-cross, unpacked) with no actions/cache of "
                       "~/Library/Caches/mavergreen-clang22 keyed on hashFiles('components/clang22/version') "
                       "before it, so every run on a scarce macOS runner downloads and expands it again" % (name, job))
if os.path.exists(os.path.join(wf, "..", "actions", "shipyard-cmake")):
    bad.append(".github/actions/shipyard-cmake still exists")

if bad:
    for b in bad:
        print("FAIL:", b)
    sys.exit(1)
print("ok: ci.yml rehearses the packaging path release.yml only ever runs while publishing, and "
      "neither builds CMake")
PY
echo "PASS: shipyard-workflow-coupling"
