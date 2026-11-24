#!/bin/sh
# platform: host-agnostic
#   usage: kext_sig_exception.sh add PLIST BUNDLE_ID VERSION   add the entry, or replace its version
#          kext_sig_exception.sh remove PLIST BUNDLE_ID        remove it; absent is fine
#          PLIST is AppleKextExcludeList.kext/Contents/Info.plist on the target volume. 10.9's kextd
#          loads an unsigned kext from /Library/Extensions only when its bundle id is listed in that
#          file's OSKextSigExceptionList. Only that one <key>/<string> pair changes; every other byte
#          stays, and the file is replaced in one rename, mode 644. A plist that is not XML, or has no
#          OSKextSigExceptionList, is refused and left alone.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot"
set -eu
op="${1:-}"; P="${2:-}"; id="${3:-}"; ver="${4:-}"
case "$op" in
  add) [ -n "$id" ] && [ -n "$ver" ] || { echo "usage: kext_sig_exception.sh add PLIST BUNDLE_ID VERSION" >&2; exit 2; } ;;
  remove) [ -n "$id" ] || { echo "usage: kext_sig_exception.sh remove PLIST BUNDLE_ID" >&2; exit 2; } ;;
  *) echo "usage: kext_sig_exception.sh add|remove PLIST BUNDLE_ID [VERSION]" >&2; exit 2 ;;
esac
case "$id" in *[!A-Za-z0-9._-]*|.*|-*) echo "kext_sig_exception: bad bundle id '$id'" >&2; exit 2 ;; esac
case "$ver" in *[!A-Za-z0-9._+-]*) echo "kext_sig_exception: bad version '$ver'" >&2; exit 2 ;; esac
[ -f "$P" ] || { echo "kext_sig_exception: no $P" >&2; exit 1; }
head -c 5 "$P" | grep -q '^<?xml' || { echo "kext_sig_exception: $P is not an XML plist; left alone" >&2; exit 1; }
tmp="$P.shipyard.$$"
trap 'rm -f "$tmp"' EXIT
awk -v op="$op" -v id="$id" -v ver="$ver" '
  inlist && skip { skip = 0; next }
  inlist && index($0, "<key>" id "</key>") { skip = 1; next }
  inlist && /<\/dict>/ { inlist = 0 }
  { print }
  want && /<dict>/ {
    want = 0; inlist = 1; found = 1
    if (op == "add") { print "\t\t<key>" id "</key>"; print "\t\t<string>" ver "</string>" }
  }
  /<key>OSKextSigExceptionList<\/key>/ { want = 1 }
  END { if (!found) exit 3 }
' "$P" > "$tmp" || { echo "kext_sig_exception: $P has no OSKextSigExceptionList; left alone" >&2; exit 1; }
# platform: Apple's file is 644 root:wheel; the installer runs this as root, so the new file is root's too
chmod 644 "$tmp"
mv -f "$tmp" "$P"
trap - EXIT
