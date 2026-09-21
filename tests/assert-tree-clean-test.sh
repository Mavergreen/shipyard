#!/bin/sh
# assert-tree-clean.sh is the family's out-of-tree contract. It must be
# build-system-agnostic: it asks what the tree looks like, never how it was built.
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

# 1. a build that writes NOTHING passes
mkrepo "$work/clean"
(cd "$work/clean" && sh "$S" --record && sh "$S" >/dev/null 2>&1) \
  || say "a build that wrote nothing should pass"

# 2. a build that writes an UNDECLARED file fails, and NAMES it
mkrepo "$work/dirty"
(cd "$work/dirty" && sh "$S" --record) >/dev/null 2>&1
mkdir -p "$work/dirty/build-native"; : > "$work/dirty/build-native/CMakeCache.txt"
if (cd "$work/dirty" && sh "$S" >/dev/null 2>&1); then
  say "an undeclared in-tree write should fail"; fi
(cd "$work/dirty" && sh "$S" 2>&1 | grep -q 'build-native') \
  || say "the failure should name build-native"

# 3. a DECLARED path passes
mkrepo "$work/declared"
printf 'VERSION  # the build stamps the resolved version\n' > "$work/declared/.mavericks-intree"
(cd "$work/declared" && git add .mavericks-intree \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/declared" && sh "$S" --record) >/dev/null 2>&1
printf '1.0.0\n' > "$work/declared/VERSION"
(cd "$work/declared" && sh "$S" >/dev/null 2>&1) \
  || say "a declared in-tree path should pass"

# 4. NO manifest falls back to the STRICTER form, and SAYS so
mkrepo "$work/nomanifest"
mkdir -p "$work/nomanifest/build-native"; : > "$work/nomanifest/build-native/x"
rm -f "$RUNNER_TEMP/mavericks-tree-manifest"
if (cd "$work/nomanifest" && sh "$S" >/dev/null 2>&1); then
  say "with no manifest, an in-tree write should still fail"; fi
(cd "$work/nomanifest" && sh "$S" 2>&1 | grep -qi 'no manifest\|--record') \
  || say "the fallback should say it did not have a manifest"

# 5. a STALE allowlist entry is reported -- an allowlist nobody prunes is how this rots
mkrepo "$work/stale"
printf 'NEVER_WRITTEN  # nothing writes this any more\n' > "$work/stale/.mavericks-intree"
(cd "$work/stale" && git add .mavericks-intree \
   && git -c user.email=t@t -c user.name=t commit -qm allow) >/dev/null 2>&1
(cd "$work/stale" && sh "$S" --record) >/dev/null 2>&1
(cd "$work/stale" && sh "$S" 2>&1 | grep -q 'NEVER_WRITTEN') \
  || say "an allowlist entry nothing wrote should be reported"

[ "$fails" -eq 0 ] && echo "assert-tree-clean: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
