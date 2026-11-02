#!/bin/sh
# platform: host-agnostic
#   usage: deviations-test.sh
#          ONE reader for .mavergreen/deviations/<check>/<label>/{scope,reason,revisit}: the artifact
#          checker and the conventions gate must read a declared exception identically, and a
#          deviation without a reason or a revisit trigger is not a declaration.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; S="$here/../scripts/deviations.sh"
. "$here/lib/deviation_tree.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/dev-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
r="$w/r"
fresh() { rm -rf "$r"; mkdir "$r"; }
fail() { echo "FAIL: $1"; exit 1; }
has() { printf '%s\n' "$out" | grep -qx -- "$1" || fail "$2; got: $out"; }
refused() {
  if out="$(sh "$S" "$r" 2>&1)"; then fail "$2 must be refused; got: $out"; fi
  printf '%s\n' "$out" | grep -q -- "$1" || fail "$2: the refusal should say '$1': $out"
  printf '%s\n' "$out" | grep -q '^deviations\.sh: ' || fail "$2: a refusal opens with 'deviations.sh: ': $out"
}

fresh
deviation "$r" version-scheme first-party '*' 'shipyard ports nothing'
deviation "$r" enclosure-url tag-v 'appcast.xml' 'the tag carries a v'
deviation "$r" shipyard-cmake-only bootstrap 'build/legacy.sh' 'runs under the host cmake to bootstrap'
deviation "$r" rosetta gyp 'build/cross.sh' "gyp's host tools are x86_64 and run under Rosetta"
printf '# x\n\n## Conformance deviations\n\n- not-a-deviation: the old grammar is not read\n' > "$r/INGREDIENTS.md"
out="$(sh "$S" "$r")"
has 'version-scheme \* shipyard ports nothing' "a scope of * is unscoped"
has 'enclosure-url appcast.xml the tag carries a v' "a scoped deviation"
has 'shipyard-cmake-only build/legacy.sh runs under the host cmake to bootstrap' "a path-scoped deviation"
has "rosetta build/cross.sh gyp's host tools are x86_64 and run under Rosetta" "rosetta parses like any other check"
printf '%s\n' "$out" | grep -q 'not-a-deviation' && fail "INGREDIENTS.md's ## Conformance deviations is no longer read"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 4 ] || fail "one line per deviation; got: $out"

fresh
printf '# x\n\nNo upstream release notes: upstream keeps none\n' > "$r/INGREDIENTS.md"
out="$(sh "$S" "$r")"
[ -z "$out" ] || fail "INGREDIENTS.md's No upstream release notes line is no longer read: $out"

fresh
[ -z "$(sh "$S" "$r")" ] || fail "no .mavergreen/ is no deviations"
mkdir -p "$r/.mavergreen"
[ -z "$(sh "$S" "$r")" ] || fail "no deviations/ is no deviations"

fresh
deviation "$r" rosetta multi 'build/x.sh' 'first line'
printf 'first line\n  second line\n\nthird\n' > "$r/.mavergreen/deviations/rosetta/multi/reason"
printf 'when x\nis native\n' > "$r/.mavergreen/deviations/rosetta/multi/revisit"
out="$(sh "$S" "$r")"
has 'rosetta build/x.sh first line second line third' "a multi-line reason reads as one line"

fresh
deviation "$r" rosetta crlf 'build/x.sh' 'a reason'
printf 'build/x.sh\r\n' > "$r/.mavergreen/deviations/rosetta/crlf/scope"
printf 'no final newline' > "$r/.mavergreen/deviations/rosetta/crlf/reason"
out="$(sh "$S" "$r")"
has 'rosetta build/x.sh no final newline' "a CRLF scope and a reason without a final newline"

fresh
deviation "$r" rosetta spaced 'build/my tool.sh' 'a path with a space'
deviation "$r" rosetta percent 'build/100%.sh' 'a path with a percent sign'
out="$(sh "$S" "$r")"
has 'rosetta build/100%25.sh a path with a percent sign' "a percent sign in a scope is escaped"
has 'rosetta build/my%20tool.sh a path with a space' "a space in a scope is escaped, so the scope stays one column"

fresh; deviation "$r" rosetta x 'build/x.sh' ''
refused 'no reason' "an empty reason"
fresh; deviation "$r" rosetta x 'build/x.sh' 'r'; rm "$r/.mavergreen/deviations/rosetta/x/reason"
refused 'no reason' "a missing reason"
fresh; deviation "$r" rosetta x 'build/x.sh' 'r' ''
refused 'no revisit' "an empty revisit"
fresh; deviation "$r" rosetta x 'build/x.sh' 'r'; printf '  \n\n' > "$r/.mavergreen/deviations/rosetta/x/revisit"
refused 'no revisit' "a blank revisit"
fresh; deviation "$r" rosetta x 'build/x.sh' 'r'; rm "$r/.mavergreen/deviations/rosetta/x/revisit"
refused 'no revisit' "a missing revisit"
fresh; deviation "$r" rosetta x '' 'r'
refused 'empty scope' "an empty scope"
fresh; deviation "$r" rosetta x 'build/x.sh' 'r'; rm "$r/.mavergreen/deviations/rosetta/x/scope"
refused 'no scope' "a missing scope"
fresh; deviation "$r" rosetta x 'build/x.sh' 'r'; printf 'build/x.sh\nbuild/y.sh\n' > "$r/.mavergreen/deviations/rosetta/x/scope"
refused 'second line' "a scope with a line 2"
for label in Upper -dash under_score 'a b'; do
  fresh; deviation "$r" rosetta "$label" 'build/x.sh' 'r'
  refused 'label' "the label '$label'"
