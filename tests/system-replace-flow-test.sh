#!/bin/sh
# platform: macOS-only -- pkgbuild, pkgutil, lsbom, mkbom and PlistBuddy build the pkgs and the fake volume
#   usage: sh tests/system-replace-flow-test.sh
#          tests/system-replace-mavericks.sh's life cycle, as a non-root user on a fake volume: the
#          real generated preinstall and postinstall, the real helper, Installer emulated.
# spec: tests/lib/system_replace_flow.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" != 0 ] || { echo "the fake-volume flow runs as a non-root user -- skipping as root"; exit 77; }
for t in pkgbuild pkgutil lsbom mkbom /usr/libexec/PlistBuddy; do
  command -v "$t" >/dev/null 2>&1 || { echo "no $t -- skipping"; exit 77; }
done
W="$(mktemp -d "${TMPDIR:-/tmp}/system-replace-flow.XXXXXX")"
E2E_MODE=fake; R="$W/vol"; RUID="$(id -u)"
MAVERGREEN_TRUSTED_UID="$RUID"; export MAVERGREEN_TRUSTED_UID
mkdir "$R"
. "$here/lib/system_replace_flow.sh"
