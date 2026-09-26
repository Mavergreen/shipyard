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
    # release-state.sh refuses (exit 2) a declared `upstream` that is not the file version.sh reads.
    # So a product whose upstream lives elsewhere -- container-tools and tailscale
    # (components/*/version) -- cannot render state here at all unless it can say where: without
    # this input it would hard-fail nightly from its first run after adopting the documented
    # ten-line caller.
    if "upstream-file" not in ins:
        fail.append("reconcile.yml has no upstream-file input: a product whose upstream is not "
                    "UPSTREAM_VERSION cannot render state here, because release-state.sh exits 2 "
                    "when the declared upstream is not the file version.sh reads")
    elif ins["upstream-file"].get("default") != "":
        fail.append("upstream-file must default to '' -- both readers use "
                    "${MAVERICKS_UPSTREAM_FILE:-UPSTREAM_VERSION}, so empty means the default path")

# ...and the input has to REACH the scripts. An input nothing wires through is the same hard failure
# with an extra place to look.
state_steps = [s for j in wf["jobs"].values() for s in j.get("steps", []) if s.get("id") == "state"]
if not state_steps:
    fail.append("reconcile.yml has no step with id: state -- the digest and version come from there")
else:
    env = state_steps[0].get("env") or {}
    if "upstream-file" not in str(env.get("MAVERICKS_UPSTREAM_FILE", "")):
        fail.append("the state step does not set MAVERICKS_UPSTREAM_FILE from inputs.upstream-file: "
                    "both release-state.sh and version.sh read it there, and they must agree")

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

# A derived pin (ca-certs' NSS_TAG) needs build/derive-upstream-version.sh run before version.sh
# reads its (gitignored) output -- but only when the repo tracks that script, since most callers
# (container-tools, tailscale) do not have one.
idx_guard = state_run.find("git ls-files --error-unmatch build/derive-upstream-version.sh")
idx_derive = state_run.find("sh build/derive-upstream-version.sh", idx_guard + 1 if idx_guard >= 0 else 0)
idx_version = state_run.find("SHIPYARD_SCRIPTS/version.sh")
if idx_guard < 0:
    fail.append("the state step never checks whether build/derive-upstream-version.sh is tracked "
                "(git ls-files --error-unmatch build/derive-upstream-version.sh)")
if idx_derive < 0 or idx_derive < idx_guard:
    fail.append("the state step never runs build/derive-upstream-version.sh guarded on that check")
if idx_version < 0 or idx_version < idx_derive:
    fail.append("build/derive-upstream-version.sh must run before version.sh, which reads its output")

# version.sh's own exit status must decide the step, not sed's -- a `version.sh ... | sed ...`
# takes its status from the last command in the pipe, so version.sh failing (e.g. no
# UPSTREAM_VERSION on a fresh checkout) would be swallowed until a later step.
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
#       below, never re-typed) against a fake repo, so a tracked derive script's output must reach
#       version.sh, and version.sh failing (a fresh checkout with no derive script run) must fail
#       the step at once rather than being swallowed by a pipeline.
python3 - "$root" <<'PY'
import os, pathlib, stat, subprocess, sys, tempfile, yaml

root = pathlib.Path(sys.argv[1])
wf = yaml.safe_load((root / ".github/workflows/reconcile.yml").read_text())
state_steps = [s for j in wf["jobs"].values() for s in j.get("steps", []) if s.get("id") == "state"]
run = state_steps[0]["run"]

fail = []

def executable(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)

def simulate(tracked_derive, upstream_version_present):
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        repo = d / "repo"; repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)
        (repo / "build").mkdir()
        derive = repo / "build/derive-upstream-version.sh"
        executable(derive, "#!/bin/sh\nset -eu\nprintf '%s\\n' v1.0.421 > UPSTREAM_VERSION\n")
        if tracked_derive:
            subprocess.run(["git", "add", "build/derive-upstream-version.sh"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "t"], cwd=repo, check=True)
        if upstream_version_present and not tracked_derive:
            (repo / "UPSTREAM_VERSION").write_text("v1.0.421\n")

        scripts = d / "scripts"; scripts.mkdir()
        executable(scripts / "release-state.sh",
                    "#!/bin/sh\nprintf 'v1:sha256:%s\\n' " + "0" * 64 + "\n")
        executable(scripts / "version.sh",
                    "#!/bin/sh\nset -eu\n"
                    "[ -f UPSTREAM_VERSION ] || { echo 'version.sh: no UPSTREAM_VERSION' >&2; exit 1; }\n"
                    "u=\"$(cat UPSTREAM_VERSION)\"\n"
                    "printf 'FULL=%s-mavericks.1\\nTAG=%s-mavericks.1\\nRELEASE=no\\n' \"$u\" \"$u\"\n")

        out_file = d / "github_output"; out_file.write_text("")
        env = dict(os.environ)
        env["SHIPYARD_SCRIPTS"] = str(scripts)
        env["GITHUB_OUTPUT"] = str(out_file)
        env["MAVERICKS_UPSTREAM_FILE"] = ""
        proc = subprocess.run(["sh", "-c", run], cwd=repo, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return proc, out_file.read_text()

# A tracked derive script on a fresh checkout (no UPSTREAM_VERSION yet) must still produce the
# derived version -- this is the ca-certs shape the bug report reproduced.
proc, out = simulate(tracked_derive=True, upstream_version_present=False)
if proc.returncode != 0:
    fail.append("simulated state step failed on a fresh checkout with a tracked derive script "
                "(stdout=%r stderr=%r)" % (proc.stdout, proc.stderr))
elif "version=v1.0.421-mavericks.1" not in out:
    fail.append("simulated state step did not derive the pinned version: outputs=%r stderr=%r"
                % (out, proc.stderr))

# No derive script tracked and no UPSTREAM_VERSION present (the untouched fresh-checkout bug):
# version.sh fails, and that failure must fail the step immediately, never swallowed by a pipeline.
proc, _ = simulate(tracked_derive=False, upstream_version_present=False)
if proc.returncode == 0:
    fail.append("simulated state step exited 0 even though version.sh had nothing to read -- its "
                "exit status is being swallowed (e.g. by `version.sh ... | sed ...`)")

if fail:
    for f in fail: print("FAIL: " + f)
    sys.exit(1)
print("ok: state step simulation (tracked derive runs before version.sh; version.sh's failure is not swallowed)")
PY

echo "PASS: reconcile-workflow"
