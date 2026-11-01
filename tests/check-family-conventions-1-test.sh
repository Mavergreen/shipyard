#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

(cd "$work/ok" && sh "$S" >/dev/null) || { echo "FAIL compliant repo should pass"; exit 1; }

mkdir -p "$work/norel/.github"; printf '{"extends":["github>Mavergreen/shipyard"]}\n' > "$work/norel/.github/renovate.json"
printf '.superpowers/\n.idea/\n' > "$work/norel/.gitignore"
(cd "$work/norel" && git init -q && git add -A) >/dev/null 2>&1
(cd "$work/norel" && sh "$S" > "$work/norel.out" 2>&1) || { echo "FAIL: a repo with no release.yml that keeps the repo-wide rules should pass: $(cat "$work/norel.out")"; exit 1; }
grep -q '^release-concurrency: not run: no .github/workflows/release.yml' "$work/norel.out" \
  || { echo "FAIL: with no release.yml the release rules say they did not run: $(cat "$work/norel.out")"; exit 1; }

mkrepo "$work/c"; grep -v -e '^concurrency:' -e '^  group:' -e '^  cancel-in-progress:' \
  "$work/ok/.github/workflows/release.yml" > "$work/c/.github/workflows/release.yml"
if (cd "$work/c" && sh "$S" >/dev/null 2>&1); then echo "FAIL missing concurrency should fail"; exit 1; fi
out="$(cd "$work/c" && sh "$S" 2>&1 || true)"; first_is "$out" release-concurrency || { echo "FAIL should name release-concurrency: $out"; exit 1; }

# spec: a release.yml whose concurrency group is IDENTICAL for every event cannot keep a
#       publishing run out of a shared group. cancel-in-progress:false protects the RUNNING job
#       and not the QUEUED one -- GitHub keeps only the newest pending run per group -- so a
#       queued dispatch is evicted by the next arrival and its release silently never happens.
#       This must fail.
mkrepo "$work/cr"
chk_py /dev/stdin "$work/cr/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}",
            "  group: release-${{ github.ref }}")
