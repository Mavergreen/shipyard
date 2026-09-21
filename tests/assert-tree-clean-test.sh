#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts/assert-tree-clean.sh"
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }

mkrepo() {  # $1 = dir
  mkdir -p "$1"
  (cd "$1" && git init -q && printf 'x\n' > tracked.txt && git add tracked.txt \
     && git -c user.email=t@t -c user.name=t commit -qm init) >/dev/null 2>&1
}

work="$(mktemp -d "${TMPDIR:-/tmp}/atc.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM
export RUNNER_TEMP="$work/rt"; mkdir -p "$RUNNER_TEMP"

mkrepo "$work/clean"
(cd "$work/clean" && sh "$S" --record && sh "$S" >/dev/null 2>&1) \
  || say "a build that wrote nothing should pass"

mkrepo "$work/dirty"
(cd "$work/dirty" && sh "$S" --record) >/dev/null 2>&1
mkdir -p "$work/dirty/build-native"; : > "$work/dirty/build-native/CMakeCache.txt"
if (cd "$work/dirty" && sh "$S" >/dev/null 2>&1); then
  say "an undeclared in-tree write should fail"; fi
(cd "$work/dirty" && sh "$S" 2>&1 | grep -q 'build-native') \
  || say "the failure should name build-native"

mkrepo "$work/declared"
printf 'VERSION  # the build stamps the resolved version\n' > "$work/declared/.mavericks-intree"
(cd "$work/declared" && git add .mavericks-intree \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/declared" && sh "$S" --record) >/dev/null 2>&1
printf '1.0.0\n' > "$work/declared/VERSION"
(cd "$work/declared" && sh "$S" >/dev/null 2>&1) \
  || say "a declared in-tree path should pass"

mkrepo "$work/nomanifest"
mkdir -p "$work/nomanifest/build-native"; : > "$work/nomanifest/build-native/x"
if (cd "$work/nomanifest" && sh "$S" >/dev/null 2>&1); then
  say "with no manifest, an in-tree write should still fail"; fi
(cd "$work/nomanifest" && sh "$S" 2>&1 | grep -qi 'no manifest\|--record') \
  || say "the fallback should say it did not have a manifest"

mkrepo "$work/stale"
printf 'NEVER_WRITTEN  # nothing writes this any more\n' > "$work/stale/.mavericks-intree"
(cd "$work/stale" && git add .mavericks-intree \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/stale" && sh "$S" --record) >/dev/null 2>&1
(cd "$work/stale" && sh "$S" 2>&1 | grep -q 'NEVER_WRITTEN') \
  || say "an allowlist entry nothing wrote should be reported"
(cd "$work/stale" && sh "$S" >/dev/null 2>&1) \
  || say "a stale allowlist entry alone should still exit 0"

mkrepo "$work/prefix"
printf 'VERSION  # the build stamps the resolved version\n' > "$work/prefix/.mavericks-intree"
(cd "$work/prefix" && git add .mavericks-intree \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/prefix" && sh "$S" --record) >/dev/null 2>&1
printf '1.0.0\n' > "$work/prefix/VERSION"
printf 'oops\n' > "$work/prefix/VERSION_HISTORY_DUMP.log"
if (cd "$work/prefix" && sh "$S" >/dev/null 2>&1); then
  say "an undeclared sibling sharing a declared path's prefix should fail"; fi
(cd "$work/prefix" && sh "$S" 2>&1 | grep -q 'VERSION_HISTORY_DUMP.log') \
  || say "the failure should name VERSION_HISTORY_DUMP.log"

mkrepo "$work/masked-untracked"
mkdir -p "$work/masked-untracked/build-native"
: > "$work/masked-untracked/build-native/old.txt"
(cd "$work/masked-untracked" && sh "$S" --record) >/dev/null 2>&1
: > "$work/masked-untracked/build-native/CMakeCache.txt"
if (cd "$work/masked-untracked" && sh "$S" >/dev/null 2>&1); then
  say "an untracked directory present at --record should not hide a later write beneath it"; fi
(cd "$work/masked-untracked" && sh "$S" 2>&1 | grep -q 'build-native/CMakeCache.txt') \
  || say "the failure should name build-native/CMakeCache.txt, not the directory"

mkrepo "$work/masked-ignored"
(cd "$work/masked-ignored" && printf 'build-native/\n' > .gitignore && git add .gitignore \
   && git -c user.email=t@t -c user.name=t commit -qm ignore) >/dev/null 2>&1
mkdir -p "$work/masked-ignored/build-native"
: > "$work/masked-ignored/build-native/old.txt"
(cd "$work/masked-ignored" && sh "$S" --record) >/dev/null 2>&1
: > "$work/masked-ignored/build-native/CMakeCache.txt"
if (cd "$work/masked-ignored" && sh "$S" >/dev/null 2>&1); then
  say "an ignored directory present at --record should not hide a later write beneath it"; fi
(cd "$work/masked-ignored" && sh "$S" 2>&1 | grep -q 'build-native/CMakeCache.txt') \
  || say "the ignored-directory failure should name build-native/CMakeCache.txt"

mkdir -p "$work/notarepo/build-native"
: > "$work/notarepo/build-native/CMakeCache.txt"
if (cd "$work/notarepo" && sh "$S" >/dev/null 2>&1); then
  say "a directory that is not a git checkout should not be certified clean"; fi
(cd "$work/notarepo" && sh "$S" 2>&1 | grep -q 'assert-tree-clean:.*refus') \
  || say "the non-checkout run should say it is refusing"

mkrepo "$work/brokenindex"
printf 'not an index\n' > "$work/brokenindex/.git/index"
if (cd "$work/brokenindex" && sh "$S" >/dev/null 2>&1); then
  say "a git status failure should not be certified clean"; fi
(cd "$work/brokenindex" && sh "$S" 2>&1 | grep -q 'assert-tree-clean:.*refus') \
  || say "the git-failure run should say it is refusing"

mkrepo "$work/leftover"
mkdir -p "$work/leftover/build-native"; : > "$work/leftover/build-native/CMakeCache.txt"
(cd "$work/leftover" && sh "$S" --record) >/dev/null 2>&1
(cd "$work/leftover" && sh "$S" >/dev/null 2>&1) \
  || say "a manifest recorded with the write already present should pass once"
if (cd "$work/leftover" && sh "$S" >/dev/null 2>&1); then
  say "a manifest a successful check consumed should not certify a second run"; fi

mkrepo "$work/keyed-a"
mkrepo "$work/keyed-b"
mkdir -p "$work/keyed-a/build-native"; : > "$work/keyed-a/build-native/CMakeCache.txt"
(cd "$work/keyed-a" && sh "$S" --record) >/dev/null 2>&1
mkdir -p "$work/keyed-b/build-native"; : > "$work/keyed-b/build-native/CMakeCache.txt"
if (cd "$work/keyed-b" && sh "$S" >/dev/null 2>&1); then
  say "one checkout's manifest should not certify another checkout"; fi

mkrepo "$work/untracked-allow"
(cd "$work/untracked-allow" && sh "$S" --record) >/dev/null 2>&1
printf '.mavericks-intree  # self\nbuild/  # mine\n' > "$work/untracked-allow/.mavericks-intree"
mkdir -p "$work/untracked-allow/build"; : > "$work/untracked-allow/build/CMakeCache.txt"
if (cd "$work/untracked-allow" && sh "$S" >/dev/null 2>&1); then
  say "an uncommitted .mavericks-intree should not be honoured"; fi
(cd "$work/untracked-allow" && sh "$S" 2>&1 | grep -q 'build/CMakeCache.txt') \
  || say "the uncommitted-allowlist failure should name build/CMakeCache.txt"
(cd "$work/untracked-allow" && sh "$S" 2>&1 | grep -q 'not tracked by git') \
  || say "an uncommitted .mavericks-intree should be reported as untracked"

mkrepo "$work/dirallow"
mkdir -p "$work/dirallow/dist"; : > "$work/dirallow/dist/.gitkeep"
printf 'dist/  # the build stages the package here\n' > "$work/dirallow/.mavericks-intree"
(cd "$work/dirallow" && git add .mavericks-intree dist/.gitkeep \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/dirallow" && sh "$S" --record) >/dev/null 2>&1
: > "$work/dirallow/dist/thing.pkg"
(cd "$work/dirallow" && sh "$S" >/dev/null 2>&1) \
  || say "a declared directory should cover what the build writes inside it"

mkrepo "$work/noslash"
mkdir -p "$work/noslash/dist"; : > "$work/noslash/dist/.gitkeep"
printf 'dist  # missing the trailing slash\n' > "$work/noslash/.mavericks-intree"
(cd "$work/noslash" && git add .mavericks-intree dist/.gitkeep \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/noslash" && sh "$S" --record) >/dev/null 2>&1
: > "$work/noslash/dist/thing.pkg"
(cd "$work/noslash" && sh "$S" 2>&1 | grep -q 'trailing slash') \
  || say "a directory declared without a trailing slash should be called out"

# platform: this host's en_US.UTF-8 collates ASCII exactly like C, so nothing run
#           here can distinguish a pinned comm from an unpinned one -- the orderings only
#           diverge on a glibc runner. Pin the invocation, which is what a mutation reaches.
pinned=0
grep -q 'LC_ALL=C sort' "$S" || pinned=1
grep -q 'LC_ALL=C comm' "$S" || pinned=1
[ "$pinned" -eq 0 ] \
  || say "the snapshot sort and the manifest comm must both be pinned to LC_ALL=C"

mkrepo "$work/deleted"
(cd "$work/deleted" && sh "$S" --record) >/dev/null 2>&1
rm "$work/deleted/tracked.txt"
if (cd "$work/deleted" && sh "$S" >/dev/null 2>&1); then
  say "a deleted tracked file should still fail"; fi
(cd "$work/deleted" && sh "$S" 2>&1 | grep -q 'tracked.txt') \
  || say "the deletion should name tracked.txt"
if (cd "$work/deleted" && sh "$S" 2>&1 | grep -q 'wrote into the source tree: tracked.txt'); then
  say "a deleted file should not be reported as something the build wrote"; fi

mkrepo "$work/renamed"
(cd "$work/renamed" && printf 'y\n' > longfilename.txt && git add longfilename.txt \
   && git -c user.email=t@t -c user.name=t commit -qm add) >/dev/null 2>&1
(cd "$work/renamed" && sh "$S" --record) >/dev/null 2>&1
(cd "$work/renamed" && git mv longfilename.txt renamed.txt) >/dev/null 2>&1
if (cd "$work/renamed" && sh "$S" >/dev/null 2>&1); then
  say "a renamed tracked file should still fail"; fi
if (cd "$work/renamed" && sh "$S" 2>&1 | grep -q ': gfilename.txt$'); then
  say "a rename should not report a truncated old path"; fi
(cd "$work/renamed" && sh "$S" 2>&1 | grep -q ': longfilename.txt$') \
  || say "a rename should name the old path in full"
(cd "$work/renamed" && sh "$S" 2>&1 | grep -q ': renamed.txt$') \
  || say "a rename should name the new path too"

mkrepo "$work/newline"
(cd "$work/newline" && sh "$S" --record) >/dev/null 2>&1
: > "$work/newline/$(printf 'we\nird')"
if (cd "$work/newline" && sh "$S" >/dev/null 2>&1); then
  say "a path containing a newline should still fail"; fi
if (cd "$work/newline" && sh "$S" 2>&1 | grep -q ': we$'); then
  say "a path containing a newline should not be reported truncated to its first line"; fi
(cd "$work/newline" && sh "$S" 2>&1 | grep -q 'we\\nird') \
  || say "a path containing a newline should be reported whole, with the newline escaped"

[ "$fails" -eq 0 ] && echo "assert-tree-clean: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
