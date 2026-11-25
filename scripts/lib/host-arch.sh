# platform: host-agnostic
#   usage: . scripts/lib/host-arch.sh; mavergreen_host_arch
#          Prints the hardware arch of this host, arm64 or x86_64: arm64 exactly when
#          `/usr/sbin/sysctl -n hw.optional.arm64` prints 1, x86_64 in every other case (an unknown OID on
#          10.9, no sysctl, Linux). uname -m is never read: Rosetta translates it. A set
#          MAVERGREEN_HOST_ARCH of x86_64 or arm64 replaces the sysctl; any other value is an
#          error on stderr and return 2. MAVERGREEN_SYSCTL replaces /usr/sbin/sysctl, so a
#          PATH without /usr/sbin cannot answer x86_64 on Apple Silicon. Inlined into generated
#          scripts, so it never sets -e.
# spec: tests/host-arch-test.sh

mavergreen_host_arch() {
  if [ -n "${MAVERGREEN_HOST_ARCH:-}" ]; then
    case "$MAVERGREEN_HOST_ARCH" in
      x86_64|arm64) printf '%s\n' "$MAVERGREEN_HOST_ARCH"; return 0 ;;
    esac
    echo "mavergreen: MAVERGREEN_HOST_ARCH is '$MAVERGREEN_HOST_ARCH', not x86_64 or arm64" >&2
    return 2
  fi
  if [ "$("${MAVERGREEN_SYSCTL:-/usr/sbin/sysctl}" -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    printf 'arm64\n'
  else
    printf 'x86_64\n'
  fi
}
