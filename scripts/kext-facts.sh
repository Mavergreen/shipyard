#!/bin/sh
# platform: host-agnostic -- stevedore reads each kext's Info.plist
#   usage: kext-facts.sh PKG [--root DIR] [--scripts DIR]...
#          Emits artifact-facts.sh's kext records for one pkg, read from what it ships:
#            kext <pkg> <path> <CFBundleIdentifier> boot|library   one per kext a payload installed at "/"
#                                                                   (DIR) carries, %20-encoded; library when
#                                                                   it declares OSBundleCompatibleVersion and
#                                                                   no IOKitPersonalities, so it loads only as
#                                                                   another kext's dependency
#            kext-exception <pkg> <id>                             one per id stage_product.sh --boot-kext's
#                                                                   generated postinstall lists
#            excludelist-script <pkg> <script>                     a pre/postinstall that names
#                                                                   AppleKextExcludeList or
#                                                                   OSKextSigExceptionList other than through
#                                                                   that generated block
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot"
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
pkg="${1:?kext-facts: pkg name required}"; shift
roots=""; scripts=""
nl='
'
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "kext-facts: --root needs a value" >&2; exit 2; }; roots="$roots$2$nl"; shift 2 ;;
    --scripts) [ $# -ge 2 ] || { echo "kext-facts: --scripts needs a value" >&2; exit 2; }; scripts="$scripts$2$nl"; shift 2 ;;
    *) echo "kext-facts: unknown option $1" >&2; exit 2 ;;
  esac
done
enc() { sed -e 's/%/%25/g' -e 's/ /%20/g'; }
_ifs="$IFS"; IFS="$nl"
for r in $roots; do
  IFS="$_ifs"
  [ -n "$r" ] || continue
  if [ -z "${STEVEDORE:-}" ]; then STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"; export STEVEDORE; fi
  ( cd "$r" && find . -type d -name '*.kext' ) | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r k; do
    ip="$r/$k/Contents/Info.plist"
    [ -f "$ip" ] || ip="$r/$k/Info.plist"
    id="$("$STEVEDORE" plist get "$ip" CFBundleIdentifier 2>/dev/null || echo none)"
    how=boot
    if "$STEVEDORE" plist has "$ip" OSBundleCompatibleVersion 2>/dev/null \
      && ! "$STEVEDORE" plist has "$ip" IOKitPersonalities 2>/dev/null; then how=library; fi
    printf 'kext %s %s %s %s\n' "$pkg" "$(printf '%s' "$k" | enc)" "$(printf '%s' "${id:-none}" | tr -s '[:space:]' '_')" "$how"
  done
  IFS="$nl"
done
for d in $scripts; do
  IFS="$_ifs"
  [ -n "$d" ] || continue
  for s in preinstall postinstall; do
    [ -f "$d/$s" ] || continue
    awk -v pkg="$pkg" -v s="$s" '
      s == "postinstall" && !done && !inb && /^_kx="\$ROOT\/usr\/local\/mavergreen\/[a-z0-9-]+\/libexec\/mavergreen\/kext-sig-exception"$/ { inb = 1; next }
      inb && $0 == "unset _kx _kl _kv _kx_added" { inb = 0; done = 1; next }
      inb && $0 == "_kl=\"$ROOT/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist\"" { next }
      inb && /^  if \[ -n "\$_kv" \] && sh "\$_kx" add "\$_kl" [A-Za-z0-9._-]+ "\$_kv"; then / { split($0, f, " "); print "kext-exception", pkg, f[11]; next }
      /AppleKextExcludeList|OSKextSigExceptionList/ { touched = 1 }
      END { if (touched) print "excludelist-script", pkg, s }' "$d/$s"
  done
  IFS="$nl"
done
IFS="$_ifs"
exit 0
