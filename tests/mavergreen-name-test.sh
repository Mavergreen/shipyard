#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-name-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
p="$w/.mavergreen/products"
mkdir -p "$p/go127" "$p/libcxx22" "$p/shipyard" "$p/porthole" "$p/empty" "$p/bare"
printf 'Go\n' > "$p/go127/noun"; printf '1.27\n' > "$p/go127/line"
printf 'libc++\n' > "$p/libcxx22/noun"; printf '22\n' > "$p/libcxx22/line"
printf 'Shipyard\n' > "$p/shipyard/noun"
printf 'Porthole' > "$p/porthole/noun"
: > "$p/empty/noun"

fail() { echo "FAIL $*"; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
status() { _st=0; "$@" >/dev/null 2>&1 || _st=$?; printf '%s\n' "$_st"; }

MAVERGREEN_REPO_ROOT="$w"; export MAVERGREEN_REPO_ROOT
. "$here/../scripts/mavergreen-meta.sh"

eq name-go "$(mavergreen_name name go127)" "Go 1.27"
eq installer-title "$(mavergreen_name installer-title go127)" "Mavergreen Go 1.27"
eq link-suffix "$(mavergreen_name link-suffix go127)" 127
printf '1.27\n' > "$p/go127/line"
eq title "$(mavergreen_name title go127 1.27.2-mavergreen.1)" "Go 1.27.2"
eq pkg "$(mavergreen_name pkg go127 1.27.2-mavergreen.1)" "go127-1.27.2-mavergreen.1.pkg"
eq name-libcxx "$(mavergreen_name name libcxx22)" "libc++ 22"
eq title-shipyard "$(mavergreen_name title shipyard v1.0.300)" "Shipyard 1.0.300"
eq pkg-shipyard "$(mavergreen_name pkg shipyard v1.0.300)" "shipyard-1.0.300.pkg"
eq title-porthole "$(mavergreen_name title porthole 20261006.1)" "Porthole 20261006.1"
eq notes-heading "$(mavergreen_name notes-heading porthole 20261006.1)" "## Porthole 20261006.1"
eq release-title "$(mavergreen_name release-title go127 1.27.2-mavergreen.1)" "Go 1.27.2"
eq item-title "$(mavergreen_name item-title go127 1.27.2-mavergreen.1)" "Go 1.27.2"
eq channel-title "$(mavergreen_name channel-title go127)" "Go 1.27"
eq manifest-name "$(mavergreen_name manifest-name go127)" "Go 1.27"
eq component "$(mavergreen_name component go127)" go127.pkg
eq feed "$(mavergreen_name feed go127)" go127.xml
eq identifier "$(mavergreen_name identifier go127)" dev.mavergreen.go127
eq link-suffix-none "$(mavergreen_name link-suffix shipyard)" ""
eq no-newline "$(mavergreen_name name porthole)" Porthole

eq "name empty status" "$(status mavergreen_name name empty)" 1
eq "name bare status" "$(status mavergreen_name name bare)" 1
eq "name absent product status" "$(status mavergreen_name name nowhere)" 1
err="$(mavergreen_name name empty 2>&1 >/dev/null || :)"
case "$err" in *".mavergreen/products/empty/noun"*) ;; *) fail "empty noun stderr: '$err'";; esac
err="$(mavergreen_name name bare 2>&1 >/dev/null || :)"
case "$err" in *".mavergreen/products/bare/noun"*) ;; *) fail "bare noun stderr: '$err'";; esac

eq "unknown surface" "$(status mavergreen_name bogus go127)" 2
eq "missing version" "$(status mavergreen_name title go127)" 2
eq "missing version pkg" "$(status mavergreen_name pkg go127)" 2
eq "bad short" "$(status mavergreen_name name Go127)" 2

eq "mg_repo env" "$(GITHUB_REPOSITORY=Mavergreen/x mg_repo)" Mavergreen/x
echo "ok mavergreen-name-test"
