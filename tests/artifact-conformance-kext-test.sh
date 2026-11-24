#!/bin/sh
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot" --
#       check-artifact-conformance.sh's kext-sig-exception and kext-exclude-list checks, on fact streams
set -eu
unset GITHUB_REPOSITORY
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-artifact-conformance.sh"
ok() {
  out="$(printf '%s\nend-of-facts\n' "$2" | sh "$S" 2>&1)" || { echo "FAIL $1: expected pass, got: $out"; exit 1; }
}
no() {
  out="$(printf '%s\nend-of-facts\n' "$3" | sh "$S" 2>&1)" && { echo "FAIL $1: expected failure"; exit 1; }
  printf '%s\n' "$out" | grep -qi "$2" || { echo "FAIL $1: should mention '$2', got: $out"; exit 1; }
}
GOOD='expected 1.0-mavericks.1
pkg p.pkg 1.0-mavericks.1 10.9.5 dev.mavergreen.p
asset p.pkg 4096'
K='kext p.pkg Library/Extensions/Boot.kext dev.mavergreen.p.boot'
E='kext-exception p.pkg dev.mavergreen.p.boot'

ok "a pkg with no kext" "$GOOD"
no "a boot kext in Library/Extensions with no exception" "kext-sig-exception: p.pkg installs Library/Extensions/Boot.kext (dev.mavergreen.p.boot)" "$GOOD
$K boot"
ok "a boot kext listed through --boot-kext" "$GOOD
$K boot
$E"
ok "a library kext loads only as a dependency" "$GOOD
kext p.pkg Library/Extensions/KPI.kext dev.mavergreen.p.kpi library"
ok "a kext nested in another bundle is not judged by its place" "$GOOD
kext p.pkg Library/Extensions/Boot.kext/Contents/PlugIns/Inner.kext dev.mavergreen.p.inner boot
kext p.pkg Library/Extensions/Boot.kext dev.mavergreen.p.boot boot
$E"
ok "a kext outside Library/Extensions may be listed" "$GOOD
kext p.pkg Library/Filesystems/macfuse.fs/Contents/Extensions/10.9/macfuse.kext io.macfuse.filesystems.macfuse boot
kext-exception p.pkg io.macfuse.filesystems.macfuse"
no "the exception is per pkg" "kext-sig-exception" "$GOOD
pkg q.pkg 1.0-mavericks.1 10.9.5 dev.mavergreen.q
$K boot
kext-exception q.pkg dev.mavergreen.p.boot"
ok "a declared deviation excuses its kext" "$GOOD
deviation kext-sig-exception:dev.mavergreen.p.boot loaded only with kext-dev-mode=1, which its README requires
$K boot"
no "and only that kext" "kext-sig-exception: p.pkg installs Library/Extensions/Other.kext" "$GOOD
deviation kext-sig-exception:dev.mavergreen.p.boot loaded only with kext-dev-mode=1, which its README requires
$K boot
kext p.pkg Library/Extensions/Other.kext dev.mavergreen.p.other boot"
no "a deviation with no reason excuses nothing" "kext-sig-exception" "$GOOD
deviation kext-sig-exception
$K boot"
no "listing an id the pkg ships no kext for" "lists dev.mavergreen.p.ghost in OSKextSigExceptionList but installs no kext" "$GOOD
kext-exception p.pkg dev.mavergreen.p.ghost"
no "a hand-written exclude-list edit" "kext-exclude-list: p.pkg's postinstall edits AppleKextExcludeList" "$GOOD
$K boot
$E
excludelist-script p.pkg postinstall"
no "no deviation excuses a hand-written edit" "kext-exclude-list" "$GOOD
deviation kext-exclude-list we really mean it
excludelist-script p.pkg preinstall"
echo "artifact-conformance-kext OK"
