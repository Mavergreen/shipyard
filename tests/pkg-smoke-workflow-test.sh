#!/bin/sh
# platform: host-agnostic
#   usage: pkg-smoke-workflow-test.sh
#          ci.yml waits on no macOS runner: package builds the pkg on Linux, and pkg-smoke.yml installs
#          it on Mac OS X 10.9 in mavericks-vm, after the cmake product its preinstall requires, then
#          runs the install assertions and tests/on-target-tests there.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here/../.github/workflows" <<'PY'
import os, re, sys, yaml
wf = sys.argv[1]
bad = []
def load(n):
    p = os.path.join(wf, n)
    return yaml.safe_load(open(p)) if os.path.exists(p) else None

ci = load("ci.yml")
jobs = ci.get("jobs") or {}
for name, job in jobs.items():
    ro = job.get("runs-on", "")
    for r in (ro if isinstance(ro, list) else [ro]):
        if str(r).startswith("macos-"):
            bad.append("ci.yml job %s runs on %s; branch pushes and PRs must wait for no macOS runner" % (name, r))

smoke_callers = [n for n, j in jobs.items() if j.get("uses") == "./.github/workflows/pkg-smoke.yml"]
if smoke_callers != ["pkg-smoke"]:
    bad.append("ci.yml must call ./.github/workflows/pkg-smoke.yml from one job named pkg-smoke, got %r" % smoke_callers)
else:
    caller = jobs["pkg-smoke"]
    needs = caller.get("needs") or []
    needs = [needs] if isinstance(needs, str) else needs
    if "package" not in needs:
        bad.append("ci.yml's pkg-smoke must need package, which builds the pkg it installs")
    if (caller.get("with") or {}).get("artifact") != "shipyard-rehearsal-pkg":
        bad.append("ci.yml's pkg-smoke must pass artifact: shipyard-rehearsal-pkg")
    sec = caller.get("secrets")
    if not isinstance(sec, dict) or set(sec) != {"MAVERICKS_VM_KEY"}:
        bad.append("ci.yml's pkg-smoke must pass MAVERICKS_VM_KEY alone, never secrets: inherit")
    if (caller.get("permissions") or {}).get("packages") != "write":
        bad.append("ci.yml's pkg-smoke must grant packages: write, or mavericks-vm cannot pull its guest")

ps = load("pkg-smoke.yml")
if ps is None:
    bad.append("no .github/workflows/pkg-smoke.yml")
else:
    on = ps.get("on") or ps.get(True) or {}
    if set(on) != {"workflow_call"}:
        bad.append("pkg-smoke.yml must be reusable only (on: workflow_call), got %r" % sorted(on))
    call = on.get("workflow_call") or {}
    if set(call.get("inputs") or {}) != {"artifact", "ref"}:
        bad.append("pkg-smoke.yml must take the inputs artifact and ref, got %r" % sorted(call.get("inputs") or {}))
    if set(call.get("secrets") or {}) != {"MAVERICKS_VM_KEY"}:
        bad.append("pkg-smoke.yml must take the secret MAVERICKS_VM_KEY alone")
    pj = ps.get("jobs") or {}
    if set(pj) != {"smoke"}:
        bad.append("pkg-smoke.yml must define one job, smoke, got %r" % sorted(pj))
    smoke = pj.get("smoke") or {}
    if smoke.get("runs-on") != "ubuntu-latest":
        bad.append("pkg-smoke.yml's smoke must run on ubuntu-latest, got %r" % smoke.get("runs-on"))
    guard = "github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository"
    if " ".join(str(smoke.get("if", "")).split()) != guard:
        bad.append("pkg-smoke.yml's smoke must carry the fork guard `if: %s`; a fork's PR has no "
                   "MAVERICKS_VM_KEY, got %r" % (guard, smoke.get("if")))
    steps = smoke.get("steps") or []
    vm = [st for st in steps if str(st.get("uses", "")).startswith("Mavergreen/mavericks-vm@")]
    if len(vm) != 1:
        bad.append("pkg-smoke.yml's smoke must run one Mavergreen/mavericks-vm step, got %d" % len(vm))
    else:
        guest = [l.strip() for l in str((vm[0].get("with") or {}).get("run", "")).splitlines()
                 if l.strip() and not l.strip().startswith("#")]
        inst = [i for i, l in enumerate(guest) if re.match(r"sudo -n installer -pkg ", l)]
        cm = [i for i in inst if "cmake" in guest[i]]
        sy = [i for i in inst if "cmake" not in guest[i]]
        if not cm or not sy:
            bad.append("the guest must sudo -n installer the cmake pkg and the shipyard pkg, got %r" % [guest[i] for i in inst])
        elif max(cm) > min(sy):
            bad.append("the guest must install the cmake pkg before the shipyard pkg, whose preinstall refuses a box without it")
        if not any(re.match(r"sh scripts/assert-installed-shipyard\.sh --no-slices --cmake-version .* --root / ", l) for l in guest):
            bad.append("the guest must run sh scripts/assert-installed-shipyard.sh --no-slices --cmake-version ... --root /; "
                       "10.9's lipo cannot read the arm64 slices, which package checks on Linux")
        if not any(re.search(r"done < tests/on-target-tests$", l) for l in guest):
            bad.append("the guest must run each line of tests/on-target-tests")
        # spec: tests/shipyard-workflow-coupling-test.sh R-P1-20 -- each check records its failure and
        #       the script ends on it, so `|| true` in place of `|| bad=1` cannot turn the smoke into decoration.
        for what, pat in (("the cmake install", r"sudo -n installer -pkg cmake-pkg/"),
                          ("the shipyard install", r"sudo -n installer -pkg shipyard-pkg/"),
                          ("the install assertion", r"sh scripts/assert-installed-shipyard\.sh "),
                          ("/usr/local/bin/mavergreen check", r"/usr/local/bin/mavergreen check "),
                          ("on-target test", r'sh "\$t" ')):
            if not any(re.match(pat + r".*\|\| bad=1$", l) for l in guest):
                bad.append("the guest must record a failed %s with `|| bad=1`" % what)
        if not guest or guest[-1] != '[ "$bad" -eq 0 ]':
            bad.append('the guest script must end on [ "$bad" -eq 0 ], or a recorded failure exits 0')
    runs = "\n".join(str(st.get("run", "")) for st in steps)
    if not re.search(r"gh release download .*-R Mavergreen/cmake --pattern '\*\.pkg' --pattern SHA256SUMS", runs):
        bad.append("pkg-smoke.yml must download the pinned cmake release's pkg and SHA256SUMS on the runner")
    if "sha256sum -c --strict" not in runs:
        bad.append("pkg-smoke.yml must verify the cmake pkg against its SHA256SUMS with sha256sum -c --strict")
    if not re.search(r'::error::cmake \$v has no pkg', runs):
        bad.append("pkg-smoke.yml must fail by name (::error::cmake $v has no pkg) when the cmake release has none")

if bad:
    for b in bad: print("FAIL: " + b)
    sys.exit(1)
print("ok: ci.yml packages on Linux and smoke-installs on 10.9, cmake first, with no macOS job")
PY
