#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/repackage-decision.sh"

out="$(CHANGED='UPSTREAM_VERSION' OWN_UPSTREAM_PATHS='UPSTREAM_VERSION' sh "$S")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL: own-upstream changed is the N=1 auto-cut path's job, should skip the repackage dispatch: $out"; exit 1; }

out="$(CHANGED="$(printf 'components/golang/version\ncomponents/tailscale/version')" OWN_UPSTREAM_PATHS='components/tailscale/version' sh "$S")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL own-upstream-multi: $out"; exit 1; }

out="$(CHANGED='components/golang/version' OWN_UPSTREAM_PATHS='components/tailscale/version' sh "$S")"
[ "$out" = "DISPATCH" ] || { echo "FAIL ingredient/dispatch: $out"; exit 1; }

out="$(CHANGED='components/golang/version' OWN_UPSTREAM_PATHS='' sh "$S")"
[ "$out" = "DISPATCH" ] || { echo "FAIL: an ingredient change with empty own-upstream (e.g. container-tools) should dispatch: $out"; exit 1; }

# spec: SKILL.md "Versioning" -- own-upstream declared as a KEY inside a shared file
#       (pins.env:SWIFT_VERSION) is for a repo that keeps every pin in ONE shell file, where
#       path-level ownership cannot tell the upstream pin from an ingredient pin.
work="$(mktemp -d "${TMPDIR:-/tmp}/repackage-decision-t.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q . && git config user.email t@t && git config user.name t
cat > pins.env <<'EOF'
SWIFT_VERSION="6.3.3"
LLVM_SHA="aaaa"
EOF
git add -A && git commit -qm one
BASE="$(git rev-parse HEAD)"

sed -i.bak 's/LLVM_SHA="aaaa"/LLVM_SHA="bbbb"/' pins.env && rm -f pins.env.bak
git add -A && git commit -qm two
out="$(CHANGED='pins.env' OWN_UPSTREAM_PATHS='pins.env:SWIFT_VERSION' BEFORE="$BASE" sh "$S")"
[ "$out" = "DISPATCH" ] || { echo "FAIL: the ingredient key moved, the upstream key did not -- key-level ingredient should dispatch: $out"; exit 1; }

BASE2="$(git rev-parse HEAD)"
sed -i.bak 's/SWIFT_VERSION="6.3.3"/SWIFT_VERSION="6.4.0"/' pins.env && rm -f pins.env.bak
git add -A && git commit -qm three
out="$(CHANGED='pins.env' OWN_UPSTREAM_PATHS='pins.env:SWIFT_VERSION' BEFORE="$BASE2" sh "$S")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL: the upstream key itself moved, so the repo's own new-upstream path owns it -- key-level upstream should skip: $out"; exit 1; }

out="$(CHANGED='components/x/version' OWN_UPSTREAM_PATHS='pins.env:SWIFT_VERSION' BEFORE="$BASE2" sh "$S")"
[ "$out" = "DISPATCH" ] || { echo "FAIL: a key entry whose FILE did not change at all should dispatch without consulting git: $out"; exit 1; }

if out="$(CHANGED='pins.env' OWN_UPSTREAM_PATHS='pins.env:SWIFT_VERSION' sh "$S" 2>&1)"; then
  echo "FAIL: a key entry with no BEFORE cannot answer the question and must fail loudly -- guessing DISPATCH would double-publish an upstream bump, and guessing SKIP would silently stop every repackage; got: $out"; exit 1
fi
printf '%s\n' "$out" | grep -qi 'BEFORE' || { echo "FAIL should name BEFORE: $out"; exit 1; }

cd /
echo "PASS: repackage-decision"
