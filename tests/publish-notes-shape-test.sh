#!/bin/sh
# platform: host-agnostic
# spec: check-family-conventions.sh clause 14 gates a repo's wiring at PR time; publish-release.yml
#       itself is the one place EVERY release passes through -- hand-tagged, re-dispatched, or from a
#       repo that never had the PR gate -- so it is the only check a body regression cannot route
#       around.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/publish-release.yml"

python3 - "$w" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = []
for job in wf["jobs"].values():
    steps += job.get("steps") or []

def fail(msg):
    print("FAIL: " + msg); sys.exit(1)

# Strip whole-line comments and join backslash continuations before matching: a call left inside a
# comment (or behind `if: false` / the equivalent `if: ${{ false }}` expression form) must not read as
# "wired in" -- Task 4's fixture passed for the wrong reason once already, because the check it was
# supposed to prove had silently stopped running.
def step_cmds(step):
    lines = [l for l in (step.get("run") or "").splitlines() if not l.lstrip().startswith("#")]
    joined = re.sub(r"\\\s*\n\s*", " ", "\n".join(lines))
    return [" ".join(l.split()) for l in joined.splitlines() if l.strip()]

assets = [s for s in steps if s.get("id") == "assets"]
if not assets:
    fail("no step with id 'assets' -- the release-assets.sh step was renamed or removed")
a = assets[0]
if_norm = re.sub(r"\s+", "", str(a.get("if", ""))).lower()
if if_norm in ("false", "${{false}}"):
    fail("the assets step is disabled (if: false)")

cmds = step_cmds(a)

# The literal path, not just the script's basename: publish-release.yml checks out ONLY shipyard, into
# .shipyard/ (the product repo itself is never checked out here) -- "scripts/check-release-notes.sh"
# with no .shipyard/ prefix does not exist on this runner and exits 127, stranding every release in the
# family. Task 4 already learned this lesson once: only literal paths compare.
ra = [i for i, c in enumerate(cmds) if ".shipyard/scripts/release-assets.sh" in c]
if not ra:
    fail("the assets step no longer calls .shipyard/scripts/release-assets.sh")

# The call, and nothing chained onto it. A first cut at this check enumerated specific silencers
# (|| true, || :, ; true, continue-on-error: true) -- and a re-review walked straight past that list:
# || echo skipped, || exit 0 (which also skips the checksum verification below, by exiting the whole
# run: block), || logger x, && true, a pipe into cat, all leave a disabled gate looking green. Rather
# than keep enumerating spellings, require the STRUCTURE: the line that calls check-release-notes.sh
# must be the whole command -- nothing before it, nothing chained after it with ||, &&, ;, or a pipe.
# Any fallback of any spelling, thought of or not, then fails this instead of passing it.
call_re = re.compile(r'sh \.shipyard/scripts/check-release-notes\.sh "?dist/\$NOTES"? "?\$VERSION"? --short "?\$SHORT"? --tag "?\$VERSION"?')
crn = [i for i, c in enumerate(cmds) if call_re.fullmatch(c)]
if not crn:
    decorated = [c for c in cmds if call_re.search(c)]
    if decorated:
        fail("check-release-notes.sh is called, but not as a standalone command -- "
             "something is chained onto it (||, &&, ;, a pipe, ...), so a refused body can still ship: %r" % decorated[0])
    fail('the assets step does not call .shipyard/scripts/check-release-notes.sh on "dist/$NOTES" "$VERSION" --short "$SHORT" --tag "$VERSION" -- '
         "a copied notes file under a new tag would pass every other check and announce its predecessor")

# A structurally-clean call line can still run under a disabled errexit set earlier in the SAME step --
# `set +e` neuters the call without touching the call's own line at all, so the line check above cannot
# see it. Nothing between the step's start and the call may turn -e off.
if any(re.match(r"^set\b", c) and "+e" in c for c in cmds[:crn[0]]):
    fail("the assets step disables errexit (set +e) before calling check-release-notes.sh -- "
         "its failure would then not stop the step, so a refused body can still ship")

if str(a.get("continue-on-error", "")).strip().lower() == "true":
    fail("the assets step is continue-on-error: true -- check-release-notes.sh failing would not fail the job")

if crn[0] < ra[0]:
    fail("check-release-notes.sh runs before release-assets.sh -- validating a file not yet proven to exist")

sums = [i for i, c in enumerate(cmds) if "SHA256SUMS" in c]
if sums and crn[0] > min(sums):
    fail("check-release-notes.sh runs after the checksum block -- validate the body before spending work checksumming it")

env = a.get("env") or {}
if "inputs.version" not in str(env.get("VERSION", "")):
    fail("the assets step's env has no VERSION set to inputs.version -- check-release-notes.sh has nothing to check the body against")

# ...and before the FIRST publish attempt, or it validates a body that may already have shipped.
gi = steps.index(a)
pubs = [i for i, s in enumerate(steps) if "action-gh-release" in (s.get("uses") or "")]
if not pubs:
    fail("no step publishes with softprops/action-gh-release")
if gi > pubs[0]:
    fail("the assets step runs after the first publish attempt")

if "inputs.short" not in str(env.get("SHORT", "")):
    fail("the assets step's env has no SHORT set to inputs.short -- the heading cannot be derived")
