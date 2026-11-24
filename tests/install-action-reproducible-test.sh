#!/bin/sh
# platform: host-agnostic
#   usage: install-action-reproducible-test.sh
#          install@v1 exports ZERO_AR_DATE=1 and, unless it is already set, SOURCE_DATE_EPOCH, the
#          committer time of $GITHUB_WORKSPACE's HEAD, on every OS. A workspace that is not a checkout
#          yet gets a notice and no SOURCE_DATE_EPOCH. Runs the step itself. Exit 0 clean, 1 on failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/install-reproducible.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: install-action-reproducible: $1"; exit 1; }
python3 - "$root/.github/actions/install/action.yml" "$w/step" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
r = [s for s in steps if s.get("name") == "Reproducible defaults"]
if len(r) != 1:
    print("FAIL: install-action-reproducible: expected one step named Reproducible defaults, got %d" % len(r)); sys.exit(1)
if r[0].get("if"):
    print("FAIL: install-action-reproducible: the step runs on every OS, so it has no if: %r" % r[0]["if"]); sys.exit(1)
open(sys.argv[2], "w").write(r[0].get("run") or "")
PY
mkdir -p "$w/ws"
( cd "$w/ws" && git init -q . && git config user.email t@e.com && git config user.name t \
  && printf 'x\n' > f && git add f && GIT_COMMITTER_DATE='1700000123 +0000' git commit -qm c )
run() {  # $1 = workspace; SOURCE_DATE_EPOCH from the caller's environment
  : > "$w/env"
  ( cd "$1" && env GITHUB_ACTION_PATH="$root/.github/actions/install" GITHUB_ENV="$w/env" GITHUB_WORKSPACE="$1" \
      bash "$w/step" ) > "$w/out" 2>&1 || fail "the step failed: $(cat "$w/out")"
}
( unset SOURCE_DATE_EPOCH; run "$w/ws" ) || exit 1
grep -qx 'ZERO_AR_DATE=1' "$w/env" || fail "ZERO_AR_DATE=1 is exported: $(cat "$w/env")"
grep -qx 'SOURCE_DATE_EPOCH=1700000123' "$w/env" || fail "SOURCE_DATE_EPOCH is HEAD's committer time: $(cat "$w/env")"
echo "ok: SOURCE_DATE_EPOCH and ZERO_AR_DATE are exported"
( SOURCE_DATE_EPOCH=42; export SOURCE_DATE_EPOCH; run "$w/ws" ) || exit 1
grep -q '^SOURCE_DATE_EPOCH=' "$w/env" && fail "a preset SOURCE_DATE_EPOCH is kept, not overwritten: $(cat "$w/env")"
grep -qx 'ZERO_AR_DATE=1' "$w/env" || fail "ZERO_AR_DATE=1 is exported with a preset SOURCE_DATE_EPOCH too"
echo "ok: a preset SOURCE_DATE_EPOCH is kept"
mkdir -p "$w/bare"
( unset SOURCE_DATE_EPOCH; run "$w/bare" ) || exit 1
grep -q '^SOURCE_DATE_EPOCH=' "$w/env" && fail "a workspace that is no checkout exports no SOURCE_DATE_EPOCH: $(cat "$w/env")"
grep -q '::notice::' "$w/out" || fail "a workspace that is no checkout says so: $(cat "$w/out")"
echo "PASS: install-action-reproducible"
