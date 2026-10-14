#!/bin/sh
# platform: host-agnostic
#   usage: installed as `gh` ahead of PATH; answers from the files under $GH_STUB, so no network is touched
d="$GH_STUB"
case "$1 $2" in
  "auth status") [ -f "$d/noauth" ] && exit 1; cat "$d/scopes"; exit 0 ;;
  "repo list") cat "$d/repos"; exit 0 ;;
esac
case "$2" in
  repos/*/shipyard) cat "$d/shipyard-admin"; exit 0 ;;
  repos/*/contents/*) r="${2#repos/*/}"; r="${r%%/contents*}"; [ -f "$d/product-$r" ] && exit 0; exit 1 ;;
  repos/*/branches/main/protection) r="${2#repos/*/}"; r="${r%%/branches*}"; [ -f "$d/ctx-$r" ] || exit 1; cat "$d/ctx-$r"; exit 0 ;;
  repos/*) r="${2#repos/*/}"; cat "$d/am-$r"; exit 0 ;;
esac
exit 1