if "steps.names.outputs.root" not in str(env.get("MAVERGREEN_REPO_ROOT", "")):
    fail("the assets step does not read the fetched names through MAVERGREEN_REPO_ROOT")

inp = (wf.get(True) or wf.get("on"))["workflow_call"]["inputs"]
sh = inp.get("short")
if not sh or sh.get("required") is not True or sh.get("type") != "string":
    fail("publish-release.yml has no required string input `short`")

names = [s for s in steps if s.get("id") == "names"]
if not names:
    fail("no step with id 'names' fetches the product's noun and line")
ni = steps.index(names[0])
if ni > gi or ni > pubs[0]:
    fail("the names step must run before the assets step and every publish")
if str(names[0].get("continue-on-error", "")).strip().lower() == "true":
    fail("the names step is continue-on-error: true -- a missing noun would not stop the release")
ncmd = names[0].get("run") or ""
if re.search(r"\bgit\b", ncmd):
    fail("the names step uses git; it fetches through the API")
if "fetch-product-names.sh" not in ncmd or "release-title" not in ncmd:
    fail("the names step must fetch the names and derive the release-title")
if "target-commitish" not in str(names[0].get("env", {}).get("SHA", "")):
    fail("the names step reads the names at the release commit (target-commitish, else the caller's SHA)")
for i in pubs:
    if "steps.names.outputs.title" not in str(steps[i].get("with", {}).get("name", "")):
        fail("publish step %d does not name the Release from the derived title" % i)

print("ok: check-release-notes.sh runs on dist/$NOTES against $VERSION, after release-assets.sh, "
      "before the checksum block, and before the first publish attempt")
PY

S="$here/../scripts/check-release-notes.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/pns.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/root/.mavergreen/products/thing"; printf 'Thing\n' > "$T/root/.mavergreen/products/thing/noun"
export MAVERGREEN_REPO_ROOT="$T/root"

printf '## %s\n\nAutomated release.\n' 9.9p2-mavergreen.6 > "$T/hand.md"
if sh "$S" "$T/hand.md" 9.9p2-mavergreen.6 --short thing --tag 9.9p2-mavergreen.6 >/dev/null 2>&1; then
  echo "FAIL: a hand-rolled body from a repo that never adopted the shared generator (no '### What changed') must not pass"; exit 1
fi
echo "ok: a hand-rolled body is refused"

: > "$T/empty.md"
if sh "$S" "$T/empty.md" 9.9p2-mavergreen.6 --short thing --tag 9.9p2-mavergreen.6 >/dev/null 2>&1; then
  echo "FAIL: an empty body must not pass -- tailscale published one on EVERY release, forever, before this check closed the hole"; exit 1
fi
echo "ok: an empty body is refused"

python3 - "$here/../.github/workflows/publish-release.yml" "$T/names-step.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
step = [s for j in wf["jobs"].values() for s in j["steps"] if s.get("id") == "names"][0]
open(sys.argv[2], "w").write(step["run"])
PY

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Publishing a release" -- the names
#       step, run as the runner would, with gh stubbed: it derives the release-title from the fetched noun
#       and line, and a missing noun fails before anything is published.
mkdir -p "$T/run/.shipyard" "$T/bin"; cp -R "$here/../scripts" "$T/run/.shipyard/scripts"
cat > "$T/bin/gh" <<'STUB'
#!/bin/sh
case "$*" in
  */noun?ref=*) f="$STUB_NOUN" ;;
  */line?ref=*) f="$STUB_LINE" ;;
esac
if [ -n "$f" ]; then printf '%s\n' "$f"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
STUB
chmod +x "$T/bin/gh"
names_step() {  # $1 = noun ('' for none), $2 = line, $3 = version
  rm -rf "$T/run/rt"; mkdir -p "$T/run/rt"; : > "$T/run/out"
  ( cd "$T/run" && env -u MAVERGREEN_REPO_ROOT PATH="$T/bin:$PATH" STUB_NOUN="$1" STUB_LINE="$2" REPO=Mavergreen/thing SHA=abc123 SHORT=go127 \
      VERSION="$3" GH_TOKEN=t RUNNER_TEMP="$T/run/rt" GITHUB_OUTPUT="$T/run/out" sh -e "$T/names-step.sh" ) > "$T/run/log" 2>&1
}
names_step Go 1.27 1.27.2-mavergreen.1 || { echo "FAIL: the names step must pass with a noun and a line:"; cat "$T/run/log"; exit 1; }
grep -qx 'title=Go 1.27.2' "$T/run/out" || { echo "FAIL: the release title is the derived title"; cat "$T/run/out"; exit 1; }
names_step Shipyard '' v1.0.300 || { echo "FAIL: a 404 on line is fine:"; cat "$T/run/log"; exit 1; }
grep -qx 'title=Shipyard 1.0.300' "$T/run/out" || { echo "FAIL: the release title drops the v"; cat "$T/run/out"; exit 1; }
if names_step '' '' v1.0.300; then echo "FAIL: a missing noun must fail the names step"; exit 1; fi
grep -q 'noun' "$T/run/log" || { echo "FAIL: the missing noun is named"; cat "$T/run/log"; exit 1; }
[ ! -s "$T/run/out" ] || { echo "FAIL: nothing is set for later steps after a missing noun"; cat "$T/run/out"; exit 1; }
echo "ok: the names step derives the release title and a missing noun fails it"

echo "PASS: publish-notes-shape"
