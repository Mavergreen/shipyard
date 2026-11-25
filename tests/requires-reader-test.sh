#!/bin/sh
# platform: host-agnostic
# spec: scripts/lib/requires.sh -- mavergreen_requires with an ARCH reads requires-on-host from a manifest staged by render-manifest.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/requires-reader.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
. "$here/../scripts/lib/requires.sh"
st="$w/stage"; mkdir -p "$st/usr/local/mavergreen/openssh/bin"; touch "$st/usr/local/mavergreen/openssh/bin/ssh"
M="$st/usr/local/mavergreen/openssh/mavergreen.plist"
render() { sh "$here/../scripts/render-manifest.sh" --stage "$st" --product openssh --name x --version 1 "$@"; }
render --requires sdk109 --requires-on-host x86_64:swift-runtime --requires-on-host 'arm64:sdk113>=1'
[ "$(mavergreen_requires "$SD" "$M" "$w/err")" = sdk109 ] || fail "without ARCH only requires is read"
[ "$(mavergreen_requires "$SD" "$M" "$w/err" x86_64)" = "$(printf 'sdk109\nswift-runtime')" ] || fail "x86_64 reads its entries"
[ "$(mavergreen_requires "$SD" "$M" "$w/err" arm64)" = "$(printf 'sdk109\nsdk113>=1')" ] || fail "arm64 reads its entries"
[ "$(mavergreen_requires "$SD" "$M" "$w/err" all)" = "$(printf 'sdk109\nswift-runtime\nsdk113>=1')" ] || fail "all reads every entry"
render
[ -z "$(mavergreen_requires "$SD" "$M" "$w/err" all)" ] || fail "a manifest without the key has none"
render --requires-on-host ppc:sdk109
rc=0; mavergreen_requires "$SD" "$M" "$w/err" all >/dev/null || rc=$?
[ "$rc" -eq 1 ] && grep -qF " requires-on-host 'ppc:sdk109' names no arch" "$w/err" || fail "an entry with no known arch is an error: $(cat "$w/err")"
echo "PASS: requires-reader"
