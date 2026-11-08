#!/bin/sh
# platform: host-agnostic
#   usage: objc-drydock-wrappers-test.sh
# spec: scripts/objc-compat.sh, scripts/objc-build-evidence.sh and scripts/objc-provider-link-args.sh headers -- each runs
#       the pinned Drydock's drydock-objc (here a stub prefix named by MAVERGREEN_DRYDOCK_PREFIX) with its own subcommand
#       and the caller's arguments unchanged, and exits with its status; a malformed call is refused before it runs (2);
#       a Drydock that cannot be had is cannot-measure (4).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-drydock-wrappers-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [ ! -f "$T/err" ] || sed 's/^/    | /' "$T/err"; fails=$((fails + 1)); }
mkdir -p "$T/drydock/bin"
# The stub records its arguments one per line and exits with $STUB_RC.
cat >"$T/drydock/bin/drydock-objc" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done >"$T/argv"
exit "\${STUB_RC:-0}"
EOF
chmod +x "$T/drydock/bin/drydock-objc"
MAVERGREEN_DRYDOCK_PREFIX="$T/drydock"; export MAVERGREEN_DRYDOCK_PREFIX
# spec: scripts/objc-compat.sh header -- wrap SCRIPT RC ARGS...: SCRIPT run with ARGS while the stub exits RC; sets rc.
wrap() { s=$1 STUB_RC=$2; export STUB_RC; shift 2; rm -f "$T/argv"; rc=0; sh "$ROOT/scripts/$s" "$@" 2>"$T/err" || rc=$?; }
argv_is() { for a in "$@"; do printf '%s\n' "$a"; done >"$T/want"; cmp -s "$T/want" "$T/argv" 2>/dev/null; }

A='a file'
wrap objc-compat.sh 0 --artifact "$A" --root /r --references /refs --report /rep --mode strict
[ "$rc" = 0 ] && argv_is analyze --artifact "$A" --root /r --references /refs --report /rep --mode strict &&
  pass 'objc-compat.sh runs drydock-objc analyze with its arguments' || fail "objc-compat.sh: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
for want in 1 2 4; do
  wrap objc-compat.sh "$want" --artifact "$A" --root /r --references /refs --report /rep
  [ "$rc" = "$want" ] && pass "objc-compat.sh exits $want when drydock-objc does" || fail "objc-compat.sh: exit $rc, want $want"
done
wrap objc-compat.sh 0 --artifact "$A" --root /r --references /refs --report /rep --analyzer-id mine
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-compat.sh refuses an option its usage does not name, before running' ||
  fail "objc-compat.sh with --analyzer-id: exit $rc"
wrap objc-compat.sh 0 --artifact "$A" --root /r
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-compat.sh refuses a short call' || fail "objc-compat.sh short: exit $rc"

wrap objc-build-evidence.sh 0 --artifact /a --prestrip /p --source-root /s --references /refs --output /o
[ "$rc" = 0 ] && argv_is evidence --artifact /a --prestrip /p --source-root /s --references /refs --output /o &&
  pass 'objc-build-evidence.sh runs drydock-objc evidence with its arguments' || fail "objc-build-evidence.sh: exit $rc"
wrap objc-build-evidence.sh 4 --artifact /a --prestrip /p --source-root /s --link-map /m --provider-prefix /x --references /refs --output /o
[ "$rc" = 4 ] && pass 'objc-build-evidence.sh exits with drydock-objc' || fail "objc-build-evidence.sh: exit $rc, want 4"
wrap objc-build-evidence.sh 0 --artifact /a --prestrip /p --source-root /s --output /o
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-build-evidence.sh refuses a malformed call' || fail "objc-build-evidence.sh short: exit $rc"

wrap objc-provider-link-args.sh 0 --prefix /x --link-map /m
[ "$rc" = 0 ] && argv_is link-args --prefix /x --link-map /m &&
  pass 'objc-provider-link-args.sh runs drydock-objc link-args with its arguments' || fail "objc-provider-link-args.sh: exit $rc"
wrap objc-provider-link-args.sh 0 --prefix /x --output /m
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-provider-link-args.sh refuses a malformed call' || fail "link-args malformed: exit $rc"

MAVERGREEN_DRYDOCK_PREFIX="$T/no-drydock"
for s in "objc-compat.sh --artifact /a --root /r --references /refs --report /rep" \
         "objc-build-evidence.sh --artifact /a --prestrip /p --source-root /s --references /refs --output /o" \
         "objc-provider-link-args.sh --prefix /x --link-map /m"; do
  # shellcheck disable=SC2086
  set -- $s; script=$1; shift
  wrap "$script" 0 "$@"
  [ "$rc" = 4 ] && pass "${s%% *}: no Drydock is cannot-measure (4)" || fail "${s%% *} with no Drydock: exit $rc, want 4"
done

[ "$fails" = 0 ] && echo 'objc-drydock-wrappers-test: all passed' || { echo "objc-drydock-wrappers-test: $fails failed"; exit 1; }