done
fresh; mkdir -p "$r/.mavergreen/deviations/rosetta"; : > "$r/.mavergreen/deviations/rosetta/x"
refused 'not a directory' "a label that is a file"
fresh; mkdir -p "$r/.mavergreen/deviations"; : > "$r/.mavergreen/deviations/rosetta"
refused 'not a directory' "a check that is a file"
fresh; deviation "$r" Rosetta x 'build/x.sh' 'r'
refused 'check id' "a check directory that cannot be a check id"
fresh
deviation "$r" rosetta bad 'build/x.sh' ''
deviation "$r" rosetta good 'build/y.sh' 'a reason'
out="$(sh "$S" "$r" 2>/dev/null)" && fail "one bad deviation fails the run"
[ "$out" = 'rosetta build/y.sh a reason' ] || fail "the good ones still print; got: $out"

# spec: SKILL.md "Acceptance on real 10.9" -- an on-target of scope * stands in for the 10.9
#       acceptance job; one of scope <part> names one gap in the job's coverage and keeps its part,
#       which is how check 29 tells the two apart.
fresh
deviation "$r" on-target job '*' 'no 10.9 acceptance job yet'
deviation "$r" on-target docker-vm 'docker-vm' 'Fusion cannot nest in QEMU'
out="$(sh "$S" "$r")"
has 'on-target \* no 10.9 acceptance job yet' "an on-target of scope * is unscoped"
has 'on-target docker-vm Fusion cannot nest in QEMU' "an on-target part keeps its part"
for part in 'docker-*' 'gui?' 'a[b]'; do
  fresh; deviation "$r" on-target x "$part" 'a glob for a part'
  refused 'one word' "the on-target part $part, a glob,"
done

fresh; deviation "$r" rosetta x 'build/x.sh:FOO' 'runs translated'
refused 'never a :KEY' "a :KEY scope on rosetta"
# spec: SKILL.md "Versioning" -- a self-upstream-exclude of only "*" and "/" would make no change
#       own code.
for scope in '*' '**' '*/**' '/'; do
  fresh; deviation "$r" self-upstream-exclude x "$scope" 'x'
  refused 'self-upstream-exclude' "a self-upstream-exclude of $scope"
done
# spec: SKILL.md "Family conventions" checks 35 and 36 -- packager names one path and macos-runner
#       one <workflow file>:<job>; * or a wildcard would excuse everything, so it is refused.
for scope in '*' 'build/*' 'build/?.sh'; do
  fresh; deviation "$r" packager x "$scope" 'every path'
  refused 'packager' "the packager scope $scope"
done
for scope in '*' 'ci.yml:*' 'ci.yml' 'build' 'ci.yml:' ':build' 'a:b:c'; do
  fresh; deviation "$r" macos-runner x "$scope" 'every job'
  refused 'macos-runner' "the macos-runner scope $scope"
done
fresh
deviation "$r" packager oracle 'build/package.sh' 'oracle; exit when stevedore is it'
deviation "$r" macos-runner build 'ci.yml:build' 'needs macOS; exit when Linux'
out="$(sh "$S" "$r")"
has 'packager build/package.sh oracle; exit when stevedore is it' "a named packager path is a scope"
has 'macos-runner ci.yml:build needs macOS; exit when Linux' "macos-runner scopes <file>:<job>"
# spec: SKILL.md "Family conventions" check 37 -- arm64 and cxxabi name the install paths they
#       cover; * or a glob of nothing but wildcards would declare the whole pkg, so it is refused.
for check in arm64 cxxabi; do
  for scope in '*' '*/*' '**' '?'; do
    fresh; deviation "$r" "$check" x "$scope" 'every path'
    refused "$check" "the $check scope $scope"
  done
done
fresh
deviation "$r" arm64 cmake 'usr/local/mavergreen/cmake/*' 'developers on Apple Silicon run it'
deviation "$r" cxxabi runtime 'usr/local/mavergreen/libcxx22/lib/libc++abi.1.dylib' 'the family runtime'
out="$(sh "$S" "$r")"
has 'arm64 usr/local/mavergreen/cmake/\* developers on Apple Silicon run it' "an install-path glob is an arm64 scope"
has 'cxxabi usr/local/mavergreen/libcxx22/lib/libc++abi.1.dylib the family runtime' "an install path is a cxxabi scope"
echo "PASS: deviations"
