#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

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
first_is "$out" comments || { echo "FAIL should be a comments failure: $out"; exit 1; }
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
first_is "$out" comments || { echo "FAIL should be a comments failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'DECLARED DEVIATION' \
  && { echo "FAIL: a scoped deviation must not also be announced as accepted: $out"; exit 1; }
# spec: SKILL.md "Family conventions" check 16 -- nothing tracked reads the CMake user package
#       registry, because nothing writes it any more.
mkrepo "$work/r16"; printf '#!/bin/sh\ncat "$HOME/.cmake/packages/MavericksShipyard/"*\n' > "$work/r16/build/x.sh"
(cd "$work/r16" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/r16" && sh "$S" 2>&1)"; then echo "FAIL 16: a registry read should fail"; exit 1; fi
first_is "$out" registry-read || { echo "FAIL should be a registry-read failure: $out"; exit 1; }
printf '\n- registry-read:build/x.sh: a shim that leaves with the flag day\n' >> "$work/r16/INGREDIENTS.md"
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
if out="$(cd "$work/m17" && sh "$S" 2>&1)"; then echo "FAIL 17: a drifted msc.sh should fail"; exit 1; fi
first_is "$out" msc-template || { echo "FAIL should be a msc-template failure: $out"; exit 1; }
printf '\n- msc-template:build/msc.sh: exercising the deviation path\n' >> "$work/m17/INGREDIENTS.md"
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
for g in "$here"/../scripts/*.sh "$here"/../scripts/check-ids.tsv; do cp "$g" "$fake/"; done
cp -R "$here/../scripts/lib" "$here/../scripts/vendor" "$fake/"
mkdir -p "$fake/templates"   # ...but no msc.sh in it
out="$(cd "$work/m17t" && sh "$fake/check-family-conventions.sh" 2>&1 || true)"
first_is "$out" msc-template || { echo "FAIL should be a msc-template failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'is not shipyard' \
  && { echo "FAIL 17: a missing template must NOT be reported as the repo's msc.sh being wrong"; exit 1; }

# spec: SKILL.md "Family conventions" check 18 -- configure, test and package with
#       shipyard-cmake/ctest/cpack, in workflows and in committed build scripts.
mkrepo "$work/p18"; printf '      - run: cmake -S . -B "$RUNNER_TEMP/b"\n' >> "$work/p18/.github/workflows/release.yml"
(cd "$work/p18" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/p18" && sh "$S" 2>&1)"; then echo "FAIL 18: plain cmake in a workflow should fail"; exit 1; fi
first_is "$out" shipyard-cmake-only || { echo "FAIL should be a shipyard-cmake-only failure: $out"; exit 1; }
mkrepo "$work/p18b"; printf '#!/bin/sh\ncd x && ctest --test-dir b\n' > "$work/p18b/build/t.sh"
(cd "$work/p18b" && git add -A) >/dev/null 2>&1
if (cd "$work/p18b" && sh "$S" >/dev/null 2>&1); then echo "FAIL 18: plain ctest in a build script should fail"; exit 1; fi
mkrepo "$work/p18ok"; printf '      - run: shipyard-cmake -S . -B "$RUNNER_TEMP/b"   # not plain cmake\n' >> "$work/p18ok/.github/workflows/release.yml"
printf '#!/bin/sh\n# cmake -S would be wrong here, but this is a comment\n' > "$work/p18ok/build/c.sh"
(cd "$work/p18ok" && git add -A) >/dev/null 2>&1
(cd "$work/p18ok" && sh "$S" >/dev/null) || { echo "FAIL 18: shipyard-cmake and comments should pass"; exit 1; }
printf '\n- shipyard-cmake-only:build/t.sh: exercising the deviation path\n' >> "$work/p18b/INGREDIENTS.md"
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
  echo "FAIL 18: non-invocation shapes should pass:"; (cd "$work/p18ok2" && sh "$S" 2>&1 | grep '^shipyard-cmake-only'); exit 1; }

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

# spec: SKILL.md "Check 18" -- indentation is not command position: a tab-indented call is still a
#       call, and a tab-indented comment is still a comment. Pinned so the single-pass line filter
#       cannot drift from reading `^[[:space:]]*` the way the shell-per-line filter did.
mkrepo "$work/p18tab"
printf '#!/bin/sh\nif true; then\n\tcmake -S . -B b\nfi\n' > "$work/p18tab/build/x.sh"
(cd "$work/p18tab" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/p18tab" && sh "$S" 2>&1)"; then echo "FAIL 18: a tab-indented call should fail"; exit 1; fi
has_id "$out" shipyard-cmake-only || { echo "FAIL 18: a tab-indented call should be a shipyard-cmake-only failure: $out"; exit 1; }
mkrepo "$work/p18tabc"
printf '#!/bin/sh\n\t# cmake -S . -B b\nexit 0\n' > "$work/p18tabc/build/x.sh"
(cd "$work/p18tabc" && git add -A) >/dev/null 2>&1
(cd "$work/p18tabc" && sh "$S" >/dev/null) || { echo "FAIL 18: a tab-indented comment should pass"; exit 1; }

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
  out="$(cd "$1" && sh "$S" 2>&1 || true)"
  has_id "$out" shipyard-cmake-only \
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
  (cd "$work/p18fn" && sh "$S" 2>&1 | grep '^shipyard-cmake-only'); exit 1; }

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

# platform: check 18 reads its candidate lines through awk, and a failing awk must fail the gate
#           and say so -- an empty hit list would read as "no plain cmake anywhere". The stub awk
#           goes first on PATH and fails only the -F call check 18 makes (the gate's other awk
#           calls must still work, or it would die earlier, in a different check); any other call
#           runs the real awk, found by absolute path before PATH is changed.
mkdir -p "$work/badawk"
printf '#!/bin/sh\ncase "${1:-}" in -F*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v awk)" > "$work/badawk/awk"
chmod +x "$work/badawk/awk"
mkrepo "$work/p18awk"
(cd "$work/p18awk" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/p18awk" && PATH="$work/badawk:$PATH" sh "$S" 2>&1)"; then
  echo "FAIL 18: an awk that fails must fail the gate, not pass as 'no hits'"; exit 1; fi
has_id "$out" shipyard-cmake-only \
  || { echo "FAIL 18: a failing awk must be named as check 18's: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh check 19 -- the baseline (tests/lib/conventions_fixture.sh) now CALLS the
#       assertion, so this case is built by stripping the two calls out again. That direction
#       is forced: the fixture's whole premise is a repo that satisfies every check, so the
#       compliant state has to be the default and each case turns exactly one thing off.
mkrepo "$work/noassert"
grep -v 'assert-tree-clean' "$work/ok/.github/workflows/release.yml" \
  > "$work/noassert/.github/workflows/release.yml"
(cd "$work/noassert" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/noassert" && sh "$S" 2>&1)"; then
  echo "FAIL: a repo whose CI builds but never asserts the tree should fail"; exit 1; fi
first_is "$out" tree-clean-wired || { echo "FAIL: check 19 should be a tree-clean-wired failure: $out"; exit 1; }

# spec: check 19 greps with comment lines stripped (ci_mentions), so a commented-out call is
#       not a call. Without this case the check would accept a repo that had disabled the
#       assertion and left the line behind as documentation.
mkrepo "$work/assertcomment"
sed 's|^\( *\)- run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|\1# - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|; s|^\( *\)- run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh" --record|\1# - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh" --record|' \
  "$work/ok/.github/workflows/release.yml" > "$work/assertcomment/.github/workflows/release.yml"
(cd "$work/assertcomment" && git add -A) >/dev/null 2>&1
if (cd "$work/assertcomment" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a commented-out assertion call should not satisfy check 19"; exit 1; fi

# spec: scripts/check-family-conventions.sh check 19 -- --record returns 0 unconditionally, so a
#       repo that calls only that half has adopted the half of the contract that can never fail.
#       This is the one failure mode unique to check 19, and a substring match for the script name
#       cannot see it.
mkrepo "$work/recordonly"
grep -v 'assert-tree-clean\.sh"$' "$work/ok/.github/workflows/release.yml" \
  > "$work/recordonly/.github/workflows/release.yml"
(cd "$work/recordonly" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/recordonly" && sh "$S" 2>&1)"; then
  echo "FAIL: a repo that calls only --record should not satisfy check 19"; exit 1; fi
first_is "$out" tree-clean-wired || { echo "FAIL: the --record-only case should be a tree-clean-wired failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh check 19 -- the other half. With no recording the bare
#       call falls back to "every untracked or ignored path counts", which is a different and
#       stricter assertion than the one this convention describes.
mkrepo "$work/bareonly"
grep -v -e 'assert-tree-clean\.sh" --record' "$work/ok/.github/workflows/release.yml" \
  > "$work/bareonly/.github/workflows/release.yml"
(cd "$work/bareonly" && git add -A) >/dev/null 2>&1
if (cd "$work/bareonly" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a repo that never records the tree should not satisfy check 19"; exit 1; fi

# spec: scripts/check-family-conventions.sh check 19 -- a step NAME is not a call. ci_mentions
#       strips whole-line comments only, so before check 19 required the call shape a workflow
#       that merely spelled the script name in its step titles passed.
mkrepo "$work/assertname"
sed 's|- run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|- name: assert-tree-clean.sh|' \
  "$work/ok/.github/workflows/release.yml" > "$work/assertname/.github/workflows/release.yml"
(cd "$work/assertname" && git add -A) >/dev/null 2>&1
if (cd "$work/assertname" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a step name mentioning the script should not satisfy check 19"; exit 1; fi

# spec: scripts/check-family-conventions.sh check 19 -- a TRAILING comment is not a call either,
#       and ci_mentions cannot strip one without guessing where a YAML run: line's shell quoting
#       ends. Requiring the call shape makes the guess unnecessary.
mkrepo "$work/asserttrailing"
sed 's|- run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|- run: make all   # we should add assert-tree-clean.sh|' \
  "$work/ok/.github/workflows/release.yml" > "$work/asserttrailing/.github/workflows/release.yml"
(cd "$work/asserttrailing" && git add -A) >/dev/null 2>&1
if (cd "$work/asserttrailing" && sh "$S" >/dev/null 2>&1); then
  echo "FAIL: a trailing comment mentioning the script should not satisfy check 19"; exit 1; fi

# spec: scripts/check-family-conventions.sh check 19 -- shipyard's own workflows call the script
#       by repo-relative path, with no quotes and no $SHIPYARD_SCRIPTS, because in shipyard the
#       scripts ARE the repo. Both spellings are in use across the family and both must pass.
mkrepo "$work/assertunquoted"
sed 's|sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"|sh scripts/assert-tree-clean.sh|' \
  "$work/ok/.github/workflows/release.yml" > "$work/assertunquoted/.github/workflows/release.yml"
(cd "$work/assertunquoted" && git add -A) >/dev/null 2>&1
(cd "$work/assertunquoted" && sh "$S" >/dev/null) \
  || { echo "FAIL: the unquoted repo-relative spelling should satisfy check 19"; exit 1; }

# spec: scripts/check-family-conventions.sh check 20 -- CMakeUserPresets.json is the
#       per-developer build-location override, because a preset's own `environment` block is
#       applied after the real environment and therefore beats an exported variable. It must be
#       gitignored or it pollutes git status and gets committed by accident.
mkrepo "$work/nouser"
printf '{ "version": 6 }\n' > "$work/nouser/CMakePresets.json"
(cd "$work/nouser" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/nouser" && sh "$S" 2>&1)"; then
  echo "FAIL: a preset repo not ignoring CMakeUserPresets.json should fail"; exit 1; fi
first_is "$out" user-presets-ignored || { echo "FAIL: check 20 should be a user-presets-ignored failure: $out"; exit 1; }

mkrepo "$work/withuser"
printf '{ "version": 6 }\n' > "$work/withuser/CMakePresets.json"
printf 'CMakeUserPresets.json\n' >> "$work/withuser/.gitignore"
(cd "$work/withuser" && git add -A) >/dev/null 2>&1
(cd "$work/withuser" && sh "$S" >/dev/null) \
  || { echo "FAIL: a preset repo that ignores the override should pass"; exit 1; }

# spec: check 20 keys on a COMMITTED CMakePresets.json. A repo with no presets has no override
#       channel to protect, and the baseline (tests/lib/conventions_fixture.sh) is exactly that repo -- it passes already,
#       which is what makes the two cases above attributable to the presets file.
mkrepo "$work/untrackedpresets"
printf '{ "version": 6 }\n' > "$work/untrackedpresets/CMakePresets.json"
(cd "$work/untrackedpresets" && sh "$S" >/dev/null) \
  || { echo "FAIL: an UNTRACKED CMakePresets.json is not the committed override channel"; exit 1; }

# spec: SKILL.md "Family conventions" check 21 -- a repo that builds a .pkg must run artifact
#       conformance, or the identity and install-path rules never see its payload.
mkrepo "$work/pk"; printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg\n' > "$work/pk/build/package.sh"
(cd "$work/pk" && git add -A) >/dev/null 2>&1
out="$(cd "$work/pk" && sh "$S" 2>&1)" && { echo "FAIL: a repo that runs pkgbuild without artifact conformance should fail"; exit 1; }
first_is "$out" artifact-checks-wired || { echo "FAIL should be a artifact-checks-wired failure: $out"; exit 1; }
printf '      - run: sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" dist "$FULL" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"\n' >> "$work/pk/.github/workflows/release.yml"
(cd "$work/pk" && git add -A) >/dev/null 2>&1
out="$(cd "$work/pk" && sh "$S" 2>&1)" && { echo "FAIL: the retired artifact-facts pipeline is not shipyard-check --dist and should still fail"; exit 1; }
first_is "$out" artifact-checks-wired || { echo "FAIL: the retired pipeline should be an artifact-checks-wired failure: $out"; exit 1; }
printf '      - run: SHIPYARD_CHECK_VERSION="$FULL" shipyard-check --dist dist\n' >> "$work/pk/.github/workflows/release.yml"
(cd "$work/pk" && git add -A) >/dev/null 2>&1

# spec: SKILL.md "Family conventions" check 23 -- a pkg-building repo gets its install scripts and
#       manifest from stage_product.sh, or the layout conformance enforces has no one generating it.
#       Running conformance satisfies check 21 but not check 23, which needs the call itself.
out="$(cd "$work/pk" && sh "$S" 2>&1)" && { echo "FAIL: a pkg repo that never calls stage_product.sh should fail check 23"; exit 1; }
has_id "$out" artifact-checks-wired && { echo "FAIL: a pkg repo that runs artifact conformance should no longer fail check 21: $out"; exit 1; }
first_is "$out" stage-product || { echo "FAIL: check 23 should be a stage-product failure: $out"; exit 1; }
printf 'sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr\n' >> "$work/pk/build/package.sh"
(cd "$work/pk" && git add -A && sh "$S" >/dev/null 2>&1) || { echo "FAIL: a pkg repo that calls stage_product.sh should pass: $(cd "$work/pk" && sh "$S" 2>&1)"; exit 1; }

# spec: scripts/check-family-conventions.sh check 23 -- matches a CALL shape ANCHORED to command
#       position (check 18's anchor set: line start, ; & | a backtick, "$(", then/do/exec, plus
#       YAML "run:" and CMake "COMMAND"), not a bare mention -- the same distinction check 19 pins
#       for assert-tree-clean.sh (assertname, asserttrailing above). A step name, an echo'd string
#       whose payload merely spells "sh stage_product.sh" or a path to it, and a trailing comment
#       all put "stage_product.sh" textually next to "/" or "sh " with no COMMAND-POSITION anchor
#       in front of it, so none of them is a call.
mkrepo "$work/pkm"
printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg   # sh stage_product.sh\necho "sh stage_product.sh"\necho "use $SHIPYARD_SCRIPTS/stage_product.sh --stage x"\n' \
  > "$work/pkm/build/package.sh"
printf '      - name: stage_product.sh already ran earlier\n        run: echo done\n' >> "$work/pkm/.github/workflows/release.yml"
printf '      - run: SHIPYARD_CHECK_VERSION="$FULL" shipyard-check --dist dist\n' >> "$work/pkm/.github/workflows/release.yml"
out="$(cd "$work/pkm" && git add -A && sh "$S" 2>&1)" && { echo "FAIL: a step name, an echo'd mention, or a trailing comment naming stage_product.sh must not satisfy check 23: $out"; exit 1; }
first_is "$out" stage-product || { echo "FAIL should be a stage-product failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh check 23 -- a call inside a YAML "run: |" block scalar
#       is still a call: its continuation lines are their own physical lines, indented but
#       otherwise ordinary shell, so the plain line-start anchor covers them with no special case.
mkrepo "$work/pkblock"; printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg\n' > "$work/pkblock/build/package.sh"
printf '      - run: |\n          SHIPYARD_CHECK_VERSION="$FULL" shipyard-check --dist dist\n          sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr\n' \
  >> "$work/pkblock/.github/workflows/release.yml"
(cd "$work/pkblock" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: a stage_product.sh call inside a YAML run: | block should satisfy check 23: $(cd "$work/pkblock" && sh "$S" 2>&1)"; exit 1; }

# spec: scripts/check-family-conventions.sh check 23 -- CMake's own command position is the
#       COMMAND keyword inside execute_process()/add_custom_command(), the same anchor check 18
#       does not need because check 18 only ever scans *.sh files and extracted YAML run: lines.
mkrepo "$work/pkcmake"; printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg\n' > "$work/pkcmake/build/package.sh"
printf '      - run: SHIPYARD_CHECK_VERSION="$FULL" shipyard-check --dist dist\n' >> "$work/pkcmake/.github/workflows/release.yml"
printf 'execute_process(COMMAND sh ${SHIPYARD_SCRIPTS}/stage_product.sh --stage stage --product w --name W --version 1 --scripts-out scr)\n' > "$work/pkcmake/CMakeLists.txt"
(cd "$work/pkcmake" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: a stage_product.sh call via CMake's COMMAND keyword should satisfy check 23: $(cd "$work/pkcmake" && sh "$S" 2>&1)"; exit 1; }

echo "PASS: check-family-conventions-3"
