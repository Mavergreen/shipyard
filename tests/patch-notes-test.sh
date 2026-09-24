#!/bin/sh
# platform: host-agnostic
# spec: scripts/patch-notes.sh -- a repackage that adds or changes OUR modifications to the upstream
#       source is a behaviour change, not "packaging changes only": tailscale 1.102.4-mavericks.7
#       added patches/darwin-exit-nodes.patch (exit nodes on macOS) and its notes said otherwise.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/patch-notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/patch-notes-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p patches overlays components/boot2docker/patches release-notes src
printf 'old\n'   > patches/old.patch
printf 'keep\n'  > patches/keep.patch
printf 'a\nb\nc\nd\ne\nf\ng\nh\n' > patches/moveme.patch
printf 'int x;\n' > overlays/systray_darwin.m
printf 'b2d\n'   > components/boot2docker/patches/kernel.config
printf 'prose\n' > release-notes/1.0-mavericks.1.md
printf 'code\n'  > src/main.go
printf 'readme\n' > README.md
git add -A; git commit -qm base; git tag 1.0-mavericks.1

# spec: scripts/patch-notes.sh usage -- nothing changed -> nothing printed, so callers append unconditionally (as ingredient-notes).
out="$(sh "$S" 1.0-mavericks.1)"
[ -z "$out" ] || { echo "FAIL unchanged: expected nothing, got '$out'"; exit 1; }

# spec: scripts/patch-notes.sh usage -- no previous release -> nothing printed.
out="$(sh "$S" "")"
[ -z "$out" ] || { echo "FAIL no-prev: expected nothing, got '$out'"; exit 1; }

# spec: scripts/patch-notes.sh usage -- prose, ordinary source, and README are not our patches.
printf 'more prose\n' >> release-notes/1.0-mavericks.1.md
printf 'more\n' >> src/main.go
printf 'more\n' >> README.md
git commit -qam "not patches"
out="$(sh "$S" 1.0-mavericks.1)"
[ -z "$out" ] || { echo "FAIL non-patch paths: expected nothing, got '$out'"; exit 1; }

# spec: added / changed (a non-.patch file under overlays/ and under a nested patches/) / removed /
#       renamed / a *.diff at any depth, sorted by path, rendered like the ingredient section.
printf 'new\n' > patches/darwin-exit-nodes.patch
printf 'int y;\n' > overlays/systray_darwin.m
printf 'b2d2\n' > components/boot2docker/patches/kernel.config
mkdir -p src/deep; printf 'd\n' > src/deep/fix.diff
git rm -q patches/old.patch
git mv patches/moveme.patch patches/moved.patch
git add -A; git commit -qm "patch changes"
out="$(sh "$S" 1.0-mavericks.1)"
want="$(printf '%s\n' '### Our patches' ''; cat <<'EOF'
Changed since 1.0-mavericks.1:

- Changed `components/boot2docker/patches/kernel.config`
- Changed `overlays/systray_darwin.m`
- Added `patches/darwin-exit-nodes.patch`
- Renamed `patches/moveme.patch` to `patches/moved.patch`
- Removed `patches/old.patch`
- Added `src/deep/fix.diff`
EOF
)"
[ "$out" = "$want" ] || { echo "FAIL patch changes: got:"; printf '%s\n' "$out"; echo "want:"; printf '%s\n' "$want"; exit 1; }

# spec: a path passed as an exclusion (an ingredient pin, already reported by ingredient-notes.sh,
#       possibly in its "path:KEY" form) is not reported twice.
out="$(sh "$S" 1.0-mavericks.1 patches/darwin-exit-nodes.patch overlays/systray_darwin.m:KEY)"
printf '%s\n' "$out" | grep -q 'darwin-exit-nodes' && { echo "FAIL exclude: pin reported twice"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 'systray_darwin' && { echo "FAIL exclude path:KEY: pin reported twice"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 'old.patch' || { echo "FAIL exclude: dropped a non-excluded path"; exit 1; }

# spec: scripts/patch-notes.sh usage -- a baseline git cannot diff against must be fatal, never an empty (= "no changes") answer.
if sh "$S" no-such-tag >/dev/null 2>&1; then echo "FAIL badprev: must fail"; exit 1; fi

echo "PASS: patch-notes"
