#!/bin/sh
# platform: host-agnostic
#   usage: updater-plist-test.sh
#          The updater's plist templates render to well-formed XML -- the RENDERED plist is what ships
#          (configure_file(@ONLY) fills in every @VAR@ first; the raw .in file, with bare @VAR@ tokens,
#          is never what a strict reader sees). Render each template by substituting @MAVERICKS_AUTO_CHECK@
#          with a real boolean and every other @VAR@ with a plain token, then parse the result.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: no python3"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/updater-plist-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
for t in Info.plist.in updatecheck.plist.in; do
  sed -e 's/@MAVERICKS_AUTO_CHECK@/true/g' -e 's/@[A-Z_][A-Z_]*@/x/g' "$here/../updater/$t" > "$w/$t"
  python3 -c 'import plistlib, sys; plistlib.load(open(sys.argv[1], "rb"))' "$w/$t" \
    || { echo "FAIL: updater/$t does not render to a well-formed plist -- no \"--\" inside an XML comment"; exit 1; }
done
echo "PASS: updater-plist"
