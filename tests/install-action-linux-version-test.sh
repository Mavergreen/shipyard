#!/bin/sh
# platform: host-agnostic
#   usage: install-action-linux-version-test.sh
#          Off macOS, install@v1 exports SHIPYARD_VERSION, resolved from the ref the caller pinned, so
#          build-base-component.sh can name the base's version where the action's checkout has no .git
#          and no installed config (ed25519's Linux packaging, 2026-10-27). A consumer whose ref names
#          no release is warned; shipyard's own ./.github/actions/install, whose checkout is the
#          workspace and whose ref is empty, is not. Runs the step itself, with a git that cannot reach
#          the network. Exit 0 clean, 1 on failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/install-linux-version.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/bin"; printf '#!/bin/sh\nexit 128\n' > "$w/bin/git"; chmod +x "$w/bin/git"
python3 - "$root/.github/actions/install/action.yml" "$w/step" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
off = [s for s in steps if "runner.os != 'macOS'" in (s.get("if") or "")]
if len(off) != 1:
    print("FAIL: install-action-linux-version: expected one release step off macOS, got %d" % len(off)); sys.exit(1)
open(sys.argv[2], "w").write(off[0].get("run") or "")
PY
bad=0
run() {  # $1 = github.action_ref  $2 = GITHUB_WORKSPACE
  sed "s|\${{ github.action_ref }}|$1|g" "$w/step" > "$w/step.sh"
  : > "$w/env"; : > "$w/path"; mkdir -p "$w/rt"
  env PATH="$w/bin:$PATH" GITHUB_ACTION_PATH="$root/.github/actions/install" GITHUB_ENV="$w/env" \
    RUNNER_TEMP="$w/rt" GITHUB_PATH="$w/path" \
    GITHUB_WORKSPACE="$2" bash "$w/step.sh" > "$w/out" 2>&1 \
    || { echo "FAIL: the off-macOS step failed (ref '$1'):"; sed 's/^/    | /' "$w/out"; bad=1; }
}
run v1.2.3 "$w/consumer"
grep -qx 'SHIPYARD_VERSION=1.2.3' "$w/env" || { echo "FAIL: an exact pin must export SHIPYARD_VERSION=1.2.3"; bad=1; }
! grep -q '::warning::' "$w/out" || { echo "FAIL: an exact pin must not warn:"; sed 's/^/    | /' "$w/out"; bad=1; }
run main "$w/consumer"
grep -q "::warning::'main' names no shipyard release" "$w/out" \
  || { echo "FAIL: a consumer ref that names no release must warn:"; sed 's/^/    | /' "$w/out"; bad=1; }
run '' "$root"
! grep -q '::warning::' "$w/out" \
  || { echo "FAIL: shipyard's own ./.github/actions/install must not warn about its empty ref:"; sed 's/^/    | /' "$w/out"; bad=1; }
grep -qx "MavericksShipyard_DIR=$root" "$w/env" || { echo "FAIL: the local checkout must still export MavericksShipyard_DIR"; bad=1; }
[ "$bad" -eq 0 ] || exit 1
echo "PASS: install-action-linux-version"
