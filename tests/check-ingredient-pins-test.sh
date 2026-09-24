#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-ingredient-pins.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-ingredient-pin.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github/workflows components/golang components/tailscale
printf '1.26.5-mavericks.1\n' > components/golang/version
printf 'REF=v1.102.0\n'       > components/tailscale/version
git add -A; git commit -qm base

sh "$S" >/dev/null || { echo "FAIL: no caller (legacysupport has no ingredients) should pass trivially"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    paths: ['components/**']
jobs:
  repackage:
    with:
      own-upstream-paths: components/tailscale/version
YML
sh "$S" >/dev/null || { echo "FAIL sound declaration should pass"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    paths: ['componentz/**']
jobs:
  repackage:
    with:
      own-upstream-paths: ""
YML
if sh "$S" >/dev/null 2>&1; then echo "FAIL: a glob matching nothing must fail loudly, or a typo would thin the notes silently -- empty expansion should fail"; exit 1; fi

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    paths: ['components/tailscale/version']
jobs:
  repackage:
    with:
      own-upstream-paths: components/tailscale/version
YML
if sh "$S" >/dev/null 2>&1; then echo "FAIL: every watched path being own-upstream leaves nothing to describe -- all-excluded should fail"; exit 1; fi

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    paths: ['components/**', 'untracked.txt']
jobs:
  repackage:
    with:
      own-upstream-paths: ""
YML
printf 'x\n' > untracked.txt
sh "$S" >/dev/null || { echo "FAIL: an untracked file never enters the list, since expansion is over tracked files -- untracked-but-unmatched should still pass"; exit 1; }

printf 'SWIFT_VERSION=6.3.3\nOTHER_PIN=x\n' > pins.env
git add pins.env; git commit -qm "add pins.env"
cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    paths: ['pins.env']
jobs:
  repackage:
    with:
      own-upstream-paths: pins.env:SWIFT_VERSION
YML
sh "$S" >/dev/null || { echo "FAIL: the swift-repo own-upstream form (path:KEY) must not be tested as a git path with the key still attached, since pins.env:SWIFT_VERSION is never a tracked file, only pins.env is -- path:KEY own-upstream form should pass"; exit 1; }

echo "PASS: check-ingredient-pins"
