#!/bin/sh
# platform: host-agnostic
#   usage: objc-drydock-wrappers-test.sh
# spec: scripts/objc-compat.sh, scripts/objc-build-evidence.sh, scripts/objc-provider-link-args.sh and scripts/objc-resolve.sh
#       headers -- each runs the pinned Drydock's drydock-objc (here a stub prefix named by MAVERGREEN_DRYDOCK_PREFIX) with its own subcommand
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
# spec: scripts/objc-compat.sh header -- the stub records its arguments one per line and exits with $STUB_RC.
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
wrap objc-compat.sh 0 --artifact "$A" --root /r --references /refs --report /rep --build-evidence /e \
  --source-root '/s s' --crate-sources /c --sdk-root /k
[ "$rc" = 0 ] && argv_is analyze --artifact "$A" --root /r --references /refs --report /rep --build-evidence /e \
  --source-root '/s s' --crate-sources /c --sdk-root /k &&
  pass 'objc-compat.sh passes --source-root, --crate-sources and --sdk-root to drydock-objc analyze' ||
  fail "objc-compat.sh with the source roots: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-compat.sh 0 --artifact "$A" --root /r --references /refs --report /rep --mode strict --root-kind volume
[ "$rc" = 0 ] && argv_is analyze --artifact "$A" --root /r --references /refs --report /rep --mode strict --root-kind volume &&
  pass 'objc-compat.sh passes --root-kind to drydock-objc analyze' ||
  fail "objc-compat.sh with --root-kind: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-compat.sh 0 --artifact "$A" --root /r --references /refs --report /rep --build-evidence /e \
  --link-map '/m m' --object-dir /o1 --object-dir '/o 2'
[ "$rc" = 0 ] && argv_is analyze --artifact "$A" --root /r --references /refs --report /rep --build-evidence /e \
  --link-map '/m m' --object-dir /o1 --object-dir '/o 2' &&
  pass 'objc-compat.sh passes --link-map and every --object-dir to drydock-objc analyze' ||
  fail "objc-compat.sh with --link-map and --object-dir: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-compat.sh 0 --artifact "$A" --root /r
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-compat.sh refuses a short call' || fail "objc-compat.sh short: exit $rc"

wrap objc-build-evidence.sh 0 --artifact /a --prestrip /p --source-root /s --references /refs --output /o
[ "$rc" = 0 ] && argv_is evidence --artifact /a --prestrip /p --source-root /s --references /refs --output /o &&
  pass 'objc-build-evidence.sh runs drydock-objc evidence with its arguments' || fail "objc-build-evidence.sh: exit $rc"
wrap objc-build-evidence.sh 4 --artifact /a --prestrip /p --source-root /s --link-map /m --provider-prefix /x --references /refs --output /o
[ "$rc" = 4 ] && pass 'objc-build-evidence.sh exits with drydock-objc' || fail "objc-build-evidence.sh: exit $rc, want 4"
wrap objc-build-evidence.sh 0 --artifact /a --prestrip /p --source-root /s --link-map /m --references /refs --output /o
[ "$rc" = 0 ] && argv_is evidence --artifact /a --prestrip /p --source-root /s --link-map /m --references /refs --output /o &&
  pass 'objc-build-evidence.sh passes --link-map without --provider-prefix' ||
  fail "objc-build-evidence.sh with --link-map alone: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-build-evidence.sh 0 --artifact /a --prestrip /p --source-root /s --output /o
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-build-evidence.sh refuses a malformed call' || fail "objc-build-evidence.sh short: exit $rc"

# spec: scripts/objc-build-evidence.sh header -- the digest-only forms print a prepared tree's or an SDK's digest.
wrap objc-build-evidence.sh 0 --tree-digest-only --source-root '/s s'
[ "$rc" = 0 ] && argv_is evidence --tree-digest-only --source-root '/s s' &&
  pass 'objc-build-evidence.sh --tree-digest-only runs drydock-objc evidence --tree-digest-only' ||
  fail "objc-build-evidence.sh --tree-digest-only: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-build-evidence.sh 0 --sdk-digest-only --sdk-root /k
[ "$rc" = 0 ] && argv_is evidence --sdk-digest-only --sdk-root /k &&
  pass 'objc-build-evidence.sh --sdk-digest-only runs drydock-objc evidence --sdk-digest-only' ||
  fail "objc-build-evidence.sh --sdk-digest-only: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-build-evidence.sh 4 --tree-digest-only --source-root /s
