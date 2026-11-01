#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

command -v python3 >/dev/null 2>&1 || { echo "SKIP: no python3"; exit 77; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "SKIP: no PyYAML"; exit 77; }

python3 - "$root" <<'PY'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1])
p = root / ".github/workflows/reconcile.yml"
if not p.exists():
    print("FAIL: no .github/workflows/reconcile.yml"); sys.exit(1)
fail = []
wf = yaml.safe_load(p.read_text())
on = wf.get("on", wf.get(True))

if "workflow_call" not in on:
    fail.append("reconcile.yml must be reusable (workflow_call)")
else:
    ins = on["workflow_call"].get("inputs", {})
    for name, default in (("release-workflow", "release.yml"), ("dispatch-field", "local_release=true")):
        if name not in ins:
            fail.append(f"reconcile.yml has no {name} input")
        elif ins[name].get("default") != default:
            fail.append(f"{name} default must be {default!r}, matching repackage-on-ingredient-bump.yml")
    if "upstream-file" in ins:
        fail.append("reconcile.yml still has an upstream-file input: the upstream is always "
                    ".mavergreen/upstream/, and MAVERICKS_UPSTREAM_FILE is gone")

state_steps = [s for j in wf["jobs"].values() for s in j.get("steps", []) if s.get("id") == "state"]
if not state_steps:
    fail.append("reconcile.yml has no step with id: state -- the digest and version come from there")
elif "MAVERICKS_UPSTREAM_FILE" in (state_steps[0].get("env") or {}):
    fail.append("the state step still sets MAVERICKS_UPSTREAM_FILE, which nothing reads")

# The whole point of the backstop is that a quiet night is nearly free. macOS here would be 14
# product builds a night.
for job, spec in wf["jobs"].items():
    if "macos" in str(spec.get("runs-on", "")):
        fail.append(f"job {job} runs on macos: the backstop must stay on ubuntu (one API call a night)")

perms = wf.get("permissions", {})
if perms.get("actions") != "write":
    fail.append("reconcile.yml needs permissions.actions: write -- it dispatches the release run, and "
                "without it the backstop fails as silently as the lost release it exists to catch")
# It reads main and it reads releases; it must NOT be able to write one. The backstop used to
# backfill a digest onto a release it had INFERRED was this state from a version match -- and
# version.sh's `auto` mode maps every declared state of one upstream to one version, so that write
# could cement an unreleased state onto a release that did not contain it, permanently and silently
# (ruling 16). Marking a pre-migration release is a one-time migration step a human runs, with the
# digest computed exactly from that tag's own tree.
if perms.get("contents") != "read":
    fail.append("reconcile.yml must declare permissions.contents: read, not write -- the backstop "
                "reads state and dispatches; it never edits a release")

text = p.read_text()
for needed in ("release-state.sh", "release-needed.sh"):
    if needed not in text:
        fail.append(f"reconcile.yml never calls {needed}")
# The step cannot creep back: asserting the permission alone would not stop someone re-adding the
# call and then "fixing" the permission it needs. Matched on the INVOCATION form, not the bare name:
# $SHIPYARD_SCRIPTS is this workflow's only path to shipyard's scripts, so that prefix is the only
# way it could call one -- while NAMING the script in the unreadable-marker guidance is exactly what
# that warning has to do, since running it by hand is the escape.
if "SHIPYARD_SCRIPTS/release-state-record.sh" in text:
    fail.append("reconcile.yml calls release-state-record.sh -- the nightly backstop must never "
                "write a digest onto a release. That write is a migration step, run once, with a "
                "digest computed from the released tag's own tree (release-state.sh --ref)")
# main is where state is DECLARED; a branch is a proposal (spec decision 3).
if "ref: main" not in text:
    fail.append("reconcile.yml must check out main: a branch is a proposal, not a declaration")

state_run = state_steps[0]["run"] if state_steps else ""

if "derive-upstream-version" in state_run:
    fail.append("the state step runs a derive script itself: version.sh runs "
                ".mavergreen/hooks/derive-upstream-version, so a second caller could disagree with it")

# version.sh's own exit status must decide the step, not sed's -- a `version.sh ... | sed ...`
# takes its status from the last command in the pipe, so version.sh failing (e.g. no
# .mavergreen/upstream/ on a fresh checkout) would be swallowed until a later step.
version_line = next((l for l in state_run.splitlines() if "SHIPYARD_SCRIPTS/version.sh" in l), "")
if "|" in version_line:
    fail.append("the line invoking version.sh still pipes it directly (its exit status would be "
                "lost to the pipeline): %r" % version_line.strip())

if fail:
    for f in fail: print("FAIL: " + f)
    sys.exit(1)
print("ok: reconcile.yml")
PY

# spec: .github/workflows/reconcile.yml -- simulates the state step's own run: text (extracted
#       below, never re-typed) against a fake repo with shipyard's real scripts, so a PIN upstream
#       reaches its version through version.sh alone, and version.sh failing (a PIN with no derive
#       hook) fails the step at once rather than being swallowed by a pipeline.
python3 - "$root" <<'PY'
import os, pathlib, subprocess, sys, tempfile, yaml

root = pathlib.Path(sys.argv[1])
wf = yaml.safe_load((root / ".github/workflows/reconcile.yml").read_text())
state_steps = [s for j in wf["jobs"].values() for s in j.get("steps", []) if s.get("id") == "state"]
run = state_steps[0]["run"]

fail = []

def simulate(hook):
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        repo = d / "repo"; repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)
        (repo / ".mavergreen/upstream").mkdir(parents=True)
        (repo / ".mavergreen/upstream/PIN").write_text("v1.0.421@" + "0" * 40 + "\n")
        (repo / "INGREDIENTS.md").write_text("# x\n\n## Declared state\n\n- upstream: .mavergreen/upstream/PIN\n")
        if hook:
            (repo / ".mavergreen/hooks").mkdir()
            (repo / ".mavergreen/hooks/derive-upstream-version").write_text(
                "#!/bin/sh\nIFS= read -r p < .mavergreen/upstream/PIN\np=\"${p%%@*}\"\nprintf '%s\\n' \"${p#v}\"\n")
        subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "t"], cwd=repo, check=True)

        out_file = d / "github_output"; out_file.write_text("")
        env = dict(os.environ)
        for k in ("MAVERICKS_ROOT", "MAVERGREEN_ROOT", "MAVERICKS_TAGS", "SHIPYARD", "SELF"):
            env.pop(k, None)
        env["SHIPYARD_SCRIPTS"] = str(root / "scripts")
        env["GITHUB_OUTPUT"] = str(out_file)
        proc = subprocess.run(["sh", "-c", run], cwd=repo, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return proc, out_file.read_text()

proc, out = simulate(hook=True)
if proc.returncode != 0:
    fail.append("simulated state step failed on a PIN upstream with its derive hook "
                "(stdout=%r stderr=%r)" % (proc.stdout, proc.stderr))
elif "version=1.0.421-mavericks.1" not in out:
    fail.append("simulated state step did not derive the version from the PIN: outputs=%r stderr=%r"
                % (out, proc.stderr))

proc, _ = simulate(hook=False)
if proc.returncode == 0:
    fail.append("simulated state step exited 0 even though version.sh had no hook to derive the PIN's "
                "version -- its exit status is being swallowed (e.g. by `version.sh ... | sed ...`)")

if fail:
    for f in fail: print("FAIL: " + f)
    sys.exit(1)
print("ok: state step simulation (a PIN reaches version.sh's hook; version.sh's failure is not swallowed)")
PY

echo "PASS: reconcile-workflow"
