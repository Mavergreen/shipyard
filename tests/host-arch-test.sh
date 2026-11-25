#!/bin/sh
# platform: host-agnostic
# spec: scripts/lib/host-arch.sh -- the hardware arch from hw.optional.arm64, with a stub sysctl as MAVERGREEN_SYSCTL
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/host-arch.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$w/bin"
stub() { printf '#!/bin/sh\n%s\n' "$1" > "$w/bin/sysctl"; chmod +x "$w/bin/sysctl"; }
arch() { MAVERGREEN_SYSCTL="$w/bin/sysctl" sh -c '. "$1"; mavergreen_host_arch' sh "$here/../scripts/lib/host-arch.sh"; }

test_arm64_from_sysctl() {
  stub 'echo 1'
  [ "$(arch)" = arm64 ] || fail "sysctl 1 must give arm64"
}
test_unknown_oid_is_x86_64() {
  stub 'exit 1'
  [ "$(arch)" = x86_64 ] || fail "an unknown OID must give x86_64"
  stub 'echo 0'
  [ "$(arch)" = x86_64 ] || fail "sysctl 0 must give x86_64"
}
test_override_wins() {
  stub 'echo 1'
  [ "$(MAVERGREEN_HOST_ARCH=x86_64 arch)" = x86_64 ] || fail "the override must win over sysctl"
  stub 'exit 1'
  [ "$(MAVERGREEN_HOST_ARCH=arm64 arch)" = arm64 ] || fail "the arm64 override must win"
}
test_bad_override() {
  stub 'echo 1'
  rc=0; MAVERGREEN_HOST_ARCH=ppc arch > "$w/out" 2> "$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "a bad override must return 2, got $rc"
  grep -q 'not x86_64 or arm64' "$w/err" || fail "a bad override must say so: $(cat "$w/err")"
  [ ! -s "$w/out" ] || fail "a bad override prints nothing on stdout"
}
test_path_sysctl_is_ignored() {
  stub 'echo 1'
  want=x86_64; [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ] || want=arm64
  got="$(unset MAVERGREEN_SYSCTL; PATH="$w/bin:$PATH" sh -c '. "$1"; mavergreen_host_arch' sh "$here/../scripts/lib/host-arch.sh")" \
    || fail "mavergreen_host_arch failed with a sysctl on PATH"
  [ "$got" = "$want" ] || fail "a sysctl on PATH must not answer; /usr/sbin/sysctl does: got $got, want $want"
}
test_arm64_from_sysctl; test_unknown_oid_is_x86_64; test_override_wins; test_bad_override; test_path_sysctl_is_ignored
echo "PASS: host-arch"
