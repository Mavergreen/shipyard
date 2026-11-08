#!/bin/sh
# platform: host-agnostic -- the source receipt is written on x86_64 Linux (Recaulk's release host) and on a Mac alike
# spec: scripts/objc-source-inventory.sh header -- the receipt is the pinned Drydock's `drydock-objc receipt`, given the clang
#       and the floor SDK the wrapper fetched; with no --clang-prefix the pinned receipt clang is fetched, and the receipt of
#       one prepared source is the same on every host: tests/fixtures/objc-api/provider-body.receipt, apart from its libclang
#       line (the pinned release's own version string) and its tool line (the digest of Drydock's receipt tool source,
#       recorded in tests/fixtures/objc-api/provider-body.tool). Any exit of
#       drydock-objc's but 0, 2 and 4, a death by signal included, is 4.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
FX="$HERE/fixtures/objc-api"
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-source-inventory-host-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
unset MAVERGREEN_DRYDOCK_PREFIX
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [ ! -f "$T/err" ] || tail -15 "$T/err"; fails=$((fails + 1)); }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-64; }

mkdir -p "$T/src"
cp "$FX/provider-body.m" "$FX/provider-register.c" "$T/src/"
printf '%s  provider-body.m\n%s  provider-register.c\n' "$(sha "$T/src/provider-body.m")" "$(sha "$T/src/provider-register.c")" >"$T/inputs"
inventory() { sh "$ROOT/scripts/objc-source-inventory.sh" "$@" --inputs "$T/inputs" --root "$T/src" \
  --unit provider-body.m --unit provider-register.c; }

# spec: scripts/objc-source-inventory.sh header -- the wrapper hands drydock-objc receipt the clang and the floor SDK, then the
#       caller's options in order. A stub Drydock (MAVERGREEN_DRYDOCK_PREFIX) records its arguments and exits $STUB_RC, or
#       kills itself when STUB_RC is "signal".
mkdir -p "$T/stub/bin" "$T/clang"
cat >"$T/stub/bin/drydock-objc" <<STUB
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done >"$T/argv"
[ "\${STUB_RC:-0}" != signal ] || kill -9 \$\$
exit "\${STUB_RC:-0}"
STUB
chmod +x "$T/stub/bin/drydock-objc"
floor=$(sh "$ROOT/scripts/fetch_sdk.sh" --arch x86_64)
stubbed() { STUB_RC=$1; export STUB_RC; shift; rm -f "$T/argv"; rc=0
  (MAVERGREEN_DRYDOCK_PREFIX="$T/stub"; export MAVERGREEN_DRYDOCK_PREFIX; inventory --clang-prefix "$T/clang" "$@" --output "$T/stub.receipt") \
    2>"$T/err" || rc=$?; }
stubbed 0
printf '%s\n' receipt --clang-prefix "$T/clang" --sdk "$floor" --output "$T/stub.receipt" --inputs "$T/inputs" --root "$T/src" \
  --unit provider-body.m --unit provider-register.c >"$T/want"
[ "$rc" = 0 ] && cmp -s "$T/want" "$T/argv" && pass 'drydock-objc receipt gets the named clang, the floor SDK and the options in order' ||
  { fail "the stub receipt: exit $rc"; diff "$T/want" "$T/argv" | head -10; }
for c in 2:2 4:4 3:4 1:4 signal:4; do
  stubbed "${c%%:*}"
  [ "$rc" = "${c#*:}" ] && pass "drydock-objc's ${c%%:*} is the wrapper's ${c#*:}" || fail "drydock-objc's ${c%%:*}: exit $rc, want ${c#*:}"
done
rc=0; (MAVERGREEN_DRYDOCK_PREFIX="$T/no-drydock"; export MAVERGREEN_DRYDOCK_PREFIX
  inventory --clang-prefix "$T/clang" --output "$T/none.receipt") 2>"$T/err" || rc=$?
[ "$rc" = 4 ] && [ ! -e "$T/none.receipt" ] && pass 'a Drydock that cannot be had is 4' || fail "no Drydock: exit $rc, want 4"
rc=0; MAVERGREEN_DRYDOCK_PREFIX="$T/stub" sh "$ROOT/scripts/objc-source-inventory.sh" --inputs "$T/inputs" --output "$T/x" 2>"$T/err" || rc=$?
[ "$rc" = 2 ] && pass 'a short call is usage' || fail "short call: exit $rc, want 2"
unset STUB_RC

rc=0; inventory --output "$T/fetched.receipt" 2>"$T/err" || rc=$?
if [ "$rc" = 0 ]; then
  pass 'with no --clang-prefix, the pinned receipt clang is fetched and the receipt written'
  grep -v -e '^libclang	' -e '^tool	' "$T/fetched.receipt" >"$T/fetched.body"
  if cmp -s "$T/fetched.body" "$FX/provider-body.receipt"; then pass "the receipt matches the recorded one on $(uname -s) $(uname -m)"
  else fail "the receipt differs from tests/fixtures/objc-api/provider-body.receipt on $(uname -s) $(uname -m):"; diff "$FX/provider-body.receipt" "$T/fetched.body" | head -20; fi
  grep -q '^libclang	clang version 22\.' "$T/fetched.receipt" && pass 'the receipt names clang 22' ||
    fail "the receipt's libclang line: $(grep '^libclang' "$T/fetched.receipt")"
  grep -Fxq "$(printf 'tool\t%s' "$(cat "$FX/provider-body.tool")")" "$T/fetched.receipt" &&
    pass "the receipt names Drydock's receipt tool by the digest recorded in provider-body.tool" ||
    fail "the receipt's tool line: $(grep '^tool' "$T/fetched.receipt")"
else
  fail "inventory with the fetched clang exits $rc"
fi

rc=0; inventory --clang-prefix "$T/no-such-clang" --output "$T/named.receipt" 2>"$T/err" || rc=$?
[ "$rc" = 4 ] && [ ! -e "$T/named.receipt" ] && grep -qF "$T/no-such-clang" "$T/err" &&
  pass 'a named --clang-prefix is used, not replaced by the fetched one' || fail "a missing named prefix exits $rc"

[ "$fails" = 0 ] && echo 'objc-source-inventory-host-test: all passed' || { echo "objc-source-inventory-host-test: $fails failed"; exit 1; }