[ "$rc" = 4 ] && pass 'objc-build-evidence.sh --tree-digest-only exits with drydock-objc' || fail "--tree-digest-only: exit $rc, want 4"
for bad in '--tree-digest-only --sdk-root /k' '--sdk-digest-only --source-root /s' '--source-root /s --tree-digest-only' \
           '--tree-digest-only --source-root' '--tree-digest-only --source-root /s --sdk-root /k'; do
  # shellcheck disable=SC2086
  wrap objc-build-evidence.sh 0 $bad
  [ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass "objc-build-evidence.sh refuses '$bad'" || fail "objc-build-evidence.sh '$bad': exit $rc"
done

wrap objc-provider-link-args.sh 0 --prefix /x --link-map /m
[ "$rc" = 0 ] && argv_is link-args --prefix /x --link-map /m &&
  pass 'objc-provider-link-args.sh runs drydock-objc link-args with its arguments' || fail "objc-provider-link-args.sh: exit $rc"
wrap objc-provider-link-args.sh 0 --prefix /x --output /m
[ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass 'objc-provider-link-args.sh refuses a malformed call' || fail "link-args malformed: exit $rc"
# spec: scripts/objc-provider-link-args.sh header -- any number of --provider ID pairs, passed on in the order given.
wrap objc-provider-link-args.sh 0 --prefix /x --link-map /m --provider openurls --provider 'an id'
[ "$rc" = 0 ] && argv_is link-args --prefix /x --link-map /m --provider openurls --provider 'an id' &&
  pass 'objc-provider-link-args.sh passes every --provider ID to drydock-objc link-args' ||
  fail "objc-provider-link-args.sh with providers: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
wrap objc-provider-link-args.sh 0 --provider openurls --link-map /m --prefix /x
[ "$rc" = 0 ] && argv_is link-args --provider openurls --link-map /m --prefix /x &&
  pass 'objc-provider-link-args.sh keeps its options in the order given' || fail "link-args reordered: exit $rc"
for bad in '--prefix /x --link-map /m --provider' '--prefix /x --link-map /m --providers a' '--prefix /x --provider a' \
           '--prefix /x --link-map /m --prefix /y' '--prefix /x --link-map /m --link-map /n' '--link-map /m --provider a --provider b'; do
  # shellcheck disable=SC2086
  wrap objc-provider-link-args.sh 0 $bad
  [ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass "objc-provider-link-args.sh refuses '$bad'" || fail "link-args '$bad': exit $rc"
done

# spec: scripts/objc-resolve.sh header -- runs drydock-objc resolve with its arguments and exits with its status.
wrap objc-resolve.sh 0 --artifact "$A" --reviewed /rev --output /o
[ "$rc" = 0 ] && argv_is resolve --artifact "$A" --reviewed /rev --output /o &&
  pass 'objc-resolve.sh runs drydock-objc resolve with its arguments' || fail "objc-resolve.sh: exit $rc, argv $(cat "$T/argv" 2>/dev/null)"
for want in 2 4; do
  wrap objc-resolve.sh "$want" --output /o --artifact "$A" --reviewed /rev
  [ "$rc" = "$want" ] && pass "objc-resolve.sh exits $want when drydock-objc does" || fail "objc-resolve.sh: exit $rc, want $want"
done
for bad in '--artifact /a --reviewed /rev' '--artifact /a --reviewed /rev --report /o' '--artifact /a --artifact /b --output /o' \
           '--artifact /a --reviewed /rev --output /o --mode strict'; do
  # shellcheck disable=SC2086
  wrap objc-resolve.sh 0 $bad
  [ "$rc" = 2 ] && [ ! -e "$T/argv" ] && pass "objc-resolve.sh refuses '$bad'" || fail "objc-resolve.sh '$bad': exit $rc"
done

# spec: scripts/objc-compat.sh header -- the pinned Drydock's drydock-objc analyzes, writes evidence, prints link arguments and
#       resolves on Linux as on a Mac, so on a host uname calls Linux each wrapper runs it and exits with its status.
mkdir -p "$T/linux-bin"
printf '#!/bin/sh\ncase "$1" in -m) echo x86_64 ;; *) echo Linux ;; esac\n' >"$T/linux-bin/uname"
chmod +x "$T/linux-bin/uname"
saved_path=$PATH; PATH="$T/linux-bin:$PATH"
for s in "objc-compat.sh analyze --artifact /a --root /r --references /refs --report /rep" \
         "objc-build-evidence.sh evidence --artifact /a --prestrip /p --source-root /s --references /refs --output /o" \
         "objc-provider-link-args.sh link-args --prefix /x --link-map /m" \
         "objc-resolve.sh resolve --artifact /a --reviewed /rev --output /o"; do
  # shellcheck disable=SC2086
  set -- $s; script=$1; cmd=$2; shift 2
  for want in 0 1 4; do
    wrap "$script" "$want" "$@"
    [ "$rc" = "$want" ] && argv_is "$cmd" "$@" &&
      pass "$script on Linux runs drydock-objc $cmd and exits $want with it" || fail "$script on Linux: exit $rc, want $want"
  done
done
PATH=$saved_path
MAVERGREEN_DRYDOCK_PREFIX="$T/no-drydock"
for s in "objc-compat.sh --artifact /a --root /r --references /refs --report /rep" \
         "objc-build-evidence.sh --artifact /a --prestrip /p --source-root /s --references /refs --output /o" \
         "objc-provider-link-args.sh --prefix /x --link-map /m" \
         "objc-resolve.sh --artifact /a --reviewed /rev --output /o"; do
  # shellcheck disable=SC2086
  set -- $s; script=$1; shift
  wrap "$script" 0 "$@"
  [ "$rc" = 4 ] && pass "${s%% *}: no Drydock is cannot-measure (4)" || fail "${s%% *} with no Drydock: exit $rc, want 4"
done

[ "$fails" = 0 ] && echo 'objc-drydock-wrappers-test: all passed' || { echo "objc-drydock-wrappers-test: $fails failed"; exit 1; }
