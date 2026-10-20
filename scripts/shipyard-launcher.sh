#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-cmake|shipyard-ctest|shipyard-cpack [ARG...]
#          Installed as <prefix>/shipyard/bin/shipyard-{cmake,ctest,cpack}; runs the cmake product's
#          <prefix>/cmake/bin/{cmake,ctest,cpack}. shipyard-cmake first appends <prefix>/shipyard to
#          CMAKE_PREFIX_PATH, so find_package(MavericksShipyard) finds it after any caller's entry.
# spec: 2026-10-09 C4
self="$0"
case "$self" in */*) ;; *) self="./$self" ;; esac
# platform: 10.9 has no realpath and no readlink -f, so links are followed one at a time.
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="${self%/*}/$link" ;;
  esac
done
case "${self##*/}" in
  shipyard-cmake) tool=cmake ;;
  shipyard-ctest) tool=ctest ;;
  shipyard-cpack) tool=cpack ;;
  *) echo "shipyard-launcher: install this as shipyard-cmake, shipyard-ctest or shipyard-cpack, not ${self##*/}" >&2; exit 2 ;;
esac
bin="$(cd -P "${self%/*}" && pwd)"
shipyard="${bin%/*}"
exe="${shipyard%/*}/cmake/bin/$tool"
if [ ! -x "$exe" ]; then
  echo "shipyard-$tool: shipyard needs the Mavergreen cmake product, which isn't installed: https://github.com/Mavergreen/cmake/releases/latest -- install it, then run this again." >&2
  exit 1
fi
if [ "$tool" = cmake ]; then
  CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:+$CMAKE_PREFIX_PATH:}$shipyard"
  export CMAKE_PREFIX_PATH
fi
exec "$exe" "$@"
