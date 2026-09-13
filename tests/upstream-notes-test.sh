#!/bin/sh
set -eu
work="$(mktemp -d "${TMPDIR:-/tmp}/upstream-notes.XXXXXX")"; trap 'rm -rf "$work"' EXIT
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/upstream-notes.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/upstream-notes-t.XXXXXX")"; trap 'rm -rf "$w" "$work"' EXIT
cd "$w"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf 'x\n' > README
git add -A; git commit -qm base
git tag 1.0.0-mavericks.1; git tag 1.0.0-mavericks.2
export MAVERICKS_ROOT="$w"

out="$(sh "$S" 1.1.0-mavericks.1)"
[ -z "$out" ] || { echo "FAIL: no hook (a repo that has not adopted it, or a self-upstream repo) must produce nothing, successfully: got '$out'"; exit 1; }

mkdir -p build
printf '#!/bin/sh\nprintf "https://example.com/releases/v%%s\\n" "$1"\n' > build/upstream-release-notes-url.sh

mkdir -p scripts
printf '#!/bin/sh\nprintf "https://example.com/from-scripts/%%s\\n" "$1"\n' > scripts/upstream-release-notes-url.sh
mv build/upstream-release-notes-url.sh build/hook.keep
out="$(sh "$S" 1.1.0-mavericks.1)"
printf '%s\n' "$out" | grep -qF 'https://example.com/from-scripts/1.1.0' \
  || { echo "FAIL: a repo that keeps its scripts in scripts/ (the swift repos) must find the hook there too: $out"; exit 1; }
mv build/hook.keep build/upstream-release-notes-url.sh
out="$(sh "$S" 1.1.0-mavericks.1)"
printf '%s\n' "$out" | grep -qF 'https://example.com/releases/v1.1.0' || { echo "FAIL build/ should win: $out"; exit 1; }
rm -r scripts

out="$(sh "$S" 1.0.0-mavericks.3)"
[ -z "$out" ] || { echo "FAIL: a repackage of an upstream already shipped must produce nothing: got '$out'"; exit 1; }

out="$(sh "$S" 1.1.0-mavericks.1)"
printf '%s\n' "$out" | grep -qx '### Upstream' || { echo "FAIL header: $out"; exit 1; }
printf '%s\n' "$out" | grep -qxF -- '- [Upstream release notes for 1.1.0](https://example.com/releases/v1.1.0)' \
  || { echo "FAIL: a new upstream must get a section linking upstream's notes for THAT version: $out"; exit 1; }

git tag 1.1.0-mavericks.1
out="$(sh "$S" 1.1.0-mavericks.1)"
printf '%s\n' "$out" | grep -qF 'https://example.com/releases/v1.1.0' \
  || { echo "FAIL: a tag-triggered build's own tag must not be counted as an EARLIER release of the upstream: $out"; exit 1; }
out="$(sh "$S" 1.1.0-mavericks.2)"
[ -z "$out" ] || { echo "FAIL repackage after tag: got '$out'"; exit 1; }

git tag 1.1.0.1-mavericks.1
out="$(sh "$S" 1.1-mavericks.1)"
printf '%s\n' "$out" | grep -qF 'https://example.com/releases/v1.1)' \
  || { echo "FAIL: 1.1.0 must not be mistaken for a repackage of 1.1.0.1 or 11.1.0 -- the glob must match the whole upstream: $out"; exit 1; }

git commit -q --allow-empty -m later     # releases are tagged BEHIND the tip, as in real history
git clone -q --depth 1 "file://$w" "$w/shallow"
[ -z "$(git -C "$w/shallow" tag)" ] || { echo "FAIL fixture: shallow clone carried tags"; exit 1; }
mkdir -p "$w/shallow/build"; cp build/upstream-release-notes-url.sh "$w/shallow/build/"
out="$(MAVERICKS_ROOT="$w/shallow" sh "$S" 1.0.0-mavericks.3 2>"$w/err")"
[ -z "$out" ] || { echo "FAIL: tags a shallow clone cannot see must not read as \"no earlier release\", or it calls every repackage new: $out"; exit 1; }
grep -q 'upstream-notes' "$w/err" || { echo "FAIL shallow not warned"; exit 1; }
mkdir -p "$w/not-a-repo/build"; cp build/upstream-release-notes-url.sh "$w/not-a-repo/build/"
out="$(cd "$w/not-a-repo" && MAVERICKS_ROOT="$w/not-a-repo" GIT_CEILING_DIRECTORIES="$w" \
        sh "$S" 1.0.0-mavericks.3 2>"$w/err")"
[ -z "$out" ] || { echo "FAIL: a git that refuses the repo lists no tags, which must not read as \"no earlier release\" either: $out"; exit 1; }
grep -q 'upstream-notes' "$w/err" || { echo "FAIL unlistable tags not warned"; exit 1; }
rm -rf "$w/shallow" "$w/not-a-repo"

git tag | xargs git tag -d >/dev/null
out="$(sh "$S" 2.0.0-mavericks.1)"
printf '%s\n' "$out" | grep -qF 'https://example.com/releases/v2.0.0' || { echo "FAIL: the first release a repo ever cuts ships a new upstream too: $out"; exit 1; }

printf '#!/bin/sh\necho "upstream changelog unreachable" >&2\nexit 3\n' > build/upstream-release-notes-url.sh
out="$(sh "$S" 3.0.0-mavericks.1 2>"$w/err")" || { echo "FAIL: notes are prose -- a failing hook must warn and drop the section, never fail the release"; exit 1; }
[ -z "$out" ] || { echo "FAIL hook-fail output: $out"; exit 1; }
grep -q 'unreachable' "$w/err" || { echo "FAIL hook's own stderr swallowed"; cat "$w/err"; exit 1; }
grep -q 'upstream-notes' "$w/err" || { echo "FAIL no warning of our own"; cat "$w/err"; exit 1; }

