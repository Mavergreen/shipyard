#!/bin/sh
# platform: host-agnostic
#   usage: mavericks_mode.sh
#          Prints "native" when running on OS X 10.9, else "cross". The sh companion to
#          MavericksMode.cmake, for build/gate scripts. POSIX sh; no bashisms.
# platform: guarded macOS-only call -- the uname test on this same line keeps sw_vers off Linux
if [ "$(uname -s)" = Darwin ] && sw_vers -productVersion 2>/dev/null | grep -q '^10\.9\.'; then
  echo native
else
  echo cross
fi
