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
rm -f "$RUNNER_TEMP/mavericks-tree-manifest"
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

[ "$fails" -eq 0 ] && echo "assert-tree-clean: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