printf '#!/bin/sh\necho "see the website"\n' > build/upstream-release-notes-url.sh
out="$(sh "$S" 3.0.0-mavericks.1 2>"$w/err")"
[ -z "$out" ] || { echo "FAIL: a hook that prints something that is not a single URL must also drop the section: $out"; exit 1; }
grep -q 'upstream-notes' "$w/err" || { echo "FAIL non-url not warned"; exit 1; }
printf '#!/bin/sh\n:\n' > build/upstream-release-notes-url.sh
out="$(sh "$S" 3.0.0-mavericks.1 2>"$w/err")"
[ -z "$out" ] || { echo "FAIL: a hook with empty output must also drop the section: $out"; exit 1; }
grep -q 'upstream-notes' "$w/err" || { echo "FAIL empty not warned"; exit 1; }

# spec: SKILL.md "Release notes" -- signal-desktop's 8.27.0-mavericks.1 shipped a NEW upstream
#       with no link and nothing red, because everything returned 0. --url-only distinguishes
#       "no link is due" from "the link is broken" so a caller that cares can tell them apart.
mk_repo_with_hook() {   # $1 = dir, $2 = hook body
  mkdir -p "$1/build"; ( cd "$1" && git init -q -b main . \
    && git config user.email t@example.com && git config user.name tester \
    && echo x > f && git add f && git commit -qm base )
  printf '%s\n' "$2" > "$1/build/upstream-release-notes-url.sh"
}

u1="$work/u-new"
mk_repo_with_hook "$u1" '#!/bin/sh
printf "https://example.com/notes/%s\n" "$1"'
( cd "$u1" && git tag 1.2.3-mavericks.1 )
out="$(cd "$u1" && MAVERICKS_ROOT="$u1" sh "$S" --url-only 1.2.3-mavericks.1)" && rc=0 || rc=$?
[ "$rc" = 0 ] && [ "$out" = "https://example.com/notes/1.2.3" ] \
  || { echo "FAIL --url-only new upstream: rc=$rc out='$out'"; exit 1; }

( cd "$u1" && git tag 1.2.3-mavericks.2 )
out="$(cd "$u1" && MAVERICKS_ROOT="$u1" sh "$S" --url-only 1.2.3-mavericks.2 2>/dev/null)" && rc=0 || rc=$?
[ "$rc" = 3 ] && [ -z "$out" ] || { echo "FAIL: a repackage (an earlier -mavericks.N of the same upstream exists) must exit 3 with no output: rc=$rc out='$out'"; exit 1; }

u2="$work/u-nohook"
mk_repo_with_hook "$u2" '#!/bin/sh
exit 0'
rm "$u2/build/upstream-release-notes-url.sh"
( cd "$u2" && git tag 1.2.3-mavericks.1 )
( cd "$u2" && MAVERICKS_ROOT="$u2" sh "$S" --url-only 1.2.3-mavericks.1 >/dev/null 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 4 ] || { echo "FAIL: no hook at all must exit 4: rc=$rc"; exit 1; }

u3="$work/u-junk"
mk_repo_with_hook "$u3" '#!/bin/sh
echo not-a-url'
( cd "$u3" && git tag 1.2.3-mavericks.1 )
( cd "$u3" && MAVERICKS_ROOT="$u3" sh "$S" --url-only 1.2.3-mavericks.1 >/dev/null 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 5 ] || { echo "FAIL: a hook that prints junk must exit 5, NOT 0 -- a broken link must be distinguishable from no link: rc=$rc"; exit 1; }

out="$(cd "$u3" && MAVERICKS_ROOT="$u3" sh "$S" 1.2.3-mavericks.1 2>/dev/null)" && rc=0 || rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || { echo "FAIL: the DEFAULT mode is unchanged by --url-only -- section or nothing, always 0: rc=$rc out='$out'"; exit 1; }

# spec: SKILL.md "Release notes" -- a shallow clone hides the tags, so an unknown tag list must
#       NOT read as "no earlier release" (that is exactly how a repackage gets called new, the
#       signal-desktop incident above). --url-only cannot honestly report "no link due" over an
#       unknown tag list and must bail 5; default mode still prints nothing and exits 0 -- both
#       halves of the mode split need to be proven together.
u4="$work/u-shallow-src"
mk_repo_with_hook "$u4" '#!/bin/sh
printf "https://example.com/notes/%s\n" "$1"'
( cd "$u4" && git tag 1.2.3-mavericks.1 && git commit -q --allow-empty -m later )
u4s="$work/u-shallow"
git clone -q --depth 1 "file://$u4" "$u4s"
[ -z "$(git -C "$u4s" tag)" ] || { echo "FAIL fixture: shallow clone carried tags"; exit 1; }
mkdir -p "$u4s/build"; cp "$u4/build/upstream-release-notes-url.sh" "$u4s/build/"

( cd "$u4s" && MAVERICKS_ROOT="$u4s" sh "$S" --url-only 1.2.3-mavericks.1 >/dev/null 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 5 ] || { echo "FAIL --url-only shallow clone: rc=$rc"; exit 1; }

out="$(cd "$u4s" && MAVERICKS_ROOT="$u4s" sh "$S" 1.2.3-mavericks.1 2>/dev/null)" && rc=0 || rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || { echo "FAIL default mode shallow clone changed: rc=$rc out='$out'"; exit 1; }

echo "PASS: upstream-notes"