s=s.replace("  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "  cancel-in-progress: false")
open(p,'w').write(s)
PY
if (cd "$work/cr" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a single-group concurrency block should fail"; exit 1; fi
out="$(cd "$work/cr" && sh "$S" 2>&1 || true)"; first_is "$out" concurrency-group || { echo "FAIL: should be a concurrency-group failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the block the family actually ships must pass. Only pull_request supersedes (keyed
#       per ref, so a force-push replaces its own predecessor); a branch push, a tag and a
#       dispatch are each keyed per RUN and alone in their group. Folded across lines, because
#       that is how it is written in the repos.
mkrepo "$work/cok"
chk_py /dev/stdin "$work/cok/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}",
            "  group: >-\n"
            "    release-${{ github.event_name == 'pull_request'\n"
            "                && github.ref || github.run_id }}")
open(p,'w').write(s)
PY
(cd "$work/cok" && sh "$S" >/dev/null) || { echo "FAIL: the shipped concurrency block should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and so must the gate reject, by name, the shape this family actually ran until
#       2026-09-09: dispatches herded into one shared literal group with
#       cancel-in-progress:false. It mentions github.event_name, so a check that only asks "does
#       the group distinguish events?" waves it straight through -- yet it is the exact
#       arrangement that evicted a queued run in mavericks-golang.
mkrepo "$work/cold"
chk_py /dev/stdin "$work/cold/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}",
            "  group: ${{ github.workflow }}-${{ github.event_name == 'workflow_dispatch' && 'local_release' || github.ref }}")
s=s.replace("  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "  cancel-in-progress: ${{ github.event_name != 'workflow_dispatch' }}")
open(p,'w').write(s)
PY
if (cd "$work/cold" && sh "$S" >/dev/null 2>&1); then echo "FAIL: the old shared-dispatch-group shape should fail"; exit 1; fi
out="$(cd "$work/cold" && sh "$S" 2>&1 || true)"; first_is "$out" concurrency-group || { echo "FAIL: should be a concurrency-group failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a group that IS per-run but still lets a publish be cancelled is only half the rule.
mkrepo "$work/chalf"
chk_py /dev/stdin "$work/chalf/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "  cancel-in-progress: true")
open(p,'w').write(s)
PY
if (cd "$work/chalf" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a cancellable publish should fail"; exit 1; fi
out="$(cd "$work/chalf" && sh "$S" 2>&1 || true)"; first_is "$out" concurrency-group || { echo "FAIL: should be a concurrency-group failure: $out"; exit 1; }

mkrepo "$work/t"; grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/t/.github/workflows/release.yml"
if out="$(cd "$work/t" && sh "$S" 2>&1)"; then echo "FAIL: tests exist but CI never runs them should fail"; exit 1; fi
first_is "$out" tests-run-in-ci || { echo "FAIL: should be a tests-run-in-ci failure: $out"; exit 1; }

mkrepo "$work/te"; rm -f "$work/te/tests/a-test.sh"
grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/te/.github/workflows/release.yml"
(cd "$work/te" && sh "$S" >/dev/null) || { echo "FAIL: a repo with an EMPTY tests dir is fine, should pass"; exit 1; }

mkrepo "$work/i"; rm -f "$work/i/INGREDIENTS.md"
if out="$(cd "$work/i" && sh "$S" 2>&1)"; then echo "FAIL missing INGREDIENTS.md should fail"; exit 1; fi
first_is "$out" ingredients-md || { echo "FAIL: should be an ingredients-md failure: $out"; exit 1; }

mkrepo "$work/r"
printf '{"extends":["github>Mavergreen/shipyard"],"ignoreTests":false}\n' > "$work/r/.github/renovate.json"
if out="$(cd "$work/r" && sh "$S" 2>&1)"; then echo "FAIL: a Renovate key restating the preset's own value is redundant and should fail"; exit 1; fi
first_is "$out" renovate-no-restated-defaults || { echo "FAIL should be a renovate-no-restated-defaults failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but the SAME key with a DIFFERENT value is a deliberate override, not drift. A repo with
#       no build to gate legitimately opts back into blind automerge with ignoreTests:true; the
#       gate must allow it.
mkrepo "$work/r2"
printf '{"extends":["github>Mavergreen/shipyard"],"ignoreTests":true}\n' > "$work/r2/.github/renovate.json"
(cd "$work/r2" && sh "$S" >/dev/null) || { echo "FAIL deliberate ignoreTests:true override should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- an automerge exception must say WHY. The family default is ship-if-green (patch, minor
#       and major alike); a repo restricts automerge only where a bad bump would build fine and
#       be wrong -- the case a green build cannot catch. Unexplained, that is indistinguishable
#       from drift.
mkrepo "$work/am"
printf '%s\n' '{"extends":["github>Mavergreen/shipyard"],"packageRules":[{"matchDepNames":["x"],"matchUpdateTypes":["minor"],"automerge":false}]}' \
  > "$work/am/.github/renovate.json"
if out="$(cd "$work/am" && sh "$S" 2>&1)"; then echo "FAIL undescribed automerge exception should fail"; exit 1; fi
first_is "$out" automerge-described || { echo "FAIL should be an automerge-described failure: $out"; exit 1; }

mkrepo "$work/am2"
printf '%s\n' '{"extends":["github>Mavergreen/shipyard"],"packageRules":[{"description":"A minor bump needs LLVM_BRANCH to follow, which no regex can infer: it would build fine and be wrong.","matchDepNames":["x"],"matchUpdateTypes":["minor"],"automerge":false}]}' \
  > "$work/am2/.github/renovate.json"
(cd "$work/am2" && sh "$S" >/dev/null) || { echo "FAIL: with a reason, the exception should pass"; exit 1; }

mkrepo "$work/am3"
printf '%s\n' '{"extends":["github>Mavergreen/shipyard"],"packageRules":[{"matchDepNames":["x"],"allowedVersions":"/^v?[0-9.]+$/"}]}' \
  > "$work/am3/.github/renovate.json"
(cd "$work/am3" && sh "$S" >/dev/null) || { echo "FAIL: a rule that does NOT touch automerge (e.g. allowedVersions) needs no such reason, should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a repo that publishes via the shared workflow satisfies the notes check: the caller has
#       no --notes-file or body_path of its own, because publish-release.yml owns the body (and
#       fails on an empty one, which is stronger than what this check can see).
mkrepo "$work/p" novm
chk_py /dev/stdin "$work/p/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('      - run: gh release create "$TAG" dist/* --notes-file dist/RELEASE_NOTES.md\n',
            '  publish:\n'
            '    uses: Mavergreen/shipyard/.github/workflows/publish-release.yml@v1\n'
            '    with: { version: "7.0.0", artifact: pkg }\n')
open(p,'w').write(s)
PY
(cd "$work/p" && sh "$S" >/dev/null) || { echo "FAIL publish-release caller should satisfy the notes check"; exit 1; }

# spec: tests may be run from a DIFFERENT workflow (tailscale runs ctest from ci.yml, not
#       release.yml).
mkrepo "$work/x"; grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/x/.github/workflows/release.yml"
printf 'name: CI\njobs:\n  build:\n    steps:\n      - run: shipyard-ctest --preset cross\n' > "$work/x/.github/workflows/ci.yml"
(cd "$work/x" && sh "$S" >/dev/null) || { echo "FAIL tests run from ci.yml should pass"; exit 1; }

# spec: SKILL.md "Versioning" -- VERSION must not be committed. The shipped state lives in tags; a
#       committed VERSION is a second answer to "what version is this?", and it drifts --
#       container-tools built -mavericks.14 from a file that still said .2, which also made its
#       tag-triggered publish path (tag must equal VERSION) unsatisfiable. UPSTREAM_VERSION is the
#       committed input; VERSION is derived from it plus the tags.
mkrepo "$work/v1"
(cd "$work/v1" && sh "$S" >/dev/null) || { echo "FAIL derived-version repo should pass"; exit 1; }

mkrepo "$work/v2"
printf '1.0.0-mavericks.3\n' > "$work/v2/VERSION"
(cd "$work/v2" && git add -f VERSION) >/dev/null 2>&1
if out="$(cd "$work/v2" && sh "$S" 2>&1)"; then echo "FAIL tracked VERSION should fail"; exit 1; fi
first_is "$out" no-tracked-version || { echo "FAIL should be a no-tracked-version failure: $out"; exit 1; }

mkrepo "$work/v3"
printf '1.0.0-mavericks.3\n' > "$work/v3/VERSION"
(cd "$work/v3" && sh "$S" >/dev/null) || { echo "FAIL: an untracked VERSION (a build product sitting in the tree) is FINE -- that is the normal state after any local build, and failing on it would make the gate unrunnable on a developer's machine: should pass"; exit 1; }

mkrepo "$work/v4"; rm "$work/v4/UPSTREAM_VERSION"
if out="$(cd "$work/v4" && sh "$S" 2>&1)"; then echo "FAIL: no upstream input at all means nothing can derive a version, so it should say so rather than let CI discover it -- should fail"; exit 1; fi
first_is "$out" upstream-version || { echo "FAIL should be an upstream-version failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a repo whose upstream is DERIVED from its pin (ed25519: the pinned commit's date;
#       tailscale: the upstream's own VERSION.txt) has no committed UPSTREAM_VERSION and must
#       still pass.
mkrepo "$work/v5"; rm "$work/v5/UPSTREAM_VERSION"
mkdir -p "$work/v5/build"; printf '#!/bin/sh\n: > UPSTREAM_VERSION\n' > "$work/v5/build/derive-upstream-version.sh"
(cd "$work/v5" && git add -A) >/dev/null 2>&1
(cd "$work/v5" && sh "$S" >/dev/null) || { echo "FAIL derived upstream should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- check 7b fails a repo with a TRACKED lines/ dir --
#       golang, nodejs and clang have all migrated off it (2026-09-22), so a reappearing tracked
#       lines/ means the retired per-line directory shape crept back in, not a legitimate
#       parallel-lines repo. Keeps its root UPSTREAM_VERSION (from mkrepo) so check 7, just above,
#       stays satisfied and this fixture isolates 7b's failure.
mkrepo "$work/v6"
mkdir -p "$work/v6/lines/126"; printf '1.26.5\n' > "$work/v6/lines/126/UPSTREAM_VERSION"
(cd "$work/v6" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/v6" && sh "$S" 2>&1)"; then echo "FAIL: a reappearing tracked lines/ dir should fail"; exit 1; fi
first_is "$out" no-lines-dir || { echo "FAIL should be a no-lines-dir failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and a repo with no lines/ dir at all (the family's
#       current shape, everywhere) must pass. "$work/ok" (built in tests/lib/conventions_fixture.sh) already proves this implicitly; this
#       makes it explicit for check 7b specifically.
mkrepo "$work/v7"
(cd "$work/v7" && sh "$S" >/dev/null) || { echo "FAIL: a repo with no lines/ dir should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- check 7b reads TRACKED files only, the same rule
#       checks 7/17 apply. This family's NFS checkouts collect ignored AppleDouble `._*` files
#       (lines/._126, lines/126/._patches); a migrated checkout that fast-forwards past golang's or
#       clang's lines/-retiring commit has git delete the TRACKED files under lines/ while those
#       ignored siblings stay on disk, leaving a real (but untracked) lines/ directory. That must
#       not fail the gate on an otherwise-migrated repo.
mkrepo "$work/v8"
mkdir -p "$work/v8/lines/126"
printf '._AppleDouble\n' > "$work/v8/lines/126/._patches"     # untracked -- .gitignore below covers it
printf '._*\n' >> "$work/v8/.gitignore"
(cd "$work/v8" && git add -A) >/dev/null 2>&1
(cd "$work/v8" && sh "$S" >/dev/null) || { echo "FAIL: an untracked (ignored-AppleDouble) lines/ dir should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- `git ls-files -- lines/` (trailing slash) matches
#       only paths INSIDE a lines/ directory, so a tracked plain FILE literally named "lines" is not
#       the retired shape and must pass.
mkrepo "$work/v9"
printf 'not a directory\n' > "$work/v9/lines"
(cd "$work/v9" && git add -A) >/dev/null 2>&1
(cd "$work/v9" && sh "$S" >/dev/null) || { echo "FAIL: a plain file named 'lines' (not a directory) should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the check only cares about lines/ AT THE REPO ROOT;
#       a nested sub/lines/ is some other directory's business, not this family convention's.
mkrepo "$work/v10"
mkdir -p "$work/v10/sub/lines/22"; printf '22.1.1\n' > "$work/v10/sub/lines/22/UPSTREAM_VERSION"
(cd "$work/v10" && git add -A) >/dev/null 2>&1
(cd "$work/v10" && sh "$S" >/dev/null) || { echo "FAIL: a nested sub/lines/ should pass"; exit 1; }

# spec: check 7d is the mirror of 7c: a build OUTPUT dir that is NOT ignored. tailscale's
#       release.yml configures the updater with `cmake -S updater -B build/updater`, a path the
#       shared presets never name -- so nothing tied it to .gitignore, and 7.4MB of CMake output
#       sat in the checkout untracked AND unignored, one `git add -A` from being committed. The
#       gate finds the paths the repo itself names rather than demanding one blessed spelling: ten
#       of fifteen repos spell their ignores differently and all are fine.
mkrepo "$work/bo"
cat >> "$work/bo/.github/workflows/release.yml" <<'YML'
      - run: shipyard-cmake -S updater -B build/updater
YML
if out="$(cd "$work/bo" && sh "$S" 2>&1)"; then echo "FAIL: an unignored build output dir should fail"; exit 1; fi
first_is "$out" build-dirs-ignored || { echo "FAIL: should be a build-dirs-ignored failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- ignored, it must pass -- any spelling that actually covers the path is fine.
mkrepo "$work/bok"
cat >> "$work/bok/.github/workflows/release.yml" <<'YML'
      - run: shipyard-cmake -S updater -B build/updater
YML
printf 'build/updater/\n' >> "$work/bok/.gitignore"
(cd "$work/bok" && git add -A >/dev/null 2>&1; sh "$S" >/dev/null) || { echo "FAIL: an ignored build output dir should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a build that already leaves the tree needs no ignore at all -- that is the point of
#       leaving it.
mkrepo "$work/boo"
cat >> "$work/boo/.github/workflows/release.yml" <<'YML'
      - run: shipyard-cmake -S . -B "$RUNNER_TEMP/b"
      - run: shipyard-cmake -S . -B /tmp/build
YML
(cd "$work/boo" && git add -A >/dev/null 2>&1; sh "$S" >/dev/null) || { echo "FAIL: an out-of-tree build dir needs no ignore"; exit 1; }

# spec: scripts/check-family-conventions.sh -- `grep -B 3` is not a build directory. The gate reads only cmake's -B, or it invents
#       failures.
mkrepo "$work/bgrep"
cat >> "$work/bgrep/.github/workflows/release.yml" <<'YML'
      - run: grep -B 3 pattern file
YML
(cd "$work/bgrep" && git add -A >/dev/null 2>&1; sh "$S" >/dev/null) || { echo "FAIL: grep -B must not be read as a build dir"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a committed CMakePresets.json names binaryDirs too; those are build output just the same.
mkrepo "$work/bpre"
printf '{"version":6,"configurePresets":[{"name":"n","binaryDir":"${sourceDir}/build-native"}]}\n' \
  > "$work/bpre/CMakePresets.json"
if out="$(cd "$work/bpre" && git add -A >/dev/null 2>&1; sh "$S" 2>&1)"; then echo "FAIL: an unignored preset binaryDir should fail"; exit 1; fi
first_is "$out" build-dirs-ignored || { echo "FAIL: should be a build-dirs-ignored failure: $out"; exit 1; }

# spec: check 7d, the way it actually runs -- family-conventions.yml checks shipyard out to
#       .shipyard/ INSIDE the consumer's workspace and runs the gate from there. A sweep of "*.sh"
#       therefore reads the gate's OWN source -- whose comments explain the rule using
#       `cmake -S updater -B build/updater` and `cmake ... -B <dir>` as examples. The first draft
#       reported those as unignored build directories and turned every consumer's conventions run
#       red. Vendored shipyard is not this repo's build.
mkrepo "$work/bvend"
mkdir -p "$work/bvend/.shipyard/scripts"
cat > "$work/bvend/.shipyard/scripts/check-family-conventions.sh" <<'SH'
#!/bin/sh
# tailscale configured the updater with `cmake -S updater -B build/updater` -- a path the shared
# presets do not name -- so nothing tied it to .gitignore. Every `cmake ... -B <dir>` counts.
SH
(cd "$work/bvend" && git add -A >/dev/null 2>&1; sh "$S" >/dev/null) || { echo "FAIL: a vendored .shipyard/ must not be read as this repo's build"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and a COMMENT in the repo's own shell that merely mentions a cmake command line is prose,
#       not a build. Only a line that actually runs cmake names a directory.
mkrepo "$work/bcomment"
cat > "$work/bcomment/note.sh" <<'SH'
#!/bin/sh
# Historically we ran cmake -S . -B legacy-build here; see the notes for why we stopped.
exit 0
SH
(cd "$work/bcomment" && git add -A >/dev/null 2>&1; sh "$S" >/dev/null) || { echo "FAIL: a commented-out cmake line is not a build dir"; exit 1; }

# spec: check 7d must read only what the repo COMMITS. An earlier draft swept the worktree with
#       `find`, so it also read build output and the AppleDouble `._*.sh` files an NFS checkout
#       collects -- 65 .sh swept against 58 tracked in shipyard itself. BSD sed aborts on their
#       binary content ("RE error: illegal byte sequence"), which truncates the candidate stream
#       mid-pipe: the check then silently stops looking, and an unignored build dir later in the
#       sweep goes unreported. Tracked files only.
mkrepo "$work/buntracked"
printf '#!/bin/sh\nshipyard-cmake -S . -B never-committed-build\n' > "$work/buntracked/stray.sh"
printf 'binary-\000-junk\n' > "$work/buntracked/._decoy.sh"
(cd "$work/buntracked" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: an UNTRACKED .sh must not be scanned as this repo's build"; exit 1; }
(cd "$work/buntracked" && sh "$S" 2>&1 | grep -qi 'illegal byte sequence') && { echo "FAIL: a binary ._*.sh must not reach sed"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but once committed, the very same file counts.
(cd "$work/buntracked" && git add stray.sh >/dev/null 2>&1)
if out="$(cd "$work/buntracked" && sh "$S" 2>&1)"; then echo "FAIL: a COMMITTED build script's dir must be required to be ignored"; exit 1; fi
first_is "$out" build-dirs-ignored || { echo "FAIL: should be a build-dirs-ignored failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- workflow YAML must parse with DUPLICATE KEYS REJECTED. A second `with:` on one step is
#       valid YAML (last key wins) and ordinary parsers accept it, but GitHub refuses to run the
#       workflow: the run shows up named after the file path, "likely failed because of a
#       workflow file issue", with no step logs at all. swift-runtime shipped exactly that.
mkrepo "$work/y1"
awk '{print} /^    steps:$/ && !d {print "      - uses: actions/checkout@v7"; print "        with:"; print "          fetch-depth: 0"; print "        with:"; print "          fetch-depth: 1"; d=1}' \
  "$work/ok/.github/workflows/release.yml" > "$work/y1/.github/workflows/release.yml"
if out="$(cd "$work/y1" && sh "$S" 2>&1)"; then echo "FAIL duplicate key should fail"; exit 1; fi
first_is "$out" workflow-yaml || { echo "FAIL should be a workflow-yaml failure: $out"; exit 1; }

mkrepo "$work/y2"
printf 'name: x\non: [push]\njobs:\n  a:\n   steps:\n  - bad indent\n' > "$work/y2/.github/workflows/broken.yml"
if out="$(cd "$work/y2" && sh "$S" 2>&1)"; then echo "FAIL: malformed YAML should fail too, naming the file"; exit 1; fi
first_is "$out" workflow-yaml || { echo "FAIL should be a workflow-yaml failure: $out"; exit 1; }

# spec: scripts/vendor/yaml -- the gate parses workflows with the PyYAML it ships, so a host python3 with
#       no PyYAML, or a broken one earlier on PYTHONPATH, changes nothing: this fixture put a yaml
#       module that cannot import ahead of everything and the gate still passes.
mkrepo "$work/y3"
noyaml="$work/noyaml"; mkdir -p "$noyaml"
printf 'raise ImportError("No module named yaml")\n' > "$noyaml/yaml.py"
(cd "$work/y3" && PYTHONPATH="$noyaml" sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL a host python3 with no usable PyYAML must not matter: $(cd "$work/y3" && PYTHONPATH="$noyaml" sh "$S" 2>&1)"; exit 1; }

# spec: 2026-10-03 -- with no python3 at all, the parse check was skipped and the gate passed.
#       A PATH holding every command but python3 stands in for a 10.9 box without python-315, and
#       the one thing it must report is the python3 check, once.
nopy="$work/nopy"; mkdir -p "$nopy"
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
  for f in "$d"/*; do
    case "${f##*/}" in python3*) continue ;; esac
    if [ -x "$f" ] && [ ! -e "$nopy/${f##*/}" ]; then ln -s "$f" "$nopy/${f##*/}"; fi
  done
done
mkdir -p "$work/emptyopt"
PATH="$nopy" sh -c 'command -v python3' >/dev/null 2>&1 && { echo "FAIL the no-python3 PATH still finds python3"; exit 1; }
if out="$(cd "$work/y3" && PATH="$nopy" SHIPYARD_OPT_PREFIX="$work/emptyopt" SHIPYARD_LOCAL_PREFIX="$work/emptyopt" SHIPYARD_PYTHON3= sh "$S" 2>&1)"; then
  echo "FAIL missing python3 should fail (cannot-verify is not a pass)"; exit 1
fi
first_is "$out" python3 || { echo "FAIL should be the python3 failure: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | grep -c '^  more: shipyard-check --explain ')" -eq 1 ] || { echo "FAIL no python3 is one failure, python3, and no other: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the 10.9-portability lint runs as part of this gate, so every consumer gets it from the
#       @v1 they already pin. Asserted HERE and not only in shell-portability-test.sh because the
#       wiring is the part that can rot: check-shell-portability.sh could keep passing its own
#       tests while this gate quietly stopped calling it, and nothing would go red.
mkrepo "$work/p1"
printf '#!/bin/sh\nd="$(mktemp -d)"\n' > "$work/p1/tool.sh"  # portability-ok: fixture must contain the violation
(cd "$work/p1" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/p1" && sh "$S" 2>&1)"; then echo "FAIL a 10.9-unportable script should fail the gate"; exit 1; fi
first_is "$out" shell-portability || { echo "FAIL should be a shell-portability failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'tool.sh:2' || { echo "FAIL should name file:line: $out"; exit 1; }

# spec: SKILL.md "Renovate & automerge" -- every build ingredient must be able to auto-update. An
#       ingredient nobody tracks is one that silently goes stale: swift-runtime's swift-toolchain
#       pin sat at 6.3.3-mavericks.1 while that repo shipped .3, because updating it meant a human
#       fetching and pasting two SHA256s. Wiring a Renovate customManager is the doctrine; a
#       genuine exception (no datasource exists at all) must SAY so.
mkrepo "$work/r1"
printf '# Build ingredients\n\n| I | Pinned in | Renovate | On a bump |\n|---|---|---|---|\n| Go | `x` | ✅ github-releases | repackage |\n' \
  > "$work/r1/INGREDIENTS.md"
(cd "$work/r1" && sh "$S" >/dev/null) || { echo "FAIL tracked ingredient should pass"; exit 1; }

echo "PASS: check-family-conventions-1"
