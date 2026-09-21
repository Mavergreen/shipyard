#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-family-conventions.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/family-conventions.XXXXXX")"; trap 'rm -rf "$work"' EXIT  # template: 10.9 BSD mktemp requires one

# spec: scripts/check-family-conventions.sh -- the baseline is a repo that satisfies EVERY
#       check, so each case below can turn exactly one thing off. Since check 14 the release
#       body has to come from the shared generator, so the
#       baseline calls release-notes.sh and hands the publisher the very path it was given as
#       --out; a fixture that still hand-waved `--notes-file "$NOTES"` would fail 14 in thirty
#       unrelated cases.
mkrepo() {  # $1 = dir
  mkdir -p "$1/.github/workflows" "$1/tests"
  cat > "$1/.github/workflows/release.yml" <<'YML'
name: release
on:
  push:
    tags: ['*-mavericks.*']
concurrency:
  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  build:
    steps:
      - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh" --record
      - run: sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
      - run: |
          sh "$SHIPYARD_SCRIPTS/release-notes.sh" --tag "$TAG" --version "$FULL" \
            --product Widget --min-os 10.9.5 --out dist/RELEASE_NOTES.md
      - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"
      - run: gh release create "$TAG" dist/* --notes-file dist/RELEASE_NOTES.md
YML
  printf '# Build ingredients\n' > "$1/INGREDIENTS.md"
  printf '{"extends":["github>ModernMavericks/shipyard"]}\n' > "$1/.github/renovate.json"
  printf '#!/bin/sh\nexit 0\n' > "$1/tests/a-test.sh"
  # spec: scripts/check-family-conventions.sh -- a compliant repo commits UPSTREAM_VERSION and
  #       gitignores VERSION (a build product), and the gate asks git what is tracked -- so the
  #       fixture has to be a real checkout. It also
  #       says where upstream's own release notes live, for a release that ships a new upstream.
  printf '1.0.0\n' > "$1/UPSTREAM_VERSION"
  printf '/VERSION\n' > "$1/.gitignore"
  mkdir -p "$1/build"
  printf '#!/bin/sh\nprintf "https://example.com/v%%s\\n" "$1"\n' > "$1/build/upstream-release-notes-url.sh"
  (cd "$1" && git init -q && git add -A) >/dev/null 2>&1
}

mkrepo "$work/ok"; (cd "$work/ok" && sh "$S" >/dev/null) || { echo "FAIL compliant repo should pass"; exit 1; }

mkdir -p "$work/norel"; (cd "$work/norel" && sh "$S" >/dev/null) || { echo "FAIL: no release.yml at all (shipyard itself) should pass"; exit 1; }

mkrepo "$work/c"; grep -v -e '^concurrency:' -e '^  group:' -e '^  cancel-in-progress:' \
  "$work/ok/.github/workflows/release.yml" > "$work/c/.github/workflows/release.yml"
if (cd "$work/c" && sh "$S" >/dev/null 2>&1); then echo "FAIL missing concurrency should fail"; exit 1; fi
(cd "$work/c" && sh "$S" 2>&1 | grep -qi concurrency) || { echo "FAIL should name concurrency"; exit 1; }

# spec: a release.yml whose concurrency group is IDENTICAL for every event cannot keep a
#       publishing run out of a shared group. cancel-in-progress:false protects the RUNNING job
#       and not the QUEUED one -- GitHub keeps only the newest pending run per group -- so a
#       queued dispatch is evicted by the next arrival and its release silently never happens.
#       This must fail.
mkrepo "$work/cr"
python3 - "$work/cr/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}",
            "  group: release-${{ github.ref }}")
s=s.replace("  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "  cancel-in-progress: false")
open(p,'w').write(s)
PY
if (cd "$work/cr" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a single-group concurrency block should fail"; exit 1; fi
(cd "$work/cr" && sh "$S" 2>&1 | grep -qiE 'queued|pending|supersede') || { echo "FAIL: should explain the queued-run eviction"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the block the family actually ships must pass. Only pull_request supersedes (keyed
#       per ref, so a force-push replaces its own predecessor); a branch push, a tag and a
#       dispatch are each keyed per RUN and alone in their group. Folded across lines, because
#       that is how it is written in the repos.
mkrepo "$work/cok"
python3 - "$work/cok/.github/workflows/release.yml" <<'PY'
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
python3 - "$work/cold/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}",
            "  group: ${{ github.workflow }}-${{ github.event_name == 'workflow_dispatch' && 'local_release' || github.ref }}")
s=s.replace("  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "  cancel-in-progress: ${{ github.event_name != 'workflow_dispatch' }}")
open(p,'w').write(s)
PY
if (cd "$work/cold" && sh "$S" >/dev/null 2>&1); then echo "FAIL: the old shared-dispatch-group shape should fail"; exit 1; fi
(cd "$work/cold" && sh "$S" 2>&1 | grep -qiE 'run_id|per run|alone') || { echo "FAIL: should say publishing runs must be keyed per run"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a group that IS per-run but still lets a publish be cancelled is only half the rule.
mkrepo "$work/chalf"
python3 - "$work/chalf/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "  cancel-in-progress: true")
open(p,'w').write(s)
PY
if (cd "$work/chalf" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a cancellable publish should fail"; exit 1; fi
(cd "$work/chalf" && sh "$S" 2>&1 | grep -qi 'pull_request') || { echo "FAIL: should say only a pull_request may be cancelled"; exit 1; }

mkrepo "$work/t"; grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/t/.github/workflows/release.yml"
if (cd "$work/t" && sh "$S" >/dev/null 2>&1); then echo "FAIL: tests exist but CI never runs them should fail"; exit 1; fi

mkrepo "$work/te"; rm -f "$work/te/tests/a-test.sh"
grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/te/.github/workflows/release.yml"
(cd "$work/te" && sh "$S" >/dev/null) || { echo "FAIL: a repo with an EMPTY tests dir is fine, should pass"; exit 1; }

mkrepo "$work/i"; rm -f "$work/i/INGREDIENTS.md"
if (cd "$work/i" && sh "$S" >/dev/null 2>&1); then echo "FAIL missing INGREDIENTS.md should fail"; exit 1; fi

mkrepo "$work/r"
printf '{"extends":["github>ModernMavericks/shipyard"],"ignoreTests":false}\n' > "$work/r/.github/renovate.json"
if (cd "$work/r" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a Renovate key restating the preset's own value is redundant and should fail"; exit 1; fi
(cd "$work/r" && sh "$S" 2>&1 | grep -qi ignoreTests) || { echo "FAIL should name the key"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but the SAME key with a DIFFERENT value is a deliberate override, not drift. A repo with
#       no build to gate legitimately opts back into blind automerge with ignoreTests:true; the
#       gate must allow it.
mkrepo "$work/r2"
printf '{"extends":["github>ModernMavericks/shipyard"],"ignoreTests":true}\n' > "$work/r2/.github/renovate.json"
(cd "$work/r2" && sh "$S" >/dev/null) || { echo "FAIL deliberate ignoreTests:true override should pass"; exit 1; }

mkrepo "$work/n"; grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/n/.github/workflows/release.yml"
if (cd "$work/n" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a release that publishes no notes should fail"; exit 1; fi

# spec: scripts/check-family-conventions.sh -- an automerge exception must say WHY. The family default is ship-if-green (patch, minor
#       and major alike); a repo restricts automerge only where a bad bump would build fine and
#       be wrong -- the case a green build cannot catch. Unexplained, that is indistinguishable
#       from drift.
mkrepo "$work/am"
printf '%s\n' '{"extends":["github>ModernMavericks/shipyard"],"packageRules":[{"matchDepNames":["x"],"matchUpdateTypes":["minor"],"automerge":false}]}' \
  > "$work/am/.github/renovate.json"
if (cd "$work/am" && sh "$S" >/dev/null 2>&1); then echo "FAIL undescribed automerge exception should fail"; exit 1; fi
(cd "$work/am" && sh "$S" 2>&1 | grep -qi 'automerge') || { echo "FAIL should name the automerge rule"; exit 1; }

mkrepo "$work/am2"
printf '%s\n' '{"extends":["github>ModernMavericks/shipyard"],"packageRules":[{"description":"A minor bump needs LLVM_BRANCH to follow, which no regex can infer: it would build fine and be wrong.","matchDepNames":["x"],"matchUpdateTypes":["minor"],"automerge":false}]}' \
  > "$work/am2/.github/renovate.json"
(cd "$work/am2" && sh "$S" >/dev/null) || { echo "FAIL: with a reason, the exception should pass"; exit 1; }

mkrepo "$work/am3"
printf '%s\n' '{"extends":["github>ModernMavericks/shipyard"],"packageRules":[{"matchDepNames":["x"],"allowedVersions":"/^v?[0-9.]+$/"}]}' \
  > "$work/am3/.github/renovate.json"
(cd "$work/am3" && sh "$S" >/dev/null) || { echo "FAIL: a rule that does NOT touch automerge (e.g. allowedVersions) needs no such reason, should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a repo that publishes via the shared workflow satisfies the notes check: the caller has
#       no --notes-file or body_path of its own, because publish-release.yml owns the body (and
#       fails on an empty one, which is stronger than what this check can see).
mkrepo "$work/p"
python3 - "$work/p/.github/workflows/release.yml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('      - run: gh release create "$TAG" dist/* --notes-file dist/RELEASE_NOTES.md\n',
            '  publish:\n'
            '    uses: ModernMavericks/shipyard/.github/workflows/publish-release.yml@v1\n'
            '    with: { version: "1.0.0", artifact: pkg }\n')
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
printf '%s\n' "$out" | grep -q 'VERSION' || { echo "FAIL should name VERSION: $out"; exit 1; }

mkrepo "$work/v3"
printf '1.0.0-mavericks.3\n' > "$work/v3/VERSION"
(cd "$work/v3" && sh "$S" >/dev/null) || { echo "FAIL: an untracked VERSION (a build product sitting in the tree) is FINE -- that is the normal state after any local build, and failing on it would make the gate unrunnable on a developer's machine: should pass"; exit 1; }

mkrepo "$work/v4"; rm "$work/v4/UPSTREAM_VERSION"
if out="$(cd "$work/v4" && sh "$S" 2>&1)"; then echo "FAIL: no upstream input at all means nothing can derive a version, so it should say so rather than let CI discover it -- should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'UPSTREAM_VERSION' || { echo "FAIL should name UPSTREAM_VERSION: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a repo whose upstream is DERIVED from its pin (ed25519: the pinned commit's date;
#       tailscale: the upstream's own VERSION.txt) has no committed UPSTREAM_VERSION and must
#       still pass.
mkrepo "$work/v5"; rm "$work/v5/UPSTREAM_VERSION"
mkdir -p "$work/v5/build"; printf '#!/bin/sh\n: > UPSTREAM_VERSION\n' > "$work/v5/build/derive-upstream-version.sh"
(cd "$work/v5" && git add -A) >/dev/null 2>&1
(cd "$work/v5" && sh "$S" >/dev/null) || { echo "FAIL derived upstream should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- parallel upstream lines (golang) keep one UPSTREAM_VERSION per line. Check 7b additionally
#       demands each line carry its OWN capped Renovate manager, so the fixture has to look like
#       golang really does -- an anchored managerFilePatterns plus an allowedVersions cap keeping
#       the line off the next minor.
mkrepo "$work/v6"; rm "$work/v6/UPSTREAM_VERSION"
mkdir -p "$work/v6/lines/126"; printf '1.26.5\n' > "$work/v6/lines/126/UPSTREAM_VERSION"
cat > "$work/v6/.github/renovate.json" <<'JSON'
{"extends":["github>ModernMavericks/shipyard"],
 "customManagers":[{"customType":"regex","managerFilePatterns":["/^lines/126/UPSTREAM_VERSION$/"],
                    "matchStrings":["^(?<currentValue>.+?)\\s*$"],"depNameTemplate":"go-126",
                    "packageNameTemplate":"go","datasourceTemplate":"golang-version"}],
 "packageRules":[{"matchDepNames":["go-126"],"allowedVersions":"<1.27"}]}
JSON
(cd "$work/v6" && git add -A) >/dev/null 2>&1
(cd "$work/v6" && sh "$S" >/dev/null) || { echo "FAIL per-line upstream should pass"; exit 1; }

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
if (cd "$work/bo" && sh "$S" >/dev/null 2>&1); then echo "FAIL: an unignored build output dir should fail"; exit 1; fi
(cd "$work/bo" && sh "$S" 2>&1 | grep -q 'build/updater') || { echo "FAIL: should name the unignored path"; exit 1; }

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
if (cd "$work/bpre" && git add -A >/dev/null 2>&1; sh "$S" >/dev/null 2>&1); then echo "FAIL: an unignored preset binaryDir should fail"; exit 1; fi
(cd "$work/bpre" && sh "$S" 2>&1 | grep -q 'build-native') || { echo "FAIL: should name the preset binaryDir"; exit 1; }

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
if (cd "$work/buntracked" && sh "$S" >/dev/null 2>&1); then echo "FAIL: a COMMITTED build script's dir must be required to be ignored"; exit 1; fi
(cd "$work/buntracked" && sh "$S" 2>&1 | grep -q 'never-committed-build') || { echo "FAIL: should name the tracked script's build dir"; exit 1; }

# spec: scripts/check-family-conventions.sh -- workflow YAML must parse with DUPLICATE KEYS REJECTED. A second `with:` on one step is
#       valid YAML (last key wins) and ordinary parsers accept it, but GitHub refuses to run the
#       workflow: the run shows up named after the file path, "likely failed because of a
#       workflow file issue", with no step logs at all. swift-runtime shipped exactly that.
mkrepo "$work/y1"
awk '{print} /^    steps:$/ && !d {print "      - uses: actions/checkout@v7"; print "        with:"; print "          fetch-depth: 0"; print "        with:"; print "          fetch-depth: 1"; d=1}' \
  "$work/ok/.github/workflows/release.yml" > "$work/y1/.github/workflows/release.yml"
if out="$(cd "$work/y1" && sh "$S" 2>&1)"; then echo "FAIL duplicate key should fail"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'duplicate' || { echo "FAIL should say duplicate: $out"; exit 1; }

mkrepo "$work/y2"
printf 'name: x\non: [push]\njobs:\n  a:\n   steps:\n  - bad indent\n' > "$work/y2/.github/workflows/broken.yml"
if out="$(cd "$work/y2" && sh "$S" 2>&1)"; then echo "FAIL: malformed YAML should fail too, naming the file"; exit 1; fi
printf '%s\n' "$out" | grep -q 'broken.yml' || { echo "FAIL should name the file: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- when PyYAML itself is missing, the gate must NAME the absent dependency rather than dump
#       a ModuleNotFoundError traceback at a repo that is fully compliant. GitHub's macOS runner
#       python3 ships without PyYAML, so this reported a bare "FAIL compliant repo should pass" on
#       every CI run for a month, pointing at the repo instead of at the one `pip install` that
#       fixes it.
mkrepo "$work/y3"
noyaml="$work/noyaml"; mkdir -p "$noyaml"
printf 'raise ImportError("No module named yaml")\n' > "$noyaml/yaml.py"
if out="$(cd "$work/y3" && PYTHONPATH="$noyaml" sh "$S" 2>&1)"; then
  echo "FAIL missing PyYAML should fail (cannot-verify is not a pass)"; exit 1
fi
printf '%s\n' "$out" | grep -qi 'PyYAML' || { echo "FAIL should name PyYAML: $out"; exit 1; }
if printf '%s\n' "$out" | grep -qi 'Traceback'; then
  echo "FAIL should not dump a traceback: $out"; exit 1
fi

# spec: scripts/check-family-conventions.sh -- the 10.9-portability lint runs as part of this gate, so every consumer gets it from the
#       @v1 they already pin. Asserted HERE and not only in shell-portability-test.sh because the
#       wiring is the part that can rot: check-shell-portability.sh could keep passing its own
#       tests while this gate quietly stopped calling it, and nothing would go red.
mkrepo "$work/p1"
printf '#!/bin/sh\nd="$(mktemp -d)"\n' > "$work/p1/tool.sh"  # portability-ok: fixture must contain the violation
(cd "$work/p1" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/p1" && sh "$S" 2>&1)"; then echo "FAIL a 10.9-unportable script should fail the gate"; exit 1; fi
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

mkrepo "$work/r2"
printf '# Build ingredients\n\n| I | Pinned in | Renovate | On a bump |\n|---|---|---|---|\n| Swift | `build.sh` | ❌ untracked | manual |\n' \
  > "$work/r2/INGREDIENTS.md"
if out="$(cd "$work/r2" && sh "$S" 2>&1)"; then echo "FAIL untracked ingredient should fail"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'customManager\|renovate' || { echo "FAIL should name the fix: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but a genuinely UNTRACKABLE input (no datasource exists -- golang's CA bundle) is allowed
#       when it says so. The rule is "wire it or explain why you cannot", not "never write ❌".
mkrepo "$work/r3"
printf '# Build ingredients\n\n| I | Pinned in | Renovate | On a bump |\n|---|---|---|---|\n| CA bundle | `vendor/cacert.pem` | ❌ **untrackable — manual refresh** (see below) | watched path |\n' \
  > "$work/r3/INGREDIENTS.md"
(cd "$work/r3" && sh "$S" >/dev/null) || { echo "FAIL declared-untrackable should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a release shipping a new upstream links upstream's notes: the repo commits the hook that
#       says where, or says in INGREDIENTS.md why there is nothing to link.
mkrepo "$work/u1"; (cd "$work/u1" && git rm -q --cached build/upstream-release-notes-url.sh && rm -r build)
if out="$(cd "$work/u1" && sh "$S" 2>&1)"; then echo "FAIL no hook and no reason should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'upstream-release-notes-url.sh' || { echo "FAIL should name the hook: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'No upstream release notes:' || { echo "FAIL should name the declaration: $out"; exit 1; }
printf '# Build ingredients\n\nNo upstream release notes: this repo is its own upstream.\n' > "$work/u1/INGREDIENTS.md"
(cd "$work/u1" && sh "$S" >/dev/null) || { echo "FAIL: the declaration, with a reason (a self-upstream repo; a bundle), is the other way to comply -- should pass"; exit 1; }
printf '# Build ingredients\n\nNo upstream release notes:\n' > "$work/u1/INGREDIENTS.md"
if (cd "$work/u1" && sh "$S" >/dev/null 2>&1); then echo "FAIL: an empty reason is not a reason -- a reasonless declaration should fail"; exit 1; fi
mkrepo "$work/u2"; (cd "$work/u2" && mkdir scripts && git mv build/upstream-release-notes-url.sh scripts/)
[ -f "$work/u2/scripts/upstream-release-notes-url.sh" ] && [ ! -e "$work/u2/build/upstream-release-notes-url.sh" ] \
  || { echo "FAIL fixture: hook did not move to scripts/"; exit 1; }
(cd "$work/u2" && sh "$S" >/dev/null) || { echo "FAIL: the swift repos keep their scripts, and so the hook, in scripts/ -- a hook there should pass"; exit 1; }
# spec: scripts/check-family-conventions.sh -- a hook that exists but is not committed is the trap: a .gitignore'd build/ drops it
#       without a word (macports-legacy-support ignores build/ wholesale), and CI's fresh
#       checkout never sees it.
mkrepo "$work/u3"; (cd "$work/u3" && git rm -q --cached build/upstream-release-notes-url.sh && printf 'build/\n' >> .gitignore)
if out="$(cd "$work/u3" && sh "$S" 2>&1)"; then echo "FAIL an uncommitted hook should fail"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'not committed' || { echo "FAIL should say it is not committed: $out"; exit 1; }

# spec: a workflow that signs must call scan-for-key.yml -- publish-release.yml refuses a signed
#       release without its record, and a missing job should fail a PR here, not a release there.
mkrepo "$work/k"
printf '      - run: sh "$SHIPYARD_SCRIPTS/sign_and_appcast.sh" --pkg dist/x.pkg > dist/appcast.xml\n' \
  >> "$work/k/.github/workflows/release.yml"
(cd "$work/k" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/k" && sh "$S" 2>&1)"; then echo "FAIL a signing workflow with no scan job should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'scan-for-key.yml' || { echo "FAIL should name scan-for-key.yml: $out"; exit 1; }
cat >> "$work/k/.github/workflows/release.yml" <<'YML'
  scan:
    needs: [build]
    if: always()
    uses: ModernMavericks/shipyard/.github/workflows/scan-for-key.yml@v1
    with: { artifact: dist }
YML
(cd "$work/k" && git add -A) >/dev/null 2>&1
(cd "$work/k" && sh "$S" >/dev/null) || { echo "FAIL a signing workflow with a scan job should pass"; exit 1; }

# spec: SKILL.md "Renovate & automerge" -- a pin on a -mavericks.N release must be read with
#       versioning that COMPARES N. Renovate's default coerces the suffix away, so .1 and .4
#       compare equal and the bot proposes nothing: swift-runtime's swift-toolchain pin sat at
#       6.3.3-mavericks.1 while .4 shipped, with a manager wired and green.
MMVER='regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)-mavericks\.(?<build>\d+)$'
mkrepo "$work/mv"   # swift-runtime's shape: an inline pin in a shared file, default versioning
printf 'TOOLCHAIN_REF="6.3.3-mavericks.1"\n' > "$work/mv/build.sh"
printf '%s\n' '{"extends":["github>ModernMavericks/shipyard"],"customManagers":[{"customType":"regex","managerFilePatterns":["/^build\\.sh$/"],"matchStrings":["TOOLCHAIN_REF=\"(?<currentValue>[^\"]+)\""],"depNameTemplate":"ModernMavericks/swift-toolchain","datasourceTemplate":"github-releases"}]}' \
  > "$work/mv/.github/renovate.json"
(cd "$work/mv" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/mv" && sh "$S" 2>&1)"; then echo "FAIL a -mavericks.N pin with default versioning should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'ModernMavericks/swift-toolchain' || { echo "FAIL should name the dep: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'mavericks' || { echo "FAIL should name the -mavericks.N versioning: $out"; exit 1; }
# spec: with the family's versioning regex (container-tools/tailscale tracking golang), it must
#       pass.
python3 - "$work/mv/.github/renovate.json" "$MMVER" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
c["customManagers"][0]["versioningTemplate"] = sys.argv[2]
json.dump(c, open(p, "w"))
PY
(cd "$work/mv" && git add -A) >/dev/null 2>&1
(cd "$work/mv" && sh "$S" >/dev/null) || { echo "FAIL a -mavericks.N pin with the family versioning should pass"; exit 1; }
# spec: scripts/check-family-conventions.sh -- but a regex that matches the version without capturing N is the same bug, spelled
#       differently.
mkrepo "$work/mv2"
printf '6.3.3-mavericks.1\n' > "$work/mv2/components-version"
printf '%s\n' '{"extends":["github>ModernMavericks/shipyard"],"customManagers":[{"customType":"regex","managerFilePatterns":["/^components-version$/"],"matchStrings":["^(?<currentValue>.+?)\\s*$"],"depNameTemplate":"x","datasourceTemplate":"github-releases","versioningTemplate":"regex:^(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)"}]}' \
  > "$work/mv2/.github/renovate.json"
(cd "$work/mv2" && git add -A) >/dev/null 2>&1
if (cd "$work/mv2" && sh "$S" >/dev/null 2>&1); then echo "FAIL versioning that ignores N should fail"; exit 1; fi
# spec: scripts/check-family-conventions.sh -- and a pin that is NOT a -mavericks.N release needs nothing (openssh's own upstream, tag
#       form).
mkrepo "$work/mv3"
printf 'V_9_9_P2\n' > "$work/mv3/components-version"
printf '%s\n' '{"extends":["github>ModernMavericks/shipyard"],"customManagers":[{"customType":"regex","managerFilePatterns":["/^components-version$/"],"matchStrings":["^(?<currentValue>V_[0-9_P]+)\\s*$"],"depNameTemplate":"openssh/openssh-portable","datasourceTemplate":"github-tags"}]}' \
  > "$work/mv3/.github/renovate.json"
(cd "$work/mv3" && git add -A) >/dev/null 2>&1
(cd "$work/mv3" && sh "$S" >/dev/null) || { echo "FAIL a non-mavericks pin should pass"; exit 1; }

# spec: SKILL.md "Family conventions" check 14 -- the release body comes from the shared
#       generator, and every consumer reads that same file. Before Plan 2 six products published
#       "Automated release for Mac OS X 10.9 (Mavericks)." as their entire notes and tailscale
#       published an empty body; all 13 now call release-notes.sh. Check 5 only asks whether SOME
#       notes reached the release, which --generate-notes and a printf redirect both satisfy.
#       This is the strong form, and it fails on the PR rather than at release time. mkrepo's
#       baseline already IS the compliant shape (generator --out dist/RELEASE_NOTES.md, publisher
#       --notes-file dist/RELEASE_NOTES.md), so `mkrepo` alone covers the passing case; each
#       fixture below breaks exactly one thing -- starting with no generator at all: a repo that
#       publishes some body, but not this family's.
mkrepo "$work/g1"
grep -v 'release-notes\.sh' "$work/ok/.github/workflows/release.yml" > "$work/g1/.github/workflows/release.yml"
if out="$(cd "$work/g1" && sh "$S" 2>&1)"; then echo "FAIL a repo with no generator call should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'release-notes.sh' || { echo "FAIL should name the generator: $out"; exit 1; }

# spec: check-release-notes.sh is the PUBLISHER's shape gate, a different script. A substring
#       match on "release-notes.sh" would let a repo that only runs the shape gate pass while
#       writing no body.
mkrepo "$work/g1b"
sed -e 's|sh "$SHIPYARD_SCRIPTS/release-notes\.sh" .*|sh "$SHIPYARD_SCRIPTS/check-release-notes.sh" dist/RELEASE_NOTES.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g1b/.github/workflows/release.yml"
if out="$(cd "$work/g1b" && sh "$S" 2>&1)"; then echo "FAIL check-release-notes.sh must not count as the generator"; exit 1; fi
printf '%s\n' "$out" | grep -q 'no workflow builds the release body' || { echo "FAIL should fail for the missing generator, not something else: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a hand-written body is the exact regression this check exists for, in the printf-redirect
#       shape.
mkrepo "$work/g2"
sed -e 's|sh "$SHIPYARD_SCRIPTS/release-notes\.sh" .*|printf "## %s\\n\\nAutomated release.\\n" "$FULL" > dist/RELEASE_NOTES.md|' \
  -e '/--product Widget --min-os/d' "$work/ok/.github/workflows/release.yml" > "$work/g2/.github/workflows/release.yml"
if out="$(cd "$work/g2" && sh "$S" 2>&1)"; then echo "FAIL a hand-written body should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'hand-writes the release body' || { echo "FAIL should say it is hand-written: $out"; exit 1; }

# spec: and in the copy-a-committed-file shape (porthole shipped its README.md as the body of
#       every release). The generator call stays, so this is caught by the redirect/cp clause and
#       nothing else.
mkrepo "$work/g3"
cat >> "$work/g3/.github/workflows/release.yml" <<'YML'
      - run: cp release-notes/README.md dist/RELEASE_NOTES.md
YML
if out="$(cd "$work/g3" && sh "$S" 2>&1)"; then echo "FAIL copying a committed file in as the body should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'hand-writes the release body' || { echo "FAIL should say it is hand-written: $out"; exit 1; }

# spec: and in the directory that is NOT dist/. magic-trackpad2 stages its body at
#       build/RELEASE_NOTES.md, so a hand-write check anchored on dist/ passes every test above
#       while leaving the one repo that uses another directory completely uncovered -- which is
#       what a mutation run found here. The directory is the caller's business; the FILE is what
#       only the generator may write.
mkrepo "$work/g3b"
cat >> "$work/g3b/.github/workflows/release.yml" <<'YML'
      - run: printf '## %s\n\nAutomated release.\n' "$FULL" > build/RELEASE_NOTES.md
YML
if out="$(cd "$work/g3b" && sh "$S" 2>&1)"; then echo "FAIL a hand-written body outside dist/ should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'hand-writes the release body' || { echo "FAIL should say it is hand-written: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but COPYING the generated body somewhere else is reading it, not writing it. A repo
#       staging the file into an artifact does exactly this, and flagging it would fail a correct
#       repo.
mkrepo "$work/g3c"
cat >> "$work/g3c/.github/workflows/release.yml" <<'YML'
      - run: cp dist/RELEASE_NOTES.md "$RUNNER_TEMP/keep.md"
YML
(cd "$work/g3c" && sh "$S" >/dev/null) || { echo "FAIL copying the generated body OUT must not be read as hand-writing it"; exit 1; }

# spec: scripts/check-family-conventions.sh -- GitHub's autogenerated notes are a commit list, not the Sparkle <description> a 10.9 user
#       reads. It satisfies check 5, which is exactly why 14 has to reject it by name.
mkrepo "$work/g4"
cat >> "$work/g4/.github/workflows/release.yml" <<'YML'
      - run: gh release create "$TAG" --generate-notes
YML
if out="$(cd "$work/g4" && sh "$S" 2>&1)"; then echo "FAIL --generate-notes should fail"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'autogenerated' || { echo "FAIL should name the autogenerated body: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the appcast must read the file the generator wrote, or the Release page and the update
#       dialog tell two different stories.
mkrepo "$work/g5"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file release-notes/README.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g5/.github/workflows/release.yml"
if out="$(cd "$work/g5" && sh "$S" 2>&1)"; then echo "FAIL a notes file the generator never wrote should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'the generator does not write' || { echo "FAIL should say the generator does not write it: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'release-notes/README.md' || { echo "FAIL should name the offending path: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- now the four shapes the REAL repos use, each of which a plausible check gets wrong.
#       magic-trackpad2 stages its body at build/RELEASE_NOTES.md and QUOTES the value. A check
#       anchored on dist/ fails it; a character class that excludes the quote captures an EMPTY
#       value and fails it too (and swift-runtime, which quotes a dist/ path).
mkrepo "$work/g6"
sed -e 's|--out dist/RELEASE_NOTES\.md|--out build/RELEASE_NOTES.md|' \
    -e 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "build/RELEASE_NOTES.md"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g6/.github/workflows/release.yml"
(cd "$work/g6" && sh "$S" >/dev/null) || { echo "FAIL a quoted build/ notes path should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the quote must actually be STRIPPED, not merely survived. A pattern that excludes the
#       quote from the value captures an EMPTY string, which word-splits away to nothing and
#       leaves the subset loop with no members at all -- so the case above would keep passing for
#       entirely the wrong reason, with the comparison silently switched off for the two repos
#       that quote. A mutation run found this. A WRONG quoted path is what tells the two apart.
mkrepo "$work/g6b"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "release-notes/README.md"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g6b/.github/workflows/release.yml"
if out="$(cd "$work/g6b" && sh "$S" 2>&1)"; then echo "FAIL a quoted notes path the generator never wrote should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'release-notes/README.md' || { echo "FAIL should name the unquoted path: $out"; exit 1; }

# spec: --out is not release-notes.sh's flag alone -- container-tools and tailscale pass --out
#       "$PKG" to cmake/package_pkg.sh. That must not make "$PKG" an acceptable --notes-file.
mkrepo "$work/g7"
cat >> "$work/g7/.github/workflows/release.yml" <<'YML'
      - run: sh cmake/package_pkg.sh --out "$PKG" --version "$VER"
YML
(cd "$work/g7" && sh "$S" >/dev/null) || { echo "FAIL a packaging step's --out must not fail the repo"; exit 1; }
# spec: the .md filter is what stops a packaging --out from vouching for a notes file. Spelled
#       with a LITERAL .pkg: a "$PKG" on the --notes-file side is skipped as unresolvable (see
#       g12 below) and would prove nothing about the filter.
mkrepo "$work/g7b"
cat >> "$work/g7b/.github/workflows/release.yml" <<'YML'
      - run: sh cmake/package_pkg.sh --out dist/tool.pkg --version "$VER"
      - run: sh "$SHIPYARD_SCRIPTS/gen_appcast.sh" --notes-file dist/tool.pkg
YML
if out="$(cd "$work/g7b" && sh "$S" 2>&1)"; then echo "FAIL a packaging --out must not vouch for a non-.md notes file"; exit 1; fi
printf '%s\n' "$out" | grep -q 'dist/tool.pkg' || { echo "FAIL should name the non-.md notes file: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the comparison is between WHOLE values. A --notes-file that is a strict SUFFIX of a real
#       --out value is a genuinely different file, and a substring match would wave it through.
mkrepo "$work/g5c"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file NOTES.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g5c/.github/workflows/release.yml"
if out="$(cd "$work/g5c" && sh "$S" 2>&1)"; then echo "FAIL a notes file that is only a SUFFIX of the --out path should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'notes-file NOTES.md' || { echo "FAIL should name the suffix path: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a repo that routes ONE path through a variable is more self-consistent than one spelling
#       it twice, and the two sides simply cannot be compared as text. Failing it would tell a
#       correct repo to "pass the same path release-notes.sh was given as --out" -- which it did.
#       Unresolvable values are skipped.
mkrepo "$work/g12"
sed -e 's|--out dist/RELEASE_NOTES\.md|--out "$NOTES"|' \
    -e 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "$NOTES"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g12/.github/workflows/release.yml"
(cd "$work/g12" && sh "$S" >/dev/null) || { echo "FAIL a notes path routed through a variable should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and a workflow expression the same way. Unskipped, the value stops at the first space and
#       the failure message named the garbage '${{'.
mkrepo "$work/g12b"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "${{ steps.notes.outputs.path }}"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g12b/.github/workflows/release.yml"
(cd "$work/g12b" && sh "$S" >/dev/null) || { echo "FAIL a notes path from a workflow expression should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but skipping the unresolvable ones must not switch the comparison off: a LITERAL mismatch
#       in the same repo still fails.
mkrepo "$work/g12c"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "$NOTES" --notes-file release-notes/README.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g12c/.github/workflows/release.yml"
if out="$(cd "$work/g12c" && sh "$S" 2>&1)"; then echo "FAIL a literal mismatch alongside a variable one should still fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'release-notes/README.md' || { echo "FAIL should name the literal mismatch: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a flag and its value need not share a line. Reproduced against openssh's real main by
#       changing nothing but whitespace: the captured --out value became the backslash, the .md
#       filter dropped it, and the repo was told to "pass the same path release-notes.sh was
#       given as --out" -- which it did. No repo wraps this way today, so this is a cosmetic
#       reformat away, not live; a reformat must not redden a repo.
mkrepo "$work/g17"
sed 's|--product Widget --min-os 10.9.5 --out dist/RELEASE_NOTES\.md|--product Widget --min-os 10.9.5 \\\
            --out \\\
            dist/RELEASE_NOTES.md|' "$work/ok/.github/workflows/release.yml" > "$work/g17/.github/workflows/release.yml"
grep -q '^ *--out \\$' "$work/g17/.github/workflows/release.yml" \
  || { echo "FAIL test setup did not produce a line-wrapped --out"; exit 1; }
(cd "$work/g17" && sh "$S" >/dev/null) || { echo "FAIL a line-wrapped --out value should pass"; exit 1; }

mkrepo "$work/g18"
sed -e 's|--out dist/RELEASE_NOTES\.md|--out=dist/RELEASE_NOTES.md|' \
    "$work/ok/.github/workflows/release.yml" > "$work/g18/.github/workflows/release.yml"
grep -q -e '--out=dist/RELEASE_NOTES\.md' "$work/g18/.github/workflows/release.yml" \
  || { echo "FAIL test setup did not produce an --out=VALUE form"; exit 1; }
(cd "$work/g18" && sh "$S" >/dev/null) \
  || { echo "FAIL --out=VALUE is the same command as --out VALUE, and a repo that writes the equals form must not be told it reads a notes file the generator does not write: the flag/value separator is a character class, not a literal space"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the same on the reading side, which wraps just as legally. A block scalar, because that
#       is where a wrapped shell command can legally live: folding a plain `run:` scalar over two
#       lines would change what the shell is handed, and a fixture has to be a repo someone could
#       really write.
mkrepo "$work/g17b"
grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/g17b/.github/workflows/release.yml"
cat >> "$work/g17b/.github/workflows/release.yml" <<'YML'
      - run: |
          gh release create "$TAG" dist/* --notes-file \
            dist/RELEASE_NOTES.md
YML
(cd "$work/g17b" && sh "$S" >/dev/null) || { echo "FAIL a line-wrapped --notes-file value should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and joining the continuation must not be a way to switch the comparison off: a WRONG
#       path, wrapped, still fails and is still named. Without this, "wrapped values are skipped"
#       would pass the two cases above while checking nothing.
mkrepo "$work/g17c"
grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/g17c/.github/workflows/release.yml"
cat >> "$work/g17c/.github/workflows/release.yml" <<'YML'
      - run: |
          gh release create "$TAG" dist/* --notes-file \
            release-notes/README.md
YML
if out="$(cd "$work/g17c" && sh "$S" 2>&1)"; then echo "FAIL a wrapped notes path the generator never wrote should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'release-notes/README.md' || { echo "FAIL should name the wrapped mismatch: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- 1password, ed25519, signal-desktop and swift-toolchain pass no --notes-file at all: they
#       stage no appcast from the notes. The subset loop is then empty, which is correct and not
#       a gap.
mkrepo "$work/g8"
grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/g8/.github/workflows/release.yml"
cat >> "$work/g8/.github/workflows/release.yml" <<'YML'
  publish:
    uses: ModernMavericks/shipyard/.github/workflows/publish-release.yml@v1
YML
(cd "$work/g8" && sh "$S" >/dev/null) || { echo "FAIL a repo that stages no appcast from the notes should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- porthole's feed-porthole moving-tag release passes a bare --notes "<text>" to gh release.
#       That is a feed pointer, not a product release body, and failing it would redden a
#       correct repo. golang does the same for each go-line feed.
mkrepo "$work/g9"
cat >> "$work/g9/.github/workflows/release.yml" <<'YML'
      - run: |
          gh release create feed-porthole --title 'Porthole appcast' \
            --notes "Sparkle appcast for Porthole; asset replaced every release, tag never moves."
YML
(cd "$work/g9" && sh "$S" >/dev/null) || { echo "FAIL a bare --notes on a moving-tag feed release must not fail"; exit 1; }

# spec: scripts/check-family-conventions.sh -- golang renders TWO appcasts from one body. The comparison is between SETS, so the same
#       path read twice is one member, not a duplicate to complain about.
mkrepo "$work/g10"
cat >> "$work/g10/.github/workflows/release.yml" <<'YML'
      - run: |
          sh "$SHIPYARD_SCRIPTS/gen_appcast.sh" --notes-file dist/RELEASE_NOTES.md --out-x dist/x.xml
          sh "$SHIPYARD_SCRIPTS/gen_appcast.sh" --notes-file dist/RELEASE_NOTES.md --out-n dist/n.xml
YML
(cd "$work/g10" && sh "$S" >/dev/null) || { echo "FAIL two appcasts from one body should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- prose about a rule is not the rule being obeyed or broken. This family documents its
#       conventions in the very workflows they govern, so every clause here false-POSITIVES on
#       comments unless comment lines are dropped: appending any ONE of these four to openssh's
#       real main reddened it, and @v1 would have carried that to twelve repos within minutes. A
#       maintainer writing the rule down must not be the thing that breaks the rule.
mkrepo "$work/g13"
cat >> "$work/g13/.github/workflows/release.yml" <<'YML'
      - run: |
          # was: printf "x" > dist/RELEASE_NOTES.md -- never again
          # never: cp release-notes/README.md dist/RELEASE_NOTES.md
          # NOT --generate-notes here: it cannot say which ingredient moved
          # do not write --notes-file release-notes/README.md
          true
YML
(cd "$work/g13" && sh "$S" >/dev/null) || { echo "FAIL comments describing the banned shapes must not fail a correct repo"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the other direction, which is the reason to filter in ci_mentions rather than only
#       where a false positive stung: a repo whose ONLY mention of the generator is a comment is
#       not wired up. magic-trackpad2 carries five such comment mentions beside its one real
#       invocation, so an unfiltered clause 1 kept printing "ok" with that invocation replaced by
#       `:`.
mkrepo "$work/g14"
sed 's|sh "$SHIPYARD_SCRIPTS/release-notes\.sh" .*|# TODO: rewire sh "$SHIPYARD_SCRIPTS/release-notes.sh" here|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g14/.github/workflows/release.yml"
if out="$(cd "$work/g14" && sh "$S" 2>&1)"; then echo "FAIL a generator mentioned only in a comment is not wired up"; exit 1; fi
printf '%s\n' "$out" | grep -q 'no workflow builds the release body' || { echo "FAIL should say the generator is not called: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the residual the filter deliberately accepts, which is load-bearing rather than a
#       tolerated wart: container-tools writes
#       `--out dist/RELEASE_NOTES.md   # becomes the Release body`. A line that carries CODE plus
#       a trailing comment is not a comment line, and dropping it would drop a real --out.
mkrepo "$work/g15"
sed 's|--out dist/RELEASE_NOTES\.md|--out dist/RELEASE_NOTES.md   # becomes the Release body|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g15/.github/workflows/release.yml"
(cd "$work/g15" && sh "$S" >/dev/null) || { echo "FAIL a trailing inline comment must not hide a real --out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the comment filter lives in ci_mentions, so checks 2, 5 and 12 get it too -- a comment
#       should not vouch for wiring anywhere. A repo whose only mention of the test runner is a
#       comment has unrun tests.
mkrepo "$work/g16"
sed 's|- run: sh "$SHIPYARD_SCRIPTS/run-repo-tests\.sh"|# we should run: sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g16/.github/workflows/release.yml"
if out="$(cd "$work/g16" && sh "$S" 2>&1)"; then echo "FAIL a test runner mentioned only in a comment should fail check 2"; exit 1; fi
printf '%s\n' "$out" | grep -q 'no workflow runs them' || { echo "FAIL should say the tests are not run: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a check-14 failure must ACCUMULATE like every other, not abort the run: this gate reports
#       all its failures at once, and a check 14 that killed the script under set -eu would take
#       the "ok" guard and any future check 15 with it. So a repo that breaks 14 AND an earlier
#       check must report both.
mkrepo "$work/g11"; rm -f "$work/g11/INGREDIENTS.md"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file release-notes/README.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g11/.github/workflows/release.yml"
out="$(cd "$work/g11" && sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'INGREDIENTS.md' || { echo "FAIL check 3 should still be reported: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'the generator does not write' || { echo "FAIL check 14 should still be reported: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a failing run must NOT also print "ok". The success line used to sit mid-script, so
#       checks appended after it (7, 8, 9) printed "check-family-conventions: ok" and THEN failed
#       -- the exact "output says it passed while it did not" shape these gates exist to prevent.
mkrepo "$work/ok2"
printf '# Build ingredients\n\n| I | P | Renovate | On a bump |\n|---|---|---|---|\n| X | `y` | ❌ untracked | manual |\n' \
  > "$work/ok2/INGREDIENTS.md"
out="$(cd "$work/ok2" && sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'check-family-conventions: ok' \
  && { echo "FAIL a failing run printed ok: $out"; exit 1; }

# spec: SKILL.md "Family conventions" check 15 -- delegates to check-comments.sh, so these
#       fixtures prove the WIRING, not the scanner (tests/check-comments-test.sh already covers the
#       scanner's rules in detail). comment-reasons here mirrors this repo's own root file
#       (platform, spec) so the fixture reasons match what check-comments.sh actually ships with.
mkrepo "$work/cm1"
mkdir -p "$work/cm1/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm1/scripts/x.sh"
printf 'platform\nspec\n' > "$work/cm1/comment-reasons"
(cd "$work/cm1" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/cm1" && sh "$S" 2>&1)"; then echo "FAIL: an untagged comment, with comment-reasons present, should fail"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'cite a reason' || { echo "FAIL should name what to cite: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the same fixture, tagged, must pass: the check is
#       satisfied by a reason, not by removing the comment.
mkrepo "$work/cm2"
mkdir -p "$work/cm2/scripts"
printf '#!/bin/sh\n# platform: a fact about the platform or a tool\nexit 0\n' > "$work/cm2/scripts/x.sh"
printf 'platform\nspec\n' > "$work/cm2/comment-reasons"
(cd "$work/cm2" && git add -A) >/dev/null 2>&1
(cd "$work/cm2" && sh "$S" >/dev/null) || { echo "FAIL: a comment tagged # platform: should pass"; exit 1; }

# spec: SKILL.md "Comments cite a reason" -- check-comments.sh itself exits 0 with
#       no comment-reasons file; this fixture is the load-bearing proof that the WIRING preserves
#       that opt-in. check-family-conventions.sh runs in 14 consumers through a moving @v1 tag --
#       without this passing, the day check 15 lands is the day all 14 go red on an untagged
#       comment nobody there has swept yet.
mkrepo "$work/cm3"
mkdir -p "$work/cm3/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm3/scripts/x.sh"
(cd "$work/cm3" && git add -A) >/dev/null 2>&1
(cd "$work/cm3" && sh "$S" >/dev/null) || { echo "FAIL: no comment-reasons file at all must pass despite an untagged comment -- this is the opt-in promise"; exit 1; }

# spec: SKILL.md "Conformance deviations" -- the same declared-exception shape
#       check-artifact-conformance.sh already uses, reused here for a swept repo that still wants
#       ONE stated exception rather than fixing the comment.
mkrepo "$work/cm4"
mkdir -p "$work/cm4/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm4/scripts/x.sh"
printf 'platform\nspec\n' > "$work/cm4/comment-reasons"
printf '# Build ingredients\n\n## Conformance deviations\n\n- comments: vendored verbatim from upstream, reformatting it would defeat the point of a byte-for-byte mirror\n' \
  > "$work/cm4/INGREDIENTS.md"
(cd "$work/cm4" && git add -A) >/dev/null 2>&1
(cd "$work/cm4" && sh "$S" >/dev/null) || { echo "FAIL: a declared deviation with a reason should pass"; exit 1; }

mkrepo "$work/cm5"
mkdir -p "$work/cm5/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm5/scripts/x.sh"
printf 'platform\nspec\n' > "$work/cm5/comment-reasons"
printf '# Build ingredients\n\n## Conformance deviations\n\n- comments:vendor/* upstream code, not ours to sweep\n' \
  > "$work/cm5/INGREDIENTS.md"
(cd "$work/cm5" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/cm5" && sh "$S" 2>&1)"; then echo "FAIL: a scoped comments deviation was honoured -- the glob was swallowed as part of the reason and comment checking went off REPO-WIDE, which is exactly the drift nobody would ever notice: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'repo-wide' \
  || { echo "FAIL: the rejection must say check 15's deviation is repo-wide, or the author just retries the same glob: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '- comments: <reason>' \
  || { echo "FAIL: the rejection must name what to write instead: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'DECLARED DEVIATION' \
  && { echo "FAIL: a scoped deviation must not also be announced as accepted: $out"; exit 1; }

mkrepo "$work/cm6"
mkdir -p "$work/cm6/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm6/scripts/x.sh"
printf 'platform\nspec\n' > "$work/cm6/comment-reasons"
printf '# Build ingredients\n\n## Conformance deviations\n\n- comments :vendor/* upstream code, not ours to sweep\n' \
  > "$work/cm6/INGREDIENTS.md"
(cd "$work/cm6" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/cm6" && sh "$S" 2>&1)"; then echo "FAIL: a scoped comments deviation with a space before the colon was honoured -- the parser that accepts the deviation line tolerates that space, and the rejection must too: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'repo-wide' \
  || { echo "FAIL: the rejection must say check 15's deviation is repo-wide, or the author just retries the same glob: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'DECLARED DEVIATION' \
  && { echo "FAIL: a scoped deviation must not also be announced as accepted: $out"; exit 1; }
# spec: SKILL.md "Family conventions" check 16 -- nothing tracked reads the CMake user package
#       registry, because nothing writes it any more.
mkrepo "$work/r16"; printf '#!/bin/sh\ncat "$HOME/.cmake/packages/MavericksShipyard/"*\n' > "$work/r16/build/x.sh"
(cd "$work/r16" && git add -A) >/dev/null 2>&1
if (cd "$work/r16" && sh "$S" >/dev/null 2>&1); then echo "FAIL 16: a registry read should fail"; exit 1; fi
(cd "$work/r16" && sh "$S" 2>&1 | grep -q 'user package registry') || { echo "FAIL 16: should name the registry"; exit 1; }
printf '\n## Conformance deviations\n- registry-read:build/x.sh: a shim that leaves with the flag day\n' >> "$work/r16/INGREDIENTS.md"
(cd "$work/r16" && sh "$S" >/dev/null) || { echo "FAIL 16: a declared registry-read deviation should pass"; exit 1; }

# spec: tests/shipyard-release-workflow-test.sh -- a test asserting the registry is GONE has to be
#       able to name it, so check 16 reads what a repo SHIPS and not what it asserts about itself.
mkrepo "$work/r16ok"
printf '#!/bin/sh\ngrep -q "cmake/packages" out && { echo "the registry came back"; exit 1; }\n' \
  > "$work/r16ok/tests/registry-gone-test.sh"
printf '#!/bin/sh\n# We used to read "$HOME/.cmake/packages/MavericksShipyard"; msc.sh replaced it.\nexit 0\n' \
  > "$work/r16ok/build/history.sh"
(cd "$work/r16ok" && git add -A) >/dev/null 2>&1
(cd "$work/r16ok" && sh "$S" >/dev/null) || { echo "FAIL 16: a test asserting the registry is gone, and a comment about it, should pass"; exit 1; }

# spec: SKILL.md "Family conventions" check 17 -- a product's msc.sh is shipyard's canonical
#       template, byte for byte.
mkrepo "$work/m17"; cp "$here/../scripts/templates/msc.sh" "$work/m17/build/msc.sh"
(cd "$work/m17" && git add -A) >/dev/null 2>&1
(cd "$work/m17" && sh "$S" >/dev/null) || { echo "FAIL 17: the canonical msc.sh should pass"; exit 1; }
echo '# a local tweak' >> "$work/m17/build/msc.sh"
if (cd "$work/m17" && sh "$S" >/dev/null 2>&1); then echo "FAIL 17: a drifted msc.sh should fail"; exit 1; fi
(cd "$work/m17" && sh "$S" 2>&1 | grep -q 'canonical msc.sh') || { echo "FAIL 17: should name the canonical msc.sh"; exit 1; }
(cd "$work/m17" && sh "$S" 2>&1 | grep -q 'a local tweak') || { echo "FAIL 17: should show the first difference"; exit 1; }
printf '\n## Conformance deviations\n- msc-template:build/msc.sh: exercising the deviation path\n' >> "$work/m17/INGREDIENTS.md"
(cd "$work/m17" && sh "$S" >/dev/null) || { echo "FAIL 17: a declared msc-template deviation should pass"; exit 1; }

# spec: SKILL.md "Family conventions" check 17 -- only TRACKED copies count, the rule 7c/7d already
#       apply: an untracked build/msc.sh in a worktree is not what the repo ships, and failing on it
#       would make the gate unrunnable for the person mid-way through fixing it.
mkrepo "$work/m17u"
printf '# a drifted scratch copy nobody committed\n' > "$work/m17u/build/msc.sh"
(cd "$work/m17u" && sh "$S" >/dev/null) || { echo "FAIL 17: an UNTRACKED msc.sh must not fail the gate"; exit 1; }
(cd "$work/m17u" && git add -A) >/dev/null 2>&1
if (cd "$work/m17u" && sh "$S" >/dev/null 2>&1); then echo "FAIL 17: ...but once committed it counts"; exit 1; fi

# platform: `cmp -s` against a nonexistent file is "different", so a template that MOVED would redden
#           all fifteen repos at once with the real cause nowhere in the message. A missing template
#           must name itself instead.
mkrepo "$work/m17t"; cp "$here/../scripts/templates/msc.sh" "$work/m17t/build/msc.sh"
(cd "$work/m17t" && git add -A) >/dev/null 2>&1
fake="$work/fakeshipyard"; mkdir -p "$fake"
for g in "$here"/../scripts/*.sh; do cp "$g" "$fake/"; done
mkdir -p "$fake/templates"   # ...but no msc.sh in it
out="$(cd "$work/m17t" && sh "$fake/check-family-conventions.sh" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'canonical msc.sh at' \
  || { echo "FAIL 17: a missing template must name the template, not the repo: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'is not shipyard' \
  && { echo "FAIL 17: a missing template must NOT be reported as the repo's msc.sh being wrong"; exit 1; }

# spec: SKILL.md "Family conventions" check 18 -- configure, test and package with
#       shipyard-cmake/ctest/cpack, in workflows and in committed build scripts.
mkrepo "$work/p18"; printf '      - run: cmake -S . -B "$RUNNER_TEMP/b"\n' >> "$work/p18/.github/workflows/release.yml"
(cd "$work/p18" && git add -A) >/dev/null 2>&1
if (cd "$work/p18" && sh "$S" >/dev/null 2>&1); then echo "FAIL 18: plain cmake in a workflow should fail"; exit 1; fi
(cd "$work/p18" && sh "$S" 2>&1 | grep -q 'shipyard-cmake') || { echo "FAIL 18: should say shipyard-cmake"; exit 1; }
mkrepo "$work/p18b"; printf '#!/bin/sh\ncd x && ctest --test-dir b\n' > "$work/p18b/build/t.sh"
(cd "$work/p18b" && git add -A) >/dev/null 2>&1
if (cd "$work/p18b" && sh "$S" >/dev/null 2>&1); then echo "FAIL 18: plain ctest in a build script should fail"; exit 1; fi
mkrepo "$work/p18ok"; printf '      - run: shipyard-cmake -S . -B "$RUNNER_TEMP/b"   # not plain cmake\n' >> "$work/p18ok/.github/workflows/release.yml"
printf '#!/bin/sh\n# cmake -S would be wrong here, but this is a comment\n' > "$work/p18ok/build/c.sh"
(cd "$work/p18ok" && git add -A) >/dev/null 2>&1
(cd "$work/p18ok" && sh "$S" >/dev/null) || { echo "FAIL 18: shipyard-cmake and comments should pass"; exit 1; }
printf '\n## Conformance deviations\n- shipyard-cmake-only:build/t.sh: exercising the deviation path\n' >> "$work/p18b/INGREDIENTS.md"
(cd "$work/p18b" && sh "$S" >/dev/null) || { echo "FAIL 18: a declared shipyard-cmake-only deviation should pass"; exit 1; }

# spec: SKILL.md "Check 18" -- the shapes a whole-org survey turned up that are NOT an invocation.
#       Each was a false positive on a first draft and would have put a compliant repo on the
#       migration queue: CMake language in a probe heredoc; a prose word in a message, variable, URL
#       or path; a longer identifier (cmake_policy, ctest_start); an assignment or a --flag value;
#       and `(cmake --build <dir>)` inside an error message -- the survey's real catch, the only hit
#       in container-tools, openssh and swift-runtime, three compliant files each telling a human
#       what to run, flagged because the first draft read a bare `(` as command position.
mkrepo "$work/p18ok2"
cat > "$work/p18ok2/build/shapes.sh" <<'SH'
#!/bin/sh
printf '%s\n' 'cmake_minimum_required(VERSION 3.16)' 'project(p NONE)' > "$d/CMakeLists.txt"
echo "install any cmake, then re-run"
url=https://cmake.org/files/v4.4/cmake-4.4.3.tar.gz
CMAKE_BIN=shipyard-cmake
"$CMAKE_BIN" -S . -B b
test -x /usr/local/bin/shipyard-ctest || echo "no ctest here"
[ -f "$A" ] || { echo "build the shim first (cmake --build <dir>); need $A"; exit 2; }
[ -d "$UPD_APP" ] || { echo "FATAL: updater not built at $UPD_APP (cmake --build build/updater)" >&2; exit 1; }
[ -d "$SH" ] || { echo "shipyard not found"; echo "       install it (cmake --install) or set SHIPYARD_SCRIPTS." >&2; exit 4; }
SH
(cd "$work/p18ok2" && git add -A) >/dev/null 2>&1
(cd "$work/p18ok2" && sh "$S" >/dev/null) || {
  echo "FAIL 18: non-invocation shapes should pass:"; (cd "$work/p18ok2" && sh "$S" 2>&1 | grep 'plain cmake'); exit 1; }

# spec: SKILL.md "Check 18" -- the tightening must not go so far that a real call hides behind a
#       paren: a command substitution IS a call, and a subshell announces itself with the `&&` after
#       the cd. The -B is out of tree so check 7d does not additionally demand a .gitignore for it,
#       here or in THIS file, itself a tracked *.sh that 7d sweeps.
for shape in 'v="$(cmake --version | head -1)"' '(cd sub && cmake -S . -B /tmp/b)'; do
  mkrepo "$work/p18bad"
  printf '#!/bin/sh\n%s\n' "$shape" > "$work/p18bad/build/call.sh"
  (cd "$work/p18bad" && git add -A) >/dev/null 2>&1
  if (cd "$work/p18bad" && sh "$S" >/dev/null 2>&1); then
    echo "FAIL 18: a real call should still fail: $shape"; exit 1
  fi
  rm -rf "$work/p18bad"
done

# spec: SKILL.md "Check 18" -- the LIMIT of "prose is not a call". A quoted message or a heredoc
#       whose text carries `;`, `&&` or a backtick immediately before the command still matches;
#       separating those from a real call needs a shell parser. Asserted here so the limitation is a
#       written rule rather than something a contributor rediscovers when an ordinary usage() block
#       reddens a PR. lim18 <repo> <what> demands the repo fail ON CHECK 18, not merely fail: several
#       of these fixtures also trip check 7d, so "exit != 0" alone would pass even if check 18 had
#       stopped matching entirely.
lim18() {
  if (cd "$1" && sh "$S" >/dev/null 2>&1); then
    echo "FAIL 18: $2 is (knowingly) still flagged -- assert it"; exit 1; fi
  (cd "$1" && sh "$S" 2>&1 | grep -q 'runs plain cmake/ctest/cpack') \
    || { echo "FAIL 18: $2 failed, but not on check 18 -- the assertion is not testing what it says"; exit 1; }
}

mkrepo "$work/p18lim"
cat > "$work/p18lim/build/prose.sh" <<'SH'
#!/bin/sh
echo "to rebuild: cmake -S . -B /tmp/b; cmake --build /tmp/b"
SH
(cd "$work/p18lim" && git add -A) >/dev/null 2>&1
lim18 "$work/p18lim" "a quoted message separated by ';'"

mkrepo "$work/p18lim2"
cat > "$work/p18lim2/build/prose.sh" <<'SH'
#!/bin/sh
echo "or: shipyard-cmake -S . -B /tmp/b && cmake --build /tmp/b"
SH
(cd "$work/p18lim2" && git add -A) >/dev/null 2>&1
lim18 "$work/p18lim2" "a quoted message separated by '&&'"

mkrepo "$work/p18lim3"
printf '#!/bin/sh\nprintf %s\n' "'try \`cmake --version\` first\\n'" > "$work/p18lim3/build/prose.sh"
(cd "$work/p18lim3" && git add -A) >/dev/null 2>&1
lim18 "$work/p18lim3" "a backtick-quoted command in prose"

mkrepo "$work/p18lim4"
cat > "$work/p18lim4/build/prose.sh" <<'SH'
#!/bin/sh
usage() { cat <<EOF
  cmake -S . -B build
  cmake --build build
EOF
}
SH
(cd "$work/p18lim4" && git add -A) >/dev/null 2>&1
lim18 "$work/p18lim4" "a usage() heredoc listing commands"

# spec: SKILL.md "Check 18" -- the known false negatives, asserted for the same reason: a bare
#       subshell, a path, a variable or a prefix command hides a real call from this check, and each
#       is caught at configure time instead. Dropping the bare `(` from the separator class is what
#       killed the three real false positives, so the miss is the deliberate price, NOT evidence that
#       `(` means prose.
mkrepo "$work/p18fn"
cat > "$work/p18fn/build/hidden.sh" <<'SH'
#!/bin/sh
(cmake -S . -B /tmp/xyz)
/usr/local/bin/cmake -S . -B /tmp/b
"$CMAKE" -S . -B /tmp/b
sudo cmake --install /tmp/b
env FOO=1 cmake -S . -B /tmp/b
command cmake -S . -B /tmp/b
xcrun cmake -S . -B /tmp/b
time cmake -S . -B /tmp/b
SH
(cd "$work/p18fn" && git add -A) >/dev/null 2>&1
(cd "$work/p18fn" && sh "$S" >/dev/null) || {
  echo "FAIL 18: the documented false negatives must stay documented -- if one now FAILS, the comment"
  echo "         above check 18 (and the SKILL.md row) is out of date:"
  (cd "$work/p18fn" && sh "$S" 2>&1 | grep 'plain cmake'); exit 1; }

# platform: a step's `run:` is not necessarily a STRING -- YAML reads an unquoted `run: true` as a
#           bool, and `(st.get("run") or "").splitlines()` then dies on it, taking the whole gate
#           down with a traceback against a repo whose only sin is an odd-looking step.
mkrepo "$work/p18yaml"
printf '      - run: true\n      - run: 42\n' >> "$work/p18yaml/.github/workflows/release.yml"
(cd "$work/p18yaml" && git add -A) >/dev/null 2>&1
out="$(cd "$work/p18yaml" && sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -qi 'Traceback' && { echo "FAIL 18: a non-string run: must not crash the gate: $out"; exit 1; }
(cd "$work/p18yaml" && sh "$S" >/dev/null) || { echo "FAIL 18: a non-string run: should simply be skipped: $out"; exit 1; }


# platform: shipyard ships no Linux pkg and no Linux shipyard-cmake, so a job that demonstrably runs
#           off macOS must be allowed plain cmake -- requiring it there broke container-tools'
#           ubuntu jobs twice, most recently during the 2026-09-16 cutover. The macOS case must
#           still fail, or the skip would have switched check 18 off altogether.
mkrepo "$work/p18linux"
printf 'name: CI\njobs:\n  iso:\n    runs-on: ubuntu-latest\n    steps:\n      - run: cmake --preset iso\n' \
  > "$work/p18linux/.github/workflows/ci.yml"
(cd "$work/p18linux" && git add -A) >/dev/null 2>&1
(cd "$work/p18linux" && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL 18: a ubuntu-latest job using plain cmake must be allowed"; exit 1; }

mkrepo "$work/p18mac"
printf 'name: CI\njobs:\n  build:\n    runs-on: macos-26\n    steps:\n      - run: cmake --preset cross\n' \
  > "$work/p18mac/.github/workflows/ci.yml"
(cd "$work/p18mac" && git add -A) >/dev/null 2>&1
lim18 "$work/p18mac" "a macos-26 job using plain cmake"

mkrepo "$work/p18expr"
printf 'name: CI\njobs:\n  build:\n    runs-on: ${{ matrix.os }}\n    steps:\n      - run: cmake --preset cross\n' \
  > "$work/p18expr/.github/workflows/ci.yml"
(cd "$work/p18expr" && git add -A) >/dev/null 2>&1
lim18 "$work/p18expr" "an unresolvable runs-on expression (checked, not skipped)"

# spec: scripts/check-family-conventions.sh check 19 -- the baseline above now CALLS the
#       assertion, so this case is built by stripping the two calls out again. That direction
#       is forced: the fixture's whole premise is a repo that satisfies every check, so the
#       compliant state has to be the default and each case turns exactly one thing off.
mkrepo "$work/noassert"
grep -v 'assert-tree-clean' "$work/ok/.github/workflows/release.yml" \
  > "$work/noassert/.github/workflows/release.yml"
(cd "$work/noassert" && git add -A) >/dev/null 2>&1
if (cd "$work/noassert" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a repo whose CI builds but never asserts the tree should fail"; exit 1; fi
(cd "$work/noassert" && sh "$S" 2>&1 | grep -q 'assert-tree-clean') \
  || { echo "FAIL: check 19 should name assert-tree-clean.sh"; exit 1; }

# spec: check 19 greps with comment lines stripped (ci_mentions), so a commented-out call is
#       not a call. Without this case the check would accept a repo that had disabled the
#       assertion and left the line behind as documentation.
mkrepo "$work/assertcomment"
sed 's|^\( *\)- run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|\1# - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|; s|^\( *\)- run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh" --record|\1# - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh" --record|' \
  "$work/ok/.github/workflows/release.yml" > "$work/assertcomment/.github/workflows/release.yml"
(cd "$work/assertcomment" && git add -A) >/dev/null 2>&1
if (cd "$work/assertcomment" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a commented-out assertion call should not satisfy check 19"; exit 1; fi

# spec: scripts/check-family-conventions.sh check 20 -- CMakeUserPresets.json is the
#       per-developer build-location override, because a preset's own `environment` block is
#       applied after the real environment and therefore beats an exported variable. It must be
#       gitignored or it pollutes git status and gets committed by accident.
mkrepo "$work/nouser"
printf '{ "version": 6 }\n' > "$work/nouser/CMakePresets.json"
(cd "$work/nouser" && git add -A) >/dev/null 2>&1
if (cd "$work/nouser" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a preset repo not ignoring CMakeUserPresets.json should fail"; exit 1; fi
(cd "$work/nouser" && sh "$S" 2>&1 | grep -q 'CMakeUserPresets') \
  || { echo "FAIL: check 20 should name CMakeUserPresets.json"; exit 1; }

mkrepo "$work/withuser"
printf '{ "version": 6 }\n' > "$work/withuser/CMakePresets.json"
printf 'CMakeUserPresets.json\n' >> "$work/withuser/.gitignore"
(cd "$work/withuser" && git add -A) >/dev/null 2>&1
(cd "$work/withuser" && sh "$S" >/dev/null) \
  || { echo "FAIL: a preset repo that ignores the override should pass"; exit 1; }

# spec: check 20 keys on a COMMITTED CMakePresets.json. A repo with no presets has no override
#       channel to protect, and the baseline above is exactly that repo -- it passes already,
#       which is what makes the two cases above attributable to the presets file.
mkrepo "$work/untrackedpresets"
printf '{ "version": 6 }\n' > "$work/untrackedpresets/CMakePresets.json"
(cd "$work/untrackedpresets" && sh "$S" >/dev/null) \
  || { echo "FAIL: an UNTRACKED CMakePresets.json is not the committed override channel"; exit 1; }

echo "PASS: check-family-conventions"
