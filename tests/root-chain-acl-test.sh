#!/bin/sh
# platform: macOS-only -- chmod +a and ls -le are Darwin's; run by hand on the 10.9 box and Golden Gate (tests/maintainer-tests)
# spec: scripts/lib/root-chain.sh -- a deny entry passes; an allow entry granting a write fails acl-write, and its fix names the entry.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
. "$here/../scripts/lib/root-chain.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/root-chain-acl-test.XXXXXX")"; trap 'chmod -RN "$w" 2>/dev/null; rm -rf "$w"' EXIT
unset MAVERGREEN_CHAIN_UID
mavergreen_chain_ok /usr/bin / 2>"$w/err" || { cat "$w/err"; fail "/usr/bin passes with the default uid 0"; }
mavergreen_chain_ok /usr/bin // 2>"$w/err" || { cat "$w/err"; fail "/usr/bin passes with a // VOLROOT"; }

MAVERGREEN_CHAIN_UID="$(id -u)"; export MAVERGREEN_CHAIN_UID
d="$(cd -P "$w" && pwd -P)/d"
mkdir -m 755 "$d"
chmod +a "group:everyone deny delete" "$d"
[ "$(ls -ldne "$d" | mavergreen_chain_verdict)" = ok ] || fail "a real deny entry's verdict is ok"
mavergreen_chain_ok "$d" "$d" 2>"$w/err" || { cat "$w/err"; fail "a deny entry passes"; }
mavergreen_dir_ok "$d" 2>"$w/err" || { cat "$w/err"; fail "dir_ok passes a deny entry"; }
chmod +a "group:staff allow add_file" "$d"
[ "$(ls -ldne "$d" | mavergreen_chain_verdict)" = acl-write ] || fail "a real allow add_file entry's verdict is acl-write"
if mavergreen_chain_ok "$d" "$d" 2>"$w/err"; then fail "an allow add_file entry fails"; fi
grep -qxF "$d: acl-write; root will not write or run here; fix: sudo chmod -a 'group:staff allow add_file' '$d'" "$w/err" \
  || { cat "$w/err"; fail "the acl-write line names the entry to remove"; }
if mavergreen_root_dir "$d" 2>"$w/err"; then fail "root_dir refuses an allow add_file entry"; fi
grep -qF "$d: acl-write;" "$w/err" || { cat "$w/err"; fail "root_dir names acl-write"; }
chmod -N "$d"; chmod +a "group:staff allow add_subdirectory,directory_inherit" "$d"; mkdir "$d/c"; chmod -a "group:staff allow add_subdirectory,directory_inherit" "$d"
if mavergreen_chain_ok "$d/c" "$d" 2>"$w/err"; then fail "an inherited allow add_subdirectory entry fails"; fi
grep -qxF "$d/c: acl-write; root will not write or run here; fix: sudo chmod -a 'group:staff allow add_subdirectory,directory_inherit' '$d/c'" "$w/err" \
  || { cat "$w/err"; fail "the fix for an inherited entry drops the word inherited"; }
echo "PASS: root-chain-acl"
