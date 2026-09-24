#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-shell-portability.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/shell-portability.XXXXXX")"; trap 'rm -rf "$work"' EXIT

mkrepo() {  # $1 = dir
  mkdir -p "$1"
  (cd "$1" && git init -q)
}

mkrepo "$work/ok"
printf '#!/bin/sh\nd="$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")"\nt="$(mktemp -d -t pfx)"\n' > "$work/ok/a.sh"
(cd "$work/ok" && git add -A) >/dev/null 2>&1
(cd "$work/ok" && sh "$S" >/dev/null) || { echo "FAIL legal mktemp forms should pass"; exit 1; }

mkrepo "$work/v"
printf '#!/bin/sh\ngit tag --list | sort -V | tail -1\n' > "$work/v/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/v" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/v" && sh "$S" 2>&1)"; then echo "FAIL sort -V should fail"; exit 1; fi  # portability-ok: names the construct under test
printf '%s\n' "$out" | grep -q 'a.sh:2' || { echo "FAIL should name file:line: $out"; exit 1; }
printf '%s\n' "$out" | grep -qi 'ver_cmp' || { echo "FAIL should say what to use instead: $out"; exit 1; }

mkrepo "$work/v2"
printf '#!/bin/sh\nprintf x | sort --version-sort\n' > "$work/v2/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/v2" && git add -A) >/dev/null 2>&1
if (cd "$work/v2" && sh "$S" >/dev/null 2>&1); then echo "FAIL: sort -V's long-form spelling (--version-sort) should also fail"; exit 1; fi  # portability-ok: names the construct under test

mkrepo "$work/m"
printf '#!/bin/sh\nw="$(mktemp -d)"\nl="$(mktemp)"\n' > "$work/m/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/m" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/m" && sh "$S" 2>&1)"; then echo "FAIL bare mktemp should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'a.sh:2' || { echo "FAIL should catch mktemp -d: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'a.sh:3' || { echo "FAIL should catch bare mktemp: $out"; exit 1; }

mkrepo "$work/c"
printf '#!/bin/sh\n# never use sort -V here; and not $(mktemp -d) either\necho ok\n' > "$work/c/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/c" && git add -A) >/dev/null 2>&1
(cd "$work/c" && sh "$S" >/dev/null) || { echo "FAIL: prose ABOUT a ban is not a violation, or the docs could not explain the rule -- full-line comments should not trip the lint"; exit 1; }

mkrepo "$work/b"
printf '#!/bin/sh\necho ok\n' > "$work/b/a.sh"
printf 'setup() {\n  TMP="$(mktemp -d)"\n}\n' > "$work/b/tests.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/b" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/b" && sh "$S" 2>&1)"; then echo "FAIL: .bats files are shell too -- the first cut of this lint scanned only *.sh, so it called ed25519 clean while tests/version.bats was dying on a bare mktemp in setup(); a .bats violation should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'tests.bats:2' || { echo "FAIL should name the .bats file:line: $out"; exit 1; }

mkrepo "$work/u"
printf '#!/bin/sh\necho ok\n' > "$work/u/a.sh"
(cd "$work/u" && git add -A) >/dev/null 2>&1
printf '#!/bin/sh\nsort -V\n' > "$work/u/vendored.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/u" && sh "$S" >/dev/null) || { echo "FAIL: UNTRACKED files are out of scope, since vendored/fetched upstream trees are not ours to rewrite"; exit 1; }

# spec: SKILL.md "Running a repo's tests" -- an assertion must be able to fail on 10.9 too;
#       check-shell-portability.sh bans the bare forms because it found them all green there
#       whatever the code did (seventeen in shipyard, fourteen in ed25519).
mkrepo "$work/a"
printf '@test "t" {\n  run x\n  [[ "$output" == *y* ]]\n  [ "$status" -eq 0 ]\n}\n' > "$work/a/t.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/a" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/a" && sh "$S" 2>&1)"; then echo "FAIL a bare [[ ]] assertion should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 't.bats:3' || { echo "FAIL should name the bare [[ ]] line: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '|| false' || { echo "FAIL should say to end it || false: $out"; exit 1; }

mkrepo "$work/a2"
printf '@test "t" {\n  for i in 1 2; do [[ $i == 1 ]]; done\n  true\n}\n' > "$work/a2/t.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/a2" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/a2" && sh "$S" 2>&1)"; then echo "FAIL: an unfailable [[ ]] must be caught as the body of a one-line loop too"; exit 1; fi
printf '%s\n' "$out" | grep -q 't.bats:2' || { echo "FAIL should name the loop line: $out"; exit 1; }

mkrepo "$work/n"
printf '@test "t" {\n  ! echo "$output" | grep -q y\n  true\n}\n' > "$work/n/t.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/n" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/n" && sh "$S" 2>&1)"; then echo "FAIL a bare ! command should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 't.bats:2' || { echo "FAIL should name the ! line: $out"; exit 1; }

mkrepo "$work/a3"
printf '@test "t" {\n  [[ "$output" == *y* ]] || false\n  if [[ -n "$x" ]]; then true; fi\n  ! grep -q x f || { echo no; exit 1; }\n  ! grep x f \\\n      | grep -q y || return 1\n  run ! false\n  for i in 1; do [[ $i == 1 ]] || false; done\n}\n' > "$work/a3/t.bats"
(cd "$work/a3" && git add -A) >/dev/null 2>&1
(cd "$work/a3" && sh "$S" >/dev/null) || { echo "FAIL: the forms that DO fail a test (|| false, a condition, ! ... || fail, run !) must pass the lint"; exit 1; }

sed 's/^sort\[\[:space:\]\]/sortXX[[:space:]]/' "$S" > "$work/dead.sh"
if out="$(cd "$work/ok" && sh "$work/dead.sh" 2>&1)"; then echo "FAIL: a rule that no longer matches its own sample is DEAD and must say so rather than pass"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'lint is dead' || { echo "FAIL should say the lint is dead: $out"; exit 1; }

(cd "$here/.." && sh "$S" >/dev/null) || { echo "FAIL shipyard's own scripts must be clean"; exit 1; }

echo "PASS: shell-portability"
